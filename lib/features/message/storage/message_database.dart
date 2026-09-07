// ============================================================================
// JR CALL
// File: message_database.dart
// Location: lib/features/message/storage/message_database.dart
// Description:
// Typed local/offline persistence abstraction for JR CALL Message Engine.
//
// Responsibilities:
// - Stores locally known durable MessageEntity records.
// - Stores queued/failed outgoing messages for retry/recovery.
// - Stores bounded conversation cache.
// - Stores bounded paginated message cache.
// - Supports safe immutable local mutations.
// - Deduplicates messages by canonical message ID.
// - Never invents delivered/read state.
// - Never performs Firestore or Firebase Storage operations.
//
// Current local strategy:
// JR CALL currently has no dedicated SQL/Isar/Hive dependency in the frozen
// package contract. This file therefore provides a dependency-free bounded
// in-memory implementation. Durable server/offline persistence remains owned
// by Firebase/Firestore once messages are committed. A future disk database
// may implement the same frozen MessageDatabase contract without changing
// controllers/repositories.
//
// Important:
// - Canonical message ID is the deduplication key.
// - Canonical Firebase UID remains sender/owner identity.
// - No UI concerns.
// - No new package dependency.
// ============================================================================

import 'dart:collection';

import '../data/conversation_entity.dart';
import '../data/message_entity.dart';
import '../data/message_status.dart';

/// Typed local persistence contract used by the Message domain.
///
/// Implementations must:
/// - deduplicate messages by [MessageEntity.id],
/// - keep conversation/message ownership intact,
/// - return immutable snapshots,
/// - never fake server delivery/read acknowledgement,
/// - remain bounded in memory/storage.
abstract interface class MessageDatabase {
  /// Returns one locally cached message or `null` when unavailable.
  Future<MessageEntity?> getMessage({
    required String conversationId,
    required String messageId,
  });

  /// Returns the newest cached messages for [conversationId].
  ///
  /// The returned list is chronological from oldest -> newest.
  Future<List<MessageEntity>> getMessages({
    required String conversationId,
    int limit = 50,
  });

  /// Returns cached messages older than [before].
  ///
  /// The returned list is chronological from oldest -> newest.
  Future<List<MessageEntity>> getMessagesBefore({
    required String conversationId,
    required DateTime before,
    int limit = 50,
  });

  /// Inserts or replaces one message using canonical message ID.
  Future<void> upsertMessage(MessageEntity message);

  /// Inserts or replaces multiple messages.
  Future<void> upsertMessages(Iterable<MessageEntity> messages);

  /// Removes one local message record only.
  ///
  /// This does not perform a remote/server delete.
  Future<void> removeMessage({
    required String conversationId,
    required String messageId,
  });

  /// Removes all locally cached messages for one conversation.
  Future<void> clearConversationMessages(String conversationId);

  /// Returns locally recoverable outgoing messages.
  ///
  /// Only `queued` and `failed` records are returned.
  Future<List<MessageEntity>> getPendingOutgoingMessages({
    String? conversationId,
  });

  /// Stores/replaces a conversation cache record.
  Future<void> upsertConversation(ConversationEntity conversation);

  /// Stores/replaces multiple conversation cache records.
  Future<void> upsertConversations(Iterable<ConversationEntity> conversations);

  /// Returns one locally cached conversation or `null`.
  Future<ConversationEntity?> getConversation(String conversationId);

  /// Returns locally cached conversations ordered newest first.
  Future<List<ConversationEntity>> getConversations({int limit = 50});

  /// Removes one local conversation cache record and its cached messages.
  Future<void> removeConversation(String conversationId);

  /// Clears all local Message Engine data.
  Future<void> clear();

  /// Releases implementation-owned resources.
  Future<void> dispose();
}

/// Dependency-free bounded local Message Engine database.
///
/// This implementation intentionally does not add a new persistence package.
/// It is suitable as the current local optimistic/retry cache and can later be
/// replaced by a disk-backed implementation through [MessageDatabase] without
/// changing the frozen repository/controller contract.
final class InMemoryMessageDatabase implements MessageDatabase {
  InMemoryMessageDatabase({
    this.maxConversations = 100,
    this.maxMessagesPerConversation = 300,
  }) {
    if (maxConversations <= 0) {
      throw ArgumentError.value(
        maxConversations,
        'maxConversations',
        'maxConversations must be greater than zero.',
      );
    }

    if (maxMessagesPerConversation <= 0) {
      throw ArgumentError.value(
        maxMessagesPerConversation,
        'maxMessagesPerConversation',
        'maxMessagesPerConversation must be greater than zero.',
      );
    }
  }

  /// Maximum number of cached conversation entities.
  final int maxConversations;

  /// Maximum number of cached durable message records per conversation.
  final int maxMessagesPerConversation;

  final LinkedHashMap<String, ConversationEntity> _conversations =
      LinkedHashMap<String, ConversationEntity>();

  final Map<String, LinkedHashMap<String, MessageEntity>>
  _messagesByConversation = <String, LinkedHashMap<String, MessageEntity>>{};

  bool _disposed = false;

  @override
  Future<MessageEntity?> getMessage({
    required String conversationId,
    required String messageId,
  }) async {
    _ensureActive();

    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );
    final String message = _normalizeId(messageId, fieldName: 'messageId');

    return _messagesByConversation[conversation]?[message];
  }

  @override
  Future<List<MessageEntity>> getMessages({
    required String conversationId,
    int limit = 50,
  }) async {
    _ensureActive();
    _validateLimit(limit);

    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final Iterable<MessageEntity> values =
        _messagesByConversation[conversation]?.values ??
        const <MessageEntity>[];

    final List<MessageEntity> sorted = values.toList(growable: false)
      ..sort(_compareMessages);

    if (sorted.length <= limit) {
      return List<MessageEntity>.unmodifiable(sorted);
    }

    return List<MessageEntity>.unmodifiable(
      sorted.sublist(sorted.length - limit),
    );
  }

  @override
  Future<List<MessageEntity>> getMessagesBefore({
    required String conversationId,
    required DateTime before,
    int limit = 50,
  }) async {
    _ensureActive();
    _validateLimit(limit);

    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final DateTime boundary = before.toUtc();

    final Iterable<MessageEntity> values =
        _messagesByConversation[conversation]?.values ??
        const <MessageEntity>[];

    final List<MessageEntity> matching =
        values
            .where(
              (MessageEntity message) =>
                  _effectiveTimestamp(message).isBefore(boundary),
            )
            .toList(growable: false)
          ..sort(_compareMessages);

    if (matching.length <= limit) {
      return List<MessageEntity>.unmodifiable(matching);
    }

    return List<MessageEntity>.unmodifiable(
      matching.sublist(matching.length - limit),
    );
  }

  @override
  Future<void> upsertMessage(MessageEntity message) async {
    _ensureActive();
    _validateMessageIdentity(message);
    _upsertMessageInternal(message);
  }

  @override
  Future<void> upsertMessages(Iterable<MessageEntity> messages) async {
    _ensureActive();

    for (final MessageEntity message in messages) {
      _validateMessageIdentity(message);
      _upsertMessageInternal(message);
    }
  }

  @override
  Future<void> removeMessage({
    required String conversationId,
    required String messageId,
  }) async {
    _ensureActive();

    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );
    final String message = _normalizeId(messageId, fieldName: 'messageId');

    final LinkedHashMap<String, MessageEntity>? bucket =
        _messagesByConversation[conversation];

    if (bucket == null) {
      return;
    }

    bucket.remove(message);

    if (bucket.isEmpty) {
      _messagesByConversation.remove(conversation);
    }
  }

  @override
  Future<void> clearConversationMessages(String conversationId) async {
    _ensureActive();

    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    _messagesByConversation.remove(conversation);
  }

  @override
  Future<List<MessageEntity>> getPendingOutgoingMessages({
    String? conversationId,
  }) async {
    _ensureActive();

    final String? normalizedConversation = conversationId == null
        ? null
        : _normalizeId(conversationId, fieldName: 'conversationId');

    final List<MessageEntity> result = <MessageEntity>[];

    if (normalizedConversation != null) {
      final Iterable<MessageEntity> messages =
          _messagesByConversation[normalizedConversation]?.values ??
          const <MessageEntity>[];

      for (final MessageEntity message in messages) {
        if (_isPendingForRetry(message.status)) {
          result.add(message);
        }
      }
    } else {
      for (final LinkedHashMap<String, MessageEntity> bucket
          in _messagesByConversation.values) {
        for (final MessageEntity message in bucket.values) {
          if (_isPendingForRetry(message.status)) {
            result.add(message);
          }
        }
      }
    }

    result.sort(_compareMessages);

    return List<MessageEntity>.unmodifiable(result);
  }

  @override
  Future<void> upsertConversation(ConversationEntity conversation) async {
    _ensureActive();
    _upsertConversationInternal(conversation);
  }

  @override
  Future<void> upsertConversations(
    Iterable<ConversationEntity> conversations,
  ) async {
    _ensureActive();

    for (final ConversationEntity conversation in conversations) {
      _upsertConversationInternal(conversation);
    }
  }

  @override
  Future<ConversationEntity?> getConversation(String conversationId) async {
    _ensureActive();

    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final ConversationEntity? entity = _conversations[conversation];

    if (entity != null) {
      _touchConversation(conversation, entity);
    }

    return entity;
  }

  @override
  Future<List<ConversationEntity>> getConversations({int limit = 50}) async {
    _ensureActive();
    _validateLimit(limit);

    final List<ConversationEntity> conversations = _conversations.values.toList(
      growable: false,
    )..sort(_compareConversations);

    if (conversations.length <= limit) {
      return List<ConversationEntity>.unmodifiable(conversations);
    }

    return List<ConversationEntity>.unmodifiable(
      conversations.sublist(0, limit),
    );
  }

  @override
  Future<void> removeConversation(String conversationId) async {
    _ensureActive();

    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    _conversations.remove(conversation);
    _messagesByConversation.remove(conversation);
  }

  @override
  Future<void> clear() async {
    _ensureActive();

    _conversations.clear();
    _messagesByConversation.clear();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _conversations.clear();
    _messagesByConversation.clear();
  }

  void _upsertMessageInternal(MessageEntity incoming) {
    final LinkedHashMap<String, MessageEntity> bucket = _messagesByConversation
        .putIfAbsent(
          incoming.conversationId,
          () => LinkedHashMap<String, MessageEntity>(),
        );

    final MessageEntity? existing = bucket[incoming.id];

    if (existing == null) {
      bucket[incoming.id] = incoming;
    } else {
      bucket[incoming.id] = _selectSaferVersion(existing, incoming);
    }

    _trimMessageBucket(bucket);
  }

  MessageEntity _selectSaferVersion(
    MessageEntity existing,
    MessageEntity incoming,
  ) {
    if (existing.conversationId != incoming.conversationId ||
        existing.id != incoming.id) {
      throw StateError(
        'Local message reconciliation requires the same canonical '
        'conversationId and messageId.',
      );
    }

    if (existing.senderUid != incoming.senderUid) {
      throw StateError(
        'Canonical message senderUid cannot change during reconciliation.',
      );
    }

    final MessageStatus oldStatus = existing.status;
    final MessageStatus newStatus = incoming.status;

    if (oldStatus == MessageStatus.read && newStatus != MessageStatus.read) {
      return existing;
    }

    if (oldStatus == MessageStatus.delivered &&
        newStatus.rank < MessageStatus.delivered.rank &&
        newStatus != MessageStatus.failed) {
      return existing;
    }

    if (oldStatus.isCommitted && newStatus == MessageStatus.failed) {
      return existing;
    }

    if (oldStatus != MessageStatus.failed &&
        newStatus != MessageStatus.failed &&
        newStatus.rank < oldStatus.rank) {
      return existing;
    }

    return incoming;
  }

  void _upsertConversationInternal(ConversationEntity conversation) {
    final String id = _normalizeId(
      conversation.id,
      fieldName: 'conversation.id',
    );

    final ConversationEntity? existing = _conversations.remove(id);

    if (existing != null &&
        conversation.updatedAt.isBefore(existing.updatedAt)) {
      _conversations[id] = existing;
      return;
    }

    _conversations[id] = conversation;
    _trimConversations();
  }

  void _touchConversation(String id, ConversationEntity conversation) {
    _conversations.remove(id);
    _conversations[id] = conversation;
  }

  void _trimConversations() {
    while (_conversations.length > maxConversations) {
      final String oldestKey = _conversations.keys.first;
      _conversations.remove(oldestKey);
      _messagesByConversation.remove(oldestKey);
    }
  }

  void _trimMessageBucket(LinkedHashMap<String, MessageEntity> bucket) {
    if (bucket.length <= maxMessagesPerConversation) {
      return;
    }

    final List<MessageEntity> ordered = bucket.values.toList(growable: false)
      ..sort(_compareMessages);

    final Set<String> protectedIds = <String>{
      for (final MessageEntity message in ordered)
        if (_isPendingForRetry(message.status)) message.id,
    };

    for (final MessageEntity message in ordered) {
      if (bucket.length <= maxMessagesPerConversation) {
        break;
      }

      if (protectedIds.contains(message.id)) {
        continue;
      }

      bucket.remove(message.id);
    }

    // If every item is pending, preserve the newest bounded subset while
    // still enforcing the hard memory limit.
    while (bucket.length > maxMessagesPerConversation) {
      final List<MessageEntity> remaining = bucket.values.toList(
        growable: false,
      )..sort(_compareMessages);

      if (remaining.isEmpty) {
        break;
      }

      bucket.remove(remaining.first.id);
    }
  }

  static bool _isPendingForRetry(MessageStatus status) {
    return status == MessageStatus.queued || status == MessageStatus.failed;
  }

  static void _validateMessageIdentity(MessageEntity message) {
    _normalizeId(message.id, fieldName: 'message.id');
    _normalizeId(message.conversationId, fieldName: 'message.conversationId');
    _normalizeId(message.senderUid, fieldName: 'message.senderUid');
  }

  static String _normalizeId(String value, {required String fieldName}) {
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

  static void _validateLimit(int limit) {
    if (limit <= 0) {
      throw ArgumentError.value(
        limit,
        'limit',
        'limit must be greater than zero.',
      );
    }
  }

  static DateTime _effectiveTimestamp(MessageEntity message) {
    return (message.serverCreatedAt ?? message.clientCreatedAt).toUtc();
  }

  static int _compareMessages(MessageEntity first, MessageEntity second) {
    final DateTime firstTime = _effectiveTimestamp(first);
    final DateTime secondTime = _effectiveTimestamp(second);

    final int timeComparison = firstTime.compareTo(secondTime);

    if (timeComparison != 0) {
      return timeComparison;
    }

    return first.id.compareTo(second.id);
  }

  static int _compareConversations(
    ConversationEntity first,
    ConversationEntity second,
  ) {
    final DateTime firstTime = (first.lastMessageAt ?? first.updatedAt).toUtc();

    final DateTime secondTime = (second.lastMessageAt ?? second.updatedAt)
        .toUtc();

    final int timeComparison = secondTime.compareTo(firstTime);

    if (timeComparison != 0) {
      return timeComparison;
    }

    return first.id.compareTo(second.id);
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('InMemoryMessageDatabase has already been disposed.');
    }
  }
}

// ============================================================================
// END OF FILE: lib/features/message/storage/message_database.dart
// ============================================================================
