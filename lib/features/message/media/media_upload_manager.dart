// ============================================================================
// JR CALL
// File: media_upload_manager.dart
// Location: lib/features/message/media/media_upload_manager.dart
// Description:
// Production attachment-upload orchestration for JR CALL Message Engine.
//
// Owns:
// - Active upload registry.
// - Stable attachment/message identity validation.
// - Upload lifecycle state.
// - Immutable upload progress snapshots.
// - Cancellation.
// - Retry coordination.
// - Stale upload/generation protection.
// - Durable-send handoff after Storage upload completes.
// - Safe normalized upload errors.
//
// Does NOT own:
// - Raw Firebase Storage implementation.
// - Firestore message persistence.
// - File picker UI.
// - Attachment-specific file preparation.
// - Durable-message retry engine.
// - Call Engine / WebRTC.
//
// Raw Firebase Storage access remains exclusively inside
// message_media_store.dart.
// ============================================================================

import 'dart:async';
import 'dart:io';

import '../data/attachment_entity.dart';
import '../storage/message_media_store.dart';

/// Lifecycle state owned by [MediaUploadManager].
///
/// This is orchestration state and intentionally does not replace the
/// canonical attachment upload-state definition in `attachment_entity.dart`.
enum MediaUploadState {
  queued,
  validating,
  uploading,
  completing,
  completed,
  failed,
  cancelled,
}

/// Stable media-upload error categories.
enum MediaUploadErrorCode {
  invalidRequest,
  duplicateUpload,
  fileUnavailable,
  cancelled,
  storage,
  completion,
  stale,
  disposed,
  unknown,
}

/// Safe normalized upload exception.
///
/// Raw backend/filesystem exceptions remain available in [cause] only for
/// internal diagnostics. Presentation code must not blindly display them.
final class MediaUploadException implements Exception {
  const MediaUploadException({
    required this.code,
    required this.message,
    this.attachmentId,
    this.messageId,
    this.conversationId,
    this.cause,
    this.stackTrace,
  });

  final MediaUploadErrorCode code;
  final String message;

  final String? attachmentId;
  final String? messageId;
  final String? conversationId;

  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() {
    return 'MediaUploadException('
        'code: ${code.name}, '
        'message: $message'
        ')';
  }
}

/// Immutable upload request.
///
/// Attachment-specific preparation belongs to FILE 23-27. Those preparation
/// layers produce the local file plus canonical [AttachmentEntity], which are
/// then wrapped here for upload orchestration.
final class MediaUploadRequest {
  MediaUploadRequest({required this.file, required this.attachment}) {
    _validateIdentity();
  }

  final File file;
  final AttachmentEntity attachment;

  String get attachmentId => attachment.id.trim();

  String get messageId => attachment.messageId.trim();

  String get conversationId => attachment.conversationId.trim();

  String get ownerUid => attachment.ownerUid.trim();

  void _validateIdentity() {
    if (attachmentId.isEmpty) {
      throw const MediaUploadException(
        code: MediaUploadErrorCode.invalidRequest,
        message: 'Attachment ID must not be empty.',
      );
    }

    if (messageId.isEmpty) {
      throw MediaUploadException(
        code: MediaUploadErrorCode.invalidRequest,
        message: 'Message ID must not be empty.',
        attachmentId: attachmentId,
      );
    }

    if (conversationId.isEmpty) {
      throw MediaUploadException(
        code: MediaUploadErrorCode.invalidRequest,
        message: 'Conversation ID must not be empty.',
        attachmentId: attachmentId,
        messageId: messageId,
      );
    }

    if (ownerUid.isEmpty) {
      throw MediaUploadException(
        code: MediaUploadErrorCode.invalidRequest,
        message: 'Attachment owner UID must not be empty.',
        attachmentId: attachmentId,
        messageId: messageId,
        conversationId: conversationId,
      );
    }
  }
}

/// Immutable upload progress/lifecycle snapshot.
final class MediaUploadSnapshot {
  const MediaUploadSnapshot({
    required this.attachmentId,
    required this.messageId,
    required this.conversationId,
    required this.state,
    required this.progress,
    required this.attempt,
    required this.generation,
    required this.updatedAt,
    this.attachment,
    this.error,
  });

  final String attachmentId;
  final String messageId;
  final String conversationId;

  final MediaUploadState state;

  /// Normalized range: `0.0 <= progress <= 1.0`.
  final double progress;

  /// One-based upload attempt count.
  final int attempt;

  /// Per-attachment generation used to reject stale callbacks.
  final int generation;

  final DateTime updatedAt;

  /// Completed/final attachment metadata when available.
  final AttachmentEntity? attachment;

  final MediaUploadException? error;

  bool get isActive {
    return switch (state) {
      MediaUploadState.queued ||
      MediaUploadState.validating ||
      MediaUploadState.uploading ||
      MediaUploadState.completing => true,
      MediaUploadState.completed ||
      MediaUploadState.failed ||
      MediaUploadState.cancelled => false,
    };
  }

  bool get isCompleted => state == MediaUploadState.completed;

  bool get isFailed => state == MediaUploadState.failed;

  bool get isCancelled => state == MediaUploadState.cancelled;

  MediaUploadSnapshot copyWith({
    MediaUploadState? state,
    double? progress,
    int? attempt,
    int? generation,
    DateTime? updatedAt,
    AttachmentEntity? attachment,
    MediaUploadException? error,
    bool clearAttachment = false,
    bool clearError = false,
  }) {
    return MediaUploadSnapshot(
      attachmentId: attachmentId,
      messageId: messageId,
      conversationId: conversationId,
      state: state ?? this.state,
      progress: progress ?? this.progress,
      attempt: attempt ?? this.attempt,
      generation: generation ?? this.generation,
      updatedAt: updatedAt ?? this.updatedAt,
      attachment: clearAttachment ? null : (attachment ?? this.attachment),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Cancellation token visible to the typed Storage adapter.
///
/// FILE 16 remains the raw Storage owner. Its concrete upload implementation
/// may observe this token and cancel its native Storage task when supported.
final class MediaUploadCancellationToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }

  void throwIfCancelled({
    required String attachmentId,
    required String messageId,
    required String conversationId,
  }) {
    if (!_isCancelled) {
      return;
    }

    throw MediaUploadException(
      code: MediaUploadErrorCode.cancelled,
      message: 'The attachment upload was cancelled.',
      attachmentId: attachmentId,
      messageId: messageId,
      conversationId: conversationId,
    );
  }
}

/// Progress callback supplied to the Storage adapter.
typedef MediaUploadProgressCallback = void Function(double progress);

/// Typed adapter that connects this orchestrator to FILE 16.
///
/// The adapter receives the existing [MessageMediaStore] instance so all raw
/// Firebase Storage operations remain owned by FILE 16.
///
/// It must return the final canonical [AttachmentEntity] containing completed
/// Storage metadata such as `storagePath` and `downloadUrl`.
typedef MessageMediaUploadExecutor =
    Future<AttachmentEntity> Function({
      required MessageMediaStore mediaStore,
      required MediaUploadRequest request,
      required MediaUploadProgressCallback onProgress,
      required MediaUploadCancellationToken cancellationToken,
    });

/// Optional durable-send handoff.
///
/// This is invoked only after Storage upload succeeds. Durable message
/// persistence remains owned by Message Sender/Repository, not this class.
typedef MediaUploadCompletionHandler =
    Future<void> Function(AttachmentEntity attachment);

/// Optional request validator.
///
/// Attachment-specific validation normally already happened in FILE 23-27.
/// This hook allows FILE 31 / repository policy to repeat central validation
/// immediately before Storage upload.
typedef MediaUploadRequestValidator =
    FutureOr<void> Function(MediaUploadRequest request);

/// Production attachment upload orchestrator.
///
/// Important architecture:
///
/// prepared attachment
///   -> validate
///   -> register stable upload generation
///   -> FILE 16 Storage execution
///   -> progress
///   -> completed AttachmentEntity
///   -> durable-send handoff
///
/// A stable attachment ID identifies one logical upload. Retrying keeps that
/// same ID so Storage/message identity is not duplicated.
final class MediaUploadManager {
  factory MediaUploadManager({
    required MessageMediaStore mediaStore,
    required MessageMediaUploadExecutor uploadExecutor,
    MediaUploadCompletionHandler? completionHandler,
    MediaUploadRequestValidator? validator,
    int maxAttempts = 3,
  }) {
    if (maxAttempts < 1) {
      throw ArgumentError.value(
        maxAttempts,
        'maxAttempts',
        'maxAttempts must be at least 1.',
      );
    }

    return MediaUploadManager._(
      mediaStore,
      uploadExecutor,
      completionHandler,
      validator,
      maxAttempts,
    );
  }

  MediaUploadManager._(
    this._mediaStore,
    this._uploadExecutor,
    this._completionHandler,
    this._validator,
    this._maxAttempts,
  );

  final MessageMediaStore _mediaStore;
  final MessageMediaUploadExecutor _uploadExecutor;
  final MediaUploadCompletionHandler? _completionHandler;
  final MediaUploadRequestValidator? _validator;
  final int _maxAttempts;

  final Map<String, _ActiveMediaUpload> _active =
      <String, _ActiveMediaUpload>{};

  final Map<String, MediaUploadRequest> _requests =
      <String, MediaUploadRequest>{};

  final Map<String, MediaUploadSnapshot> _latest =
      <String, MediaUploadSnapshot>{};

  final StreamController<MediaUploadSnapshot> _snapshotController =
      StreamController<MediaUploadSnapshot>.broadcast(sync: true);

  final StreamController<MediaUploadException> _errorController =
      StreamController<MediaUploadException>.broadcast(sync: true);

  bool _isDisposed = false;

  int _managerGeneration = 0;

  // --------------------------------------------------------------------------
  // PUBLIC STATE
  // --------------------------------------------------------------------------

  bool get isDisposed => _isDisposed;

  int get activeUploadCount => _active.length;

  int get maxAttempts => _maxAttempts;

  bool get hasActiveUploads => _active.isNotEmpty;

  Stream<MediaUploadSnapshot> get snapshots => _snapshotController.stream;

  Stream<MediaUploadException> get errors => _errorController.stream;

  /// Immutable latest known upload snapshots.
  List<MediaUploadSnapshot> get currentSnapshots {
    final List<MediaUploadSnapshot> result = List<MediaUploadSnapshot>.of(
      _latest.values,
    );

    result.sort((MediaUploadSnapshot first, MediaUploadSnapshot second) {
      final int timeComparison = first.updatedAt.compareTo(second.updatedAt);

      if (timeComparison != 0) {
        return timeComparison;
      }

      return first.attachmentId.compareTo(second.attachmentId);
    });

    return List<MediaUploadSnapshot>.unmodifiable(result);
  }

  MediaUploadSnapshot? snapshotFor(String attachmentId) {
    final String normalizedId = _normalizeId(
      attachmentId,
      fieldName: 'attachmentId',
    );

    return _latest[normalizedId];
  }

  bool isUploading(String attachmentId) {
    final String normalizedId = _normalizeId(
      attachmentId,
      fieldName: 'attachmentId',
    );

    return _active.containsKey(normalizedId);
  }

  // --------------------------------------------------------------------------
  // UPLOAD
  // --------------------------------------------------------------------------

  /// Starts a new upload.
  ///
  /// Duplicate rapid taps using the same canonical attachment ID cannot create
  /// concurrent duplicate uploads.
  Future<AttachmentEntity> upload(MediaUploadRequest request) async {
    _ensureNotDisposed();

    final String attachmentId = request.attachmentId;

    if (_active.containsKey(attachmentId)) {
      throw MediaUploadException(
        code: MediaUploadErrorCode.duplicateUpload,
        message: 'This attachment is already being uploaded.',
        attachmentId: attachmentId,
        messageId: request.messageId,
        conversationId: request.conversationId,
      );
    }

    final MediaUploadSnapshot? previous = _latest[attachmentId];

    if (previous?.isCompleted == true && previous?.attachment != null) {
      return previous!.attachment!;
    }

    _requests[attachmentId] = request;

    final int nextAttempt = (previous?.attempt ?? 0) + 1;

    if (nextAttempt > _maxAttempts) {
      final MediaUploadException error = MediaUploadException(
        code: MediaUploadErrorCode.storage,
        message: 'The attachment upload reached the retry limit.',
        attachmentId: attachmentId,
        messageId: request.messageId,
        conversationId: request.conversationId,
      );

      _emitFailure(
        request: request,
        attempt: previous?.attempt ?? _maxAttempts,
        generation: previous?.generation ?? 0,
        error: error,
      );

      throw error;
    }

    return _runUpload(request, attempt: nextAttempt);
  }

  /// Retries a failed/cancelled upload using the same canonical attachment ID.
  ///
  /// The same request/message/attachment identity is preserved.
  Future<AttachmentEntity> retry(String attachmentId) async {
    _ensureNotDisposed();

    final String normalizedId = _normalizeId(
      attachmentId,
      fieldName: 'attachmentId',
    );

    if (_active.containsKey(normalizedId)) {
      throw MediaUploadException(
        code: MediaUploadErrorCode.duplicateUpload,
        message: 'This attachment is already being uploaded.',
        attachmentId: normalizedId,
      );
    }

    final MediaUploadRequest? request = _requests[normalizedId];

    if (request == null) {
      throw MediaUploadException(
        code: MediaUploadErrorCode.invalidRequest,
        message: 'No upload request exists for this attachment.',
        attachmentId: normalizedId,
      );
    }

    final MediaUploadSnapshot? previous = _latest[normalizedId];

    if (previous?.isCompleted == true && previous?.attachment != null) {
      return previous!.attachment!;
    }

    final int nextAttempt = (previous?.attempt ?? 0) + 1;

    if (nextAttempt > _maxAttempts) {
      final MediaUploadException error = MediaUploadException(
        code: MediaUploadErrorCode.storage,
        message: 'The attachment upload reached the retry limit.',
        attachmentId: normalizedId,
        messageId: request.messageId,
        conversationId: request.conversationId,
      );

      _emitFailure(
        request: request,
        attempt: previous?.attempt ?? _maxAttempts,
        generation: previous?.generation ?? 0,
        error: error,
      );

      throw error;
    }

    return _runUpload(request, attempt: nextAttempt);
  }

  Future<AttachmentEntity> _runUpload(
    MediaUploadRequest request, {
    required int attempt,
  }) async {
    _ensureNotDisposed();

    final String attachmentId = request.attachmentId;

    final int managerGeneration = _managerGeneration;
    final int uploadGeneration = (_latest[attachmentId]?.generation ?? 0) + 1;

    final MediaUploadCancellationToken cancellationToken =
        MediaUploadCancellationToken();

    final Completer<AttachmentEntity> completer = Completer<AttachmentEntity>();

    final _ActiveMediaUpload activeUpload = _ActiveMediaUpload(
      request: request,
      cancellationToken: cancellationToken,
      generation: uploadGeneration,
      managerGeneration: managerGeneration,
      attempt: attempt,
      completer: completer,
    );

    _active[attachmentId] = activeUpload;

    _emit(
      MediaUploadSnapshot(
        attachmentId: attachmentId,
        messageId: request.messageId,
        conversationId: request.conversationId,
        state: MediaUploadState.queued,
        progress: 0,
        attempt: attempt,
        generation: uploadGeneration,
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    unawaited(_execute(activeUpload));

    return completer.future;
  }

  Future<void> _execute(_ActiveMediaUpload activeUpload) async {
    final MediaUploadRequest request = activeUpload.request;

    try {
      if (!_isCurrent(activeUpload)) {
        return;
      }

      _emitForActive(
        activeUpload,
        state: MediaUploadState.validating,
        progress: 0,
      );

      await _validateRequest(request);

      activeUpload.cancellationToken.throwIfCancelled(
        attachmentId: request.attachmentId,
        messageId: request.messageId,
        conversationId: request.conversationId,
      );

      if (!_isCurrent(activeUpload)) {
        return;
      }

      _emitForActive(
        activeUpload,
        state: MediaUploadState.uploading,
        progress: 0,
      );

      final AttachmentEntity uploadedAttachment = await _uploadExecutor(
        mediaStore: _mediaStore,
        request: request,
        cancellationToken: activeUpload.cancellationToken,
        onProgress: (double progress) {
          _onProgress(activeUpload, progress);
        },
      );

      activeUpload.cancellationToken.throwIfCancelled(
        attachmentId: request.attachmentId,
        messageId: request.messageId,
        conversationId: request.conversationId,
      );

      if (!_isCurrent(activeUpload)) {
        return;
      }

      _validateCompletedAttachment(
        original: request.attachment,
        completed: uploadedAttachment,
      );

      _emitForActive(
        activeUpload,
        state: MediaUploadState.completing,
        progress: 1,
        attachment: uploadedAttachment,
      );

      final MediaUploadCompletionHandler? completionHandler =
          _completionHandler;

      if (completionHandler != null) {
        try {
          await completionHandler(uploadedAttachment);
        } catch (error, stackTrace) {
          throw MediaUploadException(
            code: MediaUploadErrorCode.completion,
            message: 'The attachment uploaded but message completion failed.',
            attachmentId: request.attachmentId,
            messageId: request.messageId,
            conversationId: request.conversationId,
            cause: error,
            stackTrace: stackTrace,
          );
        }
      }

      if (!_isCurrent(activeUpload)) {
        return;
      }

      _active.remove(request.attachmentId);

      final MediaUploadSnapshot completedSnapshot = MediaUploadSnapshot(
        attachmentId: request.attachmentId,
        messageId: request.messageId,
        conversationId: request.conversationId,
        state: MediaUploadState.completed,
        progress: 1,
        attempt: activeUpload.attempt,
        generation: activeUpload.generation,
        updatedAt: DateTime.now().toUtc(),
        attachment: uploadedAttachment,
      );

      _emit(completedSnapshot);

      if (!activeUpload.completer.isCompleted) {
        activeUpload.completer.complete(uploadedAttachment);
      }
    } catch (error, stackTrace) {
      _handleExecutionError(activeUpload, error, stackTrace);
    }
  }

  // --------------------------------------------------------------------------
  // PROGRESS
  // --------------------------------------------------------------------------

  void _onProgress(_ActiveMediaUpload activeUpload, double rawProgress) {
    if (!_isCurrent(activeUpload) ||
        activeUpload.cancellationToken.isCancelled) {
      return;
    }

    final double progress = _normalizeProgress(rawProgress);

    final MediaUploadSnapshot? previous =
        _latest[activeUpload.request.attachmentId];

    if (previous != null &&
        previous.generation == activeUpload.generation &&
        progress < previous.progress) {
      return;
    }

    _emitForActive(
      activeUpload,
      state: MediaUploadState.uploading,
      progress: progress,
    );
  }

  static double _normalizeProgress(double progress) {
    if (!progress.isFinite) {
      return 0;
    }

    if (progress <= 0) {
      return 0;
    }

    if (progress >= 1) {
      return 1;
    }

    return progress;
  }

  // --------------------------------------------------------------------------
  // CANCELLATION
  // --------------------------------------------------------------------------

  /// Cancels one active upload.
  ///
  /// FILE 16's executor should observe [MediaUploadCancellationToken] and
  /// cancel its native Storage task where supported.
  Future<bool> cancel(String attachmentId) async {
    if (_isDisposed) {
      return false;
    }

    final String normalizedId = _normalizeId(
      attachmentId,
      fieldName: 'attachmentId',
    );

    final _ActiveMediaUpload? activeUpload = _active.remove(normalizedId);

    if (activeUpload == null) {
      return false;
    }

    activeUpload.cancellationToken.cancel();

    final MediaUploadRequest request = activeUpload.request;

    final MediaUploadException error = MediaUploadException(
      code: MediaUploadErrorCode.cancelled,
      message: 'The attachment upload was cancelled.',
      attachmentId: request.attachmentId,
      messageId: request.messageId,
      conversationId: request.conversationId,
    );

    _emit(
      MediaUploadSnapshot(
        attachmentId: request.attachmentId,
        messageId: request.messageId,
        conversationId: request.conversationId,
        state: MediaUploadState.cancelled,
        progress: _latest[request.attachmentId]?.progress ?? 0,
        attempt: activeUpload.attempt,
        generation: activeUpload.generation,
        updatedAt: DateTime.now().toUtc(),
        error: error,
      ),
    );

    if (!activeUpload.completer.isCompleted) {
      activeUpload.completer.completeError(error);
    }

    return true;
  }

  /// Cancels all currently active uploads.
  Future<void> cancelAll() async {
    if (_isDisposed) {
      return;
    }

    final List<String> attachmentIds = List<String>.of(_active.keys);

    for (final String attachmentId in attachmentIds) {
      await cancel(attachmentId);
    }
  }

  // --------------------------------------------------------------------------
  // CACHE / REGISTRY
  // --------------------------------------------------------------------------

  /// Removes completed/failed/cancelled orchestration history.
  ///
  /// Active uploads are never removed by this method.
  void clearFinished() {
    _ensureNotDisposed();

    final List<String> removable = <String>[];

    for (final MapEntry<String, MediaUploadSnapshot> entry in _latest.entries) {
      if (!_active.containsKey(entry.key) && !entry.value.isActive) {
        removable.add(entry.key);
      }
    }

    for (final String attachmentId in removable) {
      _latest.remove(attachmentId);
      _requests.remove(attachmentId);
    }
  }

  /// Removes one non-active upload from local orchestration history.
  bool removeFinished(String attachmentId) {
    _ensureNotDisposed();

    final String normalizedId = _normalizeId(
      attachmentId,
      fieldName: 'attachmentId',
    );

    if (_active.containsKey(normalizedId)) {
      return false;
    }

    final bool existed = _latest.remove(normalizedId) != null;
    _requests.remove(normalizedId);

    return existed;
  }

  // --------------------------------------------------------------------------
  // VALIDATION
  // --------------------------------------------------------------------------

  Future<void> _validateRequest(MediaUploadRequest request) async {
    request._validateIdentity();

    FileStat stat;

    try {
      stat = await request.file.stat();
    } on FileSystemException catch (error, stackTrace) {
      throw MediaUploadException(
        code: MediaUploadErrorCode.fileUnavailable,
        message: 'The selected attachment could not be accessed.',
        attachmentId: request.attachmentId,
        messageId: request.messageId,
        conversationId: request.conversationId,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
      throw MediaUploadException(
        code: MediaUploadErrorCode.fileUnavailable,
        message: 'The selected attachment is not a valid local file.',
        attachmentId: request.attachmentId,
        messageId: request.messageId,
        conversationId: request.conversationId,
      );
    }

    if (request.attachment.byteSize <= 0) {
      throw MediaUploadException(
        code: MediaUploadErrorCode.invalidRequest,
        message: 'Attachment byte size is invalid.',
        attachmentId: request.attachmentId,
        messageId: request.messageId,
        conversationId: request.conversationId,
      );
    }

    if (stat.size != request.attachment.byteSize) {
      throw MediaUploadException(
        code: MediaUploadErrorCode.invalidRequest,
        message: 'Attachment metadata no longer matches the local file.',
        attachmentId: request.attachmentId,
        messageId: request.messageId,
        conversationId: request.conversationId,
      );
    }

    if (request.attachment.fileName.trim().isEmpty ||
        request.attachment.mimeType.trim().isEmpty) {
      throw MediaUploadException(
        code: MediaUploadErrorCode.invalidRequest,
        message: 'Attachment metadata is incomplete.',
        attachmentId: request.attachmentId,
        messageId: request.messageId,
        conversationId: request.conversationId,
      );
    }

    final MediaUploadRequestValidator? validator = _validator;

    if (validator != null) {
      await validator(request);
    }
  }

  static void _validateCompletedAttachment({
    required AttachmentEntity original,
    required AttachmentEntity completed,
  }) {
    if (completed.id.trim() != original.id.trim() ||
        completed.messageId.trim() != original.messageId.trim() ||
        completed.conversationId.trim() != original.conversationId.trim() ||
        completed.ownerUid.trim() != original.ownerUid.trim()) {
      throw MediaUploadException(
        code: MediaUploadErrorCode.storage,
        message: 'Uploaded attachment identity changed unexpectedly.',
        attachmentId: original.id,
        messageId: original.messageId,
        conversationId: original.conversationId,
      );
    }

    // storagePath is non-null in the finalized AttachmentEntity contract.
    // Therefore no unnecessary null-aware operator is used here.
    final String completedStoragePath = completed.storagePath.trim();

    // downloadUrl remains nullable until Storage upload completion.
    final String completedDownloadUrl = completed.downloadUrl?.trim() ?? '';

    if (completedStoragePath.isEmpty || completedDownloadUrl.isEmpty) {
      throw MediaUploadException(
        code: MediaUploadErrorCode.storage,
        message: 'Uploaded attachment metadata is incomplete.',
        attachmentId: original.id,
        messageId: original.messageId,
        conversationId: original.conversationId,
      );
    }
  }

  // --------------------------------------------------------------------------
  // ERROR HANDLING
  // --------------------------------------------------------------------------

  void _handleExecutionError(
    _ActiveMediaUpload activeUpload,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!_isCurrent(activeUpload)) {
      return;
    }

    _active.remove(activeUpload.request.attachmentId);

    final MediaUploadException normalizedError = _normalizeError(
      error,
      stackTrace: stackTrace,
      request: activeUpload.request,
    );

    final MediaUploadState state =
        normalizedError.code == MediaUploadErrorCode.cancelled
        ? MediaUploadState.cancelled
        : MediaUploadState.failed;

    final MediaUploadSnapshot previous =
        _latest[activeUpload.request.attachmentId] ??
        MediaUploadSnapshot(
          attachmentId: activeUpload.request.attachmentId,
          messageId: activeUpload.request.messageId,
          conversationId: activeUpload.request.conversationId,
          state: state,
          progress: 0,
          attempt: activeUpload.attempt,
          generation: activeUpload.generation,
          updatedAt: DateTime.now().toUtc(),
        );

    _emit(
      previous.copyWith(
        state: state,
        attempt: activeUpload.attempt,
        generation: activeUpload.generation,
        updatedAt: DateTime.now().toUtc(),
        error: normalizedError,
      ),
    );

    if (!_errorController.isClosed &&
        normalizedError.code != MediaUploadErrorCode.cancelled) {
      _errorController.add(normalizedError);
    }

    if (!activeUpload.completer.isCompleted) {
      activeUpload.completer.completeError(
        normalizedError,
        normalizedError.stackTrace ?? stackTrace,
      );
    }
  }

  MediaUploadException _normalizeError(
    Object error, {
    required StackTrace stackTrace,
    required MediaUploadRequest request,
  }) {
    if (error is MediaUploadException) {
      return error;
    }

    return MediaUploadException(
      code: MediaUploadErrorCode.storage,
      message: 'The attachment could not be uploaded.',
      attachmentId: request.attachmentId,
      messageId: request.messageId,
      conversationId: request.conversationId,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  void _emitFailure({
    required MediaUploadRequest request,
    required int attempt,
    required int generation,
    required MediaUploadException error,
  }) {
    _emit(
      MediaUploadSnapshot(
        attachmentId: request.attachmentId,
        messageId: request.messageId,
        conversationId: request.conversationId,
        state: MediaUploadState.failed,
        progress: _latest[request.attachmentId]?.progress ?? 0,
        attempt: attempt,
        generation: generation,
        updatedAt: DateTime.now().toUtc(),
        error: error,
      ),
    );

    if (!_errorController.isClosed) {
      _errorController.add(error);
    }
  }

  // --------------------------------------------------------------------------
  // SNAPSHOT EMISSION
  // --------------------------------------------------------------------------

  void _emitForActive(
    _ActiveMediaUpload activeUpload, {
    required MediaUploadState state,
    required double progress,
    AttachmentEntity? attachment,
  }) {
    if (!_isCurrent(activeUpload)) {
      return;
    }

    _emit(
      MediaUploadSnapshot(
        attachmentId: activeUpload.request.attachmentId,
        messageId: activeUpload.request.messageId,
        conversationId: activeUpload.request.conversationId,
        state: state,
        progress: _normalizeProgress(progress),
        attempt: activeUpload.attempt,
        generation: activeUpload.generation,
        updatedAt: DateTime.now().toUtc(),
        attachment: attachment,
      ),
    );
  }

  void _emit(MediaUploadSnapshot snapshot) {
    if (_isDisposed) {
      return;
    }

    final MediaUploadSnapshot? previous = _latest[snapshot.attachmentId];

    if (previous != null && snapshot.generation < previous.generation) {
      return;
    }

    _latest[snapshot.attachmentId] = snapshot;

    if (!_snapshotController.isClosed) {
      _snapshotController.add(snapshot);
    }
  }

  bool _isCurrent(_ActiveMediaUpload activeUpload) {
    if (_isDisposed || activeUpload.managerGeneration != _managerGeneration) {
      return false;
    }

    final _ActiveMediaUpload? current =
        _active[activeUpload.request.attachmentId];

    return identical(current, activeUpload) &&
        current?.generation == activeUpload.generation;
  }

  // --------------------------------------------------------------------------
  // INTERNAL HELPERS
  // --------------------------------------------------------------------------

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw const MediaUploadException(
        code: MediaUploadErrorCode.disposed,
        message: 'MediaUploadManager has already been disposed.',
      );
    }
  }

  static String _normalizeId(String value, {required String fieldName}) {
    final String normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(
        value,
        fieldName,
        '$fieldName must not be empty.',
      );
    }

    return normalized;
  }

  // --------------------------------------------------------------------------
  // DISPOSAL
  // --------------------------------------------------------------------------

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    ++_managerGeneration;

    _isDisposed = true;

    final List<_ActiveMediaUpload> activeUploads = List<_ActiveMediaUpload>.of(
      _active.values,
    );

    _active.clear();

    for (final _ActiveMediaUpload activeUpload in activeUploads) {
      activeUpload.cancellationToken.cancel();

      if (!activeUpload.completer.isCompleted) {
        final MediaUploadException error = MediaUploadException(
          code: MediaUploadErrorCode.cancelled,
          message: 'The attachment upload was cancelled during disposal.',
          attachmentId: activeUpload.request.attachmentId,
          messageId: activeUpload.request.messageId,
          conversationId: activeUpload.request.conversationId,
        );

        activeUpload.completer.completeError(error);
      }
    }

    _requests.clear();
    _latest.clear();

    await _snapshotController.close();
    await _errorController.close();
  }
}

final class _ActiveMediaUpload {
  const _ActiveMediaUpload({
    required this.request,
    required this.cancellationToken,
    required this.generation,
    required this.managerGeneration,
    required this.attempt,
    required this.completer,
  });

  final MediaUploadRequest request;
  final MediaUploadCancellationToken cancellationToken;

  final int generation;
  final int managerGeneration;
  final int attempt;

  final Completer<AttachmentEntity> completer;
}

// ============================================================================
// END OF FILE: lib/features/message/media/media_upload_manager.dart
// ============================================================================
