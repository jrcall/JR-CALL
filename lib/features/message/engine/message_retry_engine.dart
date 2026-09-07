// ============================================================================
// JR CALL
// File: message_retry_engine.dart
// Location: lib/features/message/engine/message_retry_engine.dart
// Description:
// Production reliable durable-message retry engine.
//
// Responsibilities:
// - Retries failed outgoing messages using the SAME canonical message ID.
// - Classifies transient vs permanent failures.
// - Performs bounded exponential backoff.
// - Prevents infinite retry loops.
// - Prevents duplicate concurrent retries.
// - Supports cancellation/reset/disposal.
// - Supports retry after confirmed network restoration.
// - Preserves Firebase UID/conversation/message ownership.
// - Transitions failed -> queued -> sending -> sent only through real send.
// - Marks permanent/exhausted failures safely.
// - Rejects stale session completions.
//
// Important:
// - Stable canonical message ID is NEVER replaced during retry.
// - Authentication/permission/validation failures are NOT retried.
// - No timer-derived delivery/read state exists here.
// - Does NOT own Firestore collection references.
// - Does NOT own Firebase Storage.
// - Does NOT render UI.
// - Does NOT contain Call Engine/WebRTC logic.
// ============================================================================

import 'dart:async';
import 'dart:collection';

import '../data/message_entity.dart';
import '../data/message_status.dart';

/// Canonical retry decision.
enum MessageRetryDisposition { transient, permanent, cancelled }

/// Normalized retry failure category.
///
/// These categories follow the JR CALL Message Engine error contract without
/// exposing raw backend exception text to presentation code.
enum MessageRetryErrorCategory {
  authentication,
  permission,
  network,
  validation,
  storage,
  quota,
  notFound,
  conflict,
  cancelled,
  temporary,
  unknown,
}

/// Immutable classified retry failure.
final class MessageRetryFailure {
  const MessageRetryFailure({
    required this.disposition,
    required this.category,
    required this.safeCode,
    this.safeMessage,
  });

  final MessageRetryDisposition disposition;
  final MessageRetryErrorCategory category;

  /// Stable sanitized diagnostic code.
  final String safeCode;

  /// Optional user-safe diagnostic text.
  ///
  /// Raw Firebase/backend exception text must not be copied here blindly.
  final String? safeMessage;

  bool get canRetry => disposition == MessageRetryDisposition.transient;
}

/// Retry error classification boundary.
///
/// Repository/storage/network adapters can classify their concrete exceptions
/// without coupling this engine directly to Firebase exception classes.
abstract interface class MessageRetryClassifier {
  MessageRetryFailure classify(Object error, StackTrace stackTrace);
}

/// Retry persistence/state bridge.
///
/// FILE 14 / FILE 17 / FILE 35 can provide the production implementation.
abstract interface class MessageRetryStateStore {
  /// Returns the canonical locally known outgoing message.
  MessageEntity? findMessage(String messageId);

  /// Applies an updated local retry state.
  FutureOr<void> upsertMessage(MessageEntity message);

  /// Stores a safe final failure state.
  FutureOr<void> markRetryFailure({
    required MessageEntity message,
    required MessageRetryFailure failure,
    required int attempts,
  });
}

/// Actual stable-ID resend executor.
///
/// The concrete repository adapter must retry persistence using the original
/// [message.id]. It must not create a new message ID.
abstract interface class MessageRetryExecutor {
  Future<MessageEntity> resend({
    required String authenticatedUid,
    required String conversationId,
    required MessageEntity message,
  });
}

/// Optional connectivity source.
///
/// This engine does not infer connectivity from timers. The app/repository
/// layer may explicitly notify it when transport has actually recovered.
abstract interface class MessageRetryNetworkState {
  bool get isNetworkAvailable;
}

/// Production retry queue.
final class MessageRetryEngine {
  factory MessageRetryEngine({
    required MessageRetryClassifier classifier,
    required MessageRetryStateStore stateStore,
    required MessageRetryExecutor executor,
    MessageRetryNetworkState? networkState,
    int maxAttempts = 5,
    Duration initialBackoff = const Duration(seconds: 1),
    Duration maxBackoff = const Duration(seconds: 30),
    int rememberedMessageLimit = 512,
  }) {
    return MessageRetryEngine._(
      classifier,
      stateStore,
      executor,
      networkState,
      _validateMaxAttempts(maxAttempts),
      _validateInitialBackoff(initialBackoff),
      _validateMaxBackoff(
        initialBackoff: initialBackoff,
        maxBackoff: maxBackoff,
      ),
      _validateRememberedMessageLimit(rememberedMessageLimit),
    );
  }

  MessageRetryEngine._(
    this._classifier,
    this._stateStore,
    this._executor,
    this._networkState,
    this._maxAttempts,
    this._initialBackoff,
    this._maxBackoff,
    this._rememberedMessageLimit,
  );

  final MessageRetryClassifier _classifier;
  final MessageRetryStateStore _stateStore;
  final MessageRetryExecutor _executor;
  final MessageRetryNetworkState? _networkState;

  final int _maxAttempts;
  final Duration _initialBackoff;
  final Duration _maxBackoff;
  final int _rememberedMessageLimit;

  final Map<String, Future<MessageEntity>> _activeRetries =
      <String, Future<MessageEntity>>{};

  final LinkedHashMap<String, int> _attemptsByMessageId =
      LinkedHashMap<String, int>();

  final Set<String> _cancelledMessageIds = <String>{};

  final Map<String, Timer> _backoffTimers = <String, Timer>{};

  final Map<String, Completer<void>> _backoffCompleters =
      <String, Completer<void>>{};

  String? _authenticatedUid;
  String? _conversationId;

  int _sessionGeneration = 0;

  bool _initialized = false;
  bool _disposed = false;

  /// True while initialized for an authenticated conversation.
  bool get isInitialized => _initialized && !_disposed;

  /// True after permanent disposal.
  bool get isDisposed => _disposed;

  /// Returns active attempt count for one canonical message ID.
  int attemptsFor(String messageId) {
    final String normalized = messageId.trim();

    if (normalized.isEmpty) {
      return 0;
    }

    return _attemptsByMessageId[normalized] ?? 0;
  }

  /// Returns true while the specific message retry is active.
  bool isRetrying(String messageId) {
    final String normalized = messageId.trim();
    return normalized.isNotEmpty && _activeRetries.containsKey(normalized);
  }

  /// Initializes this retry engine for one Firebase-authenticated conversation.
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

    ++_sessionGeneration;

    _authenticatedUid = uid;
    _conversationId = conversation;
    _initialized = true;
  }

  /// Retries one failed outgoing durable message.
  ///
  /// This public API is frozen by FILE 01.
  Future<MessageEntity> retry({
    required String authenticatedUid,
    required String conversationId,
    required String messageId,
  }) {
    final _RetrySession session = _requireMatchingSession(
      authenticatedUid: authenticatedUid,
      conversationId: conversationId,
    );

    final String id = _normalizeRequiredIdentifier(
      messageId,
      fieldName: 'messageId',
    );

    final Future<MessageEntity>? existing = _activeRetries[id];

    if (existing != null) {
      return existing;
    }

    final MessageEntity? message = _stateStore.findMessage(id);

    if (message == null) {
      return Future<MessageEntity>.error(
        StateError('Cannot retry unknown message $id.'),
      );
    }

    _validateRetryMessage(message, session: session);

    if (_isDurablyAccepted(message.status)) {
      return Future<MessageEntity>.value(message);
    }

    if (message.status != MessageStatus.failed &&
        message.status != MessageStatus.queued &&
        message.status != MessageStatus.sending) {
      return Future<MessageEntity>.error(
        StateError('Message $id is not in a retryable client state.'),
      );
    }

    _cancelledMessageIds.remove(id);

    final Future<MessageEntity> operation = _runRetryLoop(
      session: session,
      initialMessage: message,
    );

    _activeRetries[id] = operation;

    operation.whenComplete(() {
      if (identical(_activeRetries[id], operation)) {
        _activeRetries.remove(id);
      }
    });

    return operation;
  }

  Future<MessageEntity> _runRetryLoop({
    required _RetrySession session,
    required MessageEntity initialMessage,
  }) async {
    final String messageId = initialMessage.id;
    final int generation = session.generation;

    MessageEntity current = initialMessage;

    while (true) {
      _assertGeneration(generation);
      _throwIfCancelled(messageId);

      final int currentAttempts = _attemptsByMessageId[messageId] ?? 0;

      if (currentAttempts >= _maxAttempts) {
        final MessageRetryFailure exhausted = const MessageRetryFailure(
          disposition: MessageRetryDisposition.permanent,
          category: MessageRetryErrorCategory.temporary,
          safeCode: 'retry_attempts_exhausted',
          safeMessage: 'Message retry limit reached.',
        );

        await _markPermanentFailure(
          message: current,
          failure: exhausted,
          attempts: currentAttempts,
        );

        throw StateError('Retry limit reached for message $messageId.');
      }

      if (_networkState != null && !_networkState.isNetworkAvailable) {
        final MessageRetryFailure unavailable = const MessageRetryFailure(
          disposition: MessageRetryDisposition.transient,
          category: MessageRetryErrorCategory.network,
          safeCode: 'network_unavailable',
          safeMessage: 'Network is currently unavailable.',
        );

        await _markTransientFailure(
          message: current,
          failure: unavailable,
          attempts: currentAttempts,
        );

        throw StateError('Network unavailable for message retry.');
      }

      final int attempt = currentAttempts + 1;

      _rememberAttempt(messageId, attempt);

      final MessageEntity queued = current.copyWith(
        status: MessageStatus.queued,
        localOnly: true,
        clearFailureCode: true,
        clearFailureMessage: true,
      );

      await _stateStore.upsertMessage(queued);

      _assertGeneration(generation);
      _throwIfCancelled(messageId);

      final MessageEntity sending = queued.copyWith(
        status: MessageStatus.sending,
        localOnly: true,
        clearFailureCode: true,
        clearFailureMessage: true,
      );

      await _stateStore.upsertMessage(sending);

      _assertGeneration(generation);
      _throwIfCancelled(messageId);

      try {
        final MessageEntity persisted = await _executor.resend(
          authenticatedUid: session.authenticatedUid,
          conversationId: session.conversationId,
          message: sending,
        );

        _assertGeneration(generation);
        _throwIfCancelled(messageId);

        _validatePersistedIdentity(expected: sending, persisted: persisted);

        final MessageStatus acceptedStatus = _acceptedStatus(persisted.status);

        final MessageEntity sent = persisted.copyWith(
          status: acceptedStatus,
          localOnly: false,
          clearFailureCode: true,
          clearFailureMessage: true,
        );

        await _stateStore.upsertMessage(sent);

        _attemptsByMessageId.remove(messageId);
        _cancelledMessageIds.remove(messageId);

        return sent;
      } catch (error, stackTrace) {
        if (!_isGenerationCurrent(generation)) {
          Error.throwWithStackTrace(error, stackTrace);
        }

        if (_cancelledMessageIds.contains(messageId)) {
          throw StateError('Retry cancelled for message $messageId.');
        }

        final MessageRetryFailure failure = _classifier.classify(
          error,
          stackTrace,
        );

        if (failure.disposition == MessageRetryDisposition.cancelled) {
          await _markCancelledFailure(
            message: sending,
            failure: failure,
            attempts: attempt,
          );

          Error.throwWithStackTrace(error, stackTrace);
        }

        if (!failure.canRetry) {
          await _markPermanentFailure(
            message: sending,
            failure: failure,
            attempts: attempt,
          );

          Error.throwWithStackTrace(error, stackTrace);
        }

        await _markTransientFailure(
          message: sending,
          failure: failure,
          attempts: attempt,
        );

        if (attempt >= _maxAttempts) {
          final MessageRetryFailure exhausted = MessageRetryFailure(
            disposition: MessageRetryDisposition.permanent,
            category: failure.category,
            safeCode: 'retry_attempts_exhausted',
            safeMessage: failure.safeMessage,
          );

          final MessageEntity failed =
              _stateStore.findMessage(messageId) ?? sending;

          await _markPermanentFailure(
            message: failed,
            failure: exhausted,
            attempts: attempt,
          );

          Error.throwWithStackTrace(error, stackTrace);
        }

        final Duration delay = _calculateBackoff(attempt);

        await _waitBackoff(
          messageId: messageId,
          delay: delay,
          generation: generation,
        );

        _assertGeneration(generation);
        _throwIfCancelled(messageId);

        current = _stateStore.findMessage(messageId) ?? sending;
      }
    }
  }

  /// Explicitly retries currently failed messages after REAL network recovery.
  ///
  /// The caller must invoke this only after connectivity restoration has been
  /// observed by the existing network layer.
  Future<List<MessageEntity>> retryFailedOnNetworkRestored({
    required String authenticatedUid,
    required String conversationId,
    required Iterable<String> messageIds,
  }) async {
    final _RetrySession session = _requireMatchingSession(
      authenticatedUid: authenticatedUid,
      conversationId: conversationId,
    );

    if (_networkState != null && !_networkState.isNetworkAvailable) {
      return const <MessageEntity>[];
    }

    final LinkedHashSet<String> uniqueIds = LinkedHashSet<String>();

    for (final String value in messageIds) {
      final String normalized = value.trim();

      if (normalized.isNotEmpty) {
        uniqueIds.add(normalized);
      }
    }

    final List<MessageEntity> completed = <MessageEntity>[];

    for (final String messageId in uniqueIds) {
      final MessageEntity? message = _stateStore.findMessage(messageId);

      if (message == null ||
          message.conversationId != session.conversationId ||
          message.senderUid != session.authenticatedUid ||
          message.status != MessageStatus.failed) {
        continue;
      }

      try {
        completed.add(
          await retry(
            authenticatedUid: session.authenticatedUid,
            conversationId: session.conversationId,
            messageId: messageId,
          ),
        );
      } catch (_) {
        // Individual failure remains recorded in canonical local state.
        // One failed retry must not block unrelated failed messages.
      }
    }

    return List<MessageEntity>.unmodifiable(completed);
  }

  /// Cancels retry/backoff for one canonical message.
  void cancel(String messageId) {
    _ensureNotDisposed();

    final String id = _normalizeRequiredIdentifier(
      messageId,
      fieldName: 'messageId',
    );

    _cancelledMessageIds.add(id);

    final Timer? timer = _backoffTimers.remove(id);
    timer?.cancel();

    final Completer<void>? completer = _backoffCompleters.remove(id);

    if (completer != null && !completer.isCompleted) {
      completer.completeError(StateError('Retry cancelled for message $id.'));
    }
  }

  /// Cancels every currently scheduled retry.
  void cancelAll() {
    _ensureNotDisposed();

    _cancelledMessageIds.addAll(_activeRetries.keys);
    _cancelledMessageIds.addAll(_backoffTimers.keys);

    for (final Timer timer in _backoffTimers.values) {
      timer.cancel();
    }

    _backoffTimers.clear();

    final List<MapEntry<String, Completer<void>>> pending = _backoffCompleters
        .entries
        .toList(growable: false);

    _backoffCompleters.clear();

    for (final MapEntry<String, Completer<void>> entry in pending) {
      if (!entry.value.isCompleted) {
        entry.value.completeError(
          StateError('Retry cancelled for message ${entry.key}.'),
        );
      }
    }
  }

  Future<void> _waitBackoff({
    required String messageId,
    required Duration delay,
    required int generation,
  }) {
    _throwIfCancelled(messageId);

    final Completer<void> completer = Completer<void>();

    _backoffCompleters[messageId] = completer;

    final Timer timer = Timer(delay, () {
      if (!_isGenerationCurrent(generation)) {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('Message retry belongs to a stale session.'),
          );
        }
        return;
      }

      if (_cancelledMessageIds.contains(messageId)) {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('Retry cancelled for message $messageId.'),
          );
        }
        return;
      }

      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    _backoffTimers[messageId] = timer;

    return completer.future.whenComplete(() {
      final Timer? registered = _backoffTimers[messageId];

      if (identical(registered, timer)) {
        _backoffTimers.remove(messageId);
      }

      final Completer<void>? registeredCompleter =
          _backoffCompleters[messageId];

      if (identical(registeredCompleter, completer)) {
        _backoffCompleters.remove(messageId);
      }

      timer.cancel();
    });
  }

  Future<void> _markTransientFailure({
    required MessageEntity message,
    required MessageRetryFailure failure,
    required int attempts,
  }) async {
    final MessageEntity failed = message.copyWith(
      status: MessageStatus.failed,
      localOnly: true,
      failureCode: failure.safeCode,
      failureMessage: failure.safeMessage,
    );

    await _stateStore.upsertMessage(failed);

    await _stateStore.markRetryFailure(
      message: failed,
      failure: failure,
      attempts: attempts,
    );
  }

  Future<void> _markPermanentFailure({
    required MessageEntity message,
    required MessageRetryFailure failure,
    required int attempts,
  }) async {
    final MessageEntity failed = message.copyWith(
      status: MessageStatus.failed,
      localOnly: true,
      failureCode: failure.safeCode,
      failureMessage: failure.safeMessage,
    );

    await _stateStore.upsertMessage(failed);

    await _stateStore.markRetryFailure(
      message: failed,
      failure: failure,
      attempts: attempts,
    );
  }

  Future<void> _markCancelledFailure({
    required MessageEntity message,
    required MessageRetryFailure failure,
    required int attempts,
  }) async {
    final MessageEntity failed = message.copyWith(
      status: MessageStatus.failed,
      localOnly: true,
      failureCode: failure.safeCode,
      failureMessage: failure.safeMessage,
    );

    await _stateStore.upsertMessage(failed);

    await _stateStore.markRetryFailure(
      message: failed,
      failure: failure,
      attempts: attempts,
    );
  }

  Duration _calculateBackoff(int attempt) {
    int milliseconds = _initialBackoff.inMilliseconds;

    for (int index = 1; index < attempt; index++) {
      if (milliseconds >= _maxBackoff.inMilliseconds) {
        milliseconds = _maxBackoff.inMilliseconds;
        break;
      }

      milliseconds *= 2;

      if (milliseconds > _maxBackoff.inMilliseconds) {
        milliseconds = _maxBackoff.inMilliseconds;
      }
    }

    return Duration(milliseconds: milliseconds);
  }

  void _rememberAttempt(String messageId, int attempt) {
    _attemptsByMessageId.remove(messageId);
    _attemptsByMessageId[messageId] = attempt;

    while (_attemptsByMessageId.length > _rememberedMessageLimit) {
      _attemptsByMessageId.remove(_attemptsByMessageId.keys.first);
    }
  }

  _RetrySession _requireSession() {
    _ensureNotDisposed();

    if (!_initialized) {
      throw StateError('MessageRetryEngine is not initialized.');
    }

    final String? uid = _authenticatedUid;
    final String? conversation = _conversationId;

    if (uid == null ||
        uid.isEmpty ||
        conversation == null ||
        conversation.isEmpty) {
      throw StateError(
        'MessageRetryEngine has no valid authenticated conversation session.',
      );
    }

    return _RetrySession(
      authenticatedUid: uid,
      conversationId: conversation,
      generation: _sessionGeneration,
    );
  }

  _RetrySession _requireMatchingSession({
    required String authenticatedUid,
    required String conversationId,
  }) {
    final _RetrySession session = _requireSession();

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
        'MessageRetryEngine authenticated UID does not match active session.',
      );
    }

    if (conversation != session.conversationId) {
      throw StateError(
        'MessageRetryEngine conversation ID does not match active session.',
      );
    }

    return session;
  }

  static void _validateRetryMessage(
    MessageEntity message, {
    required _RetrySession session,
  }) {
    _normalizeRequiredIdentifier(message.id, fieldName: 'message.id');

    _normalizeRequiredIdentifier(
      message.senderUid,
      fieldName: 'message.senderUid',
    );

    if (message.conversationId != session.conversationId) {
      throw StateError('Retry message belongs to another conversation.');
    }

    if (message.senderUid != session.authenticatedUid) {
      throw StateError(
        'Only the original Firebase UID sender may retry this message.',
      );
    }
  }

  static void _validatePersistedIdentity({
    required MessageEntity expected,
    required MessageEntity persisted,
  }) {
    if (persisted.id != expected.id) {
      throw StateError('Retry persistence changed the canonical message ID.');
    }

    if (persisted.conversationId != expected.conversationId) {
      throw StateError(
        'Retry persistence changed the canonical conversation ID.',
      );
    }

    if (persisted.senderUid != expected.senderUid) {
      throw StateError(
        'Retry persistence changed the canonical sender Firebase UID.',
      );
    }

    if (persisted.type != expected.type) {
      throw StateError(
        'Retry persistence changed the canonical durable message type.',
      );
    }
  }

  static MessageStatus _acceptedStatus(MessageStatus status) {
    switch (status) {
      case MessageStatus.sent:
      case MessageStatus.delivered:
      case MessageStatus.read:
        return status;

      case MessageStatus.queued:
      case MessageStatus.sending:
      case MessageStatus.failed:
        return MessageStatus.sent;
    }
  }

  static bool _isDurablyAccepted(MessageStatus status) {
    switch (status) {
      case MessageStatus.sent:
      case MessageStatus.delivered:
      case MessageStatus.read:
        return true;

      case MessageStatus.queued:
      case MessageStatus.sending:
      case MessageStatus.failed:
        return false;
    }
  }

  void _throwIfCancelled(String messageId) {
    if (_cancelledMessageIds.contains(messageId)) {
      throw StateError('Retry cancelled for message $messageId.');
    }
  }

  void _assertGeneration(int generation) {
    if (!_isGenerationCurrent(generation)) {
      throw StateError(
        'MessageRetryEngine operation belongs to a stale session.',
      );
    }
  }

  bool _isGenerationCurrent(int generation) {
    return !_disposed && _initialized && generation == _sessionGeneration;
  }

  /// Resets active retry-session state while keeping the engine reusable.
  Future<void> reset() async {
    _ensureNotDisposed();

    ++_sessionGeneration;

    _initialized = false;
    _authenticatedUid = null;
    _conversationId = null;

    cancelAll();

    _activeRetries.clear();
    _attemptsByMessageId.clear();
    _cancelledMessageIds.clear();
  }

  /// Permanently disposes this retry engine.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    ++_sessionGeneration;

    _initialized = false;
    _authenticatedUid = null;
    _conversationId = null;

    for (final Timer timer in _backoffTimers.values) {
      timer.cancel();
    }

    _backoffTimers.clear();

    final List<MapEntry<String, Completer<void>>> pending = _backoffCompleters
        .entries
        .toList(growable: false);

    _backoffCompleters.clear();

    for (final MapEntry<String, Completer<void>> entry in pending) {
      if (!entry.value.isCompleted) {
        entry.value.completeError(
          StateError('MessageRetryEngine disposed during retry.'),
        );
      }
    }

    _activeRetries.clear();
    _attemptsByMessageId.clear();
    _cancelledMessageIds.clear();

    _disposed = true;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError(
        'MessageRetryEngine has already been disposed and cannot be reused.',
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

  static int _validateMaxAttempts(int value) {
    if (value < 1 || value > 10) {
      throw ArgumentError.value(
        value,
        'maxAttempts',
        'maxAttempts must be between 1 and 10.',
      );
    }

    return value;
  }

  static Duration _validateInitialBackoff(Duration value) {
    if (value <= Duration.zero || value > const Duration(minutes: 1)) {
      throw ArgumentError.value(
        value,
        'initialBackoff',
        'initialBackoff must be greater than zero and at most 1 minute.',
      );
    }

    return value;
  }

  static Duration _validateMaxBackoff({
    required Duration initialBackoff,
    required Duration maxBackoff,
  }) {
    if (maxBackoff < initialBackoff ||
        maxBackoff > const Duration(minutes: 5)) {
      throw ArgumentError.value(
        maxBackoff,
        'maxBackoff',
        'maxBackoff must be >= initialBackoff and at most 5 minutes.',
      );
    }

    return maxBackoff;
  }

  static int _validateRememberedMessageLimit(int value) {
    if (value < 32 || value > 4096) {
      throw ArgumentError.value(
        value,
        'rememberedMessageLimit',
        'rememberedMessageLimit must be between 32 and 4096.',
      );
    }

    return value;
  }
}

final class _RetrySession {
  const _RetrySession({
    required this.authenticatedUid,
    required this.conversationId,
    required this.generation,
  });

  final String authenticatedUid;
  final String conversationId;
  final int generation;
}

// ============================================================================
// END OF FILE: lib/features/message/engine/message_retry_engine.dart
// ============================================================================
