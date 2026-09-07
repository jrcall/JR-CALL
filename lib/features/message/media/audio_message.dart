// ============================================================================
// JR CALL
// File: audio_message.dart
// Location: lib/features/message/media/audio_message.dart
// Description:
// Existing audio-file attachment preparation for JR CALL Message Engine.
//
// Owns:
// - Local audio-file validation.
// - Safe file-name normalization.
// - MIME/type validation.
// - Byte-size validation.
// - Optional duration metadata validation.
// - Upload-ready AttachmentEntity creation.
//
// Distinct from:
// - Recorded voice-message lifecycle.
// - Microphone recording ownership.
//
// Does NOT own:
// - Firestore writes.
// - Firebase Storage upload.
// - Audio recording.
// - Audio playback UI.
// - Message creation.
// - Call Engine / WebRTC.
//
// Duration extraction may be supplied by an existing picker/media layer when
// available. This file does not introduce a new audio/media dependency.
// ============================================================================

import 'dart:io';

import '../data/attachment_entity.dart';

/// Production existing-audio-file attachment preparation helper.
///
/// This class handles files that already exist on the user's device.
///
/// Recorded microphone voice messages belong to `voice_message.dart`.
final class AudioMessage {
  const AudioMessage._();

  /// Maximum accepted audio-file size before upload.
  ///
  /// Firebase Storage Security Rules must independently enforce the same or a
  /// stricter server-side limit.
  static const int maxAudioBytes = 50 * 1024 * 1024;

  /// Maximum accepted duration for an existing audio attachment.
  static const Duration maxAudioDuration = Duration(hours: 1);

  /// Supported MIME types for durable audio-file messages.
  static const Set<String> supportedMimeTypes = <String>{
    'audio/mpeg',
    'audio/mp3',
    'audio/mp4',
    'audio/aac',
    'audio/x-aac',
    'audio/wav',
    'audio/x-wav',
    'audio/wave',
    'audio/ogg',
    'audio/webm',
    'audio/flac',
    'audio/x-flac',
    'audio/x-m4a',
    'audio/3gpp',
    'audio/amr',
  };

  /// Prepares an existing local audio file for the upload pipeline.
  ///
  /// [id] is the stable attachment ID.
  /// [messageId] is the canonical durable message ID.
  /// [conversationId] is the canonical conversation ID.
  /// [ownerUid] must be the authenticated Firebase UID.
  ///
  /// [mimeType] must come from trusted picker/media metadata or validated
  /// content inspection. File extension alone is never trusted as proof of
  /// media type.
  static Future<AttachmentEntity> prepare({
    required String id,
    required String messageId,
    required String conversationId,
    required String ownerUid,
    required File file,
    required String mimeType,
    Duration? duration,
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
      type: AttachmentType.audio,
      fileName: fileName,
      mimeType: normalizedMimeType,
      byteSize: byteSize,
      storagePath: '',
      downloadUrl: '',
      uploadState: AttachmentUploadState.pending,
      duration: duration,
      createdAt: (createdAt ?? DateTime.now()).toUtc(),
    );
  }

  /// Returns whether [mimeType] belongs to the supported existing-audio set.
  static bool supportsMimeType(String mimeType) {
    final String normalized = mimeType.trim().toLowerCase();
    return supportedMimeTypes.contains(normalized);
  }

  /// Validates local audio-file existence and byte size.
  static Future<int> validateFileSize(File file) async {
    final FileStat stat = await _readFileStat(file);
    return _validateByteSize(stat);
  }

  /// Validates metadata independently from attachment creation.
  static void validateMetadata({required String mimeType, Duration? duration}) {
    final String normalizedMimeType = _normalizeMimeType(mimeType);

    _validateMimeType(normalizedMimeType);
    _validateDuration(duration);
  }

  static Future<FileStat> _readFileStat(File file) async {
    final FileStat stat;

    try {
      stat = await file.stat();
    } on FileSystemException catch (error, stackTrace) {
      throw AudioMessageException(
        code: AudioMessageErrorCode.fileUnavailable,
        message: 'The selected audio file could not be accessed.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (stat.type != FileSystemEntityType.file) {
      throw const AudioMessageException(
        code: AudioMessageErrorCode.fileUnavailable,
        message: 'The selected audio item is not a valid local file.',
      );
    }

    return stat;
  }

  static int _validateByteSize(FileStat stat) {
    final int byteSize = stat.size;

    if (byteSize <= 0) {
      throw const AudioMessageException(
        code: AudioMessageErrorCode.emptyFile,
        message: 'The selected audio file is empty.',
      );
    }

    if (byteSize > maxAudioBytes) {
      throw const AudioMessageException(
        code: AudioMessageErrorCode.fileTooLarge,
        message: 'The selected audio file is larger than the allowed limit.',
      );
    }

    return byteSize;
  }

  static void _validateMimeType(String mimeType) {
    if (!supportedMimeTypes.contains(mimeType)) {
      throw const AudioMessageException(
        code: AudioMessageErrorCode.unsupportedMimeType,
        message: 'This audio format is not supported.',
      );
    }
  }

  static void _validateDuration(Duration? duration) {
    if (duration == null) {
      return;
    }

    if (duration <= Duration.zero) {
      throw const AudioMessageException(
        code: AudioMessageErrorCode.invalidMetadata,
        message: 'Audio duration must be greater than zero.',
      );
    }

    if (duration > maxAudioDuration) {
      throw const AudioMessageException(
        code: AudioMessageErrorCode.durationTooLong,
        message: 'The selected audio file is longer than the allowed limit.',
      );
    }
  }

  static String _normalizeRequired(String value, {required String fieldName}) {
    final String normalized = value.trim();

    if (normalized.isEmpty) {
      throw AudioMessageException(
        code: AudioMessageErrorCode.invalidMetadata,
        message: '$fieldName must not be empty.',
      );
    }

    return normalized;
  }

  static String _normalizeMimeType(String value) {
    final String normalized = value.trim().toLowerCase();

    if (normalized.isEmpty) {
      throw const AudioMessageException(
        code: AudioMessageErrorCode.invalidMetadata,
        message: 'Audio MIME type must not be empty.',
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
      return 'audio.${_extensionForMimeType(mimeType)}';
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
      return 'audio.${_extensionForMimeType(mimeType)}';
    }

    return '${rawName.substring(0, allowedBaseLength)}$extension';
  }

  static String _extensionForMimeType(String mimeType) {
    switch (mimeType) {
      case 'audio/mpeg':
      case 'audio/mp3':
        return 'mp3';

      case 'audio/mp4':
      case 'audio/x-m4a':
        return 'm4a';

      case 'audio/aac':
      case 'audio/x-aac':
        return 'aac';

      case 'audio/wav':
      case 'audio/x-wav':
      case 'audio/wave':
        return 'wav';

      case 'audio/ogg':
        return 'ogg';

      case 'audio/webm':
        return 'webm';

      case 'audio/flac':
      case 'audio/x-flac':
        return 'flac';

      case 'audio/3gpp':
        return '3gp';

      case 'audio/amr':
        return 'amr';
    }

    return 'audio';
  }
}

/// Stable existing-audio preparation error categories.
enum AudioMessageErrorCode {
  invalidMetadata,
  unsupportedMimeType,
  fileUnavailable,
  emptyFile,
  fileTooLarge,
  durationTooLong,
}

/// Safe normalized audio preparation exception.
///
/// [cause] and [stackTrace] are retained for internal diagnostics only.
/// Presentation layers must not blindly expose raw filesystem errors.
final class AudioMessageException implements Exception {
  const AudioMessageException({
    required this.code,
    required this.message,
    this.cause,
    this.stackTrace,
  });

  final AudioMessageErrorCode code;
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() {
    return 'AudioMessageException('
        'code: ${code.name}, '
        'message: $message'
        ')';
  }
}

// ============================================================================
// END OF FILE: lib/features/message/media/audio_message.dart
// ============================================================================
