// ============================================================================
// JR CALL
// File: message_sync_engine.dart
// Location: lib/features/message/engine/message_sync_engine.dart
// Description:
// Production local/server durable-message reconciliation engine.
//
// Responsibilities:
// - Initial durable-message synchronization.
// - Incremental server/local reconciliation.
// - Canonical messageId-based deduplication.
// - Optimistic local + authoritative server merge.
// - Stable deterministic timeline ordering.
// - Edit/delete reconciliation.
// - Older-page pagination merge.
// - Offline -> online reconciliation.
// - Immutable timeline stream emission.
// - Stale lifecycle/session protection.
// - Bounded in-memory retention.
//
// Important:
// - Canonical message ID is the ONLY deduplication identity.
// - Same message must never appear twice after reconnect.
// - serverCreatedAt is preferred for committed timeline ordering.
// - clientCreatedAt is used while server timestamp is unresolved.
// - This file does NOT directly own Firestore collection references.
// - This file does NOT render UI.
// - This file does NOT contain Call Engine/WebRTC logic.
// ============================================================================

import 'dart:async';

import '../data/message_entity.dart';
import '../data/message_status.dart';

/// Page returned by the synchronization data source.
final class MessageSyncPage {
  const MessageSyncPage({required this.messages, required this.hasMore});

  final List<MessageEntity> messages;
  final bool hasMore;
}

/// Data source required by [MessageSyncEngine].
///
/// Repository/storage infrastructure provides the concrete implementation.
/// This keeps synchronization logic independent from raw Firestore APIs.
abstract interface class MessageSyncDataSource {
  /// Loads the newest page for an active conversation.
  Future<MessageSyncPage> loadInitialMessages({
    required String authenticatedUid,
    required String conversationId,
  });

  /// Loads the next older page using the current oldest canonical message.
  Future<MessageSyncPage> loadOlderMessages({
    required String authenticatedUid,
    required String conversationId,
    required MessageEntity oldestLoadedMessage,
  });

  /// Loads authoritative server state needed for explicit reconciliation.
  ///
  /// Implementations should return the bounded relevant synchronization
  /// window rather than lifetime conversation history.
  Future<List<MessageEntity>> loadReconciliationMessages({
    required String authenticatedUid,
    required String conversationId,
  });
}

/// Local/offline synchronization bridge.
///
/// FILE 14 / FILE 17 / FILE 35 may provide the concrete adapter.
abstract interface class MessageSyncLocalStore {
  /// Loads locally retained messages for the active conversation.
  Future<List<MessageEntity>> loadLocalMessages({
    required String authenticatedUid,
    required String conversationId,
  });

  /// Persists one reconciled canonical message locally.
  FutureOr<void> upsertMessage(MessageEntity message);

  /// Persists a bounded canonical snapshot for the current conversation.
  FutureOr<void> replaceConversationSnapshot({
    required String conversationId,
    required List<MessageEntity> messages,
  });

  /// Clears only transient synchronization state for a conversation.
  ///
  /// Durable queued/failed messages must not be destroyed by session reset.
  FutureOr<void> clearTransientState({required String conversationId});
}

/// Origin of a reconciliation candidate.
enum MessageSyncSource { local, server, pagination, reconciliation }

/// Production durable-message synchronization engine.
final class MessageSyncEngine {
  factory MessageSyncEngine({
    required MessageSyncDataSource dataSource,
    required MessageSyncLocalStore localStore,
    int maxRetainedMessages = 600,
  }) {
    return MessageSyncEngine._(
      dataSource,
      localStore,
      _validateRetention(maxRetainedMessages),
    );
  }

  MessageSyncEngine._(
    this._dataSource,
    this._localStore,
    this._maxRetainedMessages,
  );

  final MessageSyncDataSource _dataSource;
  final MessageSyncLocalStore _localStore;
  final int _maxRetainedMessages;

  final StreamController<List<MessageEntity>> _messagesController =
      StreamController<List<MessageEntity>>.broadcast(sync: true);

  final Map<String, MessageEntity> _messagesById = <String, MessageEntity>{};

  List<MessageEntity> _currentMessages = const <MessageEntity>[];

  String? _authenticatedUid;
  String? _conversationId;

  int _sessionGeneration = 0;

  bool _initialized = false;
  bool _disposed = false;
  bool _hasMore = true;
  bool _isLoadingOlder = false;
  bool _isSynchronizing = false;

  /// Immutable synchronized durable timeline.
  Stream<List<MessageEntity>> get messages => _messagesController.stream;

  /// Latest immutable synchronized timeline snapshot.
  List<MessageEntity> get currentMessages => _currentMessages;

  /// Whether an older durable page remains available.
  bool get hasMore => _hasMore;

  /// Whether older-page pagination is currently running.
  bool get isLoadingOlder => _isLoadingOlder;

  /// Whether explicit local/server reconciliation is active.
  bool get isSynchronizing => _isSynchronizing;

  /// True when initialized for an authenticated conversation.
  bool get isInitialized => _initialized && !_disposed;

  /// True after permanent disposal.
  bool get isDisposed => _disposed;

  /// Initializes synchronization for one authenticated conversation.
  ///
  /// Local optimistic/failed records are merged with the newest authoritative
  /// server page using canonical message ID.
  Future<void> initialize({
    required String authenticatedUid,
    required String conversationId,
  }) async {
    _ensureNotDisposed();

    final String uid = _normalizeRequiredIdentifier(
      authenticatedUid,
      fieldName: 'authenticatedUid',
    );

    final String conversation = _normalizeRequiredIdentifier(
      conversationId,
      fieldName: 'conversationId',
    );

    if (_initialized &&
        _authenticatedUid == uid &&
        _conversationId == conversation) {
      return;
    }

    if (_initialized || _authenticatedUid != null || _conversationId != null) {
      await reset();
    }

    final int generation = ++_sessionGeneration;

    _authenticatedUid = uid;
    _conversationId = conversation;
    _initialized = true;
    _hasMore = true;
    _isLoadingOlder = false;
    _isSynchronizing = false;

    try {
      final List<MessageEntity> localMessages = await _localStore
          .loadLocalMessages(
            authenticatedUid: uid,
            conversationId: conversation,
          );

      _assertGeneration(generation);

      _mergeCollection(localMessages, source: MessageSyncSource.local);

      _emitSnapshot();

      final MessageSyncPage initialPage = await _dataSource.loadInitialMessages(
        authenticatedUid: uid,
        conversationId: conversation,
      );

      _assertGeneration(generation);

      _mergeCollection(initialPage.messages, source: MessageSyncSource.server);

      _hasMore = initialPage.hasMore;

      _trimRetainedMessages();
      _emitSnapshot();

      await _persistSnapshot();

      _assertGeneration(generation);
    } catch (error, stackTrace) {
      if (_isGenerationCurrent(generation)) {
        _emitSnapshot();
      }

      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Adds or reconciles one local optimistic message.
  Future<MessageEntity> mergeLocalMessage(MessageEntity message) async {
    final _SyncSession session = _requireSession();

    _validateConversation(message, conversationId: session.conversationId);

    final MessageEntity merged = _mergeOne(
      message,
      source: MessageSyncSource.local,
    );

    _trimRetainedMessages();
    _emitSnapshot();

    await _localStore.upsertMessage(merged);

    return merged;
  }

  /// Adds or reconciles one authoritative incoming/server message.
  Future<MessageEntity> mergeServerMessage(MessageEntity message) async {
    final _SyncSession session = _requireSession();

    _validateConversation(message, conversationId: session.conversationId);

    final MessageEntity merged = _mergeOne(
      message,
      source: MessageSyncSource.server,
    );

    _trimRetainedMessages();
    _emitSnapshot();

    await _localStore.upsertMessage(merged);

    return merged;
  }

  /// Reconciles a batch of incremental server events.
  Future<void> mergeServerMessages(Iterable<MessageEntity> messages) async {
    final _SyncSession session = _requireSession();

    for (final MessageEntity message in messages) {
      _validateConversation(message, conversationId: session.conversationId);
    }

    _mergeCollection(messages, source: MessageSyncSource.server);

    _trimRetainedMessages();
    _emitSnapshot();

    await _persistSnapshot();
  }

  /// Loads one older page.
  Future<void> loadOlder({
    required String authenticatedUid,
    required String conversationId,
  }) async {
    final _SyncSession session = _requireMatchingSession(
      authenticatedUid: authenticatedUid,
      conversationId: conversationId,
    );

    if (_isLoadingOlder || !_hasMore) {
      return;
    }

    if (_currentMessages.isEmpty) {
      _hasMore = false;
      return;
    }

    _isLoadingOlder = true;
    final int generation = session.generation;

    try {
      final MessageEntity oldest = _currentMessages.first;

      final MessageSyncPage page = await _dataSource.loadOlderMessages(
        authenticatedUid: session.authenticatedUid,
        conversationId: session.conversationId,
        oldestLoadedMessage: oldest,
      );

      _assertGeneration(generation);

      _mergeCollection(page.messages, source: MessageSyncSource.pagination);

      _hasMore = page.hasMore;

      _trimRetainedMessages(preserveOldestSide: true);

      _emitSnapshot();

      await _persistSnapshot();

      _assertGeneration(generation);
    } finally {
      if (_isGenerationCurrent(generation)) {
        _isLoadingOlder = false;
      }
    }
  }

  /// Performs explicit offline -> online reconciliation.
  Future<void> synchronize({
    required String authenticatedUid,
    required String conversationId,
  }) async {
    final _SyncSession session = _requireMatchingSession(
      authenticatedUid: authenticatedUid,
      conversationId: conversationId,
    );

    if (_isSynchronizing) {
      return;
    }

    _isSynchronizing = true;
    final int generation = session.generation;

    try {
      final List<MessageEntity> localMessages = await _localStore
          .loadLocalMessages(
            authenticatedUid: session.authenticatedUid,
            conversationId: session.conversationId,
          );

      _assertGeneration(generation);

      _mergeCollection(localMessages, source: MessageSyncSource.local);

      final List<MessageEntity> remoteMessages = await _dataSource
          .loadReconciliationMessages(
            authenticatedUid: session.authenticatedUid,
            conversationId: session.conversationId,
          );

      _assertGeneration(generation);

      _mergeCollection(
        remoteMessages,
        source: MessageSyncSource.reconciliation,
      );

      _trimRetainedMessages();
      _emitSnapshot();

      await _persistSnapshot();

      _assertGeneration(generation);
    } finally {
      if (_isGenerationCurrent(generation)) {
        _isSynchronizing = false;
      }
    }
  }

  MessageEntity _mergeOne(
    MessageEntity incoming, {
    required MessageSyncSource source,
  }) {
    final String id = _normalizeRequiredIdentifier(
      incoming.id,
      fieldName: 'message.id',
    );

    if (id != incoming.id.trim()) {
      throw StateError(
        'Canonical message ID contains invalid outer whitespace.',
      );
    }

    final MessageEntity? existing = _messagesById[id];

    if (existing == null) {
      final MessageEntity normalized = incoming.copyWith(
        clientCreatedAt: incoming.clientCreatedAt.toUtc(),
        serverCreatedAt: incoming.serverCreatedAt?.toUtc(),
        editedAt: incoming.editedAt?.toUtc(),
        deletedAt: incoming.deletedAt?.toUtc(),
      );

      _messagesById[id] = normalized;
      return normalized;
    }

    _validateCanonicalIdentity(existing: existing, incoming: incoming);

    final MessageEntity merged = _reconcile(
      local: existing,
      incoming: incoming,
      source: source,
    );

    _messagesById[id] = merged;
    return merged;
  }

  void _mergeCollection(
    Iterable<MessageEntity> messages, {
    required MessageSyncSource source,
  }) {
    final String conversation =
        _conversationId ??
        (throw StateError('MessageSyncEngine has no active conversation.'));

    for (final MessageEntity message in messages) {
      _validateConversation(message, conversationId: conversation);

      _mergeOne(message, source: source);
    }
  }

  MessageEntity _reconcile({
    required MessageEntity local,
    required MessageEntity incoming,
    required MessageSyncSource source,
  }) {
    final MessageStatus status = _mergeStatus(
      local.status,
      incoming.status,
      source: source,
    );

    final DateTime clientCreatedAt = _earliestDate(
      local.clientCreatedAt,
      incoming.clientCreatedAt,
    );

    final DateTime? serverCreatedAt = _preferredServerTimestamp(
      local.serverCreatedAt,
      incoming.serverCreatedAt,
    );

    final DateTime? editedAt = _latestNullableDate(
      local.editedAt,
      incoming.editedAt,
    );

    final DateTime? deletedAt = _latestNullableDate(
      local.deletedAt,
      incoming.deletedAt,
    );

    final bool incomingIsAuthoritative =
        source == MessageSyncSource.server ||
        source == MessageSyncSource.pagination ||
        source == MessageSyncSource.reconciliation;

    final MessageEntity base = incomingIsAuthoritative ? incoming : local;

    final bool committed =
        serverCreatedAt != null ||
        _statusRank(status) >= _statusRank(MessageStatus.sent);

    return base.copyWith(
      status: status,
      clientCreatedAt: clientCreatedAt,
      serverCreatedAt: serverCreatedAt,
      editedAt: editedAt,
      deletedAt: deletedAt,
      localOnly: committed ? false : base.localOnly,
      clearFailureCode: committed && status != MessageStatus.failed,
      clearFailureMessage: committed && status != MessageStatus.failed,
    );
  }

  static MessageStatus _mergeStatus(
    MessageStatus current,
    MessageStatus incoming, {
    required MessageSyncSource source,
  }) {
    if (current == incoming) {
      return current;
    }

    if (current == MessageStatus.read) {
      return MessageStatus.read;
    }

    if (current == MessageStatus.delivered && incoming != MessageStatus.read) {
      return MessageStatus.delivered;
    }

    if (current == MessageStatus.sent &&
        (incoming == MessageStatus.queued ||
            incoming == MessageStatus.sending ||
            incoming == MessageStatus.failed)) {
      return MessageStatus.sent;
    }

    if (current == MessageStatus.failed) {
      if (incoming == MessageStatus.sent ||
          incoming == MessageStatus.delivered ||
          incoming == MessageStatus.read) {
        return incoming;
      }

      if (source == MessageSyncSource.local) {
        return incoming;
      }

      return current;
    }

    if (incoming == MessageStatus.failed) {
      if (current == MessageStatus.queued || current == MessageStatus.sending) {
        return source == MessageSyncSource.local
            ? MessageStatus.failed
            : current;
      }

      return current;
    }

    return _statusRank(incoming) > _statusRank(current) ? incoming : current;
  }

  void _emitSnapshot() {
    final List<MessageEntity> ordered = _messagesById.values.toList(
      growable: false,
    )..sort(_compareMessages);

    _currentMessages = List<MessageEntity>.unmodifiable(ordered);

    if (!_messagesController.isClosed) {
      _messagesController.add(_currentMessages);
    }
  }

  static int _compareMessages(MessageEntity first, MessageEntity second) {
    final DateTime firstTime = (first.serverCreatedAt ?? first.clientCreatedAt)
        .toUtc();

    final DateTime secondTime =
        (second.serverCreatedAt ?? second.clientCreatedAt).toUtc();

    final int timeComparison = firstTime.compareTo(secondTime);

    if (timeComparison != 0) {
      return timeComparison;
    }

    final int clientComparison = first.clientCreatedAt.toUtc().compareTo(
      second.clientCreatedAt.toUtc(),
    );

    if (clientComparison != 0) {
      return clientComparison;
    }

    return first.id.compareTo(second.id);
  }

  void _trimRetainedMessages({bool preserveOldestSide = false}) {
    if (_messagesById.length <= _maxRetainedMessages) {
      return;
    }

    final List<MessageEntity> ordered = _messagesById.values.toList(
      growable: false,
    )..sort(_compareMessages);

    final Set<String> keepIds = ordered
        .where(_mustRetainLocalMessage)
        .map((MessageEntity message) => message.id)
        .toSet();

    final int remainingCapacity = (_maxRetainedMessages - keepIds.length).clamp(
      0,
      _maxRetainedMessages,
    );

    final List<MessageEntity> candidates = ordered
        .where((MessageEntity message) => !keepIds.contains(message.id))
        .toList(growable: false);

    if (remainingCapacity > 0) {
      if (preserveOldestSide) {
        for (final MessageEntity message in candidates.take(
          remainingCapacity,
        )) {
          keepIds.add(message.id);
        }
      } else {
        final int start = candidates.length > remainingCapacity
            ? candidates.length - remainingCapacity
            : 0;

        for (final MessageEntity message in candidates.skip(start)) {
          keepIds.add(message.id);
        }
      }
    }

    _messagesById.removeWhere(
      (String id, MessageEntity _) => !keepIds.contains(id),
    );
  }

  static bool _mustRetainLocalMessage(MessageEntity message) {
    return message.localOnly ||
        message.status == MessageStatus.queued ||
        message.status == MessageStatus.sending ||
        message.status == MessageStatus.failed;
  }

  Future<void> _persistSnapshot() async {
    final String? conversation = _conversationId;

    if (conversation == null) {
      return;
    }

    for (final MessageEntity message in _currentMessages) {
      await _localStore.upsertMessage(message);
    }

    await _localStore.replaceConversationSnapshot(
      conversationId: conversation,
      messages: _currentMessages,
    );
  }

  _SyncSession _requireSession() {
    _ensureNotDisposed();

    if (!_initialized) {
      throw StateError('MessageSyncEngine is not initialized.');
    }

    final String? uid = _authenticatedUid;
    final String? conversation = _conversationId;

    if (uid == null ||
        uid.isEmpty ||
        conversation == null ||
        conversation.isEmpty) {
      throw StateError(
        'MessageSyncEngine has no valid authenticated conversation session.',
      );
    }

    return _SyncSession(
      authenticatedUid: uid,
      conversationId: conversation,
      generation: _sessionGeneration,
    );
  }

  _SyncSession _requireMatchingSession({
    required String authenticatedUid,
    required String conversationId,
  }) {
    final _SyncSession session = _requireSession();

    final String uid = _normalizeRequiredIdentifier(
      authenticatedUid,
      fieldName: 'authenticatedUid',
    );

    final String conversation = _normalizeRequiredIdentifier(
      conversationId,
      fieldName: 'conversationId',
    );

    if (uid != session.authenticatedUid) {
      throw StateError(
        'MessageSyncEngine authenticated UID does not match active session.',
      );
    }

    if (conversation != session.conversationId) {
      throw StateError(
        'MessageSyncEngine conversation ID does not match active session.',
      );
    }

    return session;
  }

  void _assertGeneration(int generation) {
    if (!_isGenerationCurrent(generation)) {
      throw StateError(
        'MessageSyncEngine operation belongs to a stale session.',
      );
    }
  }

  bool _isGenerationCurrent(int generation) {
    return !_disposed && _initialized && generation == _sessionGeneration;
  }

  static void _validateConversation(
    MessageEntity message, {
    required String conversationId,
  }) {
    if (message.conversationId != conversationId) {
      throw StateError('Message belongs to a different conversation.');
    }

    _normalizeRequiredIdentifier(message.id, fieldName: 'message.id');

    _normalizeRequiredIdentifier(
      message.senderUid,
      fieldName: 'message.senderUid',
    );
  }

  static void _validateCanonicalIdentity({
    required MessageEntity existing,
    required MessageEntity incoming,
  }) {
    if (existing.id != incoming.id) {
      throw StateError('Canonical reconciliation message ID mismatch.');
    }

    if (existing.conversationId != incoming.conversationId) {
      throw StateError('Canonical message ID conflicts across conversations.');
    }

    if (existing.senderUid != incoming.senderUid) {
      throw StateError(
        'Canonical message ID conflicts across Firebase sender UIDs.',
      );
    }

    if (existing.type != incoming.type) {
      throw StateError('Canonical message ID conflicts across message types.');
    }
  }

  static int _statusRank(MessageStatus status) {
    switch (status) {
      case MessageStatus.failed:
        return -1;
      case MessageStatus.queued:
        return 0;
      case MessageStatus.sending:
        return 1;
      case MessageStatus.sent:
        return 2;
      case MessageStatus.delivered:
        return 3;
      case MessageStatus.read:
        return 4;
    }
  }

  static DateTime _earliestDate(DateTime first, DateTime second) {
    final DateTime firstUtc = first.toUtc();
    final DateTime secondUtc = second.toUtc();

    return firstUtc.isBefore(secondUtc) ? firstUtc : secondUtc;
  }

  static DateTime? _preferredServerTimestamp(
    DateTime? current,
    DateTime? incoming,
  ) {
    if (incoming != null) {
      return incoming.toUtc();
    }

    return current?.toUtc();
  }

  static DateTime? _latestNullableDate(DateTime? first, DateTime? second) {
    if (first == null) {
      return second?.toUtc();
    }

    if (second == null) {
      return first.toUtc();
    }

    final DateTime firstUtc = first.toUtc();
    final DateTime secondUtc = second.toUtc();

    return firstUtc.isAfter(secondUtc) ? firstUtc : secondUtc;
  }

  /// Resets active per-conversation synchronization state.
  Future<void> reset() async {
    _ensureNotDisposed();

    final String? previousConversation = _conversationId;

    ++_sessionGeneration;

    _initialized = false;
    _authenticatedUid = null;
    _conversationId = null;

    _hasMore = true;
    _isLoadingOlder = false;
    _isSynchronizing = false;

    _messagesById.clear();
    _currentMessages = const <MessageEntity>[];

    if (!_messagesController.isClosed) {
      _messagesController.add(_currentMessages);
    }

    if (previousConversation != null) {
      await _localStore.clearTransientState(
        conversationId: previousConversation,
      );
    }
  }

  /// Permanently disposes this synchronization engine.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    final String? previousConversation = _conversationId;

    ++_sessionGeneration;

    _initialized = false;
    _authenticatedUid = null;
    _conversationId = null;

    _hasMore = false;
    _isLoadingOlder = false;
    _isSynchronizing = false;

    _messagesById.clear();
    _currentMessages = const <MessageEntity>[];

    if (previousConversation != null) {
      await _localStore.clearTransientState(
        conversationId: previousConversation,
      );
    }

    _disposed = true;

    await _messagesController.close();
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError(
        'MessageSyncEngine has already been disposed and cannot be reused.',
      );
    }
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

  static int _validateRetention(int value) {
    if (value < 100 || value > 5000) {
      throw ArgumentError.value(
        value,
        'maxRetainedMessages',
        'maxRetainedMessages must be between 100 and 5000.',
      );
    }

    return value;
  }
}

final class _SyncSession {
  const _SyncSession({
    required this.authenticatedUid,
    required this.conversationId,
    required this.generation,
  });

  final String authenticatedUid;
  final String conversationId;
  final int generation;
}

// ============================================================================
// END OF FILE: lib/features/message/engine/message_sync_engine.dart
// ============================================================================
