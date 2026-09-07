// ============================================================================
// JR CALL
// File: message_media_store.dart
// Location: lib/features/message/storage/message_media_store.dart
// Description:
// Sole Firebase Storage owner for JR CALL Message Engine media.
//
// Owns:
// - Deterministic message-media Storage references.
// - File/data uploads.
// - Upload progress.
// - Pause / resume / cancel.
// - Download URL resolution.
// - Storage metadata.
// - Sender-owned attachment deletion.
// - Firebase Storage error normalization.
//
// Does NOT own:
// - Firestore message creation.
// - Conversation summary writes.
// - Message UI.
// - Call Engine / WebRTC.
// - Attachment selection/preparation policy.
// ============================================================================

import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// High-level Storage error categories exposed by MessageMediaStore.
enum MessageMediaErrorCategory {
  authentication,
  permission,
  network,
  storage,
  quota,
  notFound,
  conflict,
  cancelled,
  validation,
  temporary,
  unknown,
}

/// Safe normalized Message Engine media exception.
///
/// [message] is suitable for higher application layers.
/// [debugCode] preserves a non-secret diagnostic code without exposing
/// arbitrary Firebase exception text to the UI.
final class MessageMediaStoreException implements Exception {
  const MessageMediaStoreException({
    required this.category,
    required this.message,
    this.debugCode,
  });

  final MessageMediaErrorCategory category;
  final String message;
  final String? debugCode;

  @override
  String toString() {
    final String code = debugCode == null ? '' : ' [$debugCode]';
    return 'MessageMediaStoreException$code: $message';
  }
}

/// Normalized Firebase Storage upload state.
enum MessageMediaUploadState { running, paused, success, cancelled, failed }

/// Immutable upload-progress snapshot.
final class MessageMediaUploadProgress {
  const MessageMediaUploadProgress({
    required this.state,
    required this.bytesTransferred,
    required this.totalBytes,
  });

  final MessageMediaUploadState state;
  final int bytesTransferred;
  final int totalBytes;

  double get progress {
    if (totalBytes <= 0) {
      return 0;
    }

    final double value = bytesTransferred / totalBytes;

    if (value < 0) {
      return 0;
    }

    if (value > 1) {
      return 1;
    }

    return value;
  }

  bool get isComplete => state == MessageMediaUploadState.success;

  bool get isCancelled => state == MessageMediaUploadState.cancelled;

  bool get isFailed => state == MessageMediaUploadState.failed;
}

/// Immutable normalized Storage object metadata.
final class MessageMediaMetadata {
  const MessageMediaMetadata({
    required this.storagePath,
    required this.bucket,
    required this.byteSize,
    required this.contentType,
    required this.ownerUid,
    required this.conversationId,
    required this.messageId,
    required this.attachmentId,
    required this.originalFileName,
    required this.createdAt,
    required this.updatedAt,
  });

  final String storagePath;
  final String bucket;
  final int byteSize;
  final String? contentType;

  final String ownerUid;
  final String conversationId;
  final String messageId;
  final String attachmentId;
  final String originalFileName;

  final DateTime? createdAt;
  final DateTime? updatedAt;
}

/// Successful uploaded-media result.
final class MessageMediaUploadResult {
  const MessageMediaUploadResult({
    required this.storagePath,
    required this.downloadUrl,
    required this.byteSize,
    required this.contentType,
    required this.ownerUid,
    required this.conversationId,
    required this.messageId,
    required this.attachmentId,
    required this.originalFileName,
    required this.metadata,
  });

  final String storagePath;
  final String downloadUrl;
  final int byteSize;
  final String? contentType;

  final String ownerUid;
  final String conversationId;
  final String messageId;
  final String attachmentId;
  final String originalFileName;

  final MessageMediaMetadata metadata;
}

typedef _UploadResultResolver =
    Future<MessageMediaUploadResult> Function(UploadTask task);

typedef _StorageExceptionNormalizer =
    MessageMediaStoreException Function(Object error);

/// One active Firebase Storage upload.
///
/// This wrapper does not create a second upload implementation.
/// It directly controls the underlying Firebase [UploadTask].
final class MessageMediaUploadHandle {
  MessageMediaUploadHandle._({
    required this._task,
    required this._resultResolver,
    required this._normalizeError,
  });

  final UploadTask _task;
  final _UploadResultResolver _resultResolver;
  final _StorageExceptionNormalizer _normalizeError;

  UploadTask get firebaseTask => _task;

  Stream<MessageMediaUploadProgress> get progressStream {
    return _task.snapshotEvents.map((TaskSnapshot snapshot) {
      return MessageMediaUploadProgress(
        state: _mapTaskState(snapshot.state),
        bytesTransferred: snapshot.bytesTransferred,
        totalBytes: snapshot.totalBytes,
      );
    });
  }

  Future<MessageMediaUploadResult> get result {
    return _resultResolver(_task);
  }

  Future<bool> pause() async {
    try {
      return await _task.pause();
    } catch (error) {
      throw _normalizeError(error);
    }
  }

  Future<bool> resume() async {
    try {
      return await _task.resume();
    } catch (error) {
      throw _normalizeError(error);
    }
  }

  Future<bool> cancel() async {
    try {
      return await _task.cancel();
    } catch (error) {
      throw _normalizeError(error);
    }
  }

  static MessageMediaUploadState _mapTaskState(TaskState state) {
    switch (state) {
      case TaskState.running:
        return MessageMediaUploadState.running;

      case TaskState.paused:
        return MessageMediaUploadState.paused;

      case TaskState.success:
        return MessageMediaUploadState.success;

      case TaskState.canceled:
        return MessageMediaUploadState.cancelled;

      case TaskState.error:
        return MessageMediaUploadState.failed;
    }
  }
}

/// Sole Firebase Storage access layer for JR CALL Message Engine.
final class MessageMediaStore {
  MessageMediaStore({FirebaseStorage? storage, FirebaseAuth? auth})
    : _storage = storage ?? FirebaseStorage.instance,
      _auth = auth ?? FirebaseAuth.instance;

  static const String rootFolder = 'message_media';

  static const String _ownerUidMetadataKey = 'ownerUid';
  static const String _conversationIdMetadataKey = 'conversationId';
  static const String _messageIdMetadataKey = 'messageId';
  static const String _attachmentIdMetadataKey = 'attachmentId';
  static const String _originalFileNameMetadataKey = 'originalFileName';

  final FirebaseStorage _storage;
  final FirebaseAuth _auth;

  // --------------------------------------------------------------------------
  // STORAGE PATH
  // --------------------------------------------------------------------------

  /// Builds the canonical JR CALL Message Storage path.
  ///
  /// message_media/
  ///   {conversationId}/
  ///     {messageId}/
  ///       {attachmentId}/
  ///         filename
  static String buildStoragePath({
    required String conversationId,
    required String messageId,
    required String attachmentId,
    required String fileName,
  }) {
    final String conversation = _normalizePathSegment(
      conversationId,
      fieldName: 'conversationId',
    );

    final String message = _normalizePathSegment(
      messageId,
      fieldName: 'messageId',
    );

    final String attachment = _normalizePathSegment(
      attachmentId,
      fieldName: 'attachmentId',
    );

    final String normalizedFileName = normalizeFileName(fileName);

    return '$rootFolder/'
        '$conversation/'
        '$message/'
        '$attachment/'
        '$normalizedFileName';
  }

  /// Produces a safe Storage filename while retaining a useful original name.
  static String normalizeFileName(String fileName) {
    String value = fileName.trim();

    if (value.isEmpty) {
      throw ArgumentError.value(
        fileName,
        'fileName',
        'File name must not be empty.',
      );
    }

    value = value
        .replaceAll(RegExp(r'[/\\]'), '_')
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    while (value.startsWith('.')) {
      value = value.substring(1);
    }

    if (value.isEmpty || value == '.' || value == '..') {
      throw ArgumentError.value(fileName, 'fileName', 'File name is invalid.');
    }

    const int maxLength = 180;

    if (value.length <= maxLength) {
      return value;
    }

    final int extensionIndex = value.lastIndexOf('.');

    if (extensionIndex <= 0 ||
        extensionIndex >= value.length - 1 ||
        value.length - extensionIndex > 20) {
      return value.substring(0, maxLength);
    }

    final String extension = value.substring(extensionIndex);
    final int baseLength = maxLength - extension.length;

    return '${value.substring(0, baseLength)}$extension';
  }

  Reference referenceFor({
    required String conversationId,
    required String messageId,
    required String attachmentId,
    required String fileName,
  }) {
    return _storage.ref(
      buildStoragePath(
        conversationId: conversationId,
        messageId: messageId,
        attachmentId: attachmentId,
        fileName: fileName,
      ),
    );
  }

  Reference referenceFromStoragePath(String storagePath) {
    final String path = _normalizeOwnedStoragePath(storagePath);
    return _storage.ref(path);
  }

  // --------------------------------------------------------------------------
  // FILE UPLOAD
  // --------------------------------------------------------------------------

  /// Starts a file-based upload.
  ///
  /// File/type/size product validation belongs to the preparation/security
  /// layers. This Storage boundary still enforces authentication, identity,
  /// path safety, file existence, non-empty file size and MIME metadata.
  Future<MessageMediaUploadHandle> uploadFile({
    required String ownerUid,
    required String conversationId,
    required String messageId,
    required String attachmentId,
    required String fileName,
    required String mimeType,
    required File file,
    Map<String, String>? customMetadata,
  }) async {
    final String owner = _requireAuthenticatedOwner(ownerUid);

    final String conversation = _normalizePathSegment(
      conversationId,
      fieldName: 'conversationId',
    );

    final String message = _normalizePathSegment(
      messageId,
      fieldName: 'messageId',
    );

    final String attachment = _normalizePathSegment(
      attachmentId,
      fieldName: 'attachmentId',
    );

    final String originalName = _normalizeOriginalFileName(fileName);
    final String normalizedFileName = normalizeFileName(originalName);
    final String contentType = _normalizeMimeType(mimeType);

    try {
      if (!await file.exists()) {
        throw const MessageMediaStoreException(
          category: MessageMediaErrorCategory.notFound,
          message: 'The selected attachment file could not be found.',
          debugCode: 'local-file-not-found',
        );
      }

      final int byteSize = await file.length();

      if (byteSize <= 0) {
        throw const MessageMediaStoreException(
          category: MessageMediaErrorCategory.validation,
          message: 'The selected attachment is empty.',
          debugCode: 'empty-file',
        );
      }

      final String storagePath = buildStoragePath(
        conversationId: conversation,
        messageId: message,
        attachmentId: attachment,
        fileName: normalizedFileName,
      );

      final Reference reference = _storage.ref(storagePath);

      final SettableMetadata metadata = SettableMetadata(
        contentType: contentType,
        customMetadata: _buildMetadata(
          ownerUid: owner,
          conversationId: conversation,
          messageId: message,
          attachmentId: attachment,
          originalFileName: originalName,
          additionalMetadata: customMetadata,
        ),
      );

      final UploadTask task = reference.putFile(file, metadata);

      return _createHandle(task);
    } on MessageMediaStoreException {
      rethrow;
    } catch (error) {
      throw _normalizeError(error);
    }
  }

  // --------------------------------------------------------------------------
  // BYTE DATA UPLOAD
  // --------------------------------------------------------------------------

  /// Starts a byte-data upload.
  ///
  /// Intended for already-bounded in-memory media. Large files should use
  /// [uploadFile] so callers do not need to load the complete file into memory.
  Future<MessageMediaUploadHandle> uploadData({
    required String ownerUid,
    required String conversationId,
    required String messageId,
    required String attachmentId,
    required String fileName,
    required String mimeType,
    required Uint8List data,
    Map<String, String>? customMetadata,
  }) async {
    final String owner = _requireAuthenticatedOwner(ownerUid);

    final String conversation = _normalizePathSegment(
      conversationId,
      fieldName: 'conversationId',
    );

    final String message = _normalizePathSegment(
      messageId,
      fieldName: 'messageId',
    );

    final String attachment = _normalizePathSegment(
      attachmentId,
      fieldName: 'attachmentId',
    );

    final String originalName = _normalizeOriginalFileName(fileName);
    final String normalizedFileName = normalizeFileName(originalName);
    final String contentType = _normalizeMimeType(mimeType);

    if (data.isEmpty) {
      throw const MessageMediaStoreException(
        category: MessageMediaErrorCategory.validation,
        message: 'The selected attachment is empty.',
        debugCode: 'empty-data',
      );
    }

    try {
      final String storagePath = buildStoragePath(
        conversationId: conversation,
        messageId: message,
        attachmentId: attachment,
        fileName: normalizedFileName,
      );

      final Reference reference = _storage.ref(storagePath);

      final SettableMetadata metadata = SettableMetadata(
        contentType: contentType,
        customMetadata: _buildMetadata(
          ownerUid: owner,
          conversationId: conversation,
          messageId: message,
          attachmentId: attachment,
          originalFileName: originalName,
          additionalMetadata: customMetadata,
        ),
      );

      final UploadTask task = reference.putData(data, metadata);

      return _createHandle(task);
    } on MessageMediaStoreException {
      rethrow;
    } catch (error) {
      throw _normalizeError(error);
    }
  }

  // --------------------------------------------------------------------------
  // DOWNLOAD URL
  // --------------------------------------------------------------------------

  Future<String> getDownloadUrl({
    required String ownerUid,
    required String storagePath,
  }) async {
    final String owner = _requireAuthenticatedOwner(ownerUid);
    final Reference reference = referenceFromStoragePath(storagePath);

    try {
      final FullMetadata metadata = await reference.getMetadata();

      _verifyOwnedMetadata(metadata: metadata, expectedOwnerUid: owner);

      return await reference.getDownloadURL();
    } on MessageMediaStoreException {
      rethrow;
    } catch (error) {
      throw _normalizeError(error);
    }
  }

  // --------------------------------------------------------------------------
  // METADATA
  // --------------------------------------------------------------------------

  Future<MessageMediaMetadata> getMetadata({
    required String ownerUid,
    required String storagePath,
  }) async {
    final String owner = _requireAuthenticatedOwner(ownerUid);
    final Reference reference = referenceFromStoragePath(storagePath);

    try {
      final FullMetadata metadata = await reference.getMetadata();

      _verifyOwnedMetadata(metadata: metadata, expectedOwnerUid: owner);

      return _metadataFromFirebase(reference: reference, metadata: metadata);
    } on MessageMediaStoreException {
      rethrow;
    } catch (error) {
      throw _normalizeError(error);
    }
  }

  // --------------------------------------------------------------------------
  // DELETE
  // --------------------------------------------------------------------------

  /// Deletes only media whose stored owner metadata matches [ownerUid].
  ///
  /// Firebase Storage Security Rules remain the final server authority.
  Future<void> deleteOwnedAttachment({
    required String ownerUid,
    required String storagePath,
    String? expectedConversationId,
    String? expectedMessageId,
    String? expectedAttachmentId,
  }) async {
    final String owner = _requireAuthenticatedOwner(ownerUid);
    final Reference reference = referenceFromStoragePath(storagePath);

    try {
      final FullMetadata metadata = await reference.getMetadata();

      _verifyOwnedMetadata(
        metadata: metadata,
        expectedOwnerUid: owner,
        expectedConversationId: expectedConversationId,
        expectedMessageId: expectedMessageId,
        expectedAttachmentId: expectedAttachmentId,
      );

      await reference.delete();
    } on MessageMediaStoreException {
      rethrow;
    } catch (error) {
      throw _normalizeError(error);
    }
  }

  // --------------------------------------------------------------------------
  // UPLOAD COMPLETION
  // --------------------------------------------------------------------------

  MessageMediaUploadHandle _createHandle(UploadTask task) {
    return MessageMediaUploadHandle._(
      task: task,
      resultResolver: _resolveUploadResult,
      normalizeError: _normalizeError,
    );
  }

  Future<MessageMediaUploadResult> _resolveUploadResult(UploadTask task) async {
    try {
      final TaskSnapshot snapshot = await task;

      if (snapshot.state != TaskState.success) {
        throw const MessageMediaStoreException(
          category: MessageMediaErrorCategory.storage,
          message: 'The attachment upload did not complete successfully.',
          debugCode: 'upload-not-successful',
        );
      }

      final Reference reference = snapshot.ref;
      final FullMetadata metadata = await reference.getMetadata();

      final Map<String, String> custom =
          metadata.customMetadata ?? const <String, String>{};

      final String ownerUid = _requiredCustomMetadata(
        custom,
        _ownerUidMetadataKey,
      );

      final String conversationId = _requiredCustomMetadata(
        custom,
        _conversationIdMetadataKey,
      );

      final String messageId = _requiredCustomMetadata(
        custom,
        _messageIdMetadataKey,
      );

      final String attachmentId = _requiredCustomMetadata(
        custom,
        _attachmentIdMetadataKey,
      );

      final String originalFileName = _requiredCustomMetadata(
        custom,
        _originalFileNameMetadataKey,
      );

      final int byteSize = _requiredMetadataSize(metadata);

      final String downloadUrl = await reference.getDownloadURL();

      final MessageMediaMetadata normalizedMetadata = _metadataFromFirebase(
        reference: reference,
        metadata: metadata,
      );

      return MessageMediaUploadResult(
        storagePath: reference.fullPath,
        downloadUrl: downloadUrl,
        byteSize: byteSize,
        contentType: metadata.contentType,
        ownerUid: ownerUid,
        conversationId: conversationId,
        messageId: messageId,
        attachmentId: attachmentId,
        originalFileName: originalFileName,
        metadata: normalizedMetadata,
      );
    } on MessageMediaStoreException {
      rethrow;
    } catch (error) {
      throw _normalizeError(error);
    }
  }

  // --------------------------------------------------------------------------
  // AUTHENTICATION / OWNERSHIP
  // --------------------------------------------------------------------------

  String _requireAuthenticatedOwner(String requestedOwnerUid) {
    final String ownerUid = _normalizeIdentity(
      requestedOwnerUid,
      fieldName: 'ownerUid',
    );

    final User? currentUser = _auth.currentUser;

    if (currentUser == null) {
      throw const MessageMediaStoreException(
        category: MessageMediaErrorCategory.authentication,
        message: 'Authentication is required to access message media.',
        debugCode: 'unauthenticated',
      );
    }

    if (currentUser.uid != ownerUid) {
      throw const MessageMediaStoreException(
        category: MessageMediaErrorCategory.permission,
        message: 'You are not allowed to access this message attachment.',
        debugCode: 'owner-uid-mismatch',
      );
    }

    return ownerUid;
  }

  static void _verifyOwnedMetadata({
    required FullMetadata metadata,
    required String expectedOwnerUid,
    String? expectedConversationId,
    String? expectedMessageId,
    String? expectedAttachmentId,
  }) {
    final Map<String, String> custom =
        metadata.customMetadata ?? const <String, String>{};

    final String actualOwnerUid = custom[_ownerUidMetadataKey]?.trim() ?? '';

    if (actualOwnerUid.isEmpty || actualOwnerUid != expectedOwnerUid) {
      throw const MessageMediaStoreException(
        category: MessageMediaErrorCategory.permission,
        message: 'You are not allowed to access this message attachment.',
        debugCode: 'storage-owner-mismatch',
      );
    }

    if (expectedConversationId != null) {
      final String expected = _normalizeIdentity(
        expectedConversationId,
        fieldName: 'expectedConversationId',
      );

      if (custom[_conversationIdMetadataKey] != expected) {
        throw const MessageMediaStoreException(
          category: MessageMediaErrorCategory.conflict,
          message: 'The attachment does not belong to this conversation.',
          debugCode: 'conversation-metadata-mismatch',
        );
      }
    }

    if (expectedMessageId != null) {
      final String expected = _normalizeIdentity(
        expectedMessageId,
        fieldName: 'expectedMessageId',
      );

      if (custom[_messageIdMetadataKey] != expected) {
        throw const MessageMediaStoreException(
          category: MessageMediaErrorCategory.conflict,
          message: 'The attachment does not belong to this message.',
          debugCode: 'message-metadata-mismatch',
        );
      }
    }

    if (expectedAttachmentId != null) {
      final String expected = _normalizeIdentity(
        expectedAttachmentId,
        fieldName: 'expectedAttachmentId',
      );

      if (custom[_attachmentIdMetadataKey] != expected) {
        throw const MessageMediaStoreException(
          category: MessageMediaErrorCategory.conflict,
          message: 'The attachment identity does not match.',
          debugCode: 'attachment-metadata-mismatch',
        );
      }
    }
  }

  // --------------------------------------------------------------------------
  // METADATA HELPERS
  // --------------------------------------------------------------------------

  static Map<String, String> _buildMetadata({
    required String ownerUid,
    required String conversationId,
    required String messageId,
    required String attachmentId,
    required String originalFileName,
    Map<String, String>? additionalMetadata,
  }) {
    final Map<String, String> result = <String, String>{};

    if (additionalMetadata != null) {
      for (final MapEntry<String, String> entry in additionalMetadata.entries) {
        final String key = entry.key.trim();
        final String value = entry.value.trim();

        if (key.isEmpty || value.isEmpty) {
          continue;
        }

        if (_reservedMetadataKeys.contains(key)) {
          continue;
        }

        result[key] = value;
      }
    }

    result
      ..[_ownerUidMetadataKey] = ownerUid
      ..[_conversationIdMetadataKey] = conversationId
      ..[_messageIdMetadataKey] = messageId
      ..[_attachmentIdMetadataKey] = attachmentId
      ..[_originalFileNameMetadataKey] = originalFileName;

    return result;
  }

  static const Set<String> _reservedMetadataKeys = <String>{
    _ownerUidMetadataKey,
    _conversationIdMetadataKey,
    _messageIdMetadataKey,
    _attachmentIdMetadataKey,
    _originalFileNameMetadataKey,
  };

  static MessageMediaMetadata _metadataFromFirebase({
    required Reference reference,
    required FullMetadata metadata,
  }) {
    final Map<String, String> custom =
        metadata.customMetadata ?? const <String, String>{};

    final int byteSize = _requiredMetadataSize(metadata);

    return MessageMediaMetadata(
      storagePath: reference.fullPath,
      bucket: metadata.bucket ?? '',
      byteSize: byteSize,
      contentType: metadata.contentType,
      ownerUid: _requiredCustomMetadata(custom, _ownerUidMetadataKey),
      conversationId: _requiredCustomMetadata(
        custom,
        _conversationIdMetadataKey,
      ),
      messageId: _requiredCustomMetadata(custom, _messageIdMetadataKey),
      attachmentId: _requiredCustomMetadata(custom, _attachmentIdMetadataKey),
      originalFileName: _requiredCustomMetadata(
        custom,
        _originalFileNameMetadataKey,
      ),
      createdAt: metadata.timeCreated?.toUtc(),
      updatedAt: metadata.updated?.toUtc(),
    );
  }

  static int _requiredMetadataSize(FullMetadata metadata) {
    final int? value = metadata.size;

    if (value == null || value < 0) {
      throw const MessageMediaStoreException(
        category: MessageMediaErrorCategory.storage,
        message: 'Attachment size metadata is unavailable.',
        debugCode: 'missing-size-metadata',
      );
    }

    return value;
  }

  static String _requiredCustomMetadata(
    Map<String, String> metadata,
    String key,
  ) {
    final String value = metadata[key]?.trim() ?? '';

    if (value.isEmpty) {
      throw MessageMediaStoreException(
        category: MessageMediaErrorCategory.storage,
        message: 'Attachment metadata is incomplete.',
        debugCode: 'missing-$key',
      );
    }

    return value;
  }

  // --------------------------------------------------------------------------
  // VALUE VALIDATION
  // --------------------------------------------------------------------------

  static String _normalizeIdentity(String value, {required String fieldName}) {
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

  static String _normalizePathSegment(
    String value, {
    required String fieldName,
  }) {
    final String normalized = _normalizeIdentity(value, fieldName: fieldName);

    if (normalized == '.' ||
        normalized == '..' ||
        normalized.contains('/') ||
        normalized.contains('\\') ||
        normalized.contains('\u0000')) {
      throw ArgumentError.value(
        value,
        fieldName,
        '$fieldName is not a valid Storage path segment.',
      );
    }

    return normalized;
  }

  static String _normalizeOriginalFileName(String value) {
    final String normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(
        value,
        'fileName',
        'File name must not be empty.',
      );
    }

    if (normalized.contains('\u0000')) {
      throw ArgumentError.value(
        value,
        'fileName',
        'File name contains an invalid character.',
      );
    }

    return normalized;
  }

  static String _normalizeMimeType(String value) {
    final String normalized = value.trim().toLowerCase();

    final RegExp pattern = RegExp(r'^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$');

    if (normalized.isEmpty || !pattern.hasMatch(normalized)) {
      throw ArgumentError.value(
        value,
        'mimeType',
        'A valid MIME type is required.',
      );
    }

    return normalized;
  }

  static String _normalizeOwnedStoragePath(String storagePath) {
    final String path = storagePath.trim();

    if (path.isEmpty) {
      throw ArgumentError.value(
        storagePath,
        'storagePath',
        'Storage path must not be empty.',
      );
    }

    if (path.startsWith('/') ||
        path.contains('\\') ||
        path.contains('\u0000') ||
        path
            .split('/')
            .any(
              (String segment) =>
                  segment.isEmpty || segment == '.' || segment == '..',
            )) {
      throw ArgumentError.value(
        storagePath,
        'storagePath',
        'Storage path is invalid.',
      );
    }

    if (!path.startsWith('$rootFolder/')) {
      throw ArgumentError.value(
        storagePath,
        'storagePath',
        'Storage path is outside the JR CALL message-media root.',
      );
    }

    return path;
  }

  // --------------------------------------------------------------------------
  // FIREBASE ERROR NORMALIZATION
  // --------------------------------------------------------------------------

  MessageMediaStoreException _normalizeError(Object error) {
    if (error is MessageMediaStoreException) {
      return error;
    }

    if (error is FirebaseException) {
      final String code = error.code.trim().toLowerCase();

      switch (code) {
        case 'unauthenticated':
        case 'storage/unauthenticated':
          return MessageMediaStoreException(
            category: MessageMediaErrorCategory.authentication,
            message: 'Authentication is required to access message media.',
            debugCode: code,
          );

        case 'unauthorized':
        case 'permission-denied':
        case 'storage/unauthorized':
          return MessageMediaStoreException(
            category: MessageMediaErrorCategory.permission,
            message: 'You are not allowed to access this message attachment.',
            debugCode: code,
          );

        case 'object-not-found':
        case 'storage/object-not-found':
        case 'bucket-not-found':
        case 'storage/bucket-not-found':
          return MessageMediaStoreException(
            category: MessageMediaErrorCategory.notFound,
            message: 'The requested message attachment could not be found.',
            debugCode: code,
          );

        case 'quota-exceeded':
        case 'storage/quota-exceeded':
          return MessageMediaStoreException(
            category: MessageMediaErrorCategory.quota,
            message: 'Message media storage is temporarily unavailable.',
            debugCode: code,
          );

        case 'canceled':
        case 'cancelled':
        case 'storage/canceled':
        case 'storage/cancelled':
          return MessageMediaStoreException(
            category: MessageMediaErrorCategory.cancelled,
            message: 'The attachment upload was cancelled.',
            debugCode: code,
          );

        case 'retry-limit-exceeded':
        case 'storage/retry-limit-exceeded':
        case 'unavailable':
        case 'deadline-exceeded':
        case 'network-request-failed':
          return MessageMediaStoreException(
            category: MessageMediaErrorCategory.temporary,
            message:
                'The attachment could not be transferred right now. Please retry.',
            debugCode: code,
          );

        case 'invalid-argument':
        case 'invalid-checksum':
        case 'storage/invalid-checksum':
          return MessageMediaStoreException(
            category: MessageMediaErrorCategory.validation,
            message: 'The selected attachment could not be validated.',
            debugCode: code,
          );

        default:
          return MessageMediaStoreException(
            category: MessageMediaErrorCategory.storage,
            message: 'A message media storage operation failed.',
            debugCode: code.isEmpty ? 'firebase-storage-error' : code,
          );
      }
    }

    if (error is SocketException) {
      return const MessageMediaStoreException(
        category: MessageMediaErrorCategory.network,
        message:
            'Network connection was lost while transferring the attachment.',
        debugCode: 'socket-exception',
      );
    }

    if (error is FileSystemException) {
      return const MessageMediaStoreException(
        category: MessageMediaErrorCategory.storage,
        message: 'The selected local attachment could not be accessed.',
        debugCode: 'file-system-exception',
      );
    }

    return const MessageMediaStoreException(
      category: MessageMediaErrorCategory.unknown,
      message: 'The message attachment operation could not be completed.',
      debugCode: 'unknown-media-error',
    );
  }
}

// ============================================================================
// END OF FILE: lib/features/message/storage/message_media_store.dart
// ============================================================================
