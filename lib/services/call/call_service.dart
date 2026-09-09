// ===============================================================
// JR CALL
// File: call_service.dart
// Location: lib/services/call/call_service.dart
//
// MASTER PRODUCTION CALL ORCHESTRATOR
//
// Ownership:
// - Firebase UID -> canonical participant identity.
// - SignalingService -> Firestore signaling owner.
// - CallListenerService -> call-document listener owner.
// - IceManager -> local/remote ICE owner.
// - RecoveryManager -> recovery scheduling/policy owner.
// - WebRTCService -> PeerConnection/media/SDP transport owner.
// - CallService -> complete call lifecycle/orchestration owner.
//
// Production guarantees:
// - No fake CONNECTED state from Firestore alone.
// - Duration starts only after actual WebRTC connection.
// - Terminal statuses preserve their real meaning.
// - Initial receiver offer is processed exactly once.
// - Duplicate accept cannot destroy an established call.
// - A detached/non-current call cannot clean up the active call.
// - Local terminal operations cannot race listener cleanup.
// - Remote terminal calls persist history when possible.
// - Same-session history persistence is guarded.
// - Stale asynchronous sessions are rejected.
// - ICE remains exclusively owned by IceManager.
// - SDP remains owned by WebRTCService.
// - RecoveryManager never owns Firestore signaling.
// - Caller recovery is coordinated here.
// - Native ICE restart and signaling restart cannot double-fire.
// ===============================================================

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../managers/ice_manager.dart';
import '../managers/recovery_manager.dart';
import 'call_listener_service.dart';
import 'connection_manager.dart';
import 'signaling_service.dart';
import 'stun_turn_service.dart';
import 'webrtc_service.dart';

// ===============================================================
// UI CALL STATUS CONSTANTS
// ===============================================================

abstract final class CallServiceStatus {
  static const String idle = 'IDLE';
  static const String preparing = 'PREPARING';
  static const String calling = 'CALLING';
  static const String ringing = 'RINGING';
  static const String connecting = 'CONNECTING';
  static const String connected = 'CONNECTED';
  static const String reconnecting = 'RECONNECTING';
  static const String reconnected = 'RECONNECTED';

  static const String networkLost = 'NETWORK_LOST';
  static const String userBusy = 'USER_BUSY';

  static const String rejected = 'REJECTED';
  static const String declined = 'DECLINED';
  static const String cancelled = 'CANCELLED';
  static const String timeout = 'TIMEOUT';
  static const String failed = 'FAILED';
  static const String ended = 'ENDED';
}

// ===============================================================
// ACTIVE CALL ROLE
// ===============================================================

enum CallRole { none, caller, receiver }

// ===============================================================
// CALL SERVICE
// ===============================================================

class CallService with WidgetsBindingObserver {
  CallService._internal() {
    WidgetsBinding.instance.addObserver(this);

    unawaited(_warmUpInfrastructure());
  }

  static final CallService _instance = CallService._internal();

  factory CallService() => _instance;

  // =============================================================
  // SERVICES
  // =============================================================

  final WebRTCService webRTCService = WebRTCService();

  final SignalingService signalingService = SignalingService.instance;

  final CallListenerService _callListener = CallListenerService.instance;

  final IceManager _iceManager = IceManager.instance;

  final RecoveryManager _recoveryManager = RecoveryManager.instance;

  final ConnectionManager _connectionManager = ConnectionManager.instance;

  final StunTurnService _stunTurnService = StunTurnService.instance;

  /// Existing compatibility getter.
  WebRTCService get webrtc => webRTCService;

  // =============================================================
  // CONFIGURATION
  // =============================================================

  static const Duration _outgoingCallTimeout = Duration(seconds: 45);

  static const Duration _incomingConnectionTimeout = Duration(seconds: 20);

  // =============================================================
  // RUNTIME STATE
  // =============================================================

  bool _isDisposed = false;

  bool _isInfrastructureInitialized = false;

  bool _isStartingCall = false;

  bool _isAnsweringCall = false;

  bool _isEndingCall = false;

  bool _isFailingCall = false;

  bool _isCleaningUp = false;

  bool _isPerformingIceRestart = false;

  /// True only after the native PeerConnection restart has been
  /// completed for the active recovery attempt.
  bool _nativeIceRestartPrepared = false;

  /// Prevents concurrent native restart requests from invoking
  /// RTCPeerConnection.restartIce() more than once.
  Future<void>? _nativeIceRestartFuture;

  bool _networkAvailable = false;

  bool _isVideoCall = true;

  /// Prevents a successful history write from being repeated by
  /// another terminal path belonging to the same local session.
  bool _historyPersistedForSession = false;

  int _sessionGeneration = 0;

  int _callDurationSeconds = 0;

  String? _currentCallId;

  String? _currentUserId;

  String? _currentPeerId;

  String? _lastStatus;

  /// SDP fingerprint of the initial offer already processed by the
  /// receiver before the call listener starts.
  ///
  /// The initial Firestore snapshot can contain that same offer again.
  /// This session-local value lets the listener ignore only that exact
  /// duplicate while still allowing later ICE-restart offers.
  String? _initialReceiverOfferSdp;

  /// Last terminal status received from remote signaling.
  String? _lastRemoteTerminalStatus;

  CallRole _currentRole = CallRole.none;

  Future<void>? _infrastructureInitializationFuture;

  /// Serializes remote SDP application.
  Future<void>? _remoteDescriptionFuture;

  // =============================================================
  // TIMERS
  // =============================================================

  Timer? _callTimeoutTimer;

  Timer? _callDurationTimer;

  // =============================================================
  // SUBSCRIPTIONS
  // =============================================================

  StreamSubscription<ConnectionStateModel>? _connectionSubscription;

  // =============================================================
  // UI STREAMS
  // =============================================================

  final StreamController<String> _callStatusController =
  StreamController<String>.broadcast();

  final StreamController<int> _callDurationController =
  StreamController<int>.broadcast();

  Stream<String> get callStatusStream => _callStatusController.stream;

  Stream<int> get callDurationStream => _callDurationController.stream;

  // =============================================================
  // PUBLIC STATE
  // =============================================================

  String? get currentCallId => _currentCallId;

  String? get currentPeerId => _currentPeerId;

  String? get currentUserId => _currentUserId;

  bool get isDisposed => _isDisposed;

  bool get isVideoCall => _isVideoCall;

  bool get isCallActive => _currentCallId != null;

  bool get isCaller => _currentRole == CallRole.caller;

  bool get isReceiver => _currentRole == CallRole.receiver;

  bool get networkAvailable => _networkAvailable;

  int get callDurationSeconds => _callDurationSeconds;

  CallRole get currentRole => _currentRole;

  // =============================================================
  // TERMINAL GUARD
  // =============================================================

  bool get _terminalOutcomeInProgress {
    return _isEndingCall ||
        _isFailingCall ||
        _isCleaningUp ||
        _lastRemoteTerminalStatus != null;
  }

  // =============================================================
  // INFRASTRUCTURE INITIALIZATION
  // =============================================================

  Future<void> initialize() async {
    if (_isDisposed) {
      throw StateError(
        'CallService has been disposed and cannot be reused.',
      );
    }

    await _initializeInfrastructure();
  }

  Future<void> _warmUpInfrastructure() async {
    try {
      await _initializeInfrastructure();
    } catch (error, stackTrace) {
      _reportError(
        'Infrastructure warm-up',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _initializeInfrastructure() async {
    if (_isDisposed) {
      throw StateError(
        'CallService has been disposed and cannot initialize.',
      );
    }

    if (_isInfrastructureInitialized) {
      return;
    }

    final Future<void>? existing =
        _infrastructureInitializationFuture;

    if (existing != null) {
      await existing;

      return;
    }

    final Future<void> initialization =
    _performInfrastructureInitialization();

    _infrastructureInitializationFuture = initialization;

    try {
      await initialization;
    } finally {
      if (identical(
        _infrastructureInitializationFuture,
        initialization,
      )) {
        _infrastructureInitializationFuture = null;
      }
    }
  }

  Future<void> _performInfrastructureInitialization() async {
    if (_isDisposed) {
      return;
    }

    if (_callListener.isDisposed) {
      _callListener.initialize();
    }

    if (!_connectionManager.isMonitoring) {
      await _connectionManager.startMonitoring();
    }

    if (_isDisposed) {
      return;
    }

    _networkAvailable = _connectionManager.isConnected;

    await _connectionSubscription?.cancel();

    _connectionSubscription = null;

    if (_isDisposed) {
      return;
    }

    _connectionSubscription =
        _connectionManager.connectionStream.listen(
          _handleConnectionState,
          onError: (Object error, StackTrace stackTrace) {
            _reportError(
              'ConnectionManager stream',
              error,
              stackTrace,
            );
          },
        );

    if (_isDisposed) {
      await _connectionSubscription?.cancel();

      _connectionSubscription = null;

      return;
    }

    _configureRecoveryCallbacks();

    _isInfrastructureInitialized = true;

    debugPrint(
      'JR CALL: CallService infrastructure initialized.',
    );
  }

  // =============================================================
  // APPLICATION LIFECYCLE
  // =============================================================

  @override
  void didChangeAppLifecycleState(
      AppLifecycleState state,
      ) {
    if (_isDisposed) {
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        debugPrint('JR CALL: App resumed.');

        if (_currentCallId != null) {
          _callListener.resumeListening();

          if (_connectionManager.isConnected) {
            _networkAvailable = true;

            _recoveryManager.handleNetworkRestored();
          }
        }

        break;

      case AppLifecycleState.inactive:
        debugPrint('JR CALL: App inactive.');
        break;

      case AppLifecycleState.paused:
        debugPrint('JR CALL: App backgrounded.');
        break;

      case AppLifecycleState.hidden:
        debugPrint('JR CALL: App hidden.');
        break;

      case AppLifecycleState.detached:
        debugPrint('JR CALL: App detached.');
        break;
    }
  }

  // =============================================================
  // OUTGOING CALL
  // =============================================================

  Future<String?> startCall({
    required String callerId,
    required String receiverId,
    bool isVideoCall = true,
  }) async {
    final String normalizedCallerId = callerId.trim();

    final String normalizedReceiverId = receiverId.trim();

    if (_isDisposed) {
      return null;
    }

    if (_isStartingCall ||
        _isAnsweringCall ||
        _isEndingCall ||
        _isFailingCall ||
        _isCleaningUp ||
        _currentCallId != null) {
      debugPrint(
        'JR CALL: Duplicate outgoing call blocked.',
      );

      return null;
    }

    if (normalizedCallerId.isEmpty ||
        normalizedReceiverId.isEmpty ||
        normalizedCallerId == normalizedReceiverId) {
      _emitStatus(
        CallServiceStatus.failed,
        force: true,
      );

      return null;
    }

    final String? authenticatedUid =
    signalingService.auth.currentUser?.uid.trim();

    if (authenticatedUid == null ||
        authenticatedUid.isEmpty ||
        authenticatedUid != normalizedCallerId) {
      _emitStatus(
        CallServiceStatus.failed,
        force: true,
      );

      _reportError(
        'Start outgoing call',
        StateError(
          'Authenticated Firebase UID does not match callerId.',
        ),
      );

      return null;
    }

    _isStartingCall = true;

    final int sessionToken = _beginNewSession();

    _currentUserId = normalizedCallerId;

    _currentPeerId = normalizedReceiverId;

    _currentRole = CallRole.caller;

    _isVideoCall = isVideoCall;

    try {
      await _initializeInfrastructure();

      if (!_isSessionCurrent(sessionToken)) {
        return null;
      }

      _emitStatus(
        CallServiceStatus.preparing,
      );

      if (!_connectionManager.isConnected) {
        _networkAvailable = false;

        _emitStatus(
          CallServiceStatus.networkLost,
          force: true,
        );

        await _cleanupSession(
          sessionToken: sessionToken,
          preserveLastStatus: true,
        );

        return null;
      }

      _networkAvailable = true;

      final bool isBusy =
      await signalingService.checkUserBusyStatus(
        normalizedReceiverId,
      );

      if (!_isSessionCurrent(sessionToken)) {
        return null;
      }

      if (isBusy) {
        _emitStatus(
          CallServiceStatus.userBusy,
          force: true,
        );

        await _cleanupSession(
          sessionToken: sessionToken,
          preserveLastStatus: true,
        );

        return null;
      }

      await _initializePeerConnection(
        video: isVideoCall,
        sessionToken: sessionToken,
      );

      if (!_isSessionCurrent(sessionToken)) {
        return null;
      }

      final callReference =
      await signalingService.createCall(
        callerId: normalizedCallerId,
        receiverId: normalizedReceiverId,
        isVideoCall: isVideoCall,
      );

      if (!_isSessionCurrent(sessionToken)) {
        return null;
      }

      _currentCallId = callReference.id;

      await _initializeIce(
        callId: callReference.id,
        isCaller: true,
        sessionToken: sessionToken,
      );

      if (!_isSessionCurrent(sessionToken)) {
        return null;
      }

      _configureRecoveryContext(
        callId: callReference.id,
        userId: normalizedCallerId,
        isCaller: true,
      );

      _configureCallListener(
        callId: callReference.id,
        sessionToken: sessionToken,
      );

      _callListener.startListening(
        callReference.id,
      );

      final RTCSessionDescription offer =
      await webRTCService.createOffer();

      if (!_isSessionCurrent(sessionToken)) {
        return null;
      }

      await signalingService.saveOffer(
        callReference.id,
        _sessionDescriptionToMap(offer),
      );

      if (!_isSessionCurrent(sessionToken)) {
        return null;
      }

      _emitStatus(
        CallServiceStatus.calling,
      );

      _startCallTimeoutTimer(sessionToken);

      return callReference.id;
    } catch (error, stackTrace) {
      _reportError(
        'Start outgoing call',
        error,
        stackTrace,
      );

      await _failCurrentCall(
        sessionToken: sessionToken,
        callId: _currentCallId,
      );

      return null;
    } finally {
      _isStartingCall = false;
    }
  }

  // =============================================================
  // INCOMING CALL
  // =============================================================

  Future<void> acceptCall({
    required String callId,
  }) async {
    await answerIncomingCall(
      callId: callId,
    );
  }

  Future<void> answerIncomingCall({
    required String callId,
  }) async {
    final String normalizedCallId = callId.trim();

    if (_isDisposed ||
        normalizedCallId.isEmpty ||
        _isStartingCall ||
        _isAnsweringCall ||
        _isEndingCall ||
        _isFailingCall ||
        _isCleaningUp) {
      return;
    }

    if (_currentCallId != null) {
      debugPrint(
        'JR CALL: Incoming answer ignored because '
            'a local call session is already active.',
      );

      return;
    }

    _isAnsweringCall = true;

    final int sessionToken = _beginNewSession();

    _currentCallId = normalizedCallId;

    _currentRole = CallRole.receiver;

    try {
      await _initializeInfrastructure();

      if (!_isSessionCurrent(sessionToken)) {
        return;
      }

      _emitStatus(
        CallServiceStatus.preparing,
      );

      if (!_connectionManager.isConnected) {
        _networkAvailable = false;

        throw StateError(
          'Network connection is unavailable.',
        );
      }

      _networkAvailable = true;

      final Map<String, dynamic> callData =
      await signalingService.getCallDocument(
        normalizedCallId,
      );

      if (!_isSessionCurrent(sessionToken)) {
        return;
      }

      final String? status =
      _readString(
        callData[CallFields.status],
      )?.toLowerCase();

      debugPrint(
        'JR CALL [Incoming answer state]: '
            'callId=$normalizedCallId, '
            'status=${status ?? 'null'}, '
            'terminal=${status != null && CallStatusValues.isTerminal(status)}',
      );

      if (status == null ||
          CallStatusValues.isTerminal(status)) {
        throw StateError(
          'Incoming call is no longer active.',
        );
      }

      final String? callerId =
          _readString(callData['callerId']) ??
              _readString(callData['senderId']);

      final String? receiverId =
          _readString(callData['receiverId']) ??
              _readString(callData['recipientId']);

      if (callerId == null) {
        throw StateError(
          'Incoming call caller ID is missing.',
        );
      }

      if (receiverId == null) {
        throw StateError(
          'Incoming call receiver ID is missing.',
        );
      }

      final String? authenticatedUid =
      signalingService.auth.currentUser?.uid.trim();

      if (authenticatedUid == null ||
          authenticatedUid.isEmpty ||
          authenticatedUid != receiverId) {
        throw StateError(
          'Authenticated Firebase UID does not match '
              'the incoming call receiver.',
        );
      }

      if (callerId == receiverId) {
        throw StateError(
          'Caller and receiver cannot be the same user.',
        );
      }

      _currentPeerId = callerId;

      _currentUserId = receiverId;

      _isVideoCall =
          _readBool(callData['isVideoCall']) ??
              _readBool(callData['video']) ??
              true;

      final Map<String, dynamic>? offer =
      _normalizeMap(
        callData[CallFields.offer],
      );

      if (!_isValidSessionDescription(
        offer,
        requiredType: 'offer',
      )) {
        throw StateError(
          'Incoming call offer is missing or invalid.',
        );
      }

      // The initial receiver offer is processed directly below before
      // the call listener starts. Keep its SDP so the listener's first
      // Firestore snapshot cannot process the same offer as a restart.
      _initialReceiverOfferSdp =
          _readString(
            offer![CallFields.sdp],
          );

      // Persist the receiver acceptance before WebRTC enters
      // CONNECTING. This keeps the canonical lifecycle:
      //
      // CALLING -> RINGING -> ACCEPTED -> CONNECTING -> CONNECTED
      //
      // CALLING -> ACCEPTED is also intentionally supported so a
      // fast user acceptance cannot fail if the separate RINGING
      // acknowledgement is still racing.
      if (status == CallStatusValues.calling ||
          status == CallStatusValues.ringing) {
        await signalingService.updateCallStatus(
          normalizedCallId,
          'accepted',
        );

        if (!_isSessionCurrent(sessionToken)) {
          return;
        }
      } else if (status != 'accepted') {
        throw StateError(
          'Incoming call cannot be accepted from status: $status.',
        );
      }

      await _initializePeerConnection(
        video: _isVideoCall,
        sessionToken: sessionToken,
      );

      if (!_isSessionCurrent(sessionToken)) {
        return;
      }

      await _initializeIce(
        callId: normalizedCallId,
        isCaller: false,
        sessionToken: sessionToken,
      );

      if (!_isSessionCurrent(sessionToken)) {
        return;
      }

      _configureRecoveryContext(
        callId: normalizedCallId,
        userId: receiverId,
        isCaller: false,
      );

      _emitStatus(
        CallServiceStatus.connecting,
      );

      await signalingService.updateCallStatus(
        normalizedCallId,
        CallStatusValues.connecting,
      );

      if (!_isSessionCurrent(sessionToken)) {
        return;
      }

      await _applyRemoteDescription(
        description: offer,
        expectedType: 'offer',
        sessionToken: sessionToken,
      );

      if (!_isSessionCurrent(sessionToken)) {
        return;
      }

      final RTCSessionDescription answer =
      await webRTCService.createAnswer();

      if (!_isSessionCurrent(sessionToken)) {
        return;
      }

      await signalingService.saveAnswer(
        normalizedCallId,
        _sessionDescriptionToMap(answer),
      );

      if (!_isSessionCurrent(sessionToken)) {
        return;
      }

      _configureCallListener(
        callId: normalizedCallId,
        sessionToken: sessionToken,
      );

      _callListener.startListening(
        normalizedCallId,
      );

      if (!_isSessionCurrent(sessionToken)) {
        return;
      }

      await webRTCService.waitUntilConnected(
        timeout: _incomingConnectionTimeout,
      );

      if (!_isActiveCall(
        callId: normalizedCallId,
        sessionToken: sessionToken,
      )) {
        return;
      }

      if (!webRTCService.isPeerConnected) {
        throw StateError(
          'WebRTC did not reach connected state.',
        );
      }

      final Map<String, dynamic> latestCallData =
      await signalingService.getCallDocument(
        normalizedCallId,
      );

      if (!_isActiveCall(
        callId: normalizedCallId,
        sessionToken: sessionToken,
      )) {
        return;
      }

      final String? latestStatus =
      _readString(
        latestCallData[CallFields.status],
      )?.toLowerCase();

      if (latestStatus != null &&
          CallStatusValues.isTerminal(latestStatus)) {
        _lastRemoteTerminalStatus = latestStatus;

        _emitStatus(
          latestStatus.toUpperCase(),
          force: true,
        );

        await _handleRemoteCallEnded(
          callId: normalizedCallId,
          sessionToken: sessionToken,
        );

        return;
      }

      await signalingService.updateCallStatus(
        normalizedCallId,
        CallStatusValues.connected,
      );

      if (!_isActiveCall(
        callId: normalizedCallId,
        sessionToken: sessionToken,
      )) {
        return;
      }

      _markCallConnected();
    } catch (error, stackTrace) {
      _reportError(
        'Answer incoming call',
        error,
        stackTrace,
      );

      await _failCurrentCall(
        sessionToken: sessionToken,
        callId: normalizedCallId,
      );
    } finally {
      _isAnsweringCall = false;
    }
  }

  // =============================================================
  // REJECT / CANCEL / END
  // =============================================================

  Future<void> rejectCall({
    required String callId,
  }) async {
    await _completeCallWithStatus(
      callId: callId,
      firestoreStatus: CallStatusValues.rejected,
      historyStatus: CallServiceStatus.rejected,
      uiStatus: CallServiceStatus.rejected,
      useEndCallOperation: false,
    );
  }

  Future<void> cancelCall({
    required String callId,
  }) async {
    await _completeCallWithStatus(
      callId: callId,
      firestoreStatus: CallStatusValues.cancelled,
      historyStatus: CallServiceStatus.cancelled,
      uiStatus: CallServiceStatus.cancelled,
      useEndCallOperation: false,
    );
  }

  Future<void> endCall({
    required String callId,
    String status = 'COMPLETED',
  }) async {
    await _completeCallWithStatus(
      callId: callId,
      firestoreStatus: CallStatusValues.ended,
      historyStatus: status,
      uiStatus: CallServiceStatus.ended,
      useEndCallOperation: true,
    );
  }

  Future<void> _completeCallWithStatus({
    required String callId,
    required String firestoreStatus,
    required String historyStatus,
    required String uiStatus,
    required bool useEndCallOperation,
  }) async {
    if (_isDisposed ||
        _isEndingCall ||
        _isCleaningUp) {
      return;
    }

    final String normalizedCallId = callId.trim();

    final String? targetCallId =
    normalizedCallId.isNotEmpty
        ? normalizedCallId
        : _currentCallId;

    if (targetCallId == null ||
        targetCallId.isEmpty) {
      return;
    }

    if (_currentCallId != targetCallId) {
      await _completeDetachedCallWithStatus(
        callId: targetCallId,
        firestoreStatus: firestoreStatus,
        historyStatus: historyStatus,
        uiStatus: uiStatus,
        useEndCallOperation: useEndCallOperation,
      );

      return;
    }

    _isEndingCall = true;

    final int sessionToken = _sessionGeneration;

    final int durationSeconds = _callDurationSeconds;

    final String callType =
    _isVideoCall ? 'video' : 'voice';

    try {
      _emitStatus(
        uiStatus,
        force: true,
      );

      if (useEndCallOperation) {
        await signalingService.endCall(
          targetCallId,
        );
      } else {
        await signalingService.updateCallStatus(
          targetCallId,
          firestoreStatus,
        );
      }

      if (_isSessionCurrent(sessionToken)) {
        await _persistCurrentSessionHistory(
          sessionToken: sessionToken,
          callId: targetCallId,
          durationSeconds: durationSeconds,
          status: historyStatus,
          callType: callType,
        );
      }
    } catch (error, stackTrace) {
      _reportError(
        'Complete call',
        error,
        stackTrace,
      );
    } finally {
      await _cleanupSession(
        sessionToken: sessionToken,
        preserveLastStatus: true,
      );

      _isEndingCall = false;
    }
  }

  // =============================================================
  // DETACHED TERMINAL OPERATION
  // =============================================================

  Future<void> _completeDetachedCallWithStatus({
    required String callId,
    required String firestoreStatus,
    required String historyStatus,
    required String uiStatus,
    required bool useEndCallOperation,
  }) async {
    final bool hasOtherActiveCall =
        _currentCallId != null &&
            _currentCallId != callId;

    String callType = 'voice';

    try {
      try {
        final Map<String, dynamic> callData =
        await signalingService.getCallDocument(
          callId,
        );

        final bool isVideo =
            _readBool(callData['isVideoCall']) ??
                _readBool(callData['video']) ??
                false;

        callType = isVideo ? 'video' : 'voice';
      } catch (error, stackTrace) {
        _reportError(
          'Read detached call metadata',
          error,
          stackTrace,
        );
      }

      if (!hasOtherActiveCall) {
        _emitStatus(
          uiStatus,
          force: true,
        );
      }

      if (useEndCallOperation) {
        await signalingService.endCall(
          callId,
        );
      } else {
        await signalingService.updateCallStatus(
          callId,
          firestoreStatus,
        );
      }

      try {
        await signalingService.saveCallHistory(
          callId: callId,
          duration: 0,
          status: historyStatus,
          callType: callType,
        );
      } catch (error, stackTrace) {
        _reportError(
          'Persist detached call history',
          error,
          stackTrace,
        );
      }
    } catch (error, stackTrace) {
      _reportError(
        'Complete detached call',
        error,
        stackTrace,
      );
    }
  }

  // =============================================================
  // PEER CONNECTION INITIALIZATION
  // =============================================================

  Future<void> _initializePeerConnection({
    required bool video,
    required int sessionToken,
  }) async {
    if (!_isSessionCurrent(sessionToken)) {
      return;
    }

    final Map<String, dynamic> configuration =
    await _loadIceConfiguration();

    if (!_isSessionCurrent(sessionToken)) {
      return;
    }

    final List<Map<String, dynamic>> iceServers =
    _extractIceServers(configuration);

    await webRTCService.initializeConnection(
      video: video,
      audio: true,
      iceServers: iceServers,
    );

    if (!_isSessionCurrent(sessionToken)) {
      return;
    }

    _configureWebRtcCallbacks(
      sessionToken,
    );
  }

  Future<Map<String, dynamic>> _loadIceConfiguration() async {
    try {
      return await _stunTurnService.loadTurnCredential();
    } catch (error, stackTrace) {
      _reportError(
        'TURN credential loading; '
            'using cached/fallback config',
        error,
        stackTrace,
      );

      return _stunTurnService.configuration;
    }
  }

  List<Map<String, dynamic>> _extractIceServers(
      Map<String, dynamic> configuration,
      ) {
    final Object? rawServers =
    configuration['iceServers'];

    if (rawServers is! List) {
      return const <Map<String, dynamic>>[];
    }

    final List<Map<String, dynamic>> result =
    <Map<String, dynamic>>[];

    for (final Object? rawServer in rawServers) {
      if (rawServer is! Map) {
        continue;
      }

      final Map<String, dynamic> server =
      <String, dynamic>{};

      for (final MapEntry<dynamic, dynamic> entry
      in rawServer.entries) {
        server[entry.key.toString()] = entry.value;
      }

      if (server.isNotEmpty) {
        result.add(server);
      }
    }

    return List<Map<String, dynamic>>.unmodifiable(
      result,
    );
  }

  // =============================================================
  // WEBRTC CALLBACKS
  // =============================================================

  void _configureWebRtcCallbacks(
      int sessionToken,
      ) {
    webRTCService.onConnectionStateChanged =
        (RTCPeerConnectionState state) {
      if (!_isSessionCurrent(sessionToken) ||
          _terminalOutcomeInProgress) {
        return;
      }

      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _markCallConnected();
          break;

        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          _emitStatus(
            CallServiceStatus.reconnecting,
          );
          break;

        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _emitStatus(
            CallServiceStatus.reconnecting,
          );

          _recoveryManager.handleRecoveryRequired();
          break;

        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          break;

        default:
          break;
      }
    };

    webRTCService.onIceConnectionStateChanged =
        (RTCIceConnectionState state) {
      if (!_isSessionCurrent(sessionToken) ||
          _terminalOutcomeInProgress) {
        return;
      }

      unawaited(
        _recoveryManager.handleIceConnectionChange(
          state,
          webRTCService.peerConnection,
              () => _restartNativeIceOnly(
            sessionToken,
          ),
        ),
      );
    };

    webRTCService.onSignalingStateChanged =
        (RTCSignalingState state) {
      if (!_isSessionCurrent(sessionToken)) {
        return;
      }

      debugPrint(
        'JR CALL: WebRTC signaling state -> $state',
      );
    };

    webRTCService.onIceGatheringStateChanged =
        (RTCIceGatheringState state) {
      if (!_isSessionCurrent(sessionToken)) {
        return;
      }

      debugPrint(
        'JR CALL: ICE gathering state -> $state',
      );
    };
  }

  // =============================================================
  // ICE MANAGER
  // =============================================================

  Future<void> _initializeIce({
    required String callId,
    required bool isCaller,
    required int sessionToken,
  }) async {
    if (!_isSessionCurrent(sessionToken)) {
      return;
    }

    final RTCPeerConnection? peerConnection =
        webRTCService.peerConnection;

    if (peerConnection == null) {
      throw StateError(
        'Peer connection is unavailable for ICE.',
      );
    }

    await _iceManager.initialize(
      callId: callId,
      isCaller: isCaller,
      peerConnection: peerConnection,
    );

    if (!_isSessionCurrent(sessionToken)) {
      return;
    }

    _iceManager.listenRemoteCandidates(
      callId: callId,
      isCaller: isCaller,
      peerConnection: peerConnection,
    );
  }

  // =============================================================
  // CALL LISTENER INTEGRATION
  // =============================================================

  void _configureCallListener({
    required String callId,
    required int sessionToken,
  }) {
    _callListener.reset();

    _callListener.onStatusChanged =
        (String status) {
      if (!_isActiveCall(
        callId: callId,
        sessionToken: sessionToken,
      )) {
        return;
      }

      _handleRemoteStatus(
        status,
        sessionToken,
      );
    };

    _callListener.onOfferReceived =
        (Map<String, dynamic> offer) {
      if (!_isActiveCall(
        callId: callId,
        sessionToken: sessionToken,
      ) ||
          _currentRole != CallRole.receiver) {
        return;
      }

      unawaited(
        _handleReceiverOffer(
          offer: offer,
          callId: callId,
          sessionToken: sessionToken,
        ),
      );
    };

    _callListener.onAnswerReceived =
        (Map<String, dynamic> answer) {
      if (!_isActiveCall(
        callId: callId,
        sessionToken: sessionToken,
      ) ||
          _currentRole != CallRole.caller) {
        return;
      }

      unawaited(
        _handleCallerAnswer(
          answer: answer,
          callId: callId,
          sessionToken: sessionToken,
        ),
      );
    };

    _callListener.onNetworkRecovered = () {
      if (!_isActiveCall(
        callId: callId,
        sessionToken: sessionToken,
      )) {
        return;
      }

      if (webRTCService.isPeerConnected) {
        _emitStatus(
          CallServiceStatus.reconnected,
          force: true,
        );
      } else {
        _emitStatus(
          CallServiceStatus.reconnecting,
        );
      }
    };

    _callListener.onIceRestart = () {
      if (!_isActiveCall(
        callId: callId,
        sessionToken: sessionToken,
      )) {
        return;
      }

      _emitStatus(
        CallServiceStatus.reconnecting,
      );
    };

    _callListener.onCallDeleted = () {
      if (!_isActiveCall(
        callId: callId,
        sessionToken: sessionToken,
      )) {
        return;
      }

      _lastRemoteTerminalStatus =
          CallStatusValues.ended;

      _emitStatus(
        CallServiceStatus.ended,
        force: true,
      );
    };

    _callListener.onCallEnded = () {
      if (_isDisposed ||
          _currentCallId != callId) {
        return;
      }

      if (_isEndingCall ||
          _isFailingCall ||
          _isCleaningUp) {
        return;
      }

      unawaited(
        _handleRemoteCallEnded(
          callId: callId,
          sessionToken: sessionToken,
        ),
      );
    };

    _callListener.onError = (Object error) {
      _reportError(
        'CallListenerService',
        error,
      );
    };
  }

  void _handleRemoteStatus(
      String rawStatus,
      int sessionToken,
      ) {
    if (!_isSessionCurrent(sessionToken)) {
      return;
    }

    final String status =
    rawStatus.trim().toLowerCase();

    if (status.isEmpty) {
      return;
    }

    if (CallStatusValues.isTerminal(status)) {
      _lastRemoteTerminalStatus = status;

      _emitStatus(
        status.toUpperCase(),
        force: true,
      );

      return;
    }

    if (_lastRemoteTerminalStatus != null) {
      return;
    }

    switch (status) {
      case CallStatusValues.connected:
        if (webRTCService.isPeerConnected) {
          _markCallConnected();
        } else {
          _emitStatus(
            CallServiceStatus.connecting,
          );
        }
        break;

      case CallStatusValues.reconnecting:
        _emitStatus(
          CallServiceStatus.reconnecting,
        );
        break;

      case CallStatusValues.ringing:
        _emitStatus(
          CallServiceStatus.ringing,
        );
        break;

      case 'accepted':
        _emitStatus(
          CallServiceStatus.connecting,
        );
        break;

      case CallStatusValues.connecting:
        _emitStatus(
          CallServiceStatus.connecting,
        );
        break;

      case CallStatusValues.calling:
        _emitStatus(
          CallServiceStatus.calling,
        );
        break;

      default:
        _emitStatus(
          status.toUpperCase(),
        );
        break;
    }
  }

  // =============================================================
  // REMOTE TERMINAL HISTORY
  // =============================================================

  Future<void> _handleRemoteCallEnded({
    required String callId,
    required int sessionToken,
  }) async {
    if (!_isActiveCall(
      callId: callId,
      sessionToken: sessionToken,
    )) {
      return;
    }

    final int durationSeconds =
        _callDurationSeconds;

    final String callType =
    _isVideoCall ? 'video' : 'voice';

    final String historyStatus =
    _historyStatusForRemoteTerminal(
      _lastRemoteTerminalStatus,
    );

    try {
      await _persistCurrentSessionHistory(
        sessionToken: sessionToken,
        callId: callId,
        durationSeconds: durationSeconds,
        status: historyStatus,
        callType: callType,
      );
    } catch (error, stackTrace) {
      _reportError(
        'Persist remote terminal call history',
        error,
        stackTrace,
      );
    }

    await _cleanupSession(
      sessionToken: sessionToken,
      preserveLastStatus: true,
    );
  }

  String _historyStatusForRemoteTerminal(
      String? status,
      ) {
    switch (status?.trim().toLowerCase()) {
      case CallStatusValues.rejected:
        return CallServiceStatus.rejected;

      case CallStatusValues.declined:
        return CallServiceStatus.declined;

      case CallStatusValues.cancelled:
        return CallServiceStatus.cancelled;

      case CallStatusValues.failed:
        return CallServiceStatus.failed;

      case CallStatusValues.timeout:
        return CallServiceStatus.timeout;

      case CallStatusValues.ended:
      default:
        return 'COMPLETED';
    }
  }

  // =============================================================
  // SAME-SESSION HISTORY GUARD
  // =============================================================

  Future<void> _persistCurrentSessionHistory({
    required int sessionToken,
    required String callId,
    required int durationSeconds,
    required String status,
    required String callType,
  }) async {
    if (!_isSessionCurrent(sessionToken) ||
        _historyPersistedForSession) {
      return;
    }

    await signalingService.saveCallHistory(
      callId: callId,
      duration: durationSeconds,
      status: status,
      callType: callType,
    );

    if (_isSessionCurrent(sessionToken)) {
      _historyPersistedForSession = true;
    }
  }

  // =============================================================
  // CALLER ANSWER
  // =============================================================

  Future<void> _handleCallerAnswer({
    required Map<String, dynamic> answer,
    required String callId,
    required int sessionToken,
  }) async {
    if (!_isActiveCall(
      callId: callId,
      sessionToken: sessionToken,
    ) ||
        _currentRole != CallRole.caller ||
        _terminalOutcomeInProgress) {
      return;
    }

    if (!_isValidSessionDescription(
      answer,
      requiredType: 'answer',
    )) {
      return;
    }

    try {
      _emitStatus(
        CallServiceStatus.connecting,
      );

      await _applyRemoteDescription(
        description: answer,
        expectedType: 'answer',
        sessionToken: sessionToken,
      );

      if (!_isActiveCall(
        callId: callId,
        sessionToken: sessionToken,
      ) ||
          _terminalOutcomeInProgress) {
        return;
      }

      await webRTCService.waitUntilConnected(
        timeout: _incomingConnectionTimeout,
      );

      if (!_isActiveCall(
        callId: callId,
        sessionToken: sessionToken,
      ) ||
          _terminalOutcomeInProgress) {
        return;
      }

      if (!webRTCService.isPeerConnected) {
        throw StateError(
          'WebRTC did not reach connected state.',
        );
      }

      final Map<String, dynamic> latestCallData =
      await signalingService.getCallDocument(
        callId,
      );

      if (!_isActiveCall(
        callId: callId,
        sessionToken: sessionToken,
      ) ||
          _terminalOutcomeInProgress) {
        return;
      }

      final String? latestStatus =
      _readString(
        latestCallData[CallFields.status],
      )?.toLowerCase();

      if (latestStatus != null &&
          CallStatusValues.isTerminal(
            latestStatus,
          )) {
        _lastRemoteTerminalStatus =
            latestStatus;

        _emitStatus(
          latestStatus.toUpperCase(),
          force: true,
        );

        await _handleRemoteCallEnded(
          callId: callId,
          sessionToken: sessionToken,
        );

        return;
      }

      await signalingService.updateCallStatus(
        callId,
        CallStatusValues.connected,
      );

      if (!_isActiveCall(
        callId: callId,
        sessionToken: sessionToken,
      ) ||
          _terminalOutcomeInProgress) {
        return;
      }

      _markCallConnected();
    } catch (error, stackTrace) {
      _reportError(
        'Apply caller answer',
        error,
        stackTrace,
      );

      if (_isActiveCall(
        callId: callId,
        sessionToken: sessionToken,
      ) &&
          !_terminalOutcomeInProgress) {
        _recoveryManager.handleRecoveryRequired();
      }
    }
  }

  // =============================================================
  // RECEIVER RESTART OFFER
  // =============================================================

  Future<void> _handleReceiverOffer({
    required Map<String, dynamic> offer,
    required String callId,
    required int sessionToken,
  }) async {
    if (!_isActiveCall(
      callId: callId,
      sessionToken: sessionToken,
    ) ||
        _currentRole != CallRole.receiver ||
        _terminalOutcomeInProgress ||
        !_isValidSessionDescription(
          offer,
          requiredType: 'offer',
        )) {
      return;
    }

    final String? incomingOfferSdp =
    _readString(
      offer[CallFields.sdp],
    );

    // The initial receiver offer is already processed by
    // answerIncomingCall(). When the call listener starts,
    // Firestore sends the existing offer in its first snapshot.
    //
    // Ignore only the exact SDP that was already processed as the
    // initial offer. Do not use _lastStatus as the discriminator:
    // a legitimate ICE-restart offer can arrive while the call is
    // also in CONNECTING/RECONNECTING state.
    if (_currentRole == CallRole.receiver &&
        _initialReceiverOfferSdp != null &&
        incomingOfferSdp == _initialReceiverOfferSdp) {
      debugPrint(
        'JR CALL: Ignoring duplicate initial receiver offer '
            'from the listener snapshot.',
      );

      return;
    }

    // WebRTCService is the sole owner of remote SDP state.
    // Do not perform a native getRemoteDescription() pre-read here:
    // a fresh PeerConnection may legitimately report a null native
    // SessionDescription even though the Firestore offer is valid.
    // WebRTCService performs cache-based duplicate detection atomically
    // with remote-description application.
    if (!_isActiveCall(
      callId: callId,
      sessionToken: sessionToken,
    ) ||
        _terminalOutcomeInProgress) {
      return;
    }

    try {
      _emitStatus(
        CallServiceStatus.reconnecting,
      );

      await _applyRemoteDescription(
        description: offer,
        expectedType: 'offer',
        sessionToken: sessionToken,
      );

      if (!_isActiveCall(
        callId: callId,
        sessionToken: sessionToken,
      ) ||
          _terminalOutcomeInProgress) {
        return;
      }

      final RTCSessionDescription answer =
      await webRTCService.createAnswer();

      if (!_isActiveCall(
        callId: callId,
        sessionToken: sessionToken,
      ) ||
          _terminalOutcomeInProgress) {
        return;
      }

      await signalingService.saveAnswer(
        callId,
        _sessionDescriptionToMap(answer),
      );
    } catch (error, stackTrace) {
      _reportError(
        'Handle receiver restart offer',
        error,
        stackTrace,
      );

      if (_isActiveCall(
        callId: callId,
        sessionToken: sessionToken,
      ) &&
          !_terminalOutcomeInProgress) {
        _recoveryManager.handleRecoveryRequired();
      }
    }
  }

  // =============================================================
  // REMOTE SDP APPLICATION
  // =============================================================

  Future<void> _applyRemoteDescription({
    required Map<String, dynamic> description,
    required String expectedType,
    required int sessionToken,
  }) async {
    if (!_isSessionCurrent(sessionToken)) {
      return;
    }

    final String normalizedExpectedType =
    expectedType.trim().toLowerCase();

    if (normalizedExpectedType.isEmpty) {
      throw ArgumentError.value(
        expectedType,
        'expectedType',
        'Expected WebRTC session-description type '
            'cannot be empty.',
      );
    }

    final String? sdp =
    _readString(
      description[CallFields.sdp],
    );

    final String? rawType =
    _readString(
      description[CallFields.type],
    );

    if (sdp == null || rawType == null) {
      throw StateError(
        'Invalid $normalizedExpectedType '
            'session description.',
      );
    }

    final String type =
    rawType.toLowerCase();

    if (type != normalizedExpectedType) {
      throw StateError(
        'Expected $normalizedExpectedType '
            'session description but received $type.',
      );
    }

    final Future<void>? previousOperation =
        _remoteDescriptionFuture;

    if (previousOperation != null) {
      try {
        await previousOperation;
      } catch (_) {
        // Original operation owns its error.
      }

      if (!_isSessionCurrent(sessionToken)) {
        return;
      }
    }

    final Future<void> operation =
    _performRemoteDescriptionApplication(
      sdp: sdp,
      type: type,
      sessionToken: sessionToken,
    );

    _remoteDescriptionFuture = operation;

    try {
      await operation;
    } finally {
      if (identical(
        _remoteDescriptionFuture,
        operation,
      )) {
        _remoteDescriptionFuture = null;
      }
    }
  }

  Future<void> _performRemoteDescriptionApplication({
    required String sdp,
    required String type,
    required int sessionToken,
  }) async {
    if (!_isSessionCurrent(sessionToken)) {
      return;
    }

    // WebRTCService owns the remote SDP cache and native SDP
    // application. Never read the native remote description as a
    // prerequisite here: flutter_webrtc may return null on a fresh
    // PeerConnection and that null must not prevent the valid
    // Firestore offer/answer from being applied.
    // Duplicate detection is handled by WebRTCService.
    await webRTCService.setRemoteDescription(
      sdp: sdp,
      type: type,
    );

    if (!_isSessionCurrent(sessionToken)) {
      return;
    }

    await _iceManager.flushPendingCandidates(
      webRTCService.peerConnection,
    );
  }

  // =============================================================
  // RECOVERY INTEGRATION
  // =============================================================

  void _configureRecoveryCallbacks() {
    _recoveryManager.onRecoverySuccess = () {
      final String? callId = _currentCallId;

      if (callId == null ||
          _isDisposed ||
          _terminalOutcomeInProgress) {
        return;
      }

      _nativeIceRestartPrepared = false;

      if (webRTCService.isPeerConnected) {
        _emitStatus(
          CallServiceStatus.reconnected,
          force: true,
        );
      } else {
        _emitStatus(
          CallServiceStatus.reconnecting,
        );
      }

      unawaited(
        signalingService.markNetworkRecovered(
          callId,
          true,
        ),
      );
    };

    _recoveryManager.onRecoveryFailed = () {
      final String? callId = _currentCallId;

      _nativeIceRestartPrepared = false;

      if (callId == null ||
          _isEndingCall ||
          _isFailingCall ||
          _isCleaningUp ||
          _isDisposed ||
          _terminalOutcomeInProgress) {
        return;
      }

      unawaited(
        _completeCallWithStatus(
          callId: callId,
          firestoreStatus: CallStatusValues.failed,
          historyStatus: CallServiceStatus.failed,
          uiStatus: CallServiceStatus.failed,
          useEndCallOperation: false,
        ),
      );
    };

    _recoveryManager.onRestartSignalingListener =
        (String callId) {
      if (_isDisposed ||
          _currentCallId != callId ||
          _terminalOutcomeInProgress) {
        return;
      }

      _callListener.restartListening(
        callId,
      );
    };

    // -----------------------------------------------------------
    // EXACT FILE 17 CALLBACK CONTRACT
    //
    // Future<void> Function(
    //   String callId,
    //   Future<void> Function()? nativeRestart,
    // )?
    //
    // IMPORTANT:
    //
    // The second parameter is intentionally NULLABLE.
    //
    // RecoveryManager supplies:
    // - exact callId
    // - optional native-only restart callback
    //
    // CallService owns:
    // - lifecycle coordination
    // - native restart when available
    // - restart offer creation
    // - offer persistence
    // - restart metadata persistence
    // -----------------------------------------------------------

    _recoveryManager.onCallerRecoveryRequired =
        (
        String recoveryCallId,
        Future<void> Function()? nativeRestart,
        ) async {
      final String normalizedCallId =
      recoveryCallId.trim();

      final int sessionToken =
          _sessionGeneration;

      if (_isDisposed ||
          normalizedCallId.isEmpty ||
          _currentCallId != normalizedCallId ||
          _currentRole != CallRole.caller ||
          _terminalOutcomeInProgress ||
          !_isActiveCall(
            callId: normalizedCallId,
            sessionToken: sessionToken,
          )) {
        return;
      }

      await _restartIceSignaling(
        sessionToken: sessionToken,
        recoveryCallId: normalizedCallId,
        nativeRestart: nativeRestart,
      );
    };
  }

  void _configureRecoveryContext({
    required String callId,
    required String userId,
    required bool isCaller,
  }) {
    _recoveryManager.setCallContext(
      callId: callId,
      userId: userId,
      isCaller: isCaller,
    );

    _configureRecoveryCallbacks();
  }

  // =============================================================
  // NATIVE-ONLY ICE RESTART
  // =============================================================

  Future<void> _restartNativeIceOnly(
      int sessionToken,
      ) async {
    if (_isDisposed ||
        !_isSessionCurrent(sessionToken) ||
        _currentRole != CallRole.caller ||
        _terminalOutcomeInProgress ||
        _nativeIceRestartPrepared) {
      return;
    }

    final Future<void>? active =
        _nativeIceRestartFuture;

    if (active != null) {
      await active;

      return;
    }

    final Future<void> operation =
    _performNativeIceRestart(
      sessionToken,
    );

    _nativeIceRestartFuture = operation;

    try {
      await operation;
    } finally {
      if (identical(
        _nativeIceRestartFuture,
        operation,
      )) {
        _nativeIceRestartFuture = null;
      }
    }
  }

  Future<void> _performNativeIceRestart(
      int sessionToken,
      ) async {
    if (_isDisposed ||
        !_isSessionCurrent(sessionToken) ||
        _terminalOutcomeInProgress) {
      return;
    }

    final RTCPeerConnection? peerConnection =
        webRTCService.peerConnection;

    if (peerConnection == null) {
      throw StateError(
        'Peer connection is unavailable for ICE restart.',
      );
    }

    await peerConnection.restartIce();

    if (!_isSessionCurrent(sessionToken) ||
        _terminalOutcomeInProgress) {
      return;
    }

    _nativeIceRestartPrepared = true;
  }

  // =============================================================
  // COMPLETE CALLER ICE-RESTART SIGNALING
  // =============================================================

  Future<void> _restartIceSignaling({
    required int sessionToken,
    required String recoveryCallId,
    required Future<void> Function()? nativeRestart,
  }) async {
    final String normalizedRecoveryCallId =
    recoveryCallId.trim();

    if (_isDisposed ||
        normalizedRecoveryCallId.isEmpty ||
        !_isSessionCurrent(sessionToken) ||
        _currentCallId != normalizedRecoveryCallId ||
        _currentRole != CallRole.caller ||
        _isPerformingIceRestart ||
        _terminalOutcomeInProgress) {
      return;
    }

    _isPerformingIceRestart = true;

    try {
      _emitStatus(
        CallServiceStatus.reconnecting,
      );

      final Map<String, dynamic> callData =
      await signalingService.getCallDocument(
        normalizedRecoveryCallId,
      );

      if (!_isActiveCall(
        callId: normalizedRecoveryCallId,
        sessionToken: sessionToken,
      ) ||
          _terminalOutcomeInProgress) {
        return;
      }

      final String? currentStatus =
      _readString(
        callData[CallFields.status],
      )?.toLowerCase();

      if (currentStatus != null &&
          CallStatusValues.isTerminal(
            currentStatus,
          )) {
        _lastRemoteTerminalStatus =
            currentStatus;

        return;
      }

      // Persist RECONNECTING only where FILE 01 lifecycle permits.
      if (currentStatus ==
          CallStatusValues.connecting ||
          currentStatus ==
              CallStatusValues.connected ||
          currentStatus ==
              CallStatusValues.reconnecting) {
        await signalingService.updateCallStatus(
          normalizedRecoveryCallId,
          CallStatusValues.reconnecting,
        );
      }

      if (!_isActiveCall(
        callId: normalizedRecoveryCallId,
        sessionToken: sessionToken,
      ) ||
          _terminalOutcomeInProgress) {
        return;
      }

      await signalingService.markNetworkRecovered(
        normalizedRecoveryCallId,
        false,
      );

      if (!_isActiveCall(
        callId: normalizedRecoveryCallId,
        sessionToken: sessionToken,
      ) ||
          _terminalOutcomeInProgress) {
        return;
      }

      final RTCSessionDescription offer;

      // ---------------------------------------------------------
      // EXACTLY-ONCE NATIVE RESTART
      //
      // FILE 17 intentionally allows nativeRestart == null.
      //
      // Case A:
      // RecoveryManager supplies native callback.
      // -> execute that callback once
      // -> create only the restart offer afterwards
      //
      // Case B:
      // callback is unavailable.
      // -> WebRTCService performs native restart + creates offer
      //
      // Therefore complete recovery remains functional without
      // inventing a second native restart.
      // ---------------------------------------------------------

      if (_nativeIceRestartPrepared) {
        offer = await webRTCService.createOffer(
          iceRestart: true,
        );
      } else if (nativeRestart != null) {
        await nativeRestart();

        if (!_isActiveCall(
          callId: normalizedRecoveryCallId,
          sessionToken: sessionToken,
        ) ||
            _terminalOutcomeInProgress) {
          return;
        }

        if (!_nativeIceRestartPrepared) {
          throw StateError(
            'Native ICE restart callback completed '
                'without preparing the active restart.',
          );
        }

        offer = await webRTCService.createOffer(
          iceRestart: true,
        );
      } else {
        // FILE 17 explicitly permits the callback to be null.
        //
        // In this fallback path WebRTCService performs the complete
        // transport restart exactly once and returns the restart
        // offer. No second native restart is invoked afterwards.
        offer =
        await webRTCService.performIceRestart();
      }

      if (!_isActiveCall(
        callId: normalizedRecoveryCallId,
        sessionToken: sessionToken,
      ) ||
          _terminalOutcomeInProgress) {
        return;
      }

      await signalingService.saveOffer(
        normalizedRecoveryCallId,
        _sessionDescriptionToMap(offer),
      );

      if (!_isActiveCall(
        callId: normalizedRecoveryCallId,
        sessionToken: sessionToken,
      ) ||
          _terminalOutcomeInProgress) {
        return;
      }

      await signalingService.incrementIceRestart(
        normalizedRecoveryCallId,
      );

      _nativeIceRestartPrepared = false;
    } catch (error, stackTrace) {
      _nativeIceRestartPrepared = false;

      _reportError(
        'ICE restart signaling',
        error,
        stackTrace,
      );

      if (_isActiveCall(
        callId: normalizedRecoveryCallId,
        sessionToken: sessionToken,
      ) &&
          !_terminalOutcomeInProgress) {
        _recoveryManager.handleRecoveryRequired();
      }
    } finally {
      _isPerformingIceRestart = false;

      _nativeIceRestartPrepared = false;
    }
  }

  // =============================================================
  // CONNECTION MANAGER
  // =============================================================

  void _handleConnectionState(
      ConnectionStateModel state,
      ) {
    if (_isDisposed) {
      return;
    }

    switch (state) {
      case ConnectionStateModel.connected:
        final bool wasUnavailable =
        !_networkAvailable;

        _networkAvailable = true;

        if (_currentCallId != null &&
            wasUnavailable &&
            !_terminalOutcomeInProgress) {
          _recoveryManager.handleNetworkRestored();
        }

        break;

      case ConnectionStateModel.reconnecting:
        if (_currentCallId != null &&
            !_terminalOutcomeInProgress) {
          _emitStatus(
            CallServiceStatus.reconnecting,
          );
        }

        break;

      case ConnectionStateModel.disconnected:
        _networkAvailable = false;

        if (_currentCallId != null &&
            !_terminalOutcomeInProgress) {
          _emitStatus(
            CallServiceStatus.networkLost,
          );

          _recoveryManager.handleRecoveryRequired();
        }

        break;
    }
  }

  // =============================================================
  // CALL TIMEOUT
  // =============================================================

  void _startCallTimeoutTimer(
      int sessionToken,
      ) {
    _callTimeoutTimer?.cancel();

    _callTimeoutTimer =
        Timer(
          _outgoingCallTimeout,
              () {
            final String? callId =
                _currentCallId;

            if (!_isSessionCurrent(sessionToken) ||
                callId == null ||
                webRTCService.isPeerConnected ||
                _terminalOutcomeInProgress) {
              return;
            }

            unawaited(
              _completeCallWithStatus(
                callId: callId,
                firestoreStatus:
                CallStatusValues.timeout,
                historyStatus:
                CallServiceStatus.timeout,
                uiStatus:
                CallServiceStatus.timeout,
                useEndCallOperation: false,
              ),
            );
          },
        );
  }

  // =============================================================
  // CALL DURATION
  // =============================================================

  void _startCallDurationTimer() {
    _callTimeoutTimer?.cancel();

    _callTimeoutTimer = null;

    if (_callDurationTimer?.isActive == true) {
      return;
    }

    _callDurationSeconds = 0;

    _emitDuration(0);

    _callDurationTimer =
        Timer.periodic(
          const Duration(seconds: 1),
              (_) {
            if (_currentCallId == null ||
                _isDisposed ||
                _terminalOutcomeInProgress ||
                !webRTCService.isPeerConnected) {
              return;
            }

            _callDurationSeconds++;

            _emitDuration(
              _callDurationSeconds,
            );
          },
        );
  }

  void _markCallConnected() {
    if (_currentCallId == null ||
        _isDisposed ||
        _terminalOutcomeInProgress ||
        !webRTCService.isPeerConnected) {
      return;
    }

    _nativeIceRestartPrepared = false;

    _emitStatus(
      CallServiceStatus.connected,
    );

    if (_callDurationTimer?.isActive != true) {
      _startCallDurationTimer();
    }

    _recoveryManager.stopRecovery();
  }

  // =============================================================
  // LEGACY COMPATIBILITY
  // =============================================================

  Future<RTCSessionDescription> answerCall() async {
    return webRTCService.createAnswer();
  }

  Future<void> setRemoteOffer({
    required String sdp,
    required String type,
  }) async {
    final String normalizedSdp = sdp.trim();

    final String normalizedType =
    type.trim().toLowerCase();

    if (normalizedSdp.isEmpty ||
        normalizedType.isEmpty) {
      throw ArgumentError(
        'Remote offer SDP and type are required.',
      );
    }

    await webRTCService.setRemoteDescription(
      sdp: normalizedSdp,
      type: normalizedType,
    );

    await _iceManager.flushPendingCandidates(
      webRTCService.peerConnection,
    );
  }

  // =============================================================
  // SESSION MANAGEMENT
  // =============================================================

  int _beginNewSession() {
    _sessionGeneration++;

    _callTimeoutTimer?.cancel();

    _callTimeoutTimer = null;

    _callDurationTimer?.cancel();

    _callDurationTimer = null;

    _remoteDescriptionFuture = null;

    _nativeIceRestartFuture = null;

    _callDurationSeconds = 0;

    _lastStatus = null;

    _initialReceiverOfferSdp = null;

    _lastRemoteTerminalStatus = null;

    _historyPersistedForSession = false;

    _isPerformingIceRestart = false;

    _nativeIceRestartPrepared = false;

    return _sessionGeneration;
  }

  bool _isSessionCurrent(
      int sessionToken,
      ) {
    return !_isDisposed &&
        sessionToken == _sessionGeneration;
  }

  bool _isActiveCall({
    required String callId,
    required int sessionToken,
  }) {
    return _isSessionCurrent(sessionToken) &&
        _currentCallId == callId;
  }

  // =============================================================
  // FAILURE
  // =============================================================

  Future<void> _failCurrentCall({
    required int sessionToken,
    required String? callId,
  }) async {
    if (!_isSessionCurrent(sessionToken) ||
        _isFailingCall) {
      return;
    }

    _isFailingCall = true;

    final int durationSeconds =
        _callDurationSeconds;

    final String callType =
    _isVideoCall ? 'video' : 'voice';

    try {
      _emitStatus(
        CallServiceStatus.failed,
        force: true,
      );

      if (callId != null &&
          callId.trim().isNotEmpty) {
        final String normalizedCallId =
        callId.trim();

        try {
          await signalingService.updateCallStatus(
            normalizedCallId,
            CallStatusValues.failed,
          );

          if (_isSessionCurrent(sessionToken)) {
            await _persistCurrentSessionHistory(
              sessionToken: sessionToken,
              callId: normalizedCallId,
              durationSeconds: durationSeconds,
              status: CallServiceStatus.failed,
              callType: callType,
            );
          }
        } catch (error, stackTrace) {
          _reportError(
            'Persist failed call',
            error,
            stackTrace,
          );
        }
      }

      await _cleanupSession(
        sessionToken: sessionToken,
        preserveLastStatus: true,
      );
    } finally {
      _isFailingCall = false;
    }
  }

  // =============================================================
  // CLEANUP
  // =============================================================

  Future<void> _cleanupSession({
    required int sessionToken,
    required bool preserveLastStatus,
    bool force = false,
  }) async {
    if (_isCleaningUp) {
      return;
    }

    if (!force &&
        sessionToken != _sessionGeneration) {
      return;
    }

    _isCleaningUp = true;

    _sessionGeneration++;

    try {
      _callTimeoutTimer?.cancel();

      _callTimeoutTimer = null;

      _callDurationTimer?.cancel();

      _callDurationTimer = null;

      _remoteDescriptionFuture = null;

      _nativeIceRestartFuture = null;

      _nativeIceRestartPrepared = false;

      _isPerformingIceRestart = false;

      // Cleanup order:
      //
      // 1. Stop call-document callbacks.
      // 2. Detach IceManager from active PeerConnection.
      // 3. Reset recovery policy.
      // 4. Remove CallService-owned WebRTC callbacks.
      // 5. Release WebRTC resources.

      _callListener.reset();

      _iceManager.reset();

      _recoveryManager.reset();

      webRTCService.onConnectionStateChanged = null;

      webRTCService.onIceConnectionStateChanged =
      null;

      webRTCService.onSignalingStateChanged =
      null;

      webRTCService.onIceGatheringStateChanged =
      null;

      await webRTCService.dispose();
    } catch (error, stackTrace) {
      _reportError(
        'Call resource cleanup',
        error,
        stackTrace,
      );
    } finally {
      _currentCallId = null;

      _currentUserId = null;

      _currentPeerId = null;

      _currentRole = CallRole.none;

      _isVideoCall = true;

      _callDurationSeconds = 0;

      _isStartingCall = false;

      _isAnsweringCall = false;

      _isPerformingIceRestart = false;

      _nativeIceRestartFuture = null;

      _nativeIceRestartPrepared = false;

      _lastRemoteTerminalStatus = null;

      if (!preserveLastStatus) {
        _lastStatus = null;
      }

      _emitDuration(0);

      _isCleaningUp = false;

      if (!_isDisposed) {
        _configureRecoveryCallbacks();
      }
    }
  }

  // =============================================================
  // STATUS / ERROR
  // =============================================================

  void _emitStatus(
      String status, {
        bool force = false,
      }) {
    final String normalizedStatus =
    status.trim().toUpperCase();

    if (normalizedStatus.isEmpty) {
      return;
    }

    if (!force &&
        normalizedStatus == _lastStatus) {
      return;
    }

    _lastStatus = normalizedStatus;

    if (!_callStatusController.isClosed) {
      _callStatusController.add(
        normalizedStatus,
      );
    }
  }

  void _emitDuration(
      int duration,
      ) {
    if (!_callDurationController.isClosed) {
      _callDurationController.add(
        duration,
      );
    }
  }

  void _reportError(
      String source,
      Object error, [
        StackTrace? stackTrace,
      ]) {
    debugPrint(
      'JR CALL [$source] error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label: 'JR CALL [$source]',
        stackTrace: stackTrace,
      );
    }
  }

  // =============================================================
  // DATA HELPERS
  // =============================================================

  Map<String, dynamic> _sessionDescriptionToMap(
      RTCSessionDescription description,
      ) {
    final String? rawSdp =
        description.sdp;

    final String? rawType =
        description.type;

    if (rawSdp == null ||
        rawType == null) {
      throw StateError(
        'WebRTC session description is invalid.',
      );
    }

    final String sdp =
    rawSdp.trim();

    final String type =
    rawType.trim().toLowerCase();

    if (sdp.isEmpty ||
        type.isEmpty) {
      throw StateError(
        'WebRTC session description is invalid.',
      );
    }

    if (type != 'offer' &&
        type != 'answer') {
      throw StateError(
        'Unsupported WebRTC session '
            'description type: $type',
      );
    }

    return <String, dynamic>{
      CallFields.type: type,
      CallFields.sdp: sdp,
    };
  }

  String? _readString(
      Object? value,
      ) {
    if (value is! String) {
      return null;
    }

    final String normalized =
    value.trim();

    return normalized.isEmpty
        ? null
        : normalized;
  }

  bool? _readBool(
      Object? value,
      ) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      if (value == 1) {
        return true;
      }

      if (value == 0) {
        return false;
      }
    }

    if (value is String) {
      final String normalized =
      value.trim().toLowerCase();

      if (normalized == 'true' ||
          normalized == '1' ||
          normalized == 'yes') {
        return true;
      }

      if (normalized == 'false' ||
          normalized == '0' ||
          normalized == 'no') {
        return false;
      }
    }

    return null;
  }

  Map<String, dynamic>? _normalizeMap(
      Object? value,
      ) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(
        value,
      );
    }

    if (value is Map) {
      final Map<String, dynamic> result =
      <String, dynamic>{};

      for (final MapEntry<dynamic, dynamic> entry
      in value.entries) {
        if (entry.key is! String) {
          return null;
        }

        result[entry.key as String] =
            entry.value;
      }

      return result;
    }

    return null;
  }

  bool _isValidSessionDescription(
      Map<String, dynamic>? description, {
        required String requiredType,
      }) {
    if (description == null) {
      return false;
    }

    final String normalizedRequiredType =
    requiredType.trim().toLowerCase();

    if (normalizedRequiredType.isEmpty) {
      return false;
    }

    final String? sdp =
    _readString(
      description[CallFields.sdp],
    );

    final String? rawType =
    _readString(
      description[CallFields.type],
    );

    if (sdp == null ||
        rawType == null) {
      return false;
    }

    return rawType.toLowerCase() ==
        normalizedRequiredType;
  }

  // =============================================================
  // COMPLETE DISPOSAL
  // =============================================================

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    WidgetsBinding.instance.removeObserver(
      this,
    );

    _isDisposed = true;

    _isInfrastructureInitialized = false;

    final Future<void>? pendingInitialization =
        _infrastructureInitializationFuture;

    if (pendingInitialization != null) {
      try {
        await pendingInitialization;
      } catch (error, stackTrace) {
        _reportError(
          'Pending infrastructure disposal',
          error,
          stackTrace,
        );
      }
    }

    await _connectionSubscription?.cancel();

    _connectionSubscription = null;

    await _cleanupSession(
      sessionToken: _sessionGeneration,
      preserveLastStatus: false,
      force: true,
    );

    if (!_callStatusController.isClosed) {
      await _callStatusController.close();
    }

    if (!_callDurationController.isClosed) {
      await _callDurationController.close();
    }

    debugPrint(
      'JR CALL: CallService disposed.',
    );
  }
}

// ===============================================================
// END OF FILE
//
// FILE 28 FINAL EXACT FILE-17 ALIGNMENT:
//
// ✓ Existing CallService public API preserved.
// ✓ Existing lifecycle logic preserved.
// ✓ Firebase UID identity preserved.
// ✓ SignalingService ownership preserved.
// ✓ IceManager ownership preserved.
// ✓ WebRTCService ownership preserved.
// ✓ RecoveryManager retry/backoff ownership preserved.
//
// ✓ Exact RecoveryManager callback signature used:
//
// Future<void> Function(
//   String callId,
//   Future<void> Function()? nativeRestart,
// )?
//
// ✓ nativeRestart is correctly nullable.
// ✓ Previous compile-time callback mismatch removed.
// ✓ No zero-argument callback guess remains.
// ✓ Native callback remains transport-only.
// ✓ Null native callback has safe complete-restart fallback.
// ✓ Non-null native callback executes only once.
// ✓ Native restart single-flight protection preserved.
// ✓ Restart offer still uses iceRestart: true.
// ✓ No second native restart after callback.
// ✓ Restart offer remains SignalingService persisted.
// ✓ Restart counter remains SignalingService persisted.
// ✓ networkRecovered metadata preserved.
// ✓ Illegal early reconnecting lifecycle write blocked.
// ✓ Terminal resurrection protection preserved.
// ✓ Caller answer terminal guard preserved.
// ✓ Receiver offer terminal guard preserved.
// ✓ Duration real-WebRTC-only behavior preserved.
// ✓ Detached-call protection preserved.
// ✓ Same-session history guard preserved.
// ✓ TURN/STUN flow preserved.
// ✓ No UI/design changes.
// ✓ No Message/Profile/Auth ownership added.
//
// ✓ Initial receiver offer SDP is stored per session.
// ✓ Listener duplicate initial offer is ignored by exact SDP match.
// ✓ Lowercase _lastStatus comparison removed from duplicate guard.
// ✓ Legitimate later ICE-restart offers remain processable.
//
// STATUS:
// FILE 28 — READY FOR IDE VERIFICATION.
//
// AFTER SAVE:
// Android Studio -> Problems -> File
//
// REQUIRED:
// No problems in call_service.dart
//
// NEXT AFTER FILE 28 PASSES:
// FILE 29
// lib/screens/incoming_call_screen.dart
// ===============================================================