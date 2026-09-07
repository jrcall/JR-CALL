// ============================================================================
// JR CALL
// File: message_controller.dart
// Location: lib/features/message/controller/message_controller.dart
// Description:
// UI-facing controller for one durable JR CALL conversation.
//
// Owns:
// - Loaded message timeline state.
// - Initial loading / refresh state.
// - Older-message pagination state.
// - Send/retry/edit/delete/reaction command coordination.
// - Delivery/read command coordination.
// - Repository listener binding.
// - Stable message-ID reconciliation.
// - Safe UI error state.
// - Subscription/disposal lifecycle.
//
// Does NOT:
// - Call Firestore directly.
// - Call Firebase Storage directly.
// - Own authentication credentials.
// - Invent sent/delivered/read state.
// - Render widgets.
// - Recreate Call Engine/WebRTC.
// ============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/message_entity.dart';
import '../data/message_status.dart';
import '../repository/message_repository.dart';
import 'message_composer_controller.dart';

/// High-level controller operation currently being performed.
enum MessageControllerOperation {
  idle,
  loading,
  paginating,
  sending,
  retrying,
  editing,
  deleting,
  reacting,
  markingDelivered,
  markingRead,
}

/// Immutable UI-facing state snapshot for one conversation.
@immutable
final class MessageControllerState {
  const MessageControllerState({
    required this.messages,
    required this.operation,
    required this.isInitialized,
    required this.isListening,
    required this.hasMore,
    required this.errorMessage,
  });

  const MessageControllerState.initial()
    : messages = const <MessageEntity>[],
      operation = MessageControllerOperation.idle,
      isInitialized = false,
      isListening = false,
      hasMore = true,
      errorMessage = null;

  final List<MessageEntity> messages;
  final MessageControllerOperation operation;
  final bool isInitialized;
  final bool isListening;
  final bool hasMore;
  final String? errorMessage;

  bool get isLoading =>
      operation == MessageControllerOperation.loading && messages.isEmpty;

  bool get isRefreshing =>
      operation == MessageControllerOperation.loading && messages.isNotEmpty;

  bool get isPaginating => operation == MessageControllerOperation.paginating;

  bool get isSending => operation == MessageControllerOperation.sending;

  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;

  bool get isBusy => operation != MessageControllerOperation.idle;

  MessageControllerState copyWith({
    List<MessageEntity>? messages,
    MessageControllerOperation? operation,
    bool? isInitialized,
    bool? isListening,
    bool? hasMore,
    String? errorMessage,
    bool clearError = false,
  }) {
    return MessageControllerState(
      messages: messages ?? this.messages,
      operation: operation ?? this.operation,
      isInitialized: isInitialized ?? this.isInitialized,
      isListening: isListening ?? this.isListening,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

/// Chat-screen state controller.
///
/// One controller instance represents one authenticated Firebase user's view
/// of one conversation.
///
/// Firebase UID remains the canonical internal identity.
///
/// This controller depends only on [MessageRepository] and never accesses
/// Firestore or Firebase Storage directly.
final class MessageController extends ChangeNotifier {
  MessageController({
    required this.repository,
    required String conversationId,
    required String currentUserUid,
    this.pageSize = 40,
  }) : conversationId = conversationId.trim(),
       currentUserUid = currentUserUid.trim() {
    if (this.conversationId.isEmpty) {
      throw ArgumentError.value(
        conversationId,
        'conversationId',
        'Conversation ID must not be empty.',
      );
    }

    if (this.currentUserUid.isEmpty) {
      throw ArgumentError.value(
        currentUserUid,
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

  /// Message-domain repository used by this controller.
  ///
  /// The constructor parameter name remains exactly `repository`.
  final MessageRepository repository;

  final String conversationId;
  final String currentUserUid;
  final int pageSize;

  MessageControllerState _state = const MessageControllerState.initial();

  StreamSubscription<List<MessageEntity>>? _messageSubscription;

  Object? _paginationCursor;

  int _listenerGeneration = 0;
  int _loadGeneration = 0;

  bool _disposed = false;
  bool _initializing = false;
  bool _paginating = false;
  bool _sending = false;
  bool _retrying = false;
  bool _editing = false;
  bool _deleting = false;
  bool _reacting = false;
  bool _markingDelivered = false;
  bool _markingRead = false;

  MessageControllerState get state => _state;

  List<MessageEntity> get messages => _state.messages;

  bool get isInitialized => _state.isInitialized;
  bool get isListening => _state.isListening;
  bool get isLoading => _state.isLoading;
  bool get isRefreshing => _state.isRefreshing;
  bool get isPaginating => _state.isPaginating;
  bool get isSending => _state.isSending;
  bool get hasMore => _state.hasMore;
  bool get hasError => _state.hasError;
  bool get isDisposed => _disposed;

  String? get errorMessage => _state.errorMessage;

  /// Loads the newest durable page and then binds the realtime timeline.
  ///
  /// A generation token prevents stale async load results from replacing a
  /// newer controller state.
  Future<void> initialize() async {
    _ensureNotDisposed();

    if (_initializing) {
      return;
    }

    _initializing = true;

    final int generation = ++_loadGeneration;

    _setState(
      _state.copyWith(
        operation: MessageControllerOperation.loading,
        clearError: true,
      ),
    );

    try {
      final MessageRepositoryPage page = await repository.load(
        conversationId: conversationId,
        requesterUid: currentUserUid,
        limit: pageSize,
      );

      if (!_isCurrentLoadGeneration(generation)) {
        return;
      }

      final List<MessageEntity> normalized = _normalizeTimeline(page.messages);

      _paginationCursor = page.cursor;

      _setState(
        _state.copyWith(
          messages: normalized,
          operation: MessageControllerOperation.idle,
          isInitialized: true,
          hasMore: page.hasMore,
          clearError: true,
        ),
      );

      await _bindMessageListener();
    } catch (_) {
      if (_isCurrentLoadGeneration(generation)) {
        _setState(
          _state.copyWith(
            operation: MessageControllerOperation.idle,
            isInitialized: true,
            errorMessage: 'Unable to load messages.',
          ),
        );
      }
    } finally {
      if (_isCurrentLoadGeneration(generation)) {
        _initializing = false;
      }
    }
  }

  /// Reloads the newest durable page without duplicating timeline messages.
  Future<void> refresh() async {
    _ensureNotDisposed();

    if (_initializing) {
      return;
    }

    _initializing = true;

    final int generation = ++_loadGeneration;

    _setState(
      _state.copyWith(
        operation: MessageControllerOperation.loading,
        clearError: true,
      ),
    );

    try {
      final MessageRepositoryPage page = await repository.load(
        conversationId: conversationId,
        requesterUid: currentUserUid,
        limit: pageSize,
      );

      if (!_isCurrentLoadGeneration(generation)) {
        return;
      }

      final List<MessageEntity> merged = _mergeById(
        local: _state.messages,
        remote: page.messages,
        preserveLocalPending: true,
      );

      _paginationCursor = page.cursor;

      _setState(
        _state.copyWith(
          messages: merged,
          operation: MessageControllerOperation.idle,
          isInitialized: true,
          hasMore: page.hasMore,
          clearError: true,
        ),
      );

      if (!_state.isListening) {
        await _bindMessageListener();
      }
    } catch (_) {
      if (_isCurrentLoadGeneration(generation)) {
        _setState(
          _state.copyWith(
            operation: MessageControllerOperation.idle,
            errorMessage: 'Unable to refresh messages.',
          ),
        );
      }
    } finally {
      if (_isCurrentLoadGeneration(generation)) {
        _initializing = false;
      }
    }
  }

  /// Loads one older durable page through the repository's opaque cursor.
  ///
  /// Lifetime conversation history is never loaded all at once.
  Future<void> loadOlder() async {
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
        operation: MessageControllerOperation.paginating,
        clearError: true,
      ),
    );

    try {
      final MessageRepositoryPage page = await repository.paginate(
        conversationId: conversationId,
        requesterUid: currentUserUid,
        cursor: cursor,
        limit: pageSize,
      );

      if (_disposed) {
        return;
      }

      final List<MessageEntity> merged = _mergeById(
        local: _state.messages,
        remote: page.messages,
        preserveLocalPending: true,
      );

      _paginationCursor = page.cursor;

      _setState(
        _state.copyWith(
          messages: merged,
          operation: MessageControllerOperation.idle,
          hasMore: page.hasMore,
          clearError: true,
        ),
      );
    } catch (_) {
      if (!_disposed) {
        _setState(
          _state.copyWith(
            operation: MessageControllerOperation.idle,
            errorMessage: 'Unable to load older messages.',
          ),
        );
      }
    } finally {
      _paginating = false;
    }
  }

  /// Sends one canonical composer request through [MessageRepository].
  ///
  /// MessageSender/Message Engine remains responsible for stable durable
  /// message identity, optimistic queued/sending state and durable persistence.
  Future<MessageEntity?> send(MessageComposerSendRequest request) async {
    _ensureNotDisposed();

    if (_sending) {
      return null;
    }

    _assertSendRequest(request);

    _sending = true;

    _setState(
      _state.copyWith(
        operation: MessageControllerOperation.sending,
        clearError: true,
      ),
    );

    try {
      final MessageEntity sent = await repository.send(request);

      if (_disposed) {
        return sent;
      }

      _assertMessageBelongsToConversation(sent);
      _replaceMessage(sent);

      _setState(
        _state.copyWith(
          operation: MessageControllerOperation.idle,
          clearError: true,
        ),
      );

      return sent;
    } catch (_) {
      if (!_disposed) {
        _setState(
          _state.copyWith(
            operation: MessageControllerOperation.idle,
            errorMessage: 'Unable to send message.',
          ),
        );
      }

      return null;
    } finally {
      _sending = false;
    }
  }

  /// Retries one failed durable message using the SAME canonical message ID.
  Future<MessageEntity?> retry(String messageId) async {
    _ensureNotDisposed();

    if (_retrying) {
      return null;
    }

    final MessageEntity? existing = findMessage(messageId);

    if (existing == null) {
      _setError('Message is no longer available.');
      return null;
    }

    if (existing.senderUid != currentUserUid) {
      _setError('You can only retry your own message.');
      return null;
    }

    if (existing.status != MessageStatus.failed) {
      return existing;
    }

    _retrying = true;

    _setState(
      _state.copyWith(
        operation: MessageControllerOperation.retrying,
        clearError: true,
      ),
    );

    try {
      final MessageEntity retried = await repository.retry(
        conversationId: conversationId,
        messageId: existing.id,
        requesterUid: currentUserUid,
      );

      if (_disposed) {
        return retried;
      }

      _assertMessageBelongsToConversation(retried);
      _replaceMessage(retried);

      _setState(
        _state.copyWith(
          operation: MessageControllerOperation.idle,
          clearError: true,
        ),
      );

      return retried;
    } catch (_) {
      if (!_disposed) {
        _setState(
          _state.copyWith(
            operation: MessageControllerOperation.idle,
            errorMessage: 'Unable to retry message.',
          ),
        );
      }

      return null;
    } finally {
      _retrying = false;
    }
  }

  /// Edits one sender-owned durable text message while preserving its ID.
  Future<MessageEntity?> edit({
    required String messageId,
    required String text,
  }) async {
    _ensureNotDisposed();

    if (_editing) {
      return null;
    }

    final MessageEntity? existing = findMessage(messageId);

    if (existing == null) {
      _setError('Message is no longer available.');
      return null;
    }

    if (existing.senderUid != currentUserUid) {
      _setError('You can only edit your own message.');
      return null;
    }

    if (existing.deletedAt != null) {
      _setError('Deleted messages cannot be edited.');
      return null;
    }

    final String normalizedText = _normalizeText(text);

    if (normalizedText.isEmpty) {
      _setError('Edited message text must not be empty.');
      return null;
    }

    _editing = true;

    _setState(
      _state.copyWith(
        operation: MessageControllerOperation.editing,
        clearError: true,
      ),
    );

    try {
      final MessageEntity edited = await repository.edit(
        conversationId: conversationId,
        messageId: existing.id,
        requesterUid: currentUserUid,
        text: normalizedText,
      );

      if (_disposed) {
        return edited;
      }

      _assertMessageBelongsToConversation(edited);
      _replaceMessage(edited);

      _setState(
        _state.copyWith(
          operation: MessageControllerOperation.idle,
          clearError: true,
        ),
      );

      return edited;
    } catch (_) {
      if (!_disposed) {
        _setState(
          _state.copyWith(
            operation: MessageControllerOperation.idle,
            errorMessage: 'Unable to edit message.',
          ),
        );
      }

      return null;
    } finally {
      _editing = false;
    }
  }

  /// Applies sender-authorized durable delete/tombstone policy.
  Future<MessageEntity?> delete(String messageId) async {
    _ensureNotDisposed();

    if (_deleting) {
      return null;
    }

    final MessageEntity? existing = findMessage(messageId);

    if (existing == null) {
      _setError('Message is no longer available.');
      return null;
    }

    if (existing.senderUid != currentUserUid) {
      _setError('You can only delete your own message.');
      return null;
    }

    _deleting = true;

    _setState(
      _state.copyWith(
        operation: MessageControllerOperation.deleting,
        clearError: true,
      ),
    );

    try {
      final MessageEntity deleted = await repository.delete(
        conversationId: conversationId,
        messageId: existing.id,
        requesterUid: currentUserUid,
      );

      if (_disposed) {
        return deleted;
      }

      _assertMessageBelongsToConversation(deleted);
      _replaceMessage(deleted);

      _setState(
        _state.copyWith(
          operation: MessageControllerOperation.idle,
          clearError: true,
        ),
      );

      return deleted;
    } catch (_) {
      if (!_disposed) {
        _setState(
          _state.copyWith(
            operation: MessageControllerOperation.idle,
            errorMessage: 'Unable to delete message.',
          ),
        );
      }

      return null;
    } finally {
      _deleting = false;
    }
  }

  /// Creates or changes the authenticated user's own reaction.
  Future<void> react({
    required String messageId,
    required String reaction,
  }) async {
    _ensureNotDisposed();

    if (_reacting) {
      return;
    }

    final MessageEntity? existing = findMessage(messageId);

    if (existing == null) {
      _setError('Message is no longer available.');
      return;
    }

    final String normalizedReaction = reaction.trim();

    if (normalizedReaction.isEmpty) {
      await removeReaction(existing.id);
      return;
    }

    _reacting = true;

    _setState(
      _state.copyWith(
        operation: MessageControllerOperation.reacting,
        clearError: true,
      ),
    );

    try {
      await repository.react(
        conversationId: conversationId,
        messageId: existing.id,
        userUid: currentUserUid,
        reaction: normalizedReaction,
      );

      if (!_disposed) {
        _setState(
          _state.copyWith(
            operation: MessageControllerOperation.idle,
            clearError: true,
          ),
        );
      }
    } catch (_) {
      if (!_disposed) {
        _setState(
          _state.copyWith(
            operation: MessageControllerOperation.idle,
            errorMessage: 'Unable to update reaction.',
          ),
        );
      }
    } finally {
      _reacting = false;
    }
  }

  /// Removes the authenticated user's own reaction.
  Future<void> removeReaction(String messageId) async {
    _ensureNotDisposed();

    if (_reacting) {
      return;
    }

    final MessageEntity? existing = findMessage(messageId);

    if (existing == null) {
      _setError('Message is no longer available.');
      return;
    }

    _reacting = true;

    _setState(
      _state.copyWith(
        operation: MessageControllerOperation.reacting,
        clearError: true,
      ),
    );

    try {
      await repository.react(
        conversationId: conversationId,
        messageId: existing.id,
        userUid: currentUserUid,
        reaction: null,
      );

      if (!_disposed) {
        _setState(
          _state.copyWith(
            operation: MessageControllerOperation.idle,
            clearError: true,
          ),
        );
      }
    } catch (_) {
      if (!_disposed) {
        _setState(
          _state.copyWith(
            operation: MessageControllerOperation.idle,
            errorMessage: 'Unable to remove reaction.',
          ),
        );
      }
    } finally {
      _reacting = false;
    }
  }

  /// Acknowledges real recipient delivery.
  ///
  /// Delivery is never inferred from elapsed time.
  Future<void> markDelivered(Iterable<String> messageIds) async {
    _ensureNotDisposed();

    if (_markingDelivered) {
      return;
    }

    final List<String> eligible = _eligibleMessagesForDelivery(messageIds);

    if (eligible.isEmpty) {
      return;
    }

    _markingDelivered = true;

    try {
      await repository.markDelivered(
        conversationId: conversationId,
        messageIds: eligible,
        recipientUid: currentUserUid,
      );
    } catch (_) {
      if (!_disposed) {
        _setError('Unable to acknowledge message delivery.');
      }
    } finally {
      _markingDelivered = false;
    }
  }

  /// Marks only messages explicitly determined visible/read by presentation.
  ///
  /// Realtime listener arrival alone never causes a read acknowledgement.
  Future<void> markRead(Iterable<String> messageIds) async {
    _ensureNotDisposed();

    if (_markingRead) {
      return;
    }

    final List<String> eligible = _eligibleMessagesForRead(messageIds);

    if (eligible.isEmpty) {
      return;
    }

    _markingRead = true;

    try {
      await repository.markRead(
        conversationId: conversationId,
        messageIds: eligible,
        readerUid: currentUserUid,
      );
    } catch (_) {
      if (!_disposed) {
        _setError('Unable to update read state.');
      }
    } finally {
      _markingRead = false;
    }
  }

  /// Returns one currently loaded canonical message.
  MessageEntity? findMessage(String messageId) {
    final String normalized = messageId.trim();

    if (normalized.isEmpty) {
      return null;
    }

    for (final MessageEntity message in _state.messages) {
      if (message.id == normalized) {
        return message;
      }
    }

    return null;
  }

  /// Clears current safe UI error state.
  void clearError() {
    _ensureNotDisposed();

    if (!_state.hasError) {
      return;
    }

    _setState(_state.copyWith(clearError: true));
  }

  /// Restarts the realtime timeline without discarding already loaded items.
  Future<void> restartListener() async {
    _ensureNotDisposed();
    await _bindMessageListener(forceRestart: true);
  }

  Future<void> _bindMessageListener({bool forceRestart = false}) async {
    _ensureNotDisposed();

    if (!forceRestart && _messageSubscription != null) {
      return;
    }

    final int generation = ++_listenerGeneration;

    final StreamSubscription<List<MessageEntity>>? previous =
        _messageSubscription;

    _messageSubscription = null;

    if (previous != null) {
      await previous.cancel();
    }

    repository.releaseTimeline(
      conversationId: conversationId,
      requesterUid: currentUserUid,
    );

    if (_disposed || generation != _listenerGeneration) {
      return;
    }

    final Stream<List<MessageEntity>> stream = repository.listen(
      conversationId: conversationId,
      requesterUid: currentUserUid,
    );

    _messageSubscription = stream.listen(
      (List<MessageEntity> incoming) {
        if (_disposed || generation != _listenerGeneration) {
          return;
        }

        final List<MessageEntity> merged = _mergeById(
          local: _state.messages,
          remote: incoming,
          preserveLocalPending: true,
        );

        _setState(
          _state.copyWith(
            messages: merged,
            isListening: true,
            clearError: true,
          ),
        );
      },
      onError: (Object _, StackTrace _) {
        if (_disposed || generation != _listenerGeneration) {
          return;
        }

        _setState(
          _state.copyWith(
            isListening: false,
            errorMessage: 'Message synchronization was interrupted.',
          ),
        );
      },
      onDone: () {
        if (_disposed || generation != _listenerGeneration) {
          return;
        }

        _messageSubscription = null;

        _setState(_state.copyWith(isListening: false));
      },
      cancelOnError: false,
    );

    if (!_disposed && generation == _listenerGeneration) {
      _setState(_state.copyWith(isListening: true));
    }
  }

  void _replaceMessage(MessageEntity message) {
    if (_disposed) {
      return;
    }

    final Map<String, MessageEntity> byId = <String, MessageEntity>{
      for (final MessageEntity current in _state.messages) current.id: current,
    };

    final MessageEntity? existing = byId[message.id];

    byId[message.id] = existing == null
        ? message
        : _preferCanonicalVersion(existing, message);

    _setState(_state.copyWith(messages: _normalizeTimeline(byId.values)));
  }

  List<MessageEntity> _mergeById({
    required Iterable<MessageEntity> local,
    required Iterable<MessageEntity> remote,
    required bool preserveLocalPending,
  }) {
    final Map<String, MessageEntity> merged = <String, MessageEntity>{};

    for (final MessageEntity message in local) {
      if (message.conversationId != conversationId ||
          message.id.trim().isEmpty) {
        continue;
      }

      merged[message.id] = message;
    }

    for (final MessageEntity incoming in remote) {
      if (incoming.conversationId != conversationId ||
          incoming.id.trim().isEmpty) {
        continue;
      }

      final MessageEntity? existing = merged[incoming.id];

      merged[incoming.id] = existing == null
          ? incoming
          : _preferCanonicalVersion(existing, incoming);
    }

    if (!preserveLocalPending) {
      merged.removeWhere(
        (String _, MessageEntity message) =>
            message.localOnly &&
            (message.status == MessageStatus.queued ||
                message.status == MessageStatus.sending),
      );
    }

    return _normalizeTimeline(merged.values);
  }

  MessageEntity _preferCanonicalVersion(
    MessageEntity current,
    MessageEntity candidate,
  ) {
    if (candidate.status.rank > current.status.rank) {
      return candidate;
    }

    if (candidate.status.rank < current.status.rank) {
      return current;
    }

    if (current.localOnly && !candidate.localOnly) {
      return candidate;
    }

    if (!current.localOnly && candidate.localOnly) {
      return current;
    }

    final DateTime currentMutationAt =
        current.deletedAt ??
        current.editedAt ??
        current.serverCreatedAt ??
        current.clientCreatedAt;

    final DateTime candidateMutationAt =
        candidate.deletedAt ??
        candidate.editedAt ??
        candidate.serverCreatedAt ??
        candidate.clientCreatedAt;

    if (candidateMutationAt.isAfter(currentMutationAt)) {
      return candidate;
    }

    if (currentMutationAt.isAfter(candidateMutationAt)) {
      return current;
    }

    if (candidate.serverCreatedAt != null && current.serverCreatedAt == null) {
      return candidate;
    }

    if (current.serverCreatedAt != null && candidate.serverCreatedAt == null) {
      return current;
    }

    return candidate;
  }

  List<MessageEntity> _normalizeTimeline(Iterable<MessageEntity> source) {
    final Map<String, MessageEntity> unique = <String, MessageEntity>{};

    for (final MessageEntity message in source) {
      final String id = message.id.trim();

      if (id.isEmpty || message.conversationId != conversationId) {
        continue;
      }

      final MessageEntity? previous = unique[id];

      unique[id] = previous == null
          ? message
          : _preferCanonicalVersion(previous, message);
    }

    final List<MessageEntity> result = unique.values.toList(growable: false);

    result.sort(_compareTimelineMessages);

    return List<MessageEntity>.unmodifiable(result);
  }

  int _compareTimelineMessages(MessageEntity left, MessageEntity right) {
    final DateTime leftTime = left.serverCreatedAt ?? left.clientCreatedAt;

    final DateTime rightTime = right.serverCreatedAt ?? right.clientCreatedAt;

    final int timeComparison = leftTime.compareTo(rightTime);

    if (timeComparison != 0) {
      return timeComparison;
    }

    final int clientComparison = left.clientCreatedAt.compareTo(
      right.clientCreatedAt,
    );

    if (clientComparison != 0) {
      return clientComparison;
    }

    return left.id.compareTo(right.id);
  }

  List<String> _eligibleMessagesForDelivery(Iterable<String> messageIds) {
    final Set<String> seen = <String>{};
    final List<String> eligible = <String>[];

    for (final String rawId in messageIds) {
      final String id = rawId.trim();

      if (id.isEmpty || !seen.add(id)) {
        continue;
      }

      final MessageEntity? message = findMessage(id);

      if (message == null ||
          message.senderUid == currentUserUid ||
          message.deletedAt != null) {
        continue;
      }

      if (message.status == MessageStatus.sent) {
        eligible.add(id);
      }
    }

    return List<String>.unmodifiable(eligible);
  }

  List<String> _eligibleMessagesForRead(Iterable<String> messageIds) {
    final Set<String> seen = <String>{};
    final List<String> eligible = <String>[];

    for (final String rawId in messageIds) {
      final String id = rawId.trim();

      if (id.isEmpty || !seen.add(id)) {
        continue;
      }

      final MessageEntity? message = findMessage(id);

      if (message == null ||
          message.senderUid == currentUserUid ||
          message.deletedAt != null ||
          message.status == MessageStatus.read) {
        continue;
      }

      eligible.add(id);
    }

    return List<String>.unmodifiable(eligible);
  }

  void _assertSendRequest(MessageComposerSendRequest request) {
    if (request.conversationId != conversationId) {
      throw StateError(
        'Composer request does not belong to the active conversation.',
      );
    }

    if (request.senderUid != currentUserUid) {
      throw StateError(
        'Composer request sender must match the authenticated Firebase UID.',
      );
    }

    if (!request.hasContent) {
      throw StateError('Composer request must contain text or an attachment.');
    }
  }

  void _assertMessageBelongsToConversation(MessageEntity message) {
    if (message.id.trim().isEmpty) {
      throw StateError('Message ID must not be empty.');
    }

    if (message.conversationId != conversationId) {
      throw StateError('Message does not belong to the active conversation.');
    }
  }

  String _normalizeText(String value) {
    return value.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  }

  bool _isCurrentLoadGeneration(int generation) {
    return !_disposed && generation == _loadGeneration;
  }

  void _setError(String message) {
    if (_disposed) {
      return;
    }

    _setState(_state.copyWith(errorMessage: message));
  }

  void _setState(MessageControllerState next) {
    if (_disposed) {
      return;
    }

    _state = next;
    notifyListeners();
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('MessageController has already been disposed.');
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

    final StreamSubscription<List<MessageEntity>>? subscription =
        _messageSubscription;

    _messageSubscription = null;

    if (subscription != null) {
      unawaited(subscription.cancel());
    }

    repository.releaseTimeline(
      conversationId: conversationId,
      requesterUid: currentUserUid,
    );

    super.dispose();
  }
}

// ============================================================================
// END OF FILE: lib/features/message/controller/message_controller.dart
// ============================================================================
