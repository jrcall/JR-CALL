// ============================================================================
// JR CALL
// File: voice_message.dart
// Location: lib/features/message/media/voice_message.dart
// Description:
// Recorded voice-message lifecycle/model preparation for JR CALL Message Engine.
//
// Owns:
// - Voice recording lifecycle abstraction.
// - Recording state.
// - Duration tracking.
// - Recording cancellation.
// - Safe recorder cleanup.
// - Completed local voice attachment preparation.
// - MIME/size/duration validation before upload.
//
// Important:
// This file intentionally does NOT introduce a new recording package.
// The actual microphone/recorder implementation must be supplied through
// [VoiceRecorderAdapter] using an existing JR CALL/project recording capability
// or a separately approved dependency.
//
// Does NOT own:
// - Firebase Storage upload.
// - Firestore writes.
// - Message creation.
// - Audio playback UI.
// - Call Engine / WebRTC.
// ============================================================================

import 'dart:async';
import 'dart:io';

import '../data/attachment_entity.dart';

/// Voice-recording lifecycle state.
enum VoiceRecordingState {
  idle,
  starting,
  recording,
  stopping,
  completed,
  cancelling,
  cancelled,
  failed,
  disposed,
}

/// Immutable low-level result returned by the configured recorder adapter.
final class VoiceRecorderResult {
  VoiceRecorderResult({
    required String filePath,
    required this.duration,
    required String mimeType,
  }) : filePath = _requireValue(filePath, 'filePath'),
       mimeType = _requireValue(mimeType, 'mimeType').toLowerCase() {
    if (duration <= Duration.zero) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Recorded voice duration must be greater than zero.',
      );
    }
  }

  final String filePath;
  final Duration duration;
  final String mimeType;

  static String _requireValue(String value, String fieldName) {
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
}

/// Recorder integration boundary.
///
/// JR CALL Message Engine deliberately avoids binding FILE 26 to a recording
/// plugin that may not exist in the current package stack.
///
/// Implement this adapter with the project's approved recording mechanism.
///
/// Contract:
/// - [start] acquires microphone/recorder resources.
/// - [stop] finishes recording and releases active recording resources.
/// - [cancel] aborts recording and releases resources.
/// - [dispose] permanently releases adapter-owned resources.
///
/// Implementations must be idempotent where practical.
abstract interface class VoiceRecorderAdapter {
  Future<void> start();

  Future<VoiceRecorderResult> stop();

  Future<void> cancel();

  Future<void> dispose();
}

/// Completed local voice recording ready for media upload coordination.
final class PreparedVoiceMessage {
  const PreparedVoiceMessage({required this.file, required this.attachment});

  final File file;
  final AttachmentEntity attachment;
}

/// Production voice-message lifecycle coordinator.
final class VoiceMessage {
  /// Public production constructor.
  ///
  /// Keeps the frozen public API:
  ///
  /// VoiceMessage(recorder: recorder)
  ///
  /// while the private constructor uses an initializing formal so
  /// `prefer_initializing_formals` remains analyzer-clean.
  factory VoiceMessage({required VoiceRecorderAdapter recorder}) {
    return VoiceMessage._(recorder);
  }

  VoiceMessage._(this._recorder);

  static const int maxVoiceBytes = 25 * 1024 * 1024;

  static const Duration maxVoiceDuration = Duration(minutes: 30);

  static const Duration minimumVoiceDuration = Duration(milliseconds: 300);

  static const Set<String> supportedMimeTypes = <String>{
    'audio/aac',
    'audio/x-aac',
    'audio/mp4',
    'audio/x-m4a',
    'audio/m4a',
    'audio/mpeg',
    'audio/mp3',
    'audio/ogg',
    'audio/opus',
    'audio/webm',
    'audio/wav',
    'audio/x-wav',
    'audio/3gpp',
    'audio/amr',
  };

  final VoiceRecorderAdapter _recorder;

  final StreamController<VoiceRecordingState> _stateController =
      StreamController<VoiceRecordingState>.broadcast(sync: true);

  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast(sync: true);

  VoiceRecordingState _state = VoiceRecordingState.idle;

  Timer? _durationTimer;
  DateTime? _recordingStartedAt;
  Duration _duration = Duration.zero;

  int _operationGeneration = 0;

  bool _isDisposed = false;
  bool _operationActive = false;

  // --------------------------------------------------------------------------
  // PUBLIC STATE
  // --------------------------------------------------------------------------

  VoiceRecordingState get state => _state;

  Duration get duration => _duration;

  bool get isRecording => _state == VoiceRecordingState.recording;

  bool get isBusy =>
      _state == VoiceRecordingState.starting ||
      _state == VoiceRecordingState.stopping ||
      _state == VoiceRecordingState.cancelling;

  bool get isDisposed => _isDisposed;

  Stream<VoiceRecordingState> get states => _stateController.stream;

  Stream<Duration> get durations => _durationController.stream;

  // --------------------------------------------------------------------------
  // RECORDING LIFECYCLE
  // --------------------------------------------------------------------------

  /// Begins a new voice recording.
  Future<void> start() async {
    _ensureUsable();

    if (_operationActive) {
      throw const VoiceMessageException(
        code: VoiceMessageErrorCode.operationInProgress,
        message: 'Another voice recording operation is already in progress.',
      );
    }

    if (_state == VoiceRecordingState.recording) {
      return;
    }

    if (_state == VoiceRecordingState.starting ||
        _state == VoiceRecordingState.stopping ||
        _state == VoiceRecordingState.cancelling) {
      throw const VoiceMessageException(
        code: VoiceMessageErrorCode.invalidState,
        message: 'Voice recording cannot start in the current state.',
      );
    }

    final int generation = ++_operationGeneration;
    _operationActive = true;

    _resetDuration();
    _setState(VoiceRecordingState.starting);

    try {
      await _recorder.start();

      if (!_isCurrentOperation(generation)) {
        await _safeCancelRecorder();
        return;
      }

      _recordingStartedAt = DateTime.now().toUtc();
      _startDurationTicker(generation);

      _setState(VoiceRecordingState.recording);
    } catch (error, stackTrace) {
      if (_isCurrentOperation(generation)) {
        _stopDurationTicker();
        _recordingStartedAt = null;
        _setState(VoiceRecordingState.failed);
      }

      await _safeCancelRecorder();

      throw VoiceMessageException(
        code: VoiceMessageErrorCode.recorderStartFailed,
        message: 'Voice recording could not be started.',
        cause: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (_isCurrentOperation(generation)) {
        _operationActive = false;
      }
    }
  }

  /// Stops recording and prepares the resulting local file as a voice
  /// attachment.
  Future<PreparedVoiceMessage> stop({
    required String attachmentId,
    required String messageId,
    required String conversationId,
    required String ownerUid,
    DateTime? createdAt,
  }) async {
    _ensureUsable();

    if (_operationActive) {
      throw const VoiceMessageException(
        code: VoiceMessageErrorCode.operationInProgress,
        message: 'Another voice recording operation is already in progress.',
      );
    }

    if (_state != VoiceRecordingState.recording) {
      throw const VoiceMessageException(
        code: VoiceMessageErrorCode.notRecording,
        message: 'There is no active voice recording to stop.',
      );
    }

    final String normalizedAttachmentId = _normalizeRequired(
      attachmentId,
      fieldName: 'attachmentId',
    );

    final String normalizedMessageId = _normalizeRequired(
      messageId,
      fieldName: 'messageId',
    );

    final String normalizedConversationId = _normalizeRequired(
      conversationId,
      fieldName: 'conversationId',
    );

    final String normalizedOwnerUid = _normalizeRequired(
      ownerUid,
      fieldName: 'ownerUid',
    );

    final int generation = ++_operationGeneration;
    _operationActive = true;

    _stopDurationTicker();
    _updateDurationFromClock();

    _setState(VoiceRecordingState.stopping);

    try {
      final VoiceRecorderResult result = await _recorder.stop();

      if (!_isCurrentOperation(generation)) {
        throw const VoiceMessageException(
          code: VoiceMessageErrorCode.cancelled,
          message: 'Voice recording operation was cancelled.',
        );
      }

      final PreparedVoiceMessage prepared = await prepareCompletedRecording(
        attachmentId: normalizedAttachmentId,
        messageId: normalizedMessageId,
        conversationId: normalizedConversationId,
        ownerUid: normalizedOwnerUid,
        file: File(result.filePath),
        mimeType: result.mimeType,
        duration: result.duration,
        createdAt: createdAt,
      );

      _duration = result.duration;
      _emitDuration();

      _recordingStartedAt = null;
      _setState(VoiceRecordingState.completed);

      return prepared;
    } on VoiceMessageException {
      if (_isCurrentOperation(generation)) {
        _recordingStartedAt = null;
        _setState(VoiceRecordingState.failed);
      }

      rethrow;
    } catch (error, stackTrace) {
      if (_isCurrentOperation(generation)) {
        _recordingStartedAt = null;
        _setState(VoiceRecordingState.failed);
      }

      throw VoiceMessageException(
        code: VoiceMessageErrorCode.recorderStopFailed,
        message: 'Voice recording could not be completed.',
        cause: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (_isCurrentOperation(generation)) {
        _operationActive = false;
      }
    }
  }

  /// Cancels an active or starting recording.
  ///
  /// Recorder resources are explicitly released through the adapter.
  Future<void> cancel() async {
    if (_isDisposed) {
      return;
    }

    if (_state == VoiceRecordingState.idle ||
        _state == VoiceRecordingState.cancelled ||
        _state == VoiceRecordingState.completed ||
        _state == VoiceRecordingState.failed) {
      _resetDuration();
      return;
    }

    ++_operationGeneration;
    _operationActive = true;

    _stopDurationTicker();
    _recordingStartedAt = null;

    _setState(VoiceRecordingState.cancelling);

    try {
      await _recorder.cancel();

      if (_isDisposed) {
        return;
      }

      _resetDuration();
      _setState(VoiceRecordingState.cancelled);
    } catch (error, stackTrace) {
      if (!_isDisposed) {
        _setState(VoiceRecordingState.failed);
      }

      throw VoiceMessageException(
        code: VoiceMessageErrorCode.recorderCancelFailed,
        message: 'Voice recording could not be cancelled cleanly.',
        cause: error,
        stackTrace: stackTrace,
      );
    } finally {
      _operationActive = false;
    }
  }

  /// Resets completed/cancelled/failed state for another recording session.
  void reset() {
    _ensureUsable();

    if (_state == VoiceRecordingState.recording ||
        _state == VoiceRecordingState.starting ||
        _state == VoiceRecordingState.stopping ||
        _state == VoiceRecordingState.cancelling) {
      throw const VoiceMessageException(
        code: VoiceMessageErrorCode.invalidState,
        message: 'An active voice recording must be cancelled before reset.',
      );
    }

    ++_operationGeneration;
    _stopDurationTicker();
    _recordingStartedAt = null;
    _resetDuration();
    _setState(VoiceRecordingState.idle);
  }

  // --------------------------------------------------------------------------
  // COMPLETED RECORDING PREPARATION
  // --------------------------------------------------------------------------

  /// Validates and prepares an already-completed recorder output.
  ///
  /// This may also be used by an approved recording layer that manages its own
  /// lifecycle but needs JR CALL's canonical voice attachment validation.
  static Future<PreparedVoiceMessage> prepareCompletedRecording({
    required String attachmentId,
    required String messageId,
    required String conversationId,
    required String ownerUid,
    required File file,
    required String mimeType,
    required Duration duration,
    DateTime? createdAt,
  }) async {
    final String normalizedAttachmentId = _normalizeRequired(
      attachmentId,
      fieldName: 'attachmentId',
    );

    final String normalizedMessageId = _normalizeRequired(
      messageId,
      fieldName: 'messageId',
    );

    final String normalizedConversationId = _normalizeRequired(
      conversationId,
      fieldName: 'conversationId',
    );

    final String normalizedOwnerUid = _normalizeRequired(
      ownerUid,
      fieldName: 'ownerUid',
    );

    final String normalizedMimeType = _normalizeMimeType(mimeType);

    validateMimeType(normalizedMimeType);
    validateDuration(duration);

    final FileStat stat = await _readFileStat(file);
    final int byteSize = validateByteSize(stat.size);

    final String fileName = _safeFileName(
      file.path,
      mimeType: normalizedMimeType,
    );

    final AttachmentEntity attachment = AttachmentEntity(
      id: normalizedAttachmentId,
      messageId: normalizedMessageId,
      conversationId: normalizedConversationId,
      ownerUid: normalizedOwnerUid,
      type: AttachmentType.voice,
      fileName: fileName,
      mimeType: normalizedMimeType,
      byteSize: byteSize,
      storagePath: '',
      downloadUrl: '',
      uploadState: AttachmentUploadState.pending,
      duration: duration,
      createdAt: (createdAt ?? DateTime.now()).toUtc(),
    );

    return PreparedVoiceMessage(file: file, attachment: attachment);
  }

  /// Returns whether the MIME type is accepted for recorded voice messages.
  static bool supportsMimeType(String mimeType) {
    return supportedMimeTypes.contains(mimeType.trim().toLowerCase());
  }

  static void validateMimeType(String mimeType) {
    final String normalized = mimeType.trim().toLowerCase();

    if (normalized.isEmpty) {
      throw const VoiceMessageException(
        code: VoiceMessageErrorCode.invalidMetadata,
        message: 'Voice recording MIME type must not be empty.',
      );
    }

    if (!supportedMimeTypes.contains(normalized)) {
      throw const VoiceMessageException(
        code: VoiceMessageErrorCode.unsupportedMimeType,
        message: 'This voice recording format is not supported.',
      );
    }
  }

  static void validateDuration(Duration duration) {
    if (duration < minimumVoiceDuration) {
      throw const VoiceMessageException(
        code: VoiceMessageErrorCode.recordingTooShort,
        message: 'The voice recording is too short.',
      );
    }

    if (duration > maxVoiceDuration) {
      throw const VoiceMessageException(
        code: VoiceMessageErrorCode.recordingTooLong,
        message: 'The voice recording exceeds the allowed duration.',
      );
    }
  }

  static int validateByteSize(int byteSize) {
    if (byteSize <= 0) {
      throw const VoiceMessageException(
        code: VoiceMessageErrorCode.emptyFile,
        message: 'The recorded voice file is empty.',
      );
    }

    if (byteSize > maxVoiceBytes) {
      throw const VoiceMessageException(
        code: VoiceMessageErrorCode.fileTooLarge,
        message: 'The recorded voice file exceeds the allowed size.',
      );
    }

    return byteSize;
  }

  // --------------------------------------------------------------------------
  // DURATION
  // --------------------------------------------------------------------------

  void _startDurationTicker(int generation) {
    _stopDurationTicker();

    _durationTimer = Timer.periodic(const Duration(milliseconds: 250), (
      Timer timer,
    ) {
      if (!_isCurrentOperation(generation) &&
          _state != VoiceRecordingState.recording) {
        timer.cancel();
        return;
      }

      if (_isDisposed || _state != VoiceRecordingState.recording) {
        timer.cancel();
        return;
      }

      _updateDurationFromClock();

      if (_duration >= maxVoiceDuration) {
        _duration = maxVoiceDuration;
        _emitDuration();
        timer.cancel();
      }
    });
  }

  void _stopDurationTicker() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  void _updateDurationFromClock() {
    final DateTime? startedAt = _recordingStartedAt;

    if (startedAt == null) {
      return;
    }

    Duration elapsed = DateTime.now().toUtc().difference(startedAt);

    if (elapsed.isNegative) {
      elapsed = Duration.zero;
    }

    if (elapsed > maxVoiceDuration) {
      elapsed = maxVoiceDuration;
    }

    if (elapsed != _duration) {
      _duration = elapsed;
      _emitDuration();
    }
  }

  void _resetDuration() {
    _duration = Duration.zero;
    _emitDuration();
  }

  void _emitDuration() {
    if (_isDisposed || _durationController.isClosed) {
      return;
    }

    _durationController.add(_duration);
  }

  // --------------------------------------------------------------------------
  // INTERNAL HELPERS
  // --------------------------------------------------------------------------

  void _setState(VoiceRecordingState next) {
    if (_isDisposed && next != VoiceRecordingState.disposed) {
      return;
    }

    if (_state == next) {
      return;
    }

    _state = next;

    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  bool _isCurrentOperation(int generation) {
    return !_isDisposed && generation == _operationGeneration;
  }

  void _ensureUsable() {
    if (_isDisposed) {
      throw StateError('VoiceMessage has already been disposed.');
    }
  }

  static Future<FileStat> _readFileStat(File file) async {
    final FileStat stat;

    try {
      stat = await file.stat();
    } on FileSystemException catch (error, stackTrace) {
      throw VoiceMessageException(
        code: VoiceMessageErrorCode.fileUnavailable,
        message: 'The recorded voice file could not be accessed.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (stat.type != FileSystemEntityType.file) {
      throw const VoiceMessageException(
        code: VoiceMessageErrorCode.fileUnavailable,
        message: 'The recorded voice output is not a valid local file.',
      );
    }

    return stat;
  }

  static String _normalizeRequired(String value, {required String fieldName}) {
    final String normalized = value.trim();

    if (normalized.isEmpty) {
      throw VoiceMessageException(
        code: VoiceMessageErrorCode.invalidMetadata,
        message: '$fieldName must not be empty.',
      );
    }

    return normalized;
  }

  static String _normalizeMimeType(String value) {
    final String normalized = value.trim().toLowerCase();

    if (normalized.isEmpty) {
      throw const VoiceMessageException(
        code: VoiceMessageErrorCode.invalidMetadata,
        message: 'Voice recording MIME type must not be empty.',
      );
    }

    return normalized;
  }

  static String _safeFileName(String path, {required String mimeType}) {
    String rawName = path.replaceAll('\\', '/').split('/').last.trim();

    rawName = rawName
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    while (rawName.startsWith('.')) {
      rawName = rawName.substring(1);
    }

    if (rawName.isEmpty) {
      return 'voice.${_extensionForMimeType(mimeType)}';
    }

    const int maxFileNameLength = 120;

    if (rawName.length <= maxFileNameLength) {
      return rawName;
    }

    final int dotIndex = rawName.lastIndexOf('.');

    if (dotIndex <= 0 || dotIndex == rawName.length - 1) {
      return rawName.substring(0, maxFileNameLength);
    }

    final String extension = rawName.substring(dotIndex);
    final int allowedBaseLength = maxFileNameLength - extension.length;

    if (allowedBaseLength <= 0) {
      return 'voice.${_extensionForMimeType(mimeType)}';
    }

    return '${rawName.substring(0, allowedBaseLength)}$extension';
  }

  static String _extensionForMimeType(String mimeType) {
    switch (mimeType) {
      case 'audio/aac':
      case 'audio/x-aac':
        return 'aac';

      case 'audio/mp4':
      case 'audio/x-m4a':
      case 'audio/m4a':
        return 'm4a';

      case 'audio/mpeg':
      case 'audio/mp3':
        return 'mp3';

      case 'audio/ogg':
        return 'ogg';

      case 'audio/opus':
        return 'opus';

      case 'audio/webm':
        return 'webm';

      case 'audio/wav':
      case 'audio/x-wav':
        return 'wav';

      case 'audio/3gpp':
        return '3gp';

      case 'audio/amr':
        return 'amr';
    }

    return 'audio';
  }

  Future<void> _safeCancelRecorder() async {
    try {
      await _recorder.cancel();
    } catch (_) {
      // Emergency best-effort cleanup only.
      // The originating recorder failure remains the primary error.
    }
  }

  // --------------------------------------------------------------------------
  // DISPOSAL
  // --------------------------------------------------------------------------

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    ++_operationGeneration;

    _stopDurationTicker();
    _recordingStartedAt = null;
    _operationActive = false;

    final bool mayHoldRecorderResources =
        _state == VoiceRecordingState.starting ||
        _state == VoiceRecordingState.recording ||
        _state == VoiceRecordingState.stopping ||
        _state == VoiceRecordingState.cancelling;

    if (mayHoldRecorderResources) {
      await _safeCancelRecorder();
    }

    _isDisposed = true;
    _state = VoiceRecordingState.disposed;

    if (!_stateController.isClosed) {
      _stateController.add(VoiceRecordingState.disposed);
    }

    Object? disposeError;
    StackTrace? disposeStackTrace;

    try {
      await _recorder.dispose();
    } catch (error, stackTrace) {
      disposeError = error;
      disposeStackTrace = stackTrace;
    }

    await _stateController.close();
    await _durationController.close();

    if (disposeError != null) {
      throw VoiceMessageException(
        code: VoiceMessageErrorCode.recorderDisposeFailed,
        message: 'Voice recorder resources could not be released cleanly.',
        cause: disposeError,
        stackTrace: disposeStackTrace,
      );
    }
  }
}

/// Stable voice-message preparation/lifecycle error categories.
enum VoiceMessageErrorCode {
  invalidState,
  operationInProgress,
  notRecording,
  cancelled,
  invalidMetadata,
  unsupportedMimeType,
  recorderStartFailed,
  recorderStopFailed,
  recorderCancelFailed,
  recorderDisposeFailed,
  recordingTooShort,
  recordingTooLong,
  fileUnavailable,
  emptyFile,
  fileTooLarge,
}

/// Safe normalized voice-message exception.
///
/// Raw recorder/filesystem exceptions remain available through [cause] for
/// internal diagnostics but must not be blindly shown in user-facing UI.
final class VoiceMessageException implements Exception {
  const VoiceMessageException({
    required this.code,
    required this.message,
    this.cause,
    this.stackTrace,
  });

  final VoiceMessageErrorCode code;
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() {
    return 'VoiceMessageException('
        'code: ${code.name}, '
        'message: $message'
        ')';
  }
}

// ============================================================================
// END OF FILE: lib/features/message/media/voice_message.dart
// ============================================================================
