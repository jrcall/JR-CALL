// ============================================================================
// JR CALL
// File: message_listener.dart
// Location: lib/features/message/realtime/message_listener.dart
// Description:
// Realtime durable-message listener coordination for JR CALL Message Engine.
//
// Owns:
// - One active durable-message stream subscription.
// - Snapshot/list normalization.
// - Added / modified / removed event derivation.
// - Canonical message-ID deduplication.
// - Stale subscription protection.
// - Deterministic timeline emission.
// - Listener cancellation / restart / disposal.
// - Immutable output snapshots.
//
// Does NOT own:
// - Firestore collection paths.
// - Firestore writes.
// - Firebase Storage.
// - Message sending.
// - Delivery/read invention.
// - Widget/UI state.
// - Call Engine / WebRTC.
//
// Firestore query/path ownership remains in message_remote_store.dart.
// This listener consumes the typed durable-message stream supplied by the
// storage/repository layer.
// ============================================================================

import 'dart:async';

import '../data/message_entity.dart';

/// Type of durable-message change detected between two realtime snapshots.
enum MessageListenerChangeType { added, modified, removed }

/// Immutable single-message realtime change.
final class MessageListenerChange {
  const MessageListenerChange({
    required this.type,
    required this.messageId,
    this.message,
    this.previousMessage,
  });

  final MessageListenerChangeType type;
  final String messageId;

  /// Present for [MessageListenerChangeType.added] and
  /// [MessageListenerChangeType.modified].
  final MessageEntity? message;

  /// Present when a previous cached version existed.
  final MessageEntity? previousMessage;

  bool get isAdded => type == MessageListenerChangeType.added;

  bool get isModified => type == MessageListenerChangeType.modified;

  bool get isRemoved => type == MessageListenerChangeType.removed;
}

/// Immutable normalized realtime message snapshot.
final class MessageListenerSnapshot {
  MessageListenerSnapshot({
    required String conversationId,
    required Iterable<MessageEntity> messages,
    required Iterable<MessageListenerChange> changes,
    required int generation,
  }) : conversationId = conversationId.trim(),
       messages = List<MessageEntity>.unmodifiable(messages),
       changes = List<MessageListenerChange>.unmodifiable(changes),
       generation = generation {
    if (this.conversationId.isEmpty) {
      throw ArgumentError.value(
        conversationId,
        'conversationId',
        'Conversation ID must not be empty.',
      );
    }

    if (generation < 0) {
      throw ArgumentError.value(
        generation,
        'generation',
        'Generation must not be negative.',
      );
    }
  }

  final String conversationId;
  final List<MessageEntity> messages;
  final List<MessageListenerChange> changes;

  /// Subscription generation that produced this snapshot.
  ///
  /// Used by higher layers when they need additional stale-event protection.
  final int generation;

  bool get isEmpty => messages.isEmpty;

  bool get isNotEmpty => messages.isNotEmpty;

  int get length => messages.length;

  bool get hasChanges => changes.isNotEmpty;
}

/// Realtime durable-message listener.
///
/// The stream supplied to [startListening] must represent the server-backed
/// durable timeline for exactly one conversation. Firestore path/query
/// creation remains the responsibility of `message_remote_store.dart`.
///
/// Every incoming list is:
/// - conversation-validated,
/// - deduplicated by canonical message ID,
/// - deterministically ordered,
/// - compared against the previous accepted snapshot,
/// - emitted as immutable data.
///
/// A restarted/replaced subscription invalidates the old generation before
/// cancellation so late callbacks cannot corrupt the new conversation state.
final class MessageListener {
  MessageListener();

  final StreamController<MessageListenerSnapshot> _snapshotController =
      StreamController<MessageListenerSnapshot>.broadcast(sync: true);

  final StreamController<MessageListenerChange> _changeController =
      StreamController<MessageListenerChange>.broadcast(sync: true);

  final StreamController<Object> _errorController =
      StreamController<Object>.broadcast(sync: true);

  StreamSubscription<List<MessageEntity>>? _subscription;

  final Map<String, MessageEntity> _messagesById = <String, MessageEntity>{};

  String? _conversationId;

  int _generation = 0;

  bool _isListening = false;
  bool _isPaused = false;
  bool _isDisposed = false;

  // --------------------------------------------------------------------------
  // PUBLIC STATE
  // --------------------------------------------------------------------------

  String? get conversationId => _conversationId;

  int get generation => _generation;

  bool get isListening => _isListening;

  bool get isPaused => _isPaused;

  bool get isDisposed => _isDisposed;

  /// Immutable current accepted timeline.
  List<MessageEntity> get messages =>
      List<MessageEntity>.unmodifiable(_orderedMessages(_messagesById.values));

  Stream<MessageListenerSnapshot> get snapshots => _snapshotController.stream;

  Stream<MessageListenerChange> get changes => _changeController.stream;

  Stream<Object> get errors => _errorController.stream;

  // --------------------------------------------------------------------------
  // LISTENER LIFECYCLE
  // --------------------------------------------------------------------------

  /// Starts listening to a durable-message stream for [conversationId].
  ///
  /// Only one subscription may be active at a time.
  ///
  /// Calling this method again safely invalidates and cancels the previous
  /// subscription before the replacement is installed.
  Future<void> startListening({
    required String conversationId,
    required Stream<List<MessageEntity>> stream,
  }) async {
    _ensureNotDisposed();

    final String normalizedConversationId = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    // Critical stale-callback protection:
    // invalidate the previous generation BEFORE cancellation/replacement.
    final int listenerGeneration = ++_generation;

    final StreamSubscription<List<MessageEntity>>? previous = _subscription;

    _subscription = null;
    _isListening = false;
    _isPaused = false;

    if (previous != null) {
      await previous.cancel();
    }

    _conversationId = normalizedConversationId;
    _messagesById.clear();

    if (_isDisposed || listenerGeneration != _generation) {
      return;
    }

    late final StreamSubscription<List<MessageEntity>> subscription;

    subscription = stream.listen(
      (List<MessageEntity> incoming) {
        _handleSnapshot(
          incoming,
          conversationId: normalizedConversationId,
          listenerGeneration: listenerGeneration,
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        _handleError(
          error,
          stackTrace: stackTrace,
          listenerGeneration: listenerGeneration,
        );
      },
      onDone: () {
        _handleDone(subscription, listenerGeneration: listenerGeneration);
      },
      cancelOnError: false,
    );

    if (_isDisposed || listenerGeneration != _generation) {
      await subscription.cancel();
      return;
    }

    _subscription = subscription;
    _isListening = true;
  }

  /// Replaces the currently active realtime stream while preserving the same
  /// public lifecycle semantics as [startListening].
  Future<void> restartListening({
    required String conversationId,
    required Stream<List<MessageEntity>> stream,
  }) {
    return startListening(conversationId: conversationId, stream: stream);
  }

  /// Stops the current listener and clears conversation/timeline state.
  Future<void> stopListening() async {
    if (_isDisposed) {
      return;
    }

    // Invalidate callbacks before cancellation.
    ++_generation;

    final StreamSubscription<List<MessageEntity>>? subscription = _subscription;

    _subscription = null;
    _isListening = false;
    _isPaused = false;
    _conversationId = null;
    _messagesById.clear();

    if (subscription != null) {
      await subscription.cancel();
    }
  }

  /// Pauses the active subscription.
  ///
  /// Pausing does not clear the accepted timeline.
  void pauseListening() {
    _ensureNotDisposed();

    final StreamSubscription<List<MessageEntity>>? subscription = _subscription;

    if (subscription == null || !_isListening || _isPaused) {
      return;
    }

    subscription.pause();
    _isPaused = true;
  }

  /// Resumes a previously paused active subscription.
  void resumeListening() {
    _ensureNotDisposed();

    final StreamSubscription<List<MessageEntity>>? subscription = _subscription;

    if (subscription == null || !_isListening || !_isPaused) {
      return;
    }

    subscription.resume();
    _isPaused = false;
  }

  /// Clears accepted timeline data without cancelling the active subscription.
  ///
  /// The next valid stream emission becomes a fresh baseline and produces
  /// `added` events for its current durable messages.
  void clearSnapshot() {
    _ensureNotDisposed();
    _messagesById.clear();
  }

  // --------------------------------------------------------------------------
  // SNAPSHOT PROCESSING
  // --------------------------------------------------------------------------

  void _handleSnapshot(
    List<MessageEntity> incoming, {
    required String conversationId,
    required int listenerGeneration,
  }) {
    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    final Map<String, MessageEntity> nextById = <String, MessageEntity>{};

    for (final MessageEntity message in incoming) {
      final String messageId = _normalizeId(
        message.id,
        fieldName: 'message.id',
      );

      final String messageConversationId = _normalizeId(
        message.conversationId,
        fieldName: 'message.conversationId',
      );

      if (messageConversationId != conversationId) {
        _emitSafeError(
          MessageListenerException(
            code: MessageListenerErrorCode.invalidConversation,
            message: 'Realtime message belongs to a different conversation.',
            conversationId: conversationId,
            messageId: messageId,
          ),
          listenerGeneration: listenerGeneration,
        );
        continue;
      }

      // Canonical deduplication:
      // one final entity per Firestore/canonical message document ID.
      //
      // If the source list accidentally contains the same ID twice, retain the
      // deterministically newer/stronger representation.
      final MessageEntity? existing = nextById[messageId];

      if (existing == null) {
        nextById[messageId] = message;
      } else {
        nextById[messageId] = _choosePreferredVersion(existing, message);
      }
    }

    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    final List<MessageListenerChange> detectedChanges = _calculateChanges(
      previous: _messagesById,
      next: nextById,
    );

    if (_sameMessageSet(_messagesById, nextById)) {
      return;
    }

    _messagesById
      ..clear()
      ..addAll(nextById);

    final List<MessageEntity> ordered = _orderedMessages(_messagesById.values);

    final List<MessageListenerChange> orderedChanges = _orderedChanges(
      detectedChanges,
    );

    final MessageListenerSnapshot snapshot = MessageListenerSnapshot(
      conversationId: conversationId,
      messages: ordered,
      changes: orderedChanges,
      generation: listenerGeneration,
    );

    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    _snapshotController.add(snapshot);

    for (final MessageListenerChange change in orderedChanges) {
      if (!_isCurrentGeneration(listenerGeneration)) {
        return;
      }

      _changeController.add(change);
    }
  }

  List<MessageListenerChange> _calculateChanges({
    required Map<String, MessageEntity> previous,
    required Map<String, MessageEntity> next,
  }) {
    final List<MessageListenerChange> result = <MessageListenerChange>[];

    for (final MapEntry<String, MessageEntity> entry in next.entries) {
      final MessageEntity? oldMessage = previous[entry.key];
      final MessageEntity newMessage = entry.value;

      if (oldMessage == null) {
        result.add(
          MessageListenerChange(
            type: MessageListenerChangeType.added,
            messageId: entry.key,
            message: newMessage,
          ),
        );
        continue;
      }

      if (!_messageEquivalent(oldMessage, newMessage)) {
        result.add(
          MessageListenerChange(
            type: MessageListenerChangeType.modified,
            messageId: entry.key,
            message: newMessage,
            previousMessage: oldMessage,
          ),
        );
      }
    }

    for (final MapEntry<String, MessageEntity> entry in previous.entries) {
      if (next.containsKey(entry.key)) {
        continue;
      }

      result.add(
        MessageListenerChange(
          type: MessageListenerChangeType.removed,
          messageId: entry.key,
          previousMessage: entry.value,
        ),
      );
    }

    return result;
  }

  // --------------------------------------------------------------------------
  // ERROR / COMPLETION
  // --------------------------------------------------------------------------

  void _handleError(
    Object error, {
    required StackTrace stackTrace,
    required int listenerGeneration,
  }) {
    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    _emitSafeError(
      MessageListenerException(
        code: MessageListenerErrorCode.stream,
        message: 'The realtime message stream reported an error.',
        conversationId: _conversationId,
        cause: error,
        stackTrace: stackTrace,
      ),
      listenerGeneration: listenerGeneration,
    );
  }

  void _handleDone(
    StreamSubscription<List<MessageEntity>> subscription, {
    required int listenerGeneration,
  }) {
    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    if (!identical(_subscription, subscription)) {
      return;
    }

    _subscription = null;
    _isListening = false;
    _isPaused = false;
  }

  void _emitSafeError(Object error, {required int listenerGeneration}) {
    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    _errorController.add(error);
  }

  // --------------------------------------------------------------------------
  // DEDUPLICATION / RECONCILIATION
  // --------------------------------------------------------------------------

  static MessageEntity _choosePreferredVersion(
    MessageEntity first,
    MessageEntity second,
  ) {
    final DateTime? firstServer = first.serverCreatedAt;
    final DateTime? secondServer = second.serverCreatedAt;

    if (firstServer == null && secondServer != null) {
      return second;
    }

    if (firstServer != null && secondServer == null) {
      return first;
    }

    if (firstServer != null && secondServer != null) {
      final int comparison = secondServer.toUtc().compareTo(
        firstServer.toUtc(),
      );

      if (comparison > 0) {
        return second;
      }

      if (comparison < 0) {
        return first;
      }
    }

    final DateTime firstEffective =
        (first.serverCreatedAt ?? first.clientCreatedAt).toUtc();

    final DateTime secondEffective =
        (second.serverCreatedAt ?? second.clientCreatedAt).toUtc();

    if (secondEffective.isAfter(firstEffective)) {
      return second;
    }

    if (firstEffective.isAfter(secondEffective)) {
      return first;
    }

    // Same canonical ID and same effective timestamp:
    // prefer the latter source entry so server-side edits/status changes in
    // the newest incoming snapshot are not silently discarded.
    return second;
  }

  static bool _sameMessageSet(
    Map<String, MessageEntity> previous,
    Map<String, MessageEntity> next,
  ) {
    if (previous.length != next.length) {
      return false;
    }

    for (final MapEntry<String, MessageEntity> entry in next.entries) {
      final MessageEntity? previousMessage = previous[entry.key];

      if (previousMessage == null ||
          !_messageEquivalent(previousMessage, entry.value)) {
        return false;
      }
    }

    return true;
  }

  /// Uses the canonical serialized domain representation rather than object
  /// identity so immutable instances carrying identical durable state do not
  /// produce duplicate realtime events.
  static bool _messageEquivalent(MessageEntity first, MessageEntity second) {
    if (identical(first, second)) {
      return true;
    }

    if (first.id != second.id ||
        first.conversationId != second.conversationId) {
      return false;
    }

    return _deepMapEquals(first.toMap(), second.toMap());
  }

  static bool _deepMapEquals(
    Map<String, Object?> first,
    Map<String, Object?> second,
  ) {
    if (first.length != second.length) {
      return false;
    }

    for (final MapEntry<String, Object?> entry in first.entries) {
      if (!second.containsKey(entry.key)) {
        return false;
      }

      if (!_deepValueEquals(entry.value, second[entry.key])) {
        return false;
      }
    }

    return true;
  }

  static bool _deepValueEquals(Object? first, Object? second) {
    if (identical(first, second)) {
      return true;
    }

    if (first is DateTime && second is DateTime) {
      return first.toUtc() == second.toUtc();
    }

    if (first is Map && second is Map) {
      if (first.length != second.length) {
        return false;
      }

      for (final Object? rawKey in first.keys) {
        if (!second.containsKey(rawKey)) {
          return false;
        }

        if (!_deepValueEquals(first[rawKey], second[rawKey])) {
          return false;
        }
      }

      return true;
    }

    if (first is Iterable && second is Iterable) {
      final Iterator<Object?> firstIterator = first.cast<Object?>().iterator;

      final Iterator<Object?> secondIterator = second.cast<Object?>().iterator;

      while (true) {
        final bool firstMoved = firstIterator.moveNext();
        final bool secondMoved = secondIterator.moveNext();

        if (firstMoved != secondMoved) {
          return false;
        }

        if (!firstMoved) {
          return true;
        }

        if (!_deepValueEquals(firstIterator.current, secondIterator.current)) {
          return false;
        }
      }
    }

    return first == second;
  }

  // --------------------------------------------------------------------------
  // ORDERING
  // --------------------------------------------------------------------------

  static List<MessageEntity> _orderedMessages(Iterable<MessageEntity> source) {
    final List<MessageEntity> messages = List<MessageEntity>.of(source);

    messages.sort(_compareMessages);

    return messages;
  }

  /// Durable timeline ordering contract:
  /// 1. serverCreatedAt when available
  /// 2. otherwise clientCreatedAt
  /// 3. canonical message ID tie-break
  static int _compareMessages(MessageEntity first, MessageEntity second) {
    final DateTime firstTime = (first.serverCreatedAt ?? first.clientCreatedAt)
        .toUtc();

    final DateTime secondTime =
        (second.serverCreatedAt ?? second.clientCreatedAt).toUtc();

    final int timeComparison = firstTime.compareTo(secondTime);

    if (timeComparison != 0) {
      return timeComparison;
    }

    return first.id.compareTo(second.id);
  }

  static List<MessageListenerChange> _orderedChanges(
    Iterable<MessageListenerChange> source,
  ) {
    final List<MessageListenerChange> changes = List<MessageListenerChange>.of(
      source,
    );

    changes.sort((MessageListenerChange first, MessageListenerChange second) {
      final MessageEntity? firstMessage =
          first.message ?? first.previousMessage;

      final MessageEntity? secondMessage =
          second.message ?? second.previousMessage;

      if (firstMessage != null && secondMessage != null) {
        final int timelineComparison = _compareMessages(
          firstMessage,
          secondMessage,
        );

        if (timelineComparison != 0) {
          return timelineComparison;
        }
      }

      final int typeComparison = first.type.index.compareTo(second.type.index);

      if (typeComparison != 0) {
        return typeComparison;
      }

      return first.messageId.compareTo(second.messageId);
    });

    return changes;
  }

  // --------------------------------------------------------------------------
  // INTERNAL VALIDATION
  // --------------------------------------------------------------------------

  bool _isCurrentGeneration(int listenerGeneration) {
    return !_isDisposed && listenerGeneration == _generation;
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('MessageListener has already been disposed.');
    }
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

  // --------------------------------------------------------------------------
  // DISPOSAL
  // --------------------------------------------------------------------------

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    // Invalidate stale callbacks before cancelling.
    ++_generation;

    _isDisposed = true;
    _isListening = false;
    _isPaused = false;
    _conversationId = null;
    _messagesById.clear();

    final StreamSubscription<List<MessageEntity>>? subscription = _subscription;

    _subscription = null;

    if (subscription != null) {
      await subscription.cancel();
    }

    await _snapshotController.close();
    await _changeController.close();
    await _errorController.close();
  }
}

/// Stable listener-level error categories.
///
/// Raw backend exception text is intentionally not exposed as the public
/// message. The original cause remains available for internal diagnostics.
enum MessageListenerErrorCode { invalidConversation, stream }

/// Safe normalized realtime-listener exception.
final class MessageListenerException implements Exception {
  const MessageListenerException({
    required this.code,
    required this.message,
    this.conversationId,
    this.messageId,
    this.cause,
    this.stackTrace,
  });

  final MessageListenerErrorCode code;

  /// Safe description suitable for propagation to higher domain layers.
  final String message;

  final String? conversationId;
  final String? messageId;

  /// Internal diagnostic cause. Higher UI layers must not blindly display it.
  final Object? cause;

  final StackTrace? stackTrace;

  @override
  String toString() {
    return 'MessageListenerException('
        'code: ${code.name}, '
        'message: $message'
        ')';
  }
}

// ============================================================================
// END OF FILE: lib/features/message/realtime/message_listener.dart
// ============================================================================
