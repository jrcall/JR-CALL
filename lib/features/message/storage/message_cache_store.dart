// ============================================================================
// JR CALL
// File: message_cache_store.dart
// Location: lib/features/message/storage/message_cache_store.dart
// Description:
// Fast bounded in-memory cache coordination for JR CALL Message Engine.
//
// Owns:
// - Loaded conversation cache.
// - Loaded message-page cache.
// - Canonical message-ID deduplication.
// - Optimistic message lookup.
// - Cache invalidation.
// - Bounded-memory eviction.
// - Immutable snapshot output.
// - Deterministic timeline/conversation ordering.
//
// Does NOT own:
// - Firestore reads/writes.
// - Firebase Storage.
// - Local durable persistence.
// - Realtime subscriptions.
// - Retry execution.
// - UI state.
// - Call Engine / WebRTC.
// ============================================================================

import 'dart:collection';

import '../data/conversation_entity.dart';
import '../data/message_entity.dart';

/// Immutable cached page of messages.
final class MessageCachePage {
  MessageCachePage({
    required String key,
    required Iterable<MessageEntity> messages,
    this.hasMore = false,
  }) : key = key.trim(),
       messages = List<MessageEntity>.unmodifiable(messages) {
    if (this.key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'Page key must not be empty.');
    }
  }

  final String key;
  final List<MessageEntity> messages;
  final bool hasMore;

  MessageCachePage copyWith({
    String? key,
    Iterable<MessageEntity>? messages,
    bool? hasMore,
  }) {
    return MessageCachePage(
      key: key ?? this.key,
      messages: messages ?? this.messages,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

/// Immutable snapshot of a cached conversation timeline.
final class MessageCacheSnapshot {
  MessageCacheSnapshot({
    required String conversationId,
    required Iterable<MessageEntity> messages,
    required Iterable<MessageCachePage> pages,
    required this.hasMore,
  }) : conversationId = conversationId.trim(),
       messages = List<MessageEntity>.unmodifiable(messages),
       pages = List<MessageCachePage>.unmodifiable(pages) {
    if (this.conversationId.isEmpty) {
      throw ArgumentError.value(
        conversationId,
        'conversationId',
        'Conversation ID must not be empty.',
      );
    }
  }

  final String conversationId;
  final List<MessageEntity> messages;
  final List<MessageCachePage> pages;
  final bool hasMore;

  bool get isEmpty => messages.isEmpty;

  bool get isNotEmpty => messages.isNotEmpty;

  int get length => messages.length;
}

/// Immutable high-level cache diagnostics.
///
/// This contains counts only and never exposes message text or user data.
final class MessageCacheStats {
  const MessageCacheStats({
    required this.conversationCount,
    required this.timelineCount,
    required this.messageCount,
    required this.pageCount,
  });

  final int conversationCount;
  final int timelineCount;
  final int messageCount;
  final int pageCount;
}

/// Fast bounded memory cache for the Message feature.
///
/// Message ID is the canonical deduplication key.
final class MessageCacheStore {
  MessageCacheStore({
    this.maxConversations = 100,
    this.maxMessagesPerConversation = 300,
    this.maxPagesPerConversation = 8,
    this.maxCachedTimelines = 20,
  }) {
    if (maxConversations <= 0) {
      throw ArgumentError.value(
        maxConversations,
        'maxConversations',
        'Must be greater than zero.',
      );
    }

    if (maxMessagesPerConversation <= 0) {
      throw ArgumentError.value(
        maxMessagesPerConversation,
        'maxMessagesPerConversation',
        'Must be greater than zero.',
      );
    }

    if (maxPagesPerConversation <= 0) {
      throw ArgumentError.value(
        maxPagesPerConversation,
        'maxPagesPerConversation',
        'Must be greater than zero.',
      );
    }

    if (maxCachedTimelines <= 0) {
      throw ArgumentError.value(
        maxCachedTimelines,
        'maxCachedTimelines',
        'Must be greater than zero.',
      );
    }
  }

  /// Maximum inbox/conversation entities kept in memory.
  final int maxConversations;

  /// Maximum unique messages retained for one conversation.
  final int maxMessagesPerConversation;

  /// Maximum pagination pages retained for one conversation.
  final int maxPagesPerConversation;

  /// Maximum distinct conversation timelines retained simultaneously.
  final int maxCachedTimelines;

  final LinkedHashMap<String, ConversationEntity> _conversations =
      LinkedHashMap<String, ConversationEntity>();

  final LinkedHashMap<String, _ConversationMessageCache> _messageCaches =
      LinkedHashMap<String, _ConversationMessageCache>();

  // --------------------------------------------------------------------------
  // CONVERSATION CACHE
  // --------------------------------------------------------------------------

  /// Returns an immutable conversation list using deterministic inbox order.
  List<ConversationEntity> get conversations {
    final List<ConversationEntity> values = List<ConversationEntity>.of(
      _conversations.values,
    );

    values.sort(_compareConversations);

    return List<ConversationEntity>.unmodifiable(values);
  }

  int get conversationCount => _conversations.length;

  bool containsConversation(String conversationId) {
    final String id = _normalizeId(conversationId, fieldName: 'conversationId');

    return _conversations.containsKey(id);
  }

  ConversationEntity? getConversation(String conversationId) {
    final String id = _normalizeId(conversationId, fieldName: 'conversationId');

    final ConversationEntity? value = _conversations.remove(id);

    if (value != null) {
      _conversations[id] = value;
    }

    return value;
  }

  /// Adds or replaces one conversation by canonical conversation ID.
  void putConversation(ConversationEntity conversation) {
    final String id = _normalizeId(
      conversation.id,
      fieldName: 'conversation.id',
    );

    _conversations.remove(id);
    _conversations[id] = conversation;

    _trimConversations();
  }

  /// Merges conversations by ID.
  ///
  /// Duplicate IDs always resolve to the last supplied entity.
  void putConversations(
    Iterable<ConversationEntity> conversations, {
    bool replaceExisting = false,
  }) {
    if (replaceExisting) {
      _conversations.clear();
    }

    for (final ConversationEntity conversation in conversations) {
      putConversation(conversation);
    }
  }

  bool removeConversation(String conversationId, {bool removeMessages = true}) {
    final String id = _normalizeId(conversationId, fieldName: 'conversationId');

    final bool removed = _conversations.remove(id) != null;

    if (removeMessages) {
      _messageCaches.remove(id);
    }

    return removed;
  }

  void clearConversations({bool clearMessages = false}) {
    _conversations.clear();

    if (clearMessages) {
      _messageCaches.clear();
    }
  }

  // --------------------------------------------------------------------------
  // MESSAGE LOOKUP
  // --------------------------------------------------------------------------

  bool containsMessage({
    required String conversationId,
    required String messageId,
  }) {
    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String message = _normalizeId(messageId, fieldName: 'messageId');

    return _messageCaches[conversation]?.messages.containsKey(message) ?? false;
  }

  MessageEntity? getMessage({
    required String conversationId,
    required String messageId,
  }) {
    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String message = _normalizeId(messageId, fieldName: 'messageId');

    final _ConversationMessageCache? cache = _touchTimeline(conversation);

    return cache?.messages[message];
  }

  /// Finds a cached optimistic/local version of a message by canonical ID.
  ///
  /// This intentionally relies only on the canonical message identity.
  /// Whether it is currently queued/sending/failed is owned by MessageEntity's
  /// state and higher engine/repository layers.
  MessageEntity? getOptimisticMessage({
    required String conversationId,
    required String messageId,
  }) {
    final MessageEntity? message = getMessage(
      conversationId: conversationId,
      messageId: messageId,
    );

    if (message == null) {
      return null;
    }

    if (!message.localOnly) {
      return null;
    }

    return message;
  }

  // --------------------------------------------------------------------------
  // MESSAGE TIMELINE CACHE
  // --------------------------------------------------------------------------

  /// Returns an immutable stable timeline snapshot.
  List<MessageEntity> getMessages(String conversationId) {
    final String id = _normalizeId(conversationId, fieldName: 'conversationId');

    final _ConversationMessageCache? cache = _touchTimeline(id);

    if (cache == null) {
      return const <MessageEntity>[];
    }

    return List<MessageEntity>.unmodifiable(
      _orderedMessages(cache.messages.values),
    );
  }

  MessageCacheSnapshot snapshot(String conversationId) {
    final String id = _normalizeId(conversationId, fieldName: 'conversationId');

    final _ConversationMessageCache? cache = _touchTimeline(id);

    if (cache == null) {
      return MessageCacheSnapshot(
        conversationId: id,
        messages: const <MessageEntity>[],
        pages: const <MessageCachePage>[],
        hasMore: false,
      );
    }

    return MessageCacheSnapshot(
      conversationId: id,
      messages: _orderedMessages(cache.messages.values),
      pages: cache.pages.values,
      hasMore: cache.hasMore,
    );
  }

  /// Inserts or reconciles a single message.
  ///
  /// If the same message ID already exists, [message] replaces the cached
  /// version instead of creating a duplicate timeline item.
  void putMessage(MessageEntity message) {
    final String conversationId = _normalizeId(
      message.conversationId,
      fieldName: 'message.conversationId',
    );

    final String messageId = _normalizeId(message.id, fieldName: 'message.id');

    final _ConversationMessageCache cache = _ensureTimeline(conversationId);

    cache.messages[messageId] = message;

    _trimMessages(cache);
  }

  /// Canonical message-ID merge.
  ///
  /// This is suitable for:
  /// - initial local/server reconciliation
  /// - incremental realtime changes
  /// - optimistic/server reconciliation
  /// - pagination merge
  /// - offline -> online reconciliation
  ///
  /// Later entries with the same message ID replace earlier entries.
  void putMessages(
    String conversationId,
    Iterable<MessageEntity> messages, {
    bool replaceExisting = false,
  }) {
    final String id = _normalizeId(conversationId, fieldName: 'conversationId');

    final _ConversationMessageCache cache = _ensureTimeline(id);

    if (replaceExisting) {
      cache.messages.clear();
      cache.pages.clear();
      cache.hasMore = false;
    }

    for (final MessageEntity message in messages) {
      final String entityConversationId = _normalizeId(
        message.conversationId,
        fieldName: 'message.conversationId',
      );

      if (entityConversationId != id) {
        throw ArgumentError(
          'Message ${message.id} belongs to conversation '
          '$entityConversationId, not $id.',
        );
      }

      final String messageId = _normalizeId(
        message.id,
        fieldName: 'message.id',
      );

      cache.messages[messageId] = message;
    }

    _trimMessages(cache);
  }

  /// Replaces the entire currently-loaded timeline while deduplicating IDs.
  void replaceMessages(
    String conversationId,
    Iterable<MessageEntity> messages,
  ) {
    putMessages(conversationId, messages, replaceExisting: true);
  }

  /// Explicitly updates a cached canonical message.
  ///
  /// Returns false when the target message is not cached.
  bool updateMessage(MessageEntity message) {
    final String conversationId = _normalizeId(
      message.conversationId,
      fieldName: 'message.conversationId',
    );

    final String messageId = _normalizeId(message.id, fieldName: 'message.id');

    final _ConversationMessageCache? cache = _messageCaches[conversationId];

    if (cache == null || !cache.messages.containsKey(messageId)) {
      return false;
    }

    _touchTimeline(conversationId);

    cache.messages[messageId] = message;

    for (final MapEntry<String, MessageCachePage> entry
        in cache.pages.entries.toList(growable: false)) {
      final MessageCachePage page = entry.value;

      bool changed = false;

      final List<MessageEntity> updated = <MessageEntity>[];

      for (final MessageEntity cached in page.messages) {
        if (cached.id == messageId) {
          updated.add(message);
          changed = true;
        } else {
          updated.add(cached);
        }
      }

      if (changed) {
        cache.pages[entry.key] = page.copyWith(messages: updated);
      }
    }

    return true;
  }

  /// Removes a cached message only.
  ///
  /// Durable server deletion/tombstone policy belongs elsewhere.
  bool removeMessage({
    required String conversationId,
    required String messageId,
  }) {
    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String message = _normalizeId(messageId, fieldName: 'messageId');

    final _ConversationMessageCache? cache = _messageCaches[conversation];

    if (cache == null) {
      return false;
    }

    _touchTimeline(conversation);

    final bool removed = cache.messages.remove(message) != null;

    if (!removed) {
      return false;
    }

    for (final MapEntry<String, MessageCachePage> entry
        in cache.pages.entries.toList(growable: false)) {
      final MessageCachePage page = entry.value;

      final List<MessageEntity> retained = page.messages
          .where((MessageEntity item) => item.id != message)
          .toList(growable: false);

      if (retained.length != page.messages.length) {
        cache.pages[entry.key] = page.copyWith(messages: retained);
      }
    }

    return true;
  }

  // --------------------------------------------------------------------------
  // PAGINATION CACHE
  // --------------------------------------------------------------------------

  List<MessageCachePage> getPages(String conversationId) {
    final String id = _normalizeId(conversationId, fieldName: 'conversationId');

    final _ConversationMessageCache? cache = _touchTimeline(id);

    if (cache == null) {
      return const <MessageCachePage>[];
    }

    return List<MessageCachePage>.unmodifiable(cache.pages.values);
  }

  MessageCachePage? getPage({
    required String conversationId,
    required String pageKey,
  }) {
    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String key = _normalizeId(pageKey, fieldName: 'pageKey');

    final _ConversationMessageCache? cache = _touchTimeline(conversation);

    if (cache == null) {
      return null;
    }

    final MessageCachePage? page = cache.pages.remove(key);

    if (page != null) {
      cache.pages[key] = page;
    }

    return page;
  }

  /// Stores a pagination page and merges all page messages into the canonical
  /// message-ID map.
  void putPage({
    required String conversationId,
    required String pageKey,
    required Iterable<MessageEntity> messages,
    required bool hasMore,
  }) {
    final String conversation = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String key = _normalizeId(pageKey, fieldName: 'pageKey');

    final List<MessageEntity> normalizedMessages = <MessageEntity>[];

    final LinkedHashMap<String, MessageEntity> deduplicated =
        LinkedHashMap<String, MessageEntity>();

    for (final MessageEntity message in messages) {
      final String entityConversationId = _normalizeId(
        message.conversationId,
        fieldName: 'message.conversationId',
      );

      if (entityConversationId != conversation) {
        throw ArgumentError(
          'Message ${message.id} belongs to conversation '
          '$entityConversationId, not $conversation.',
        );
      }

      final String messageId = _normalizeId(
        message.id,
        fieldName: 'message.id',
      );

      deduplicated[messageId] = message;
    }

    normalizedMessages.addAll(_orderedMessages(deduplicated.values));

    final _ConversationMessageCache cache = _ensureTimeline(conversation);

    cache.pages.remove(key);

    cache.pages[key] = MessageCachePage(
      key: key,
      messages: normalizedMessages,
      hasMore: hasMore,
    );

    cache.hasMore = hasMore;

    for (final MessageEntity message in normalizedMessages) {
      cache.messages[message.id] = message;
    }

    _trimPages(cache);
    _trimMessages(cache);
  }

  bool getHasMore(String conversationId) {
    final String id = _normalizeId(conversationId, fieldName: 'conversationId');

    return _messageCaches[id]?.hasMore ?? false;
  }

  void setHasMore(String conversationId, bool hasMore) {
    final String id = _normalizeId(conversationId, fieldName: 'conversationId');

    final _ConversationMessageCache cache = _ensureTimeline(id);

    cache.hasMore = hasMore;
  }

  void clearPages(String conversationId) {
    final String id = _normalizeId(conversationId, fieldName: 'conversationId');

    final _ConversationMessageCache? cache = _messageCaches[id];

    if (cache == null) {
      return;
    }

    _touchTimeline(id);

    cache.pages.clear();
    cache.hasMore = false;
  }

  // --------------------------------------------------------------------------
  // INVALIDATION
  // --------------------------------------------------------------------------

  void invalidateConversation(
    String conversationId, {
    bool removeConversationEntity = false,
  }) {
    final String id = _normalizeId(conversationId, fieldName: 'conversationId');

    _messageCaches.remove(id);

    if (removeConversationEntity) {
      _conversations.remove(id);
    }
  }

  void invalidateMessages(String conversationId) {
    final String id = _normalizeId(conversationId, fieldName: 'conversationId');

    _messageCaches.remove(id);
  }

  /// Clears every in-memory Message feature cache.
  ///
  /// Appropriate on sign-out/session reset.
  void clear() {
    _conversations.clear();
    _messageCaches.clear();
  }

  // --------------------------------------------------------------------------
  // DIAGNOSTICS
  // --------------------------------------------------------------------------

  MessageCacheStats get stats {
    int messageCount = 0;
    int pageCount = 0;

    for (final _ConversationMessageCache cache in _messageCaches.values) {
      messageCount += cache.messages.length;
      pageCount += cache.pages.length;
    }

    return MessageCacheStats(
      conversationCount: _conversations.length,
      timelineCount: _messageCaches.length,
      messageCount: messageCount,
      pageCount: pageCount,
    );
  }

  // --------------------------------------------------------------------------
  // INTERNAL CACHE MANAGEMENT
  // --------------------------------------------------------------------------

  _ConversationMessageCache _ensureTimeline(String conversationId) {
    final _ConversationMessageCache? existing = _messageCaches.remove(
      conversationId,
    );

    if (existing != null) {
      _messageCaches[conversationId] = existing;
      return existing;
    }

    final _ConversationMessageCache created = _ConversationMessageCache();

    _messageCaches[conversationId] = created;

    _trimTimelines();

    return created;
  }

  _ConversationMessageCache? _touchTimeline(String conversationId) {
    final _ConversationMessageCache? cache = _messageCaches.remove(
      conversationId,
    );

    if (cache == null) {
      return null;
    }

    _messageCaches[conversationId] = cache;

    return cache;
  }

  void _trimConversations() {
    while (_conversations.length > maxConversations) {
      _conversations.remove(_conversations.keys.first);
    }
  }

  void _trimTimelines() {
    while (_messageCaches.length > maxCachedTimelines) {
      _messageCaches.remove(_messageCaches.keys.first);
    }
  }

  void _trimPages(_ConversationMessageCache cache) {
    while (cache.pages.length > maxPagesPerConversation) {
      cache.pages.remove(cache.pages.keys.first);
    }
  }

  void _trimMessages(_ConversationMessageCache cache) {
    if (cache.messages.length <= maxMessagesPerConversation) {
      return;
    }

    final List<MessageEntity> ordered = _orderedMessages(cache.messages.values);

    final int startIndex = ordered.length - maxMessagesPerConversation;

    final List<MessageEntity> retained = ordered.sublist(startIndex);

    cache.messages
      ..clear()
      ..addEntries(
        retained.map((MessageEntity message) {
          return MapEntry<String, MessageEntity>(message.id, message);
        }),
      );

    _removeEvictedPageEntries(cache);
  }

  void _removeEvictedPageEntries(_ConversationMessageCache cache) {
    if (cache.pages.isEmpty) {
      return;
    }

    final Set<String> retainedIds = cache.messages.keys.toSet();

    for (final MapEntry<String, MessageCachePage> entry
        in cache.pages.entries.toList(growable: false)) {
      final MessageCachePage page = entry.value;

      final List<MessageEntity> retained = page.messages
          .where((MessageEntity message) => retainedIds.contains(message.id))
          .toList(growable: false);

      if (retained.isEmpty) {
        cache.pages.remove(entry.key);
        continue;
      }

      if (retained.length != page.messages.length) {
        cache.pages[entry.key] = page.copyWith(messages: retained);
      }
    }
  }

  // --------------------------------------------------------------------------
  // ORDERING
  // --------------------------------------------------------------------------

  static List<MessageEntity> _orderedMessages(Iterable<MessageEntity> source) {
    final List<MessageEntity> messages = List<MessageEntity>.of(source);

    messages.sort(_compareMessages);

    return messages;
  }

  /// Timeline order:
  /// 1. serverCreatedAt when available
  /// 2. otherwise clientCreatedAt
  /// 3. canonical message ID tie-break
  static int _compareMessages(MessageEntity a, MessageEntity b) {
    final DateTime aTime = (a.serverCreatedAt ?? a.clientCreatedAt).toUtc();

    final DateTime bTime = (b.serverCreatedAt ?? b.clientCreatedAt).toUtc();

    final int timeComparison = aTime.compareTo(bTime);

    if (timeComparison != 0) {
      return timeComparison;
    }

    return a.id.compareTo(b.id);
  }

  /// Conversation order:
  /// newest actual lastMessageAt first.
  ///
  /// Falls back to updatedAt for conversations without a durable
  /// last-message timestamp.
  static int _compareConversations(ConversationEntity a, ConversationEntity b) {
    final DateTime aTime = (a.lastMessageAt ?? a.updatedAt).toUtc();

    final DateTime bTime = (b.lastMessageAt ?? b.updatedAt).toUtc();

    final int timeComparison = bTime.compareTo(aTime);

    if (timeComparison != 0) {
      return timeComparison;
    }

    return a.id.compareTo(b.id);
  }

  // --------------------------------------------------------------------------
  // VALUE NORMALIZATION
  // --------------------------------------------------------------------------

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
}

final class _ConversationMessageCache {
  final LinkedHashMap<String, MessageEntity> messages =
      LinkedHashMap<String, MessageEntity>();

  final LinkedHashMap<String, MessageCachePage> pages =
      LinkedHashMap<String, MessageCachePage>();

  bool hasMore = false;
}

// ============================================================================
// END OF FILE: lib/features/message/storage/message_cache_store.dart
// ============================================================================
