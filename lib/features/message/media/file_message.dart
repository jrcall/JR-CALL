// ============================================================================
// JR CALL
// File: file_message.dart
// Location: lib/features/message/media/file_message.dart
// Description:
// General document/file attachment preparation for JR CALL Message Engine.
//
// Owns:
// - Local file validation.
// - Safe filename normalization.
// - MIME normalization/validation.
// - Byte-size validation.
// - Dangerous/unsupported file rejection.
// - AttachmentEntity preparation.
//
// Security:
// - File extension is never trusted as the sole authorization signal.
// - MIME type and extension are evaluated together.
// - Known executable/script/package formats are rejected.
// - Firebase Storage Security Rules must independently enforce final limits.
//
// Does NOT own:
// - File picker UI.
// - Firebase Storage upload.
// - Firestore writes.
// - Durable message creation.
// - Media upload orchestration.
// - Call Engine / WebRTC.
// ============================================================================

import 'dart:io';

import '../data/attachment_entity.dart';

/// Immutable prepared general-file attachment.
///
/// [file] remains local until `media_upload_manager.dart` hands it to the
/// Message Storage layer.
final class PreparedFileMessage {
  const PreparedFileMessage({required this.file, required this.attachment});

  final File file;
  final AttachmentEntity attachment;
}

/// Production document/general-file preparation utility.
final class FileMessage {
  const FileMessage._();

  /// Maximum client-side size accepted for a general document/file.
  ///
  /// Storage Security Rules must repeat the final production limit.
  static const int maxFileBytes = 50 * 1024 * 1024;

  static const int maxFileNameLength = 120;

  /// Allowed general-document MIME types.
  ///
  /// Image/video/audio attachments belong to their dedicated preparation
  /// classes and therefore are intentionally not broadly accepted here.
  static const Set<String> supportedMimeTypes = <String>{
    'application/pdf',
    'text/plain',
    'text/csv',
    'text/markdown',
    'application/rtf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-powerpoint',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'application/vnd.oasis.opendocument.text',
    'application/vnd.oasis.opendocument.spreadsheet',
    'application/vnd.oasis.opendocument.presentation',
    'application/json',
    'application/xml',
    'text/xml',
    'application/zip',
    'application/x-zip-compressed',
  };

  /// Extensions allowed for MIME types where a safe document extension is
  /// expected.
  static const Set<String> supportedExtensions = <String>{
    'pdf',
    'txt',
    'csv',
    'md',
    'rtf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'odt',
    'ods',
    'odp',
    'json',
    'xml',
    'zip',
  };

  /// Executable/script/package formats that must never be accepted merely
  /// because the caller supplied a benign MIME type.
  static const Set<String> blockedExtensions = <String>{
    'apk',
    'app',
    'appx',
    'bat',
    'bin',
    'cmd',
    'com',
    'cpl',
    'dll',
    'dmg',
    'exe',
    'gadget',
    'hta',
    'inf',
    'ins',
    'ipa',
    'iso',
    'jar',
    'js',
    'jse',
    'lnk',
    'msi',
    'msp',
    'mst',
    'pif',
    'ps1',
    'ps1xml',
    'ps2',
    'ps2xml',
    'psc1',
    'psc2',
    'reg',
    'scr',
    'sh',
    'sys',
    'vb',
    'vbe',
    'vbs',
    'vxd',
    'ws',
    'wsc',
    'wsf',
    'wsh',
  };

  static const Set<String> blockedMimeTypes = <String>{
    'application/x-msdownload',
    'application/x-msdos-program',
    'application/x-executable',
    'application/x-sh',
    'application/x-shellscript',
    'application/java-archive',
    'application/vnd.android.package-archive',
    'application/x-apple-diskimage',
    'application/x-iso9660-image',
  };

  /// Prepares a local document/general file for Message Engine upload.
  static Future<PreparedFileMessage> prepare({
    required String attachmentId,
    required String messageId,
    required String conversationId,
    required String ownerUid,
    required File file,
    required String mimeType,
    String? originalFileName,
    DateTime? createdAt,
  }) async {
    final String normalizedAttachmentId = _normalizeRequiredId(
      attachmentId,
      fieldName: 'attachmentId',
    );

    final String normalizedMessageId = _normalizeRequiredId(
      messageId,
      fieldName: 'messageId',
    );

    final String normalizedConversationId = _normalizeRequiredId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String normalizedOwnerUid = _normalizeRequiredId(
      ownerUid,
      fieldName: 'ownerUid',
    );

    final String normalizedMimeType = normalizeMimeType(mimeType);

    final FileStat stat = await _readFileStat(file);

    final int byteSize = validateByteSize(stat.size);

    final String normalizedFileName = normalizeFileName(
      originalFileName ?? _nameFromPath(file.path),
    );

    validateFile(
      fileName: normalizedFileName,
      mimeType: normalizedMimeType,
      byteSize: byteSize,
    );

    final AttachmentEntity attachment = AttachmentEntity(
      id: normalizedAttachmentId,
      messageId: normalizedMessageId,
      conversationId: normalizedConversationId,
      ownerUid: normalizedOwnerUid,
      type: AttachmentType.file,
      fileName: normalizedFileName,
      mimeType: normalizedMimeType,
      byteSize: byteSize,
      storagePath: '',
      downloadUrl: '',
      uploadState: AttachmentUploadState.pending,
      createdAt: (createdAt ?? DateTime.now()).toUtc(),
    );

    return PreparedFileMessage(file: file, attachment: attachment);
  }

  /// Validates all general-file metadata as one centralized policy.
  static void validateFile({
    required String fileName,
    required String mimeType,
    required int byteSize,
  }) {
    final String normalizedFileName = normalizeFileName(fileName);
    final String normalizedMimeType = normalizeMimeType(mimeType);

    validateByteSize(byteSize);
    validateMimeType(normalizedMimeType);
    validateExtension(
      fileName: normalizedFileName,
      mimeType: normalizedMimeType,
    );
  }

  /// Returns true only when the MIME type is accepted by the general document
  /// policy.
  static bool supportsMimeType(String mimeType) {
    final String normalized = mimeType.trim().toLowerCase();

    return normalized.isNotEmpty &&
        supportedMimeTypes.contains(normalized) &&
        !blockedMimeTypes.contains(normalized);
  }

  /// Normalizes and validates a MIME type.
  static String normalizeMimeType(String value) {
    final String normalized = value
        .trim()
        .toLowerCase()
        .split(';')
        .first
        .trim();

    if (normalized.isEmpty) {
      throw const FileMessageException(
        code: FileMessageErrorCode.invalidMimeType,
        message: 'File MIME type must not be empty.',
      );
    }

    if (!_looksLikeMimeType(normalized)) {
      throw const FileMessageException(
        code: FileMessageErrorCode.invalidMimeType,
        message: 'File MIME type is malformed.',
      );
    }

    return normalized;
  }

  /// Verifies MIME authorization.
  static void validateMimeType(String mimeType) {
    final String normalized = normalizeMimeType(mimeType);

    if (blockedMimeTypes.contains(normalized)) {
      throw const FileMessageException(
        code: FileMessageErrorCode.unsafeFileType,
        message: 'This file type is not allowed.',
      );
    }

    if (!supportedMimeTypes.contains(normalized)) {
      throw const FileMessageException(
        code: FileMessageErrorCode.unsupportedMimeType,
        message: 'This document type is not supported.',
      );
    }
  }

  /// Ensures extension and MIME data describe an allowed document class.
  ///
  /// Extension is used as an additional rejection/consistency signal only.
  /// It is never treated as proof that the binary content is safe.
  static void validateExtension({
    required String fileName,
    required String mimeType,
  }) {
    final String normalizedName = normalizeFileName(fileName);
    final String normalizedMime = normalizeMimeType(mimeType);
    final String extension = extensionOf(normalizedName);

    if (extension.isEmpty) {
      throw const FileMessageException(
        code: FileMessageErrorCode.missingExtension,
        message: 'The document file type could not be determined.',
      );
    }

    if (blockedExtensions.contains(extension)) {
      throw const FileMessageException(
        code: FileMessageErrorCode.unsafeFileType,
        message: 'This file type is not allowed.',
      );
    }

    if (!supportedExtensions.contains(extension)) {
      throw const FileMessageException(
        code: FileMessageErrorCode.unsupportedExtension,
        message: 'This document file extension is not supported.',
      );
    }

    final Set<String>? permittedExtensions = _mimeExtensionMap[normalizedMime];

    if (permittedExtensions == null ||
        !permittedExtensions.contains(extension)) {
      throw const FileMessageException(
        code: FileMessageErrorCode.mimeExtensionMismatch,
        message: 'The file type does not match its MIME metadata.',
      );
    }
  }

  /// Validates client-side file-size constraints.
  static int validateByteSize(int byteSize) {
    if (byteSize <= 0) {
      throw const FileMessageException(
        code: FileMessageErrorCode.emptyFile,
        message: 'The selected file is empty.',
      );
    }

    if (byteSize > maxFileBytes) {
      throw const FileMessageException(
        code: FileMessageErrorCode.fileTooLarge,
        message: 'The selected file exceeds the allowed size.',
      );
    }

    return byteSize;
  }

  /// Sanitizes a user/device supplied filename while preserving its extension.
  static String normalizeFileName(String value) {
    String fileName = value.replaceAll('\\', '/').split('/').last.trim();

    fileName = fileName
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    while (fileName.startsWith('.')) {
      fileName = fileName.substring(1);
    }

    if (fileName.isEmpty || fileName == '.' || fileName == '..') {
      throw const FileMessageException(
        code: FileMessageErrorCode.invalidFileName,
        message: 'The selected file name is invalid.',
      );
    }

    if (fileName.length > maxFileNameLength) {
      fileName = _truncateFileName(fileName);
    }

    if (fileName.isEmpty) {
      throw const FileMessageException(
        code: FileMessageErrorCode.invalidFileName,
        message: 'The selected file name is invalid.',
      );
    }

    return fileName;
  }

  static String extensionOf(String fileName) {
    final String normalized = normalizeFileName(fileName);
    final int dotIndex = normalized.lastIndexOf('.');

    if (dotIndex <= 0 || dotIndex == normalized.length - 1) {
      return '';
    }

    return normalized.substring(dotIndex + 1).trim().toLowerCase();
  }

  static Future<FileStat> _readFileStat(File file) async {
    final FileStat stat;

    try {
      stat = await file.stat();
    } on FileSystemException catch (error, stackTrace) {
      throw FileMessageException(
        code: FileMessageErrorCode.fileUnavailable,
        message: 'The selected file could not be accessed.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (stat.type != FileSystemEntityType.file) {
      throw const FileMessageException(
        code: FileMessageErrorCode.fileUnavailable,
        message: 'The selected path is not a valid file.',
      );
    }

    return stat;
  }

  static String _normalizeRequiredId(
    String value, {
    required String fieldName,
  }) {
    final String normalized = value.trim();

    if (normalized.isEmpty) {
      throw FileMessageException(
        code: FileMessageErrorCode.invalidMetadata,
        message: '$fieldName must not be empty.',
      );
    }

    return normalized;
  }

  static String _nameFromPath(String path) {
    final String normalizedPath = path.replaceAll('\\', '/');
    final String name = normalizedPath.split('/').last;

    if (name.trim().isEmpty) {
      throw const FileMessageException(
        code: FileMessageErrorCode.invalidFileName,
        message: 'The selected file name is invalid.',
      );
    }

    return name;
  }

  static String _truncateFileName(String fileName) {
    final int dotIndex = fileName.lastIndexOf('.');

    if (dotIndex <= 0 || dotIndex == fileName.length - 1) {
      return fileName.substring(0, maxFileNameLength).trim();
    }

    final String extension = fileName.substring(dotIndex);
    final int allowedBaseLength = maxFileNameLength - extension.length;

    if (allowedBaseLength <= 0) {
      throw const FileMessageException(
        code: FileMessageErrorCode.invalidFileName,
        message: 'The selected file name is invalid.',
      );
    }

    final String base = fileName.substring(0, allowedBaseLength).trim();

    if (base.isEmpty) {
      throw const FileMessageException(
        code: FileMessageErrorCode.invalidFileName,
        message: 'The selected file name is invalid.',
      );
    }

    return '$base$extension';
  }

  static bool _looksLikeMimeType(String value) {
    final int slashIndex = value.indexOf('/');

    if (slashIndex <= 0 || slashIndex == value.length - 1) {
      return false;
    }

    if (value.indexOf('/', slashIndex + 1) != -1) {
      return false;
    }

    final String type = value.substring(0, slashIndex);
    final String subtype = value.substring(slashIndex + 1);

    final RegExp token = RegExp(r"^[a-z0-9!#$&^_.+-]+$");

    return token.hasMatch(type) && token.hasMatch(subtype);
  }

  static const Map<String, Set<String>>
  _mimeExtensionMap = <String, Set<String>>{
    'application/pdf': <String>{'pdf'},
    'text/plain': <String>{'txt'},
    'text/csv': <String>{'csv'},
    'text/markdown': <String>{'md'},
    'application/rtf': <String>{'rtf'},
    'application/msword': <String>{'doc'},
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
        <String>{'docx'},
    'application/vnd.ms-excel': <String>{'xls'},
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':
        <String>{'xlsx'},
    'application/vnd.ms-powerpoint': <String>{'ppt'},
    'application/vnd.openxmlformats-officedocument.presentationml.presentation':
        <String>{'pptx'},
    'application/vnd.oasis.opendocument.text': <String>{'odt'},
    'application/vnd.oasis.opendocument.spreadsheet': <String>{'ods'},
    'application/vnd.oasis.opendocument.presentation': <String>{'odp'},
    'application/json': <String>{'json'},
    'application/xml': <String>{'xml'},
    'text/xml': <String>{'xml'},
    'application/zip': <String>{'zip'},
    'application/x-zip-compressed': <String>{'zip'},
  };
}

/// Stable general-file preparation error categories.
enum FileMessageErrorCode {
  invalidMetadata,
  invalidFileName,
  invalidMimeType,
  missingExtension,
  unsupportedMimeType,
  unsupportedExtension,
  mimeExtensionMismatch,
  unsafeFileType,
  fileUnavailable,
  emptyFile,
  fileTooLarge,
}

/// Safe normalized general-file preparation exception.
///
/// [cause] is retained only for internal diagnostics. Presentation code must
/// not blindly expose raw filesystem/platform exception text.
final class FileMessageException implements Exception {
  const FileMessageException({
    required this.code,
    required this.message,
    this.cause,
    this.stackTrace,
  });

  final FileMessageErrorCode code;
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() {
    return 'FileMessageException('
        'code: ${code.name}, '
        'message: $message'
        ')';
  }
}

// ============================================================================
// END OF FILE: lib/features/message/media/file_message.dart
// ============================================================================
