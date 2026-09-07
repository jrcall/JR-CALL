// ===========================================================
// JR CALL
// File: call_screen_provider.dart
// Location: lib/providers/call_screen_provider.dart
//
// MASTER PRODUCTION CALL SCREEN PROVIDER
//
// RESPONSIBILITIES:
//
// - Bridge CallService lifecycle state to active-call UI.
// - Bridge CallService duration to active-call UI.
// - Expose CallService-owned local/remote WebRTC streams.
// - Recover already-existing WebRTC media for late UI binding.
// - Start / accept / reject / cancel / end through CallService.
// - Maintain UI-only identity/status/loading/error state.
// - Prevent duplicate/conflicting UI actions.
// - Protect UI from stale asynchronous completions.
// - Protect UI from stale/disposed media references.
//
// OWNERSHIP:
//
// CallService:
// - Call lifecycle.
// - Call duration.
// - Start / accept / reject / cancel / end.
//
// WebRTCService:
// - Local / remote MediaStream ownership.
// - PeerConnection ownership.
//
// SignalingService:
// - Firestore signaling/history.
//
// IceManager:
// - ICE.
//
// RecoveryManager:
// - Recovery.
//
// CallScreenProvider:
// - Presentation bridge only.
//
// IMPORTANT:
//
// - No Firestore access.
// - No direct signaling.
// - No ICE ownership.
// - No recovery implementation.
// - No duplicate call timer.
// - No PeerConnection creation.
// - No MediaStream creation/disposal.
// - Never mark connected only because start/accept completed.
// ===========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/call/call_service.dart';

class CallScreenProvider extends ChangeNotifier {
  CallScreenProvider({
    CallService? callService,
  }) : _callService = callService ?? CallService();

  // ===========================================================
  // DEPENDENCY
  // ===========================================================

  final CallService _callService;

  CallService get callService => _callService;

  // ===========================================================
  // SUBSCRIPTIONS
  // ===========================================================

  StreamSubscription<String>? _statusSubscription;
  StreamSubscription<int>? _durationSubscription;
  StreamSubscription<MediaStream?>? _localStreamSubscription;
  StreamSubscription<MediaStream?>? _remoteStreamSubscription;

  // ===========================================================
  // LIFECYCLE
  // ===========================================================

  bool _isInitialized = false;
  bool _isDisposed = false;

  Future<void>? _initializationFuture;

  bool get isInitialized => _isInitialized;
  bool get isDisposed => _isDisposed;

  // ===========================================================
  // OPERATION GUARDS
  // ===========================================================

  bool _isStarting = false;
  bool _isAccepting = false;
  bool _isRejecting = false;
  bool _isCancelling = false;
  bool _isEnding = false;

  int _operationGeneration = 0;

  bool get isStarting => _isStarting;
  bool get isAccepting => _isAccepting;
  bool get isRejecting => _isRejecting;
  bool get isCancelling => _isCancelling;
  bool get isEnding => _isEnding;

  bool get isBusy =>
      _isStarting ||
          _isAccepting ||
          _isRejecting ||
          _isCancelling ||
          _isEnding;

  // ===========================================================
  // CALL PRESENTATION STATE
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
  // MEDIA REFERENCES
  //
  // Non-owning references only.
  // WebRTCService owns these streams.
  // ===========================================================

  MediaStream? _localStream;
  MediaStream? _remoteStream;

  // ===========================================================
  // PUBLIC GETTERS
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

  bool get hasActiveCall {
    if (_callService.isCallActive) {
      return true;
    }

    final String? currentId = _normalizedOptionalString(
      _callId,
    );

    if (currentId == null) {
      return false;
    }

    return !_isTerminalStatus(
      _status,
    );
  }

  bool get isConnected =>
      _status == CallServiceStatus.connected ||
          _status == CallServiceStatus.reconnected;

  bool get isConnecting =>
      _status == CallServiceStatus.preparing ||
          _status == CallServiceStatus.calling ||
          _status == CallServiceStatus.ringing ||
          _status == CallServiceStatus.connecting ||
          _status == CallServiceStatus.reconnecting;

  bool get hasRemoteVideo => _hasVideoTrack(
    _remoteStream,
  );

  bool get hasLocalVideo => _hasVideoTrack(
    _localStream,
  );

  bool get hasRemoteAudio => _hasAudioTrack(
    _remoteStream,
  );

  bool get hasLocalAudio => _hasAudioTrack(
    _localStream,
  );

  // ===========================================================
  // INITIALIZATION
  // ===========================================================

  Future<void> initialize() {
    _ensureUsable();

    if (_isInitialized) {
      return Future<void>.value();
    }

    final Future<void>? existing =
        _initializationFuture;

    if (existing != null) {
      return existing;
    }

    final Future<void> future =
    _performInitialization();

    _initializationFuture = future;

    return future;
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

      _statusSubscription =
          _callService.callStatusStream.listen(
            _handleStatus,
            onError: (
                Object error,
                StackTrace stackTrace,
                ) {
              _handleError(
                'Call status stream',
                error,
                stackTrace,
              );
            },
          );

      _durationSubscription =
          _callService.callDurationStream.listen(
            _handleDuration,
            onError: (
                Object error,
                StackTrace stackTrace,
                ) {
              _handleError(
                'Call duration stream',
                error,
                stackTrace,
              );
            },
          );

      _localStreamSubscription =
          _callService.webrtc.localStream$.listen(
            _handleLocalStream,
            onError: (
                Object error,
                StackTrace stackTrace,
                ) {
              _handleError(
                'Local media stream',
                error,
                stackTrace,
              );
            },
          );

      _remoteStreamSubscription =
          _callService.webrtc.remoteStream$.listen(
            _handleRemoteStream,
            onError: (
                Object error,
                StackTrace stackTrace,
                ) {
              _handleError(
                'Remote media stream',
                error,
                stackTrace,
              );
            },
          );

      if (_isDisposed) {
        await _cancelSubscriptions();
        return;
      }

      // -------------------------------------------------------
      // CRITICAL LATE-BINDING SYNCHRONIZATION
      //
      // localStream$ / remoteStream$ are event streams.
      // The active WebRTC session may already have created media
      // before this presentation provider subscribes.
      //
      // Therefore initialization must also recover the currently
      // owned WebRTCService media references synchronously.
      // -------------------------------------------------------

      _syncFromCallService();

      _isInitialized = true;

      _notifySafely();
    } catch (error, stackTrace) {
      if (!_isDisposed) {
        _handleError(
          'Call screen provider initialization',
          error,
          stackTrace,
        );
      }

      await _cancelSubscriptions();

      _isInitialized = false;

      rethrow;
    } finally {
      _initializationFuture = null;
    }
  }

  Future<void> _ensureInitialized() async {
    if (_isDisposed || _isInitialized) {
      return;
    }

    await initialize();
  }

  // ===========================================================
  // START OUTGOING CALL
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

    if (_isDisposed ||
        isBusy ||
        hasActiveCall) {
      return null;
    }

    final String localId = callerId.trim();

    final String remoteId = receiverId.trim();

    if (localId.isEmpty ||
        remoteId.isEmpty ||
        localId == remoteId) {
      _setError(
        'Invalid caller or receiver information.',
      );

      return null;
    }

    final int operationToken = _beginOperation();

    _isStarting = true;

    _errorMessage = null;

    _callId = null;
    _localUserId = localId;
    _remoteUserId = remoteId;

    _remoteName = remoteName.trim();
    _remotePhoto = remotePhoto.trim();

    _isVideoCall = isVideoCall;

    _durationSeconds = 0;

    _localStream = null;
    _remoteStream = null;

    _notifySafely();

    try {
      final String? createdCallId =
      await _callService.startCall(
        callerId: localId,
        receiverId: remoteId,
        isVideoCall: isVideoCall,
      );

      if (!_isOperationCurrent(
        operationToken,
      )) {
        return null;
      }

      final String? normalizedCallId =
      _normalizedOptionalString(
        createdCallId,
      );

      if (normalizedCallId == null) {
        if (_status !=
            CallServiceStatus.userBusy) {
          _setError(
            'Unable to start the call.',
          );
        }

        return null;
      }

      _callId = normalizedCallId;

      _syncFromCallService();

      _notifySafely();

      // startCall completion is NOT proof of WebRTC connection.
      return normalizedCallId;
    } catch (error, stackTrace) {
      if (_isOperationCurrent(
        operationToken,
      )) {
        _handleError(
          'Start call',
          error,
          stackTrace,
        );
      }

      return null;
    } finally {
      if (_isOperationCurrent(
        operationToken,
      )) {
        _isStarting = false;

        _notifySafely();
      }
    }
  }

  // ===========================================================
  // PREPARE INCOMING CALL UI
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

    final String normalizedCallId =
    callId.trim();

    final String normalizedLocalUserId =
    localUserId.trim();

    final String normalizedRemoteUserId =
    remoteUserId.trim();

    if (normalizedCallId.isEmpty ||
        normalizedLocalUserId.isEmpty ||
        normalizedRemoteUserId.isEmpty) {
      return;
    }

    _invalidateOperations();

    _callId = normalizedCallId;
    _localUserId = normalizedLocalUserId;
    _remoteUserId = normalizedRemoteUserId;

    _remoteName = remoteName.trim();
    _remotePhoto = remotePhoto.trim();

    _isVideoCall = isVideoCall;

    _durationSeconds = 0;

    _localStream = null;
    _remoteStream = null;

    _errorMessage = null;

    _status = CallServiceStatus.ringing;

    _notifySafely();
  }

  // ===========================================================
  // ACCEPT INCOMING CALL
  // ===========================================================

  Future<bool> acceptCall({
    String? callId,
  }) async {
    _ensureUsable();

    await _ensureInitialized();

    if (_isDisposed || isBusy) {
      return false;
    }

    final String? targetCallId =
    _resolveCallId(
      callId,
    );

    if (targetCallId == null) {
      _setError(
        'Call ID is missing.',
      );

      return false;
    }

    final int operationToken = _beginOperation();

    _isAccepting = true;

    _errorMessage = null;

    _callId = targetCallId;

    _notifySafely();

    try {
      await _callService.acceptCall(
        callId: targetCallId,
      );

      if (!_isOperationCurrent(
        operationToken,
      )) {
        return false;
      }

      _syncFromCallService();

      // Successful acceptance request does not mean WebRTC connected.
      return !_isTerminalStatus(
        _status,
      );
    } catch (error, stackTrace) {
      if (_isOperationCurrent(
        operationToken,
      )) {
        _handleError(
          'Accept call',
          error,
          stackTrace,
        );
      }

      return false;
    } finally {
      if (_isOperationCurrent(
        operationToken,
      )) {
        _isAccepting = false;

        _notifySafely();
      }
    }
  }

  // ===========================================================
  // REJECT INCOMING CALL
  // ===========================================================

  Future<void> rejectCall({
    String? callId,
  }) async {
    _ensureUsable();

    await _ensureInitialized();

    if (_isDisposed || isBusy) {
      return;
    }

    final String? targetCallId =
    _resolveCallId(
      callId,
    );

    if (targetCallId == null) {
      return;
    }

    final int operationToken = _beginOperation();

    _isRejecting = true;

    _errorMessage = null;

    _notifySafely();

    try {
      await _callService.rejectCall(
        callId: targetCallId,
      );

      if (_isOperationCurrent(
        operationToken,
      )) {
        _syncFromCallService(
          preserveDuration:
          _isTerminalStatus(
            _status,
          ),
        );
      }
    } catch (error, stackTrace) {
      if (_isOperationCurrent(
        operationToken,
      )) {
        _handleError(
          'Reject call',
          error,
          stackTrace,
        );
      }
    } finally {
      if (_isOperationCurrent(
        operationToken,
      )) {
        _isRejecting = false;

        _notifySafely();
      }
    }
  }

  // ===========================================================
  // CANCEL OUTGOING CALL
  // ===========================================================

  Future<void> cancelCall({
    String? callId,
  }) async {
    _ensureUsable();

    await _ensureInitialized();

    if (_isDisposed || isBusy) {
      return;
    }

    final String? targetCallId =
    _resolveCallId(
      callId,
    );

    if (targetCallId == null) {
      return;
    }

    final int operationToken = _beginOperation();

    _isCancelling = true;

    _errorMessage = null;

    _notifySafely();

    try {
      await _callService.cancelCall(
        callId: targetCallId,
      );

      if (_isOperationCurrent(
        operationToken,
      )) {
        _syncFromCallService(
          preserveDuration:
          _isTerminalStatus(
            _status,
          ),
        );
      }
    } catch (error, stackTrace) {
      if (_isOperationCurrent(
        operationToken,
      )) {
        _handleError(
          'Cancel call',
          error,
          stackTrace,
        );
      }
    } finally {
      if (_isOperationCurrent(
        operationToken,
      )) {
        _isCancelling = false;

        _notifySafely();
      }
    }
  }

  // ===========================================================
  // END ACTIVE CALL
  // ===========================================================

  Future<void> endCall({
    String status = 'COMPLETED',
  }) async {
    _ensureUsable();

    await _ensureInitialized();

    if (_isDisposed || isBusy) {
      return;
    }

    final String? targetCallId =
    _resolveCallId(
      _callService.currentCallId,
    );

    if (targetCallId == null) {
      _resetUiSession(
        preserveStatus: false,
      );

      return;
    }

    final int operationToken = _beginOperation();

    final String normalizedStatus =
    status.trim().isEmpty
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

      if (_isOperationCurrent(
        operationToken,
      )) {
        _syncFromCallService(
          preserveDuration: true,
        );
      }
    } catch (error, stackTrace) {
      if (_isOperationCurrent(
        operationToken,
      )) {
        _handleError(
          'End call',
          error,
          stackTrace,
        );
      }
    } finally {
      if (_isOperationCurrent(
        operationToken,
      )) {
        _isEnding = false;

        _notifySafely();
      }
    }
  }

  // ===========================================================
  // STATUS STREAM
  // ===========================================================

  void _handleStatus(
      String status,
      ) {
    if (_isDisposed) {
      return;
    }

    final String normalized =
    status.trim().toUpperCase();

    if (normalized.isEmpty) {
      return;
    }

    final bool statusChanged =
        _status != normalized;

    _status = normalized;

    final bool terminal =
    _isTerminalStatus(
      normalized,
    );

    _syncFromCallService(
      preserveDuration: terminal,
    );

    bool mediaChanged = false;

    if (terminal) {
      mediaChanged =
          _localStream != null ||
              _remoteStream != null;

      // Presentation references only.
      // Never stop or dispose WebRTCService-owned media here.
      _localStream = null;
      _remoteStream = null;

      // Final duration is intentionally preserved until reset().
    }

    if (statusChanged || mediaChanged) {
      _notifySafely();
    }
  }

  // ===========================================================
  // DURATION STREAM
  // ===========================================================

  void _handleDuration(
      int duration,
      ) {
    if (_isDisposed) {
      return;
    }

    final int safeDuration =
    duration < 0 ? 0 : duration;

    if (_durationSeconds ==
        safeDuration) {
      return;
    }

    // Ignore a late zero after terminal cleanup if we already have
    // a meaningful final duration.
    if (_isTerminalStatus(
      _status,
    ) &&
        safeDuration == 0 &&
        _durationSeconds > 0) {
      return;
    }

    _durationSeconds = safeDuration;

    _notifySafely();
  }

  // ===========================================================
  // LOCAL MEDIA STREAM
  // ===========================================================

  void _handleLocalStream(
      MediaStream? stream,
      ) {
    if (_isDisposed) {
      return;
    }

    // A terminal call must not regain stale media references.
    if (_isTerminalStatus(
      _status,
    ) &&
        stream != null) {
      return;
    }

    if (identical(
      _localStream,
      stream,
    )) {
      return;
    }

    _localStream = stream;

    _notifySafely();
  }

  // ===========================================================
  // REMOTE MEDIA STREAM
  // ===========================================================

  void _handleRemoteStream(
      MediaStream? stream,
      ) {
    if (_isDisposed) {
      return;
    }

    // A terminal call must not regain stale media references.
    if (_isTerminalStatus(
      _status,
    ) &&
        stream != null) {
      return;
    }

    if (identical(
      _remoteStream,
      stream,
    )) {
      return;
    }

    _remoteStream = stream;

    _notifySafely();
  }

  // ===========================================================
  // CALL SERVICE SYNCHRONIZATION
  //
  // IMPORTANT:
  //
  // CallService/WebRTCService may already own a live media
  // session before this provider is initialized.
  //
  // The event streams are not treated as replay storage here.
  // Existing WebRTCService media references must therefore also
  // be synchronized directly.
  // ===========================================================

  void _syncFromCallService({
    bool preserveDuration = false,
  }) {
    if (_isDisposed) {
      return;
    }

    final String? serviceCallId =
    _normalizedOptionalString(
      _callService.currentCallId,
    );

    final String? serviceLocalUserId =
    _normalizedOptionalString(
      _callService.currentUserId,
    );

    final String? serviceRemoteUserId =
    _normalizedOptionalString(
      _callService.currentPeerId,
    );

    if (serviceCallId != null) {
      _callId = serviceCallId;
    }

    if (serviceLocalUserId != null) {
      _localUserId = serviceLocalUserId;
    }

    if (serviceRemoteUserId != null) {
      _remoteUserId =
          serviceRemoteUserId;
    }

    // -------------------------------------------------------
    // MEDIA LATE-BINDING FIX
    //
    // These are non-owning references.
    // Never stop/dispose them from this provider.
    // -------------------------------------------------------

    if (!_isTerminalStatus(
      _status,
    )) {
      _localStream =
          _callService.webrtc.localStream;

      _remoteStream =
          _callService.webrtc.remoteStream;
    }

    // Do not overwrite prepared incoming-call metadata using an
    // unowned/default CallService session.
    if (serviceCallId != null ||
        _callService.isCallActive) {
      _isVideoCall =
          _callService.isVideoCall;

      if (!preserveDuration) {
        final int serviceDuration =
            _callService.callDurationSeconds;

        _durationSeconds =
        serviceDuration < 0
            ? 0
            : serviceDuration;
      }
    }
  }

  // ===========================================================
  // TERMINAL STATUS
  // ===========================================================

  bool _isTerminalStatus(
      String status,
      ) {
    switch (status) {
      case CallServiceStatus.userBusy:
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
  // MEDIA TRACK SAFETY
  // ===========================================================

  bool _hasVideoTrack(
      MediaStream? stream,
      ) {
    if (stream == null) {
      return false;
    }

    try {
      return stream
          .getVideoTracks()
          .isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool _hasAudioTrack(
      MediaStream? stream,
      ) {
    if (stream == null) {
      return false;
    }

    try {
      return stream
          .getAudioTracks()
          .isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ===========================================================
  // ERROR STATE
  // ===========================================================

  void clearError() {
    if (_isDisposed ||
        _errorMessage == null) {
      return;
    }

    _errorMessage = null;

    _notifySafely();
  }

  void _setError(
      String message,
      ) {
    if (_isDisposed) {
      return;
    }

    final String normalized =
    message.trim();

    _errorMessage =
    normalized.isEmpty
        ? 'Unknown call error.'
        : normalized;

    _notifySafely();
  }

  void _handleError(
      String source,
      Object error, [
        StackTrace? stackTrace,
      ]) {
    if (_isDisposed) {
      return;
    }

    final String normalizedError =
    error.toString().trim();

    _errorMessage =
    normalizedError.isEmpty
        ? 'Unknown call error.'
        : normalizedError;

    debugPrint(
      'JR CALL [$source] error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL [$source]',
        stackTrace: stackTrace,
      );
    }

    _notifySafely();
  }

  // ===========================================================
  // OPERATION GENERATION
  // ===========================================================

  int _beginOperation() {
    _operationGeneration++;

    return _operationGeneration;
  }

  bool _isOperationCurrent(
      int token,
      ) {
    return !_isDisposed &&
        token == _operationGeneration;
  }

  void _invalidateOperations() {
    _operationGeneration++;

    _isStarting = false;
    _isAccepting = false;
    _isRejecting = false;
    _isCancelling = false;
    _isEnding = false;
  }

  // ===========================================================
  // CALL ID
  // ===========================================================

  String? _resolveCallId(
      String? explicitCallId,
      ) {
    return _normalizedOptionalString(
      explicitCallId,
    ) ??
        _normalizedOptionalString(
          _callId,
        ) ??
        _normalizedOptionalString(
          _callService.currentCallId,
        );
  }

  String? _normalizedOptionalString(
      String? value,
      ) {
    if (value == null) {
      return null;
    }

    final String normalized =
    value.trim();

    return normalized.isEmpty
        ? null
        : normalized;
  }

  // ===========================================================
  // USABILITY
  // ===========================================================

  void _ensureUsable() {
    if (_isDisposed) {
      throw StateError(
        'CallScreenProvider has already been disposed.',
      );
    }
  }

  // ===========================================================
  // UI RESET
  //
  // Presentation reset only.
  // Does NOT end CallService.
  // ===========================================================

  void reset({
    bool preserveRemoteIdentity = false,
  }) {
    _ensureUsable();

    _resetUiSession(
      preserveStatus: false,
      preserveRemoteIdentity:
      preserveRemoteIdentity,
    );
  }

  void _resetUiSession({
    required bool preserveStatus,
    bool preserveRemoteIdentity = false,
  }) {
    if (_isDisposed) {
      return;
    }

    _invalidateOperations();

    if (!preserveStatus) {
      _status =
          CallServiceStatus.idle;
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

    _notifySafely();
  }

  // ===========================================================
  // SUBSCRIPTION CLEANUP
  // ===========================================================

  Future<void> _cancelSubscriptions() async {
    final StreamSubscription<String>?
    statusSubscription =
        _statusSubscription;

    final StreamSubscription<int>?
    durationSubscription =
        _durationSubscription;

    final StreamSubscription<MediaStream?>?
    localStreamSubscription =
        _localStreamSubscription;

    final StreamSubscription<MediaStream?>?
    remoteStreamSubscription =
        _remoteStreamSubscription;

    _statusSubscription = null;
    _durationSubscription = null;
    _localStreamSubscription = null;
    _remoteStreamSubscription = null;

    await _cancelSubscription(
      statusSubscription,
      'status subscription',
    );

    await _cancelSubscription(
      durationSubscription,
      'duration subscription',
    );

    await _cancelSubscription(
      localStreamSubscription,
      'local stream subscription',
    );

    await _cancelSubscription(
      remoteStreamSubscription,
      'remote stream subscription',
    );
  }

  Future<void> _cancelSubscription<T>(
      StreamSubscription<T>? subscription,
      String source,
      ) async {
    if (subscription == null) {
      return;
    }

    try {
      await subscription.cancel();
    } catch (error, stackTrace) {
      debugPrint(
        'JR CALL [CallScreenProvider/$source] error: $error',
      );

      debugPrintStack(
        label:
        'JR CALL [CallScreenProvider/$source]',
        stackTrace: stackTrace,
      );
    }
  }

  // ===========================================================
  // SAFE NOTIFICATION
  // ===========================================================

  void _notifySafely() {
    if (_isDisposed) {
      return;
    }

    notifyListeners();
  }

  // ===========================================================
  // DISPOSE
  //
  // Provider does NOT dispose CallService or WebRTC media.
  // ===========================================================

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;
    _isInitialized = false;

    _operationGeneration++;

    _isStarting = false;
    _isAccepting = false;
    _isRejecting = false;
    _isCancelling = false;
    _isEnding = false;

    _initializationFuture = null;

    final StreamSubscription<String>?
    statusSubscription =
        _statusSubscription;

    final StreamSubscription<int>?
    durationSubscription =
        _durationSubscription;

    final StreamSubscription<MediaStream?>?
    localStreamSubscription =
        _localStreamSubscription;

    final StreamSubscription<MediaStream?>?
    remoteStreamSubscription =
        _remoteStreamSubscription;

    _statusSubscription = null;
    _durationSubscription = null;
    _localStreamSubscription = null;
    _remoteStreamSubscription = null;

    if (statusSubscription != null) {
      unawaited(
        _cancelSubscription(
          statusSubscription,
          'status subscription',
        ),
      );
    }

    if (durationSubscription != null) {
      unawaited(
        _cancelSubscription(
          durationSubscription,
          'duration subscription',
        ),
      );
    }

    if (localStreamSubscription != null) {
      unawaited(
        _cancelSubscription(
          localStreamSubscription,
          'local stream subscription',
        ),
      );
    }

    if (remoteStreamSubscription != null) {
      unawaited(
        _cancelSubscription(
          remoteStreamSubscription,
          'remote stream subscription',
        ),
      );
    }

    // Non-owning references only.
    _localStream = null;
    _remoteStream = null;

    _callId = null;
    _localUserId = null;
    _remoteUserId = null;

    super.dispose();
  }
}

// ===========================================================
// END OF FILE
//
// PRODUCTION CONTRACT:
//
// ✓ Existing constructor preserved.
// ✓ Existing CallService getter preserved.
// ✓ Existing public state getters preserved.
// ✓ Existing role/isCaller/isReceiver preserved.
// ✓ Existing media getters preserved.
//
// ✓ initialize() preserved.
// ✓ startCall() preserved.
// ✓ prepareIncomingCall() preserved.
// ✓ acceptCall() preserved.
// ✓ rejectCall() preserved.
// ✓ cancelCall() preserved.
// ✓ endCall() preserved.
// ✓ clearError() preserved.
// ✓ reset() preserved.
//
// ✓ CallService remains lifecycle authority.
// ✓ CallService remains duration authority.
// ✓ No fake connected state.
//
// ✓ Single-flight initialization.
// ✓ Duplicate stream subscriptions prevented.
// ✓ Conflicting UI actions blocked.
// ✓ Stale async operation protection.
// ✓ Terminal stale call ID cannot keep active-call UI alive.
// ✓ userBusy is terminal presentation state.
// ✓ Final duration survives terminal CallService cleanup.
// ✓ Late terminal zero-duration event cannot erase final duration.
// ✓ Terminal media references cannot resurrect from stale events.
//
// ✓ Existing WebRTC media is synchronized during late UI binding.
// ✓ Late active-screen creation can recover current local stream.
// ✓ Late active-screen creation can recover current remote stream.
// ✓ Media streams are never disposed by this provider.
// ✓ Media-track inspection fails closed safely.
// ✓ Subscription cancellation errors are contained.
//
// ✓ No Firestore ownership.
// ✓ No signaling ownership.
// ✓ No history ownership.
// ✓ No timer ownership.
// ✓ No ICE ownership.
// ✓ No recovery ownership.
// ✓ No PeerConnection ownership.
// ✓ No MediaStream creation.
// ✓ No MediaStream disposal.
// ===========================================================