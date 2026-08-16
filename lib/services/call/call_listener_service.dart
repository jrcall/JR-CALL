// ===============================================================
// JR CALL
// File: call_listener_service.dart
// Location: lib/services/call/call_listener_service.dart
// Fixes: BUG 07, BUG 08
// Production-safe replacement
// Existing APIs preserved
//
// PRODUCTION CONTRACT:
// - One active Firestore call-document listener only.
// - SignalingService remains the Firestore access owner.
// - ICE upload/remote ICE application remains IceManager-owned.
// - Ordered status / SDP / connection events.
// - Terminal status is never lost during session shutdown.
// - Stale terminal events cannot leak into a later call.
// - Reconnect uses bounded exponential backoff.
// - Duplicate Firestore values are filtered.
// - Session generation prevents stale async callbacks.
// - No WebRTC / signaling writes / recovery ownership duplicated.
// ===============================================================

import 'dart:async';
import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'signaling_service.dart';

// ===============================================================
// FIRESTORE CALL FIELD CONSTANTS
// ===============================================================

abstract final class CallFields {
  static const String status = 'status';
  static const String offer = 'offer';
  static const String answer = 'answer';

  static const String connectionState = 'connectionState';
  static const String iceConnectionState = 'iceConnectionState';
  static const String signalingState = 'signalingState';
  static const String iceGatheringState = 'iceGatheringState';

  static const String networkRecovered = 'networkRecovered';
  static const String iceRestartCount = 'iceRestartCount';

  static const String sdp = 'sdp';
  static const String type = 'type';
}

// ===============================================================
// STANDARD CALL STATUS VALUES
// ===============================================================

abstract final class CallStatusValues {
  static const String calling = 'calling';
  static const String ringing = 'ringing';
  static const String connecting = 'connecting';
  static const String connected = 'connected';
  static const String reconnecting = 'reconnecting';

  static const String ended = 'ended';
  static const String rejected = 'rejected';
  static const String declined = 'declined';
  static const String cancelled = 'cancelled';
  static const String failed = 'failed';
  static const String timeout = 'timeout';

  static bool isTerminal(String status) {
    switch (status.trim().toLowerCase()) {
      case ended:
      case rejected:
      case declined:
      case cancelled:
      case failed:
      case timeout:
        return true;

      default:
        return false;
    }
  }
}

// ===============================================================
// INTERNAL EVENT TYPES
// ===============================================================

enum _CallListenerEventType {
  status,
  offer,
  answer,
  connectionState,
  iceConnectionState,
  signalingState,
  iceGatheringState,
  networkRecovered,
  iceRestart,
  callEnded,
  callDeleted,
}

// ===============================================================
// INTERNAL ORDERED EVENT
// ===============================================================

class _CallListenerEvent {
  const _CallListenerEvent({
    required this.type,
    required this.sessionToken,
    required this.callId,
    this.payload,
    this.deliverAfterTermination = false,
  });

  final _CallListenerEventType type;
  final int sessionToken;
  final String callId;
  final Object? payload;

  /// Used only for events already produced by the exact session
  /// while that session is synchronously transitioning to terminal.
  final bool deliverAfterTermination;
}

// ===============================================================
// CALL LISTENER SERVICE
// ===============================================================

class CallListenerService {
  CallListenerService._();

  static final CallListenerService instance = CallListenerService._();

  final SignalingService _signalingService = SignalingService.instance;

  // =============================================================
  // CONFIGURATION
  // =============================================================

  static const int _maximumReconnectAttempts = 5;

  static const Duration _initialReconnectDelay = Duration(seconds: 2);

  static const Duration _maximumReconnectDelay = Duration(seconds: 30);

  // =============================================================
  // ACTIVE SESSION
  // =============================================================

  String? currentCallId;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  currentSubscription;

  bool isListening = false;

  bool _isDisposed = false;
  bool _isPaused = false;
  bool _isProcessingQueue = false;
  bool _isReconnectScheduled = false;
  bool _isReportingError = false;

  int _sessionGenerationId = 0;
  int _reconnectAttempts = 0;

  Timer? _reconnectTimer;

  /// Identity of the most recently synchronously terminated session.
  ///
  /// Allows terminal events already queued for that exact call/session
  /// to finish dispatching while preventing them from leaking into a
  /// later call.
  int? _terminatedSessionToken;
  String? _terminatedCallId;

  // =============================================================
  // DETERMINISTIC EVENT QUEUE
  // =============================================================

  final Queue<_CallListenerEvent> _eventQueue = Queue<_CallListenerEvent>();

  // =============================================================
  // LAST EMITTED VALUES
  // =============================================================

  String? lastStatus;

  Map<String, dynamic>? lastOffer;
  Map<String, dynamic>? lastAnswer;

  String? _lastConnectionState;
  String? _lastIceConnectionState;
  String? _lastSignalingState;
  String? _lastIceGatheringState;

  bool _lastNetworkRecovered = false;
  int _lastIceRestartCount = 0;

  // =============================================================
  // PUBLIC CALLBACKS
  // =============================================================

  ValueChanged<String>? onStatusChanged;

  ValueChanged<Map<String, dynamic>>? onOfferReceived;
  ValueChanged<Map<String, dynamic>>? onAnswerReceived;

  VoidCallback? onCallEnded;
  VoidCallback? onCallDeleted;

  ValueChanged<String>? onConnectionStateChanged;
  ValueChanged<String>? onIceConnectionStateChanged;
  ValueChanged<String>? onSignalingStateChanged;
  ValueChanged<String>? onIceGatheringStateChanged;

  VoidCallback? onNetworkRecovered;
  VoidCallback? onIceRestart;

  ValueChanged<Object>? onError;

  // =============================================================
  // PUBLIC STATE
  // =============================================================

  bool get isDisposed => _isDisposed;
  bool get isPaused => _isPaused;

  int get reconnectAttempts => _reconnectAttempts;

  // =============================================================
  // INITIALIZATION
  // =============================================================

  void initialize() {
    if (!_isDisposed) {
      return;
    }

    _isDisposed = false;
    _isPaused = false;
    _isReconnectScheduled = false;
    _reconnectAttempts = 0;

    _terminatedSessionToken = null;
    _terminatedCallId = null;
  }

  // =============================================================
  // LISTENER LIFECYCLE
  // =============================================================

  void startListening(String callId) {
    final String normalizedCallId = callId.trim();

    if (_isDisposed) {
      _reportError(
        StateError(
          'CallListenerService is disposed. '
          'Call initialize() before reusing it.',
        ),
        source: 'startListening',
      );
      return;
    }

    if (normalizedCallId.isEmpty) {
      _reportError(
        ArgumentError.value(callId, 'callId', 'Call ID cannot be empty.'),
        source: 'startListening',
      );
      return;
    }

    if (isListening &&
        currentCallId == normalizedCallId &&
        currentSubscription != null) {
      return;
    }

    _stopActiveSession(clearQueue: true, clearCachedValues: true);

    final int sessionToken = ++_sessionGenerationId;

    currentCallId = normalizedCallId;

    isListening = true;
    _isPaused = false;

    _reconnectAttempts = 0;
    _isReconnectScheduled = false;

    _terminatedSessionToken = null;
    _terminatedCallId = null;

    _subscribeToCallDocument(
      callId: normalizedCallId,
      sessionToken: sessionToken,
    );
  }

  void restartListening(String callId) {
    if (_isDisposed) {
      return;
    }

    stopListening();
    startListening(callId);
  }

  void stopListening() {
    _stopActiveSession(clearQueue: true, clearCachedValues: true);
  }

  void pauseListening() {
    if (_isDisposed || !isListening || _isPaused) {
      return;
    }

    _isPaused = true;

    _cancelReconnectTimer(resetAttempts: false);

    final subscription = currentSubscription;

    if (subscription != null && !subscription.isPaused) {
      subscription.pause();
    }
  }

  void resumeListening() {
    if (_isDisposed || !isListening || !_isPaused) {
      return;
    }

    _isPaused = false;

    final subscription = currentSubscription;

    if (subscription != null && subscription.isPaused) {
      subscription.resume();
      return;
    }

    final String? callId = currentCallId;

    if (callId == null) {
      return;
    }

    _subscribeToCallDocument(
      callId: callId,
      sessionToken: _sessionGenerationId,
    );
  }

  bool _isSessionActive({required String callId, required int sessionToken}) {
    return !_isDisposed &&
        isListening &&
        !_isPaused &&
        currentCallId == callId &&
        _sessionGenerationId == sessionToken;
  }

  // =============================================================
  // MAIN FIRESTORE SUBSCRIPTION
  // =============================================================

  void _subscribeToCallDocument({
    required String callId,
    required int sessionToken,
  }) {
    if (!_isSessionActive(callId: callId, sessionToken: sessionToken)) {
      return;
    }

    final previousSubscription = currentSubscription;

    currentSubscription = null;

    if (previousSubscription != null) {
      unawaited(previousSubscription.cancel());
    }

    currentSubscription = listenCall(callId).listen(
      (DocumentSnapshot<Map<String, dynamic>> snapshot) {
        if (!_isSessionActive(callId: callId, sessionToken: sessionToken)) {
          return;
        }

        _markListenerHealthy();

        try {
          _processSnapshot(
            snapshot: snapshot,
            callId: callId,
            sessionToken: sessionToken,
          );
        } catch (error, stackTrace) {
          _reportError(
            error,
            stackTrace: stackTrace,
            source: 'snapshot processing',
          );
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_isSessionActive(callId: callId, sessionToken: sessionToken)) {
          return;
        }

        _reportError(
          error,
          stackTrace: stackTrace,
          source: 'Firestore call stream',
        );

        _scheduleReconnect(callId: callId, sessionToken: sessionToken);
      },
      onDone: () {
        if (!_isSessionActive(callId: callId, sessionToken: sessionToken)) {
          return;
        }

        _scheduleReconnect(callId: callId, sessionToken: sessionToken);
      },
      cancelOnError: true,
    );
  }

  // =============================================================
  // SNAPSHOT PROCESSING
  // =============================================================

  void _processSnapshot({
    required DocumentSnapshot<Map<String, dynamic>> snapshot,
    required String callId,
    required int sessionToken,
  }) {
    if (!snapshot.exists) {
      _handleDeletedCall(callId: callId, sessionToken: sessionToken);
      return;
    }

    final Map<String, dynamic>? data = snapshot.data();

    if (data == null) {
      return;
    }

    final String? rawStatus = _readNonEmptyString(data[CallFields.status]);

    final String? status = rawStatus?.toLowerCase();

    final bool isTerminal =
        status != null && CallStatusValues.isTerminal(status);

    if (status != null && status != lastStatus) {
      lastStatus = status;

      _enqueueEvent(
        _CallListenerEvent(
          type: _CallListenerEventType.status,
          payload: status,
          sessionToken: sessionToken,
          callId: callId,

          // Without this, session invalidation during terminal handling
          // could discard the terminal status before CallService/UI sees it.
          deliverAfterTermination: isTerminal,
        ),
      );
    }

    if (isTerminal) {
      _handleTerminalCall(callId: callId, sessionToken: sessionToken);
      return;
    }

    _processSessionDescription(
      rawDescription: data[CallFields.offer],
      previousDescription: lastOffer,
      expectedType: 'offer',
      updateCache: (Map<String, dynamic> description) {
        lastOffer = description;
      },
      eventType: _CallListenerEventType.offer,
      callId: callId,
      sessionToken: sessionToken,
    );

    _processSessionDescription(
      rawDescription: data[CallFields.answer],
      previousDescription: lastAnswer,
      expectedType: 'answer',
      updateCache: (Map<String, dynamic> description) {
        lastAnswer = description;
      },
      eventType: _CallListenerEventType.answer,
      callId: callId,
      sessionToken: sessionToken,
    );

    _processStringState(
      rawValue: data[CallFields.connectionState],
      previousValue: _lastConnectionState,
      updateCache: (String value) {
        _lastConnectionState = value;
      },
      eventType: _CallListenerEventType.connectionState,
      callId: callId,
      sessionToken: sessionToken,
    );

    _processStringState(
      rawValue: data[CallFields.iceConnectionState],
      previousValue: _lastIceConnectionState,
      updateCache: (String value) {
        _lastIceConnectionState = value;
      },
      eventType: _CallListenerEventType.iceConnectionState,
      callId: callId,
      sessionToken: sessionToken,
    );

    _processStringState(
      rawValue: data[CallFields.signalingState],
      previousValue: _lastSignalingState,
      updateCache: (String value) {
        _lastSignalingState = value;
      },
      eventType: _CallListenerEventType.signalingState,
      callId: callId,
      sessionToken: sessionToken,
    );

    _processStringState(
      rawValue: data[CallFields.iceGatheringState],
      previousValue: _lastIceGatheringState,
      updateCache: (String value) {
        _lastIceGatheringState = value;
      },
      eventType: _CallListenerEventType.iceGatheringState,
      callId: callId,
      sessionToken: sessionToken,
    );

    _processNetworkRecovered(
      data[CallFields.networkRecovered],
      callId: callId,
      sessionToken: sessionToken,
    );

    _processIceRestartCount(
      data[CallFields.iceRestartCount],
      callId: callId,
      sessionToken: sessionToken,
    );
  }

  // =============================================================
  // FIRESTORE VALUE PROCESSING
  // =============================================================

  void _processSessionDescription({
    required Object? rawDescription,
    required Map<String, dynamic>? previousDescription,
    required String expectedType,
    required ValueChanged<Map<String, dynamic>> updateCache,
    required _CallListenerEventType eventType,
    required String callId,
    required int sessionToken,
  }) {
    final Map<String, dynamic>? description = _normalizeMap(rawDescription);

    if (description == null ||
        !_isValidSessionDescription(description, expectedType: expectedType) ||
        _sessionDescriptionsEqual(previousDescription, description)) {
      return;
    }

    final String sdp = _readNonEmptyString(description[CallFields.sdp])!;

    final String type = _readNonEmptyString(
      description[CallFields.type],
    )!.toLowerCase();

    final Map<String, dynamic> immutableDescription =
        Map<String, dynamic>.unmodifiable(<String, dynamic>{
          CallFields.sdp: sdp,
          CallFields.type: type,
        });

    updateCache(immutableDescription);

    _enqueueEvent(
      _CallListenerEvent(
        type: eventType,
        payload: immutableDescription,
        sessionToken: sessionToken,
        callId: callId,
      ),
    );
  }

  void _processStringState({
    required Object? rawValue,
    required String? previousValue,
    required ValueChanged<String> updateCache,
    required _CallListenerEventType eventType,
    required String callId,
    required int sessionToken,
  }) {
    final String? raw = _readNonEmptyString(rawValue);

    if (raw == null) {
      return;
    }

    final String value = raw.toLowerCase();

    if (value == previousValue) {
      return;
    }

    updateCache(value);

    _enqueueEvent(
      _CallListenerEvent(
        type: eventType,
        payload: value,
        sessionToken: sessionToken,
        callId: callId,
      ),
    );
  }

  void _processNetworkRecovered(
    Object? rawValue, {
    required String callId,
    required int sessionToken,
  }) {
    if (rawValue is! bool || rawValue == _lastNetworkRecovered) {
      return;
    }

    _lastNetworkRecovered = rawValue;

    if (!rawValue) {
      return;
    }

    _enqueueEvent(
      _CallListenerEvent(
        type: _CallListenerEventType.networkRecovered,
        sessionToken: sessionToken,
        callId: callId,
      ),
    );
  }

  void _processIceRestartCount(
    Object? rawValue, {
    required String callId,
    required int sessionToken,
  }) {
    final int? restartCount = _readInteger(rawValue);

    if (restartCount == null ||
        restartCount < 0 ||
        restartCount <= _lastIceRestartCount) {
      return;
    }

    final int missedRestartEvents = restartCount - _lastIceRestartCount;

    _lastIceRestartCount = restartCount;

    for (int index = 0; index < missedRestartEvents; index++) {
      _enqueueEvent(
        _CallListenerEvent(
          type: _CallListenerEventType.iceRestart,
          sessionToken: sessionToken,
          callId: callId,
        ),
      );
    }
  }

  // =============================================================
  // TERMINAL / DELETED CALL HANDLING
  // =============================================================

  void _handleTerminalCall({
    required String callId,
    required int sessionToken,
  }) {
    if (!_isSessionActive(callId: callId, sessionToken: sessionToken)) {
      return;
    }

    _enqueueEvent(
      _CallListenerEvent(
        type: _CallListenerEventType.callEnded,
        sessionToken: sessionToken,
        callId: callId,
        deliverAfterTermination: true,
      ),
    );

    _terminateSessionPreservingTerminalEvents(
      callId: callId,
      sessionToken: sessionToken,
    );
  }

  void _handleDeletedCall({required String callId, required int sessionToken}) {
    if (!_isSessionActive(callId: callId, sessionToken: sessionToken)) {
      return;
    }

    _enqueueEvent(
      _CallListenerEvent(
        type: _CallListenerEventType.callDeleted,
        sessionToken: sessionToken,
        callId: callId,
        deliverAfterTermination: true,
      ),
    );

    _enqueueEvent(
      _CallListenerEvent(
        type: _CallListenerEventType.callEnded,
        sessionToken: sessionToken,
        callId: callId,
        deliverAfterTermination: true,
      ),
    );

    _terminateSessionPreservingTerminalEvents(
      callId: callId,
      sessionToken: sessionToken,
    );
  }

  void _terminateSessionPreservingTerminalEvents({
    required String callId,
    required int sessionToken,
  }) {
    _cancelReconnectTimer();

    _terminatedSessionToken = sessionToken;
    _terminatedCallId = callId;

    isListening = false;
    _isPaused = false;

    currentCallId = null;

    final subscription = currentSubscription;

    currentSubscription = null;

    if (subscription != null) {
      unawaited(subscription.cancel());
    }

    // Invalidate every asynchronous Firestore callback from this session.
    _sessionGenerationId++;
  }

  // =============================================================
  // SIGNALING LISTENER RECOVERY
  // =============================================================

  void _scheduleReconnect({required String callId, required int sessionToken}) {
    if (!_isSessionActive(callId: callId, sessionToken: sessionToken) ||
        _isReconnectScheduled) {
      return;
    }

    if (_reconnectAttempts >= _maximumReconnectAttempts) {
      _reportError(
        StateError('Maximum Firestore listener reconnect attempts reached.'),
        source: 'listener recovery',
      );

      stopListening();
      return;
    }

    _reconnectAttempts++;
    _isReconnectScheduled = true;

    final Duration reconnectDelay = _calculateReconnectDelay(
      _reconnectAttempts,
    );

    debugPrint(
      'JR CALL: CallListener reconnect attempt '
      '$_reconnectAttempts/$_maximumReconnectAttempts '
      'in ${reconnectDelay.inSeconds}s.',
    );

    _reconnectTimer?.cancel();

    _reconnectTimer = Timer(reconnectDelay, () {
      _reconnectTimer = null;
      _isReconnectScheduled = false;

      if (!_isSessionActive(callId: callId, sessionToken: sessionToken)) {
        return;
      }

      _subscribeToCallDocument(callId: callId, sessionToken: sessionToken);
    });
  }

  Duration _calculateReconnectDelay(int attempt) {
    int seconds = _initialReconnectDelay.inSeconds;

    for (int index = 1; index < attempt; index++) {
      seconds *= 2;

      if (seconds >= _maximumReconnectDelay.inSeconds) {
        seconds = _maximumReconnectDelay.inSeconds;
        break;
      }
    }

    return Duration(seconds: seconds);
  }

  void _markListenerHealthy() {
    _reconnectAttempts = 0;
    _isReconnectScheduled = false;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _cancelReconnectTimer({bool resetAttempts = true}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    _isReconnectScheduled = false;

    if (resetAttempts) {
      _reconnectAttempts = 0;
    }
  }

  // =============================================================
  // DETERMINISTIC EVENT QUEUE
  // =============================================================

  void _enqueueEvent(_CallListenerEvent event) {
    if (_isDisposed) {
      return;
    }

    _eventQueue.addLast(event);

    if (!_isProcessingQueue) {
      scheduleMicrotask(_processEventQueue);
    }
  }

  void _processEventQueue() {
    if (_isDisposed || _isProcessingQueue) {
      return;
    }

    _isProcessingQueue = true;

    try {
      while (_eventQueue.isNotEmpty && !_isDisposed) {
        final _CallListenerEvent event = _eventQueue.removeFirst();

        if (!_eventCanBeDelivered(event)) {
          continue;
        }

        try {
          _dispatchEvent(event);
        } catch (error, stackTrace) {
          _reportError(error, stackTrace: stackTrace, source: 'event queue');
        }
      }
    } finally {
      _isProcessingQueue = false;

      if (_eventQueue.isNotEmpty && !_isDisposed) {
        scheduleMicrotask(_processEventQueue);
      }
    }
  }

  bool _eventCanBeDelivered(_CallListenerEvent event) {
    if (event.sessionToken == _sessionGenerationId) {
      return true;
    }

    if (!event.deliverAfterTermination) {
      return false;
    }

    return _terminatedSessionToken == event.sessionToken &&
        _terminatedCallId == event.callId;
  }

  void _dispatchEvent(_CallListenerEvent event) {
    switch (event.type) {
      case _CallListenerEventType.status:
        _safeValueCallback(onStatusChanged, event.payload! as String);
        break;

      case _CallListenerEventType.offer:
        _safeValueCallback(
          onOfferReceived,
          event.payload! as Map<String, dynamic>,
        );
        break;

      case _CallListenerEventType.answer:
        _safeValueCallback(
          onAnswerReceived,
          event.payload! as Map<String, dynamic>,
        );
        break;

      case _CallListenerEventType.connectionState:
        _safeValueCallback(onConnectionStateChanged, event.payload! as String);
        break;

      case _CallListenerEventType.iceConnectionState:
        _safeValueCallback(
          onIceConnectionStateChanged,
          event.payload! as String,
        );
        break;

      case _CallListenerEventType.signalingState:
        _safeValueCallback(onSignalingStateChanged, event.payload! as String);
        break;

      case _CallListenerEventType.iceGatheringState:
        _safeValueCallback(
          onIceGatheringStateChanged,
          event.payload! as String,
        );
        break;

      case _CallListenerEventType.networkRecovered:
        _safeCallback(onNetworkRecovered);
        break;

      case _CallListenerEventType.iceRestart:
        _safeCallback(onIceRestart);
        break;

      case _CallListenerEventType.callEnded:
        _safeCallback(onCallEnded);
        break;

      case _CallListenerEventType.callDeleted:
        _safeCallback(onCallDeleted);
        break;
    }
  }

  // =============================================================
  // PUBLIC FIRESTORE STREAMS
  // =============================================================

  Stream<DocumentSnapshot<Map<String, dynamic>>> listenCall(String callId) {
    final String normalizedCallId = callId.trim();

    if (normalizedCallId.isEmpty) {
      return Stream<DocumentSnapshot<Map<String, dynamic>>>.error(
        ArgumentError.value(callId, 'callId', 'Call ID cannot be empty.'),
      );
    }

    return _signalingService.listenCall(normalizedCallId);
  }

  Stream<String> listenCallStatus(String callId) {
    return listenCall(callId).map<String>((
      DocumentSnapshot<Map<String, dynamic>> snapshot,
    ) {
      if (!snapshot.exists) {
        return CallStatusValues.ended;
      }

      return _readNonEmptyString(
            snapshot.data()?[CallFields.status],
          )?.toLowerCase() ??
          CallStatusValues.ended;
    }).distinct();
  }

  Stream<Map<String, dynamic>?> listenOffer(String callId) {
    return listenCall(callId)
        .map<Map<String, dynamic>?>((
          DocumentSnapshot<Map<String, dynamic>> snapshot,
        ) {
          if (!snapshot.exists) {
            return null;
          }

          final Map<String, dynamic>? offer = _normalizeMap(
            snapshot.data()?[CallFields.offer],
          );

          if (offer == null ||
              !_isValidSessionDescription(offer, expectedType: 'offer')) {
            return null;
          }

          return _normalizedImmutableDescription(offer);
        })
        .distinct(_nullableSessionDescriptionsEqual);
  }

  Stream<Map<String, dynamic>?> listenAnswer(String callId) {
    return listenCall(callId)
        .map<Map<String, dynamic>?>((
          DocumentSnapshot<Map<String, dynamic>> snapshot,
        ) {
          if (!snapshot.exists) {
            return null;
          }

          final Map<String, dynamic>? answer = _normalizeMap(
            snapshot.data()?[CallFields.answer],
          );

          if (answer == null ||
              !_isValidSessionDescription(answer, expectedType: 'answer')) {
            return null;
          }

          return _normalizedImmutableDescription(answer);
        })
        .distinct(_nullableSessionDescriptionsEqual);
  }

  // =============================================================
  // SAFE CALLBACK WRAPPERS
  // =============================================================

  void _safeCallback(VoidCallback? callback) {
    if (callback == null || _isDisposed) {
      return;
    }

    try {
      callback();
    } catch (error, stackTrace) {
      _reportError(error, stackTrace: stackTrace, source: 'callback');
    }
  }

  void _safeValueCallback<T>(ValueChanged<T>? callback, T value) {
    if (callback == null || _isDisposed) {
      return;
    }

    try {
      callback(value);
    } catch (error, stackTrace) {
      _reportError(error, stackTrace: stackTrace, source: 'value callback');
    }
  }

  void _reportError(
    Object error, {
    StackTrace? stackTrace,
    String source = 'CallListenerService',
  }) {
    debugPrint(
      'JR CALL [CallListenerService/$source] '
      'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL [CallListenerService/$source]',
        stackTrace: stackTrace,
      );
    }

    if (_isDisposed || onError == null || _isReportingError) {
      return;
    }

    _isReportingError = true;

    try {
      onError!(error);
    } catch (callbackError, callbackStackTrace) {
      debugPrint(
        'JR CALL [CallListenerService/onError] '
        'callback failed: $callbackError',
      );

      debugPrintStack(
        label: 'JR CALL [CallListenerService/onError]',
        stackTrace: callbackStackTrace,
      );
    } finally {
      _isReportingError = false;
    }
  }

  // =============================================================
  // DATA NORMALIZATION
  // =============================================================

  String? _readNonEmptyString(Object? value) {
    if (value is! String) {
      return null;
    }

    final String normalizedValue = value.trim();

    return normalizedValue.isEmpty ? null : normalizedValue;
  }

  int? _readInteger(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num && value.isFinite) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value.trim());
    }

    return null;
  }

  Map<String, dynamic>? _normalizeMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }

    if (value is Map) {
      final Map<String, dynamic> normalizedMap = <String, dynamic>{};

      for (final MapEntry<Object?, Object?> entry in value.entries) {
        if (entry.key is! String) {
          return null;
        }

        normalizedMap[entry.key! as String] = entry.value;
      }

      return normalizedMap;
    }

    return null;
  }

  bool _isValidSessionDescription(
    Map<String, dynamic> description, {
    String? expectedType,
  }) {
    final String? sdp = _readNonEmptyString(description[CallFields.sdp]);

    final String? rawType = _readNonEmptyString(description[CallFields.type]);

    if (sdp == null || rawType == null) {
      return false;
    }

    final String type = rawType.toLowerCase();

    if (expectedType != null && type != expectedType.toLowerCase()) {
      return false;
    }

    return type == 'offer' || type == 'answer';
  }

  Map<String, dynamic> _normalizedImmutableDescription(
    Map<String, dynamic> description,
  ) {
    return Map<String, dynamic>.unmodifiable(<String, dynamic>{
      CallFields.sdp: _readNonEmptyString(description[CallFields.sdp])!,
      CallFields.type: _readNonEmptyString(
        description[CallFields.type],
      )!.toLowerCase(),
    });
  }

  bool _sessionDescriptionsEqual(
    Map<String, dynamic>? first,
    Map<String, dynamic>? second,
  ) {
    if (identical(first, second)) {
      return true;
    }

    if (first == null || second == null) {
      return false;
    }

    final String? firstSdp = _readNonEmptyString(first[CallFields.sdp]);

    final String? secondSdp = _readNonEmptyString(second[CallFields.sdp]);

    final String? firstType = _readNonEmptyString(
      first[CallFields.type],
    )?.toLowerCase();

    final String? secondType = _readNonEmptyString(
      second[CallFields.type],
    )?.toLowerCase();

    return firstSdp == secondSdp && firstType == secondType;
  }

  bool _nullableSessionDescriptionsEqual(
    Map<String, dynamic>? first,
    Map<String, dynamic>? second,
  ) {
    return _sessionDescriptionsEqual(first, second);
  }

  // =============================================================
  // RESET / DISPOSAL
  // =============================================================

  void reset() {
    _stopActiveSession(clearQueue: true, clearCachedValues: true);

    _clearCallbacks();
  }

  void _stopActiveSession({
    required bool clearQueue,
    required bool clearCachedValues,
  }) {
    _sessionGenerationId++;

    _cancelReconnectTimer();

    isListening = false;
    _isPaused = false;

    currentCallId = null;

    _terminatedSessionToken = null;
    _terminatedCallId = null;

    final subscription = currentSubscription;

    currentSubscription = null;

    if (subscription != null) {
      unawaited(subscription.cancel());
    }

    if (clearQueue) {
      _eventQueue.clear();
    }

    if (clearCachedValues) {
      _clearCachedValues();
    }
  }

  void _clearCachedValues() {
    lastStatus = null;

    lastOffer = null;
    lastAnswer = null;

    _lastConnectionState = null;
    _lastIceConnectionState = null;
    _lastSignalingState = null;
    _lastIceGatheringState = null;

    _lastNetworkRecovered = false;
    _lastIceRestartCount = 0;
  }

  void _clearCallbacks() {
    onStatusChanged = null;

    onOfferReceived = null;
    onAnswerReceived = null;

    onCallEnded = null;
    onCallDeleted = null;

    onConnectionStateChanged = null;
    onIceConnectionStateChanged = null;
    onSignalingStateChanged = null;
    onIceGatheringStateChanged = null;

    onNetworkRecovered = null;
    onIceRestart = null;

    onError = null;
  }

  /// After dispose(), call initialize() before reusing this singleton.
  void dispose() {
    if (_isDisposed) {
      return;
    }

    reset();

    _isDisposed = true;
  }
}

// ===============================================================
// END OF FILE
//
// FIXED: BUG 07, BUG 08
// ALSO FIXED:
// - Terminal-status event loss during cleanup
// - Stale terminal-event leakage protection
// - Offer/answer type validation
// - Canonical lowercase status/state normalization
// - Safer subscription replacement
// - Negative ICE restart counter rejection
//
// STATUS: READY FOR FORMAT + ANALYZE
//
// NEXT FILE: call_service.dart
// Location: lib/services/call/call_service.dart
// ===============================================================
