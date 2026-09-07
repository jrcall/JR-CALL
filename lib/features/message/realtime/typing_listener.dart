// ============================================================================
// JR CALL
// File: typing_listener.dart
// Location: lib/features/message/realtime/typing_listener.dart
// Description:
// Realtime typing + ephemeral JR CALL Live Chat listener.
//
// Owns:
// - One active typing-state subscription.
// - One active Live Chat-state subscription.
// - Peer-only state filtering.
// - Typing expiry / stale-state protection.
// - Live Chat session/version deduplication.
// - Live Chat expiry / stale-state protection.
// - Stale subscription generation protection.
// - Immutable normalized peer-state emission.
// - Safe cancellation / restart / disposal.
//
// Does NOT own:
// - Firestore collection paths.
// - Firestore writes.
// - Typing/live write throttling.
// - Particle/butterfly animation.
// - Durable message history.
// - Presence architecture.
// - Call Engine / WebRTC.
//
// Firestore query/path ownership remains in message_remote_store.dart.
// Presentation animation belongs to typing_indicator.dart.
// ============================================================================

import 'dart:async';

/// Immutable realtime typing-state record supplied to [TypingListener].
///
/// Storage/repository layers may construct this model from the canonical
/// `conversations/{conversationId}/typing/{uid}` document.
///
/// [expiresAt] is mandatory because typing state must never remain active
/// indefinitely when a client disappears without explicitly clearing it.
final class TypingState {
  TypingState({
    required String conversationId,
    required String userUid,
    required this.isTyping,
    required DateTime updatedAt,
    required DateTime expiresAt,
  }) : conversationId = _normalizeRequired(conversationId, 'conversationId'),
       userUid = _normalizeRequired(userUid, 'userUid'),
       updatedAt = updatedAt.toUtc(),
       expiresAt = expiresAt.toUtc();

  final String conversationId;
  final String userUid;
  final bool isTyping;
  final DateTime updatedAt;
  final DateTime expiresAt;

  bool get isExpired => isExpiredAt(DateTime.now().toUtc());

  bool isExpiredAt(DateTime now) {
    return !expiresAt.isAfter(now.toUtc());
  }

  TypingState copyWith({
    String? conversationId,
    String? userUid,
    bool? isTyping,
    DateTime? updatedAt,
    DateTime? expiresAt,
  }) {
    return TypingState(
      conversationId: conversationId ?? this.conversationId,
      userUid: userUid ?? this.userUid,
      isTyping: isTyping ?? this.isTyping,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'conversationId': conversationId,
      'userUid': userUid,
      'isTyping': isTyping,
      'updatedAt': updatedAt,
      'expiresAt': expiresAt,
    };
  }

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
}

/// Immutable ephemeral JR CALL Live Chat state.
///
/// Live Chat is not a durable message. It must never automatically become
/// normal message history.
///
/// A unique [sessionId] identifies one live-composer session while [version]
/// increases as newer throttled drafts are published.
///
/// [styleSeed] is presentation metadata used later by the efficient
/// particle/butterfly visual component.
final class LiveChatState {
  LiveChatState({
    required String conversationId,
    required String senderUid,
    required String sessionId,
    required int version,
    required this.text,
    required this.styleSeed,
    required DateTime updatedAt,
    required DateTime expiresAt,
    required this.isActive,
  }) : conversationId = _normalizeRequired(conversationId, 'conversationId'),
       senderUid = _normalizeRequired(senderUid, 'senderUid'),
       sessionId = _normalizeRequired(sessionId, 'sessionId'),
       version = _validateVersion(version),
       updatedAt = updatedAt.toUtc(),
       expiresAt = expiresAt.toUtc();

  final String conversationId;
  final String senderUid;
  final String sessionId;
  final int version;
  final String text;
  final int styleSeed;
  final DateTime updatedAt;
  final DateTime expiresAt;
  final bool isActive;

  bool get isExpired => isExpiredAt(DateTime.now().toUtc());

  bool get hasVisibleText => isActive && text.trim().isNotEmpty;

  bool isExpiredAt(DateTime now) {
    return !expiresAt.isAfter(now.toUtc());
  }

  LiveChatState copyWith({
    String? conversationId,
    String? senderUid,
    String? sessionId,
    int? version,
    String? text,
    int? styleSeed,
    DateTime? updatedAt,
    DateTime? expiresAt,
    bool? isActive,
  }) {
    return LiveChatState(
      conversationId: conversationId ?? this.conversationId,
      senderUid: senderUid ?? this.senderUid,
      sessionId: sessionId ?? this.sessionId,
      version: version ?? this.version,
      text: text ?? this.text,
      styleSeed: styleSeed ?? this.styleSeed,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'conversationId': conversationId,
      'senderUid': senderUid,
      'sessionId': sessionId,
      'version': version,
      'text': text,
      'styleSeed': styleSeed,
      'updatedAt': updatedAt,
      'expiresAt': expiresAt,
      'isActive': isActive,
    };
  }

  static int _validateVersion(int value) {
    if (value < 0) {
      throw ArgumentError.value(
        value,
        'version',
        'Live Chat version must not be negative.',
      );
    }

    return value;
  }

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
}

/// Immutable peer typing + Live Chat state exposed to higher layers.
final class TypingListenerSnapshot {
  const TypingListenerSnapshot({
    required this.conversationId,
    required this.currentUid,
    required this.peerTyping,
    required this.peerLiveChat,
    required this.generation,
  });

  final String conversationId;
  final String currentUid;

  /// Peer typing state only.
  ///
  /// Own typing state is never exposed here.
  final TypingState? peerTyping;

  /// Peer Live Chat state only.
  ///
  /// Own live draft is never exposed here.
  final LiveChatState? peerLiveChat;

  /// Listener generation that produced this snapshot.
  final int generation;

  bool get isPeerTyping => peerTyping?.isTyping ?? false;

  bool get hasPeerLiveChat => peerLiveChat != null;
}

/// Realtime typing + ephemeral Live Chat observer.
///
/// The supplied streams must belong to exactly one conversation.
///
/// This class never creates Firestore listeners directly. The storage or
/// repository layer supplies typed streams.
///
/// State acceptance rules:
/// - own UID state is ignored,
/// - wrong-conversation state is rejected,
/// - expired typing/live state is cleared,
/// - stale timestamp updates are ignored,
/// - older Live Chat sessions/versions cannot replace newer accepted state,
/// - duplicate state does not emit duplicate snapshots,
/// - stale callbacks from replaced subscriptions are rejected.
final class TypingListener {
  TypingListener({Duration expiryCheckInterval = const Duration(seconds: 1)})
    : _expiryCheckInterval = _validateExpiryInterval(expiryCheckInterval);

  final Duration _expiryCheckInterval;

  final StreamController<TypingListenerSnapshot> _snapshotController =
      StreamController<TypingListenerSnapshot>.broadcast(sync: true);

  final StreamController<TypingState?> _typingController =
      StreamController<TypingState?>.broadcast(sync: true);

  final StreamController<LiveChatState?> _liveChatController =
      StreamController<LiveChatState?>.broadcast(sync: true);

  final StreamController<Object> _errorController =
      StreamController<Object>.broadcast(sync: true);

  StreamSubscription<List<TypingState>>? _typingSubscription;
  StreamSubscription<List<LiveChatState>>? _liveSubscription;

  Timer? _expiryTimer;

  String? _conversationId;
  String? _currentUid;

  TypingState? _peerTyping;
  LiveChatState? _peerLiveChat;

  int _generation = 0;

  bool _isListening = false;
  bool _isPaused = false;
  bool _isDisposed = false;

  // --------------------------------------------------------------------------
  // PUBLIC STATE
  // --------------------------------------------------------------------------

  String? get conversationId => _conversationId;

  String? get currentUid => _currentUid;

  int get generation => _generation;

  bool get isListening => _isListening;

  bool get isPaused => _isPaused;

  bool get isDisposed => _isDisposed;

  TypingState? get peerTyping => _peerTyping;

  LiveChatState? get peerLiveChat => _peerLiveChat;

  bool get isPeerTyping => _peerTyping?.isTyping ?? false;

  bool get hasPeerLiveChat => _peerLiveChat != null;

  Stream<TypingListenerSnapshot> get snapshots => _snapshotController.stream;

  Stream<TypingState?> get typingStates => _typingController.stream;

  Stream<LiveChatState?> get liveChatStates => _liveChatController.stream;

  Stream<Object> get errors => _errorController.stream;

  // --------------------------------------------------------------------------
  // LISTENER LIFECYCLE
  // --------------------------------------------------------------------------

  /// Starts realtime observation for one authenticated conversation context.
  ///
  /// [currentUid] must be the canonical Firebase Auth UID.
  ///
  /// [typingStream] supplies typing documents for this conversation.
  ///
  /// [liveChatStream] supplies ephemeral Live Chat documents for this
  /// conversation.
  Future<void> startListening({
    required String conversationId,
    required String currentUid,
    required Stream<List<TypingState>> typingStream,
    required Stream<List<LiveChatState>> liveChatStream,
  }) async {
    _ensureNotDisposed();

    final String normalizedConversationId = _normalizeId(
      conversationId,
      fieldName: 'conversationId',
    );

    final String normalizedCurrentUid = _normalizeId(
      currentUid,
      fieldName: 'currentUid',
    );

    // Invalidate previous callbacks BEFORE cancellation/replacement.
    final int listenerGeneration = ++_generation;

    final StreamSubscription<List<TypingState>>? oldTyping =
        _typingSubscription;

    final StreamSubscription<List<LiveChatState>>? oldLive = _liveSubscription;

    _typingSubscription = null;
    _liveSubscription = null;

    _expiryTimer?.cancel();
    _expiryTimer = null;

    _isListening = false;
    _isPaused = false;

    if (oldTyping != null) {
      await oldTyping.cancel();
    }

    if (oldLive != null) {
      await oldLive.cancel();
    }

    _conversationId = normalizedConversationId;
    _currentUid = normalizedCurrentUid;
    _peerTyping = null;
    _peerLiveChat = null;

    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    late final StreamSubscription<List<TypingState>> typingSubscription;
    late final StreamSubscription<List<LiveChatState>> liveSubscription;

    typingSubscription = typingStream.listen(
      (List<TypingState> states) {
        _handleTypingSnapshot(
          states,
          conversationId: normalizedConversationId,
          currentUid: normalizedCurrentUid,
          listenerGeneration: listenerGeneration,
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        _handleStreamError(
          error,
          stackTrace: stackTrace,
          source: TypingListenerErrorSource.typing,
          listenerGeneration: listenerGeneration,
        );
      },
      onDone: () {
        _handleTypingDone(
          typingSubscription,
          listenerGeneration: listenerGeneration,
        );
      },
      cancelOnError: false,
    );

    liveSubscription = liveChatStream.listen(
      (List<LiveChatState> states) {
        _handleLiveSnapshot(
          states,
          conversationId: normalizedConversationId,
          currentUid: normalizedCurrentUid,
          listenerGeneration: listenerGeneration,
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        _handleStreamError(
          error,
          stackTrace: stackTrace,
          source: TypingListenerErrorSource.liveChat,
          listenerGeneration: listenerGeneration,
        );
      },
      onDone: () {
        _handleLiveDone(
          liveSubscription,
          listenerGeneration: listenerGeneration,
        );
      },
      cancelOnError: false,
    );

    if (!_isCurrentGeneration(listenerGeneration)) {
      await typingSubscription.cancel();
      await liveSubscription.cancel();
      return;
    }

    _typingSubscription = typingSubscription;
    _liveSubscription = liveSubscription;
    _isListening = true;

    _startExpiryTimer(listenerGeneration);
  }

  Future<void> restartListening({
    required String conversationId,
    required String currentUid,
    required Stream<List<TypingState>> typingStream,
    required Stream<List<LiveChatState>> liveChatStream,
  }) {
    return startListening(
      conversationId: conversationId,
      currentUid: currentUid,
      typingStream: typingStream,
      liveChatStream: liveChatStream,
    );
  }

  /// Stops observation and clears all accepted peer ephemeral state.
  Future<void> stopListening() async {
    if (_isDisposed) {
      return;
    }

    ++_generation;

    final StreamSubscription<List<TypingState>>? typingSubscription =
        _typingSubscription;

    final StreamSubscription<List<LiveChatState>>? liveSubscription =
        _liveSubscription;

    _typingSubscription = null;
    _liveSubscription = null;

    _expiryTimer?.cancel();
    _expiryTimer = null;

    _isListening = false;
    _isPaused = false;

    _conversationId = null;
    _currentUid = null;

    _peerTyping = null;
    _peerLiveChat = null;

    if (typingSubscription != null) {
      await typingSubscription.cancel();
    }

    if (liveSubscription != null) {
      await liveSubscription.cancel();
    }
  }

  /// Pauses both active realtime subscriptions and local expiry checking.
  void pauseListening() {
    _ensureNotDisposed();

    if (!_isListening || _isPaused) {
      return;
    }

    _typingSubscription?.pause();
    _liveSubscription?.pause();

    _expiryTimer?.cancel();
    _expiryTimer = null;

    _isPaused = true;
  }

  /// Resumes both realtime subscriptions and expiry checking.
  void resumeListening() {
    _ensureNotDisposed();

    if (!_isListening || !_isPaused) {
      return;
    }

    _typingSubscription?.resume();
    _liveSubscription?.resume();

    _isPaused = false;

    _startExpiryTimer(_generation);
    _expireStaleState(_generation);
  }

  /// Clears locally accepted peer ephemeral state without cancelling streams.
  ///
  /// Remote state is not written/deleted by this listener.
  void clearSnapshot() {
    _ensureNotDisposed();

    final bool typingChanged = _peerTyping != null;
    final bool liveChanged = _peerLiveChat != null;

    _peerTyping = null;
    _peerLiveChat = null;

    if (typingChanged) {
      _typingController.add(null);
    }

    if (liveChanged) {
      _liveChatController.add(null);
    }

    if (typingChanged || liveChanged) {
      _emitSnapshot(_generation);
    }
  }

  // --------------------------------------------------------------------------
  // TYPING PROCESSING
  // --------------------------------------------------------------------------

  void _handleTypingSnapshot(
    List<TypingState> incoming, {
    required String conversationId,
    required String currentUid,
    required int listenerGeneration,
  }) {
    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    final DateTime now = DateTime.now().toUtc();

    TypingState? selected;

    for (final TypingState state in incoming) {
      if (state.conversationId != conversationId) {
        _emitSafeError(
          TypingListenerException(
            code: TypingListenerErrorCode.invalidConversation,
            source: TypingListenerErrorSource.typing,
            message: 'Typing state belongs to a different conversation.',
            conversationId: conversationId,
            userUid: state.userUid,
          ),
          listenerGeneration: listenerGeneration,
        );
        continue;
      }

      // Never expose our own typing state as peer typing.
      if (state.userUid == currentUid) {
        continue;
      }

      if (!state.isTyping || state.isExpiredAt(now)) {
        continue;
      }

      final TypingState? existing = selected;

      if (existing == null ||
          state.updatedAt.isAfter(existing.updatedAt) ||
          (state.updatedAt == existing.updatedAt &&
              state.userUid.compareTo(existing.userUid) < 0)) {
        selected = state;
      }
    }

    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    final TypingState? previous = _peerTyping;

    if (_typingEquivalent(previous, selected)) {
      return;
    }

    // Reject a stale update that would replace a newer accepted state from
    // the same peer.
    if (previous != null &&
        selected != null &&
        previous.userUid == selected.userUid &&
        selected.updatedAt.isBefore(previous.updatedAt)) {
      return;
    }

    _peerTyping = selected;

    _typingController.add(selected);
    _emitSnapshot(listenerGeneration);
  }

  // --------------------------------------------------------------------------
  // LIVE CHAT PROCESSING
  // --------------------------------------------------------------------------

  void _handleLiveSnapshot(
    List<LiveChatState> incoming, {
    required String conversationId,
    required String currentUid,
    required int listenerGeneration,
  }) {
    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    final DateTime now = DateTime.now().toUtc();

    LiveChatState? selected;

    for (final LiveChatState state in incoming) {
      if (state.conversationId != conversationId) {
        _emitSafeError(
          TypingListenerException(
            code: TypingListenerErrorCode.invalidConversation,
            source: TypingListenerErrorSource.liveChat,
            message: 'Live Chat state belongs to a different conversation.',
            conversationId: conversationId,
            userUid: state.senderUid,
          ),
          listenerGeneration: listenerGeneration,
        );
        continue;
      }

      // Own draft must never be rendered as peer Live Chat.
      if (state.senderUid == currentUid) {
        continue;
      }

      if (!state.isActive ||
          state.text.trim().isEmpty ||
          state.isExpiredAt(now)) {
        continue;
      }

      final LiveChatState? existing = selected;

      if (existing == null || _compareLiveVersions(state, existing) > 0) {
        selected = state;
      }
    }

    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    final LiveChatState? previous = _peerLiveChat;

    if (_liveEquivalent(previous, selected)) {
      return;
    }

    if (previous != null && selected != null) {
      final int comparison = _compareLiveVersions(selected, previous);

      if (comparison < 0) {
        return;
      }

      if (comparison == 0 && selected.updatedAt.isBefore(previous.updatedAt)) {
        return;
      }
    }

    _peerLiveChat = selected;

    _liveChatController.add(selected);
    _emitSnapshot(listenerGeneration);
  }

  /// Determines which Live Chat update is newer.
  ///
  /// Ordering:
  /// 1. same session -> greater version
  /// 2. same version -> greater updatedAt
  /// 3. different session -> greater updatedAt
  /// 4. deterministic session-ID tie-break
  static int _compareLiveVersions(LiveChatState first, LiveChatState second) {
    if (first.sessionId == second.sessionId) {
      final int versionComparison = first.version.compareTo(second.version);

      if (versionComparison != 0) {
        return versionComparison;
      }

      final int updatedComparison = first.updatedAt.compareTo(second.updatedAt);

      if (updatedComparison != 0) {
        return updatedComparison;
      }

      return first.sessionId.compareTo(second.sessionId);
    }

    final int updatedComparison = first.updatedAt.compareTo(second.updatedAt);

    if (updatedComparison != 0) {
      return updatedComparison;
    }

    return first.sessionId.compareTo(second.sessionId);
  }

  // --------------------------------------------------------------------------
  // EXPIRY
  // --------------------------------------------------------------------------

  void _startExpiryTimer(int listenerGeneration) {
    _expiryTimer?.cancel();

    if (!_isCurrentGeneration(listenerGeneration) ||
        !_isListening ||
        _isPaused) {
      return;
    }

    _expiryTimer = Timer.periodic(_expiryCheckInterval, (_) {
      _expireStaleState(listenerGeneration);
    });
  }

  void _expireStaleState(int listenerGeneration) {
    if (!_isCurrentGeneration(listenerGeneration) || _isPaused) {
      return;
    }

    final DateTime now = DateTime.now().toUtc();

    bool changed = false;

    final TypingState? typing = _peerTyping;

    if (typing != null && (!typing.isTyping || typing.isExpiredAt(now))) {
      _peerTyping = null;
      _typingController.add(null);
      changed = true;
    }

    final LiveChatState? live = _peerLiveChat;

    if (live != null &&
        (!live.isActive || live.text.trim().isEmpty || live.isExpiredAt(now))) {
      _peerLiveChat = null;
      _liveChatController.add(null);
      changed = true;
    }

    if (changed) {
      _emitSnapshot(listenerGeneration);
    }
  }

  // --------------------------------------------------------------------------
  // STREAM COMPLETION / ERROR
  // --------------------------------------------------------------------------

  void _handleTypingDone(
    StreamSubscription<List<TypingState>> subscription, {
    required int listenerGeneration,
  }) {
    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    if (!identical(_typingSubscription, subscription)) {
      return;
    }

    _typingSubscription = null;

    _refreshListeningState(listenerGeneration);
  }

  void _handleLiveDone(
    StreamSubscription<List<LiveChatState>> subscription, {
    required int listenerGeneration,
  }) {
    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    if (!identical(_liveSubscription, subscription)) {
      return;
    }

    _liveSubscription = null;

    _refreshListeningState(listenerGeneration);
  }

  void _refreshListeningState(int listenerGeneration) {
    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    _isListening = _typingSubscription != null || _liveSubscription != null;

    if (!_isListening) {
      _isPaused = false;
      _expiryTimer?.cancel();
      _expiryTimer = null;
    }
  }

  void _handleStreamError(
    Object error, {
    required StackTrace stackTrace,
    required TypingListenerErrorSource source,
    required int listenerGeneration,
  }) {
    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    _emitSafeError(
      TypingListenerException(
        code: TypingListenerErrorCode.stream,
        source: source,
        message: source == TypingListenerErrorSource.typing
            ? 'The realtime typing stream reported an error.'
            : 'The realtime Live Chat stream reported an error.',
        conversationId: _conversationId,
        cause: error,
        stackTrace: stackTrace,
      ),
      listenerGeneration: listenerGeneration,
    );
  }

  void _emitSafeError(Object error, {required int listenerGeneration}) {
    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    _errorController.add(error);
  }

  // --------------------------------------------------------------------------
  // EMISSION
  // --------------------------------------------------------------------------

  void _emitSnapshot(int listenerGeneration) {
    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    final String? activeConversationId = _conversationId;
    final String? activeCurrentUid = _currentUid;

    if (activeConversationId == null || activeCurrentUid == null) {
      return;
    }

    _snapshotController.add(
      TypingListenerSnapshot(
        conversationId: activeConversationId,
        currentUid: activeCurrentUid,
        peerTyping: _peerTyping,
        peerLiveChat: _peerLiveChat,
        generation: listenerGeneration,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // EQUALITY / DEDUPLICATION
  // --------------------------------------------------------------------------

  static bool _typingEquivalent(TypingState? first, TypingState? second) {
    if (identical(first, second)) {
      return true;
    }

    if (first == null || second == null) {
      return false;
    }

    return first.conversationId == second.conversationId &&
        first.userUid == second.userUid &&
        first.isTyping == second.isTyping &&
        first.updatedAt == second.updatedAt &&
        first.expiresAt == second.expiresAt;
  }

  static bool _liveEquivalent(LiveChatState? first, LiveChatState? second) {
    if (identical(first, second)) {
      return true;
    }

    if (first == null || second == null) {
      return false;
    }

    return first.conversationId == second.conversationId &&
        first.senderUid == second.senderUid &&
        first.sessionId == second.sessionId &&
        first.version == second.version &&
        first.text == second.text &&
        first.styleSeed == second.styleSeed &&
        first.updatedAt == second.updatedAt &&
        first.expiresAt == second.expiresAt &&
        first.isActive == second.isActive;
  }

  // --------------------------------------------------------------------------
  // INTERNAL VALIDATION
  // --------------------------------------------------------------------------

  bool _isCurrentGeneration(int listenerGeneration) {
    return !_isDisposed && listenerGeneration == _generation;
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('TypingListener has already been disposed.');
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

  static Duration _validateExpiryInterval(Duration value) {
    if (value <= Duration.zero) {
      throw ArgumentError.value(
        value,
        'expiryCheckInterval',
        'Expiry check interval must be greater than zero.',
      );
    }

    return value;
  }

  // --------------------------------------------------------------------------
  // DISPOSAL
  // --------------------------------------------------------------------------

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    // Invalidate all stale callbacks before cancelling subscriptions.
    ++_generation;

    _isDisposed = true;
    _isListening = false;
    _isPaused = false;

    _expiryTimer?.cancel();
    _expiryTimer = null;

    final StreamSubscription<List<TypingState>>? typingSubscription =
        _typingSubscription;

    final StreamSubscription<List<LiveChatState>>? liveSubscription =
        _liveSubscription;

    _typingSubscription = null;
    _liveSubscription = null;

    _conversationId = null;
    _currentUid = null;

    _peerTyping = null;
    _peerLiveChat = null;

    if (typingSubscription != null) {
      await typingSubscription.cancel();
    }

    if (liveSubscription != null) {
      await liveSubscription.cancel();
    }

    await _snapshotController.close();
    await _typingController.close();
    await _liveChatController.close();
    await _errorController.close();
  }
}

/// Identifies which realtime source produced a listener error.
enum TypingListenerErrorSource { typing, liveChat }

/// Stable normalized listener error categories.
enum TypingListenerErrorCode { invalidConversation, stream }

/// Safe normalized typing/Live Chat listener exception.
///
/// [cause] and [stackTrace] are retained only for internal diagnostics.
/// Higher UI layers must not blindly expose raw backend error text.
final class TypingListenerException implements Exception {
  const TypingListenerException({
    required this.code,
    required this.source,
    required this.message,
    this.conversationId,
    this.userUid,
    this.cause,
    this.stackTrace,
  });

  final TypingListenerErrorCode code;
  final TypingListenerErrorSource source;

  final String message;
  final String? conversationId;
  final String? userUid;

  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() {
    return 'TypingListenerException('
        'code: ${code.name}, '
        'source: ${source.name}, '
        'message: $message'
        ')';
  }
}

// ============================================================================
// END OF FILE: lib/features/message/realtime/typing_listener.dart
// ============================================================================
