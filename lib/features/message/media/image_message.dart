// ============================================================================
// JR CALL
// File: image_message.dart
// Location: lib/features/message/media/image_message.dart
// Description:
// Image attachment preparation for JR CALL Message Engine.
//
// Owns:
// - Local image validation.
// - Safe file-name normalization.
// - MIME validation.
// - Byte-size validation.
// - Optional image-dimension metadata supplied by picker/media layer.
// - Upload-ready AttachmentEntity creation.
//
// Does NOT own:
// - Firestore writes.
// - Firebase Storage upload.
// - Message creation.
// - Image picking UI.
// - Call Engine / WebRTC.
//
// Compression/resizing is intentionally not duplicated here. If the selected
// image has already been processed by the existing picker/crop/media layer,
// this file validates and prepares that resulting file for Message Engine.
// ============================================================================

import 'dart:io';

import '../data/attachment_entity.dart';

/// Production image attachment preparation helper.
///
/// This class performs deterministic client-side validation before media is
/// handed to [MediaUploadManager] / [MessageMediaStore].
///
/// Firebase Storage Security Rules remain the final server-side authority.
final class ImageMessage {
  const ImageMessage._();

  /// Maximum accepted image size before upload.
  ///
  /// Server-side Storage Rules must enforce the same or stricter policy.
  static const int maxImageBytes = 20 * 1024 * 1024;

  /// Supported MIME types for durable JR CALL image messages.
  static const Set<String> supportedMimeTypes = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'image/heic',
    'image/heif',
  };

  /// Prepares a validated upload-ready image attachment.
  ///
  /// [id] is the stable attachment ID.
  /// [messageId] is the canonical durable message ID.
  /// [conversationId] is the canonical conversation ID.
  /// [ownerUid] must be the authenticated Firebase UID.
  ///
  /// [mimeType] must come from trusted picker/file metadata or validated
  /// media inspection. File extension alone is never treated as authoritative.
  ///
  /// [width] and [height] are optional because not every existing picker API
  /// exposes dimensions without decoding the file.
  static Future<AttachmentEntity> prepare({
    required String id,
    required String messageId,
    required String conversationId,
    required String ownerUid,
    required File file,
    required String mimeType,
    int? width,
    int? height,
    DateTime? createdAt,
  }) async {
    final String normalizedId = _normalizeRequired(id, fieldName: 'id');

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

    if (!supportedMimeTypes.contains(normalizedMimeType)) {
      throw ImageMessageException(
        code: ImageMessageErrorCode.unsupportedMimeType,
        message: 'This image format is not supported.',
      );
    }

    if (width != null && width <= 0) {
      throw ImageMessageException(
        code: ImageMessageErrorCode.invalidMetadata,
        message: 'Image width must be greater than zero.',
      );
    }

    if (height != null && height <= 0) {
      throw ImageMessageException(
        code: ImageMessageErrorCode.invalidMetadata,
        message: 'Image height must be greater than zero.',
      );
    }

    final FileStat stat;

    try {
      stat = await file.stat();
    } on FileSystemException catch (error, stackTrace) {
      throw ImageMessageException(
        code: ImageMessageErrorCode.fileUnavailable,
        message: 'The selected image could not be accessed.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (stat.type != FileSystemEntityType.file) {
      throw const ImageMessageException(
        code: ImageMessageErrorCode.fileUnavailable,
        message: 'The selected image is not a valid local file.',
      );
    }

    final int byteSize = stat.size;

    if (byteSize <= 0) {
      throw const ImageMessageException(
        code: ImageMessageErrorCode.emptyFile,
        message: 'The selected image is empty.',
      );
    }

    if (byteSize > maxImageBytes) {
      throw const ImageMessageException(
        code: ImageMessageErrorCode.fileTooLarge,
        message: 'The selected image is larger than the allowed limit.',
      );
    }

    final String fileName = _safeFileName(
      file.path,
      mimeType: normalizedMimeType,
    );

    final DateTime normalizedCreatedAt = (createdAt ?? DateTime.now()).toUtc();

    return AttachmentEntity(
      id: normalizedId,
      messageId: normalizedMessageId,
      conversationId: normalizedConversationId,
      ownerUid: normalizedOwnerUid,
      type: AttachmentType.image,
      fileName: fileName,
      mimeType: normalizedMimeType,
      byteSize: byteSize,
      storagePath: '',
      downloadUrl: '',
      uploadState: AttachmentUploadState.pending,
      width: width,
      height: height,
      duration: null,
      thumbnail: null,
      createdAt: normalizedCreatedAt,
    );
  }

  /// Validates whether [mimeType] is allowed for image-message preparation.
  static bool supportsMimeType(String mimeType) {
    final String normalized = mimeType.trim().toLowerCase();

    return supportedMimeTypes.contains(normalized);
  }

  /// Validates only the local file-size boundary.
  ///
  /// Useful to reject an oversized selected image before further processing.
  static Future<int> validateFileSize(File file) async {
    final FileStat stat;

    try {
      stat = await file.stat();
    } on FileSystemException catch (error, stackTrace) {
      throw ImageMessageException(
        code: ImageMessageErrorCode.fileUnavailable,
        message: 'The selected image could not be accessed.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (stat.type != FileSystemEntityType.file) {
      throw const ImageMessageException(
        code: ImageMessageErrorCode.fileUnavailable,
        message: 'The selected image is not a valid local file.',
      );
    }

    final int byteSize = stat.size;

    if (byteSize <= 0) {
      throw const ImageMessageException(
        code: ImageMessageErrorCode.emptyFile,
        message: 'The selected image is empty.',
      );
    }

    if (byteSize > maxImageBytes) {
      throw const ImageMessageException(
        code: ImageMessageErrorCode.fileTooLarge,
        message: 'The selected image is larger than the allowed limit.',
      );
    }

    return byteSize;
  }

  static String _normalizeRequired(String value, {required String fieldName}) {
    final String normalized = value.trim();

    if (normalized.isEmpty) {
      throw ImageMessageException(
        code: ImageMessageErrorCode.invalidMetadata,
        message: '$fieldName must not be empty.',
      );
    }

    return normalized;
  }

  static String _normalizeMimeType(String value) {
    final String normalized = value.trim().toLowerCase();

    if (normalized.isEmpty) {
      throw const ImageMessageException(
        code: ImageMessageErrorCode.invalidMetadata,
        message: 'Image MIME type must not be empty.',
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
      return 'image.${_extensionForMimeType(mimeType)}';
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
      return 'image.${_extensionForMimeType(mimeType)}';
    }

    return '${rawName.substring(0, allowedBaseLength)}$extension';
  }

  static String _extensionForMimeType(String mimeType) {
    switch (mimeType) {
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      case 'image/heic':
        return 'heic';
      case 'image/heif':
        return 'heif';
    }

    return 'img';
  }
}

/// Stable image-preparation error categories.
enum ImageMessageErrorCode {
  invalidMetadata,
  unsupportedMimeType,
  fileUnavailable,
  emptyFile,
  fileTooLarge,
}

/// Safe normalized image-preparation exception.
///
/// [cause] is retained for internal diagnostics only. UI layers should display
/// [message], not raw filesystem/backend exception text.
final class ImageMessageException implements Exception {
  const ImageMessageException({
    required this.code,
    required this.message,
    this.cause,
    this.stackTrace,
  });

  final ImageMessageErrorCode code;
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() {
    return 'ImageMessageException('
        'code: ${code.name}, '
        'message: $message'
        ')';
  }
}

// ============================================================================
// END OF FILE: lib/features/message/media/image_message.dart
// ============================================================================
