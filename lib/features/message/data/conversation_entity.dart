// ============================================================================
// JR CALL
// File: conversation_entity.dart
// Location: lib/features/message/data/conversation_entity.dart
// Description:
// Canonical immutable conversation model for JR CALL Message Engine.
//
// Responsibilities:
// - Preserves canonical conversation identity.
// - Preserves Firebase UID participant ownership.
// - Stores durable conversation summary/index state.
// - Stores per-user unread information.
// - Supports direct and future group conversation types.
// - Supports archive/mute/pin/hidden-ready participant state.
// - Provides safe Firestore/local serialization.
// - Provides deterministic direct-conversation identity generation.
// - Provides immutable copyWith/value equality.
//
// Important:
// - Public JR CALL ID/username/email/phone are NEVER participant identities.
// - participantUids always contain canonical Firebase Auth UIDs.
// - Conversation summary never invents delivery/read/presence state.
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

import 'message_type.dart';

/// Canonical JR CALL conversation type.
enum ConversationType {
  direct,
  group;

  String get serialized => name;

  static ConversationType fromValue(Object? value) {
    if (value is ConversationType) {
      return value;
    }

    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'direct':
          return ConversationType.direct;
        case 'group':
          return ConversationType.group;
      }
    }

    throw FormatException('Unsupported conversation type: $value');
  }
}

/// Canonical immutable JR CALL conversation.
final class ConversationEntity {
  ConversationEntity({
    required String id,
    required this.type,
    required List<String> participantUids,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.lastMessageId,
    this.lastMessageType,
    this.lastMessagePreview,
    this.lastSenderUid,
    DateTime? lastMessageAt,
    Map<String, int> unreadCounts = const <String, int>{},
    Set<String> archivedByUids = const <String>{},
    Set<String> mutedByUids = const <String>{},
    Set<String> pinnedByUids = const <String>{},
    Set<String> hiddenByUids = const <String>{},
    DateTime? deletedAt,
  }) : id = _normalizeRequiredString(id, fieldName: 'id'),
       participantUids = List<String>.unmodifiable(
         _normalizeParticipants(participantUids, type: type),
       ),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc(),
       lastMessageAt = lastMessageAt?.toUtc(),
       unreadCounts = Map<String, int>.unmodifiable(
         _normalizeUnreadCounts(unreadCounts, participantUids),
       ),
       archivedByUids = Set<String>.unmodifiable(
         _normalizeParticipantStateSet(
           archivedByUids,
           participantUids,
           fieldName: 'archivedByUids',
         ),
       ),
       mutedByUids = Set<String>.unmodifiable(
         _normalizeParticipantStateSet(
           mutedByUids,
           participantUids,
           fieldName: 'mutedByUids',
         ),
       ),
       pinnedByUids = Set<String>.unmodifiable(
         _normalizeParticipantStateSet(
           pinnedByUids,
           participantUids,
           fieldName: 'pinnedByUids',
         ),
       ),
       hiddenByUids = Set<String>.unmodifiable(
         _normalizeParticipantStateSet(
           hiddenByUids,
           participantUids,
           fieldName: 'hiddenByUids',
         ),
       ),
       deletedAt = deletedAt?.toUtc() {
    _validateSummary();
    _validateDates();
  }

  /// Canonical conversation document ID.
  final String id;

  /// Direct or future-compatible group conversation.
  final ConversationType type;

  /// Canonical Firebase Auth UID participants.
  final List<String> participantUids;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Latest durable message summary fields.
  final String? lastMessageId;
  final MessageType? lastMessageType;
  final String? lastMessagePreview;
  final String? lastSenderUid;
  final DateTime? lastMessageAt;

  /// Per-participant unread durable-message count.
  final Map<String, int> unreadCounts;

  /// Per-participant inbox preferences/state.
  final Set<String> archivedByUids;
  final Set<String> mutedByUids;
  final Set<String> pinnedByUids;
  final Set<String> hiddenByUids;

  /// Optional durable conversation deletion/disabled marker.
  final DateTime? deletedAt;

  bool get isDirect => type == ConversationType.direct;

  bool get isGroup => type == ConversationType.group;

  bool get isDeleted => deletedAt != null;

  bool get hasLastMessage => lastMessageId != null;

  /// Returns whether [uid] is a canonical participant.
  bool hasParticipant(String uid) {
    final String normalized = uid.trim();
    return normalized.isNotEmpty && participantUids.contains(normalized);
  }

  /// Returns unread count for [uid].
  int unreadCountFor(String uid) {
    return unreadCounts[uid.trim()] ?? 0;
  }

  bool isArchivedFor(String uid) {
    return archivedByUids.contains(uid.trim());
  }

  bool isMutedFor(String uid) {
    return mutedByUids.contains(uid.trim());
  }

  bool isPinnedFor(String uid) {
    return pinnedByUids.contains(uid.trim());
  }

  bool isHiddenFor(String uid) {
    return hiddenByUids.contains(uid.trim());
  }

  /// Returns the other participant UID for a direct conversation.
  ///
  /// Throws when this is not a valid direct conversation or [currentUid]
  /// is not a participant.
  String otherParticipantUid(String currentUid) {
    if (!isDirect || participantUids.length != 2) {
      throw StateError(
        'otherParticipantUid is available only for direct conversations.',
      );
    }

    final String uid = _normalizeRequiredString(
      currentUid,
      fieldName: 'currentUid',
    );

    if (!participantUids.contains(uid)) {
      throw StateError(
        'Firebase UID is not a participant of this conversation.',
      );
    }

    return participantUids.firstWhere(
      (String participantUid) => participantUid != uid,
    );
  }

  /// Deterministically generates the same direct-conversation ID for the same
  /// exact pair of Firebase UIDs regardless of participant ordering.
  ///
  /// Length prefixes prevent delimiter ambiguity.
  static String directConversationId(String firstUid, String secondUid) {
    final String first = _normalizeRequiredString(
      firstUid,
      fieldName: 'firstUid',
    );

    final String second = _normalizeRequiredString(
      secondUid,
      fieldName: 'secondUid',
    );

    if (first == second) {
      throw ArgumentError(
        'Direct conversation requires two different Firebase UIDs.',
      );
    }

    final List<String> ordered = <String>[first, second]..sort();

    return 'direct_'
        '${ordered[0].length}_${ordered[0]}_'
        '${ordered[1].length}_${ordered[1]}';
  }

  /// Creates a direct conversation entity using deterministic identity.
  factory ConversationEntity.direct({
    required String firstUid,
    required String secondUid,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    final String first = _normalizeRequiredString(
      firstUid,
      fieldName: 'firstUid',
    );

    final String second = _normalizeRequiredString(
      secondUid,
      fieldName: 'secondUid',
    );

    if (first == second) {
      throw ArgumentError(
        'Direct conversation requires two different Firebase UIDs.',
      );
    }

    final List<String> participants = <String>[first, second]..sort();

    return ConversationEntity(
      id: directConversationId(first, second),
      type: ConversationType.direct,
      participantUids: participants,
      createdAt: createdAt,
      updatedAt: updatedAt,
      unreadCounts: <String, int>{first: 0, second: 0},
    );
  }

  /// Builds the canonical entity from Firestore/local map data.
  factory ConversationEntity.fromMap(Map<String, Object?> map, {String? id}) {
    final List<String> participantUids = _stringList(
      map['participantUids'],
      fieldName: 'participantUids',
    );

    final ConversationType type = ConversationType.fromValue(map['type']);

    return ConversationEntity(
      id: _requiredString(id ?? map['id'], fieldName: 'id'),
      type: type,
      participantUids: participantUids,
      createdAt: _requiredDateTime(map['createdAt'], fieldName: 'createdAt'),
      updatedAt: _requiredDateTime(map['updatedAt'], fieldName: 'updatedAt'),
      lastMessageId: _optionalString(map['lastMessageId']),
      lastMessageType: map['lastMessageType'] == null
          ? null
          : MessageType.fromValue(map['lastMessageType']),
      lastMessagePreview: _optionalString(
        map['lastMessagePreview'],
        trim: false,
      ),
      lastSenderUid: _optionalString(map['lastSenderUid']),
      lastMessageAt: _optionalDateTime(map['lastMessageAt']),
      unreadCounts: _intMap(map['unreadCounts'], fieldName: 'unreadCounts'),
      archivedByUids: _stringSet(
        map['archivedByUids'],
        fieldName: 'archivedByUids',
      ),
      mutedByUids: _stringSet(map['mutedByUids'], fieldName: 'mutedByUids'),
      pinnedByUids: _stringSet(map['pinnedByUids'], fieldName: 'pinnedByUids'),
      hiddenByUids: _stringSet(map['hiddenByUids'], fieldName: 'hiddenByUids'),
      deletedAt: _optionalDateTime(map['deletedAt']),
    );
  }

  /// Serializes this conversation into Firestore/local persistence format.
  Map<String, Object?> toMap({bool includeId = true}) {
    return <String, Object?>{
      if (includeId) 'id': id,
      'type': type.serialized,
      'participantUids': List<String>.from(participantUids),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'lastMessageId': lastMessageId,
      'lastMessageType': lastMessageType?.serialized,
      'lastMessagePreview': lastMessagePreview,
      'lastSenderUid': lastSenderUid,
      'lastMessageAt': lastMessageAt == null
          ? null
          : Timestamp.fromDate(lastMessageAt!),
      'unreadCounts': Map<String, int>.from(unreadCounts),
      'archivedByUids': archivedByUids.toList(growable: false),
      'mutedByUids': mutedByUids.toList(growable: false),
      'pinnedByUids': pinnedByUids.toList(growable: false),
      'hiddenByUids': hiddenByUids.toList(growable: false),
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
    };
  }

  ConversationEntity copyWith({
    String? id,
    ConversationType? type,
    List<String>? participantUids,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? lastMessageId,
    bool clearLastMessageId = false,
    MessageType? lastMessageType,
    bool clearLastMessageType = false,
    String? lastMessagePreview,
    bool clearLastMessagePreview = false,
    String? lastSenderUid,
    bool clearLastSenderUid = false,
    DateTime? lastMessageAt,
    bool clearLastMessageAt = false,
    Map<String, int>? unreadCounts,
    Set<String>? archivedByUids,
    Set<String>? mutedByUids,
    Set<String>? pinnedByUids,
    Set<String>? hiddenByUids,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return ConversationEntity(
      id: id ?? this.id,
      type: type ?? this.type,
      participantUids: participantUids ?? this.participantUids,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessageId: clearLastMessageId
          ? null
          : lastMessageId ?? this.lastMessageId,
      lastMessageType: clearLastMessageType
          ? null
          : lastMessageType ?? this.lastMessageType,
      lastMessagePreview: clearLastMessagePreview
          ? null
          : lastMessagePreview ?? this.lastMessagePreview,
      lastSenderUid: clearLastSenderUid
          ? null
          : lastSenderUid ?? this.lastSenderUid,
      lastMessageAt: clearLastMessageAt
          ? null
          : lastMessageAt ?? this.lastMessageAt,
      unreadCounts: unreadCounts ?? this.unreadCounts,
      archivedByUids: archivedByUids ?? this.archivedByUids,
      mutedByUids: mutedByUids ?? this.mutedByUids,
      pinnedByUids: pinnedByUids ?? this.pinnedByUids,
      hiddenByUids: hiddenByUids ?? this.hiddenByUids,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    );
  }

  void _validateSummary() {
    final String? normalizedLastMessageId = _normalizeOptionalString(
      lastMessageId,
    );

    final String? normalizedLastSenderUid = _normalizeOptionalString(
      lastSenderUid,
    );

    final bool anySummaryField =
        normalizedLastMessageId != null ||
        lastMessageType != null ||
        lastMessagePreview != null ||
        normalizedLastSenderUid != null ||
        lastMessageAt != null;

    if (!anySummaryField) {
      return;
    }

    if (normalizedLastMessageId == null ||
        lastMessageType == null ||
        normalizedLastSenderUid == null ||
        lastMessageAt == null) {
      throw ArgumentError(
        'Conversation last-message summary requires lastMessageId, '
        'lastMessageType, lastSenderUid and lastMessageAt together.',
      );
    }

    if (!participantUids.contains(normalizedLastSenderUid)) {
      throw ArgumentError(
        'lastSenderUid must be a canonical conversation participant UID.',
      );
    }
  }

  void _validateDates() {
    if (updatedAt.isBefore(createdAt)) {
      throw ArgumentError('Conversation updatedAt cannot be before createdAt.');
    }

    final DateTime? messageAt = lastMessageAt;

    if (messageAt != null && messageAt.isBefore(createdAt)) {
      throw ArgumentError(
        'Conversation lastMessageAt cannot be before createdAt.',
      );
    }

    final DateTime? deleted = deletedAt;

    if (deleted != null && deleted.isBefore(createdAt)) {
      throw ArgumentError('Conversation deletedAt cannot be before createdAt.');
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is ConversationEntity &&
        other.id == id &&
        other.type == type &&
        _listEquals(other.participantUids, participantUids) &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.lastMessageId == lastMessageId &&
        other.lastMessageType == lastMessageType &&
        other.lastMessagePreview == lastMessagePreview &&
        other.lastSenderUid == lastSenderUid &&
        other.lastMessageAt == lastMessageAt &&
        _mapEquals(other.unreadCounts, unreadCounts) &&
        _setEquals(other.archivedByUids, archivedByUids) &&
        _setEquals(other.mutedByUids, mutedByUids) &&
        _setEquals(other.pinnedByUids, pinnedByUids) &&
        _setEquals(other.hiddenByUids, hiddenByUids) &&
        other.deletedAt == deletedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    Object.hashAll(participantUids),
    createdAt,
    updatedAt,
    lastMessageId,
    lastMessageType,
    lastMessagePreview,
    lastSenderUid,
    lastMessageAt,
    _unorderedMapHash(unreadCounts),
    Object.hashAllUnordered(archivedByUids),
    Object.hashAllUnordered(mutedByUids),
    Object.hashAllUnordered(pinnedByUids),
    Object.hashAllUnordered(hiddenByUids),
    deletedAt,
  );

  @override
  String toString() {
    return 'ConversationEntity('
        'id: $id, '
        'type: ${type.serialized}, '
        'participantCount: ${participantUids.length}, '
        'lastMessageId: $lastMessageId, '
        'lastMessageType: ${lastMessageType?.serialized}, '
        'lastMessageAt: $lastMessageAt, '
        'updatedAt: $updatedAt, '
        'deletedAt: $deletedAt'
        ')';
  }

  static List<String> _normalizeParticipants(
    Iterable<String> values, {
    required ConversationType type,
  }) {
    final Set<String> seen = <String>{};

    for (final String value in values) {
      final String uid = _normalizeRequiredString(
        value,
        fieldName: 'participantUid',
      );

      if (!seen.add(uid)) {
        throw ArgumentError(
          'Conversation participantUids must not contain duplicates.',
        );
      }
    }

    final List<String> normalized = seen.toList(growable: false)..sort();

    if (type == ConversationType.direct && normalized.length != 2) {
      throw ArgumentError(
        'Direct conversation must contain exactly two Firebase UIDs.',
      );
    }

    if (type == ConversationType.group && normalized.length < 2) {
      throw ArgumentError(
        'Group conversation must contain at least two Firebase UIDs.',
      );
    }

    return normalized;
  }

  static Map<String, int> _normalizeUnreadCounts(
    Map<String, int> source,
    Iterable<String> participants,
  ) {
    final Set<String> participantSet = participants
        .map((String uid) => uid.trim())
        .toSet();

    final Map<String, int> normalized = <String, int>{
      for (final String uid in participantSet) uid: 0,
    };

    for (final MapEntry<String, int> entry in source.entries) {
      final String uid = _normalizeRequiredString(
        entry.key,
        fieldName: 'unreadCounts.uid',
      );

      if (!participantSet.contains(uid)) {
        throw ArgumentError(
          'Unread count owner must be a conversation participant.',
        );
      }

      if (entry.value < 0) {
        throw ArgumentError('Conversation unread count cannot be negative.');
      }

      normalized[uid] = entry.value;
    }

    return normalized;
  }

  static Set<String> _normalizeParticipantStateSet(
    Iterable<String> values,
    Iterable<String> participants, {
    required String fieldName,
  }) {
    final Set<String> participantSet = participants
        .map((String uid) => uid.trim())
        .toSet();

    final Set<String> normalized = <String>{};

    for (final String value in values) {
      final String uid = _normalizeRequiredString(value, fieldName: fieldName);

      if (!participantSet.contains(uid)) {
        throw ArgumentError(
          '$fieldName may contain conversation participant UIDs only.',
        );
      }

      normalized.add(uid);
    }

    return normalized;
  }

  static String _requiredString(Object? value, {required String fieldName}) {
    if (value is! String) {
      throw FormatException('ConversationEntity.$fieldName must be a string.');
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

  static String? _optionalString(Object? value, {bool trim = true}) {
    if (value == null) {
      return null;
    }

    if (value is! String) {
      throw const FormatException(
        'ConversationEntity optional string field has invalid type.',
      );
    }

    final String normalized = trim ? value.trim() : value;

    return normalized.isEmpty ? null : normalized;
  }

  static String? _normalizeOptionalString(String? value) {
    if (value == null) {
      return null;
    }

    final String normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static DateTime _requiredDateTime(
    Object? value, {
    required String fieldName,
  }) {
    final DateTime? date = _optionalDateTime(value);

    if (date == null) {
      throw FormatException('ConversationEntity.$fieldName is required.');
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

      if (parsed != null) {
        return parsed.toUtc();
      }
    }

    throw const FormatException(
      'ConversationEntity timestamp field has invalid type.',
    );
  }

  static List<String> _stringList(Object? value, {required String fieldName}) {
    if (value is! Iterable) {
      throw FormatException('ConversationEntity.$fieldName must be a list.');
    }

    return value
        .map<String>((Object? item) {
          if (item is! String) {
            throw FormatException(
              'ConversationEntity.$fieldName contains a non-string value.',
            );
          }

          return item;
        })
        .toList(growable: false);
  }

  static Set<String> _stringSet(Object? value, {required String fieldName}) {
    if (value == null) {
      return <String>{};
    }

    return _stringList(value, fieldName: fieldName).toSet();
  }

  static Map<String, int> _intMap(Object? value, {required String fieldName}) {
    if (value == null) {
      return <String, int>{};
    }

    if (value is! Map) {
      throw FormatException('ConversationEntity.$fieldName must be a map.');
    }

    final Map<String, int> result = <String, int>{};

    for (final MapEntry<Object?, Object?> entry in value.entries) {
      if (entry.key is! String || entry.value is! num) {
        throw FormatException(
          'ConversationEntity.$fieldName contains invalid data.',
        );
      }

      final num numericValue = entry.value! as num;

      if (numericValue % 1 != 0) {
        throw FormatException(
          'ConversationEntity.$fieldName values must be integers.',
        );
      }

      result[entry.key! as String] = numericValue.toInt();
    }

    return result;
  }

  static bool _listEquals<T>(List<T> first, List<T> second) {
    if (identical(first, second)) {
      return true;
    }

    if (first.length != second.length) {
      return false;
    }

    for (int index = 0; index < first.length; index++) {
      if (first[index] != second[index]) {
        return false;
      }
    }

    return true;
  }

  static bool _setEquals<T>(Set<T> first, Set<T> second) {
    return first.length == second.length && first.containsAll(second);
  }

  static bool _mapEquals<K, V>(Map<K, V> first, Map<K, V> second) {
    if (first.length != second.length) {
      return false;
    }

    for (final MapEntry<K, V> entry in first.entries) {
      if (!second.containsKey(entry.key) || second[entry.key] != entry.value) {
        return false;
      }
    }

    return true;
  }

  static int _unorderedMapHash<K, V>(Map<K, V> map) {
    return Object.hashAllUnordered(
      map.entries.map<int>(
        (MapEntry<K, V> entry) => Object.hash(entry.key, entry.value),
      ),
    );
  }
}

// ============================================================================
// END OF FILE: lib/features/message/data/conversation_entity.dart
// ============================================================================
