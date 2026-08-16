// ===========================================================
// JR CALL
// File: call_provider.dart
// Location: lib/providers/call_provider.dart
//
// Description:
// Production call-state bridge between Presentation Layer
// and the central CallService.
//
// Architecture:
// UI -> CallProvider -> CallService -> Connection/Recovery/WebRTC...
//
// Ownership:
// - CallService owns call lifecycle
// - CallService owns call duration timing
// - SignalingService owns Firestore signaling/history persistence
// - IceManager owns ICE
// - RecoveryManager owns recovery
// - NetworkManager owns network monitoring
// - AudioProvider owns audio UI state
// - VideoProvider owns video UI state
//
// This provider does NOT duplicate:
// - Call timers
// - Call history creation
// - Signaling
// - ICE
// - Recovery
// - Network monitoring
// - WebRTC operations
// ===========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/network_model.dart' as network;
import '../services/call/call_service.dart';
import 'call_state.dart';

class CallProvider extends ChangeNotifier {
  CallProvider({CallService? callService})
    : _callService = callService ?? CallService();

  // ===========================================================
  // Dependencies
  // ===========================================================

  final CallService _callService;

  // ===========================================================
  // State
  // ===========================================================

  CallState _state = const CallState();

  CallState get state => _state;

  CallService get callService => _callService;

  // ===========================================================
  // Runtime Guards
  // ===========================================================

  bool _isInitialized = false;
  bool _isDisposed = false;

  bool _isStartingCall = false;
  bool _isAcceptingCall = false;
  bool _isEndingCall = false;

  bool get isInitialized => _isInitialized;

  bool get isStartingCall => _isStartingCall;

  bool get isAcceptingCall => _isAcceptingCall;

  bool get isEndingCall => _isEndingCall;

  bool get hasActiveCall => _callService.currentCallId != null;

  String? get currentCallId => _callService.currentCallId;

  // ===========================================================
  // Stream Subscriptions
  // ===========================================================

  StreamSubscription<String>? _statusSubscription;
  StreamSubscription<int>? _durationSubscription;

  // ===========================================================
  // Initialization
  // ===========================================================

  Future<void> initialize() async {
    if (_isDisposed || _isInitialized) {
      return;
    }

    await _callService.initialize();

    if (_isDisposed) {
      return;
    }

    await _statusSubscription?.cancel();
    await _durationSubscription?.cancel();

    _statusSubscription = _callService.callStatusStream.listen(
      _handleCallServiceStatus,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('JR CALL [CallProvider] status stream error: $error');

        debugPrintStack(
          label: 'JR CALL [CallProvider status stream]',
          stackTrace: stackTrace,
        );

        _setConnectionState(CallConnectionState.failed);
      },
    );

    _durationSubscription = _callService.callDurationStream.listen(
      _handleDuration,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('JR CALL [CallProvider] duration stream error: $error');

        debugPrintStack(
          label: 'JR CALL [CallProvider duration stream]',
          stackTrace: stackTrace,
        );
      },
    );

    _isInitialized = true;

    _safeNotifyListeners();
  }

  Future<void> _ensureInitialized() async {
    if (_isDisposed || _isInitialized) {
      return;
    }

    await initialize();
  }

  // ===========================================================
  // Outgoing Call
  // ===========================================================

  Future<String?> startOutgoingCall({
    required String localUid,
    required String remoteUid,
    required String remoteName,
    String remotePhoto = '',
    bool isVideoCall = false,
  }) async {
    if (_isDisposed || _isStartingCall || _isAcceptingCall || _isEndingCall) {
      return null;
    }

    final String normalizedLocalUid = localUid.trim();
    final String normalizedRemoteUid = remoteUid.trim();

    if (normalizedLocalUid.isEmpty ||
        normalizedRemoteUid.isEmpty ||
        normalizedLocalUid == normalizedRemoteUid) {
      _setConnectionState(CallConnectionState.failed);

      return null;
    }

    _isStartingCall = true;
    _safeNotifyListeners();

    try {
      await _ensureInitialized();

      if (_isDisposed) {
        return null;
      }

      _state = _state.copyWith(
        connectionState: CallConnectionState.connecting,
        localUid: normalizedLocalUid,
        remoteUid: normalizedRemoteUid,
        remoteName: remoteName.trim(),
        remotePhoto: remotePhoto.trim(),
        duration: 0,
      );

      _safeNotifyListeners();

      final String? callId = await _callService.startCall(
        callerId: normalizedLocalUid,
        receiverId: normalizedRemoteUid,
        isVideoCall: isVideoCall,
      );

      if (_isDisposed) {
        return null;
      }

      if (callId == null || callId.trim().isEmpty) {
        if (_state.connectionState != CallConnectionState.failed) {
          _setConnectionState(CallConnectionState.failed);
        }

        return null;
      }

      return callId;
    } catch (error, stackTrace) {
      debugPrint('JR CALL [CallProvider] start call error: $error');

      debugPrintStack(
        label: 'JR CALL [CallProvider start call]',
        stackTrace: stackTrace,
      );

      _setConnectionState(CallConnectionState.failed);

      return null;
    } finally {
      _isStartingCall = false;
      _safeNotifyListeners();
    }
  }

  // ===========================================================
  // Incoming Call Presentation
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

    _state = _state.copyWith(
      connectionState: CallConnectionState.incoming,
      localUid: localUid.trim(),
      remoteUid: remoteUid.trim(),
      remoteName: remoteName.trim(),
      remotePhoto: remotePhoto.trim(),
      duration: 0,
    );

    _safeNotifyListeners();
  }

  // ===========================================================
  // Accept Incoming Call
  // ===========================================================

  Future<void> acceptCall({required String callId}) async {
    if (_isDisposed || _isAcceptingCall || _isStartingCall || _isEndingCall) {
      return;
    }

    final String normalizedCallId = callId.trim();

    if (normalizedCallId.isEmpty) {
      _setConnectionState(CallConnectionState.failed);
      return;
    }

    _isAcceptingCall = true;
    _safeNotifyListeners();

    try {
      await _ensureInitialized();

      if (_isDisposed) {
        return;
      }

      _setConnectionState(CallConnectionState.connecting);

      await _callService.acceptCall(callId: normalizedCallId);
    } catch (error, stackTrace) {
      debugPrint('JR CALL [CallProvider] accept call error: $error');

      debugPrintStack(
        label: 'JR CALL [CallProvider accept call]',
        stackTrace: stackTrace,
      );

      _setConnectionState(CallConnectionState.failed);
    } finally {
      _isAcceptingCall = false;
      _safeNotifyListeners();
    }
  }

  // ===========================================================
  // Reject Incoming Call
  // ===========================================================

  Future<void> rejectCall({required String callId}) async {
    if (_isDisposed || _isEndingCall) {
      return;
    }

    final String normalizedCallId = callId.trim();

    if (normalizedCallId.isEmpty) {
      return;
    }

    _isEndingCall = true;
    _safeNotifyListeners();

    try {
      await _ensureInitialized();

      if (_isDisposed) {
        return;
      }

      await _callService.rejectCall(callId: normalizedCallId);
    } catch (error, stackTrace) {
      debugPrint('JR CALL [CallProvider] reject call error: $error');

      debugPrintStack(
        label: 'JR CALL [CallProvider reject call]',
        stackTrace: stackTrace,
      );
    } finally {
      _isEndingCall = false;
      _safeNotifyListeners();
    }
  }

  // ===========================================================
  // Cancel Outgoing Call
  // ===========================================================

  Future<void> cancelCall({String? callId}) async {
    if (_isDisposed || _isEndingCall) {
      return;
    }

    final String? explicitCallId = callId?.trim();

    final String? resolvedCallId =
        explicitCallId != null && explicitCallId.isNotEmpty
        ? explicitCallId
        : _callService.currentCallId;

    if (resolvedCallId == null || resolvedCallId.isEmpty) {
      return;
    }

    _isEndingCall = true;
    _safeNotifyListeners();

    try {
      await _ensureInitialized();

      if (_isDisposed) {
        return;
      }

      await _callService.cancelCall(callId: resolvedCallId);
    } catch (error, stackTrace) {
      debugPrint('JR CALL [CallProvider] cancel call error: $error');

      debugPrintStack(
        label: 'JR CALL [CallProvider cancel call]',
        stackTrace: stackTrace,
      );
    } finally {
      _isEndingCall = false;
      _safeNotifyListeners();
    }
  }

  // ===========================================================
  // End Active Call
  // ===========================================================

  Future<void> endCall({String? callId, String status = 'COMPLETED'}) async {
    if (_isDisposed || _isEndingCall) {
      return;
    }

    final String? explicitCallId = callId?.trim();

    final String? resolvedCallId =
        explicitCallId != null && explicitCallId.isNotEmpty
        ? explicitCallId
        : _callService.currentCallId;

    if (resolvedCallId == null || resolvedCallId.isEmpty) {
      reset();
      return;
    }

    _isEndingCall = true;
    _safeNotifyListeners();

    try {
      await _ensureInitialized();

      if (_isDisposed) {
        return;
      }

      await _callService.endCall(
        callId: resolvedCallId,
        status: status.trim().isEmpty ? 'COMPLETED' : status.trim(),
      );
    } catch (error, stackTrace) {
      debugPrint('JR CALL [CallProvider] end call error: $error');

      debugPrintStack(
        label: 'JR CALL [CallProvider end call]',
        stackTrace: stackTrace,
      );

      _setConnectionState(CallConnectionState.failed);
    } finally {
      _isEndingCall = false;
      _safeNotifyListeners();
    }
  }

  // ===========================================================
  // CallService Status Synchronization
  // ===========================================================

  void _handleCallServiceStatus(String rawStatus) {
    if (_isDisposed) {
      return;
    }

    final String status = rawStatus.trim().toUpperCase();

    switch (status) {
      case CallServiceStatus.preparing:
      case CallServiceStatus.calling:
      case CallServiceStatus.ringing:
      case CallServiceStatus.connecting:
        _setConnectionState(CallConnectionState.connecting);
        break;

      case CallServiceStatus.connected:
      case CallServiceStatus.reconnected:
        _setConnectionState(CallConnectionState.connected);
        break;

      case CallServiceStatus.reconnecting:
      case CallServiceStatus.networkLost:
        _setConnectionState(CallConnectionState.reconnecting);
        break;

      case CallServiceStatus.userBusy:
      case CallServiceStatus.timeout:
      case CallServiceStatus.failed:
        _setConnectionState(CallConnectionState.failed);
        break;

      case CallServiceStatus.rejected:
      case CallServiceStatus.declined:
      case CallServiceStatus.cancelled:
      case CallServiceStatus.ended:
        _setConnectionState(CallConnectionState.ended);
        break;

      case CallServiceStatus.idle:
        break;

      default:
        debugPrint('JR CALL [CallProvider] unknown call status: $status');
        break;
    }
  }

  void _handleDuration(int duration) {
    if (_isDisposed) {
      return;
    }

    final int safeDuration = duration < 0 ? 0 : duration;

    if (_state.duration == safeDuration) {
      return;
    }

    _state = _state.copyWith(duration: safeDuration);

    _safeNotifyListeners();
  }

  // ===========================================================
  // Network Metrics Synchronization
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

    final NetworkQuality mappedQuality;

    switch (quality) {
      case network.NetworkQuality.excellent:
        mappedQuality = NetworkQuality.excellent;
        break;

      case network.NetworkQuality.good:
        mappedQuality = NetworkQuality.good;
        break;

      case network.NetworkQuality.fair:
        mappedQuality = NetworkQuality.fair;
        break;

      case network.NetworkQuality.poor:
        mappedQuality = NetworkQuality.poor;
        break;

      case network.NetworkQuality.offline:
        mappedQuality = NetworkQuality.offline;
        break;
    }

    _state = _state.copyWith(
      networkQuality: mappedQuality,
      uploadBitrate: upload < 0 ? 0.0 : upload,
      downloadBitrate: download < 0 ? 0.0 : download,
      ping: ping < 0 ? 0 : ping,
    );

    _safeNotifyListeners();
  }

  // ===========================================================
  // Explicit State Synchronization Helpers
  // ===========================================================

  void connectCall() {
    _setConnectionState(CallConnectionState.connected);
  }

  void reconnecting() {
    _setConnectionState(CallConnectionState.reconnecting);
  }

  void connectionFailed() {
    _setConnectionState(CallConnectionState.failed);
  }

  void _setConnectionState(CallConnectionState connectionState) {
    if (_isDisposed || _state.connectionState == connectionState) {
      return;
    }

    _state = _state.copyWith(connectionState: connectionState);

    _safeNotifyListeners();
  }

  // ===========================================================
  // Presentation Metadata
  // ===========================================================

  void updateRemoteUser({
    String? remoteUid,
    String? remoteName,
    String? remotePhoto,
  }) {
    if (_isDisposed) {
      return;
    }

    _state = _state.copyWith(
      remoteUid: remoteUid?.trim() ?? _state.remoteUid,
      remoteName: remoteName?.trim() ?? _state.remoteName,
      remotePhoto: remotePhoto?.trim() ?? _state.remotePhoto,
    );

    _safeNotifyListeners();
  }

  // ===========================================================
  // Reset
  // ===========================================================

  void reset() {
    if (_isDisposed) {
      return;
    }

    _state = const CallState();

    _isStartingCall = false;
    _isAcceptingCall = false;
    _isEndingCall = false;

    _safeNotifyListeners();
  }

  // ===========================================================
  // Safe Notification
  // ===========================================================

  void _safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  // ===========================================================
  // Dispose
  // ===========================================================

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;

    final StreamSubscription<String>? statusSubscription = _statusSubscription;
    final StreamSubscription<int>? durationSubscription = _durationSubscription;

    _statusSubscription = null;
    _durationSubscription = null;

    if (statusSubscription != null) {
      unawaited(statusSubscription.cancel());
    }

    if (durationSubscription != null) {
      unawaited(durationSubscription.cancel());
    }

    super.dispose();
  }
}
