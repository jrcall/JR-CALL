// ===========================================================
// JR CALL
// File: call_provider.dart
// Location: lib/providers/call_provider.dart
//
// MASTER PRODUCTION CALL PROVIDER
//
// Architecture:
//
// UI
//   -> CallProvider
//   -> CallService
//   -> Connection / Recovery / WebRTC / Signaling layers
//
// OWNERSHIP:
//
// CallService:
// - Call lifecycle.
// - Call duration.
// - Start / accept / reject / cancel / end.
//
// SignalingService:
// - Firestore signaling.
// - Call-history persistence.
//
// IceManager:
// - ICE.
//
// RecoveryManager:
// - Recovery.
//
// NetworkManager:
// - Network monitoring.
//
// AudioProvider:
// - Audio presentation state.
//
// VideoProvider:
// - Video presentation state.
//
// CallProvider:
// - Immutable presentation-state bridge only.
// - CallService status/duration stream synchronization.
// - UI operation guards.
// - Presentation metadata.
// - Network snapshot mapping.
//
// IMPORTANT:
//
// This provider does NOT:
//
// - Create its own call timer.
// - Create call history.
// - Write signaling.
// - Own ICE.
// - Own recovery.
// - Monitor network.
// - Own RTCPeerConnection.
// - Own MediaStream / MediaStreamTrack.
// - Fake a connected call.
// ===========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/network_model.dart' as network;
import '../services/call/call_service.dart';
import 'call_state.dart';

class CallProvider extends ChangeNotifier {
  CallProvider({
    CallService? callService,
  }) : _callService = callService ?? CallService();

  // ===========================================================
  // DEPENDENCIES
  // ===========================================================

  final CallService _callService;

  // ===========================================================
  // PRESENTATION STATE
  // ===========================================================

  CallState _state = const CallState();

  CallState get state => _state;

  CallService get callService => _callService;

  // ===========================================================
  // RUNTIME STATE
  // ===========================================================

  bool _isInitialized = false;

  bool _isDisposed = false;

  bool _isStartingCall = false;

  bool _isAcceptingCall = false;

  bool _isEndingCall = false;

  Future<void>? _initializationFuture;

  /// Invalidates stale async UI operations after reset/new session.
  int _operationGeneration = 0;

  // ===========================================================
  // PUBLIC RUNTIME STATE
  // ===========================================================

  bool get isInitialized => _isInitialized;

  bool get isDisposed => _isDisposed;

  bool get isStartingCall => _isStartingCall;

  bool get isAcceptingCall => _isAcceptingCall;

  bool get isEndingCall => _isEndingCall;

  bool get isBusy =>
      _isStartingCall || _isAcceptingCall || _isEndingCall;

  bool get hasActiveCall {
    final String? callId = _callService.currentCallId;

    return callId != null && callId.trim().isNotEmpty;
  }

  String? get currentCallId {
    final String? callId = _callService.currentCallId;

    if (callId == null) {
      return null;
    }

    final String normalized = callId.trim();

    return normalized.isEmpty ? null : normalized;
  }

  // ===========================================================
  // STREAM SUBSCRIPTIONS
  // ===========================================================

  StreamSubscription<String>? _statusSubscription;

  StreamSubscription<int>? _durationSubscription;

  // ===========================================================
  // INITIALIZATION
  // ===========================================================

  Future<void> initialize() {
    if (_isDisposed) {
      return Future<void>.error(
        StateError(
          'CallProvider has already been disposed.',
        ),
      );
    }

    if (_isInitialized) {
      return Future<void>.value();
    }

    final Future<void>? existing = _initializationFuture;

    if (existing != null) {
      return existing;
    }

    final Future<void> future = _initializeInternal();

    _initializationFuture = future;

    return future;
  }

  Future<void> _initializeInternal() async {
    try {
      await _callService.initialize();

      if (_isDisposed) {
        return;
      }

      await _cancelSubscriptions();

      if (_isDisposed) {
        return;
      }

      _statusSubscription = _callService.callStatusStream.listen(
        _handleCallServiceStatus,
        onError: (
            Object error,
            StackTrace stackTrace,
            ) {
          if (_isDisposed) {
            return;
          }

          _reportError(
            'status stream',
            error,
            stackTrace,
          );

          _setConnectionState(
            CallConnectionState.failed,
          );
        },
      );

      _durationSubscription = _callService.callDurationStream.listen(
        _handleDuration,
        onError: (
            Object error,
            StackTrace stackTrace,
            ) {
          if (_isDisposed) {
            return;
          }

          _reportError(
            'duration stream',
            error,
            stackTrace,
          );
        },
      );

      _isInitialized = true;

      _safeNotifyListeners();
    } catch (error, stackTrace) {
      _reportError(
        'initialize',
        error,
        stackTrace,
      );

      await _cancelSubscriptions();

      _isInitialized = false;

      rethrow;
    } finally {
      _initializationFuture = null;
    }
  }

  Future<void> _ensureInitialized() async {
    if (_isDisposed) {
      return;
    }

    if (_isInitialized) {
      return;
    }

    await initialize();
  }

  // ===========================================================
  // OUTGOING CALL
  // ===========================================================

  Future<String?> startOutgoingCall({
    required String localUid,
    required String remoteUid,
    required String remoteName,
    String remotePhoto = '',
    bool isVideoCall = false,
  }) async {
    if (_isDisposed || isBusy) {
      return null;
    }

    final String normalizedLocalUid = localUid.trim();

    final String normalizedRemoteUid = remoteUid.trim();

    if (normalizedLocalUid.isEmpty ||
        normalizedRemoteUid.isEmpty ||
        normalizedLocalUid == normalizedRemoteUid) {
      _setConnectionState(
        CallConnectionState.failed,
      );

      return null;
    }

    final int operationToken = _beginOperation();

    _isStartingCall = true;

    _safeNotifyListeners();

    try {
      await _ensureInitialized();

      if (!_isOperationCurrent(
        operationToken,
      )) {
        return null;
      }

      _setState(
        _state.copyWith(
          connectionState: CallConnectionState.connecting,
          localUid: normalizedLocalUid,
          remoteUid: normalizedRemoteUid,
          remoteName: remoteName.trim(),
          remotePhoto: remotePhoto.trim(),
          duration: 0,
        ),
      );

      final String? callId = await _callService.startCall(
        callerId: normalizedLocalUid,
        receiverId: normalizedRemoteUid,
        isVideoCall: isVideoCall,
      );

      if (!_isOperationCurrent(
        operationToken,
      )) {
        return null;
      }

      final String normalizedCallId = callId?.trim() ?? '';

      if (normalizedCallId.isEmpty) {
        if (_state.connectionState != CallConnectionState.failed) {
          _setConnectionState(
            CallConnectionState.failed,
          );
        }

        return null;
      }

      // Do NOT fake connected state here.
      //
      // CallService status stream remains authoritative.
      return normalizedCallId;
    } catch (error, stackTrace) {
      _reportError(
        'start call',
        error,
        stackTrace,
      );

      if (_isOperationCurrent(
        operationToken,
      )) {
        _setConnectionState(
          CallConnectionState.failed,
        );
      }

      return null;
    } finally {
      if (_isOperationCurrent(
        operationToken,
      )) {
        _isStartingCall = false;

        _safeNotifyListeners();
      }
    }
  }

  // ===========================================================
  // INCOMING CALL PRESENTATION
  // ===========================================================

  void incomingCall({
    required String localUid,
    required String remoteUid,
    required String remoteName,
    String remotePhoto = '',
  }) {
    if (_isDisposed) {
      return;
    }

    _setState(
      _state.copyWith(
        connectionState: CallConnectionState.incoming,
        localUid: localUid.trim(),
        remoteUid: remoteUid.trim(),
        remoteName: remoteName.trim(),
        remotePhoto: remotePhoto.trim(),
        duration: 0,
      ),
    );
  }

  // ===========================================================
  // ACCEPT INCOMING CALL
  // ===========================================================

  Future<void> acceptCall({
    required String callId,
  }) async {
    if (_isDisposed || isBusy) {
      return;
    }

    final String normalizedCallId = callId.trim();

    if (normalizedCallId.isEmpty) {
      _setConnectionState(
        CallConnectionState.failed,
      );

      return;
    }

    final int operationToken = _beginOperation();

    _isAcceptingCall = true;

    _safeNotifyListeners();

    try {
      await _ensureInitialized();

      if (!_isOperationCurrent(
        operationToken,
      )) {
        return;
      }

      _setConnectionState(
        CallConnectionState.connecting,
      );

      await _callService.acceptCall(
        callId: normalizedCallId,
      );

      // IMPORTANT:
      // acceptCall completion does not prove WebRTC connected.
      // CallService status stream must publish real connection.
    } catch (error, stackTrace) {
      _reportError(
        'accept call',
        error,
        stackTrace,
      );

      if (_isOperationCurrent(
        operationToken,
      )) {
        _setConnectionState(
          CallConnectionState.failed,
        );
      }
    } finally {
      if (_isOperationCurrent(
        operationToken,
      )) {
        _isAcceptingCall = false;

        _safeNotifyListeners();
      }
    }
  }

  // ===========================================================
  // REJECT INCOMING CALL
  // ===========================================================

  Future<void> rejectCall({
    required String callId,
  }) async {
    if (_isDisposed || isBusy) {
      return;
    }

    final String normalizedCallId = callId.trim();

    if (normalizedCallId.isEmpty) {
      return;
    }

    final int operationToken = _beginOperation();

    _isEndingCall = true;

    _safeNotifyListeners();

    try {
      await _ensureInitialized();

      if (!_isOperationCurrent(
        operationToken,
      )) {
        return;
      }

      await _callService.rejectCall(
        callId: normalizedCallId,
      );

      // Terminal presentation remains status-stream owned.
    } catch (error, stackTrace) {
      _reportError(
        'reject call',
        error,
        stackTrace,
      );
    } finally {
      if (_isOperationCurrent(
        operationToken,
      )) {
        _isEndingCall = false;

        _safeNotifyListeners();
      }
    }
  }

  // ===========================================================
  // CANCEL OUTGOING CALL
  // ===========================================================

  Future<void> cancelCall({
    String? callId,
  }) async {
    if (_isDisposed || isBusy) {
      return;
    }

    final String? resolvedCallId = _resolveCallId(
      callId,
    );

    if (resolvedCallId == null) {
      return;
    }

    final int operationToken = _beginOperation();

    _isEndingCall = true;

    _safeNotifyListeners();

    try {
      await _ensureInitialized();

      if (!_isOperationCurrent(
        operationToken,
      )) {
        return;
      }

      await _callService.cancelCall(
        callId: resolvedCallId,
      );

      // Terminal presentation remains status-stream owned.
    } catch (error, stackTrace) {
      _reportError(
        'cancel call',
        error,
        stackTrace,
      );
    } finally {
      if (_isOperationCurrent(
        operationToken,
      )) {
        _isEndingCall = false;

        _safeNotifyListeners();
      }
    }
  }

  // ===========================================================
  // END ACTIVE CALL
  // ===========================================================

  Future<void> endCall({
    String? callId,
    String status = 'COMPLETED',
  }) async {
    if (_isDisposed || isBusy) {
      return;
    }

    final String? resolvedCallId = _resolveCallId(
      callId,
    );

    if (resolvedCallId == null) {
      reset();

      return;
    }

    final int operationToken = _beginOperation();

    _isEndingCall = true;

    _safeNotifyListeners();

    final String normalizedStatus =
    status.trim().isEmpty ? 'COMPLETED' : status.trim();

    try {
      await _ensureInitialized();

      if (!_isOperationCurrent(
        operationToken,
      )) {
        return;
      }

      await _callService.endCall(
        callId: resolvedCallId,
        status: normalizedStatus,
      );

      // CallService owns final lifecycle/history.
    } catch (error, stackTrace) {
      _reportError(
        'end call',
        error,
        stackTrace,
      );

      if (_isOperationCurrent(
        operationToken,
      )) {
        _setConnectionState(
          CallConnectionState.failed,
        );
      }
    } finally {
      if (_isOperationCurrent(
        operationToken,
      )) {
        _isEndingCall = false;

        _safeNotifyListeners();
      }
    }
  }

  // ===========================================================
  // CALL SERVICE STATUS SYNCHRONIZATION
  //
  // Existing mapping semantics intentionally preserved.
  // Do not change these casually because current screens may rely
  // on this provider-level presentation mapping.
  // ===========================================================

  void _handleCallServiceStatus(
      String rawStatus,
      ) {
    if (_isDisposed) {
      return;
    }

    final String status = rawStatus.trim().toUpperCase();

    switch (status) {
      case CallServiceStatus.preparing:
      case CallServiceStatus.calling:
      case CallServiceStatus.ringing:
      case CallServiceStatus.connecting:
        _setConnectionState(
          CallConnectionState.connecting,
        );
        break;

      case CallServiceStatus.connected:
      case CallServiceStatus.reconnected:
        _setConnectionState(
          CallConnectionState.connected,
        );
        break;

      case CallServiceStatus.reconnecting:
      case CallServiceStatus.networkLost:
        _setConnectionState(
          CallConnectionState.reconnecting,
        );
        break;

      case CallServiceStatus.userBusy:
      case CallServiceStatus.timeout:
      case CallServiceStatus.failed:
        _setConnectionState(
          CallConnectionState.failed,
        );
        break;

      case CallServiceStatus.rejected:
      case CallServiceStatus.declined:
      case CallServiceStatus.cancelled:
      case CallServiceStatus.ended:
        _setConnectionState(
          CallConnectionState.ended,
        );
        break;

      case CallServiceStatus.idle:
      // Existing behavior preserved:
      // idle does not overwrite a useful terminal state.
        break;

      default:
        debugPrint(
          'JR CALL [CallProvider] '
              'unknown call status: $status',
        );
        break;
    }
  }

  // ===========================================================
  // DURATION SYNCHRONIZATION
  // ===========================================================

  void _handleDuration(
      int duration,
      ) {
    if (_isDisposed) {
      return;
    }

    final int safeDuration = duration < 0 ? 0 : duration;

    if (_state.duration == safeDuration) {
      return;
    }

    _setState(
      _state.copyWith(
        duration: safeDuration,
      ),
    );
  }

  // ===========================================================
  // NETWORK METRICS SYNCHRONIZATION
  //
  // NetworkManager/quality layer owns measurement.
  // CallProvider only maps a supplied snapshot.
  // ===========================================================

  void updateNetwork({
    required network.NetworkQuality quality,
    required double upload,
    required double download,
    required int ping,
  }) {
    if (_isDisposed) {
      return;
    }

    final NetworkQuality mappedQuality = _mapNetworkQuality(
      quality,
    );

    final double safeUpload = _sanitizeMetric(
      upload,
    );

    final double safeDownload = _sanitizeMetric(
      download,
    );

    final int safePing = ping < 0 ? 0 : ping;

    _setState(
      _state.copyWith(
        networkQuality: mappedQuality,
        uploadBitrate: safeUpload,
        downloadBitrate: safeDownload,
        ping: safePing,
      ),
    );
  }

  NetworkQuality _mapNetworkQuality(
      network.NetworkQuality quality,
      ) {
    switch (quality) {
      case network.NetworkQuality.excellent:
        return NetworkQuality.excellent;

      case network.NetworkQuality.good:
        return NetworkQuality.good;

      case network.NetworkQuality.fair:
        return NetworkQuality.fair;

      case network.NetworkQuality.poor:
        return NetworkQuality.poor;

      case network.NetworkQuality.offline:
        return NetworkQuality.offline;
    }
  }

  double _sanitizeMetric(
      double value,
      ) {
    if (!value.isFinite || value < 0) {
      return 0.0;
    }

    return value;
  }

  // ===========================================================
  // EXPLICIT PRESENTATION SYNCHRONIZATION HELPERS
  // ===========================================================

  void connectCall() {
    _setConnectionState(
      CallConnectionState.connected,
    );
  }

  void reconnecting() {
    _setConnectionState(
      CallConnectionState.reconnecting,
    );
  }

  void connectionFailed() {
    _setConnectionState(
      CallConnectionState.failed,
    );
  }

  // ===========================================================
  // CONNECTION STATE
  // ===========================================================

  void _setConnectionState(
      CallConnectionState connectionState,
      ) {
    if (_isDisposed ||
        _state.connectionState == connectionState) {
      return;
    }

    _setState(
      _state.copyWith(
        connectionState: connectionState,
      ),
    );
  }

  // ===========================================================
  // REMOTE PRESENTATION METADATA
  // ===========================================================

  void updateRemoteUser({
    String? remoteUid,
    String? remoteName,
    String? remotePhoto,
  }) {
    if (_isDisposed) {
      return;
    }

    _setState(
      _state.copyWith(
        remoteUid: remoteUid?.trim() ?? _state.remoteUid,
        remoteName: remoteName?.trim() ?? _state.remoteName,
        remotePhoto: remotePhoto?.trim() ?? _state.remotePhoto,
      ),
    );
  }

  // ===========================================================
  // CENTRAL IMMUTABLE STATE SETTER
  // ===========================================================

  void _setState(
      CallState nextState,
      ) {
    if (_isDisposed) {
      return;
    }

    if (_state == nextState) {
      return;
    }

    _state = nextState;

    _safeNotifyListeners();
  }

  // ===========================================================
  // OPERATION GENERATION
  //
  // A reset/new UI session invalidates late completion from an
  // older async provider operation.
  // ===========================================================

  int _beginOperation() {
    _operationGeneration++;

    return _operationGeneration;
  }

  bool _isOperationCurrent(
      int token,
      ) {
    return !_isDisposed && token == _operationGeneration;
  }

  // ===========================================================
  // CALL-ID RESOLUTION
  // ===========================================================

  String? _resolveCallId(
      String? explicitCallId,
      ) {
    final String? normalizedExplicit = _normalizeOptionalString(
      explicitCallId,
    );

    if (normalizedExplicit != null) {
      return normalizedExplicit;
    }

    return currentCallId;
  }

  String? _normalizeOptionalString(
      String? value,
      ) {
    if (value == null) {
      return null;
    }

    final String normalized = value.trim();

    return normalized.isEmpty ? null : normalized;
  }

  // ===========================================================
  // RESET
  //
  // Presentation reset only.
  //
  // This does NOT terminate CallService.
  // Call lifecycle must already be handled by CallService.
  // ===========================================================

  void reset() {
    if (_isDisposed) {
      return;
    }

    _operationGeneration++;

    final bool hadBusyOperation = isBusy;

    final bool stateChanged =
        _state != const CallState();

    _state = const CallState();

    _isStartingCall = false;

    _isAcceptingCall = false;

    _isEndingCall = false;

    if (stateChanged || hadBusyOperation) {
      _safeNotifyListeners();
    }
  }

  // ===========================================================
  // SUBSCRIPTION CLEANUP
  // ===========================================================

  Future<void> _cancelSubscriptions() async {
    final StreamSubscription<String>? statusSubscription =
        _statusSubscription;

    final StreamSubscription<int>? durationSubscription =
        _durationSubscription;

    _statusSubscription = null;

    _durationSubscription = null;

    if (statusSubscription != null) {
      try {
        await statusSubscription.cancel();
      } catch (error, stackTrace) {
        _reportError(
          'cancel status subscription',
          error,
          stackTrace,
        );
      }
    }

    if (durationSubscription != null) {
      try {
        await durationSubscription.cancel();
      } catch (error, stackTrace) {
        _reportError(
          'cancel duration subscription',
          error,
          stackTrace,
        );
      }
    }
  }

  // ===========================================================
  // ERROR LOGGING
  // ===========================================================

  void _reportError(
      String source,
      Object error, [
        StackTrace? stackTrace,
      ]) {
    debugPrint(
      'JR CALL [CallProvider/$source] '
          'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL '
            '[CallProvider/$source]',
        stackTrace: stackTrace,
      );
    }
  }

  // ===========================================================
  // SAFE NOTIFICATION
  // ===========================================================

  void _safeNotifyListeners() {
    if (_isDisposed) {
      return;
    }

    notifyListeners();
  }

  // ===========================================================
  // DISPOSE
  //
  // CallProvider does NOT dispose CallService because CallService
  // may be shared/singleton-owned outside this provider.
  // ===========================================================

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;

    _operationGeneration++;

    _isStartingCall = false;

    _isAcceptingCall = false;

    _isEndingCall = false;

    _initializationFuture = null;

    final StreamSubscription<String>? statusSubscription =
        _statusSubscription;

    final StreamSubscription<int>? durationSubscription =
        _durationSubscription;

    _statusSubscription = null;

    _durationSubscription = null;

    if (statusSubscription != null) {
      unawaited(
        statusSubscription.cancel(),
      );
    }

    if (durationSubscription != null) {
      unawaited(
        durationSubscription.cancel(),
      );
    }

    super.dispose();
  }
}

// ===========================================================
// END OF FILE
//
// FILE 41 PRODUCTION CONTRACT:
//
// ✓ Existing CallProvider constructor preserved.
// ✓ Existing state getter preserved.
// ✓ Existing callService getter preserved.
//
// ✓ initialize() preserved.
// ✓ startOutgoingCall() preserved.
// ✓ incomingCall() preserved.
// ✓ acceptCall() preserved.
// ✓ rejectCall() preserved.
// ✓ cancelCall() preserved.
// ✓ endCall() preserved.
// ✓ updateNetwork() preserved.
// ✓ connectCall() preserved.
// ✓ reconnecting() preserved.
// ✓ connectionFailed() preserved.
// ✓ updateRemoteUser() preserved.
// ✓ reset() preserved.
//
// ✓ Existing CallServiceStatus mapping semantics preserved.
// ✓ CallService remains status authority.
// ✓ CallService remains duration authority.
// ✓ No fake connected state after start/accept.
//
// ✓ Single-flight initialization added.
// ✓ Duplicate stream binding prevented.
// ✓ Failed initialization cleans subscriptions.
// ✓ Conflicting UI lifecycle operations blocked.
// ✓ Stale async completion protection added.
// ✓ Reset cannot be overwritten by an older provider operation.
// ✓ Old operation finally cannot clear a newer operation guard.
//
// ✓ Negative duration normalized.
// ✓ Negative network metrics normalized.
// ✓ NaN/infinite bitrate values normalized.
// ✓ Duplicate immutable state notifications suppressed.
// ✓ Current call ID normalized safely.
//
// ✓ Provider reset remains presentation-only.
// ✓ CallService is not disposed by provider.
//
// ✓ No timer ownership.
// ✓ No history persistence.
// ✓ No signaling ownership.
// ✓ No ICE ownership.
// ✓ No recovery ownership.
// ✓ No network-monitor ownership.
// ✓ No WebRTC ownership.
// ✓ No media ownership.
// ===========================================================