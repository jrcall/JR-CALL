// ============================================================================
// JR CALL
// File: reaction_entity.dart
// Location: lib/features/message/data/reaction_entity.dart
// Description:
// Canonical immutable message-reaction model for JR CALL Message Engine.
//
// Responsibilities:
// - Represents one participant-owned reaction on one durable message.
// - Preserves canonical conversation/message/Firebase UID identity.
// - Enforces one reaction record per user/message at the data-model level.
// - Supports create/update/remove repository workflows.
// - Provides safe Firestore/local serialization.
// - Provides immutable copyWith/value equality.
//
// Important:
// - userUid is always the reacting user's Firebase Auth UID.
// - Public JR CALL ID/username/email/phone are never reaction ownership IDs.
// - Reaction writes/deletes remain protected by Firebase Security Rules.
// - This file contains no Firestore collection ownership or UI logic.
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

/// Canonical immutable JR CALL message reaction.
final class ReactionEntity {
  ReactionEntity({
    required String messageId,
    required String conversationId,
    required String userUid,
    required String value,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : messageId = _normalizeRequiredIdentifier(
         messageId,
         fieldName: 'messageId',
       ),
       conversationId = _normalizeRequiredIdentifier(
         conversationId,
         fieldName: 'conversationId',
       ),
       userUid = _normalizeRequiredIdentifier(userUid, fieldName: 'userUid'),
       value = _normalizeReactionValue(value),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc() {
    if (this.updatedAt.isBefore(this.createdAt)) {
      throw ArgumentError('Reaction updatedAt cannot be before createdAt.');
    }
  }

  /// Canonical durable message ID.
  final String messageId;

  /// Canonical conversation ID.
  final String conversationId;

  /// Canonical Firebase Auth UID that owns this reaction.
  final String userUid;

  /// Emoji/reaction value.
  ///
  /// Product policy currently supports one active reaction value per
  /// user/message. Changing a reaction updates this same owned record.
  final String value;

  /// Time the reaction was first created.
  final DateTime createdAt;

  /// Time the reaction was most recently updated.
  final DateTime updatedAt;

  /// Canonical deterministic ownership key.
  ///
  /// Firestore reaction documents may use the reacting Firebase UID directly
  /// as their document ID, but this key is useful for local/cache deduplication.
  String get ownershipKey => '$conversationId::$messageId::$userUid';

  /// Returns true when this reaction belongs to [uid].
  bool isOwnedBy(String uid) {
    final String normalized = uid.trim();
    return normalized.isNotEmpty && normalized == userUid;
  }

  /// Creates a reaction from Firestore/local map data.
  factory ReactionEntity.fromMap(Map<String, Object?> map, {String? userUid}) {
    return ReactionEntity(
      messageId: _requiredString(map['messageId'], fieldName: 'messageId'),
      conversationId: _requiredString(
        map['conversationId'],
        fieldName: 'conversationId',
      ),
      userUid: _requiredString(userUid ?? map['userUid'], fieldName: 'userUid'),
      value: _requiredString(
        map['value'] ?? map['reaction'] ?? map['emoji'],
        fieldName: 'value',
      ),
      createdAt: _requiredDateTime(map['createdAt'], fieldName: 'createdAt'),
      updatedAt: _requiredDateTime(map['updatedAt'], fieldName: 'updatedAt'),
    );
  }

  /// Serializes this reaction into Firestore/local persistence format.
  ///
  /// [includeUserUid] may be false when the reacting UID is already the
  /// Firestore reaction document ID. Keeping it true is useful for local
  /// persistence and deterministic tracing.
  Map<String, Object?> toMap({bool includeUserUid = true}) {
    return <String, Object?>{
      'messageId': messageId,
      'conversationId': conversationId,
      if (includeUserUid) 'userUid': userUid,
      'value': value,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  ReactionEntity copyWith({
    String? messageId,
    String? conversationId,
    String? userUid,
    String? value,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ReactionEntity(
      messageId: messageId ?? this.messageId,
      conversationId: conversationId ?? this.conversationId,
      userUid: userUid ?? this.userUid,
      value: value ?? this.value,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ReactionEntity &&
            other.messageId == messageId &&
            other.conversationId == conversationId &&
            other.userUid == userUid &&
            other.value == value &&
            other.createdAt == createdAt &&
            other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    messageId,
    conversationId,
    userUid,
    value,
    createdAt,
    updatedAt,
  );

  @override
  String toString() {
    return 'ReactionEntity('
        'messageId: $messageId, '
        'conversationId: $conversationId, '
        'userUid: $userUid, '
        'value: $value, '
        'createdAt: $createdAt, '
        'updatedAt: $updatedAt'
        ')';
  }

  static String _requiredString(Object? value, {required String fieldName}) {
    if (value is! String) {
      throw FormatException('ReactionEntity.$fieldName must be a string.');
    }

    return _normalizeRequiredIdentifier(value, fieldName: fieldName);
  }

  static String _normalizeRequiredIdentifier(
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

  static String _normalizeReactionValue(String value) {
    final String normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(
        value,
        'value',
        'Reaction value must not be empty.',
      );
    }

    if (normalized.length > 32) {
      throw ArgumentError.value(value, 'value', 'Reaction value is too long.');
    }

    if (_containsControlCharacter(normalized)) {
      throw ArgumentError.value(
        value,
        'value',
        'Reaction value contains unsupported control characters.',
      );
    }

    return normalized;
  }

  static bool _containsControlCharacter(String value) {
    for (final int rune in value.runes) {
      if ((rune >= 0x00 && rune <= 0x08) ||
          rune == 0x0B ||
          rune == 0x0C ||
          (rune >= 0x0E && rune <= 0x1F) ||
          rune == 0x7F) {
        return true;
      }
    }

    return false;
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
      'ReactionEntity.$fieldName has invalid timestamp data.',
    );
  }
}

// ============================================================================
// END OF FILE: lib/features/message/data/reaction_entity.dart
// ============================================================================
