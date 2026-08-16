import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../call/signaling_service.dart';
import 'network_manager.dart';

/// ===========================================================
/// JR CALL
/// File: recovery_manager.dart
/// Location: lib/services/managers/recovery_manager.dart
///
/// Controlled WebRTC call recovery coordinator.
/// ===========================================================

class RecoveryManager extends ChangeNotifier {
  RecoveryManager._();

  static final RecoveryManager instance = RecoveryManager._();

  static const int _maxAttempts = 3;

  static const Duration _totalTimeout = Duration(seconds: 30);

  static const Duration _offlineRetry = Duration(seconds: 2);

  Timer? _retryTimer;
  Timer? _timeoutTimer;

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

  RTCPeerConnection? _peerConnection;

  Future<void> Function()? _restartCallback;

  VoidCallback? onRecoverySuccess;
  VoidCallback? onRecoveryFailed;

  ValueChanged<String>? onRestartSignalingListener;

  ValueChanged<Object>? onError;

  bool get isRecovering => _recovering;

  bool get recoveryRequested => _requested;

  int get reconnectAttempts => _attempts;

  bool get isCaller => _isCaller;

  String? get currentCallId => _callId;

  String? get currentUserId => _userId;

  void initialize() {
    if (!_disposed) {
      return;
    }

    _disposed = false;
    _generation++;
    _attempts = 0;
    _failureSent = false;
  }

  void setCallContext({
    required String callId,
    required String userId,
    required bool isCaller,
  }) {
    if (_disposed) {
      return;
    }

    final normalizedCallId = callId.trim();

    final normalizedUserId = userId.trim();

    if (normalizedCallId.isEmpty || normalizedUserId.isEmpty) {
      throw ArgumentError('callId and userId cannot be empty.');
    }

    if (_callId != normalizedCallId) {
      stopRecovery();

      _peerConnection = null;
      _restartCallback = null;
    }

    _callId = normalizedCallId;
    _userId = normalizedUserId;
    _isCaller = isCaller;
  }

  Future<void> handleIceConnectionChange(
    RTCIceConnectionState state,
    RTCPeerConnection? peerConnection,
    Future<void> Function()? onIceRestart,
  ) async {
    if (_disposed) {
      return;
    }

    if (peerConnection != null) {
      _peerConnection = peerConnection;
    }

    if (onIceRestart != null) {
      _restartCallback = onIceRestart;
    }

    switch (state) {
      case RTCIceConnectionState.RTCIceConnectionStateConnected:
      case RTCIceConnectionState.RTCIceConnectionStateCompleted:
        _markRecovered();
        break;

      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        _requestRecovery(
          immediate: NetworkManager.instance.currentNetwork.isConnected,
        );
        break;

      case RTCIceConnectionState.RTCIceConnectionStateFailed:
        _requestRecovery(immediate: true);
        break;

      case RTCIceConnectionState.RTCIceConnectionStateClosed:
        stopRecovery();
        break;

      case RTCIceConnectionState.RTCIceConnectionStateNew:
      case RTCIceConnectionState.RTCIceConnectionStateChecking:
      case RTCIceConnectionState.RTCIceConnectionStateCount:
        break;
    }
  }

  void handleRecoveryRequired() {
    if (_disposed) {
      return;
    }

    _requestRecovery(
      immediate: NetworkManager.instance.currentNetwork.isConnected,
    );
  }

  void handleNetworkRestored() {
    if (_disposed || (!_requested && !_recovering)) {
      return;
    }

    _requestRecovery(immediate: true);
  }

  void _requestRecovery({required bool immediate}) {
    if (_disposed || _callId == null) {
      return;
    }

    _requested = true;

    if (!_recovering) {
      _recovering = true;
      _failureSent = false;

      notifyListeners();
    }

    if (!immediate) {
      _schedule(delay: _offlineRetry, generation: _generation);

      return;
    }

    _ensureTimeout();

    _schedule(delay: Duration.zero, generation: _generation);
  }

  void _ensureTimeout() {
    if (_timeoutTimer?.isActive == true) {
      return;
    }

    final generation = _generation;

    _timeoutTimer = Timer(_totalTimeout, () {
      unawaited(_fail(generation, 'Recovery timeout reached.'));
    });
  }

  void _schedule({required Duration delay, required int generation}) {
    if (!_validGeneration(generation)) {
      return;
    }

    _retryTimer?.cancel();

    _retryTimer = Timer(delay, () {
      unawaited(_runAttempt(generation));
    });
  }

  Future<void> _runAttempt(int generation) async {
    if (!_validGeneration(generation) || _attemptRunning) {
      return;
    }

    if (!NetworkManager.instance.currentNetwork.isConnected) {
      _schedule(delay: _offlineRetry, generation: generation);

      return;
    }

    if (_attempts >= _maxAttempts) {
      await _fail(generation, 'Maximum recovery attempts reached.');

      return;
    }

    final restart = _restartCallback;

    if (restart == null) {
      _schedule(delay: _offlineRetry, generation: generation);

      return;
    }

    _attemptRunning = true;
    _attempts++;

    notifyListeners();

    try {
      await restart();

      if (!_validGeneration(generation)) {
        return;
      }

      final callId = _callId;

      if (callId != null) {
        onRestartSignalingListener?.call(callId);
      }

      await _verifyPeerState();
    } catch (error, stackTrace) {
      _report(error, stackTrace);
    } finally {
      _attemptRunning = false;
    }

    if (!_validGeneration(generation)) {
      return;
    }

    if (_attempts >= _maxAttempts) {
      await _fail(generation, 'Connection did not recover.');

      return;
    }

    _schedule(delay: _retryDelay(_attempts), generation: generation);
  }

  Duration _retryDelay(int completedAttempts) {
    switch (completedAttempts) {
      case 0:
      case 1:
        return const Duration(seconds: 2);
      case 2:
        return const Duration(seconds: 4);
      default:
        return const Duration(seconds: 8);
    }
  }

  Future<void> _verifyPeerState() async {
    final connection = _peerConnection;

    if (connection == null) {
      return;
    }

    final remote = await connection.getRemoteDescription();

    debugPrint(
      'RecoveryManager: remote description '
      '${remote == null ? 'not ready' : 'available'}.',
    );
  }

  void _markRecovered() {
    if (!_recovering && !_requested) {
      return;
    }

    stopRecovery();

    onRecoverySuccess?.call();
  }

  Future<void> _fail(int generation, String reason) async {
    if (!_validGeneration(generation) || _failureSent) {
      return;
    }

    _failureSent = true;

    final callId = _callId;

    if (callId != null) {
      try {
        await SignalingService.instance.updateCallStatus(callId, 'failed');
      } catch (error, stackTrace) {
        _report(error, stackTrace);
      }
    }

    debugPrint('RecoveryManager: $reason');

    stopRecovery();

    onRecoveryFailed?.call();
  }

  bool _validGeneration(int generation) {
    return !_disposed && _recovering && _requested && generation == _generation;
  }

  void stopRecovery() {
    _generation++;

    _retryTimer?.cancel();
    _retryTimer = null;

    _timeoutTimer?.cancel();
    _timeoutTimer = null;

    final changed = _recovering || _requested || _attempts != 0;

    _recovering = false;
    _requested = false;
    _attemptRunning = false;
    _failureSent = false;
    _attempts = 0;

    if (changed && !_disposed) {
      notifyListeners();
    }
  }

  void reset() {
    stopRecovery();

    _callId = null;
    _userId = null;
    _isCaller = false;

    _peerConnection = null;
    _restartCallback = null;

    onRecoverySuccess = null;
    onRecoveryFailed = null;
    onRestartSignalingListener = null;
    onError = null;
  }

  void _report(Object error, StackTrace stackTrace) {
    debugPrint('RecoveryManager error: $error');

    debugPrintStack(stackTrace: stackTrace);

    try {
      onError?.call(error);
    } catch (_) {}
  }

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
