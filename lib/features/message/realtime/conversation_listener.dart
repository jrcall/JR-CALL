// ============================================================================
// JR CALL
// File: conversation_listener.dart
// Location: lib/features/message/realtime/conversation_listener.dart
// Description:
// Realtime inbox / conversation-list listener for JR CALL Message Engine.
//
// Owns:
// - One active realtime conversation-list subscription.
// - Canonical conversation-ID deduplication.
// - Stale subscription protection.
// - Deterministic inbox ordering.
// - Last-message / unread / archive / mute / pin-ready change observation.
// - Pagination-page merge support.
// - Immutable conversation snapshots.
// - Safe cancellation / restart / pause / resume / disposal.
//
// Does NOT own:
// - Firestore collection/query paths.
// - Conversation writes.
// - Message writes.
// - User discovery.
// - Firebase Auth credential creation.
// - UI/widget state.
// - Call Engine / WebRTC.
//
// Firestore query/path/pagination ownership remains in
// message_remote_store.dart / conversation_repository.dart.
// ============================================================================

import 'dart:async';

import '../data/conversation_entity.dart';

/// Type of realtime conversation-list change.
enum ConversationListenerChangeType { added, modified, removed }

/// Immutable single-conversation realtime change.
final class ConversationListenerChange {
  const ConversationListenerChange({
    required this.type,
    required this.conversationId,
    this.conversation,
    this.previousConversation,
  });

  final ConversationListenerChangeType type;
  final String conversationId;

  /// Present for [ConversationListenerChangeType.added] and
  /// [ConversationListenerChangeType.modified].
  final ConversationEntity? conversation;

  /// Present when an older accepted version existed.
  final ConversationEntity? previousConversation;

  bool get isAdded => type == ConversationListenerChangeType.added;

  bool get isModified => type == ConversationListenerChangeType.modified;

  bool get isRemoved => type == ConversationListenerChangeType.removed;
}

/// Immutable normalized inbox snapshot.
final class ConversationListenerSnapshot {
  ConversationListenerSnapshot({
    required String currentUserUid,
    required Iterable<ConversationEntity> conversations,
    required Iterable<ConversationListenerChange> changes,
    required int generation,
    required this.hasMore,
  }) : currentUserUid = _normalizeRequired(currentUserUid, 'currentUserUid'),
       conversations = List<ConversationEntity>.unmodifiable(conversations),
       changes = List<ConversationListenerChange>.unmodifiable(changes),
       generation = _validateGeneration(generation);

  /// Canonical Firebase Auth UID whose inbox is being observed.
  final String currentUserUid;

  final List<ConversationEntity> conversations;

  final List<ConversationListenerChange> changes;

  /// Current listener generation.
  final int generation;

  /// Pagination availability supplied by repository/storage coordination.
  ///
  /// This listener never guesses whether additional Firestore pages exist.
  final bool hasMore;

  bool get isEmpty => conversations.isEmpty;

  bool get isNotEmpty => conversations.isNotEmpty;

  int get length => conversations.length;

  bool get hasChanges => changes.isNotEmpty;

  static String _normalizeRequired(String value, String fieldName) {
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

  static int _validateGeneration(int value) {
    if (value < 0) {
      throw ArgumentError.value(
        value,
        'generation',
        'Generation must not be negative.',
      );
    }

    return value;
  }
}

/// Realtime inbox/conversation-list listener.
///
/// The stream supplied to [startListening] must contain conversations
/// authorized for [currentUserUid].
///
/// Firestore query construction remains outside this file.
///
/// Realtime and pagination responsibilities are intentionally separated:
/// - [startListening] owns the current realtime page/window.
/// - [mergePage] merges explicitly loaded older pagination results.
/// - realtime events replace/remove items only inside the realtime-owned set.
/// - pagination-owned items remain cached until explicitly replaced/cleared.
///
/// This prevents a newest-page realtime snapshot from accidentally deleting
/// older conversations already loaded through pagination.
final class ConversationListener {
  ConversationListener();

  final StreamController<ConversationListenerSnapshot> _snapshotController =
      StreamController<ConversationListenerSnapshot>.broadcast(sync: true);

  final StreamController<ConversationListenerChange> _changeController =
      StreamController<ConversationListenerChange>.broadcast(sync: true);

  final StreamController<Object> _errorController =
      StreamController<Object>.broadcast(sync: true);

  StreamSubscription<List<ConversationEntity>>? _subscription;

  /// Combined accepted inbox cache.
  final Map<String, ConversationEntity> _conversationsById =
      <String, ConversationEntity>{};

  /// IDs currently owned by the active realtime snapshot/window.
  final Set<String> _realtimeConversationIds = <String>{};

  /// IDs introduced through explicit pagination merge.
  ///
  /// An ID may exist in both sets when a later realtime window also contains
  /// a previously paginated conversation.
  final Set<String> _paginationConversationIds = <String>{};

  String? _currentUserUid;

  int _generation = 0;

  bool _hasMore = true;
  bool _isListening = false;
  bool _isPaused = false;
  bool _isDisposed = false;

  // --------------------------------------------------------------------------
  // PUBLIC STATE
  // --------------------------------------------------------------------------

  String? get currentUserUid => _currentUserUid;

  int get generation => _generation;

  bool get hasMore => _hasMore;

  bool get isListening => _isListening;

  bool get isPaused => _isPaused;

  bool get isDisposed => _isDisposed;

  List<ConversationEntity> get conversations =>
      List<ConversationEntity>.unmodifiable(
        _orderedConversations(_conversationsById.values),
      );

  Stream<ConversationListenerSnapshot> get snapshots =>
      _snapshotController.stream;

  Stream<ConversationListenerChange> get changes => _changeController.stream;

  Stream<Object> get errors => _errorController.stream;

  // --------------------------------------------------------------------------
  // LISTENER LIFECYCLE
  // --------------------------------------------------------------------------

  /// Starts one realtime inbox subscription for [currentUserUid].
  ///
  /// Calling this again invalidates the previous generation before
  /// cancellation so late callbacks cannot corrupt the replacement listener.
  Future<void> startListening({
    required String currentUserUid,
    required Stream<List<ConversationEntity>> stream,
    bool hasMore = true,
  }) async {
    _ensureNotDisposed();

    final String normalizedUid = _normalizeId(
      currentUserUid,
      fieldName: 'currentUserUid',
    );

    final int listenerGeneration = ++_generation;

    final StreamSubscription<List<ConversationEntity>>? previous =
        _subscription;

    _subscription = null;
    _isListening = false;
    _isPaused = false;

    if (previous != null) {
      await previous.cancel();
    }

    _currentUserUid = normalizedUid;
    _hasMore = hasMore;

    _conversationsById.clear();
    _realtimeConversationIds.clear();
    _paginationConversationIds.clear();

    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    late final StreamSubscription<List<ConversationEntity>> subscription;

    subscription = stream.listen(
      (List<ConversationEntity> incoming) {
        _handleRealtimeSnapshot(
          incoming,
          currentUserUid: normalizedUid,
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

    if (!_isCurrentGeneration(listenerGeneration)) {
      await subscription.cancel();
      return;
    }

    _subscription = subscription;
    _isListening = true;
  }

  Future<void> restartListening({
    required String currentUserUid,
    required Stream<List<ConversationEntity>> stream,
    bool hasMore = true,
  }) {
    return startListening(
      currentUserUid: currentUserUid,
      stream: stream,
      hasMore: hasMore,
    );
  }

  Future<void> stopListening() async {
    if (_isDisposed) {
      return;
    }

    ++_generation;

    final StreamSubscription<List<ConversationEntity>>? subscription =
        _subscription;

    _subscription = null;
    _isListening = false;
    _isPaused = false;

    _currentUserUid = null;
    _hasMore = true;

    _conversationsById.clear();
    _realtimeConversationIds.clear();
    _paginationConversationIds.clear();

    if (subscription != null) {
      await subscription.cancel();
    }
  }

  void pauseListening() {
    _ensureNotDisposed();

    final StreamSubscription<List<ConversationEntity>>? subscription =
        _subscription;

    if (subscription == null || !_isListening || _isPaused) {
      return;
    }

    subscription.pause();
    _isPaused = true;
  }

  void resumeListening() {
    _ensureNotDisposed();

    final StreamSubscription<List<ConversationEntity>>? subscription =
        _subscription;

    if (subscription == null || !_isListening || !_isPaused) {
      return;
    }

    subscription.resume();
    _isPaused = false;
  }

  /// Clears all accepted realtime/pagination inbox state without cancelling
  /// the current stream.
  ///
  /// The next realtime emission becomes a fresh realtime baseline.
  void clearSnapshot() {
    _ensureNotDisposed();

    if (_conversationsById.isEmpty) {
      return;
    }

    final List<ConversationListenerChange> removals = _conversationsById.entries
        .map(
          (MapEntry<String, ConversationEntity> entry) =>
              ConversationListenerChange(
                type: ConversationListenerChangeType.removed,
                conversationId: entry.key,
                previousConversation: entry.value,
              ),
        )
        .toList(growable: false);

    _conversationsById.clear();
    _realtimeConversationIds.clear();
    _paginationConversationIds.clear();

    _emitSnapshotAndChanges(removals, listenerGeneration: _generation);
  }

  // --------------------------------------------------------------------------
  // PAGINATION
  // --------------------------------------------------------------------------

  /// Merges an explicitly loaded conversation page into the current inbox.
  ///
  /// The repository/storage layer owns the actual Firestore pagination query.
  /// This method only reconciles its typed result.
  ///
  /// [hasMore] must be the real pagination state returned by the higher layer.
  void mergePage({
    required Iterable<ConversationEntity> conversations,
    required bool hasMore,
  }) {
    _ensureNotDisposed();

    final String? activeUid = _currentUserUid;

    if (activeUid == null) {
      throw StateError(
        'ConversationListener must be started before merging a page.',
      );
    }

    final int listenerGeneration = _generation;

    final Map<String, ConversationEntity> pageById =
        <String, ConversationEntity>{};

    for (final ConversationEntity conversation in conversations) {
      final ConversationEntity? accepted = _validateConversation(
        conversation,
        currentUserUid: activeUid,
        listenerGeneration: listenerGeneration,
      );

      if (accepted == null) {
        continue;
      }

      final String id = accepted.id.trim();
      final ConversationEntity? existing = pageById[id];

      pageById[id] = existing == null
          ? accepted
          : _choosePreferredVersion(existing, accepted);
    }

    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    final List<ConversationListenerChange> detectedChanges =
        <ConversationListenerChange>[];

    for (final MapEntry<String, ConversationEntity> entry in pageById.entries) {
      final ConversationEntity? previous = _conversationsById[entry.key];

      if (previous == null) {
        _conversationsById[entry.key] = entry.value;
        _paginationConversationIds.add(entry.key);

        detectedChanges.add(
          ConversationListenerChange(
            type: ConversationListenerChangeType.added,
            conversationId: entry.key,
            conversation: entry.value,
          ),
        );

        continue;
      }

      final ConversationEntity preferred = _choosePreferredVersion(
        previous,
        entry.value,
      );

      _paginationConversationIds.add(entry.key);

      if (!_conversationEquivalent(previous, preferred)) {
        _conversationsById[entry.key] = preferred;

        detectedChanges.add(
          ConversationListenerChange(
            type: ConversationListenerChangeType.modified,
            conversationId: entry.key,
            conversation: preferred,
            previousConversation: previous,
          ),
        );
      }
    }

    final bool paginationStateChanged = _hasMore != hasMore;
    _hasMore = hasMore;

    if (detectedChanges.isEmpty && !paginationStateChanged) {
      return;
    }

    _emitSnapshotAndChanges(
      detectedChanges,
      listenerGeneration: listenerGeneration,
    );
  }

  /// Updates only pagination availability.
  ///
  /// The listener never guesses pagination completion from list size.
  void setHasMore(bool value) {
    _ensureNotDisposed();

    if (_hasMore == value) {
      return;
    }

    _hasMore = value;

    if (_currentUserUid != null) {
      _emitSnapshotAndChanges(
        const <ConversationListenerChange>[],
        listenerGeneration: _generation,
      );
    }
  }

  // --------------------------------------------------------------------------
  // REALTIME PROCESSING
  // --------------------------------------------------------------------------

  void _handleRealtimeSnapshot(
    List<ConversationEntity> incoming, {
    required String currentUserUid,
    required int listenerGeneration,
  }) {
    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    final Map<String, ConversationEntity> nextRealtime =
        <String, ConversationEntity>{};

    for (final ConversationEntity conversation in incoming) {
      final ConversationEntity? accepted = _validateConversation(
        conversation,
        currentUserUid: currentUserUid,
        listenerGeneration: listenerGeneration,
      );

      if (accepted == null) {
        continue;
      }

      final String id = accepted.id.trim();

      final ConversationEntity? existing = nextRealtime[id];

      nextRealtime[id] = existing == null
          ? accepted
          : _choosePreferredVersion(existing, accepted);
    }

    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    final Set<String> previousRealtimeIds = Set<String>.of(
      _realtimeConversationIds,
    );

    final List<ConversationListenerChange> detectedChanges =
        <ConversationListenerChange>[];

    // Added / modified conversations from the new realtime window.
    for (final MapEntry<String, ConversationEntity> entry
        in nextRealtime.entries) {
      final ConversationEntity? previous = _conversationsById[entry.key];

      if (previous == null) {
        _conversationsById[entry.key] = entry.value;

        detectedChanges.add(
          ConversationListenerChange(
            type: ConversationListenerChangeType.added,
            conversationId: entry.key,
            conversation: entry.value,
          ),
        );
      } else {
        final ConversationEntity preferred = _choosePreferredVersion(
          previous,
          entry.value,
        );

        if (!_conversationEquivalent(previous, preferred)) {
          _conversationsById[entry.key] = preferred;

          detectedChanges.add(
            ConversationListenerChange(
              type: ConversationListenerChangeType.modified,
              conversationId: entry.key,
              conversation: preferred,
              previousConversation: previous,
            ),
          );
        }
      }
    }

    // Conversations removed from the realtime-owned window are deleted from
    // the combined cache only if pagination does not independently retain
    // them.
    for (final String previousId in previousRealtimeIds) {
      if (nextRealtime.containsKey(previousId)) {
        continue;
      }

      if (_paginationConversationIds.contains(previousId)) {
        continue;
      }

      final ConversationEntity? removed = _conversationsById.remove(previousId);

      if (removed != null) {
        detectedChanges.add(
          ConversationListenerChange(
            type: ConversationListenerChangeType.removed,
            conversationId: previousId,
            previousConversation: removed,
          ),
        );
      }
    }

    _realtimeConversationIds
      ..clear()
      ..addAll(nextRealtime.keys);

    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    if (detectedChanges.isEmpty) {
      return;
    }

    _emitSnapshotAndChanges(
      detectedChanges,
      listenerGeneration: listenerGeneration,
    );
  }

  ConversationEntity? _validateConversation(
    ConversationEntity conversation, {
    required String currentUserUid,
    required int listenerGeneration,
  }) {
    String conversationId;

    try {
      conversationId = _normalizeId(
        conversation.id,
        fieldName: 'conversation.id',
      );
    } on ArgumentError {
      _emitSafeError(
        ConversationListenerException(
          code: ConversationListenerErrorCode.invalidConversation,
          message: 'Conversation update contains an invalid conversation ID.',
          currentUserUid: currentUserUid,
        ),
        listenerGeneration: listenerGeneration,
      );

      return null;
    }

    final List<String> participantUids = conversation.participantUids
        .map((String uid) => uid.trim())
        .where((String uid) => uid.isNotEmpty)
        .toList(growable: false);

    if (!participantUids.contains(currentUserUid)) {
      _emitSafeError(
        ConversationListenerException(
          code: ConversationListenerErrorCode.unauthorizedConversation,
          message:
              'Conversation update does not include the current Firebase user.',
          conversationId: conversationId,
          currentUserUid: currentUserUid,
        ),
        listenerGeneration: listenerGeneration,
      );

      return null;
    }

    return conversation;
  }

  // --------------------------------------------------------------------------
  // RECONCILIATION
  // --------------------------------------------------------------------------

  /// Chooses the stronger/newer representation of the same canonical
  /// conversation ID.
  ///
  /// [ConversationEntity.updatedAt] is the primary entity freshness source.
  /// [ConversationEntity.lastMessageAt] is an additional deterministic signal.
  ///
  /// Equal freshness prefers [second], allowing the newest stream/page entry
  /// to carry summary/unread/archive/mute/pin-ready map changes without
  /// generating duplicate conversation rows.
  static ConversationEntity _choosePreferredVersion(
    ConversationEntity first,
    ConversationEntity second,
  ) {
    final DateTime firstUpdated = first.updatedAt.toUtc();
    final DateTime secondUpdated = second.updatedAt.toUtc();

    if (secondUpdated.isAfter(firstUpdated)) {
      return second;
    }

    if (firstUpdated.isAfter(secondUpdated)) {
      return first;
    }

    final DateTime? firstLast = first.lastMessageAt?.toUtc();
    final DateTime? secondLast = second.lastMessageAt?.toUtc();

    if (firstLast == null && secondLast != null) {
      return second;
    }

    if (firstLast != null && secondLast == null) {
      return first;
    }

    if (firstLast != null && secondLast != null) {
      if (secondLast.isAfter(firstLast)) {
        return second;
      }

      if (firstLast.isAfter(secondLast)) {
        return first;
      }
    }

    return second;
  }

  static bool _conversationEquivalent(
    ConversationEntity first,
    ConversationEntity second,
  ) {
    if (identical(first, second)) {
      return true;
    }

    if (first.id != second.id) {
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

      for (final Object? key in first.keys) {
        if (!second.containsKey(key)) {
          return false;
        }

        if (!_deepValueEquals(first[key], second[key])) {
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

  static List<ConversationEntity> _orderedConversations(
    Iterable<ConversationEntity> source,
  ) {
    final List<ConversationEntity> result = List<ConversationEntity>.of(source);

    result.sort(_compareConversations);

    return result;
  }

  /// Inbox ordering:
  ///
  /// 1. Active/non-archived before archived when the entity map contains
  ///    archive state.
  /// 2. Pinned conversations before non-pinned when the entity map contains
  ///    pin state.
  /// 3. Newest actual [ConversationEntity.lastMessageAt].
  /// 4. Fallback to [ConversationEntity.updatedAt].
  /// 5. Canonical conversation ID tie-break.
  ///
  /// Archive/pin are intentionally read through the frozen entity's serialized
  /// map instead of assuming optional getters exist on ConversationEntity.
  ///
  /// No synthetic activity timestamp is invented.
  static int _compareConversations(
    ConversationEntity first,
    ConversationEntity second,
  ) {
    final Map<String, Object?> firstMap = first.toMap();
    final Map<String, Object?> secondMap = second.toMap();

    final bool firstArchived = _readBool(firstMap, const <String>[
      'archived',
      'isArchived',
    ]);

    final bool secondArchived = _readBool(secondMap, const <String>[
      'archived',
      'isArchived',
    ]);

    if (firstArchived != secondArchived) {
      return firstArchived ? 1 : -1;
    }

    final bool firstPinned = _readBool(firstMap, const <String>[
      'pinned',
      'isPinned',
    ]);

    final bool secondPinned = _readBool(secondMap, const <String>[
      'pinned',
      'isPinned',
    ]);

    if (firstPinned != secondPinned) {
      return firstPinned ? -1 : 1;
    }

    final DateTime firstActivity = (first.lastMessageAt ?? first.updatedAt)
        .toUtc();

    final DateTime secondActivity = (second.lastMessageAt ?? second.updatedAt)
        .toUtc();

    final int activityComparison = secondActivity.compareTo(firstActivity);

    if (activityComparison != 0) {
      return activityComparison;
    }

    return first.id.compareTo(second.id);
  }

  /// Safely reads an optional boolean capability from the canonical serialized
  /// entity representation.
  ///
  /// Missing or malformed optional state is treated as false. This keeps
  /// ConversationListener compatible with ConversationEntity versions where
  /// archive/pin support is represented in serialized data but no dedicated
  /// Dart getter is exposed.
  static bool _readBool(Map<String, Object?> map, List<String> keys) {
    for (final String key in keys) {
      final Object? value = map[key];

      if (value is bool) {
        return value;
      }

      if (value is num) {
        return value != 0;
      }

      if (value is String) {
        final String normalized = value.trim().toLowerCase();

        if (normalized == 'true' || normalized == '1') {
          return true;
        }

        if (normalized == 'false' || normalized == '0' || normalized.isEmpty) {
          return false;
        }
      }
    }

    return false;
  }

  static List<ConversationListenerChange> _orderedChanges(
    Iterable<ConversationListenerChange> source,
  ) {
    final List<ConversationListenerChange> result =
        List<ConversationListenerChange>.of(source);

    result.sort((
      ConversationListenerChange first,
      ConversationListenerChange second,
    ) {
      final ConversationEntity? firstConversation =
          first.conversation ?? first.previousConversation;

      final ConversationEntity? secondConversation =
          second.conversation ?? second.previousConversation;

      if (firstConversation != null && secondConversation != null) {
        final int comparison = _compareConversations(
          firstConversation,
          secondConversation,
        );

        if (comparison != 0) {
          return comparison;
        }
      }

      final int typeComparison = first.type.index.compareTo(second.type.index);

      if (typeComparison != 0) {
        return typeComparison;
      }

      return first.conversationId.compareTo(second.conversationId);
    });

    return result;
  }

  // --------------------------------------------------------------------------
  // EMISSION
  // --------------------------------------------------------------------------

  void _emitSnapshotAndChanges(
    Iterable<ConversationListenerChange> changes, {
    required int listenerGeneration,
  }) {
    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    final String? activeUid = _currentUserUid;

    if (activeUid == null) {
      return;
    }

    final List<ConversationListenerChange> orderedChanges = _orderedChanges(
      changes,
    );

    final ConversationListenerSnapshot snapshot = ConversationListenerSnapshot(
      currentUserUid: activeUid,
      conversations: _orderedConversations(_conversationsById.values),
      changes: orderedChanges,
      generation: listenerGeneration,
      hasMore: _hasMore,
    );

    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    _snapshotController.add(snapshot);

    for (final ConversationListenerChange change in orderedChanges) {
      if (!_isCurrentGeneration(listenerGeneration)) {
        return;
      }

      _changeController.add(change);
    }
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
      ConversationListenerException(
        code: ConversationListenerErrorCode.stream,
        message: 'The realtime conversation stream reported an error.',
        currentUserUid: _currentUserUid,
        cause: error,
        stackTrace: stackTrace,
      ),
      listenerGeneration: listenerGeneration,
    );
  }

  void _handleDone(
    StreamSubscription<List<ConversationEntity>> subscription, {
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
  // INTERNAL VALIDATION
  // --------------------------------------------------------------------------

  bool _isCurrentGeneration(int listenerGeneration) {
    return !_isDisposed && listenerGeneration == _generation;
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('ConversationListener has already been disposed.');
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

    ++_generation;

    _isDisposed = true;
    _isListening = false;
    _isPaused = false;

    final StreamSubscription<List<ConversationEntity>>? subscription =
        _subscription;

    _subscription = null;
    _currentUserUid = null;
    _hasMore = true;

    _conversationsById.clear();
    _realtimeConversationIds.clear();
    _paginationConversationIds.clear();

    if (subscription != null) {
      await subscription.cancel();
    }

    await _snapshotController.close();
    await _changeController.close();
    await _errorController.close();
  }
}

/// Stable conversation-list listener error categories.
enum ConversationListenerErrorCode {
  invalidConversation,
  unauthorizedConversation,
  stream,
}

/// Safe normalized realtime conversation-list exception.
///
/// [cause] is retained only for internal diagnostics. UI layers must not
/// blindly display raw backend exception text.
final class ConversationListenerException implements Exception {
  const ConversationListenerException({
    required this.code,
    required this.message,
    this.conversationId,
    this.currentUserUid,
    this.cause,
    this.stackTrace,
  });

  final ConversationListenerErrorCode code;

  final String message;

  final String? conversationId;

  /// Canonical Firebase UID involved in this listener session.
  final String? currentUserUid;

  final Object? cause;

  final StackTrace? stackTrace;

  @override
  String toString() {
    return 'ConversationListenerException('
        'code: ${code.name}, '
        'message: $message'
        ')';
  }
}

// ============================================================================
// END OF FILE: lib/features/message/realtime/conversation_listener.dart
// ============================================================================
