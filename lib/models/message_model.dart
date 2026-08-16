// ===========================================================
// JR CALL
// File: message_model.dart
// Location: lib/models/message_model.dart
// Master Step: 06/11
//
// Description:
// Production-safe JR CALL message data model.
//
// Guarantees:
// - Existing public constructor / fields / enums preserved.
// - Existing fromMap / toMap / copyWith / JSON APIs preserved.
// - Text / image / video / audio / file / location / contact /
//   sticker / system message types preserved.
// - Sending / sent / delivered / seen / failed preserved.
// - Legacy Firestore / JSON values parsed safely.
// - DateTime / Firestore Timestamp / epoch values supported.
// - Missing or malformed legacy fields use safe defaults.
// - No Firestore access, UI logic, fake data, or messaging engine.
// ===========================================================

import 'dart:convert';

// ===========================================================
// Message Type
// ===========================================================

enum MessageType {
  text,
  image,
  video,
  audio,
  file,
  location,
  contact,
  sticker,
  system,
}

// ===========================================================
// Message Status
// ===========================================================

enum MessageStatus { sending, sent, delivered, seen, failed }

// ===========================================================
// Message Model
// ===========================================================

class MessageModel {
  final String id;
  final String conversationId;
  final String senderId;
  final String receiverId;

  final MessageType type;

  final String message;
  final String mediaUrl;
  final String thumbnailUrl;
  final String fileName;

  /// File size in bytes.
  final int fileSize;

  final MessageStatus status;

  final bool isEdited;
  final bool isDeleted;
  final bool isEncrypted;

  final String? replyToMessageId;

  final DateTime createdAt;
  final DateTime? seenAt;

  const MessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.receiverId,
    required this.type,
    required this.message,
    required this.mediaUrl,
    required this.thumbnailUrl,
    required this.fileName,
    required this.fileSize,
    required this.status,
    required this.isEdited,
    required this.isDeleted,
    required this.isEncrypted,
    this.replyToMessageId,
    required this.createdAt,
    this.seenAt,
  });

  // ===========================================================
  // Initial
  // ===========================================================

  factory MessageModel.initial() {
    return MessageModel(
      id: '',
      conversationId: '',
      senderId: '',
      receiverId: '',
      type: MessageType.text,
      message: '',
      mediaUrl: '',
      thumbnailUrl: '',
      fileName: '',
      fileSize: 0,
      status: MessageStatus.sending,
      isEdited: false,
      isDeleted: false,
      isEncrypted: true,
      replyToMessageId: null,
      createdAt: DateTime.now(),
      seenAt: null,
    );
  }

  // ===========================================================
  // Copy
  // ===========================================================

  MessageModel copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? receiverId,
    MessageType? type,
    String? message,
    String? mediaUrl,
    String? thumbnailUrl,
    String? fileName,
    int? fileSize,
    MessageStatus? status,
    bool? isEdited,
    bool? isDeleted,
    bool? isEncrypted,
    String? replyToMessageId,
    DateTime? createdAt,
    DateTime? seenAt,
  }) {
    return MessageModel(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      type: type ?? this.type,
      message: message ?? this.message,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      status: status ?? this.status,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      createdAt: createdAt ?? this.createdAt,
      seenAt: seenAt ?? this.seenAt,
    );
  }

  // ===========================================================
  // Serialization
  // ===========================================================

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'conversationId': conversationId,
      'senderId': senderId,
      'receiverId': receiverId,
      'type': type.name,
      'message': message,
      'mediaUrl': mediaUrl,
      'thumbnailUrl': thumbnailUrl,
      'fileName': fileName,
      'fileSize': fileSize,
      'status': status.name,
      'isEdited': isEdited,
      'isDeleted': isDeleted,
      'isEncrypted': isEncrypted,
      'replyToMessageId': replyToMessageId,
      'createdAt': createdAt.toIso8601String(),
      'seenAt': seenAt?.toIso8601String(),
    };
  }

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: _string(
        _firstValue(map, const <String>['id', 'messageId', 'message_id']),
      ),
      conversationId: _string(
        _firstValue(map, const <String>[
          'conversationId',
          'conversation_id',
          'chatId',
          'threadId',
        ]),
      ),
      senderId: _string(
        _firstValue(map, const <String>[
          'senderId',
          'sender_id',
          'fromId',
          'from',
        ]),
      ),
      receiverId: _string(
        _firstValue(map, const <String>[
          'receiverId',
          'receiver_id',
          'recipientId',
          'toId',
          'to',
        ]),
      ),
      type: _messageType(
        _firstValue(map, const <String>['type', 'messageType']),
      ),
      message: _string(
        _firstValue(map, const <String>['message', 'text', 'body', 'content']),
      ),
      mediaUrl: _string(
        _firstValue(map, const <String>[
          'mediaUrl',
          'mediaURL',
          'attachmentUrl',
          'fileUrl',
          'url',
        ]),
      ),
      thumbnailUrl: _string(
        _firstValue(map, const <String>[
          'thumbnailUrl',
          'thumbnailURL',
          'thumbUrl',
          'previewUrl',
        ]),
      ),
      fileName: _string(
        _firstValue(map, const <String>[
          'fileName',
          'filename',
          'attachmentName',
        ]),
      ),
      fileSize: _integer(
        _firstValue(map, const <String>['fileSize', 'size', 'fileSizeBytes']),
      ),
      status: _messageStatus(
        _firstValue(map, const <String>[
          'status',
          'messageStatus',
          'deliveryStatus',
        ]),
      ),
      isEdited: _boolean(
        _firstValue(map, const <String>['isEdited', 'edited']),
      ),
      isDeleted: _boolean(
        _firstValue(map, const <String>['isDeleted', 'deleted']),
      ),
      isEncrypted: _boolean(
        _firstValue(map, const <String>['isEncrypted', 'encrypted']),
        fallback: true,
      ),
      replyToMessageId: _nullableString(
        _firstValue(map, const <String>[
          'replyToMessageId',
          'replyTo',
          'replyMessageId',
        ]),
      ),
      createdAt: _dateTime(
        _firstValue(map, const <String>[
          'createdAt',
          'timestamp',
          'sentAt',
          'created_at',
          'time',
        ]),
      ),
      seenAt: _nullableDateTime(
        _firstValue(map, const <String>['seenAt', 'readAt', 'seen_at']),
      ),
    );
  }

  // ===========================================================
  // JSON
  // ===========================================================

  String toJson() => jsonEncode(toMap());

  factory MessageModel.fromJson(String source) {
    try {
      final dynamic decoded = jsonDecode(source);

      if (decoded is Map<String, dynamic>) {
        return MessageModel.fromMap(decoded);
      }

      if (decoded is Map) {
        return MessageModel.fromMap(
          decoded.map<String, dynamic>((dynamic key, dynamic value) {
            return MapEntry<String, dynamic>(key.toString(), value);
          }),
        );
      }
    } on FormatException {
      // Invalid legacy JSON safely falls through.
    }

    return MessageModel.fromMap(const <String, dynamic>{});
  }

  // ===========================================================
  // Safe Legacy Parsing
  // ===========================================================

  static dynamic _firstValue(Map<String, dynamic> map, List<String> keys) {
    for (final String key in keys) {
      if (!map.containsKey(key)) {
        continue;
      }

      final dynamic value = map[key];

      if (value == null) {
        continue;
      }

      if (value is String && value.trim().isEmpty) {
        continue;
      }

      return value;
    }

    return null;
  }

  static String _string(dynamic value) {
    if (value == null) {
      return '';
    }

    return value.toString().trim();
  }

  static String? _nullableString(dynamic value) {
    if (value == null) {
      return null;
    }

    final String result = value.toString().trim();

    return result.isEmpty ? null : result;
  }

  static int _integer(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString().trim() ?? '') ?? 0;
  }

  static bool _boolean(dynamic value, {bool fallback = false}) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final String normalized = value?.toString().trim().toLowerCase() ?? '';

    switch (normalized) {
      case 'true':
      case '1':
      case 'yes':
      case 'y':
        return true;

      case 'false':
      case '0':
      case 'no':
      case 'n':
        return false;

      default:
        return fallback;
    }
  }

  static DateTime _dateTime(dynamic value) {
    return _nullableDateTime(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  static DateTime? _nullableDateTime(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value;
    }

    if (value is num) {
      return _dateTimeFromNumber(value);
    }

    // Firestore Timestamp-compatible parsing without requiring
    // cloud_firestore inside the model.
    try {
      final dynamic converted = value.toDate();

      if (converted is DateTime) {
        return converted;
      }
    } catch (_) {
      // Value is not a Firestore Timestamp-compatible object.
    }

    final String text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    final DateTime? parsed = DateTime.tryParse(text);

    if (parsed != null) {
      return parsed;
    }

    final num? numeric = num.tryParse(text);

    if (numeric != null) {
      return _dateTimeFromNumber(numeric);
    }

    return null;
  }

  static DateTime? _dateTimeFromNumber(num value) {
    try {
      final int raw = value.toInt();

      // Seconds since Unix epoch.
      if (raw.abs() < 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
      }

      // Microseconds since Unix epoch.
      if (raw.abs() >= 100000000000000) {
        return DateTime.fromMicrosecondsSinceEpoch(raw);
      }

      // Milliseconds since Unix epoch.
      return DateTime.fromMillisecondsSinceEpoch(raw);
    } on RangeError {
      return null;
    }
  }

  static String _enumText(dynamic value) {
    final String raw = value?.toString().trim().toLowerCase() ?? '';

    if (raw.isEmpty) {
      return '';
    }

    final int dotIndex = raw.lastIndexOf('.');

    final String normalized = dotIndex >= 0 ? raw.substring(dotIndex + 1) : raw;

    return normalized
        .replaceAll('-', '')
        .replaceAll('_', '')
        .replaceAll(' ', '');
  }

  static MessageType _messageType(dynamic value) {
    switch (_enumText(value)) {
      case 'image':
      case 'photo':
      case 'picture':
        return MessageType.image;

      case 'video':
        return MessageType.video;

      case 'audio':
      case 'voice':
      case 'voicemessage':
      case 'voicenote':
        return MessageType.audio;

      case 'file':
      case 'document':
      case 'attachment':
        return MessageType.file;

      case 'location':
        return MessageType.location;

      case 'contact':
        return MessageType.contact;

      case 'sticker':
        return MessageType.sticker;

      case 'system':
      case 'notification':
        return MessageType.system;

      case 'text':
      default:
        return MessageType.text;
    }
  }

  static MessageStatus _messageStatus(dynamic value) {
    switch (_enumText(value)) {
      case 'sent':
        return MessageStatus.sent;

      case 'delivered':
      case 'received':
        return MessageStatus.delivered;

      case 'seen':
      case 'read':
        return MessageStatus.seen;

      case 'failed':
      case 'error':
        return MessageStatus.failed;

      case 'sending':
      case 'pending':
      case 'queued':
      default:
        return MessageStatus.sending;
    }
  }

  // ===========================================================
  // Object
  // ===========================================================

  @override
  String toString() {
    return 'MessageModel('
        'id: $id, '
        'type: ${type.name}, '
        'status: ${status.name}'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is MessageModel &&
        other.id == id &&
        other.conversationId == conversationId;
  }

  @override
  int get hashCode => Object.hash(id, conversationId);
}

// ===========================================================
// END OF FILE
//
// COMPLETED: 6/11
// REMAINING: 5/11
//
// NEXT FILE: 07 — user_discovery_service.dart
// Location: lib/services/user_discovery_service.dart
// ===========================================================
