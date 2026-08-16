// ===========================================================
// JR CALL
// File: call_screen_provider.dart
// Location: lib/providers/call_screen_provider.dart
//
// Description:
// Presentation-layer provider for the active call screens.
//
// Responsibilities:
// - Bridge CallService state/streams to call UI
// - Expose local/remote WebRTC media streams
// - Start, accept, reject, cancel, and end calls through CallService
// - Maintain UI-only loading/error/status state
// - Prevent duplicate UI actions
//
// Architecture Rules:
// - No Firestore access
// - No direct signaling
// - No direct ICE upload/listener
// - No recovery implementation
// - No duplicate call timer
// - No duplicate WebRTC peer connection
// - CallService remains the single call-lifecycle owner
// ===========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/call/call_service.dart';

class CallScreenProvider extends ChangeNotifier {
  CallScreenProvider({CallService? callService})
    : _callService = callService ?? CallService();

  // ===========================================================
  // Dependencies
  // ===========================================================

  final CallService _callService;

  CallService get callService => _callService;

  // ===========================================================
  // Subscriptions
  // ===========================================================

  StreamSubscription<String>? _statusSubscription;
  StreamSubscription<int>? _durationSubscription;
  StreamSubscription<MediaStream?>? _localStreamSubscription;
  StreamSubscription<MediaStream?>? _remoteStreamSubscription;

  // ===========================================================
  // Lifecycle State
  // ===========================================================

  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _isDisposed = false;

  Future<void>? _initializationFuture;

  bool get isInitialized => _isInitialized;
  bool get isDisposed => _isDisposed;

  // ===========================================================
  // Operation Guards
  // ===========================================================

  bool _isStarting = false;
  bool _isAccepting = false;
  bool _isRejecting = false;
  bool _isCancelling = false;
  bool _isEnding = false;

  bool get isStarting => _isStarting;
  bool get isAccepting => _isAccepting;
  bool get isRejecting => _isRejecting;
  bool get isCancelling => _isCancelling;
  bool get isEnding => _isEnding;

  bool get isBusy =>
      _isStarting || _isAccepting || _isRejecting || _isCancelling || _isEnding;

  // ===========================================================
  // Call State
  // ===========================================================

  String _status = CallServiceStatus.idle;
  int _durationSeconds = 0;

  String? _callId;
  String? _localUserId;
  String? _remoteUserId;

  String _remoteName = '';
  String _remotePhoto = '';

  bool _isVideoCall = true;

  String? _errorMessage;

  // ===========================================================
  // Media State
  // ===========================================================

  MediaStream? _localStream;
  MediaStream? _remoteStream;

  // ===========================================================
  // Public Getters
  // ===========================================================

  String get status => _status;

  int get durationSeconds => _durationSeconds;

  String? get callId => _callId;

  String? get localUserId => _localUserId;

  String? get remoteUserId => _remoteUserId;

  String get remoteName => _remoteName;

  String get remotePhoto => _remotePhoto;

  bool get isVideoCall => _isVideoCall;

  String? get errorMessage => _errorMessage;

  MediaStream? get localStream => _localStream;

  MediaStream? get remoteStream => _remoteStream;

  CallRole get role => _callService.currentRole;

  bool get isCaller => role == CallRole.caller;

  bool get isReceiver => role == CallRole.receiver;

  bool get hasActiveCall => _callService.isCallActive || _callId != null;

  bool get isConnected =>
      _status == CallServiceStatus.connected ||
      _status == CallServiceStatus.reconnected;

  bool get isConnecting =>
      _status == CallServiceStatus.preparing ||
      _status == CallServiceStatus.calling ||
      _status == CallServiceStatus.ringing ||
      _status == CallServiceStatus.connecting ||
      _status == CallServiceStatus.reconnecting;

  bool get hasRemoteVideo => _remoteStream?.getVideoTracks().isNotEmpty == true;

  bool get hasLocalVideo => _localStream?.getVideoTracks().isNotEmpty == true;

  bool get hasRemoteAudio => _remoteStream?.getAudioTracks().isNotEmpty == true;

  bool get hasLocalAudio => _localStream?.getAudioTracks().isNotEmpty == true;

  // ===========================================================
  // Initialization
  // ===========================================================

  Future<void> initialize() async {
    _ensureUsable();

    if (_isInitialized) {
      return;
    }

    if (_isInitializing) {
      final Future<void>? pendingInitialization = _initializationFuture;

      if (pendingInitialization != null) {
        await pendingInitialization;
      }

      return;
    }

    _isInitializing = true;

    final Future<void> initialization = _performInitialization();
    _initializationFuture = initialization;

    try {
      await initialization;
    } finally {
      _isInitializing = false;
      _initializationFuture = null;
    }
  }

  Future<void> _performInitialization() async {
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
        _handleStatus,
        onError: (Object error, StackTrace stackTrace) {
          _handleError('Call status stream', error, stackTrace);
        },
      );

      _durationSubscription = _callService.callDurationStream.listen(
        _handleDuration,
        onError: (Object error, StackTrace stackTrace) {
          _handleError('Call duration stream', error, stackTrace);
        },
      );

      _localStreamSubscription = _callService.webrtc.localStream$.listen(
        _handleLocalStream,
        onError: (Object error, StackTrace stackTrace) {
          _handleError('Local media stream', error, stackTrace);
        },
      );

      _remoteStreamSubscription = _callService.webrtc.remoteStream$.listen(
        _handleRemoteStream,
        onError: (Object error, StackTrace stackTrace) {
          _handleError('Remote media stream', error, stackTrace);
        },
      );

      if (_isDisposed) {
        await _cancelSubscriptions();
        return;
      }

      _syncFromCallService();

      _isInitialized = true;
      _notifySafely();
    } catch (error, stackTrace) {
      if (!_isDisposed) {
        _handleError('CallScreenProvider initialization', error, stackTrace);
      }

      rethrow;
    }
  }

  // ===========================================================
  // Outgoing Call
  // ===========================================================

  Future<String?> startCall({
    required String callerId,
    required String receiverId,
    String remoteName = '',
    String remotePhoto = '',
    bool isVideoCall = true,
  }) async {
    _ensureUsable();
    await _ensureInitialized();

    if (_isDisposed || isBusy || hasActiveCall) {
      return null;
    }

    final String localId = callerId.trim();
    final String remoteId = receiverId.trim();

    if (localId.isEmpty || remoteId.isEmpty || localId == remoteId) {
      _setError('Invalid caller or receiver information.');
      return null;
    }

    _isStarting = true;
    _errorMessage = null;

    _localUserId = localId;
    _remoteUserId = remoteId;
    _remoteName = remoteName.trim();
    _remotePhoto = remotePhoto.trim();
    _isVideoCall = isVideoCall;
    _durationSeconds = 0;

    _notifySafely();

    try {
      final String? createdCallId = await _callService.startCall(
        callerId: localId,
        receiverId: remoteId,
        isVideoCall: isVideoCall,
      );

      if (_isDisposed) {
        return null;
      }

      if (createdCallId == null || createdCallId.trim().isEmpty) {
        if (_status != CallServiceStatus.userBusy) {
          _setError('Unable to start the call.');
        }

        return null;
      }

      _callId = createdCallId.trim();

      _syncFromCallService();
      _notifySafely();

      return _callId;
    } catch (error, stackTrace) {
      _handleError('Start call', error, stackTrace);

      return null;
    } finally {
      _isStarting = false;
      _notifySafely();
    }
  }

  // ===========================================================
  // Prepare Incoming Call UI
  // ===========================================================

  void prepareIncomingCall({
    required String callId,
    required String localUserId,
    required String remoteUserId,
    String remoteName = '',
    String remotePhoto = '',
    bool isVideoCall = true,
  }) {
    _ensureUsable();

    final String normalizedCallId = callId.trim();
    final String normalizedLocalUserId = localUserId.trim();
    final String normalizedRemoteUserId = remoteUserId.trim();

    if (normalizedCallId.isEmpty ||
        normalizedLocalUserId.isEmpty ||
        normalizedRemoteUserId.isEmpty) {
      return;
    }

    _callId = normalizedCallId;
    _localUserId = normalizedLocalUserId;
    _remoteUserId = normalizedRemoteUserId;
    _remoteName = remoteName.trim();
    _remotePhoto = remotePhoto.trim();
    _isVideoCall = isVideoCall;
    _durationSeconds = 0;
    _errorMessage = null;

    _setStatus(CallServiceStatus.ringing);
  }

  // ===========================================================
  // Accept Incoming Call
  // ===========================================================

  Future<bool> acceptCall({String? callId}) async {
    _ensureUsable();
    await _ensureInitialized();

    if (_isDisposed || isBusy) {
      return false;
    }

    final String targetCallId = (callId ?? _callId ?? '').trim();

    if (targetCallId.isEmpty) {
      _setError('Call ID is missing.');
      return false;
    }

    _isAccepting = true;
    _errorMessage = null;
    _callId = targetCallId;

    _notifySafely();

    try {
      await _callService.acceptCall(callId: targetCallId);

      if (_isDisposed) {
        return false;
      }

      _syncFromCallService();

      return _status != CallServiceStatus.failed;
    } catch (error, stackTrace) {
      _handleError('Accept call', error, stackTrace);

      return false;
    } finally {
      _isAccepting = false;
      _notifySafely();
    }
  }

  // ===========================================================
  // Reject Incoming Call
  // ===========================================================

  Future<void> rejectCall({String? callId}) async {
    _ensureUsable();
    await _ensureInitialized();

    if (_isDisposed || isBusy) {
      return;
    }

    final String targetCallId = (callId ?? _callId ?? '').trim();

    if (targetCallId.isEmpty) {
      return;
    }

    _isRejecting = true;
    _errorMessage = null;

    _notifySafely();

    try {
      await _callService.rejectCall(callId: targetCallId);
    } catch (error, stackTrace) {
      _handleError('Reject call', error, stackTrace);
    } finally {
      _isRejecting = false;

      if (!_isDisposed) {
        _syncFromCallService();
      }

      _notifySafely();
    }
  }

  // ===========================================================
  // Cancel Outgoing Call
  // ===========================================================

  Future<void> cancelCall({String? callId}) async {
    _ensureUsable();
    await _ensureInitialized();

    if (_isDisposed || isBusy) {
      return;
    }

    final String targetCallId = (callId ?? _callId ?? '').trim();

    if (targetCallId.isEmpty) {
      return;
    }

    _isCancelling = true;
    _errorMessage = null;

    _notifySafely();

    try {
      await _callService.cancelCall(callId: targetCallId);
    } catch (error, stackTrace) {
      _handleError('Cancel call', error, stackTrace);
    } finally {
      _isCancelling = false;

      if (!_isDisposed) {
        _syncFromCallService();
      }

      _notifySafely();
    }
  }

  // ===========================================================
  // End Active Call
  // ===========================================================

  Future<void> endCall({String status = 'COMPLETED'}) async {
    _ensureUsable();
    await _ensureInitialized();

    if (_isDisposed || isBusy) {
      return;
    }

    final String targetCallId = (_callService.currentCallId ?? _callId ?? '')
        .trim();

    if (targetCallId.isEmpty) {
      _resetUiSession(preserveStatus: false);
      return;
    }

    final String normalizedStatus = status.trim().isEmpty
        ? 'COMPLETED'
        : status.trim();

    _isEnding = true;
    _errorMessage = null;

    _notifySafely();

    try {
      await _callService.endCall(
        callId: targetCallId,
        status: normalizedStatus,
      );
    } catch (error, stackTrace) {
      _handleError('End call', error, stackTrace);
    } finally {
      _isEnding = false;

      if (!_isDisposed) {
        _syncFromCallService();
      }

      _notifySafely();
    }
  }

  // ===========================================================
  // Stream Handlers
  // ===========================================================

  void _handleStatus(String status) {
    if (_isDisposed) {
      return;
    }

    final String normalized = status.trim().toUpperCase();

    if (normalized.isEmpty) {
      return;
    }

    _status = normalized;

    _syncFromCallService();

    if (_isTerminalStatus(normalized)) {
      _durationSeconds = 0;
      _localStream = null;
      _remoteStream = null;
    }

    _notifySafely();
  }

  void _handleDuration(int duration) {
    if (_isDisposed) {
      return;
    }

    final int safeDuration = duration < 0 ? 0 : duration;

    if (_durationSeconds == safeDuration) {
      return;
    }

    _durationSeconds = safeDuration;
    _notifySafely();
  }

  void _handleLocalStream(MediaStream? stream) {
    if (_isDisposed || identical(_localStream, stream)) {
      return;
    }

    _localStream = stream;
    _notifySafely();
  }

  void _handleRemoteStream(MediaStream? stream) {
    if (_isDisposed || identical(_remoteStream, stream)) {
      return;
    }

    _remoteStream = stream;
    _notifySafely();
  }

  // ===========================================================
  // State Synchronization
  // ===========================================================

  void _syncFromCallService() {
    if (_isDisposed) {
      return;
    }

    _callId = _callService.currentCallId ?? _callId;

    _localUserId = _callService.currentUserId ?? _localUserId;

    _remoteUserId = _callService.currentPeerId ?? _remoteUserId;

    _isVideoCall = _callService.isVideoCall;

    final int serviceDuration = _callService.callDurationSeconds;
    _durationSeconds = serviceDuration < 0 ? 0 : serviceDuration;
  }

  // ===========================================================
  // Status Helpers
  // ===========================================================

  void _setStatus(String value) {
    if (_isDisposed) {
      return;
    }

    final String normalized = value.trim().toUpperCase();

    if (normalized.isEmpty || normalized == _status) {
      return;
    }

    _status = normalized;
    _notifySafely();
  }

  bool _isTerminalStatus(String status) {
    switch (status) {
      case CallServiceStatus.rejected:
      case CallServiceStatus.declined:
      case CallServiceStatus.cancelled:
      case CallServiceStatus.timeout:
      case CallServiceStatus.failed:
      case CallServiceStatus.ended:
        return true;

      default:
        return false;
    }
  }

  // ===========================================================
  // Error Handling
  // ===========================================================

  void clearError() {
    if (_isDisposed || _errorMessage == null) {
      return;
    }

    _errorMessage = null;
    _notifySafely();
  }

  void _setError(String message) {
    if (_isDisposed) {
      return;
    }

    _errorMessage = message.trim().isEmpty ? 'Unknown call error.' : message;
    _notifySafely();
  }

  void _handleError(String source, Object error, [StackTrace? stackTrace]) {
    if (_isDisposed) {
      return;
    }

    _errorMessage = error.toString();

    debugPrint('JR CALL [$source] error: $error');

    if (stackTrace != null) {
      debugPrintStack(label: 'JR CALL [$source]', stackTrace: stackTrace);
    }

    _notifySafely();
  }

  // ===========================================================
  // Initialization Guard
  // ===========================================================

  Future<void> _ensureInitialized() async {
    if (_isDisposed) {
      return;
    }

    if (!_isInitialized) {
      await initialize();
    }
  }

  void _ensureUsable() {
    if (_isDisposed) {
      throw StateError('CallScreenProvider has already been disposed.');
    }
  }

  // ===========================================================
  // UI Reset
  // ===========================================================

  void reset({bool preserveRemoteIdentity = false}) {
    _ensureUsable();

    _resetUiSession(
      preserveStatus: false,
      preserveRemoteIdentity: preserveRemoteIdentity,
    );
  }

  void _resetUiSession({
    required bool preserveStatus,
    bool preserveRemoteIdentity = false,
  }) {
    if (_isDisposed) {
      return;
    }

    if (!preserveStatus) {
      _status = CallServiceStatus.idle;
    }

    _durationSeconds = 0;

    _callId = null;
    _localUserId = null;

    if (!preserveRemoteIdentity) {
      _remoteUserId = null;
      _remoteName = '';
      _remotePhoto = '';
    }

    _isVideoCall = true;

    _localStream = null;
    _remoteStream = null;

    _errorMessage = null;

    _isStarting = false;
    _isAccepting = false;
    _isRejecting = false;
    _isCancelling = false;
    _isEnding = false;

    _notifySafely();
  }

  // ===========================================================
  // Subscription Cleanup
  // ===========================================================

  Future<void> _cancelSubscriptions() async {
    final StreamSubscription<String>? statusSubscription = _statusSubscription;
    final StreamSubscription<int>? durationSubscription = _durationSubscription;
    final StreamSubscription<MediaStream?>? localStreamSubscription =
        _localStreamSubscription;
    final StreamSubscription<MediaStream?>? remoteStreamSubscription =
        _remoteStreamSubscription;

    _statusSubscription = null;
    _durationSubscription = null;
    _localStreamSubscription = null;
    _remoteStreamSubscription = null;

    await Future.wait<void>([
      if (statusSubscription != null) statusSubscription.cancel(),
      if (durationSubscription != null) durationSubscription.cancel(),
      if (localStreamSubscription != null) localStreamSubscription.cancel(),
      if (remoteStreamSubscription != null) remoteStreamSubscription.cancel(),
    ]);
  }

  // ===========================================================
  // Safe Notification
  // ===========================================================

  void _notifySafely() {
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
    _isInitialized = false;

    unawaited(_cancelSubscriptions());

    _localStream = null;
    _remoteStream = null;

    _callId = null;
    _localUserId = null;
    _remoteUserId = null;

    super.dispose();
  }
}
