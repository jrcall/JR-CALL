// ===============================================================
// JR CALL
// File: call_session_screen.dart
// Location: lib/screens/call_session_screen.dart
//
// MASTER ACTIVE CALL SESSION COORDINATOR
//
// OUTGOING:
// Contacts/Profile
//   -> CallService.startCall()
//   -> CallSessionScreen
//   -> OutgoingCallScreen
//   -> real WebRTC CONNECTED
//   -> VoiceCallScreen / VideoCallScreen
//
// INCOMING:
// IncomingCallScreen
//   -> CallService.acceptCall()
//   -> CallSessionScreen(showOutgoingStage: false)
//   -> VoiceCallScreen / VideoCallScreen
//
// IMPORTANT:
//
// - CallService remains lifecycle authority.
// - WebRTCService remains media/PeerConnection authority.
// - CallScreenProvider is presentation bridge only.
// - VideoProvider is video-control presentation bridge only.
// - NetworkProvider is network presentation bridge only.
// - No Firestore call-state writes here.
// - No signaling ownership here.
// - No ICE/recovery ownership here.
// - No duplicate timer.
// - No fake CONNECTED state.
// - Existing Voice/Video/Outgoing UI remains unchanged.
// ===============================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/network_model.dart';
import '../models/user_model.dart';
import '../providers/call_screen_provider.dart';
import '../providers/network_provider.dart';
import '../providers/video_provider.dart';
import '../services/call/call_service.dart';
import '../services/firebase/firestore_service.dart';
import 'outgoing_call_screen.dart';
import 'video_call_screen.dart';
import 'voice_call_screen.dart';

class CallSessionScreen extends StatefulWidget {
  const CallSessionScreen({
    super.key,
    required this.callerName,
    required this.isVideoCall,
    this.callerImage,
    this.remoteUid,
    this.showOutgoingStage = true,
    this.initialStatus = CallServiceStatus.calling,
    this.initialDurationSeconds = 0,
  });

  final String callerName;

  final String? callerImage;

  /// Canonical remote Firebase UID.
  ///
  /// Used only to resolve presentation identity when necessary.
  /// It is never exposed as a public search identity.
  final String? remoteUid;

  final bool isVideoCall;

  final bool showOutgoingStage;

  final String initialStatus;

  final int initialDurationSeconds;

  @override
  State<CallSessionScreen> createState() =>
      _CallSessionScreenState();
}

class _CallSessionScreenState
    extends State<CallSessionScreen> {
  // =============================================================
  // SERVICES / PROVIDERS
  // =============================================================

  final CallService _callService = CallService();

  final FirestoreService _firestore =
      FirestoreService.instance;

  late final CallScreenProvider _callScreenProvider =
  CallScreenProvider(
    callService: _callService,
  );

  final VideoProvider _videoProvider =
  VideoProvider();

  final NetworkProvider _networkProvider =
  NetworkProvider();

  // =============================================================
  // STREAMS
  // =============================================================

  StreamSubscription<String>? _statusSubscription;

  final StreamController<NetworkQuality>
  _networkQualityController =
  StreamController<NetworkQuality>.broadcast();

  // =============================================================
  // PRESENTATION STATE
  // =============================================================

  late String _status;

  late int _durationSeconds;

  late String _displayName;

  String? _displayImage;

  bool _activeScreenOpened = false;

  bool _disposed = false;

  bool _endingCall = false;

  // =============================================================
  // INITIAL VALUES
  // =============================================================

  String get _safeInitialStatus {
    final String value =
    widget.initialStatus.trim().toUpperCase();

    return value.isEmpty
        ? CallServiceStatus.connecting
        : value;
  }

  int get _safeInitialDuration {
    final int value =
        widget.initialDurationSeconds;

    return value < 0 ? 0 : value;
  }

  String _safeName(
      String value,
      ) {
    final String normalized =
    value.trim();

    return normalized.isEmpty
        ? 'JR CALL User'
        : normalized;
  }

  String? _nonEmpty(
      String? value,
      ) {
    final String normalized =
        value?.trim() ?? '';

    return normalized.isEmpty
        ? null
        : normalized;
  }

  String? get _resolvedRemoteUid {
    final String supplied =
        widget.remoteUid?.trim() ?? '';

    if (supplied.isNotEmpty) {
      return supplied;
    }

    final String serviceValue =
        _callService.currentPeerId?.trim() ?? '';

    return serviceValue.isEmpty
        ? null
        : serviceValue;
  }

  // =============================================================
  // LIFECYCLE
  // =============================================================

  @override
  void initState() {
    super.initState();

    _status = _safeInitialStatus;

    _durationSeconds =
        _safeInitialDuration;

    _displayName =
        _safeName(
          widget.callerName,
        );

    _displayImage =
        _nonEmpty(
          widget.callerImage,
        );

    _activeScreenOpened =
        !widget.showOutgoingStage ||
            _isConnectedStatus(
              _status,
            );

    _callScreenProvider.addListener(
      _handlePresentationChanged,
    );

    _videoProvider.addListener(
      _handlePresentationChanged,
    );

    _networkProvider.addListener(
      _handleNetworkChanged,
    );

    _statusSubscription =
        _callService.callStatusStream.listen(
          _handleCallStatus,
          onError: (
              Object error,
              StackTrace stackTrace,
              ) {
            _reportError(
              'Call status stream',
              error,
              stackTrace,
            );
          },
        );

    unawaited(
      _initializePresentation(),
    );
  }

  Future<void> _initializePresentation() async {
    // -----------------------------------------------------------
    // ACTIVE CALL PRESENTATION BRIDGE
    // -----------------------------------------------------------

    try {
      await _callScreenProvider.initialize();

      if (_disposed) {
        return;
      }

      _durationSeconds =
          _callScreenProvider.durationSeconds;

      _recoverCurrentConnectedState();
    } catch (error, stackTrace) {
      _reportError(
        'Call presentation initialization',
        error,
        stackTrace,
      );
    }

    // -----------------------------------------------------------
    // NETWORK PRESENTATION
    // -----------------------------------------------------------

    try {
      await _networkProvider.initialize();

      if (_disposed) {
        return;
      }

      _emitNetworkQuality(
        _networkProvider.quality,
      );
    } catch (error, stackTrace) {
      _reportError(
        'Network presentation initialization',
        error,
        stackTrace,
      );
    }

    // -----------------------------------------------------------
    // VIDEO PRESENTATION
    // -----------------------------------------------------------

    if (widget.isVideoCall) {
      try {
        await _videoProvider.initialize();
      } catch (error, stackTrace) {
        _reportError(
          'Video presentation initialization',
          error,
          stackTrace,
        );
      }
    }

    // -----------------------------------------------------------
    // REMOTE PUBLIC PROFILE PRESENTATION
    // -----------------------------------------------------------

    await _loadRemoteIdentity();

    if (_disposed) {
      return;
    }

    _recoverCurrentConnectedState();

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _disposed = true;

    final StreamSubscription<String>?
    statusSubscription =
        _statusSubscription;

    _statusSubscription = null;

    if (statusSubscription != null) {
      unawaited(
        statusSubscription.cancel(),
      );
    }

    _callScreenProvider.removeListener(
      _handlePresentationChanged,
    );

    _videoProvider.removeListener(
      _handlePresentationChanged,
    );

    _networkProvider.removeListener(
      _handleNetworkChanged,
    );

    _callScreenProvider.dispose();

    _videoProvider.dispose();

    _networkProvider.dispose();

    if (!_networkQualityController.isClosed) {
      unawaited(
        _networkQualityController.close(),
      );
    }

    super.dispose();
  }

  // =============================================================
  // REMOTE IDENTITY
  // =============================================================

  Future<void> _loadRemoteIdentity() async {
    final String? remoteUid =
        _resolvedRemoteUid;

    if (remoteUid == null ||
        remoteUid.isEmpty ||
        _disposed) {
      return;
    }

    try {
      final UserModel? profile =
      await _firestore.getUser(
        remoteUid,
      );

      if (_disposed ||
          profile == null) {
        return;
      }

      final String resolvedName =
      profile.displayName.trim();

      final String? resolvedImage =
      _nonEmpty(
        profile.profilePhotoUrl,
      );

      if (resolvedName.isNotEmpty) {
        _displayName =
            resolvedName;
      }

      if (resolvedImage != null) {
        _displayImage =
            resolvedImage;
      }
    } catch (error, stackTrace) {
      // Identity loading is presentation-only.
      // A profile read failure must never terminate a valid call.
      _reportError(
        'Remote identity',
        error,
        stackTrace,
      );
    }
  }

  // =============================================================
  // LATE CONNECTED-STATE RECOVERY
  //
  // callStatusStream is a broadcast event stream. A very fast
  // receiver may complete WebRTC connection before this route
  // finishes subscribing.
  //
  // Therefore the active PeerConnection itself is also checked.
  //
  // This is NOT a fake connected state:
  // WebRTCService.isPeerConnected must be true.
  // =============================================================

  void _recoverCurrentConnectedState() {
    if (_disposed ||
        _isTerminalStatus(
          _status,
        )) {
      return;
    }

    final String currentCallId =
        _callService.currentCallId?.trim() ?? '';

    if (currentCallId.isEmpty) {
      return;
    }

    if (!_callService
        .webRTCService
        .isPeerConnected) {
      return;
    }

    _status =
        CallServiceStatus.connected;

    _durationSeconds =
    _callService.callDurationSeconds < 0
        ? 0
        : _callService.callDurationSeconds;

    _activeScreenOpened = true;
  }

  // =============================================================
  // CALL STATUS
  // =============================================================

  void _handleCallStatus(
      String rawStatus,
      ) {
    if (_disposed) {
      return;
    }

    final String normalized =
    rawStatus.trim().toUpperCase();

    if (normalized.isEmpty) {
      return;
    }

    final bool shouldOpenActiveScreen =
    _isConnectedStatus(
      normalized,
    );

    if (!mounted) {
      _status = normalized;

      if (shouldOpenActiveScreen) {
        _activeScreenOpened = true;
      }

      return;
    }

    setState(() {
      _status = normalized;

      if (shouldOpenActiveScreen) {
        _activeScreenOpened = true;
      }
    });
  }

  bool _isConnectedStatus(
      String status,
      ) {
    final String normalized =
    status.trim().toUpperCase();

    return normalized ==
        CallServiceStatus.connected ||
        normalized ==
            CallServiceStatus.reconnected;
  }

  bool _isTerminalStatus(
      String status,
      ) {
    switch (status.trim().toUpperCase()) {
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

  bool _shouldEndConnectedCall(
      String status,
      ) {
    switch (status.trim().toUpperCase()) {
      case CallServiceStatus.connected:
      case CallServiceStatus.reconnected:
      case CallServiceStatus.reconnecting:
      case CallServiceStatus.networkLost:
        return true;

      default:
        return _activeScreenOpened;
    }
  }

  // =============================================================
  // PROVIDER SYNCHRONIZATION
  // =============================================================

  void _handlePresentationChanged() {
    if (_disposed) {
      return;
    }

    final int nextDuration =
        _callScreenProvider.durationSeconds;

    if (!mounted) {
      _durationSeconds =
      nextDuration < 0
          ? 0
          : nextDuration;

      _recoverCurrentConnectedState();

      return;
    }

    setState(() {
      _durationSeconds =
      nextDuration < 0
          ? 0
          : nextDuration;

      _recoverCurrentConnectedState();
    });
  }

  void _handleNetworkChanged() {
    if (_disposed) {
      return;
    }

    _emitNetworkQuality(
      _networkProvider.quality,
    );

    if (mounted) {
      setState(() {});
    }
  }

  void _emitNetworkQuality(
      NetworkQuality quality,
      ) {
    if (_disposed ||
        _networkQualityController.isClosed) {
      return;
    }

    _networkQualityController.add(
      quality,
    );
  }

  // =============================================================
  // END / CANCEL
  // =============================================================

  Future<void> _handleEndCall() async {
    if (_disposed ||
        _endingCall ||
        _isTerminalStatus(
          _status,
        )) {
      return;
    }

    final String? callId =
        _callScreenProvider.callId ??
            _callService.currentCallId;

    if (callId == null ||
        callId.trim().isEmpty) {
      return;
    }

    _endingCall = true;

    try {
      if (_shouldEndConnectedCall(
        _status,
      )) {
        await _callScreenProvider.endCall(
          status: 'COMPLETED',
        );
      } else {
        await _callScreenProvider.cancelCall(
          callId: callId,
        );
      }
    } catch (error, stackTrace) {
      _reportError(
        'End call',
        error,
        stackTrace,
      );

      rethrow;
    } finally {
      _endingCall = false;
    }
  }

  // =============================================================
  // VIDEO ACTIONS
  // =============================================================

  Future<void> _switchCamera() async {
    if (_disposed ||
        !widget.isVideoCall) {
      return;
    }

    await _videoProvider.switchCamera();
  }

  Future<void> _toggleVideo() async {
    if (_disposed ||
        !widget.isVideoCall) {
      return;
    }

    await _videoProvider.toggleVideo();
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    if (!_activeScreenOpened) {
      return _buildOutgoingStage();
    }

    if (widget.isVideoCall) {
      return _buildVideoCall();
    }

    return _buildVoiceCall();
  }

  // =============================================================
  // OUTGOING STAGE
  // =============================================================

  Widget _buildOutgoingStage() {
    return OutgoingCallScreen(
      callerName:
      _displayName,
      callerImage:
      _displayImage,
      isVideoCall:
      widget.isVideoCall,
      statusStream:
      _callService.callStatusStream,
      durationStream:
      _callService.callDurationStream,
      initialStatus:
      _status,
      onEndCall:
      _handleEndCall,
    );
  }

  // =============================================================
  // VOICE ACTIVE SCREEN
  // =============================================================

  Widget _buildVoiceCall() {
    return VoiceCallScreen(
      callerName:
      _displayName,
      callerImage:
      _displayImage,
      statusStream:
      _callService.callStatusStream,
      durationStream:
      _callService.callDurationStream,
      networkQualityStream:
      _networkQualityController.stream,
      initialStatus:
      _status,
      initialDurationSeconds:
      _durationSeconds,
      initialNetworkQuality:
      _networkProvider.quality,
      onEndCall:
      _handleEndCall,
    );
  }

  // =============================================================
  // VIDEO ACTIVE SCREEN
  // =============================================================

  Widget _buildVideoCall() {
    final bool localVideoEnabled =
        _videoProvider.videoEnabled &&
            _callScreenProvider.hasLocalVideo;

    final bool remoteVideoEnabled =
        _callScreenProvider.hasRemoteVideo;

    return VideoCallScreen(
      callerName:
      _displayName,
      callerImage:
      _displayImage,

      // Non-owning references.
      // WebRTCService remains MediaStream owner.
      localStream:
      _callScreenProvider.localStream,
      remoteStream:
      _callScreenProvider.remoteStream,

      statusStream:
      _callService.callStatusStream,
      durationStream:
      _callService.callDurationStream,
      networkQualityStream:
      _networkQualityController.stream,

      initialStatus:
      _status,
      initialDurationSeconds:
      _durationSeconds,
      initialNetworkQuality:
      _networkProvider.quality,

      isLocalVideoEnabled:
      localVideoEnabled,
      isRemoteVideoEnabled:
      remoteVideoEnabled,

      onEndCall:
      _handleEndCall,
      onSwitchCamera:
      _switchCamera,
      onToggleVideo:
      _toggleVideo,
    );
  }

  // =============================================================
  // ERROR REPORTING
  // =============================================================

  void _reportError(
      String source,
      Object error, [
        StackTrace? stackTrace,
      ]) {
    debugPrint(
      'JR CALL [CallSessionScreen/$source] '
          'error: $error',
    );

    if (stackTrace != null) {
      debugPrintStack(
        label:
        'JR CALL [CallSessionScreen/$source]',
        stackTrace:
        stackTrace,
      );
    }
  }
}

// ===============================================================
// END OF FILE
//
// PRODUCTION INTEGRATION:
//
// ✓ Shared CallService singleton.
// ✓ No duplicate CallService.startCall().
// ✓ Real CallService status/duration.
// ✓ Real WebRTC local/remote media.
// ✓ Real NetworkProvider quality.
// ✓ Real VideoProvider controls.
//
// ✓ Broadcast-status late-binding protected.
// ✓ Actual WebRTC PeerConnection can recover missed CONNECTED event.
// ✓ CONNECTED is never invented.
//
// ✓ Incoming caller identity may resolve from canonical Firebase UID.
// ✓ Profile read failure never destroys an active call.
//
// ✓ Existing OutgoingCallScreen unchanged.
// ✓ Existing VoiceCallScreen unchanged.
// ✓ Existing VideoCallScreen unchanged.
//
// ✓ No direct Firestore call-state write.
// ✓ No direct signaling.
// ✓ No ICE ownership.
// ✓ No recovery ownership.
// ✓ No PeerConnection creation.
// ✓ No MediaStream creation/disposal.
// ===============================================================