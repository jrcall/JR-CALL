// ===============================================================
// JR CALL
// File: video_call_screen.dart
// Location: lib/screens/video_call_screen.dart
// Fixes: BUG 08, BUG 09
// Production-safe replacement
// Existing APIs preserved
// ===============================================================
//
// Responsibilities:
// - Render remote video.
// - Render local camera preview.
// - Support local/remote presentation swap.
// - Display participant information.
// - Display real call status.
// - Display real connected-call duration.
// - Display supplied network quality.
// - Forward UI actions to Provider / CallService.
//
// Architecture ownership:
// - Call lifecycle         -> CallService
// - Call state             -> CallProvider / CallScreenProvider
// - Call duration          -> CallService / Provider
// - Network monitoring     -> NetworkManager / Provider
// - AI optimization        -> AICallEngine
// - WebRTC connection      -> WebRTCService
// - ICE                    -> IceManager
// - Signaling              -> SignalingService
// - Recovery               -> RecoveryManager
// - Camera control         -> VideoManager / VideoProvider
//
// Production rules:
// - No duplicate call timer.
// - No duplicate network polling.
// - No direct signaling.
// - No direct ICE logic.
// - No direct recovery.
// - No direct call lifecycle ownership.
// - No fake CONNECTED state.
// - No fake video stream.
// - Renderer lifecycle remains presentation-local.
// - Existing constructor/callback API preserved.
// ===============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/network_model.dart';
import '../widgets/call_bottom_bar.dart';
import '../widgets/call_timer_widget.dart';
import '../widgets/caller_avatar.dart';
import '../widgets/network_quality_widget.dart';

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
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  // =============================================================
  // DESIGN
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

  static const int _maximumDurationSeconds = 86400000;

  // =============================================================
  // STATE
  // =============================================================

  bool _isEndingCall = false;
  bool _isSwitchingCamera = false;
  bool _isTogglingVideo = false;

  /// False:
  ///   remote video = large/main
  ///   local video  = small preview
  ///
  /// True:
  ///   local video  = large/main
  ///   remote video = small preview
  ///
  /// Presentation-only. It does NOT alter WebRTC ownership.
  bool _showLocalVideoAsMain = false;

  // =============================================================
  // SAFE DATA
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

  // =============================================================
  // STREAM AVAILABILITY
  // =============================================================

  bool get _hasUsableLocalVideo {
    return widget.isLocalVideoEnabled && widget.localStream != null;
  }

  bool get _hasUsableRemoteVideo {
    return widget.isRemoteVideoEnabled && widget.remoteStream != null;
  }

  bool get _canSwapVideoPresentation {
    return _hasUsableLocalVideo && _hasUsableRemoteVideo;
  }

  // =============================================================
  // END CALL
  // =============================================================

  Future<void> _handleEndCall() async {
    if (_isEndingCall || !mounted) {
      return;
    }

    setState(() {
      _isEndingCall = true;
    });

    bool callbackSucceeded = true;

    try {
      final FutureOr<void> Function()? callback = widget.onEndCall;

      if (callback != null) {
        await Future<void>.sync(callback);
      }
    } catch (error, stackTrace) {
      callbackSucceeded = false;

      _reportError('End call', error, stackTrace);
    }

    if (!mounted) {
      return;
    }

    if (!callbackSucceeded) {
      setState(() {
        _isEndingCall = false;
      });

      return;
    }

    final NavigatorState navigator = Navigator.of(context);

    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    setState(() {
      _isEndingCall = false;
    });
  }

  // =============================================================
  // CAMERA ACTIONS
  // =============================================================

  Future<void> _handleSwitchCamera() async {
    if (_isSwitchingCamera || _isEndingCall || !mounted) {
      return;
    }

    final FutureOr<void> Function()? callback = widget.onSwitchCamera;

    if (callback == null) {
      return;
    }

    setState(() {
      _isSwitchingCamera = true;
    });

    try {
      await Future<void>.sync(callback);
    } catch (error, stackTrace) {
      _reportError('Switch camera', error, stackTrace);
    } finally {
      if (mounted) {
        setState(() {
          _isSwitchingCamera = false;
        });
      }
    }
  }

  Future<void> _handleToggleVideo() async {
    if (_isTogglingVideo || _isEndingCall || !mounted) {
      return;
    }

    final FutureOr<void> Function()? callback = widget.onToggleVideo;

    if (callback == null) {
      return;
    }

    setState(() {
      _isTogglingVideo = true;
    });

    try {
      await Future<void>.sync(callback);
    } catch (error, stackTrace) {
      _reportError('Toggle video', error, stackTrace);
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingVideo = false;
        });
      }
    }
  }

  // =============================================================
  // VIDEO PRESENTATION SWAP
  // =============================================================

  void _swapVideoPresentation() {
    if (!_canSwapVideoPresentation || _isEndingCall || !mounted) {
      return;
    }

    setState(() {
      _showLocalVideoAsMain = !_showLocalVideoAsMain;
    });
  }

  // =============================================================
  // STATUS
  // =============================================================

  String _normalizeStatus(String value) {
    final String normalized = value.trim().toUpperCase();

    return normalized.isEmpty ? 'CONNECTING' : normalized;
  }

  String _statusText(String status) {
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

  bool _showDuration(String status) {
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

  bool _isConnectedStatus(String status) {
    switch (_normalizeStatus(status)) {
      case 'CONNECTED':
      case 'RECONNECTED':
        return true;

      default:
        return false;
    }
  }

  bool _isConnectionWarning(String status) {
    switch (_normalizeStatus(status)) {
      case 'RECONNECTING':
      case 'NETWORK_LOST':
      case 'FAILED':
      case 'TIMEOUT':
        return true;

      default:
        return false;
    }
  }

  bool _isTerminalStatus(String status) {
    switch (_normalizeStatus(status)) {
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

  Color _statusAccent(String status) {
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

  bool _shouldDisplayRemoteVideo(String status) {
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
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isEndingCall,
      child: Scaffold(
        backgroundColor: _background,
        body: SafeArea(
          child: StreamBuilder<String>(
            stream: widget.statusStream,
            initialData: widget.initialStatus,
            builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
              final String status = _normalizeStatus(
                snapshot.data ?? widget.initialStatus,
              );

              return _buildVideoCall(context, status);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildVideoCall(BuildContext context, String status) {
    final Size screenSize = MediaQuery.sizeOf(context);

    final bool compactHeight = screenSize.height < 680;
    final bool narrow = screenSize.width < 360;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _buildMainVideoSurface(status),

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
                stops: <double>[0, 0.22, 0.68, 1],
              ),
            ),
          ),
        ),

        // BUG 09:
        // No JR CALL / Premium Calling Experience branding card.
        //
        // Only real call state remains visible in a compact location.
        Positioned(
          top: compactHeight ? 10 : 14,
          left: narrow ? 10 : 14,
          child: _buildCompactStatus(status),
        ),

        if (_showDuration(status))
          Positioned(
            top: compactHeight ? 10 : 14,
            right: narrow ? 10 : 14,
            child: _buildDurationPill(),
          ),

        if (_shouldShowParticipantFallback(status))
          Center(
            child: _buildParticipantFallback(status, compact: compactHeight),
          ),

        if (_shouldShowPreview(status))
          Positioned(
            top: compactHeight ? 62 : 72,
            right: narrow ? 10 : 14,
            child: _buildPreview(status: status, compact: compactHeight),
          ),

        Positioned(
          left: narrow ? 10 : 14,
          right: narrow ? 10 : 14,
          bottom: narrow ? 10 : 14,
          child: _buildBottomPanel(),
        ),
      ],
    );
  }

  // =============================================================
  // MAIN VIDEO
  // =============================================================

  Widget _buildMainVideoSurface(String status) {
    final bool remoteCanBeMain =
        !_showLocalVideoAsMain && _shouldDisplayRemoteVideo(status);

    final bool localCanBeMain = _showLocalVideoAsMain && _hasUsableLocalVideo;

    if (localCanBeMain) {
      return _RtcVideoSurface(
        stream: widget.localStream,
        mirror: widget.mirrorLocalVideo,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        backgroundColor: _background,
      );
    }

    if (remoteCanBeMain) {
      return _RtcVideoSurface(
        stream: widget.remoteStream,
        mirror: false,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
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
  // COMPACT STATUS
  // =============================================================

  Widget _buildCompactStatus(String status) {
    final Color accent = _statusAccent(status);

    return Semantics(
      label: 'Call status: ${_statusText(status)}',
      child: Container(
        constraints: const BoxConstraints(maxWidth: 190),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.36),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
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
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 7,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 7),

            Flexible(
              child: Text(
                _statusText(status),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =============================================================
  // DURATION PILL
  // =============================================================

  Widget _buildDurationPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: _buildDuration(),
    );
  }

  // =============================================================
  // PREVIEW
  // =============================================================

  bool _shouldShowPreview(String status) {
    if (_showLocalVideoAsMain) {
      return _shouldDisplayRemoteVideo(status);
    }

    return _hasUsableLocalVideo;
  }

  Widget _buildPreview({required String status, required bool compact}) {
    final double width = compact ? 96 : 118;
    final double height = compact ? 132 : 164;

    final bool previewShowsRemote = _showLocalVideoAsMain;

    final MediaStream? previewStream = previewShowsRemote
        ? widget.remoteStream
        : widget.localStream;

    final bool previewVideoEnabled = previewShowsRemote
        ? _shouldDisplayRemoteVideo(status)
        : _hasUsableLocalVideo;

    final bool mirror = previewShowsRemote ? false : widget.mirrorLocalVideo;

    final String semanticsLabel = previewShowsRemote
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

        /// WhatsApp-style presentation swap.
        onTap: _canSwapVideoPresentation ? _swapVideoPresentation : null,

        /// Preserve existing camera-switch gesture.
        onDoubleTap: !previewShowsRemote && widget.onSwitchCamera != null
            ? () {
                unawaited(_handleSwitchCamera());
              }
            : null,

        child: AnimatedOpacity(
          opacity: (!previewShowsRemote && _isSwitchingCamera) ? 0.60 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: width,
            height: height,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.88),
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
            child: previewVideoEnabled && previewStream != null
                ? _RtcVideoSurface(
                    stream: previewStream,
                    mirror: mirror,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    backgroundColor: _surface,
                  )
                : _buildPreviewFallback(remotePreview: previewShowsRemote),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewFallback({required bool remotePreview}) {
    return ColoredBox(
      color: const Color(0xFFF2F6FB),
      child: Center(
        child: Icon(
          remotePreview ? Icons.person_rounded : Icons.videocam_off_rounded,
          color: _textSecondary,
          size: 31,
        ),
      ),
    );
  }

  // =============================================================
  // PARTICIPANT FALLBACK
  // =============================================================

  bool _shouldShowParticipantFallback(String status) {
    if (_showLocalVideoAsMain && _hasUsableLocalVideo) {
      return false;
    }

    return !_shouldDisplayRemoteVideo(status);
  }

  Widget _buildParticipantFallback(String status, {required bool compact}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: EdgeInsets.fromLTRB(
          24,
          compact ? 24 : 30,
          24,
          compact ? 22 : 28,
        ),
        decoration: BoxDecoration(
          color: _surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: _border),
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
              padding: const EdgeInsets.all(7),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: <Color>[_primaryBlue, _cyan, _callGreen],
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: CallerAvatar(
                  name: _displayName,
                  imageUrl: _safeCallerImage,

                  /// Do not hard-code online state.
                  /// Connected call state is the only reliable information
                  /// available to this UI.
                  isOnline: _isConnectedStatus(status),

                  radius: compact ? 42 : 50,
                ),
              ),
            ),

            const SizedBox(height: 18),

            Text(
              _displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textPrimary,
                fontSize: compact ? 22 : 25,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 7),

            Text(
              _statusText(status),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _statusAccent(status),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),

            if (_showDuration(status)) ...<Widget>[
              const SizedBox(height: 13),
              _buildDuration(),
            ],
          ],
        ),
      ),
    );
  }

  // =============================================================
  // BOTTOM PANEL
  // =============================================================

  Widget _buildBottomPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _border),
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
                  alignment: Alignment.centerLeft,
                  child: _buildNetworkQuality(),
                ),
              ),

              if (widget.onToggleVideo != null)
                _VideoActionButton(
                  tooltip: widget.isLocalVideoEnabled
                      ? 'Turn camera off'
                      : 'Turn camera on',
                  icon: widget.isLocalVideoEnabled
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded,
                  busy: _isTogglingVideo,
                  enabled: !_isEndingCall,
                  accentColor: _primaryBlue,
                  onPressed: () {
                    unawaited(_handleToggleVideo());
                  },
                ),

              if (widget.onToggleVideo != null && widget.onSwitchCamera != null)
                const SizedBox(width: 10),

              if (widget.onSwitchCamera != null)
                _VideoActionButton(
                  tooltip: 'Switch camera',
                  icon: Icons.cameraswitch_rounded,
                  busy: _isSwitchingCamera,
                  enabled:
                      !_isEndingCall &&
                      widget.isLocalVideoEnabled &&
                      widget.localStream != null,
                  accentColor: _cyan,
                  onPressed: () {
                    unawaited(_handleSwitchCamera());
                  },
                ),
            ],
          ),

          const SizedBox(height: 12),

          IgnorePointer(
            ignoring: _isEndingCall,
            child: AnimatedOpacity(
              opacity: _isEndingCall ? 0.55 : 1,
              duration: const Duration(milliseconds: 150),
              child: CallBottomBar(onEndCall: _handleEndCall),
            ),
          ),
        ],
      ),
    );
  }

  // =============================================================
  // NETWORK QUALITY
  // =============================================================

  Widget _buildNetworkQuality() {
    return StreamBuilder<NetworkQuality>(
      stream: widget.networkQualityStream,
      initialData: widget.initialNetworkQuality,
      builder: (BuildContext context, AsyncSnapshot<NetworkQuality> snapshot) {
        return NetworkQualityWidget(
          quality: snapshot.data ?? widget.initialNetworkQuality,
        );
      },
    );
  }

  // =============================================================
  // DURATION
  // =============================================================

  Widget _buildDuration() {
    return StreamBuilder<int>(
      stream: widget.durationStream,
      initialData: widget.initialDurationSeconds,
      builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
        final int seconds = (snapshot.data ?? widget.initialDurationSeconds)
            .clamp(0, _maximumDurationSeconds);

        return CallTimerWidget(duration: Duration(seconds: seconds));
      },
    );
  }

  // =============================================================
  // ERROR REPORTING
  // =============================================================

  void _reportError(String source, Object error, StackTrace stackTrace) {
    debugPrint('JR CALL [VideoCallScreen/$source] error: $error');

    debugPrintStack(
      label: 'JR CALL [VideoCallScreen/$source]',
      stackTrace: stackTrace,
    );
  }
}

// ===============================================================
// ISOLATED RTC VIDEO SURFACE
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
  State<_RtcVideoSurface> createState() => _RtcVideoSurfaceState();
}

class _RtcVideoSurfaceState extends State<_RtcVideoSurface> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();

  bool _initialized = false;
  bool _disposed = false;
  bool _rendererDisposed = false;

  MediaStream? _pendingStream;

  // =============================================================
  // LIFECYCLE
  // =============================================================

  @override
  void initState() {
    super.initState();

    _pendingStream = widget.stream;

    unawaited(_initializeRenderer());
  }

  @override
  void didUpdateWidget(covariant _RtcVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.stream, widget.stream)) {
      _pendingStream = widget.stream;

      _attachPendingStream();
    }
  }

  Future<void> _initializeRenderer() async {
    try {
      await _renderer.initialize();

      if (_disposed) {
        await _disposeRendererOnce();
        return;
      }

      _initialized = true;

      _attachPendingStream();

      if (mounted) {
        setState(() {});
      }
    } catch (error, stackTrace) {
      if (!_disposed) {
        debugPrint('JR CALL [VideoRenderer] initialization error: $error');

        debugPrintStack(
          label: 'JR CALL [VideoRenderer]',
          stackTrace: stackTrace,
        );
      }
    }
  }

  void _attachPendingStream() {
    if (!_initialized || _disposed || _rendererDisposed) {
      return;
    }

    final MediaStream? targetStream = _pendingStream;

    if (identical(_renderer.srcObject, targetStream)) {
      return;
    }

    _renderer.srcObject = targetStream;
  }

  Future<void> _disposeRendererOnce() async {
    if (_rendererDisposed) {
      return;
    }

    _rendererDisposed = true;

    try {
      _renderer.srcObject = null;

      await _renderer.dispose();
    } catch (error, stackTrace) {
      debugPrint('JR CALL [VideoRenderer] disposal error: $error');

      debugPrintStack(
        label: 'JR CALL [VideoRenderer/dispose]',
        stackTrace: stackTrace,
      );
    }
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    if (!_initialized || _rendererDisposed) {
      return ColoredBox(
        color: widget.backgroundColor,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF087AF5),
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

    unawaited(_disposeRendererOnce());

    super.dispose();
  }
}

// ===============================================================
// VIDEO ACTION BUTTON
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
  Widget build(BuildContext context) {
    final bool actionEnabled = enabled && !busy;

    return Semantics(
      button: true,
      enabled: actionEnabled,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: AnimatedOpacity(
          opacity: actionEnabled || busy ? 1 : 0.45,
          duration: const Duration(milliseconds: 150),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: actionEnabled ? onPressed : null,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.22),
                  ),
                ),
                alignment: Alignment.center,
                child: busy
                    ? SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accentColor,
                        ),
                      )
                    : Icon(icon, color: accentColor, size: 24),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===============================================================
// END OF FILE
//
// FIXED: BUG 08, BUG 09
//
// ALSO FIXED:
// - Removed duplicate JR CALL / Premium Calling Experience top card.
// - Real compact status retained without duplicate branding.
// - Local camera preview remains available before remote connection.
// - Remote video renders only when a real remote stream exists.
// - Added local/remote tap-to-swap presentation.
// - Existing double-tap camera-switch behaviour preserved.
// - No second WebRTC/PeerConnection/media ownership introduced.
// - Safer renderer stream updates during async initialization.
// - Renderer double-dispose race prevented.
// - Camera actions protected against duplicate execution.
// - End-call action protected against duplicate execution.
// - Failed end callback safely unlocks UI.
// - No hard-coded fake CONNECTED state introduced.
// - Caller online indicator derives from actual connected status.
// - Existing constructor and callback API preserved.
//
// STATUS: READY FOR FORMAT + ANALYZE
//
// NEXT FILE: call_history_screen.dart
// Location: lib/screens/call_history_screen.dart
// ===============================================================
