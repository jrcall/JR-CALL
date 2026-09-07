// ============================================================================
// JR CALL
// File: presence_listener.dart
// Location: lib/features/message/realtime/presence_listener.dart
// Description:
// Message-screen presence representation listener for JR CALL Message Engine.
//
// Owns:
// - One active presence-state subscription.
// - One subscribed target Firebase UID.
// - Online / offline / last-seen representation.
// - Canonical Firebase UID validation.
// - Stale subscription generation protection.
// - Duplicate presence-event suppression.
// - Timestamp monotonicity protection.
// - Safe subscription cancellation / restart / pause / resume / disposal.
// - Immutable normalized presence output.
//
// Does NOT own:
// - Global JR CALL presence architecture.
// - Presence Firestore/Realtime Database paths.
// - Presence writes.
// - Authentication.
// - User discovery.
// - Typing / Live Chat.
// - Durable messages.
// - Call Engine / WebRTC.
//
// IMPORTANT:
// This listener consumes the existing JR CALL presence source through a typed
// stream supplied by the repository/shared presence layer. It intentionally
// does not create a second global presence backend.
// ============================================================================

import 'dart:async';

/// Canonical Message-feature representation of a presence update consumed
/// from the existing shared JR CALL presence source.
///
/// [userUid] is always the canonical Firebase Auth UID.
///
/// [isOnline] must represent a real presence state from the shared presence
/// owner. This class never infers online status from message activity.
///
/// [lastSeenAt] should represent the real shared presence last-seen value
/// when available.
///
/// [updatedAt] identifies the freshness of this presence record and is used
/// for monotonic stale-update rejection.
final class MessagePresenceState {
  MessagePresenceState({
    required String userUid,
    required this.isOnline,
    required DateTime updatedAt,
    DateTime? lastSeenAt,
  }) : userUid = _normalizeRequired(userUid, 'userUid'),
       updatedAt = updatedAt.toUtc(),
       lastSeenAt = lastSeenAt?.toUtc();

  final String userUid;
  final bool isOnline;

  /// Real last-seen value from the shared presence source, when available.
  final DateTime? lastSeenAt;

  /// Freshness marker for stale-update rejection.
  final DateTime updatedAt;

  MessagePresenceState copyWith({
    String? userUid,
    bool? isOnline,
    DateTime? lastSeenAt,
    bool clearLastSeenAt = false,
    DateTime? updatedAt,
  }) {
    return MessagePresenceState(
      userUid: userUid ?? this.userUid,
      isOnline: isOnline ?? this.isOnline,
      lastSeenAt: clearLastSeenAt ? null : (lastSeenAt ?? this.lastSeenAt),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'userUid': userUid,
      'isOnline': isOnline,
      'lastSeenAt': lastSeenAt,
      'updatedAt': updatedAt,
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

/// Immutable presence snapshot exposed to Message controllers/repositories.
final class PresenceListenerSnapshot {
  PresenceListenerSnapshot({
    required String userUid,
    required this.presence,
    required int generation,
  }) : userUid = _normalizeRequired(userUid, 'userUid'),
       generation = _validateGeneration(generation);

  /// Canonical Firebase UID currently being observed.
  final String userUid;

  /// Current real presence state.
  ///
  /// Null means the listener has not received a valid presence record or the
  /// supplied shared presence source explicitly removed/cleared the state.
  final MessagePresenceState? presence;

  /// Listener generation that produced this snapshot.
  final int generation;

  bool get hasPresence => presence != null;

  /// This never invents an online state.
  bool get isOnline => presence?.isOnline ?? false;

  DateTime? get lastSeenAt => presence?.lastSeenAt;

  DateTime? get updatedAt => presence?.updatedAt;

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

/// Realtime Message-screen presence observer.
///
/// The stream supplied to [startListening] must come from the existing shared
/// JR CALL user/presence architecture.
///
/// This class deliberately does not know or own whether that shared source is
/// backed by Firestore, Realtime Database, Cloud Functions, or another
/// application-level presence service.
///
/// Only one target UID is observed at a time.
///
/// Important guarantees:
/// - canonical Firebase UID based identity,
/// - no online inference,
/// - stale generation callbacks rejected,
/// - stale timestamp updates rejected,
/// - duplicate updates suppressed,
/// - safe replacement of active subscriptions,
/// - no shared singleton is disposed by this class.
final class PresenceListener {
  PresenceListener();

  final StreamController<PresenceListenerSnapshot> _snapshotController =
      StreamController<PresenceListenerSnapshot>.broadcast(sync: true);

  final StreamController<MessagePresenceState?> _presenceController =
      StreamController<MessagePresenceState?>.broadcast(sync: true);

  final StreamController<Object> _errorController =
      StreamController<Object>.broadcast(sync: true);

  StreamSubscription<MessagePresenceState?>? _subscription;

  String? _userUid;
  MessagePresenceState? _presence;

  int _generation = 0;

  bool _isListening = false;
  bool _isPaused = false;
  bool _isDisposed = false;

  // --------------------------------------------------------------------------
  // PUBLIC STATE
  // --------------------------------------------------------------------------

  /// Canonical Firebase UID currently being observed.
  String? get userUid => _userUid;

  MessagePresenceState? get presence => _presence;

  int get generation => _generation;

  bool get isListening => _isListening;

  bool get isPaused => _isPaused;

  bool get isDisposed => _isDisposed;

  bool get hasPresence => _presence != null;

  /// Returns only confirmed shared-presence state.
  ///
  /// Absence of a presence record is not treated as proof of online status.
  bool get isOnline => _presence?.isOnline ?? false;

  DateTime? get lastSeenAt => _presence?.lastSeenAt;

  Stream<PresenceListenerSnapshot> get snapshots => _snapshotController.stream;

  Stream<MessagePresenceState?> get states => _presenceController.stream;

  Stream<Object> get errors => _errorController.stream;

  // --------------------------------------------------------------------------
  // LISTENER LIFECYCLE
  // --------------------------------------------------------------------------

  /// Starts observing [userUid] using an existing JR CALL presence stream.
  ///
  /// [userUid] must be a canonical Firebase Auth UID.
  ///
  /// The supplied [stream] must not manufacture presence specifically for the
  /// Message feature. It should adapt the existing shared JR CALL presence
  /// owner into [MessagePresenceState].
  Future<void> startListening({
    required String userUid,
    required Stream<MessagePresenceState?> stream,
  }) async {
    _ensureNotDisposed();

    final String normalizedUid = _normalizeId(userUid, fieldName: 'userUid');

    // Invalidate previous callbacks BEFORE cancellation/replacement.
    final int listenerGeneration = ++_generation;

    final StreamSubscription<MessagePresenceState?>? previous = _subscription;

    _subscription = null;

    _isListening = false;
    _isPaused = false;

    if (previous != null) {
      await previous.cancel();
    }

    _userUid = normalizedUid;
    _presence = null;

    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    late final StreamSubscription<MessagePresenceState?> subscription;

    subscription = stream.listen(
      (MessagePresenceState? incoming) {
        _handlePresence(
          incoming,
          expectedUid: normalizedUid,
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

  /// Replaces the current target/source using the same lifecycle guarantees
  /// as [startListening].
  Future<void> restartListening({
    required String userUid,
    required Stream<MessagePresenceState?> stream,
  }) {
    return startListening(userUid: userUid, stream: stream);
  }

  /// Stops observation and clears the currently accepted presence state.
  Future<void> stopListening() async {
    if (_isDisposed) {
      return;
    }

    // Invalidate late callbacks before cancellation.
    ++_generation;

    final StreamSubscription<MessagePresenceState?>? subscription =
        _subscription;

    _subscription = null;

    _isListening = false;
    _isPaused = false;

    _userUid = null;
    _presence = null;

    if (subscription != null) {
      await subscription.cancel();
    }
  }

  /// Pauses the active presence subscription without clearing current state.
  void pauseListening() {
    _ensureNotDisposed();

    final StreamSubscription<MessagePresenceState?>? subscription =
        _subscription;

    if (subscription == null || !_isListening || _isPaused) {
      return;
    }

    subscription.pause();
    _isPaused = true;
  }

  /// Resumes a previously paused presence subscription.
  void resumeListening() {
    _ensureNotDisposed();

    final StreamSubscription<MessagePresenceState?>? subscription =
        _subscription;

    if (subscription == null || !_isListening || !_isPaused) {
      return;
    }

    subscription.resume();
    _isPaused = false;
  }

  /// Clears only the locally accepted presence representation.
  ///
  /// This performs no remote presence write.
  void clearSnapshot() {
    _ensureNotDisposed();

    if (_presence == null) {
      return;
    }

    _presence = null;

    _presenceController.add(null);
    _emitSnapshot(_generation);
  }

  // --------------------------------------------------------------------------
  // PRESENCE PROCESSING
  // --------------------------------------------------------------------------

  void _handlePresence(
    MessagePresenceState? incoming, {
    required String expectedUid,
    required int listenerGeneration,
  }) {
    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    if (incoming == null) {
      if (_presence == null) {
        return;
      }

      _presence = null;

      _presenceController.add(null);
      _emitSnapshot(listenerGeneration);
      return;
    }

    final String incomingUid = _normalizeId(
      incoming.userUid,
      fieldName: 'presence.userUid',
    );

    if (incomingUid != expectedUid) {
      _emitSafeError(
        PresenceListenerException(
          code: PresenceListenerErrorCode.invalidUser,
          message: 'Presence update belongs to a different Firebase user.',
          expectedUserUid: expectedUid,
          receivedUserUid: incomingUid,
        ),
        listenerGeneration: listenerGeneration,
      );
      return;
    }

    final MessagePresenceState normalized = _normalizePresence(incoming);

    final MessagePresenceState? previous = _presence;

    if (previous != null) {
      // Never allow an older shared presence update to overwrite a newer one.
      if (normalized.updatedAt.isBefore(previous.updatedAt)) {
        return;
      }

      // Same source timestamp with different contents is resolved
      // deterministically so duplicate/multi-source callbacks cannot flap
      // presence presentation.
      if (normalized.updatedAt == previous.updatedAt) {
        if (_presenceEquivalent(previous, normalized)) {
          return;
        }

        final MessagePresenceState preferred = _chooseSameTimestampVersion(
          previous,
          normalized,
        );

        if (_presenceEquivalent(preferred, previous)) {
          return;
        }

        _presence = preferred;

        _presenceController.add(preferred);
        _emitSnapshot(listenerGeneration);
        return;
      }
    }

    if (_presenceEquivalent(previous, normalized)) {
      return;
    }

    _presence = normalized;

    _presenceController.add(normalized);
    _emitSnapshot(listenerGeneration);
  }

  static MessagePresenceState _normalizePresence(MessagePresenceState state) {
    DateTime? normalizedLastSeen = state.lastSeenAt?.toUtc();

    // An online record may legitimately retain its most recent offline
    // last-seen timestamp from the shared architecture. We therefore do not
    // erase it here.
    //
    // Guard only against impossible future-ordering within this record:
    // lastSeen must not exceed updatedAt.
    if (normalizedLastSeen != null &&
        normalizedLastSeen.isAfter(state.updatedAt)) {
      normalizedLastSeen = state.updatedAt;
    }

    return MessagePresenceState(
      userUid: state.userUid,
      isOnline: state.isOnline,
      lastSeenAt: normalizedLastSeen,
      updatedAt: state.updatedAt,
    );
  }

  /// Deterministic resolution when two states carry the exact same freshness
  /// timestamp.
  ///
  /// We do not infer online from timing.
  ///
  /// If one update represents offline and supplies a newer/more useful
  /// last-seen boundary while timestamps are equal, prefer that state.
  /// Otherwise retain the already accepted version to prevent flapping.
  static MessagePresenceState _chooseSameTimestampVersion(
    MessagePresenceState previous,
    MessagePresenceState incoming,
  ) {
    if (previous.isOnline == incoming.isOnline) {
      final DateTime? previousLastSeen = previous.lastSeenAt;
      final DateTime? incomingLastSeen = incoming.lastSeenAt;

      if (previousLastSeen == null && incomingLastSeen != null) {
        return incoming;
      }

      if (previousLastSeen != null &&
          incomingLastSeen != null &&
          incomingLastSeen.isAfter(previousLastSeen)) {
        return incoming;
      }

      return previous;
    }

    if (!incoming.isOnline) {
      final DateTime? incomingLastSeen = incoming.lastSeenAt;
      final DateTime? previousLastSeen = previous.lastSeenAt;

      if (incomingLastSeen != null &&
          (previousLastSeen == null ||
              !incomingLastSeen.isBefore(previousLastSeen))) {
        return incoming;
      }
    }

    return previous;
  }

  // --------------------------------------------------------------------------
  // STREAM ERROR / COMPLETION
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
      PresenceListenerException(
        code: PresenceListenerErrorCode.stream,
        message: 'The shared presence stream reported an error.',
        expectedUserUid: _userUid,
        cause: error,
        stackTrace: stackTrace,
      ),
      listenerGeneration: listenerGeneration,
    );
  }

  void _handleDone(
    StreamSubscription<MessagePresenceState?> subscription, {
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
  // EMISSION
  // --------------------------------------------------------------------------

  void _emitSnapshot(int listenerGeneration) {
    if (!_isCurrentGeneration(listenerGeneration)) {
      return;
    }

    final String? activeUid = _userUid;

    if (activeUid == null) {
      return;
    }

    _snapshotController.add(
      PresenceListenerSnapshot(
        userUid: activeUid,
        presence: _presence,
        generation: listenerGeneration,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // DEDUPLICATION
  // --------------------------------------------------------------------------

  static bool _presenceEquivalent(
    MessagePresenceState? first,
    MessagePresenceState? second,
  ) {
    if (identical(first, second)) {
      return true;
    }

    if (first == null || second == null) {
      return false;
    }

    return first.userUid == second.userUid &&
        first.isOnline == second.isOnline &&
        first.lastSeenAt == second.lastSeenAt &&
        first.updatedAt == second.updatedAt;
  }

  // --------------------------------------------------------------------------
  // INTERNAL VALIDATION
  // --------------------------------------------------------------------------

  bool _isCurrentGeneration(int listenerGeneration) {
    return !_isDisposed && listenerGeneration == _generation;
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('PresenceListener has already been disposed.');
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

    // Invalidate all late callbacks before cancellation.
    ++_generation;

    _isDisposed = true;
    _isListening = false;
    _isPaused = false;

    final StreamSubscription<MessagePresenceState?>? subscription =
        _subscription;

    _subscription = null;

    _userUid = null;
    _presence = null;

    if (subscription != null) {
      await subscription.cancel();
    }

    await _snapshotController.close();
    await _presenceController.close();
    await _errorController.close();
  }
}

/// Stable presence-listener error categories.
enum PresenceListenerErrorCode { invalidUser, stream }

/// Safe normalized Message presence-listener exception.
///
/// Raw shared/backend exception text remains available through [cause] only
/// for internal diagnostics and must not be blindly shown in UI.
final class PresenceListenerException implements Exception {
  const PresenceListenerException({
    required this.code,
    required this.message,
    this.expectedUserUid,
    this.receivedUserUid,
    this.cause,
    this.stackTrace,
  });

  final PresenceListenerErrorCode code;

  /// Safe higher-layer description.
  final String message;

  final String? expectedUserUid;
  final String? receivedUserUid;

  /// Internal diagnostic source error.
  final Object? cause;

  final StackTrace? stackTrace;

  @override
  String toString() {
    return 'PresenceListenerException('
        'code: ${code.name}, '
        'message: $message'
        ')';
  }
}

// ============================================================================
// END OF FILE: lib/features/message/realtime/presence_listener.dart
// ============================================================================
