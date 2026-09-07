// ============================================================================
// JR CALL
// File: attachment_entity.dart
// Location: lib/features/message/data/attachment_entity.dart
// Description:
// Canonical immutable attachment metadata model for JR CALL Message Engine.
//
// Responsibilities:
// - Represents image/video/audio/voice/file attachment metadata.
// - Preserves canonical message/conversation/owner identity.
// - Preserves deterministic Firebase Storage path metadata.
// - Tracks upload lifecycle without storing binary media.
// - Stores optional image dimensions, media duration and thumbnail metadata.
// - Provides safe Firestore/local serialization.
// - Provides immutable copyWith/value equality.
//
// Important:
// - ownerUid is always Firebase Auth UID.
// - This model never stores raw file bytes.
// - This model never trusts a file extension as MIME/type authority.
// - Binary validation/upload ownership belongs to media/security/storage layers.
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

/// Canonical JR CALL attachment type.
enum AttachmentType {
  image,
  video,
  audio,
  voice,
  file;

  String get serialized => name;

  static AttachmentType fromValue(Object? value) {
    if (value is AttachmentType) {
      return value;
    }

    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'image':
          return AttachmentType.image;
        case 'video':
          return AttachmentType.video;
        case 'audio':
          return AttachmentType.audio;
        case 'voice':
          return AttachmentType.voice;
        case 'file':
        case 'document':
          return AttachmentType.file;
      }
    }

    throw FormatException('Unsupported attachment type: $value');
  }
}

/// Canonical attachment upload state.
enum AttachmentUploadState {
  pending,
  validating,
  uploading,
  paused,
  uploaded,
  failed,
  cancelled;

  String get serialized => name;

  static AttachmentUploadState fromValue(Object? value) {
    if (value is AttachmentUploadState) {
      return value;
    }

    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'pending':
          return AttachmentUploadState.pending;
        case 'validating':
          return AttachmentUploadState.validating;
        case 'uploading':
          return AttachmentUploadState.uploading;
        case 'paused':
          return AttachmentUploadState.paused;
        case 'uploaded':
          return AttachmentUploadState.uploaded;
        case 'failed':
          return AttachmentUploadState.failed;
        case 'cancelled':
          return AttachmentUploadState.cancelled;
      }
    }

    throw FormatException('Unsupported attachment upload state: $value');
  }
}

/// Optional thumbnail metadata.
final class AttachmentThumbnail {
  const AttachmentThumbnail({
    this.storagePath,
    this.downloadUrl,
    this.mimeType,
    this.byteSize,
    this.width,
    this.height,
  });

  final String? storagePath;
  final String? downloadUrl;
  final String? mimeType;
  final int? byteSize;
  final int? width;
  final int? height;

  bool get isEmpty =>
      storagePath == null &&
      downloadUrl == null &&
      mimeType == null &&
      byteSize == null &&
      width == null &&
      height == null;

  factory AttachmentThumbnail.fromMap(Map<String, Object?> map) {
    return AttachmentThumbnail(
      storagePath: _optionalString(map['storagePath']),
      downloadUrl: _optionalString(map['downloadUrl']),
      mimeType: _optionalString(map['mimeType']),
      byteSize: _optionalNonNegativeInt(
        map['byteSize'],
        fieldName: 'thumbnail.byteSize',
      ),
      width: _optionalPositiveInt(map['width'], fieldName: 'thumbnail.width'),
      height: _optionalPositiveInt(
        map['height'],
        fieldName: 'thumbnail.height',
      ),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'storagePath': storagePath,
      'downloadUrl': downloadUrl,
      'mimeType': mimeType,
      'byteSize': byteSize,
      'width': width,
      'height': height,
    };
  }

  AttachmentThumbnail copyWith({
    String? storagePath,
    bool clearStoragePath = false,
    String? downloadUrl,
    bool clearDownloadUrl = false,
    String? mimeType,
    bool clearMimeType = false,
    int? byteSize,
    bool clearByteSize = false,
    int? width,
    bool clearWidth = false,
    int? height,
    bool clearHeight = false,
  }) {
    return AttachmentThumbnail(
      storagePath: clearStoragePath ? null : storagePath ?? this.storagePath,
      downloadUrl: clearDownloadUrl ? null : downloadUrl ?? this.downloadUrl,
      mimeType: clearMimeType ? null : mimeType ?? this.mimeType,
      byteSize: clearByteSize ? null : byteSize ?? this.byteSize,
      width: clearWidth ? null : width ?? this.width,
      height: clearHeight ? null : height ?? this.height,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AttachmentThumbnail &&
            other.storagePath == storagePath &&
            other.downloadUrl == downloadUrl &&
            other.mimeType == mimeType &&
            other.byteSize == byteSize &&
            other.width == width &&
            other.height == height;
  }

  @override
  int get hashCode =>
      Object.hash(storagePath, downloadUrl, mimeType, byteSize, width, height);

  static String? _optionalString(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is! String) {
      throw const FormatException(
        'AttachmentThumbnail string field has invalid type.',
      );
    }

    final String normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static int? _optionalNonNegativeInt(
    Object? value, {
    required String fieldName,
  }) {
    if (value == null) {
      return null;
    }

    if (value is! num || value % 1 != 0) {
      throw FormatException('$fieldName must be an integer.');
    }

    final int result = value.toInt();

    if (result < 0) {
      throw FormatException('$fieldName cannot be negative.');
    }

    return result;
  }

  static int? _optionalPositiveInt(Object? value, {required String fieldName}) {
    final int? result = _optionalNonNegativeInt(value, fieldName: fieldName);

    if (result != null && result <= 0) {
      throw FormatException('$fieldName must be greater than zero.');
    }

    return result;
  }
}

/// Canonical immutable JR CALL attachment metadata.
final class AttachmentEntity {
  AttachmentEntity({
    required String id,
    required String messageId,
    required String conversationId,
    required String ownerUid,
    required this.type,
    required String fileName,
    required String mimeType,
    required int byteSize,
    required String storagePath,
    required this.uploadState,
    required DateTime createdAt,
    String? downloadUrl,
    int? width,
    int? height,
    Duration? duration,
    AttachmentThumbnail? thumbnail,
  }) : id = _normalizeRequiredString(id, fieldName: 'id'),
       messageId = _normalizeRequiredString(messageId, fieldName: 'messageId'),
       conversationId = _normalizeRequiredString(
         conversationId,
         fieldName: 'conversationId',
       ),
       ownerUid = _normalizeRequiredString(ownerUid, fieldName: 'ownerUid'),
       fileName = _normalizeFileName(fileName),
       mimeType = _normalizeMimeType(mimeType),
       byteSize = _validateByteSize(byteSize),
       storagePath = _normalizeStoragePath(storagePath),
       downloadUrl = _normalizeOptionalString(downloadUrl),
       width = _validateOptionalDimension(width, fieldName: 'width'),
       height = _validateOptionalDimension(height, fieldName: 'height'),
       duration = _validateOptionalDuration(duration),
       thumbnail = thumbnail?.isEmpty == true ? null : thumbnail,
       createdAt = createdAt.toUtc() {
    _validateTypeSpecificMetadata();
    _validateUploadState();
  }

  /// Canonical attachment identity.
  final String id;

  /// Canonical durable message ID.
  final String messageId;

  /// Canonical conversation ID.
  final String conversationId;

  /// Canonical Firebase Auth UID that owns this attachment.
  final String ownerUid;

  final AttachmentType type;

  /// Original normalized file name when relevant.
  final String fileName;

  /// MIME type determined by trusted validation/media layer.
  final String mimeType;

  final int byteSize;

  /// Deterministic Firebase Storage object path.
  final String storagePath;

  /// Firebase Storage download URL after successful upload.
  final String? downloadUrl;

  final AttachmentUploadState uploadState;

  final int? width;
  final int? height;
  final Duration? duration;
  final AttachmentThumbnail? thumbnail;

  final DateTime createdAt;

  bool get isUploaded =>
      uploadState == AttachmentUploadState.uploaded && downloadUrl != null;

  bool get isUploading => uploadState == AttachmentUploadState.uploading;

  bool get isFailed => uploadState == AttachmentUploadState.failed;

  bool get isCancelled => uploadState == AttachmentUploadState.cancelled;

  bool get isVisual =>
      type == AttachmentType.image || type == AttachmentType.video;

  bool get isAudio =>
      type == AttachmentType.audio || type == AttachmentType.voice;

  /// Required deterministic path pattern:
  ///
  /// message_media/{conversationId}/{messageId}/{attachmentId}/{filename}
  static String buildStoragePath({
    required String conversationId,
    required String messageId,
    required String attachmentId,
    required String fileName,
  }) {
    final String conversation = _normalizeRequiredString(
      conversationId,
      fieldName: 'conversationId',
    );

    final String message = _normalizeRequiredString(
      messageId,
      fieldName: 'messageId',
    );

    final String attachment = _normalizeRequiredString(
      attachmentId,
      fieldName: 'attachmentId',
    );

    final String normalizedFileName = _normalizeFileName(fileName);

    return 'message_media/'
        '$conversation/'
        '$message/'
        '$attachment/'
        '$normalizedFileName';
  }

  factory AttachmentEntity.fromMap(Map<String, Object?> map) {
    final Map<String, Object?>? thumbnailMap = _mapValue(map['thumbnail']);

    return AttachmentEntity(
      id: _requiredString(map['id'], fieldName: 'id'),
      messageId: _requiredString(map['messageId'], fieldName: 'messageId'),
      conversationId: _requiredString(
        map['conversationId'],
        fieldName: 'conversationId',
      ),
      ownerUid: _requiredString(map['ownerUid'], fieldName: 'ownerUid'),
      type: AttachmentType.fromValue(map['type']),
      fileName: _requiredString(map['fileName'], fieldName: 'fileName'),
      mimeType: _requiredString(map['mimeType'], fieldName: 'mimeType'),
      byteSize: _requiredInt(map['byteSize'], fieldName: 'byteSize'),
      storagePath: _requiredString(
        map['storagePath'],
        fieldName: 'storagePath',
      ),
      downloadUrl: _optionalString(map['downloadUrl']),
      uploadState: AttachmentUploadState.fromValue(map['uploadState']),
      width: _optionalInt(map['width'], fieldName: 'width'),
      height: _optionalInt(map['height'], fieldName: 'height'),
      duration: _optionalDuration(map['durationMs']),
      thumbnail: thumbnailMap == null
          ? null
          : AttachmentThumbnail.fromMap(thumbnailMap),
      createdAt: _requiredDateTime(map['createdAt'], fieldName: 'createdAt'),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'messageId': messageId,
      'conversationId': conversationId,
      'ownerUid': ownerUid,
      'type': type.serialized,
      'fileName': fileName,
      'mimeType': mimeType,
      'byteSize': byteSize,
      'storagePath': storagePath,
      'downloadUrl': downloadUrl,
      'uploadState': uploadState.serialized,
      'width': width,
      'height': height,
      'durationMs': duration?.inMilliseconds,
      'thumbnail': thumbnail?.toMap(),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  AttachmentEntity copyWith({
    String? id,
    String? messageId,
    String? conversationId,
    String? ownerUid,
    AttachmentType? type,
    String? fileName,
    String? mimeType,
    int? byteSize,
    String? storagePath,
    String? downloadUrl,
    bool clearDownloadUrl = false,
    AttachmentUploadState? uploadState,
    int? width,
    bool clearWidth = false,
    int? height,
    bool clearHeight = false,
    Duration? duration,
    bool clearDuration = false,
    AttachmentThumbnail? thumbnail,
    bool clearThumbnail = false,
    DateTime? createdAt,
  }) {
    return AttachmentEntity(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      conversationId: conversationId ?? this.conversationId,
      ownerUid: ownerUid ?? this.ownerUid,
      type: type ?? this.type,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      byteSize: byteSize ?? this.byteSize,
      storagePath: storagePath ?? this.storagePath,
      downloadUrl: clearDownloadUrl ? null : downloadUrl ?? this.downloadUrl,
      uploadState: uploadState ?? this.uploadState,
      width: clearWidth ? null : width ?? this.width,
      height: clearHeight ? null : height ?? this.height,
      duration: clearDuration ? null : duration ?? this.duration,
      thumbnail: clearThumbnail ? null : thumbnail ?? this.thumbnail,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  void _validateTypeSpecificMetadata() {
    if (type == AttachmentType.image) {
      if ((width == null) != (height == null)) {
        throw ArgumentError(
          'Image attachment width and height must be provided together.',
        );
      }
    }

    if (type == AttachmentType.video) {
      if ((width == null) != (height == null)) {
        throw ArgumentError(
          'Video attachment width and height must be provided together.',
        );
      }
    }

    if (type == AttachmentType.audio ||
        type == AttachmentType.voice ||
        type == AttachmentType.video) {
      if (duration != null && duration! <= Duration.zero) {
        throw ArgumentError('Media duration must be greater than zero.');
      }
    }

    if (type == AttachmentType.file && (width != null || height != null)) {
      throw ArgumentError(
        'General file attachment cannot contain image dimensions.',
      );
    }
  }

  void _validateUploadState() {
    if (uploadState == AttachmentUploadState.uploaded && downloadUrl == null) {
      throw ArgumentError('Uploaded attachment requires a downloadUrl.');
    }
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AttachmentEntity &&
            other.id == id &&
            other.messageId == messageId &&
            other.conversationId == conversationId &&
            other.ownerUid == ownerUid &&
            other.type == type &&
            other.fileName == fileName &&
            other.mimeType == mimeType &&
            other.byteSize == byteSize &&
            other.storagePath == storagePath &&
            other.downloadUrl == downloadUrl &&
            other.uploadState == uploadState &&
            other.width == width &&
            other.height == height &&
            other.duration == duration &&
            other.thumbnail == thumbnail &&
            other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    messageId,
    conversationId,
    ownerUid,
    type,
    fileName,
    mimeType,
    byteSize,
    storagePath,
    downloadUrl,
    uploadState,
    width,
    height,
    duration,
    thumbnail,
    createdAt,
  );

  @override
  String toString() {
    return 'AttachmentEntity('
        'id: $id, '
        'messageId: $messageId, '
        'conversationId: $conversationId, '
        'ownerUid: $ownerUid, '
        'type: ${type.serialized}, '
        'mimeType: $mimeType, '
        'byteSize: $byteSize, '
        'uploadState: ${uploadState.serialized}, '
        'hasDownloadUrl: ${downloadUrl != null}'
        ')';
  }

  static String _requiredString(Object? value, {required String fieldName}) {
    if (value is! String) {
      throw FormatException('AttachmentEntity.$fieldName must be a string.');
    }

    return _normalizeRequiredString(value, fieldName: fieldName);
  }

  static String _normalizeRequiredString(
    String value, {
    required String fieldName,
  }) {
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

  static String _normalizeFileName(String value) {
    final String normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError('Attachment fileName must not be empty.');
    }

    if (normalized == '.' ||
        normalized == '..' ||
        normalized.contains('/') ||
        normalized.contains('\\') ||
        normalized.contains('\u0000')) {
      throw ArgumentError(
        'Attachment fileName contains an unsafe path component.',
      );
    }

    return normalized;
  }

  static String _normalizeMimeType(String value) {
    final String normalized = value.trim().toLowerCase();

    if (normalized.isEmpty ||
        !normalized.contains('/') ||
        normalized.startsWith('/') ||
        normalized.endsWith('/')) {
      throw ArgumentError('Attachment mimeType is invalid.');
    }

    return normalized;
  }

  static String _normalizeStoragePath(String value) {
    final String normalized = value.trim();

    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        normalized.contains('//') ||
        normalized.contains('..')) {
      throw ArgumentError('Attachment storagePath is invalid.');
    }

    return normalized;
  }

  static String? _normalizeOptionalString(String? value) {
    if (value == null) {
      return null;
    }

    final String normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static int _validateByteSize(int value) {
    if (value < 0) {
      throw ArgumentError.value(
        value,
        'byteSize',
        'byteSize cannot be negative.',
      );
    }

    return value;
  }

  static int? _validateOptionalDimension(
    int? value, {
    required String fieldName,
  }) {
    if (value == null) {
      return null;
    }

    if (value <= 0) {
      throw ArgumentError.value(
        value,
        fieldName,
        '$fieldName must be greater than zero.',
      );
    }

    return value;
  }

  static Duration? _validateOptionalDuration(Duration? value) {
    if (value == null) {
      return null;
    }

    if (value <= Duration.zero) {
      throw ArgumentError.value(
        value,
        'duration',
        'duration must be greater than zero.',
      );
    }

    return value;
  }

  static String? _optionalString(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is! String) {
      throw const FormatException(
        'AttachmentEntity optional string field has invalid type.',
      );
    }

    final String normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static int _requiredInt(Object? value, {required String fieldName}) {
    final int? result = _optionalInt(value, fieldName: fieldName);

    if (result == null) {
      throw FormatException('AttachmentEntity.$fieldName is required.');
    }

    return result;
  }

  static int? _optionalInt(Object? value, {required String fieldName}) {
    if (value == null) {
      return null;
    }

    if (value is! num || value % 1 != 0) {
      throw FormatException('AttachmentEntity.$fieldName must be an integer.');
    }

    return value.toInt();
  }

  static Duration? _optionalDuration(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is! num || value % 1 != 0) {
      throw const FormatException(
        'AttachmentEntity.durationMs must be an integer.',
      );
    }

    final int milliseconds = value.toInt();

    if (milliseconds <= 0) {
      throw const FormatException(
        'AttachmentEntity.durationMs must be greater than zero.',
      );
    }

    return Duration(milliseconds: milliseconds);
  }

  static DateTime _requiredDateTime(
    Object? value, {
    required String fieldName,
  }) {
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }

    if (value is DateTime) {
      return value.toUtc();
    }

    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }

    if (value is String) {
      final DateTime? parsed = DateTime.tryParse(value);

      if (parsed != null) {
        return parsed.toUtc();
      }
    }

    throw FormatException(
      'AttachmentEntity.$fieldName has invalid timestamp data.',
    );
  }

  static Map<String, Object?>? _mapValue(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is Map<String, Object?>) {
      return value;
    }

    if (value is Map) {
      return value.map<String, Object?>((Object? key, Object? mapValue) {
        if (key is! String) {
          throw const FormatException(
            'AttachmentEntity nested map keys must be strings.',
          );
        }

        return MapEntry<String, Object?>(key, mapValue);
      });
    }

    throw const FormatException(
      'AttachmentEntity thumbnail field must be a map.',
    );
  }
}

// ============================================================================
// END OF FILE: lib/features/message/data/attachment_entity.dart
// ============================================================================
