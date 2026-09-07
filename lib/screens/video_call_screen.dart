import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/network_model.dart';
import '../widgets/call_bottom_bar.dart';
import '../widgets/call_timer_widget.dart';
import '../widgets/caller_avatar.dart';
import '../widgets/network_quality_widget.dart';

/// ===============================================================
/// JR CALL
/// File: video_call_screen.dart
/// Location: lib/screens/video_call_screen.dart
///
/// Production video-call presentation screen.
///
/// Ownership:
///
/// VideoCallScreen:
/// - Video-call presentation.
/// - Local/remote renderer presentation.
/// - Main/preview presentation swap.
/// - User camera-action forwarding.
/// - User end-call forwarding.
/// - Back-navigation protection.
///
/// CallService / Provider:
/// - Complete call lifecycle.
/// - Terminal status.
/// - Connected duration.
/// - Recovery orchestration.
///
/// WebRTCService / Managers:
/// - MediaStream ownership.
/// - PeerConnection ownership.
/// - Camera/media transport ownership.
/// - SDP/ICE/recovery ownership.
///
/// This screen does NOT:
/// - Create PeerConnection.
/// - Acquire MediaStream.
/// - Stop/dispose MediaStream.
/// - Persist SDP.
/// - Persist ICE.
/// - Write Firestore call state.
/// - Own recovery.
/// - Own a call-duration timer.
/// - Poll network state.
/// - Invent CONNECTED state.
/// ===============================================================

class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({
    super.key,
    required this.callerName,
    this.callerImage,
    this.localStream,
    this.remoteStream,
    this.statusStream,
    this.durationStream,
    this.networkQualityStream,
    this.initialStatus = 'CONNECTING',
    this.initialDurationSeconds = 0,
    this.initialNetworkQuality = NetworkQuality.good,
    this.isLocalVideoEnabled = true,
    this.isRemoteVideoEnabled = true,
    this.mirrorLocalVideo = true,
    this.onEndCall,
    this.onSwitchCamera,
    this.onToggleVideo,
  });

  final String callerName;
  final String? callerImage;

  final MediaStream? localStream;
  final MediaStream? remoteStream;

  final Stream<String>? statusStream;
  final Stream<int>? durationStream;
  final Stream<NetworkQuality>? networkQualityStream;

  final String initialStatus;
  final int initialDurationSeconds;
  final NetworkQuality initialNetworkQuality;

  final bool isLocalVideoEnabled;
  final bool isRemoteVideoEnabled;
  final bool mirrorLocalVideo;

  final FutureOr<void> Function()? onEndCall;
  final FutureOr<void> Function()? onSwitchCamera;
  final FutureOr<void> Function()? onToggleVideo;

  @override
  State<VideoCallScreen> createState() =>
      _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  // =============================================================
  // Design
  // =============================================================

  static const Color _background = Color(0xFFF5F8FE);
  static const Color _surface = Color(0xFFFFFFFF);

  static const Color _primaryBlue = Color(0xFF087AF5);
  static const Color _cyan = Color(0xFF04BDF5);
  static const Color _callGreen = Color(0xFF00D99B);

  static const Color _textPrimary = Color(0xFF101828);
  static const Color _textSecondary = Color(0xFF58677F);
  static const Color _border = Color(0xFFDCE7F5);

  static const Color _warning = Color(0xFFFFB020);
  static const Color _danger = Color(0xFFFF2449);

  // =============================================================
  // Limits
  // =============================================================

  static const int _maximumDurationSeconds = 86400000;

  // =============================================================
  // State
  // =============================================================

  bool _isEndingCall = false;
  bool _endActionCompleted = false;

  bool _isSwitchingCamera = false;
  bool _isTogglingVideo = false;

  bool _backDialogVisible = false;

  /// false:
  /// remote video = main
  /// local video = preview
  ///
  /// true:
  /// local video = main
  /// remote video = preview
  ///
  /// Presentation only.
  bool _showLocalVideoAsMain = false;

  // =============================================================
  // Safe Data
  // =============================================================

  String get _displayName {
    final String name = widget.callerName.trim();

    return name.isEmpty ? 'JR CALL User' : name;
  }

  String? get _safeCallerImage {
    final String? image = widget.callerImage?.trim();

    if (image == null || image.isEmpty) {
      return null;
    }

    return image;
  }

  String get _safeInitialStatus {
    final String normalized =
    widget.initialStatus.trim().toUpperCase();

    return normalized.isEmpty
        ? 'CONNECTING'
        : normalized;
  }

  int get _safeInitialDurationSeconds {
    return _boundedDurationSeconds(
      widget.initialDurationSeconds,
    );
  }

  int _boundedDurationSeconds(
      int value,
      ) {
    return value
        .clamp(
      0,
      _maximumDurationSeconds,
    )
        .toInt();
  }

  // =============================================================
  // Stream Availability
  // =============================================================

  bool _streamHasVideoTrack(
      MediaStream? stream,
      ) {
    if (stream == null) {
      return false;
    }

    try {
      return stream.getVideoTracks().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool get _hasUsableLocalVideo {
    return widget.isLocalVideoEnabled &&
        _streamHasVideoTrack(
          widget.localStream,
        );
  }

  bool get _hasUsableRemoteVideo {
    return widget.isRemoteVideoEnabled &&
        _streamHasVideoTrack(
          widget.remoteStream,
        );
  }

  bool get _canSwapVideoPresentation {
    return _hasUsableLocalVideo &&
        _hasUsableRemoteVideo;
  }

  bool _localVideoIsMain() {
    return _showLocalVideoAsMain &&
        _hasUsableLocalVideo;
  }

  // =============================================================
  // End Call
  // =============================================================

  Future<void> _handleEndCall() async {
    if (!mounted ||
        _isEndingCall ||
        _endActionCompleted) {
      return;
    }

    final FutureOr<void> Function()? callback =
        widget.onEndCall;

    if (callback == null) {
      _showMessage(
        'Call control is unavailable. Please try again.',
      );
      return;
    }

    setState(() {
      _isEndingCall = true;
    });

    try {
      await Future<void>.sync(
        callback,
      );
    } catch (error, stackTrace) {
      _reportError(
        'End call',
        error,
        stackTrace,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isEndingCall = false;
      });

      _showMessage(
        'The video call could not be ended. Please try again.',
      );

      return;
    }

    if (!mounted) {
      return;
    }

    _endActionCompleted = true;

    final NavigatorState navigator =
    Navigator.of(context);

    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    setState(() {
      _isEndingCall = false;
    });
  }

  // =============================================================
  // Back Navigation Protection
  // =============================================================

  Future<void> _handleBackAttempt(
      String status,
      ) async {
    if (!mounted ||
        _isEndingCall ||
        _backDialogVisible) {
      return;
    }

    if (_endActionCompleted ||
        _isTerminalStatus(status)) {
      final NavigatorState navigator =
      Navigator.of(context);

      if (navigator.canPop()) {
        navigator.pop();
      }

      return;
    }

    _backDialogVisible = true;

    try {
      final bool shouldEnd =
      await _confirmEndCall();

      if (!mounted || !shouldEnd) {
        return;
      }

      await _handleEndCall();
    } finally {
      _backDialogVisible = false;
    }
  }

  Future<bool> _confirmEndCall() async {
    if (!mounted) {
      return false;
    }

    final bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (
          BuildContext dialogContext,
          ) {
        return AlertDialog(
          title: const Text(
            'End video call?',
            style: TextStyle(
              fontWeight: FontWeight.w800,
            ),
          ),
          content: const Text(
            'Leaving this screen will end the current video call.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(false);
              },
              child: const Text(
                'Stay',
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(true);
              },
              icon: const Icon(
                Icons.call_end_rounded,
              ),
              label: const Text(
                'End Call',
              ),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  // =============================================================
  // Camera Actions
  // =============================================================

  Future<void> _handleSwitchCamera() async {
    if (!mounted ||
        _isSwitchingCamera ||
        _isEndingCall ||
        _endActionCompleted) {
      return;
    }

    final FutureOr<void> Function()? callback =
        widget.onSwitchCamera;

    if (callback == null) {
      return;
    }

    setState(() {
      _isSwitchingCamera = true;
    });

    try {
      await Future<void>.sync(
        callback,
      );
    } catch (error, stackTrace) {
      _reportError(
        'Switch camera',
        error,
        stackTrace,
      );

      if (mounted) {
        _showMessage(
          'Unable to switch camera.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSwitchingCamera = false;
        });
      }
    }
  }

  Future<void> _handleToggleVideo() async {
    if (!mounted ||
        _isTogglingVideo ||
        _isEndingCall ||
        _endActionCompleted) {
      return;
    }

    final FutureOr<void> Function()? callback =
        widget.onToggleVideo;

    if (callback == null) {
      return;
    }

    setState(() {
      _isTogglingVideo = true;
    });

    try {
      await Future<void>.sync(
        callback,
      );
    } catch (error, stackTrace) {
      _reportError(
        'Toggle video',
        error,
        stackTrace,
      );

      if (mounted) {
        _showMessage(
          'Unable to change camera state.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingVideo = false;
        });
      }
    }
  }

  // =============================================================
  // Video Presentation Swap
  // =============================================================

  void _swapVideoPresentation() {
    if (!mounted ||
        !_canSwapVideoPresentation ||
        _isEndingCall ||
        _endActionCompleted) {
      return;
    }

    setState(() {
      _showLocalVideoAsMain =
      !_showLocalVideoAsMain;
    });
  }

  // =============================================================
  // Status
  // =============================================================

  String _normalizeStatus(
      String? value,
      ) {
    final String normalized =
        value?.trim().toUpperCase() ?? '';

    return normalized.isEmpty
        ? _safeInitialStatus
        : normalized;
  }

  String _statusText(
      String status,
      ) {
    switch (_normalizeStatus(status)) {
      case 'IDLE':
        return 'Video call';

      case 'PREPARING':
        return 'Preparing video call…';

      case 'CALLING':
        return 'Calling…';

      case 'RINGING':
        return 'Ringing…';

      case 'CONNECTING':
        return 'Connecting…';

      case 'CONNECTED':
        return 'Connected';

      case 'RECONNECTING':
        return 'Reconnecting…';

      case 'RECONNECTED':
        return 'Connected';

      case 'NETWORK_LOST':
        return 'Waiting for network…';

      case 'USER_BUSY':
      case 'BUSY':
        return 'User is busy';

      case 'REJECTED':
        return 'Call rejected';

      case 'DECLINED':
        return 'Call declined';

      case 'CANCELLED':
        return 'Call cancelled';

      case 'TIMEOUT':
        return 'No answer';

      case 'FAILED':
        return 'Call failed';

      case 'ENDED':
      case 'COMPLETED':
        return 'Call ended';

      default:
        return 'Video call';
    }
  }

  bool _showDuration(
      String status,
      ) {
    switch (_normalizeStatus(status)) {
      case 'CONNECTED':
      case 'RECONNECTED':
      case 'RECONNECTING':
      case 'NETWORK_LOST':
        return true;

      default:
        return false;
    }
  }

  bool _isConnectedStatus(
      String status,
      ) {
    switch (_normalizeStatus(status)) {
      case 'CONNECTED':
      case 'RECONNECTED':
        return true;

      default:
        return false;
    }
  }

  bool _isConnectionWarning(
      String status,
      ) {
    switch (_normalizeStatus(status)) {
      case 'RECONNECTING':
      case 'NETWORK_LOST':
        return true;

      default:
        return false;
    }
  }

  bool _isTerminalStatus(
      String status,
      ) {
    switch (_normalizeStatus(status)) {
      case 'USER_BUSY':
      case 'BUSY':
      case 'REJECTED':
      case 'DECLINED':
      case 'CANCELLED':
      case 'TIMEOUT':
      case 'FAILED':
      case 'ENDED':
      case 'COMPLETED':
        return true;

      default:
        return false;
    }
  }

  Color _statusAccent(
      String status,
      ) {
    if (_isTerminalStatus(status)) {
      return _danger;
    }

    if (_isConnectionWarning(status)) {
      return _warning;
    }

    if (_isConnectedStatus(status)) {
      return _callGreen;
    }

    return _primaryBlue;
  }

  bool _shouldDisplayRemoteVideo(
      String status,
      ) {
    if (!_hasUsableRemoteVideo) {
      return false;
    }

    switch (_normalizeStatus(status)) {
      case 'CONNECTED':
      case 'RECONNECTED':
      case 'RECONNECTING':
      case 'NETWORK_LOST':
        return true;

      default:
        return false;
    }
  }

  // =============================================================
  // Build
  // =============================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    return StreamBuilder<String>(
      stream: widget.statusStream,
      initialData: _safeInitialStatus,
      builder: (
          _,
          AsyncSnapshot<String> statusSnapshot,
          ) {
        final String status = _normalizeStatus(
          statusSnapshot.data,
        );

        return StreamBuilder<int>(
          stream: widget.durationStream,
          initialData: _safeInitialDurationSeconds,
          builder: (
              _,
              AsyncSnapshot<int> durationSnapshot,
              ) {
            final int durationSeconds =
            _boundedDurationSeconds(
              durationSnapshot.data ??
                  _safeInitialDurationSeconds,
            );

            return PopScope<Object?>(
              canPop: false,
              onPopInvokedWithResult: (
                  bool didPop,
                  _,
                  ) {
                if (!didPop) {
                  unawaited(
                    _handleBackAttempt(
                      status,
                    ),
                  );
                }
              },
              child: Scaffold(
                backgroundColor: _background,
                body: SafeArea(
                  child: _buildVideoCall(
                    context,
                    status,
                    durationSeconds,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildVideoCall(
      BuildContext context,
      String status,
      int durationSeconds,
      ) {
    final Size screenSize =
    MediaQuery.sizeOf(context);

    final bool compactHeight =
        screenSize.height < 680;

    final bool narrow =
        screenSize.width < 360;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _buildMainVideoSurface(
          status,
        ),

        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x18000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0x40000000),
                ],
                stops: <double>[
                  0,
                  0.22,
                  0.68,
                  1,
                ],
              ),
            ),
          ),
        ),

        Positioned(
          top: compactHeight ? 10 : 14,
          left: narrow ? 10 : 14,
          child: _buildCompactStatus(
            status,
          ),
        ),

        if (_showDuration(status))
          Positioned(
            top: compactHeight ? 10 : 14,
            right: narrow ? 10 : 14,
            child: _buildDurationPill(
              durationSeconds,
            ),
          ),

        if (_shouldShowParticipantFallback(
          status,
        ))
          Center(
            child: _buildParticipantFallback(
              status,
              durationSeconds: durationSeconds,
              compact: compactHeight,
            ),
          ),

        if (_shouldShowPreview(status))
          Positioned(
            top: compactHeight ? 62 : 72,
            right: narrow ? 10 : 14,
            child: _buildPreview(
              status: status,
              compact: compactHeight,
            ),
          ),

        Positioned(
          left: narrow ? 10 : 14,
          right: narrow ? 10 : 14,
          bottom: narrow ? 10 : 14,
          child: _buildBottomPanel(
            terminal: _isTerminalStatus(
              status,
            ),
          ),
        ),
      ],
    );
  }

  // =============================================================
  // Main Video
  // =============================================================

  Widget _buildMainVideoSurface(
      String status,
      ) {
    final bool localCanBeMain =
    _localVideoIsMain();

    final bool remoteCanBeMain =
        !localCanBeMain &&
            _shouldDisplayRemoteVideo(
              status,
            );

    if (localCanBeMain) {
      return _RtcVideoSurface(
        stream: widget.localStream,
        mirror: widget.mirrorLocalVideo,
        objectFit:
        RTCVideoViewObjectFit
            .RTCVideoViewObjectFitCover,
        backgroundColor: _background,
      );
    }

    if (remoteCanBeMain) {
      return _RtcVideoSurface(
        stream: widget.remoteStream,
        mirror: false,
        objectFit:
        RTCVideoViewObjectFit
            .RTCVideoViewObjectFitCover,
        backgroundColor: _background,
      );
    }

    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFF8FBFF),
            Color(0xFFF0F6FF),
            Color(0xFFEAF3FF),
          ],
        ),
      ),
    );
  }

  // =============================================================
  // Compact Status
  // =============================================================

  Widget _buildCompactStatus(
      String status,
      ) {
    final Color accent =
    _statusAccent(status);

    return Semantics(
      label:
      'Call status: ${_statusText(status)}',
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 190,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(
            alpha: 0.36,
          ),
          borderRadius: BorderRadius.circular(
            999,
          ),
          border: Border.all(
            color: Colors.white.withValues(
              alpha: 0.20,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: accent.withValues(
                      alpha: 0.35,
                    ),
                    blurRadius: 7,
                  ),
                ],
              ),
            ),
            const SizedBox(
              width: 7,
            ),
            Flexible(
              child: Text(
                _statusText(status),
                maxLines: 1,
                overflow:
                TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight:
                  FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =============================================================
  // Duration Pill
  // =============================================================

  Widget _buildDurationPill(
      int durationSeconds,
      ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(
          alpha: 0.36,
        ),
        borderRadius: BorderRadius.circular(
          999,
        ),
        border: Border.all(
          color: Colors.white.withValues(
            alpha: 0.20,
          ),
        ),
      ),
      child: _buildDuration(
        durationSeconds,
      ),
    );
  }

  // =============================================================
  // Preview
  // =============================================================

  bool _shouldShowPreview(
      String status,
      ) {
    if (_localVideoIsMain()) {
      return _shouldDisplayRemoteVideo(
        status,
      );
    }

    return _hasUsableLocalVideo;
  }

  Widget _buildPreview({
    required String status,
    required bool compact,
  }) {
    final double width =
    compact ? 96 : 118;

    final double height =
    compact ? 132 : 164;

    final bool previewShowsRemote =
    _localVideoIsMain();

    final MediaStream? previewStream =
    previewShowsRemote
        ? widget.remoteStream
        : widget.localStream;

    final bool previewVideoEnabled =
    previewShowsRemote
        ? _shouldDisplayRemoteVideo(
      status,
    )
        : _hasUsableLocalVideo;

    final bool mirror =
    previewShowsRemote
        ? false
        : widget.mirrorLocalVideo;

    final String semanticsLabel =
    previewShowsRemote
        ? 'Remote participant video preview'
        : 'Your video preview';

    return Semantics(
      label: semanticsLabel,
      button: _canSwapVideoPresentation,
      hint: _canSwapVideoPresentation
          ? 'Tap to swap main and preview video'
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap:
        _canSwapVideoPresentation &&
            !_endActionCompleted
            ? _swapVideoPresentation
            : null,
        onDoubleTap:
        !previewShowsRemote &&
            widget.onSwitchCamera != null &&
            !_endActionCompleted
            ? () {
          unawaited(
            _handleSwitchCamera(),
          );
        }
            : null,
        child: AnimatedOpacity(
          opacity:
          !previewShowsRemote &&
              _isSwitchingCamera
              ? 0.60
              : 1.0,
          duration: const Duration(
            milliseconds: 150,
          ),
          child: Container(
            width: width,
            height: height,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _surface,
              borderRadius:
              BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(
                  alpha: 0.88,
                ),
                width: 1.4,
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 22,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child:
            previewVideoEnabled &&
                previewStream != null
                ? _RtcVideoSurface(
              stream: previewStream,
              mirror: mirror,
              objectFit:
              RTCVideoViewObjectFit
                  .RTCVideoViewObjectFitCover,
              backgroundColor:
              _surface,
            )
                : _buildPreviewFallback(
              remotePreview:
              previewShowsRemote,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewFallback({
    required bool remotePreview,
  }) {
    return ColoredBox(
      color: const Color(
        0xFFF2F6FB,
      ),
      child: Center(
        child: Icon(
          remotePreview
              ? Icons.person_rounded
              : Icons.videocam_off_rounded,
          color: _textSecondary,
          size: 31,
        ),
      ),
    );
  }

  // =============================================================
  // Participant Fallback
  // =============================================================

  bool _shouldShowParticipantFallback(
      String status,
      ) {
    if (_localVideoIsMain()) {
      return false;
    }

    return !_shouldDisplayRemoteVideo(
      status,
    );
  }

  Widget _buildParticipantFallback(
      String status, {
        required int durationSeconds,
        required bool compact,
      }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 28,
      ),
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 420,
        ),
        padding: EdgeInsets.fromLTRB(
          24,
          compact ? 24 : 30,
          24,
          compact ? 22 : 28,
        ),
        decoration: BoxDecoration(
          color: _surface.withValues(
            alpha: 0.94,
          ),
          borderRadius: BorderRadius.circular(
            30,
          ),
          border: Border.all(
            color: _border,
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x1A087AF5),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
            BoxShadow(
              color: Color(0x1404BDF5),
              blurRadius: 36,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(
                7,
              ),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: <Color>[
                    _primaryBlue,
                    _cyan,
                    _callGreen,
                  ],
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(
                  4,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: CallerAvatar(
                  name: _displayName,
                  imageUrl: _safeCallerImage,
                  radius: compact ? 42 : 50,
                  isOnline: false,
                ),
              ),
            ),

            const SizedBox(
              height: 18,
            ),

            Text(
              _displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textPrimary,
                fontSize: compact ? 22 : 25,
                fontWeight:
                FontWeight.w800,
              ),
            ),

            const SizedBox(
              height: 7,
            ),

            Text(
              _statusText(status),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _statusAccent(
                  status,
                ),
                fontSize: 14,
                fontWeight:
                FontWeight.w700,
              ),
            ),

            if (_showDuration(status))
              ...<Widget>[
                const SizedBox(
                  height: 13,
                ),
                _buildDuration(
                  durationSeconds,
                ),
              ],
          ],
        ),
      ),
    );
  }

  // =============================================================
  // Bottom Panel
  // =============================================================

  Widget _buildBottomPanel({
    required bool terminal,
  }) {
    final bool actionsDisabled =
        _isEndingCall ||
            _endActionCompleted ||
            terminal;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        14,
        12,
        14,
        14,
      ),
      decoration: BoxDecoration(
        color: _surface.withValues(
          alpha: 0.94,
        ),
        borderRadius: BorderRadius.circular(
          26,
        ),
        border: Border.all(
          color: _border,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1A087AF5),
            blurRadius: 26,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Align(
                  alignment:
                  Alignment.centerLeft,
                  child:
                  _buildNetworkQuality(),
                ),
              ),

              if (widget.onToggleVideo !=
                  null)
                _VideoActionButton(
                  tooltip:
                  widget.isLocalVideoEnabled
                      ? 'Turn camera off'
                      : 'Turn camera on',
                  icon:
                  widget.isLocalVideoEnabled
                      ? Icons.videocam_rounded
                      : Icons
                      .videocam_off_rounded,
                  busy: _isTogglingVideo,
                  enabled: !actionsDisabled,
                  accentColor:
                  _primaryBlue,
                  onPressed: () {
                    unawaited(
                      _handleToggleVideo(),
                    );
                  },
                ),

              if (widget.onToggleVideo !=
                  null &&
                  widget.onSwitchCamera !=
                      null)
                const SizedBox(
                  width: 10,
                ),

              if (widget.onSwitchCamera !=
                  null)
                _VideoActionButton(
                  tooltip: 'Switch camera',
                  icon:
                  Icons.cameraswitch_rounded,
                  busy:
                  _isSwitchingCamera,
                  enabled:
                  !actionsDisabled &&
                      _hasUsableLocalVideo,
                  accentColor: _cyan,
                  onPressed: () {
                    unawaited(
                      _handleSwitchCamera(),
                    );
                  },
                ),
            ],
          ),

          const SizedBox(
            height: 12,
          ),

          IgnorePointer(
            ignoring: actionsDisabled,
            child: AnimatedOpacity(
              opacity:
              actionsDisabled
                  ? 0.55
                  : 1,
              duration: const Duration(
                milliseconds: 150,
              ),
              child: CallBottomBar(
                key: ValueKey<bool>(
                  _isEndingCall,
                ),

                // Camera toggle/switch presentation is already
                // owned above by this screen and forwarded through
                // the parent callbacks. Do not duplicate a second
                // direct VideoManager control path here.
                showVideoControls: false,

                onEndCall: () {
                  unawaited(
                    _handleEndCall(),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =============================================================
  // Network Quality
  // =============================================================

  Widget _buildNetworkQuality() {
    return StreamBuilder<NetworkQuality>(
      stream: widget.networkQualityStream,
      initialData:
      widget.initialNetworkQuality,
      builder: (
          _,
          AsyncSnapshot<NetworkQuality> snapshot,
          ) {
        return NetworkQualityWidget(
          quality:
          snapshot.data ??
              widget.initialNetworkQuality,
        );
      },
    );
  }

  // =============================================================
  // Duration
  // =============================================================

  Widget _buildDuration(
      int durationSeconds,
      ) {
    return CallTimerWidget(
      duration: Duration(
        seconds:
        _boundedDurationSeconds(
          durationSeconds,
        ),
      ),
    );
  }

  // =============================================================
  // Message
  // =============================================================

  void _showMessage(
      String message,
      ) {
    if (!mounted ||
        message.trim().isEmpty) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
          ),
          behavior:
          SnackBarBehavior.floating,
        ),
      );
  }

  // =============================================================
  // Error Reporting
  // =============================================================

  void _reportError(
      String source,
      Object error,
      StackTrace stackTrace,
      ) {
    debugPrint(
      'JR CALL '
          '[VideoCallScreen/$source] '
          'error: $error',
    );

    debugPrintStack(
      label:
      'JR CALL '
          '[VideoCallScreen/$source]',
      stackTrace: stackTrace,
    );
  }
}

// ===============================================================
// Isolated RTC Video Surface
//
// Renderer ownership only.
// MediaStream ownership remains external.
// ===============================================================

class _RtcVideoSurface extends StatefulWidget {
  const _RtcVideoSurface({
    required this.stream,
    required this.mirror,
    required this.objectFit,
    required this.backgroundColor,
  });

  final MediaStream? stream;

  final bool mirror;

  final RTCVideoViewObjectFit objectFit;

  final Color backgroundColor;

  @override
  State<_RtcVideoSurface> createState() =>
      _RtcVideoSurfaceState();
}

class _RtcVideoSurfaceState
    extends State<_RtcVideoSurface> {
  final RTCVideoRenderer _renderer =
  RTCVideoRenderer();

  late final Future<void> _initializationFuture;

  bool _initialized = false;
  bool _initializationFailed = false;

  bool _disposed = false;
  bool _rendererDisposed = false;

  MediaStream? _pendingStream;

  // =============================================================
  // Lifecycle
  // =============================================================

  @override
  void initState() {
    super.initState();

    _pendingStream = widget.stream;

    _initializationFuture =
        _initializeRenderer();

    unawaited(
      _initializationFuture,
    );
  }

  @override
  void didUpdateWidget(
      covariant _RtcVideoSurface oldWidget,
      ) {
    super.didUpdateWidget(
      oldWidget,
    );

    if (!identical(
      oldWidget.stream,
      widget.stream,
    )) {
      _pendingStream = widget.stream;

      _attachPendingStream();
    }
  }

  Future<void> _initializeRenderer() async {
    try {
      await _renderer.initialize();

      if (_disposed) {
        return;
      }

      _initialized = true;

      _attachPendingStream();

      if (mounted) {
        setState(() {});
      }
    } catch (error, stackTrace) {
      if (_disposed) {
        return;
      }

      _initializationFailed = true;

      debugPrint(
        'JR CALL '
            '[VideoRenderer] '
            'initialization error: $error',
      );

      debugPrintStack(
        label:
        'JR CALL '
            '[VideoRenderer]',
        stackTrace: stackTrace,
      );

      if (mounted) {
        setState(() {});
      }
    }
  }

  void _attachPendingStream() {
    if (!_initialized ||
        _disposed ||
        _rendererDisposed) {
      return;
    }

    final MediaStream? targetStream =
        _pendingStream;

    if (identical(
      _renderer.srcObject,
      targetStream,
    )) {
      return;
    }

    try {
      _renderer.srcObject =
          targetStream;
    } catch (error, stackTrace) {
      if (_disposed) {
        return;
      }

      debugPrint(
        'JR CALL '
            '[VideoRenderer] '
            'stream attachment error: $error',
      );

      debugPrintStack(
        label:
        'JR CALL '
            '[VideoRenderer/attach]',
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _disposeRendererOnce() async {
    if (_rendererDisposed) {
      return;
    }

    _rendererDisposed = true;

    try {
      await _initializationFuture;
    } catch (_) {
      // Initialization errors are already handled by
      // _initializeRenderer().
    }

    try {
      if (_initialized &&
          _renderer.srcObject != null) {
        _renderer.srcObject = null;
      }
    } catch (error, stackTrace) {
      debugPrint(
        'JR CALL '
            '[VideoRenderer] '
            'stream detach error: $error',
      );

      debugPrintStack(
        label:
        'JR CALL '
            '[VideoRenderer/detach]',
        stackTrace: stackTrace,
      );
    }

    try {
      await _renderer.dispose();
    } catch (error, stackTrace) {
      debugPrint(
        'JR CALL '
            '[VideoRenderer] '
            'disposal error: $error',
      );

      debugPrintStack(
        label:
        'JR CALL '
            '[VideoRenderer/dispose]',
        stackTrace: stackTrace,
      );
    }
  }

  // =============================================================
  // Build
  // =============================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    if (_initializationFailed) {
      return ColoredBox(
        color: widget.backgroundColor,
        child: const Center(
          child: Icon(
            Icons.videocam_off_rounded,
            color: Color(0xFF98A2B3),
            size: 28,
          ),
        ),
      );
    }

    if (!_initialized ||
        _rendererDisposed) {
      return ColoredBox(
        color: widget.backgroundColor,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child:
            CircularProgressIndicator(
              strokeWidth: 2,
              color:
              Color(0xFF087AF5),
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: widget.backgroundColor,
      child: RTCVideoView(
        _renderer,
        mirror: widget.mirror,
        objectFit: widget.objectFit,
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;

    _pendingStream = null;

    unawaited(
      _disposeRendererOnce(),
    );

    super.dispose();
  }
}

// ===============================================================
// Video Action Button
// ===============================================================

class _VideoActionButton extends StatelessWidget {
  const _VideoActionButton({
    required this.tooltip,
    required this.icon,
    required this.busy,
    required this.enabled,
    required this.accentColor,
    required this.onPressed,
  });

  final String tooltip;

  final IconData icon;

  final bool busy;

  final bool enabled;

  final Color accentColor;

  final VoidCallback onPressed;

  @override
  Widget build(
      BuildContext context,
      ) {
    final bool actionEnabled =
        enabled && !busy;

    return Semantics(
      button: true,
      enabled: actionEnabled,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: AnimatedOpacity(
          opacity:
          actionEnabled || busy
              ? 1
              : 0.45,
          duration: const Duration(
            milliseconds: 150,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder:
              const CircleBorder(),
              onTap: actionEnabled
                  ? onPressed
                  : null,
              child: Container(
                width: 48,
                height: 48,
                alignment:
                Alignment.center,
                decoration: BoxDecoration(
                  color:
                  accentColor.withValues(
                    alpha: 0.10,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                    accentColor.withValues(
                      alpha: 0.22,
                    ),
                  ),
                ),
                child: busy
                    ? SizedBox(
                  width: 19,
                  height: 19,
                  child:
                  CircularProgressIndicator(
                    strokeWidth: 2,
                    color:
                    accentColor,
                  ),
                )
                    : Icon(
                  icon,
                  color: accentColor,
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}