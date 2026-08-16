// ===============================================================
// JR CALL
// File: voice_call_screen.dart
// Location: lib/screens/voice_call_screen.dart
// Fixes: BUG 01, BUG 07
// Production-safe replacement
// Existing APIs preserved
//
// ALSO FIXED:
// - Removed unwanted JR CALL top branding/header completely.
// - No hidden/scroll-revealed branding header.
// - Default UI no longer falsely starts as CONNECTED.
// - No fake online/presence state.
// - No fake security/encryption claim.
// - End-call callback failure does not falsely close the screen.
// - Duplicate end-call actions prevented.
// - Accidental system-back navigation protected.
// - Terminal-state controls safely disabled.
// - Duration remains owned only by supplied CallService/Provider stream.
// - Network quality remains owned only by supplied network stream.
// - No timer/network/WebRTC/ICE/signaling/recovery duplication.
// ===============================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/network_model.dart';
import '../widgets/call_bottom_bar.dart';
import '../widgets/call_timer_widget.dart';
import '../widgets/caller_avatar.dart';
import '../widgets/network_quality_widget.dart';

class VoiceCallScreen extends StatefulWidget {
  const VoiceCallScreen({
    super.key,
    required this.callerName,
    this.callerImage,
    this.statusStream,
    this.durationStream,
    this.networkQualityStream,

    // Do not advertise a connected call before the real
    // CallService/Provider reports CONNECTED.
    this.initialStatus = 'CONNECTING',

    this.initialDurationSeconds = 0,
    this.initialNetworkQuality = NetworkQuality.good,
    this.onEndCall,
  });

  final String callerName;
  final String? callerImage;

  /// Real call-state source supplied by CallService/Provider.
  final Stream<String>? statusStream;

  /// Real connected-call duration supplied by CallService/Provider.
  ///
  /// This screen never creates its own duration timer.
  final Stream<int>? durationStream;

  /// Real network-quality source supplied by NetworkManager/Provider.
  final Stream<NetworkQuality>? networkQualityStream;

  final String initialStatus;
  final int initialDurationSeconds;
  final NetworkQuality initialNetworkQuality;

  /// Actual termination remains owned by CallService/Provider.
  final FutureOr<void> Function()? onEndCall;

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  // =============================================================
  // DESIGN
  // =============================================================

  static const Color _background = Color(0xFFF5F8FE);
  static const Color _surface = Colors.white;

  static const Color _primaryBlue = Color(0xFF087AF5);
  static const Color _callGreen = Color(0xFF00C995);
  static const Color _cyan = Color(0xFF04BDF5);

  static const Color _textPrimary = Color(0xFF101828);
  static const Color _textSecondary = Color(0xFF58677F);
  static const Color _border = Color(0xFFDCE7F5);

  static const Color _warning = Color(0xFFF59E0B);
  static const Color _danger = Color(0xFFE92449);

  // =============================================================
  // LIMITS
  // =============================================================

  static const int _maximumDurationSeconds = 86400000;

  // =============================================================
  // STATE
  // =============================================================

  bool _isEndingCall = false;
  bool _backDialogVisible = false;

  // =============================================================
  // SAFE DATA
  // =============================================================

  String get _displayName {
    final String value = widget.callerName.trim();

    return value.isEmpty ? 'JR CALL User' : value;
  }

  String? get _safeImageUrl {
    final String value = widget.callerImage?.trim() ?? '';

    return value.isEmpty ? null : value;
  }

  String get _safeInitialStatus {
    final String value = widget.initialStatus.trim().toUpperCase();

    // Empty/invalid presentation data must never manufacture
    // a CONNECTED state.
    return value.isEmpty ? 'CONNECTING' : value;
  }

  int get _safeInitialDuration {
    return widget.initialDurationSeconds.clamp(0, _maximumDurationSeconds);
  }

  // =============================================================
  // END CALL
  // =============================================================

  Future<void> _handleEndCall() async {
    if (!mounted || _isEndingCall) {
      return;
    }

    setState(() {
      _isEndingCall = true;
    });

    bool completedSuccessfully = false;

    try {
      final FutureOr<void> Function()? callback = widget.onEndCall;

      if (callback != null) {
        await Future<void>.sync(callback);
      }

      completedSuccessfully = true;
    } catch (error, stackTrace) {
      _reportError('End call', error, stackTrace);

      if (mounted) {
        _showMessage('The call could not be ended. Please try again.');
      }
    }

    if (!mounted) {
      return;
    }

    // Never visually leave the call as if it ended successfully
    // when the actual CallService callback failed.
    if (!completedSuccessfully) {
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
  // BACK NAVIGATION PROTECTION
  // =============================================================

  Future<void> _handleBackAttempt(String status) async {
    if (!mounted || _isEndingCall || _backDialogVisible) {
      return;
    }

    // Once the real lifecycle is terminal, leaving the screen
    // no longer needs to issue another end-call operation.
    if (_isTerminalStatus(status)) {
      final NavigatorState navigator = Navigator.of(context);

      if (navigator.canPop()) {
        navigator.pop();
      }

      return;
    }

    _backDialogVisible = true;

    try {
      final bool shouldEnd = await _confirmEndCall();

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
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text(
            'End voice call?',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: const Text('Leaving this screen will end the current call.'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Stay'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              icon: const Icon(Icons.call_end_rounded),
              label: const Text('End Call'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  // =============================================================
  // STATUS
  // =============================================================

  String _normalizeStatus(String? value) {
    final String status = value?.trim().toUpperCase() ?? '';

    return status.isEmpty ? _safeInitialStatus : status;
  }

  String _statusText(String status) {
    switch (_normalizeStatus(status)) {
      case 'IDLE':
        return 'Voice Call';

      case 'PREPARING':
        return 'Preparing call…';

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
        return 'Voice Call';
    }
  }

  bool _showCallDuration(String status) {
    switch (_normalizeStatus(status)) {
      case 'CONNECTED':
      case 'RECONNECTED':
      case 'RECONNECTING':
        return true;

      default:
        return false;
    }
  }

  bool _isConnectionWarning(String status) {
    switch (_normalizeStatus(status)) {
      case 'RECONNECTING':
      case 'NETWORK_LOST':
        return true;

      default:
        return false;
    }
  }

  bool _isFailureStatus(String status) {
    switch (_normalizeStatus(status)) {
      case 'USER_BUSY':
      case 'BUSY':
      case 'REJECTED':
      case 'DECLINED':
      case 'CANCELLED':
      case 'TIMEOUT':
      case 'FAILED':
        return true;

      default:
        return false;
    }
  }

  bool _isTerminalStatus(String status) {
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

  Color _statusColor(String status) {
    if (_isFailureStatus(status)) {
      return _danger;
    }

    if (_isConnectionWarning(status)) {
      return _warning;
    }

    switch (_normalizeStatus(status)) {
      case 'CONNECTED':
      case 'RECONNECTED':
        return _callGreen;

      default:
        return _primaryBlue;
    }
  }

  IconData _statusIcon(String status) {
    if (_isFailureStatus(status)) {
      return Icons.info_outline_rounded;
    }

    switch (_normalizeStatus(status)) {
      case 'CONNECTED':
      case 'RECONNECTED':
        return Icons.graphic_eq_rounded;

      case 'RECONNECTING':
        return Icons.sync_rounded;

      case 'NETWORK_LOST':
        return Icons.wifi_off_rounded;

      case 'RINGING':
        return Icons.notifications_active_outlined;

      case 'CONNECTING':
        return Icons.link_rounded;

      case 'ENDED':
      case 'COMPLETED':
        return Icons.call_end_rounded;

      default:
        return Icons.phone_in_talk_rounded;
    }
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: widget.statusStream,
      initialData: _safeInitialStatus,
      builder: (BuildContext context, AsyncSnapshot<String> statusSnapshot) {
        final String status = _normalizeStatus(statusSnapshot.data);

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (!didPop) {
              unawaited(_handleBackAttempt(status));
            }
          },
          child: Scaffold(
            backgroundColor: _background,
            body: SafeArea(child: _buildScreen(context, status)),
          ),
        );
      },
    );
  }

  Widget _buildScreen(BuildContext context, String status) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxHeight < 690;
        final bool narrow = constraints.maxWidth < 360;
        final bool wide = constraints.maxWidth >= 700;

        final double horizontalPadding = wide
            ? 40
            : narrow
            ? 16
            : 22;

        return Stack(
          children: <Widget>[
            const Positioned.fill(child: _VoiceBackground()),

            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    compact ? 14 : 24,
                    horizontalPadding,
                    compact ? 18 : 28,
                  ),
                  child: Column(
                    children: <Widget>[
                      // Intentionally no JR CALL logo/title/header.
                      // BUG 01 requires a clean full-screen call surface.
                      _buildCompactStatus(status),

                      SizedBox(height: compact ? 16 : 22),

                      _buildCallerCard(compact: compact),

                      SizedBox(height: compact ? 16 : 22),

                      if (_showCallDuration(status)) _buildCallDuration(),

                      if (_showCallDuration(status))
                        SizedBox(height: compact ? 13 : 18),

                      _buildStatusCard(status),

                      SizedBox(height: compact ? 16 : 22),

                      _buildNetworkCard(),

                      SizedBox(height: compact ? 22 : 30),

                      _buildBottomControls(terminal: _isTerminalStatus(status)),

                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // =============================================================
  // COMPACT STATUS
  // =============================================================

  Widget _buildCompactStatus(String status) {
    final Color color = _statusColor(status);

    return Row(
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.08),
            border: Border.all(color: color.withValues(alpha: 0.16)),
          ),
          child: Icon(_statusIcon(status), color: color, size: 20),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'VOICE CALL',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _statusText(status),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =============================================================
  // CALLER
  // =============================================================

  Widget _buildCallerCard({required bool compact}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 20,
        vertical: compact ? 26 : 36,
      ),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x18087AF5),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(5),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[_cyan, _primaryBlue, _callGreen],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Color(0x38087AF5),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: Color(0x2600C995),
                  blurRadius: 34,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: CallerAvatar(
                name: _displayName,
                imageUrl: _safeImageUrl,
                radius: compact ? 57 : 67,

                // This screen has no real presence stream.
                // Never infer online status from call/network status.
                isOnline: false,
              ),
            ),
          ),

          SizedBox(height: compact ? 18 : 24),

          Text(
            _displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textPrimary,
              fontSize: compact ? 25 : 29,
              fontWeight: FontWeight.w900,
              height: 1.08,
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'Voice Call',
            style: TextStyle(
              color: _textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // =============================================================
  // STATUS
  // =============================================================

  Widget _buildStatusCard(String status) {
    final Color color = _statusColor(status);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_statusIcon(status), color: color, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _statusText(status),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =============================================================
  // NETWORK QUALITY
  // =============================================================

  Widget _buildNetworkCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0F087AF5),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFE9F8FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.network_check_rounded,
              color: _primaryBlue,
              size: 20,
            ),
          ),

          const SizedBox(width: 12),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Network Quality',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Live call connection quality',
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          _buildNetworkQuality(),
        ],
      ),
    );
  }

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

  Widget _buildCallDuration() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _border),
      ),
      child: StreamBuilder<int>(
        stream: widget.durationStream,
        initialData: _safeInitialDuration,
        builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
          final int seconds = (snapshot.data ?? _safeInitialDuration).clamp(
            0,
            _maximumDurationSeconds,
          );

          return CallTimerWidget(duration: Duration(seconds: seconds));
        },
      ),
    );
  }

  // =============================================================
  // BOTTOM CONTROLS
  // =============================================================

  Widget _buildBottomControls({required bool terminal}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x18087AF5),
            blurRadius: 25,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: IgnorePointer(
        ignoring: _isEndingCall || terminal,
        child: AnimatedOpacity(
          opacity: _isEndingCall || terminal ? 0.50 : 1,
          duration: const Duration(milliseconds: 150),

          // Existing CallBottomBar remains the presentation
          // boundary for voice-call media controls.
          child: CallBottomBar(onEndCall: _handleEndCall),
        ),
      ),
    );
  }

  // =============================================================
  // ERROR / MESSAGE
  // =============================================================

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  void _reportError(String source, Object error, StackTrace stackTrace) {
    debugPrint(
      'JR CALL [VoiceCallScreen/$source] '
      'error: $error',
    );

    debugPrintStack(
      label: 'JR CALL [VoiceCallScreen/$source]',
      stackTrace: stackTrace,
    );
  }
}

// ===============================================================
// PREMIUM BACKGROUND
// ===============================================================

class _VoiceBackground extends StatelessWidget {
  const _VoiceBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFF8FBFF),
            Color(0xFFF3F7FE),
            Color(0xFFF4FCFA),
          ],
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -100,
            right: -90,
            child: _VoiceGlow(size: 250, color: Color(0x18087AF5)),
          ),
          Positioned(
            bottom: 70,
            left: -110,
            child: _VoiceGlow(size: 280, color: Color(0x1500C995)),
          ),
        ],
      ),
    );
  }
}

class _VoiceGlow extends StatelessWidget {
  const _VoiceGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

// ===============================================================
// END OF FILE
//
// FIXED: BUG 01, BUG 07
//
// ALSO FIXED:
// - Unwanted JR CALL/Premium Calling header removed.
// - Header cannot reappear through scrolling.
// - Fake default CONNECTED state removed.
// - Fake caller online status removed.
// - Unsupported "secure call" claim removed.
// - End-call failure no longer falsely closes screen.
// - Duplicate end-call execution blocked.
// - Active-call back navigation protected.
// - Terminal controls disabled.
// - Real status/duration/network streams preserved.
// - No Call Engine/WebRTC/ICE/signaling/recovery duplication.
//
// STATUS: READY FOR FORMAT + ANALYZE
//
// NEXT FILE: video_call_screen.dart
// Location: lib/screens/video_call_screen.dart
// ===============================================================
