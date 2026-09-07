// ============================================================================
// JR CALL
// File: jr_message_engine.dart
// Location: lib/features/message/engine/jr_message_engine.dart
// Description:
// Top-level production Message Engine orchestrator.
//
// Responsibilities:
// - Coordinates Message Sender / Receiver / Sync / Delivery / Read / Retry.
// - Owns the active authenticated conversation context.
// - Exposes the canonical synchronized message timeline.
// - Guards authentication/session/conversation lifecycle.
// - Rejects stale lifecycle operations.
// - Provides high-level send/retry/delivery/read/pagination commands.
// - Safely resets and disposes all owned Message Engine components.
//
// Important:
// - Firebase UID is the canonical internal user identity.
// - This file does NOT directly access Firestore or Firebase Storage.
// - This file does NOT implement authentication credential creation.
// - This file does NOT contain Call Engine / WebRTC signaling logic.
// ============================================================================

import 'dart:async';

import '../data/message_entity.dart';
import 'message_delivery_engine.dart';
import 'message_read_engine.dart';
import 'message_receiver.dart';
import 'message_retry_engine.dart';
import 'message_sender.dart';
import 'message_sync_engine.dart';

/// Lifecycle state of the top-level JR CALL Message Engine.
enum JRMessageEngineState {
  uninitialized,
  initializing,
  ready,
  resetting,
  disposed,
}

/// Stable top-level orchestrator for one active JR CALL message conversation.
///
/// All lower-level components are injected so this class never duplicates
/// Firestore, Storage, authentication, cache, or realtime implementation.
final class JRMessageEngine {
  factory JRMessageEngine({
    required MessageSender sender,
    required MessageReceiver receiver,
    required MessageSyncEngine syncEngine,
    required MessageDeliveryEngine deliveryEngine,
    required MessageReadEngine readEngine,
    required MessageRetryEngine retryEngine,
  }) {
    return JRMessageEngine._(
      sender,
      receiver,
      syncEngine,
      deliveryEngine,
      readEngine,
      retryEngine,
    );
  }

  JRMessageEngine._(
    this._sender,
    this._receiver,
    this._syncEngine,
    this._deliveryEngine,
    this._readEngine,
    this._retryEngine,
  );

  final MessageSender _sender;
  final MessageReceiver _receiver;
  final MessageSyncEngine _syncEngine;
  final MessageDeliveryEngine _deliveryEngine;
  final MessageReadEngine _readEngine;
  final MessageRetryEngine _retryEngine;

  final StreamController<JRMessageEngineState> _stateController =
      StreamController<JRMessageEngineState>.broadcast(sync: true);

  JRMessageEngineState _state = JRMessageEngineState.uninitialized;

  String? _authenticatedUid;
  String? _conversationId;

  int _sessionGeneration = 0;

  Future<void> _lifecycleTail = Future<void>.value();

  /// Current engine lifecycle state.
  JRMessageEngineState get state => _state;

  /// Emits Message Engine lifecycle changes.
  Stream<JRMessageEngineState> get states => _stateController.stream;

  /// True only when the engine has a valid active conversation session.
  bool get isReady => _state == JRMessageEngineState.ready;

  /// True after permanent disposal.
  bool get isDisposed => _state == JRMessageEngineState.disposed;

  /// Current authenticated Firebase UID.
  ///
  /// Returns null before initialization or after reset.
  String? get authenticatedUid => _authenticatedUid;

  /// Current canonical conversation ID.
  ///
  /// Returns null before initialization or after reset.
  String? get conversationId => _conversationId;

  /// Canonical synchronized durable-message timeline.
  ///
  /// MessageSyncEngine owns reconciliation, ordering, optimistic/server
  /// merging, deduplication and pagination merging.
  Stream<List<MessageEntity>> get messages => _syncEngine.messages;

  /// Latest immutable synchronized message snapshot.
  List<MessageEntity> get currentMessages => _syncEngine.currentMessages;

  /// Whether older durable messages can still be loaded.
  bool get hasMoreMessages => _syncEngine.hasMore;

  /// Whether an older-page request is currently active.
  bool get isLoadingOlderMessages => _syncEngine.isLoadingOlder;

  /// Initializes this Message Engine for one authenticated conversation.
  ///
  /// [authenticatedUid] MUST be Firebase Auth UID.
  /// Public JR CALL IDs, usernames, phone numbers and emails must never be
  /// supplied here as internal identity.
  ///
  /// Reinitializing with the same active session is idempotent.
  /// Reinitializing with a different session first resets the previous one.
  Future<void> initialize({
    required String authenticatedUid,
    required String conversationId,
  }) {
    return _enqueueLifecycle(() async {
      _ensureNotDisposed();

      final String uid = _normalizeRequiredIdentifier(
        authenticatedUid,
        fieldName: 'authenticatedUid',
      );
      final String conversation = _normalizeRequiredIdentifier(
        conversationId,
        fieldName: 'conversationId',
      );

      if (_state == JRMessageEngineState.ready &&
          _authenticatedUid == uid &&
          _conversationId == conversation) {
        return;
      }

      if (_state == JRMessageEngineState.ready ||
          _authenticatedUid != null ||
          _conversationId != null) {
        await _resetInternal();
      }

      final int generation = ++_sessionGeneration;

      _setState(JRMessageEngineState.initializing);

      _authenticatedUid = uid;
      _conversationId = conversation;

      try {
        // Sync is initialized first so optimistic/incoming mutations always
        // have an authoritative reconciliation target.
        await _syncEngine.initialize(
          authenticatedUid: uid,
          conversationId: conversation,
        );

        _assertCurrentSession(
          generation: generation,
          uid: uid,
          conversationId: conversation,
        );

        await _sender.initialize(
          authenticatedUid: uid,
          conversationId: conversation,
        );

        _assertCurrentSession(
          generation: generation,
          uid: uid,
          conversationId: conversation,
        );

        await _receiver.initialize(
          authenticatedUid: uid,
          conversationId: conversation,
        );

        _assertCurrentSession(
          generation: generation,
          uid: uid,
          conversationId: conversation,
        );

        await _deliveryEngine.initialize(
          authenticatedUid: uid,
          conversationId: conversation,
        );

        _assertCurrentSession(
          generation: generation,
          uid: uid,
          conversationId: conversation,
        );

        await _readEngine.initialize(
          authenticatedUid: uid,
          conversationId: conversation,
        );

        _assertCurrentSession(
          generation: generation,
          uid: uid,
          conversationId: conversation,
        );

        await _retryEngine.initialize(
          authenticatedUid: uid,
          conversationId: conversation,
        );

        _assertCurrentSession(
          generation: generation,
          uid: uid,
          conversationId: conversation,
        );

        _setState(JRMessageEngineState.ready);
      } catch (error, stackTrace) {
        await _cleanupFailedInitialization();

        if (_state != JRMessageEngineState.disposed) {
          _authenticatedUid = null;
          _conversationId = null;
          _setState(JRMessageEngineState.uninitialized);
        }

        Error.throwWithStackTrace(error, stackTrace);
      }
    });
  }

  /// Sends one durable message through MessageSender.
  ///
  /// MessageSender owns:
  /// queued -> sending -> sent,
  /// stable message ID creation,
  /// outgoing validation,
  /// optimistic creation,
  /// attachment coordination,
  /// duplicate-send protection.
  Future<MessageEntity> send(MessageSendRequest request) async {
    final _ActiveSession session = _requireActiveSession();

    if (request.conversationId != session.conversationId) {
      throw StateError(
        'Message request conversation does not match the active '
        'Message Engine conversation.',
      );
    }

    return _sender.send(
      authenticatedUid: session.authenticatedUid,
      conversationId: session.conversationId,
      request: request,
    );
  }

  /// Retries a previously failed durable message using its existing
  /// canonical message ID.
  ///
  /// RetryEngine must never create a replacement message ID.
  Future<MessageEntity> retry(String messageId) async {
    final _ActiveSession session = _requireActiveSession();

    final String normalizedMessageId = _normalizeRequiredIdentifier(
      messageId,
      fieldName: 'messageId',
    );

    return _retryEngine.retry(
      authenticatedUid: session.authenticatedUid,
      conversationId: session.conversationId,
      messageId: normalizedMessageId,
    );
  }

  /// Acknowledges actual recipient-side delivery.
  ///
  /// This must only be called when the Message Delivery contract has real
  /// evidence that the authenticated recipient received the message.
  ///
  /// No timer-derived or fabricated delivery acknowledgement is allowed.
  Future<void> markDelivered(Iterable<String> messageIds) async {
    final _ActiveSession session = _requireActiveSession();
    final List<String> ids = _normalizeMessageIds(messageIds);

    if (ids.isEmpty) {
      return;
    }

    await _deliveryEngine.markDelivered(
      authenticatedUid: session.authenticatedUid,
      conversationId: session.conversationId,
      messageIds: ids,
    );
  }

  /// Marks messages as read after actual UI visibility/read confirmation.
  ///
  /// Listener receipt alone must not be treated as read.
  Future<void> markRead(Iterable<String> messageIds) async {
    final _ActiveSession session = _requireActiveSession();
    final List<String> ids = _normalizeMessageIds(messageIds);

    if (ids.isEmpty) {
      return;
    }

    await _readEngine.markRead(
      authenticatedUid: session.authenticatedUid,
      conversationId: session.conversationId,
      messageIds: ids,
    );
  }

  /// Loads the next older durable-message page.
  ///
  /// MessageSyncEngine owns pagination boundaries, deterministic ordering
  /// and duplicate reconciliation.
  Future<void> loadOlderMessages() async {
    final _ActiveSession session = _requireActiveSession();

    if (!_syncEngine.hasMore || _syncEngine.isLoadingOlder) {
      return;
    }

    await _syncEngine.loadOlder(
      authenticatedUid: session.authenticatedUid,
      conversationId: session.conversationId,
    );
  }

  /// Requests explicit local/server reconciliation for the active session.
  ///
  /// Useful after connectivity restoration or an intentional foreground
  /// refresh. Duplicate messages must still be eliminated by canonical ID.
  Future<void> synchronize() async {
    final _ActiveSession session = _requireActiveSession();

    await _syncEngine.synchronize(
      authenticatedUid: session.authenticatedUid,
      conversationId: session.conversationId,
    );
  }

  /// Resets the active conversation while keeping this engine reusable.
  ///
  /// All per-conversation subscriptions, timers, pending lifecycle state and
  /// retry work owned by lower-level engines must be released by their reset
  /// implementations.
  Future<void> reset() {
    return _enqueueLifecycle(() async {
      _ensureNotDisposed();
      await _resetInternal();
    });
  }

  /// Permanently disposes this Message Engine and all components it owns.
  ///
  /// After disposal this instance cannot be initialized again.
  Future<void> dispose() {
    return _enqueueLifecycle(() async {
      if (_state == JRMessageEngineState.disposed) {
        return;
      }

      ++_sessionGeneration;
      _setState(JRMessageEngineState.resetting);

      Object? firstError;
      StackTrace? firstStackTrace;

      Future<void> disposeComponent(Future<void> Function() operation) async {
        try {
          await operation();
        } catch (error, stackTrace) {
          firstError ??= error;
          firstStackTrace ??= stackTrace;
        }
      }

      // Reverse dependency/lifecycle order.
      await disposeComponent(_retryEngine.dispose);
      await disposeComponent(_readEngine.dispose);
      await disposeComponent(_deliveryEngine.dispose);
      await disposeComponent(_receiver.dispose);
      await disposeComponent(_sender.dispose);
      await disposeComponent(_syncEngine.dispose);

      _authenticatedUid = null;
      _conversationId = null;

      _setState(JRMessageEngineState.disposed);

      await _stateController.close();

      if (firstError != null && firstStackTrace != null) {
        Error.throwWithStackTrace(firstError!, firstStackTrace!);
      }
    });
  }

  Future<void> _resetInternal() async {
    if (_state == JRMessageEngineState.disposed) {
      return;
    }

    ++_sessionGeneration;

    if (_state == JRMessageEngineState.uninitialized &&
        _authenticatedUid == null &&
        _conversationId == null) {
      return;
    }

    _setState(JRMessageEngineState.resetting);

    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> resetComponent(Future<void> Function() operation) async {
      try {
        await operation();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    // Reverse initialization order.
    await resetComponent(_retryEngine.reset);
    await resetComponent(_readEngine.reset);
    await resetComponent(_deliveryEngine.reset);
    await resetComponent(_receiver.reset);
    await resetComponent(_sender.reset);
    await resetComponent(_syncEngine.reset);

    _authenticatedUid = null;
    _conversationId = null;

    _setState(JRMessageEngineState.uninitialized);

    if (firstError != null && firstStackTrace != null) {
      Error.throwWithStackTrace(firstError!, firstStackTrace!);
    }
  }

  Future<void> _cleanupFailedInitialization() async {
    Object? firstCleanupError;
    StackTrace? firstCleanupStackTrace;

    Future<void> resetComponent(Future<void> Function() operation) async {
      try {
        await operation();
      } catch (error, stackTrace) {
        firstCleanupError ??= error;
        firstCleanupStackTrace ??= stackTrace;
      }
    }

    await resetComponent(_retryEngine.reset);
    await resetComponent(_readEngine.reset);
    await resetComponent(_deliveryEngine.reset);
    await resetComponent(_receiver.reset);
    await resetComponent(_sender.reset);
    await resetComponent(_syncEngine.reset);

    // Cleanup errors are intentionally not allowed to replace the original
    // initialization failure. They remain isolated to component reset logic.
    if (firstCleanupError != null && firstCleanupStackTrace != null) {
      // The primary initialization exception remains authoritative.
      // Lower-level components must expose their own debug diagnostics.
    }
  }

  Future<void> _enqueueLifecycle(Future<void> Function() operation) {
    final Completer<void> completer = Completer<void>();
    final Future<void> previous = _lifecycleTail;

    _lifecycleTail = completer.future.then<void>((_) {}, onError: (_) {});

    () async {
      try {
        try {
          await previous;
        } catch (_) {
          // A previous lifecycle failure must not permanently block future
          // reset/dispose recovery operations.
        }

        await operation();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }();

    return completer.future;
  }

  _ActiveSession _requireActiveSession() {
    _ensureNotDisposed();

    if (_state != JRMessageEngineState.ready) {
      throw StateError(
        'JRMessageEngine is not ready. Initialize an authenticated '
        'conversation before performing message operations.',
      );
    }

    final String? uid = _authenticatedUid;
    final String? conversation = _conversationId;

    if (uid == null ||
        uid.isEmpty ||
        conversation == null ||
        conversation.isEmpty) {
      throw StateError(
        'JRMessageEngine has no valid authenticated conversation session.',
      );
    }

    return _ActiveSession(authenticatedUid: uid, conversationId: conversation);
  }

  void _assertCurrentSession({
    required int generation,
    required String uid,
    required String conversationId,
  }) {
    if (_state == JRMessageEngineState.disposed ||
        generation != _sessionGeneration ||
        _authenticatedUid != uid ||
        _conversationId != conversationId) {
      throw StateError(
        'JRMessageEngine initialization became stale before completion.',
      );
    }
  }

  void _ensureNotDisposed() {
    if (_state == JRMessageEngineState.disposed) {
      throw StateError(
        'JRMessageEngine has already been disposed and cannot be reused.',
      );
    }
  }

  void _setState(JRMessageEngineState nextState) {
    if (_state == nextState) {
      return;
    }

    _state = nextState;

    if (!_stateController.isClosed) {
      _stateController.add(nextState);
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

  static List<String> _normalizeMessageIds(Iterable<String> values) {
    final Set<String> unique = <String>{};

    for (final String value in values) {
      final String normalized = value.trim();

      if (normalized.isNotEmpty) {
        unique.add(normalized);
      }
    }

    return List<String>.unmodifiable(unique);
  }
}

final class _ActiveSession {
  const _ActiveSession({
    required this.authenticatedUid,
    required this.conversationId,
  });

  final String authenticatedUid;
  final String conversationId;
}

// ============================================================================
// END OF FILE: lib/features/message/engine/jr_message_engine.dart
// ============================================================================
