// ============================================================================
// JR CALL
// File: message_entity.dart
// Location: lib/features/message/data/message_entity.dart
// Description:
// Canonical immutable durable-message model for JR CALL Message Engine.
//
// Responsibilities:
// - Owns canonical durable message data shape.
// - Preserves Firebase UID-based sender identity.
// - Preserves canonical message and conversation IDs.
// - Supports optimistic/local and committed server state.
// - Supports reply/edit/delete metadata.
// - Supports safe failure metadata.
// - Provides Firestore/local map serialization.
// - Provides immutable copyWith.
// - Normalizes timestamps and nullable values safely.
//
// Important:
// - Live Chat drafts are NOT represented by this durable model.
// - Secrets/credentials must never be stored in this entity.
// - Canonical message ID must remain unchanged for the lifetime of a message.
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

import 'attachment_entity.dart';
import 'message_status.dart';
import 'message_type.dart';

/// Canonical immutable JR CALL durable message.
final class MessageEntity {
  const MessageEntity({
    required this.id,
    required this.conversationId,
    required this.senderUid,
    required this.type,
    required this.status,
    required this.clientCreatedAt,
    this.text,
    this.attachment,
    this.replyToMessageId,
    this.replyToSenderUid,
    this.replyPreview,
    this.replyType,
    this.serverCreatedAt,
    this.editedAt,
    this.deletedAt,
    this.localOnly = false,
    this.failureCode,
    this.failureMessage,
  });

  /// Canonical Firestore message document ID.
  final String id;

  /// Canonical conversation identity.
  final String conversationId;

  /// Canonical Firebase Auth UID of the sender.
  final String senderUid;

  /// Durable message type.
  final MessageType type;

  /// Optional durable text body.
  final String? text;

  /// Current monotonic client message lifecycle status.
  final MessageStatus status;

  /// Optional durable attachment metadata.
  final AttachmentEntity? attachment;

  /// Canonical replied-to message ID.
  final String? replyToMessageId;

  /// Firebase UID of replied-to sender.
  final String? replyToSenderUid;

  /// Safe durable preview of replied-to content.
  final String? replyPreview;

  /// Type of replied-to durable message.
  final MessageType? replyType;

  /// Client creation time used for optimistic placement.
  final DateTime clientCreatedAt;

  /// Server-accepted durable creation time.
  final DateTime? serverCreatedAt;

  /// Last accepted edit time.
  final DateTime? editedAt;

  /// Durable soft-delete/tombstone time.
  final DateTime? deletedAt;

  /// True while the entity only exists in local optimistic state.
  final bool localOnly;

  /// Sanitized failure category/code.
  final String? failureCode;

  /// Optional safe failure description.
  final String? failureMessage;

  /// Whether this message is a durable tombstone/deleted message.
  bool get isDeleted => deletedAt != null;

  /// Whether this entity still has local-only/optimistic state.
  bool get isOptimistic =>
      localOnly ||
      status == MessageStatus.queued ||
      status == MessageStatus.sending;

  /// Whether this message currently represents a failed outgoing operation.
  bool get isFailed => status == MessageStatus.failed;

  /// Whether durable backend acceptance has been confirmed.
  bool get isCommitted =>
      serverCreatedAt != null ||
      status == MessageStatus.sent ||
      status == MessageStatus.delivered ||
      status == MessageStatus.read;

  /// Best timestamp for deterministic timeline placement.
  DateTime get timelineTimestamp =>
      (serverCreatedAt ?? clientCreatedAt).toUtc();

  /// Creates an immutable entity from persisted/local map data.
  ///
  /// [id] should normally be the Firestore document ID and remains canonical.
  factory MessageEntity.fromMap(Map<String, Object?> map, {String? id}) {
    final String canonicalId = _requiredString(
      id ?? map['id'],
      fieldName: 'id',
    );

    final String conversationId = _requiredString(
      map['conversationId'],
      fieldName: 'conversationId',
    );

    final String senderUid = _requiredString(
      map['senderUid'],
      fieldName: 'senderUid',
    );

    final MessageType type = MessageType.fromValue(map['type']);

    final MessageStatus status = MessageStatus.fromValue(map['status']);

    final DateTime clientCreatedAt = _requiredDateTime(
      map['clientCreatedAt'],
      fieldName: 'clientCreatedAt',
    );

    final Map<String, Object?>? attachmentMap = _mapValue(map['attachment']);

    final String? text = _optionalString(map['text'], trim: false);

    final String? replyToMessageId = _optionalString(map['replyToMessageId']);

    final String? replyToSenderUid = _optionalString(map['replyToSenderUid']);

    final String? replyPreview = _optionalString(
      map['replyPreview'],
      trim: false,
    );

    final MessageType? replyType = map['replyType'] == null
        ? null
        : MessageType.fromValue(map['replyType']);

    return MessageEntity(
      id: canonicalId,
      conversationId: conversationId,
      senderUid: senderUid,
      type: type,
      text: text,
      status: status,
      attachment: attachmentMap == null
          ? null
          : AttachmentEntity.fromMap(attachmentMap),
      replyToMessageId: replyToMessageId,
      replyToSenderUid: replyToSenderUid,
      replyPreview: replyPreview,
      replyType: replyType,
      clientCreatedAt: clientCreatedAt,
      serverCreatedAt: _optionalDateTime(map['serverCreatedAt']),
      editedAt: _optionalDateTime(map['editedAt']),
      deletedAt: _optionalDateTime(map['deletedAt']),
      localOnly: _boolValue(map['localOnly'], fallback: false),
      failureCode: _optionalString(map['failureCode']),
      failureMessage: _optionalString(map['failureMessage'], trim: false),
    );
  }

  /// Serializes this entity into durable map form.
  ///
  /// [includeId] may be false when the map is used as the Firestore document
  /// body because [id] is already the document ID.
  ///
  /// [includeLocalFields] should be false for remote durable writes so
  /// local-only state/failure metadata does not leak into Firestore unless
  /// explicitly intended by repository policy.
  Map<String, Object?> toMap({
    bool includeId = true,
    bool includeLocalFields = true,
  }) {
    final Map<String, Object?> map = <String, Object?>{
      if (includeId) 'id': id,
      'conversationId': conversationId,
      'senderUid': senderUid,
      'type': type.serialized,
      'text': text,
      'status': status.serialized,
      'attachment': attachment?.toMap(),
      'replyToMessageId': replyToMessageId,
      'replyToSenderUid': replyToSenderUid,
      'replyPreview': replyPreview,
      'replyType': replyType?.serialized,
      'clientCreatedAt': Timestamp.fromDate(clientCreatedAt.toUtc()),
      'serverCreatedAt': serverCreatedAt == null
          ? null
          : Timestamp.fromDate(serverCreatedAt!.toUtc()),
      'editedAt': editedAt == null
          ? null
          : Timestamp.fromDate(editedAt!.toUtc()),
      'deletedAt': deletedAt == null
          ? null
          : Timestamp.fromDate(deletedAt!.toUtc()),
    };

    if (includeLocalFields) {
      map['localOnly'] = localOnly;
      map['failureCode'] = failureCode;
      map['failureMessage'] = failureMessage;
    }

    return map;
  }

  MessageEntity copyWith({
    String? id,
    String? conversationId,
    String? senderUid,
    MessageType? type,
    String? text,
    bool clearText = false,
    MessageStatus? status,
    AttachmentEntity? attachment,
    bool clearAttachment = false,
    String? replyToMessageId,
    bool clearReplyToMessageId = false,
    String? replyToSenderUid,
    bool clearReplyToSenderUid = false,
    String? replyPreview,
    bool clearReplyPreview = false,
    MessageType? replyType,
    bool clearReplyType = false,
    DateTime? clientCreatedAt,
    DateTime? serverCreatedAt,
    bool clearServerCreatedAt = false,
    DateTime? editedAt,
    bool clearEditedAt = false,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    bool? localOnly,
    String? failureCode,
    bool clearFailureCode = false,
    String? failureMessage,
    bool clearFailureMessage = false,
  }) {
    return MessageEntity(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderUid: senderUid ?? this.senderUid,
      type: type ?? this.type,
      text: clearText ? null : text ?? this.text,
      status: status ?? this.status,
      attachment: clearAttachment ? null : attachment ?? this.attachment,
      replyToMessageId: clearReplyToMessageId
          ? null
          : replyToMessageId ?? this.replyToMessageId,
      replyToSenderUid: clearReplyToSenderUid
          ? null
          : replyToSenderUid ?? this.replyToSenderUid,
      replyPreview: clearReplyPreview
          ? null
          : replyPreview ?? this.replyPreview,
      replyType: clearReplyType ? null : replyType ?? this.replyType,
      clientCreatedAt: (clientCreatedAt ?? this.clientCreatedAt).toUtc(),
      serverCreatedAt: clearServerCreatedAt
          ? null
          : (serverCreatedAt ?? this.serverCreatedAt)?.toUtc(),
      editedAt: clearEditedAt ? null : (editedAt ?? this.editedAt)?.toUtc(),
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt)?.toUtc(),
      localOnly: localOnly ?? this.localOnly,
      failureCode: clearFailureCode ? null : failureCode ?? this.failureCode,
      failureMessage: clearFailureMessage
          ? null
          : failureMessage ?? this.failureMessage,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is MessageEntity &&
        other.id == id &&
        other.conversationId == conversationId &&
        other.senderUid == senderUid &&
        other.type == type &&
        other.text == text &&
        other.status == status &&
        other.attachment == attachment &&
        other.replyToMessageId == replyToMessageId &&
        other.replyToSenderUid == replyToSenderUid &&
        other.replyPreview == replyPreview &&
        other.replyType == replyType &&
        other.clientCreatedAt.toUtc() == clientCreatedAt.toUtc() &&
        other.serverCreatedAt?.toUtc() == serverCreatedAt?.toUtc() &&
        other.editedAt?.toUtc() == editedAt?.toUtc() &&
        other.deletedAt?.toUtc() == deletedAt?.toUtc() &&
        other.localOnly == localOnly &&
        other.failureCode == failureCode &&
        other.failureMessage == failureMessage;
  }

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    senderUid,
    type,
    text,
    status,
    attachment,
    replyToMessageId,
    replyToSenderUid,
    replyPreview,
    replyType,
    clientCreatedAt.toUtc(),
    serverCreatedAt?.toUtc(),
    editedAt?.toUtc(),
    deletedAt?.toUtc(),
    localOnly,
    failureCode,
    failureMessage,
  );

  @override
  String toString() {
    return 'MessageEntity('
        'id: $id, '
        'conversationId: $conversationId, '
        'senderUid: $senderUid, '
        'type: ${type.serialized}, '
        'status: ${status.serialized}, '
        'hasText: ${text?.isNotEmpty == true}, '
        'hasAttachment: ${attachment != null}, '
        'serverCreatedAt: $serverCreatedAt, '
        'editedAt: $editedAt, '
        'deletedAt: $deletedAt, '
        'localOnly: $localOnly, '
        'failureCode: $failureCode'
        ')';
  }

  static String _requiredString(Object? value, {required String fieldName}) {
    if (value is! String) {
      throw FormatException('MessageEntity.$fieldName must be a string.');
    }

    final String normalized = value.trim();

    if (normalized.isEmpty) {
      throw FormatException('MessageEntity.$fieldName must not be empty.');
    }

    return normalized;
  }

  static String? _optionalString(Object? value, {bool trim = true}) {
    if (value == null) {
      return null;
    }

    if (value is! String) {
      throw FormatException(
        'MessageEntity optional string field has invalid type.',
      );
    }

    final String normalized = trim ? value.trim() : value;

    if (normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  static bool _boolValue(Object? value, {required bool fallback}) {
    if (value == null) {
      return fallback;
    }

    if (value is bool) {
      return value;
    }

    throw FormatException('MessageEntity boolean field has invalid type.');
  }

  static DateTime _requiredDateTime(
    Object? value, {
    required String fieldName,
  }) {
    final DateTime? date = _optionalDateTime(value);

    if (date == null) {
      throw FormatException('MessageEntity.$fieldName is required.');
    }

    return date;
  }

  static DateTime? _optionalDateTime(Object? value) {
    if (value == null) {
      return null;
    }

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
      return parsed?.toUtc();
    }

    throw FormatException('MessageEntity timestamp field has invalid type.');
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
            'MessageEntity nested map keys must be strings.',
          );
        }

        return MapEntry<String, Object?>(key, mapValue);
      });
    }

    throw const FormatException(
      'MessageEntity attachment field must be a map.',
    );
  }
}

// ============================================================================
// END OF FILE: lib/features/message/data/message_entity.dart
// ============================================================================
