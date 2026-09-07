// ===============================================================
// JR CALL
// File: recovery_manager.dart
// Location: lib/services/managers/recovery_manager.dart
//
// MASTER PRODUCTION RECOVERY COORDINATOR
//
// Ownership:
//
// CallService:
// - Complete call lifecycle
// - Terminal Firestore status
// - Call history
// - Cleanup
// - Complete caller ICE-restart signaling orchestration
//
// RecoveryManager:
// - Detect/request bounded recovery
// - Coordinate caller/receiver recovery behavior
// - Recovery timers/backoff
// - Recovery success/failure notification
// - Signaling-listener restart request
//
// PeerConnectionManager / WebRTCService:
// - PeerConnection / SDP / native restartIce transport
//
// SignalingService:
// - Firestore signaling only
//
// IceManager:
// - ICE candidate ownership
//
// NetworkManager:
// - Network availability source
//
// PRODUCTION GUARANTEES:
//
// ✓ RecoveryManager NEVER writes terminal call status.
// ✓ CallService remains sole terminal lifecycle owner.
// ✓ Native restartIce is never treated as complete signaling.
// ✓ Caller full restart is delegated to CallService coordinator.
// ✓ Receiver never performs caller-owned restart signaling.
// ✓ Receiver safely waits/restarts signaling observation.
// ✓ Connected/completed ICE immediately cancels recovery.
// ✓ PeerConnection connected state confirms recovery.
// ✓ Maximum active recovery attempts are bounded.
// ✓ Total recovery timeout remains bounded.
// ✓ Offline recovery cannot remain alive forever.
// ✓ Old async recovery operations cannot affect later sessions.
// ✓ Duplicate recovery requests are harmless.
// ✓ Existing public APIs preserved.
// ===============================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'network_manager.dart';

class RecoveryManager extends ChangeNotifier {
  RecoveryManager._();

  static final RecoveryManager instance =
  RecoveryManager._();

  // =============================================================
  // CONFIGURATION
  // =============================================================

  static const int _maxAttempts = 3;

  static const Duration _totalTimeout =
  Duration(seconds: 30);

  static const Duration _offlineRetry =
  Duration(seconds: 2);

  static const Duration _disconnectedGrace =
  Duration(seconds: 2);

  // =============================================================
  // TIMERS
  // =============================================================

  Timer? _retryTimer;

  Timer? _timeoutTimer;

  // =============================================================
  // SESSION / RECOVERY STATE
  // =============================================================

  int _attempts = 0;

  int _generation = 0;

  bool _recovering = false;

  bool _requested = false;

  bool _attemptRunning = false;

  bool _disposed = false;

  bool _failureSent = false;

  String? _callId;

  String? _userId;

  bool _isCaller = false;

  // =============================================================
  // WEBRTC CONTEXT
  // =============================================================

  RTCPeerConnection? _peerConnection;

  /// Native transport restart callback supplied by the active
  /// PeerConnection layer.
  ///
  /// IMPORTANT:
  ///
  /// This callback alone is NOT a complete recovery operation.
  ///
  /// CallService must coordinate:
  /// - reconnecting lifecycle state
  /// - native restart
  /// - createOffer(iceRestart: true)
  /// - signaling persistence
  /// - restart metadata
  Future<void> Function()? _nativeRestartCallback;

  // =============================================================
  // PUBLIC CALLBACKS
  // =============================================================

  VoidCallback? onRecoverySuccess;

  VoidCallback? onRecoveryFailed;

  ValueChanged<String>? onRestartSignalingListener;

  ValueChanged<Object>? onError;

  /// Complete caller recovery coordinator owned by CallService.
  ///
  /// Parameters:
  /// - current callId
  /// - native restart operation supplied by PeerConnection layer
  ///
  /// RecoveryManager itself never persists the restart offer.
  Future<void> Function(
      String callId,
      Future<void> Function()? nativeRestart,
      )? onCallerRecoveryRequired;

  // =============================================================
  // PUBLIC STATE
  // =============================================================

  bool get isRecovering =>
      _recovering;

  bool get recoveryRequested =>
      _requested;

  int get reconnectAttempts =>
      _attempts;

  bool get isCaller =>
      _isCaller;

  String? get currentCallId =>
      _callId;

  String? get currentUserId =>
      _userId;

  // =============================================================
  // COMPATIBILITY INITIALIZATION
  //
  // ChangeNotifier disposal is terminal.
  //
  // Normal singleton reuse must use reset(), never resurrect a
  // disposed ChangeNotifier instance.
  // =============================================================

  void initialize() {
    if (_disposed) {
      return;
    }
  }

  // =============================================================
  // CALL CONTEXT
  // =============================================================

  void setCallContext({
    required String callId,
    required String userId,
    required bool isCaller,
  }) {
    if (_disposed) {
      return;
    }

    final String normalizedCallId =
    callId.trim();

    final String normalizedUserId =
    userId.trim();

    if (normalizedCallId.isEmpty ||
        normalizedUserId.isEmpty) {
      throw ArgumentError(
        'callId and userId cannot be empty.',
      );
    }

    final bool contextChanged =
        _callId != null &&
            (_callId != normalizedCallId ||
                _userId != normalizedUserId ||
                _isCaller != isCaller);

    if (contextChanged) {
      stopRecovery();

      _peerConnection = null;

      _nativeRestartCallback = null;
    }

    _callId = normalizedCallId;

    _userId = normalizedUserId;

    _isCaller = isCaller;
  }

  // =============================================================
  // ICE CONNECTION STATE
  // =============================================================

  Future<void> handleIceConnectionChange(
      RTCIceConnectionState state,
      RTCPeerConnection? peerConnection,
      Future<void> Function()? onIceRestart,
      ) async {
    if (_disposed) {
      return;
    }

    if (peerConnection != null) {
      _peerConnection =
          peerConnection;
    }

    if (onIceRestart != null) {
      _nativeRestartCallback =
          onIceRestart;
    }

    switch (state) {
      case RTCIceConnectionState
          .RTCIceConnectionStateConnected:
      case RTCIceConnectionState
          .RTCIceConnectionStateCompleted:
        _markRecovered();

        break;

      case RTCIceConnectionState
          .RTCIceConnectionStateDisconnected:
      // A short disconnected period is frequently self-healing.
      // Avoid triggering an unnecessary immediate ICE restart.
        _requestRecovery(
          immediate: false,
          initialDelay:
          _disconnectedGrace,
        );

        break;

      case RTCIceConnectionState
          .RTCIceConnectionStateFailed:
        _requestRecovery(
          immediate: true,
        );

        break;

      case RTCIceConnectionState
          .RTCIceConnectionStateClosed:
        stopRecovery();

        break;

      case RTCIceConnectionState
          .RTCIceConnectionStateNew:
      case RTCIceConnectionState
          .RTCIceConnectionStateChecking:
      case RTCIceConnectionState
          .RTCIceConnectionStateCount:
        break;
    }
  }

  // =============================================================
  // EXPLICIT RECOVERY REQUEST
  // =============================================================

  void handleRecoveryRequired() {
    if (_disposed) {
      return;
    }

    _requestRecovery(
      immediate:
      NetworkManager.instance
          .currentNetwork
          .isConnected,
    );
  }

  // =============================================================
  // NETWORK RESTORATION
  // =============================================================

  void handleNetworkRestored() {
    if (_disposed ||
        (!_requested &&
            !_recovering)) {
      return;
    }

    _requestRecovery(
      immediate: true,
    );
  }

  // =============================================================
  // BEGIN / CONTINUE RECOVERY
  // =============================================================

  void _requestRecovery({
    required bool immediate,
    Duration? initialDelay,
  }) {
    if (_disposed ||
        _callId == null) {
      return;
    }

    _requested = true;

    if (!_recovering) {
      _recovering = true;

      _failureSent = false;

      _attempts = 0;

      _notifySafely();
    }

    _ensureTimeout();

    if (!immediate) {
      _schedule(
        delay:
        initialDelay ??
            _offlineRetry,
        generation:
        _generation,
      );

      return;
    }

    _schedule(
      delay:
      Duration.zero,
      generation:
      _generation,
    );
  }

  // =============================================================
  // TOTAL TIMEOUT
  // =============================================================

  void _ensureTimeout() {
    if (_timeoutTimer?.isActive ==
        true) {
      return;
    }

    final int generation =
        _generation;

    _timeoutTimer =
        Timer(
          _totalTimeout,
              () {
            unawaited(
              _fail(
                generation,
                'Recovery timeout reached.',
              ),
            );
          },
        );
  }

  // =============================================================
  // RETRY SCHEDULER
  // =============================================================

  void _schedule({
    required Duration delay,
    required int generation,
  }) {
    if (!_validGeneration(
      generation,
    )) {
      return;
    }

    _retryTimer?.cancel();

    _retryTimer =
        Timer(
          delay,
              () {
            _retryTimer = null;

            unawaited(
              _runAttempt(
                generation,
              ),
            );
          },
        );
  }

  // =============================================================
  // RECOVERY ATTEMPT
  // =============================================================

  Future<void> _runAttempt(
      int generation,
      ) async {
    if (!_validGeneration(
      generation,
    ) ||
        _attemptRunning) {
      return;
    }

    if (_peerIsConnected()) {
      _markRecovered();

      return;
    }

    if (!NetworkManager
        .instance
        .currentNetwork
        .isConnected) {
      _schedule(
        delay:
        _offlineRetry,
        generation:
        generation,
      );

      return;
    }

    // -----------------------------------------------------------
    // CALLER ORCHESTRATION READINESS
    //
    // Never perform native restartIce alone.
    //
    // Doing that without creating/persisting the restart offer
    // would create an incomplete recovery negotiation.
    // -----------------------------------------------------------

    if (_isCaller &&
        onCallerRecoveryRequired ==
            null) {
      _debugPrint(
        'caller recovery coordinator '
            'is not ready.',
      );

      _schedule(
        delay:
        _offlineRetry,
        generation:
        generation,
      );

      return;
    }

    if (_attempts >=
        _maxAttempts) {
      return;
    }

    _attemptRunning =
    true;

    _attempts++;

    _notifySafely();

    try {
      if (_isCaller) {
        await _performCallerRecovery(
          generation,
        );
      } else {
        await _performReceiverRecovery(
          generation,
        );
      }

      if (!_validGeneration(
        generation,
      )) {
        return;
      }

      if (await _verifyPeerState()) {
        _markRecovered();

        return;
      }
    } catch (error, stackTrace) {
      _report(
        error,
        stackTrace,
      );
    } finally {
      _attemptRunning =
      false;
    }

    if (!_validGeneration(
      generation,
    )) {
      return;
    }

    if (_peerIsConnected()) {
      _markRecovered();

      return;
    }

    if (_attempts <
        _maxAttempts) {
      _schedule(
        delay:
        _retryDelay(
          _attempts,
        ),
        generation:
        generation,
      );
    }
  }

  // =============================================================
  // CALLER RECOVERY
  // =============================================================

  Future<void> _performCallerRecovery(
      int generation,
      ) async {
    if (!_validGeneration(
      generation,
    )) {
      return;
    }

    final String? callId =
        _callId;

    final Future<void> Function(
        String callId,
        Future<void> Function()? nativeRestart,
        )? coordinator =
        onCallerRecoveryRequired;

    if (callId == null ||
        coordinator == null) {
      return;
    }

    // -----------------------------------------------------------
    // CallService owns the COMPLETE restart sequence.
    //
    // RecoveryManager supplies:
    // - callId
    // - native transport restart callback
    //
    // CallService performs:
    // - reconnecting lifecycle
    // - native restart
    // - restart offer creation
    // - offer persistence
    // - restart metadata
    // -----------------------------------------------------------

    await coordinator(
      callId,
      _nativeRestartCallback,
    );

    if (!_validGeneration(
      generation,
    )) {
      return;
    }

    _restartSignalingListener();
  }

  // =============================================================
  // RECEIVER RECOVERY
  // =============================================================

  Future<void> _performReceiverRecovery(
      int generation,
      ) async {
    if (!_validGeneration(
      generation,
    )) {
      return;
    }

    // Receiver never creates the caller-owned restart offer.
    //
    // It keeps the current PeerConnection alive and refreshes
    // signaling observation while waiting for the restart offer.

    _restartSignalingListener();

    await Future<void>.delayed(
      const Duration(
        milliseconds: 250,
      ),
    );
  }

  // =============================================================
  // SIGNALING LISTENER RECOVERY
  // =============================================================

  void _restartSignalingListener() {
    final String? callId =
        _callId;

    if (_disposed ||
        callId == null ||
        callId.isEmpty) {
      return;
    }

    try {
      onRestartSignalingListener
          ?.call(
        callId,
      );
    } catch (error, stackTrace) {
      _report(
        error,
        stackTrace,
      );
    }
  }

  // =============================================================
  // PEER VERIFICATION
  // =============================================================

  Future<bool> _verifyPeerState() async {
    final RTCPeerConnection? connection =
        _peerConnection;

    if (connection == null) {
      return false;
    }

    try {
      final RTCPeerConnectionState?
      connectionState =
          connection
              .connectionState;

      final RTCIceConnectionState?
      iceState =
          connection
              .iceConnectionState;

      _debugPrint(
        'connection=$connectionState, '
            'ice=$iceState.',
      );

      return _isConnectedState(
        connectionState,
        iceState,
      );
    } catch (error, stackTrace) {
      _report(
        error,
        stackTrace,
      );

      return false;
    }
  }

  bool _peerIsConnected() {
    final RTCPeerConnection? connection =
        _peerConnection;

    if (connection == null) {
      return false;
    }

    try {
      return _isConnectedState(
        connection.connectionState,
        connection.iceConnectionState,
      );
    } catch (_) {
      return false;
    }
  }

  bool _isConnectedState(
      RTCPeerConnectionState?
      connectionState,
      RTCIceConnectionState?
      iceState,
      ) {
    return connectionState ==
        RTCPeerConnectionState
            .RTCPeerConnectionStateConnected ||
        iceState ==
            RTCIceConnectionState
                .RTCIceConnectionStateConnected ||
        iceState ==
            RTCIceConnectionState
                .RTCIceConnectionStateCompleted;
  }

  // =============================================================
  // RETRY BACKOFF
  // =============================================================

  Duration _retryDelay(
      int completedAttempts,
      ) {
    switch (completedAttempts) {
      case 0:
      case 1:
        return const Duration(
          seconds: 2,
        );

      case 2:
        return const Duration(
          seconds: 4,
        );

      default:
        return const Duration(
          seconds: 8,
        );
    }
  }

  // =============================================================
  // RECOVERY SUCCESS
  // =============================================================

  void _markRecovered() {
    if (!_recovering &&
        !_requested) {
      return;
    }

    stopRecovery();

    try {
      onRecoverySuccess?.call();
    } catch (error, stackTrace) {
      _report(
        error,
        stackTrace,
      );
    }
  }

  // =============================================================
  // RECOVERY FAILURE
  // =============================================================

  Future<void> _fail(
      int generation,
      String reason,
      ) async {
    if (!_validGeneration(
      generation,
    ) ||
        _failureSent) {
      return;
    }

    if (_peerIsConnected()) {
      _markRecovered();

      return;
    }

    _failureSent =
    true;

    _debugPrint(
      reason,
    );

    // RecoveryManager reports failure only.
    //
    // CallService owns:
    // - terminal FAILED lifecycle
    // - Firestore status
    // - call history
    // - terminal UI
    // - cleanup

    stopRecovery();

    try {
      onRecoveryFailed?.call();
    } catch (error, stackTrace) {
      _report(
        error,
        stackTrace,
      );
    }
  }

  // =============================================================
  // GENERATION VALIDATION
  // =============================================================

  bool _validGeneration(
      int generation,
      ) {
    return !_disposed &&
        _recovering &&
        _requested &&
        generation ==
            _generation;
  }

  // =============================================================
  // STOP RECOVERY
  // =============================================================

  void stopRecovery() {
    _generation++;

    _retryTimer?.cancel();

    _retryTimer = null;

    _timeoutTimer?.cancel();

    _timeoutTimer = null;

    final bool changed =
        _recovering ||
            _requested ||
            _attempts != 0 ||
            _attemptRunning;

    _recovering = false;

    _requested = false;

    _attemptRunning = false;

    _failureSent = false;

    _attempts = 0;

    if (changed &&
        !_disposed) {
      _notifySafely();
    }
  }

  // =============================================================
  // RESET
  // =============================================================

  void reset() {
    if (_disposed) {
      return;
    }

    stopRecovery();

    _callId = null;

    _userId = null;

    _isCaller = false;

    _peerConnection = null;

    _nativeRestartCallback = null;

    onRecoverySuccess = null;

    onRecoveryFailed = null;

    onRestartSignalingListener = null;

    onCallerRecoveryRequired = null;

    onError = null;
  }

  // =============================================================
  // SAFE NOTIFY
  // =============================================================

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  // =============================================================
  // LOGGING
  // =============================================================

  void _debugPrint(
      String message,
      ) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      'JR CALL '
          '[RecoveryManager] '
          '$message',
    );
  }

  // =============================================================
  // ERROR REPORTING
  // =============================================================

  void _report(
      Object error,
      StackTrace stackTrace,
      ) {
    if (kDebugMode) {
      debugPrint(
        'JR CALL '
            '[RecoveryManager] '
            'error: $error',
      );

      debugPrintStack(
        label:
        'JR CALL '
            '[RecoveryManager]',
        stackTrace:
        stackTrace,
      );
    }

    final ValueChanged<Object>? callback =
        onError;

    if (_disposed ||
        callback == null) {
      return;
    }

    try {
      callback(
        error,
      );
    } catch (_) {
      // Error callback must never destabilize recovery.
    }
  }

  // =============================================================
  // DISPOSE
  // =============================================================

  @override
  void dispose() {
    if (_disposed) {
      return;
    }

    reset();

    _disposed = true;

    super.dispose();
  }
}

// ===============================================================
// END OF FILE
//
// FILE 17 FINAL GUARANTEES:
//
// ✓ Existing public APIs preserved.
// ✓ Native restart callback remains transport-only.
// ✓ No unsignaled native ICE restart.
// ✓ Caller complete restart delegated to CallService coordinator.
// ✓ Additive onCallerRecoveryRequired integration hook added.
// ✓ Receiver never performs caller restart signaling.
// ✓ Receiver refreshes signaling observation only.
// ✓ Transient disconnected state receives recovery grace period.
// ✓ Failed ICE triggers immediate recovery.
// ✓ Total recovery timeout remains 30 seconds.
// ✓ Maximum active attempts remain 3.
// ✓ Offline polling does not consume active attempts.
// ✓ Retry backoff remains bounded.
// ✓ Old timers/async operations generation-guarded.
// ✓ Native connection state verifies recovery.
// ✓ Diagnostic SDP read no longer gates recovery success.
// ✓ RecoveryManager never writes terminal Firestore status.
// ✓ CallService remains terminal lifecycle/history owner.
// ✓ ChangeNotifier cannot be resurrected after dispose.
// ✓ reset() remains per-call singleton reuse path.
// ✓ No PeerConnection ownership duplicated.
// ✓ No ICE candidate ownership duplicated.
// ✓ No signaling persistence ownership duplicated.
// ✓ No media/UI ownership added.
//
// STATUS:
// RECOVERY MANAGER FINALIZED.
//
// NEXT PURE CALL ENGINE FILE:
// FILE 18
// lib/services/call/connection_manager.dart
// ===============================================================