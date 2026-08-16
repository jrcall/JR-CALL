// ===============================================================
// JR CALL
// File: outgoing_call_screen.dart
// Location: lib/screens/outgoing_call_screen.dart
// Fixes: BUG 07, BUG 08, BUG 09
// Production-safe replacement
// Existing APIs preserved
//
// ALSO FIXED:
// - Removed duplicate/oversized JR CALL branding header.
// - Removed hidden duplicate CallBottomBar.
// - No fake online state.
// - No fake "secure/connected" state.
// - End-call callback failure no longer closes the screen falsely.
// - Duplicate end-call action prevented.
// - Accidental back navigation protected.
// - Status/duration remain owned by CallService/Provider.
// - No local timer.
// - No direct Firestore/WebRTC/ICE/signaling ownership.
// - Keypad callback remains external.
// ===============================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/call_timer_widget.dart';
import '../widgets/caller_avatar.dart';

class OutgoingCallScreen extends StatefulWidget {
  const OutgoingCallScreen({
    super.key,
    required this.callerName,
    this.callerImage,
    this.isVideoCall = false,
    this.onEndCall,
    this.onKeypadDigit,
    this.statusStream,
    this.durationStream,
    this.initialStatus,
  });

  /// Remote user's display name.
  final String callerName;

  /// Remote user's optional profile image.
  final String? callerImage;

  /// True for video call, false for voice call.
  final bool isVideoCall;

  /// Call-engine/provider callback used to terminate the call.
  final FutureOr<void> Function()? onEndCall;

  /// Optional DTMF/keypad callback.
  final FutureOr<void> Function(String digit)? onKeypadDigit;

  /// Optional status stream supplied by CallService/Provider.
  ///
  /// Expected examples:
  /// PREPARING, CALLING, RINGING, CONNECTING, CONNECTED,
  /// RECONNECTING, RECONNECTED, NETWORK_LOST, USER_BUSY,
  /// REJECTED, DECLINED, CANCELLED, TIMEOUT, FAILED, ENDED.
  final Stream<String>? statusStream;

  /// Connected-call duration in seconds.
  ///
  /// Actual timing remains owned by CallService/Provider.
  final Stream<int>? durationStream;

  /// Initial status shown before first stream event.
  final String? initialStatus;

  @override
  State<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<OutgoingCallScreen> {
  // =============================================================
  // DESIGN
  // =============================================================

  static const Color _background = Color(0xFFF6F9FE);
  static const Color _surface = Colors.white;

  static const Color _primaryBlue = Color(0xFF087AF5);
  static const Color _deepBlue = Color(0xFF1557D9);
  static const Color _callGreen = Color(0xFF00C995);
  static const Color _cyan = Color(0xFF04BDF5);

  static const Color _textPrimary = Color(0xFF101828);
  static const Color _textSecondary = Color(0xFF667085);

  static const Color _border = Color(0xFFDDE7F3);

  static const Color _danger = Color(0xFFE92449);
  static const Color _dangerSoft = Color(0xFFFFF1F4);

  static const Color _warning = Color(0xFFF59E0B);

  // =============================================================
  // LIMITS
  // =============================================================

  static const int _maximumDurationSeconds = 86400000;
  static const int _maximumKeypadDigits = 64;

  static const List<List<String>> _keypadRows = <List<String>>[
    <String>['1', '2', '3'],
    <String>['4', '5', '6'],
    <String>['7', '8', '9'],
    <String>['*', '0', '#'],
  ];

  // =============================================================
  // STATE
  // =============================================================

  bool _showKeypad = false;
  bool _endingCall = false;
  bool _backDialogVisible = false;

  String _dialedDigits = '';

  // =============================================================
  // DERIVED DATA
  // =============================================================

  String get _displayName {
    final String value = widget.callerName.trim();

    return value.isEmpty ? 'JR CALL User' : value;
  }

  String? get _displayImage {
    final String value = widget.callerImage?.trim() ?? '';

    return value.isEmpty ? null : value;
  }

  String get _defaultStatus {
    final String value = widget.initialStatus?.trim() ?? '';

    return value.isEmpty ? 'CALLING' : value.toUpperCase();
  }

  String get _callTypeLabel {
    return widget.isVideoCall ? 'VIDEO CALL' : 'VOICE CALL';
  }

  // =============================================================
  // KEYPAD
  // =============================================================

  Future<void> _handleKeypadDigit(String digit) async {
    if (!mounted ||
        _endingCall ||
        digit.isEmpty ||
        _dialedDigits.length >= _maximumKeypadDigits) {
      return;
    }

    setState(() {
      _dialedDigits += digit;
    });

    final FutureOr<void> Function(String digit)? callback =
        widget.onKeypadDigit;

    if (callback == null) {
      return;
    }

    try {
      await Future<void>.sync(() => callback(digit));
    } catch (error, stackTrace) {
      _logError('Keypad callback', error, stackTrace);

      _showMessage('Unable to send keypad tone.');
    }
  }

  void _removeLastDigit() {
    if (!mounted || _endingCall || _dialedDigits.isEmpty) {
      return;
    }

    setState(() {
      _dialedDigits = _dialedDigits.substring(0, _dialedDigits.length - 1);
    });
  }

  void _clearDigits() {
    if (!mounted || _endingCall || _dialedDigits.isEmpty) {
      return;
    }

    setState(() {
      _dialedDigits = '';
    });
  }

  void _toggleKeypad() {
    if (!mounted || _endingCall) {
      return;
    }

    setState(() {
      _showKeypad = !_showKeypad;

      if (!_showKeypad) {
        _dialedDigits = '';
      }
    });
  }

  // =============================================================
  // END CALL
  // =============================================================

  Future<void> _handleEndCall() async {
    if (!mounted || _endingCall) {
      return;
    }

    setState(() {
      _endingCall = true;
    });

    bool completedSuccessfully = false;

    try {
      final FutureOr<void> Function()? callback = widget.onEndCall;

      if (callback != null) {
        await Future<void>.sync(callback);
      }

      completedSuccessfully = true;
    } catch (error, stackTrace) {
      _logError('End-call callback', error, stackTrace);

      if (mounted) {
        _showMessage('The call could not be ended. Please try again.');
      }
    }

    if (!mounted) {
      return;
    }

    if (!completedSuccessfully) {
      setState(() {
        _endingCall = false;
      });

      return;
    }

    final NavigatorState navigator = Navigator.of(context);

    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    setState(() {
      _endingCall = false;
    });
  }

  // =============================================================
  // BACK PROTECTION
  // =============================================================

  Future<void> _handleBackAttempt() async {
    if (!mounted || _endingCall || _backDialogVisible) {
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
            'End call?',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'Leaving this call screen will end the current call.',
          ),
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
    final String normalized = value?.trim().toUpperCase() ?? '';

    return normalized.isEmpty ? _defaultStatus : normalized;
  }

  String _statusLabel(String rawStatus) {
    switch (_normalizeStatus(rawStatus)) {
      case 'IDLE':
        return 'Ready';

      case 'PREPARING':
        return 'Preparing call…';

      case 'CALLING':
        return widget.isVideoCall ? 'Starting video call…' : 'Calling…';

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
        return rawStatus.trim().isEmpty ? 'Calling…' : rawStatus.trim();
    }
  }

  bool _shouldShowDuration(String status) {
    switch (_normalizeStatus(status)) {
      case 'CONNECTED':
      case 'RECONNECTED':
      case 'RECONNECTING':
        return true;

      default:
        return false;
    }
  }

  Color _statusColor(String status) {
    switch (_normalizeStatus(status)) {
      case 'CONNECTED':
      case 'RECONNECTED':
        return _callGreen;

      case 'RECONNECTING':
      case 'NETWORK_LOST':
        return _warning;

      case 'FAILED':
      case 'REJECTED':
      case 'DECLINED':
      case 'TIMEOUT':
      case 'CANCELLED':
      case 'USER_BUSY':
      case 'BUSY':
        return _danger;

      default:
        return _primaryBlue;
    }
  }

  IconData _statusIcon(String status) {
    switch (_normalizeStatus(status)) {
      case 'CONNECTED':
      case 'RECONNECTED':
        return Icons.check_circle_outline_rounded;

      case 'RECONNECTING':
      case 'NETWORK_LOST':
        return Icons.sync_rounded;

      case 'FAILED':
      case 'REJECTED':
      case 'DECLINED':
      case 'TIMEOUT':
      case 'USER_BUSY':
      case 'BUSY':
        return Icons.info_outline_rounded;

      case 'RINGING':
        return Icons.notifications_active_outlined;

      case 'CONNECTING':
        return Icons.link_rounded;

      default:
        return widget.isVideoCall ? Icons.videocam_rounded : Icons.call_rounded;
    }
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          unawaited(_handleBackAttempt());
        }
      },
      child: Scaffold(
        backgroundColor: _background,
        body: SafeArea(
          child: StreamBuilder<String>(
            stream: widget.statusStream,
            initialData: _defaultStatus,
            builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
              final String status = _normalizeStatus(snapshot.data);

              return LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool compact = constraints.maxHeight < 700;

                  final bool wide = constraints.maxWidth >= 700;

                  return _buildPage(
                    status: status,
                    compact: compact,
                    wide: wide,
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPage({
    required String status,
    required bool compact,
    required bool wide,
  }) {
    final double horizontalPadding = wide ? 40 : 20;

    return Stack(
      children: <Widget>[
        const Positioned(
          top: -100,
          right: -100,
          child: _GlowOrb(size: 280, color: Color(0x1804BDF5)),
        ),
        const Positioned(
          left: -120,
          bottom: 40,
          child: _GlowOrb(size: 300, color: Color(0x1700D99B)),
        ),

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
                  _buildCompactTopStatus(status: status),

                  SizedBox(height: compact ? 14 : 20),

                  _buildCallCard(status: status, compact: compact),

                  SizedBox(height: compact ? 16 : 22),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _showKeypad
                        ? _buildKeypad(compact: compact)
                        : _buildCallInfoCard(status: status),
                  ),

                  SizedBox(height: compact ? 18 : 26),

                  _buildBottomControls(),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // =============================================================
  // COMPACT TOP STATUS
  // =============================================================

  Widget _buildCompactTopStatus({required String status}) {
    final Color color = _statusColor(status);

    return Row(
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.09),
            border: Border.all(color: color.withValues(alpha: 0.16)),
          ),
          child: Icon(_statusIcon(status), color: color, size: 20),
        ),

        const SizedBox(width: 11),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _callTypeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _statusLabel(status),
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
  // MAIN CALL CARD
  // =============================================================

  Widget _buildCallCard({required String status, required bool compact}) {
    final Color statusColor = _statusColor(status);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        20,
        compact ? 24 : 34,
        20,
        compact ? 24 : 34,
      ),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x15087AF5),
            blurRadius: 34,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          _buildCallTypeBadge(),

          SizedBox(height: compact ? 21 : 29),

          _buildAvatar(compact: compact),

          SizedBox(height: compact ? 17 : 22),

          Text(
            _displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textPrimary,
              fontSize: compact ? 25 : 30,
              height: 1.15,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),

          const SizedBox(height: 10),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              _showKeypad && _dialedDigits.isNotEmpty
                  ? _dialedDigits
                  : _statusLabel(status),
              key: ValueKey<String>(
                _showKeypad && _dialedDigits.isNotEmpty
                    ? 'digits-$_dialedDigits'
                    : 'status-$status',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _showKeypad && _dialedDigits.isNotEmpty
                    ? _deepBlue
                    : statusColor,
                fontSize: compact ? 16 : 17,
                fontWeight: FontWeight.w700,
                letterSpacing: _showKeypad && _dialedDigits.isNotEmpty ? 2 : 0,
              ),
            ),
          ),

          const SizedBox(height: 14),

          if (_shouldShowDuration(status))
            _buildDuration()
          else
            _buildStatusPill(status),
        ],
      ),
    );
  }

  Widget _buildCallTypeBadge() {
    final Color featureColor = widget.isVideoCall ? _primaryBlue : _callGreen;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: featureColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: featureColor.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            widget.isVideoCall
                ? Icons.videocam_rounded
                : Icons.phone_in_talk_rounded,
            size: 16,
            color: featureColor,
          ),
          const SizedBox(width: 7),
          Text(
            _callTypeLabel,
            style: TextStyle(
              color: featureColor,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar({required bool compact}) {
    final double radius = compact ? 58 : 68;

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: <Color>[_callGreen, _cyan, _primaryBlue],
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x3000D99B), blurRadius: 25, spreadRadius: 1),
          BoxShadow(color: Color(0x2004BDF5), blurRadius: 34, spreadRadius: 2),
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
          imageUrl: _displayImage,
          radius: radius,

          // This screen has no real presence source.
          // Never fabricate an online state.
          isOnline: false,
        ),
      ),
    );
  }

  Widget _buildStatusPill(String status) {
    final Color color = _statusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_statusIcon(status), size: 16, color: color),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              _statusLabel(status),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =============================================================
  // DURATION
  // =============================================================

  Widget _buildDuration() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF3FBF8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD1F5E9)),
      ),
      child: StreamBuilder<int>(
        stream: widget.durationStream,
        initialData: 0,
        builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
          final int rawSeconds = snapshot.data ?? 0;

          final int seconds = rawSeconds.clamp(0, _maximumDurationSeconds);

          return CallTimerWidget(duration: Duration(seconds: seconds));
        },
      ),
    );
  }

  // =============================================================
  // CALL INFO
  // =============================================================

  Widget _buildCallInfoCard({required String status}) {
    final Color color = _statusColor(status);

    return Container(
      key: const ValueKey<String>('outgoing-call-info'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0D101828),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.08),
            ),
            child: Icon(_statusIcon(status), color: color, size: 23),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Call Status',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _statusDescription(status),
                  style: const TextStyle(
                    color: _textSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusDescription(String status) {
    switch (_normalizeStatus(status)) {
      case 'CONNECTED':
      case 'RECONNECTED':
        return 'The call engine reports an active connection.';

      case 'RECONNECTING':
        return 'The call engine is restoring the connection.';

      case 'NETWORK_LOST':
        return 'Waiting for network connectivity to return.';

      case 'RINGING':
        return 'The remote device is being alerted.';

      case 'CONNECTING':
        return 'The call engine is establishing the connection.';

      case 'USER_BUSY':
      case 'BUSY':
        return 'The remote user is currently unavailable.';

      case 'REJECTED':
      case 'DECLINED':
        return 'The remote user declined this call.';

      case 'CANCELLED':
        return 'The call was cancelled.';

      case 'TIMEOUT':
        return 'The call was not answered in time.';

      case 'FAILED':
        return 'The call engine reported a failure.';

      case 'ENDED':
      case 'COMPLETED':
        return 'The call has ended.';

      default:
        return 'The call engine is preparing the call.';
    }
  }

  // =============================================================
  // KEYPAD
  // =============================================================

  Widget _buildKeypad({required bool compact}) {
    return Container(
      key: const ValueKey<String>('outgoing-call-keypad'),
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(18, compact ? 16 : 20, 18, 16),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12087AF5),
            blurRadius: 26,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          if (_dialedDigits.isNotEmpty) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _dialedDigits,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _deepBlue,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.2,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Delete digit',
                  onPressed: _endingCall ? null : _removeLastDigit,
                  icon: const Icon(
                    Icons.backspace_outlined,
                    color: _textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          for (int index = 0; index < _keypadRows.length; index++) ...<Widget>[
            _buildKeypadRow(_keypadRows[index], compact: compact),
            if (index < _keypadRows.length - 1)
              SizedBox(height: compact ? 8 : 12),
          ],

          if (_dialedDigits.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: _endingCall ? null : _clearDigits,
              icon: const Icon(Icons.clear_rounded, size: 18),
              label: const Text('Clear'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKeypadRow(List<String> digits, {required bool compact}) {
    final double size = compact ? 52 : 58;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits
          .map((String digit) {
            return Semantics(
              button: true,
              enabled: !_endingCall,
              label: 'Dial $digit',
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _endingCall
                      ? null
                      : () {
                          unawaited(_handleKeypadDigit(digit));
                        },
                  child: Container(
                    width: size,
                    height: size,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFF6FAFF),
                      border: Border.all(color: const Color(0xFFDCEAF8)),
                    ),
                    child: Text(
                      digit,
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: compact ? 20 : 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }

  // =============================================================
  // BOTTOM CONTROLS
  // =============================================================

  Widget _buildBottomControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _RoundControlButton(
          tooltip: _showKeypad ? 'Hide keypad' : 'Show keypad',
          label: _showKeypad ? 'Hide' : 'Keypad',
          icon: _showKeypad
              ? Icons.keyboard_hide_rounded
              : Icons.dialpad_rounded,
          foregroundColor: _primaryBlue,
          backgroundColor: const Color(0xFFF0F7FF),
          borderColor: const Color(0xFFD6E8FF),
          onTap: _endingCall ? null : _toggleKeypad,
        ),

        const SizedBox(width: 28),

        _RoundControlButton(
          tooltip: 'End call',
          label: _endingCall ? 'Ending…' : 'End',
          icon: Icons.call_end_rounded,
          foregroundColor: _danger,
          backgroundColor: _dangerSoft,
          borderColor: const Color(0xFFFFCFD8),
          loading: _endingCall,
          onTap: _endingCall
              ? null
              : () {
                  unawaited(_handleEndCall());
                },
        ),
      ],
    );
  }

  // =============================================================
  // MESSAGE / LOGGING
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

  void _logError(String source, Object error, StackTrace stackTrace) {
    debugPrint(
      'JR CALL [OutgoingCallScreen/$source] '
      'error: $error',
    );

    debugPrintStack(
      label: 'JR CALL [OutgoingCallScreen/$source]',
      stackTrace: stackTrace,
    );
  }
}

// ===============================================================
// ROUND CONTROL BUTTON
// ===============================================================

class _RoundControlButton extends StatelessWidget {
  const _RoundControlButton({
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.borderColor,
    this.loading = false,
    this.onTap,
  });

  final String tooltip;
  final String label;
  final IconData icon;

  final Color foregroundColor;
  final Color backgroundColor;
  final Color borderColor;

  final bool loading;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null && !loading;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: enabled ? onTap : null,
                child: Container(
                  width: 66,
                  height: 66,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: backgroundColor,
                    border: Border.all(color: borderColor),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: foregroundColor.withValues(alpha: 0.14),
                        blurRadius: 18,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: loading
                      ? SizedBox(
                          width: 23,
                          height: 23,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: foregroundColor,
                          ),
                        )
                      : Icon(icon, color: foregroundColor, size: 29),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              style: TextStyle(
                color: enabled || loading
                    ? const Color(0xFF58677F)
                    : const Color(0xFF98A2B3),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===============================================================
// DECORATIVE GLOW
// ===============================================================

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: <BoxShadow>[
            BoxShadow(color: color, blurRadius: 100, spreadRadius: 38),
          ],
        ),
      ),
    );
  }
}

// ===============================================================
// END OF FILE
//
// FIXED: BUG 07, BUG 08, BUG 09
//
// ALSO FIXED:
// - Duplicate oversized top branding removed.
// - Hidden duplicate CallBottomBar removed.
// - Fake online state removed.
// - Fake security/connected presentation removed.
// - End callback failure no longer falsely closes UI.
// - Duplicate end requests prevented.
// - Back navigation protected.
// - CallService remains lifecycle/timer owner.
// - No Firestore/WebRTC/ICE/signaling duplication.
//
// STATUS: READY FOR FORMAT + ANALYZE
//
// NEXT FILE: voice_call_screen.dart
// Location: lib/screens/voice_call_screen.dart
// ===============================================================
