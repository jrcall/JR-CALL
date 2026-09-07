// ============================================================================
// JR CALL
// File: conversation_controller.dart
// Location: lib/features/message/controller/conversation_controller.dart
// Description:
// UI-facing controller for the JR CALL Message inbox/conversation list.
//
// Owns:
// - Conversation list state.
// - Deterministic inbox ordering.
// - Initial loading / refresh state.
// - Pagination state.
// - Realtime listener lifecycle.
// - Unread badge state from real ConversationEntity data.
// - Open/find-or-create direct conversation coordination.
// - Archive / mute / pin-ready conversation operations.
// - Safe error exposure.
// - Subscription/disposal lifecycle.
//
// Does NOT:
// - Call Firestore directly.
// - Perform global user discovery.
// - Use public JR CALL ID as ownership identity.
// - Render chat tiles/message bubbles.
// - Invent unread/presence/delivery/read state.
// - Recreate Call Engine/WebRTC.
// ============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/conversation_entity.dart';
import '../repository/conversation_repository.dart';

enum ConversationControllerOperation {
  idle,
  loading,
  refreshing,
  paginating,
  opening,
  archiving,
  muting,
  pinning,
}

@immutable
final class ConversationControllerState {
  const ConversationControllerState({
    required this.conversations,
    required this.operation,
    required this.isInitialized,
    required this.isListening,
    required this.hasMore,
    required this.errorMessage,
  });

  const ConversationControllerState.initial()
    : conversations = const <ConversationEntity>[],
      operation = ConversationControllerOperation.idle,
      isInitialized = false,
      isListening = false,
      hasMore = true,
      errorMessage = null;

  final List<ConversationEntity> conversations;
  final ConversationControllerOperation operation;
  final bool isInitialized;
  final bool isListening;
  final bool hasMore;
  final String? errorMessage;

  bool get isLoading =>
      operation == ConversationControllerOperation.loading &&
      conversations.isEmpty;

  bool get isRefreshing =>
      operation == ConversationControllerOperation.refreshing;

  bool get isPaginating =>
      operation == ConversationControllerOperation.paginating;

  bool get isOpening => operation == ConversationControllerOperation.opening;

  bool get isBusy => operation != ConversationControllerOperation.idle;

  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;

  int unreadCountFor(String uid) {
    final String normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      return 0;
    }

    var total = 0;

    for (final ConversationEntity conversation in conversations) {
      final int unread = conversation.unreadCountFor(normalizedUid);

      if (unread > 0) {
        total += unread;
      }
    }

    return total;
  }

  ConversationControllerState copyWith({
    List<ConversationEntity>? conversations,
    ConversationControllerOperation? operation,
    bool? isInitialized,
    bool? isListening,
    bool? hasMore,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ConversationControllerState(
      conversations: conversations ?? this.conversations,
      operation: operation ?? this.operation,
      isInitialized: isInitialized ?? this.isInitialized,
      isListening: isListening ?? this.isListening,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

/// JR CALL inbox/conversation-list controller.
///
/// One instance represents one authenticated Firebase UID.
/// Firebase UID remains the canonical internal identity.
final class ConversationController extends ChangeNotifier {
  factory ConversationController({
    required ConversationRepository repository,
    required String currentUserUid,
    int pageSize = 30,
  }) {
    return ConversationController._(
      repository: repository,
      rawCurrentUserUid: currentUserUid,
      pageSize: pageSize,
    );
  }

  ConversationController._({
    required this._repository,
    required String rawCurrentUserUid,
    required this.pageSize,
  }) : currentUserUid = rawCurrentUserUid.trim() {
    if (currentUserUid.isEmpty) {
      throw ArgumentError.value(
        rawCurrentUserUid,
        'currentUserUid',
        'Current Firebase UID must not be empty.',
      );
    }

    if (pageSize <= 0) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'Page size must be greater than zero.',
      );
    }
  }

  final ConversationRepository _repository;

  /// Canonical authenticated Firebase UID.
  final String currentUserUid;

  /// Number of conversation records requested per page.
  final int pageSize;

  ConversationControllerState _state =
      const ConversationControllerState.initial();

  StreamSubscription<List<ConversationEntity>>? _subscription;

  Object? _paginationCursor;

  int _listenerGeneration = 0;
  int _loadGeneration = 0;

  bool _disposed = false;
  bool _loading = false;
  bool _paginating = false;
  bool _opening = false;
  bool _archiving = false;
  bool _muting = false;
  bool _pinning = false;

  ConversationControllerState get state => _state;

  List<ConversationEntity> get conversations => _state.conversations;

  bool get isInitialized => _state.isInitialized;
  bool get isListening => _state.isListening;
  bool get isLoading => _state.isLoading;
  bool get isRefreshing => _state.isRefreshing;
  bool get isPaginating => _state.isPaginating;
  bool get isOpening => _state.isOpening;
  bool get hasMore => _state.hasMore;
  bool get hasError => _state.hasError;
  bool get isDisposed => _disposed;

  String? get errorMessage => _state.errorMessage;

  int get totalUnreadCount => _state.unreadCountFor(currentUserUid);

  Future<void> initialize() async {
    _ensureNotDisposed();

    if (_loading) {
      return;
    }

    _loading = true;

    final int generation = ++_loadGeneration;

    _setState(
      _state.copyWith(
        operation: ConversationControllerOperation.loading,
        clearError: true,
      ),
    );

    try {
      final ConversationRepositoryPage page = await _repository.load(
        requesterUid: currentUserUid,
        limit: pageSize,
      );

      if (!_isCurrentLoadGeneration(generation)) {
        return;
      }

      final List<ConversationEntity> normalized = _normalizeConversations(
        page.conversations,
      );

      _paginationCursor = page.cursor;

      _setState(
        _state.copyWith(
          conversations: normalized,
          operation: ConversationControllerOperation.idle,
          isInitialized: true,
          hasMore: page.hasMore,
          clearError: true,
        ),
      );

      await _bindListener();
    } catch (error) {
      if (_isCurrentLoadGeneration(generation)) {
        _setState(
          _state.copyWith(
            operation: ConversationControllerOperation.idle,
            isInitialized: true,
            errorMessage: _safeErrorMessage(
              error,
              fallback: 'Unable to load conversations.',
            ),
          ),
        );
      }
    } finally {
      if (_isCurrentLoadGeneration(generation)) {
        _loading = false;
      }
    }
  }

  Future<void> refresh() async {
    _ensureNotDisposed();

    if (_loading) {
      return;
    }

    _loading = true;

    final int generation = ++_loadGeneration;

    _setState(
      _state.copyWith(
        operation: ConversationControllerOperation.refreshing,
        clearError: true,
      ),
    );

    try {
      final ConversationRepositoryPage page = await _repository.load(
        requesterUid: currentUserUid,
        limit: pageSize,
      );

      if (!_isCurrentLoadGeneration(generation)) {
        return;
      }

      final List<ConversationEntity> merged = _mergeConversations(
        local: _state.conversations,
        remote: page.conversations,
      );

      _paginationCursor = page.cursor;

      _setState(
        _state.copyWith(
          conversations: merged,
          operation: ConversationControllerOperation.idle,
          isInitialized: true,
          hasMore: page.hasMore,
          clearError: true,
        ),
      );

      if (!_state.isListening) {
        await _bindListener();
      }
    } catch (error) {
      if (_isCurrentLoadGeneration(generation)) {
        _setState(
          _state.copyWith(
            operation: ConversationControllerOperation.idle,
            errorMessage: _safeErrorMessage(
              error,
              fallback: 'Unable to refresh conversations.',
            ),
          ),
        );
      }
    } finally {
      if (_isCurrentLoadGeneration(generation)) {
        _loading = false;
      }
    }
  }

  Future<void> loadMore() async {
    _ensureNotDisposed();

    if (_paginating || !_state.hasMore) {
      return;
    }

    final Object? cursor = _paginationCursor;

    if (cursor == null) {
      _setState(_state.copyWith(hasMore: false));
      return;
    }

    _paginating = true;

    _setState(
      _state.copyWith(
        operation: ConversationControllerOperation.paginating,
        clearError: true,
      ),
    );

    try {
      final ConversationRepositoryPage page = await _repository.paginate(
        requesterUid: currentUserUid,
        cursor: cursor,
        limit: pageSize,
      );

      if (_disposed) {
        return;
      }

      final List<ConversationEntity> merged = _mergeConversations(
        local: _state.conversations,
        remote: page.conversations,
      );

      _paginationCursor = page.cursor;

      _setState(
        _state.copyWith(
          conversations: merged,
          operation: ConversationControllerOperation.idle,
          hasMore: page.hasMore,
          clearError: true,
        ),
      );
    } catch (error) {
      if (!_disposed) {
        _setState(
          _state.copyWith(
            operation: ConversationControllerOperation.idle,
            errorMessage: _safeErrorMessage(
              error,
              fallback: 'Unable to load more conversations.',
            ),
          ),
        );
      }
    } finally {
      _paginating = false;
    }
  }

  Future<ConversationEntity?> openDirectConversation({
    required String peerUid,
  }) async {
    _ensureNotDisposed();

    final String normalizedPeerUid = peerUid.trim();

    if (normalizedPeerUid.isEmpty) {
      _setError('Unable to open this conversation.');
      return null;
    }

    if (normalizedPeerUid == currentUserUid) {
      _setError('You cannot start a direct conversation with yourself.');
      return null;
    }

    if (_opening) {
      return null;
    }

    _opening = true;

    _setState(
      _state.copyWith(
        operation: ConversationControllerOperation.opening,
        clearError: true,
      ),
    );

    try {
      final ConversationEntity conversation = await _repository
          .findOrCreateDirect(
            currentUid: currentUserUid,
            peerUid: normalizedPeerUid,
          );

      if (_disposed) {
        return conversation;
      }

      _assertAccessibleConversation(conversation);
      _upsertConversation(conversation);

      _setState(
        _state.copyWith(
          operation: ConversationControllerOperation.idle,
          clearError: true,
        ),
      );

      return conversation;
    } catch (error) {
      if (!_disposed) {
        _setState(
          _state.copyWith(
            operation: ConversationControllerOperation.idle,
            errorMessage: _safeErrorMessage(
              error,
              fallback: 'Unable to open conversation.',
            ),
          ),
        );
      }

      return null;
    } finally {
      _opening = false;
    }
  }

  ConversationEntity? findConversation(String conversationId) {
    final String normalized = conversationId.trim();

    if (normalized.isEmpty) {
      return null;
    }

    for (final ConversationEntity conversation in _state.conversations) {
      if (conversation.id == normalized) {
        return conversation;
      }
    }

    return null;
  }

  Future<ConversationEntity?> setArchived({
    required String conversationId,
    required bool archived,
  }) async {
    _ensureNotDisposed();

    if (_archiving) {
      return null;
    }

    final ConversationEntity? existing = findConversation(conversationId);

    if (existing == null) {
      _setError('Conversation is no longer available.');
      return null;
    }

    _assertAccessibleConversation(existing);

    _archiving = true;

    _setState(
      _state.copyWith(
        operation: ConversationControllerOperation.archiving,
        clearError: true,
      ),
    );

    try {
      final ConversationEntity updated = await _repository.setArchived(
        conversationId: existing.id,
        requesterUid: currentUserUid,
        archived: archived,
      );

      if (_disposed) {
        return updated;
      }

      _assertAccessibleConversation(updated);
      _upsertConversation(updated);

      _setState(
        _state.copyWith(
          operation: ConversationControllerOperation.idle,
          clearError: true,
        ),
      );

      return updated;
    } catch (error) {
      if (!_disposed) {
        _setState(
          _state.copyWith(
            operation: ConversationControllerOperation.idle,
            errorMessage: _safeErrorMessage(
              error,
              fallback: 'Unable to update archive state.',
            ),
          ),
        );
      }

      return null;
    } finally {
      _archiving = false;
    }
  }

  Future<ConversationEntity?> setMuted({
    required String conversationId,
    required bool muted,
  }) async {
    _ensureNotDisposed();

    if (_muting) {
      return null;
    }

    final ConversationEntity? existing = findConversation(conversationId);

    if (existing == null) {
      _setError('Conversation is no longer available.');
      return null;
    }

    _assertAccessibleConversation(existing);

    _muting = true;

    _setState(
      _state.copyWith(
        operation: ConversationControllerOperation.muting,
        clearError: true,
      ),
    );

    try {
      final ConversationEntity updated = await _repository.setMuted(
        conversationId: existing.id,
        requesterUid: currentUserUid,
        muted: muted,
      );

      if (_disposed) {
        return updated;
      }

      _assertAccessibleConversation(updated);
      _upsertConversation(updated);

      _setState(
        _state.copyWith(
          operation: ConversationControllerOperation.idle,
          clearError: true,
        ),
      );

      return updated;
    } catch (error) {
      if (!_disposed) {
        _setState(
          _state.copyWith(
            operation: ConversationControllerOperation.idle,
            errorMessage: _safeErrorMessage(
              error,
              fallback: 'Unable to update mute state.',
            ),
          ),
        );
      }

      return null;
    } finally {
      _muting = false;
    }
  }

  Future<ConversationEntity?> setPinned({
    required String conversationId,
    required bool pinned,
  }) async {
    _ensureNotDisposed();

    if (_pinning) {
      return null;
    }

    final ConversationEntity? existing = findConversation(conversationId);

    if (existing == null) {
      _setError('Conversation is no longer available.');
      return null;
    }

    _assertAccessibleConversation(existing);

    _pinning = true;

    _setState(
      _state.copyWith(
        operation: ConversationControllerOperation.pinning,
        clearError: true,
      ),
    );

    try {
      final ConversationEntity updated = await _repository.setPinned(
        conversationId: existing.id,
        requesterUid: currentUserUid,
        pinned: pinned,
      );

      if (_disposed) {
        return updated;
      }

      _assertAccessibleConversation(updated);
      _upsertConversation(updated);

      _setState(
        _state.copyWith(
          operation: ConversationControllerOperation.idle,
          clearError: true,
        ),
      );

      return updated;
    } catch (error) {
      if (!_disposed) {
        _setState(
          _state.copyWith(
            operation: ConversationControllerOperation.idle,
            errorMessage: _safeErrorMessage(
              error,
              fallback: 'Unable to update pin state.',
            ),
          ),
        );
      }

      return null;
    } finally {
      _pinning = false;
    }
  }

  Future<void> restartListener() async {
    _ensureNotDisposed();
    await _bindListener(forceRestart: true);
  }

  void clearError() {
    _ensureNotDisposed();

    if (!_state.hasError) {
      return;
    }

    _setState(_state.copyWith(clearError: true));
  }

  Future<void> _bindListener({bool forceRestart = false}) async {
    _ensureNotDisposed();

    if (!forceRestart && _subscription != null) {
      return;
    }

    final int generation = ++_listenerGeneration;

    final StreamSubscription<List<ConversationEntity>>? previous =
        _subscription;

    _subscription = null;

    if (previous != null) {
      await previous.cancel();
    }

    if (_disposed || generation != _listenerGeneration) {
      return;
    }

    final Stream<List<ConversationEntity>> stream = _repository.listen(
      requesterUid: currentUserUid,
    );

    _subscription = stream.listen(
      (List<ConversationEntity> incoming) {
        if (_disposed || generation != _listenerGeneration) {
          return;
        }

        final List<ConversationEntity> merged = _mergeConversations(
          local: _state.conversations,
          remote: incoming,
        );

        _setState(
          _state.copyWith(
            conversations: merged,
            isListening: true,
            clearError: true,
          ),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_disposed || generation != _listenerGeneration) {
          return;
        }

        _setState(
          _state.copyWith(
            isListening: false,
            errorMessage: _safeErrorMessage(
              error,
              fallback: 'Conversation synchronization was interrupted.',
            ),
          ),
        );
      },
      onDone: () {
        if (_disposed || generation != _listenerGeneration) {
          return;
        }

        _subscription = null;

        _setState(_state.copyWith(isListening: false));
      },
      cancelOnError: false,
    );

    if (!_disposed && generation == _listenerGeneration) {
      _setState(_state.copyWith(isListening: true));
    }
  }

  void _upsertConversation(ConversationEntity conversation) {
    if (_disposed) {
      return;
    }

    final Map<String, ConversationEntity> byId = <String, ConversationEntity>{
      for (final ConversationEntity item in _state.conversations) item.id: item,
    };

    final ConversationEntity? current = byId[conversation.id];

    byId[conversation.id] = current == null
        ? conversation
        : _preferConversationVersion(current, conversation);

    final List<ConversationEntity> normalized = _normalizeConversations(
      byId.values,
    );

    _setState(_state.copyWith(conversations: normalized));
  }

  List<ConversationEntity> _mergeConversations({
    required Iterable<ConversationEntity> local,
    required Iterable<ConversationEntity> remote,
  }) {
    final Map<String, ConversationEntity> merged =
        <String, ConversationEntity>{};

    for (final ConversationEntity conversation in local) {
      if (!_containsCurrentUser(conversation)) {
        continue;
      }

      final String id = conversation.id.trim();

      if (id.isEmpty) {
        continue;
      }

      merged[id] = conversation;
    }

    for (final ConversationEntity incoming in remote) {
      if (!_containsCurrentUser(incoming)) {
        continue;
      }

      final String id = incoming.id.trim();

      if (id.isEmpty) {
        continue;
      }

      final ConversationEntity? existing = merged[id];

      merged[id] = existing == null
          ? incoming
          : _preferConversationVersion(existing, incoming);
    }

    return _normalizeConversations(merged.values);
  }

  List<ConversationEntity> _normalizeConversations(
    Iterable<ConversationEntity> source,
  ) {
    final Map<String, ConversationEntity> unique =
        <String, ConversationEntity>{};

    for (final ConversationEntity conversation in source) {
      final String id = conversation.id.trim();

      if (id.isEmpty || !_containsCurrentUser(conversation)) {
        continue;
      }

      final ConversationEntity? previous = unique[id];

      unique[id] = previous == null
          ? conversation
          : _preferConversationVersion(previous, conversation);
    }

    final List<ConversationEntity> result = unique.values.toList(
      growable: false,
    );

    result.sort(_compareConversations);

    return List<ConversationEntity>.unmodifiable(result);
  }

  ConversationEntity _preferConversationVersion(
    ConversationEntity current,
    ConversationEntity candidate,
  ) {
    if (candidate.updatedAt.isAfter(current.updatedAt)) {
      return candidate;
    }

    if (current.updatedAt.isAfter(candidate.updatedAt)) {
      return current;
    }

    final DateTime candidateTime = _conversationSortTime(candidate);
    final DateTime currentTime = _conversationSortTime(current);

    if (candidateTime.isAfter(currentTime)) {
      return candidate;
    }

    if (currentTime.isAfter(candidateTime)) {
      return current;
    }

    return candidate.id.compareTo(current.id) >= 0 ? candidate : current;
  }

  int _compareConversations(ConversationEntity left, ConversationEntity right) {
    final bool leftPinned = left.isPinnedFor(currentUserUid);
    final bool rightPinned = right.isPinnedFor(currentUserUid);

    if (leftPinned != rightPinned) {
      return leftPinned ? -1 : 1;
    }

    final DateTime leftTime = _conversationSortTime(left);
    final DateTime rightTime = _conversationSortTime(right);

    final int timeOrder = rightTime.compareTo(leftTime);

    if (timeOrder != 0) {
      return timeOrder;
    }

    final int updatedOrder = right.updatedAt.compareTo(left.updatedAt);

    if (updatedOrder != 0) {
      return updatedOrder;
    }

    return left.id.compareTo(right.id);
  }

  DateTime _conversationSortTime(ConversationEntity conversation) {
    return conversation.lastMessageAt ?? conversation.updatedAt;
  }

  bool _containsCurrentUser(ConversationEntity conversation) {
    return conversation.participantUids.contains(currentUserUid);
  }

  void _assertAccessibleConversation(ConversationEntity conversation) {
    if (conversation.id.trim().isEmpty) {
      throw StateError('Conversation ID must not be empty.');
    }

    if (!_containsCurrentUser(conversation)) {
      throw StateError(
        'Current Firebase UID is not a participant in this conversation.',
      );
    }
  }

  bool _isCurrentLoadGeneration(int generation) {
    return !_disposed && generation == _loadGeneration;
  }

  String _safeErrorMessage(Object error, {required String fallback}) {
    return fallback;
  }

  void _setError(String message) {
    if (_disposed) {
      return;
    }

    _setState(_state.copyWith(errorMessage: message));
  }

  void _setState(ConversationControllerState next) {
    if (_disposed) {
      return;
    }

    _state = next;
    notifyListeners();
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('ConversationController has already been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    ++_listenerGeneration;
    ++_loadGeneration;

    final StreamSubscription<List<ConversationEntity>>? subscription =
        _subscription;

    _subscription = null;

    if (subscription != null) {
      unawaited(subscription.cancel());
    }

    _repository.releaseListener(requesterUid: currentUserUid);

    super.dispose();
  }
}

// ============================================================================
// END OF FILE: lib/features/message/controller/conversation_controller.dart
// ============================================================================
