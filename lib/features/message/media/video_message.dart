// ============================================================================
// JR CALL
// File: video_message.dart
// Location: lib/features/message/media/video_message.dart
// Description:
// Video attachment preparation for JR CALL Message Engine.
//
// Owns:
// - Local video-file validation.
// - Safe file-name normalization.
// - MIME/type validation.
// - Byte-size validation.
// - Optional width/height/duration metadata validation.
// - Optional typed thumbnail metadata.
// - Upload-ready AttachmentEntity creation.
//
// Does NOT own:
// - Firestore writes.
// - Firebase Storage upload.
// - Video playback/autoplay/feed logic.
// - Video picking UI.
// - Message creation.
// - Call Engine / WebRTC.
//
// Duration/dimension/thumbnail extraction may be supplied by an existing
// picker/media layer when available. This file does not introduce a new
// media package.
// ============================================================================

import 'dart:io';

import '../data/attachment_entity.dart';

/// Production video attachment preparation helper.
///
/// Performs deterministic validation before handing media to
/// `MediaUploadManager` / `MessageMediaStore`.
///
/// Firebase Storage Security Rules remain the final server-side authority.
final class VideoMessage {
  const VideoMessage._();

  /// Maximum accepted local video size before upload.
  ///
  /// Storage Rules must enforce the same or a stricter server-side limit.
  static const int maxVideoBytes = 100 * 1024 * 1024;

  /// Maximum accepted duration for a normal message video attachment.
  ///
  /// This limit belongs only to Message attachments and does not affect
  /// Video Reels or other JR CALL media products.
  static const Duration maxVideoDuration = Duration(minutes: 10);

  /// Supported MIME types for durable JR CALL video messages.
  ///
  /// The MIME value must originate from trusted picker/media metadata or
  /// validated content inspection. File extension alone is never trusted.
  static const Set<String> supportedMimeTypes = <String>{
    'video/mp4',
    'video/quicktime',
    'video/webm',
    'video/x-matroska',
    'video/3gpp',
    'video/3gpp2',
  };

  /// Prepares one validated upload-ready video attachment.
  ///
  /// [id] is the stable attachment ID.
  /// [messageId] is the canonical durable message ID.
  /// [conversationId] is the canonical conversation ID.
  /// [ownerUid] must be the authenticated Firebase UID.
  ///
  /// [thumbnail] uses FILE 10's canonical typed thumbnail model.
  ///
  /// No upload or Firestore write occurs in this method.
  static Future<AttachmentEntity> prepare({
    required String id,
    required String messageId,
    required String conversationId,
    required String ownerUid,
    required File file,
    required String mimeType,
    Duration? duration,
    int? width,
    int? height,
    AttachmentThumbnail? thumbnail,
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

    _validateMimeType(normalizedMimeType);

    _validateDimensions(width: width, height: height);

    _validateDuration(duration);

    final FileStat stat = await _readFileStat(file);
    final int byteSize = _validateByteSize(stat);

    final String fileName = _safeFileName(
      file.path,
      mimeType: normalizedMimeType,
    );

    return AttachmentEntity(
      id: normalizedId,
      messageId: normalizedMessageId,
      conversationId: normalizedConversationId,
      ownerUid: normalizedOwnerUid,
      type: AttachmentType.video,
      fileName: fileName,
      mimeType: normalizedMimeType,
      byteSize: byteSize,
      storagePath: '',
      downloadUrl: '',
      uploadState: AttachmentUploadState.pending,
      width: width,
      height: height,
      duration: duration,
      thumbnail: thumbnail,
      createdAt: (createdAt ?? DateTime.now()).toUtc(),
    );
  }

  /// Returns whether a MIME type is supported by this preparation layer.
  static bool supportsMimeType(String mimeType) {
    final String normalized = mimeType.trim().toLowerCase();

    if (normalized.isEmpty) {
      return false;
    }

    return supportedMimeTypes.contains(normalized);
  }

  /// Validates the local video and returns its exact byte count.
  static Future<int> validateFileSize(File file) async {
    final FileStat stat = await _readFileStat(file);

    return _validateByteSize(stat);
  }

  /// Validates supplied MIME/duration/dimension metadata independently.
  static void validateMetadata({
    required String mimeType,
    Duration? duration,
    int? width,
    int? height,
  }) {
    final String normalizedMimeType = _normalizeMimeType(mimeType);

    _validateMimeType(normalizedMimeType);

    _validateDimensions(width: width, height: height);

    _validateDuration(duration);
  }

  static Future<FileStat> _readFileStat(File file) async {
    final FileStat stat;

    try {
      stat = await file.stat();
    } on FileSystemException catch (error, stackTrace) {
      throw VideoMessageException(
        code: VideoMessageErrorCode.fileUnavailable,
        message: 'The selected video could not be accessed.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (stat.type != FileSystemEntityType.file) {
      throw const VideoMessageException(
        code: VideoMessageErrorCode.fileUnavailable,
        message: 'The selected video is not a valid local file.',
      );
    }

    return stat;
  }

  static int _validateByteSize(FileStat stat) {
    final int byteSize = stat.size;

    if (byteSize <= 0) {
      throw const VideoMessageException(
        code: VideoMessageErrorCode.emptyFile,
        message: 'The selected video is empty.',
      );
    }

    if (byteSize > maxVideoBytes) {
      throw const VideoMessageException(
        code: VideoMessageErrorCode.fileTooLarge,
        message: 'The selected video is larger than the allowed limit.',
      );
    }

    return byteSize;
  }

  static void _validateMimeType(String mimeType) {
    if (!supportedMimeTypes.contains(mimeType)) {
      throw const VideoMessageException(
        code: VideoMessageErrorCode.unsupportedMimeType,
        message: 'This video format is not supported.',
      );
    }
  }

  static void _validateDuration(Duration? duration) {
    if (duration == null) {
      return;
    }

    if (duration <= Duration.zero) {
      throw const VideoMessageException(
        code: VideoMessageErrorCode.invalidMetadata,
        message: 'Video duration must be greater than zero.',
      );
    }

    if (duration > maxVideoDuration) {
      throw const VideoMessageException(
        code: VideoMessageErrorCode.durationTooLong,
        message: 'The selected video is longer than the allowed limit.',
      );
    }
  }

  static void _validateDimensions({required int? width, required int? height}) {
    if (width != null && width <= 0) {
      throw const VideoMessageException(
        code: VideoMessageErrorCode.invalidMetadata,
        message: 'Video width must be greater than zero.',
      );
    }

    if (height != null && height <= 0) {
      throw const VideoMessageException(
        code: VideoMessageErrorCode.invalidMetadata,
        message: 'Video height must be greater than zero.',
      );
    }
  }

  static String _normalizeRequired(String value, {required String fieldName}) {
    final String normalized = value.trim();

    if (normalized.isEmpty) {
      throw VideoMessageException(
        code: VideoMessageErrorCode.invalidMetadata,
        message: '$fieldName must not be empty.',
      );
    }

    return normalized;
  }

  static String _normalizeMimeType(String value) {
    final String normalized = value.trim().toLowerCase();

    if (normalized.isEmpty) {
      throw const VideoMessageException(
        code: VideoMessageErrorCode.invalidMetadata,
        message: 'Video MIME type must not be empty.',
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
      return 'video.${_extensionForMimeType(mimeType)}';
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
      return 'video.${_extensionForMimeType(mimeType)}';
    }

    return '${rawName.substring(0, allowedBaseLength)}$extension';
  }

  static String _extensionForMimeType(String mimeType) {
    switch (mimeType) {
      case 'video/mp4':
        return 'mp4';
      case 'video/quicktime':
        return 'mov';
      case 'video/webm':
        return 'webm';
      case 'video/x-matroska':
        return 'mkv';
      case 'video/3gpp':
        return '3gp';
      case 'video/3gpp2':
        return '3g2';
    }

    return 'video';
  }
}

/// Stable video-preparation error categories.
enum VideoMessageErrorCode {
  invalidMetadata,
  unsupportedMimeType,
  fileUnavailable,
  emptyFile,
  fileTooLarge,
  durationTooLong,
}

/// Safe normalized video-preparation exception.
///
/// [cause] and [stackTrace] remain available for internal diagnostics only.
/// Presentation code should use [message] rather than exposing raw filesystem
/// errors directly to the user.
final class VideoMessageException implements Exception {
  const VideoMessageException({
    required this.code,
    required this.message,
    this.cause,
    this.stackTrace,
  });

  final VideoMessageErrorCode code;
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() {
    return 'VideoMessageException('
        'code: ${code.name}, '
        'message: $message'
        ')';
  }
}

// ============================================================================
// END OF FILE: lib/features/message/media/video_message.dart
// ============================================================================
