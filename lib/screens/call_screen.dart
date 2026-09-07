import 'dart:async';

import 'package:flutter/material.dart';

import '../providers/call_state.dart';
import '../widgets/call_timer_widget.dart';
import '../widgets/caller_avatar.dart';

/// ===========================================================
/// JR CALL
/// File: call_screen.dart
/// Location: lib/screens/call_screen.dart
///
/// Production active-call presentation screen.
///
/// Architecture:
/// - Call lifecycle -> CallService / Provider.
/// - Audio state -> parent/provider.
/// - Video state -> parent/provider.
/// - Network/recovery/WebRTC/ICE/signaling -> external owners.
/// - This screen owns presentation and user-action forwarding only.
///
/// Rules:
/// - No duplicate Provider creation.
/// - No local timer.
/// - No direct WebRTC.
/// - No direct Firestore.
/// - No direct signaling.
/// - No direct recovery.
/// - No direct ICE.
/// - No fake online state.
/// - No unverified security/encryption claim.
/// ===========================================================

class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.userName,
    required this.onEndCall,
    this.userImage,
    this.connectionState = CallConnectionState.idle,
    this.durationSeconds = 0,
    this.durationStream,
    this.isMuted = false,
    this.isSpeakerEnabled = false,
    this.isBluetoothEnabled = false,
    this.isVideoEnabled = false,
    this.isFrontCamera = true,
    this.isVideoCall = false,
    this.isEncrypted = true,
    this.onToggleMute,
    this.onToggleSpeaker,
    this.onToggleBluetooth,
    this.onToggleVideo,
    this.onSwitchCamera,
    this.onKeypadDigit,
  });

  final String userName;

  final String? userImage;

  final CallConnectionState connectionState;

  final int durationSeconds;

  final Stream<int>? durationStream;

  final bool isMuted;

  final bool isSpeakerEnabled;

  final bool isBluetoothEnabled;

  final bool isVideoEnabled;

  final bool isFrontCamera;

  final bool isVideoCall;

  /// Retained for public API compatibility.
  ///
  /// This screen does not render an unverified security claim
  /// from this legacy presentation value.
  final bool isEncrypted;

  final FutureOr<void> Function() onEndCall;

  final FutureOr<void> Function()? onToggleMute;

  final FutureOr<void> Function()? onToggleSpeaker;

  final FutureOr<void> Function()? onToggleBluetooth;

  final FutureOr<void> Function()? onToggleVideo;

  final FutureOr<void> Function()? onSwitchCamera;

  final FutureOr<void> Function(String digit)? onKeypadDigit;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  // ===========================================================
  // Design
  // ===========================================================

  static const Color _background = Color(0xFFF5F8FE);
  static const Color _surface = Color(0xFFFFFFFF);

  static const Color _primaryBlue = Color(0xFF087AF5);
  static const Color _deepBlue = Color(0xFF1557D9);
  static const Color _cyan = Color(0xFF04BDF5);
  static const Color _callGreen = Color(0xFF00D99B);

  static const Color _textPrimary = Color(0xFF101828);
  static const Color _textSecondary = Color(0xFF58677F);

  static const Color _border = Color(0xFFDCE7F5);

  static const Color _danger = Color(0xFFFF1744);
  static const Color _warning = Color(0xFFFFB020);

  // ===========================================================
  // Limits
  // ===========================================================

  static const int _maximumDurationSeconds = 86400000;

  static const int _maximumKeypadDigits = 64;

  // ===========================================================
  // State
  // ===========================================================

  bool _showKeypad = false;

  bool _endingCall = false;

  bool _endActionCompleted = false;

  bool _backDialogVisible = false;

  bool _muteBusy = false;

  bool _speakerBusy = false;

  bool _bluetoothBusy = false;

  bool _videoBusy = false;

  bool _cameraBusy = false;

  String _dialedDigits = '';

  // ===========================================================
  // Widget Updates
  // ===========================================================

  @override
  void didUpdateWidget(
      covariant CallScreen oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    final bool wasTerminal = _isTerminalConnectionState(
      oldWidget.connectionState,
    );

    final bool isTerminal = _isTerminalConnectionState(
      widget.connectionState,
    );

    if (!wasTerminal && isTerminal) {
      _showKeypad = false;
      _dialedDigits = '';

      _muteBusy = false;
      _speakerBusy = false;
      _bluetoothBusy = false;
      _videoBusy = false;
      _cameraBusy = false;
    }

    if (wasTerminal && !isTerminal) {
      _endActionCompleted = false;
      _endingCall = false;
    }
  }

  // ===========================================================
  // Derived State
  // ===========================================================

  String get _displayName {
    final String value = widget.userName.trim();

    return value.isEmpty
        ? 'JR CALL User'
        : value;
  }

  String get _statusText {
    switch (widget.connectionState) {
      case CallConnectionState.idle:
        return 'Ready';

      case CallConnectionState.initializing:
        return 'Preparing call…';

      case CallConnectionState.connecting:
        return 'Connecting…';

      case CallConnectionState.outgoing:
        return 'Calling…';

      case CallConnectionState.ringing:
        return 'Ringing…';

      case CallConnectionState.incoming:
        return 'Incoming call';

      case CallConnectionState.connected:
        return widget.isVideoCall
            ? 'Video call connected'
            : 'Voice call connected';

      case CallConnectionState.reconnecting:
        return 'Reconnecting…';

      case CallConnectionState.disconnected:
        return 'Disconnected';

      case CallConnectionState.ended:
        return 'Call ended';

      case CallConnectionState.failed:
        return 'Call failed';
    }
  }

  bool get _showCallDuration {
    return widget.connectionState ==
        CallConnectionState.connected ||
        widget.connectionState ==
            CallConnectionState.reconnecting;
  }

  bool get _isCallTerminal {
    return _isTerminalConnectionState(
      widget.connectionState,
    );
  }

  bool get _controlsDisabled {
    return _endingCall ||
        _endActionCompleted ||
        _isCallTerminal;
  }

  bool _isTerminalConnectionState(
      CallConnectionState state,
      ) {
    return state == CallConnectionState.ended ||
        state == CallConnectionState.failed;
  }

  Color get _statusColor {
    switch (widget.connectionState) {
      case CallConnectionState.connected:
        return _callGreen;

      case CallConnectionState.reconnecting:
        return _warning;

      case CallConnectionState.failed:
      case CallConnectionState.disconnected:
      case CallConnectionState.ended:
        return _danger;

      default:
        return _primaryBlue;
    }
  }

  IconData get _statusIcon {
    switch (widget.connectionState) {
      case CallConnectionState.connected:
        return Icons.check_circle_rounded;

      case CallConnectionState.reconnecting:
        return Icons.sync_rounded;

      case CallConnectionState.failed:
      case CallConnectionState.disconnected:
        return Icons.error_rounded;

      case CallConnectionState.ended:
        return Icons.call_end_rounded;

      case CallConnectionState.ringing:
        return Icons.notifications_active_rounded;

      default:
        return Icons.wifi_calling_3_rounded;
    }
  }

  // ===========================================================
  // Safe Action Runner
  // ===========================================================

  Future<void> _runAction({
    required FutureOr<void> Function()? callback,
    required bool busy,
    required void Function(bool value) setBusy,
    required String source,
  }) async {
    if (callback == null ||
        busy ||
        _controlsDisabled) {
      return;
    }

    setBusy(true);
    _refresh();

    try {
      await Future<void>.sync(
        callback,
      );
    } catch (error, stackTrace) {
      _reportError(
        source,
        error,
        stackTrace,
      );

      _showMessage(
        'Unable to complete this call action.',
      );
    } finally {
      setBusy(false);
      _refresh();
    }
  }

  // ===========================================================
  // End Call
  // ===========================================================

  Future<bool> _handleEndCall({
    bool popAfterSuccess = false,
  }) async {
    if (!mounted ||
        _endingCall ||
        _endActionCompleted ||
        _isCallTerminal) {
      return false;
    }

    setState(() {
      _endingCall = true;
    });

    try {
      await Future<void>.sync(
        widget.onEndCall,
      );
    } catch (error, stackTrace) {
      _reportError(
        'End call',
        error,
        stackTrace,
      );

      if (!mounted) {
        return false;
      }

      setState(() {
        _endingCall = false;
      });

      _showMessage(
        'The call could not be ended. Please try again.',
      );

      return false;
    }

    if (!mounted) {
      return true;
    }

    setState(() {
      _endingCall = false;
      _endActionCompleted = true;

      _showKeypad = false;
      _dialedDigits = '';
    });

    if (popAfterSuccess) {
      WidgetsBinding.instance.addPostFrameCallback(
            (_) {
          if (!mounted) {
            return;
          }

          final NavigatorState navigator =
          Navigator.of(context);

          if (navigator.canPop()) {
            navigator.maybePop();
          }
        },
      );
    }

    return true;
  }

  // ===========================================================
  // Back Navigation Protection
  // ===========================================================

  Future<void> _handleBackAttempt() async {
    if (!mounted ||
        _endingCall ||
        _backDialogVisible) {
      return;
    }

    if (_isCallTerminal ||
        _endActionCompleted) {
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

      await _handleEndCall(
        popAfterSuccess: true,
      );
    } finally {
      _backDialogVisible = false;
    }
  }

  Future<bool> _confirmEndCall() async {
    if (!mounted) {
      return false;
    }

    final bool? result =
    await showDialog<bool>(
      context: context,
      builder: (
          BuildContext dialogContext,
          ) {
        return AlertDialog(
          title: const Text(
            'End call?',
            style: TextStyle(
              fontWeight: FontWeight.w800,
            ),
          ),
          content: const Text(
            'Leaving this screen will end the current call.',
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

  // ===========================================================
  // Keypad
  // ===========================================================

  Future<void> _onKeyTap(
      String digit,
      ) async {
    if (_controlsDisabled ||
        digit.isEmpty ||
        _dialedDigits.length >=
            _maximumKeypadDigits) {
      return;
    }

    setState(() {
      _dialedDigits += digit;
    });

    final FutureOr<void> Function(String digit)?
    callback = widget.onKeypadDigit;

    if (callback == null) {
      return;
    }

    try {
      await Future<void>.sync(
            () => callback(digit),
      );
    } catch (error, stackTrace) {
      _reportError(
        'Keypad digit',
        error,
        stackTrace,
      );

      _showMessage(
        'Unable to send keypad tone.',
      );
    }
  }

  void _removeLastDigit() {
    if (_controlsDisabled ||
        _dialedDigits.isEmpty) {
      return;
    }

    setState(() {
      _dialedDigits =
          _dialedDigits.substring(
            0,
            _dialedDigits.length - 1,
          );
    });
  }

  void _clearDigits() {
    if (_controlsDisabled ||
        _dialedDigits.isEmpty) {
      return;
    }

    setState(() {
      _dialedDigits = '';
    });
  }

  void _toggleKeypad() {
    if (_controlsDisabled) {
      return;
    }

    setState(() {
      _showKeypad = !_showKeypad;

      if (!_showKeypad) {
        _dialedDigits = '';
      }
    });
  }

  // ===========================================================
  // Main Build
  // ===========================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    return PopScope<Object?>(
      canPop:
      _isCallTerminal ||
          _endActionCompleted,
      onPopInvokedWithResult: (
          bool didPop,
          _,
          ) {
        if (!didPop) {
          unawaited(
            _handleBackAttempt(),
          );
        }
      },
      child: Scaffold(
        backgroundColor: _background,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (
                BuildContext context,
                BoxConstraints constraints,
                ) {
              final bool compact =
                  constraints.maxHeight < 700;

              final bool wide =
                  constraints.maxWidth >= 650;

              return Center(
                child: ConstrainedBox(
                  constraints:
                  const BoxConstraints(
                    maxWidth: 760,
                  ),
                  child:
                  SingleChildScrollView(
                    physics:
                    const BouncingScrollPhysics(),
                    padding:
                    EdgeInsets.fromLTRB(
                      wide ? 32 : 16,
                      compact ? 14 : 24,
                      wide ? 32 : 16,
                      24,
                    ),
                    child: Column(
                      children: <Widget>[
                        _buildCallIdentityCard(
                          compact: compact,
                        ),

                        SizedBox(
                          height:
                          compact ? 16 : 22,
                        ),

                        AnimatedSwitcher(
                          duration:
                          const Duration(
                            milliseconds: 220,
                          ),
                          child: _showKeypad
                              ? _buildKeypad(
                            compact:
                            compact,
                          )
                              : _buildControlsCard(
                            compact:
                            compact,
                          ),
                        ),

                        const SizedBox(
                          height: 20,
                        ),

                        _buildEndCallButton(),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ===========================================================
  // Identity / Call State Card
  // ===========================================================

  Widget _buildCallIdentityCard({
    required bool compact,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        20,
        compact ? 20 : 28,
        20,
        compact ? 20 : 28,
      ),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius:
        BorderRadius.circular(30),
        border:
        Border.all(color: _border),
        boxShadow:
        const <BoxShadow>[
          BoxShadow(
            color:
            Color(0x12087AF5),
            blurRadius: 28,
            offset:
            Offset(0, 10),
          ),
          BoxShadow(
            color:
            Color(0x0F04BDF5),
            blurRadius: 45,
            spreadRadius: 3,
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          _buildCallTypePill(),

          SizedBox(
            height: compact ? 18 : 26,
          ),

          Container(
            padding:
            const EdgeInsets.all(
              5,
            ),
            decoration:
            const BoxDecoration(
              shape: BoxShape.circle,
              gradient:
              LinearGradient(
                begin:
                Alignment.topLeft,
                end:
                Alignment.bottomRight,
                colors: <Color>[
                  _primaryBlue,
                  _cyan,
                  _callGreen,
                ],
              ),
              boxShadow:
              <BoxShadow>[
                BoxShadow(
                  color:
                  Color(
                    0x3304BDF5,
                  ),
                  blurRadius: 24,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: Container(
              padding:
              const EdgeInsets.all(
                4,
              ),
              decoration:
              const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: CallerAvatar(
                name: _displayName,
                imageUrl:
                widget.userImage,
                radius:
                compact ? 52 : 64,

                // Call connection state is not public presence.
                isOnline: false,
              ),
            ),
          ),

          SizedBox(
            height: compact ? 15 : 20,
          ),

          Text(
            _displayName,
            maxLines: 2,
            overflow:
            TextOverflow.ellipsis,
            textAlign:
            TextAlign.center,
            style: TextStyle(
              color: _textPrimary,
              fontSize:
              compact ? 24 : 29,
              fontWeight:
              FontWeight.w800,
              height: 1.15,
            ),
          ),

          const SizedBox(
            height: 10,
          ),

          AnimatedSwitcher(
            duration: const Duration(
              milliseconds: 180,
            ),
            child:
            _showKeypad &&
                _dialedDigits
                    .isNotEmpty
                ? Text(
              _dialedDigits,
              key:
              ValueKey<String>(
                _dialedDigits,
              ),
              maxLines: 1,
              overflow:
              TextOverflow
                  .ellipsis,
              textAlign:
              TextAlign.center,
              style:
              const TextStyle(
                color: _deepBlue,
                fontSize: 22,
                fontWeight:
                FontWeight
                    .w700,
                letterSpacing: 2,
              ),
            )
                : _CallStatusPill(
              key:
              ValueKey<String>(
                _statusText,
              ),
              icon:
              _statusIcon,
              text:
              _statusText,
              color:
              _statusColor,
            ),
          ),

          if (_showCallDuration)
            ...<Widget>[
              const SizedBox(
                height: 16,
              ),
              _buildDuration(),
            ],

          const SizedBox(
            height: 18,
          ),

          _buildCallTypeInformation(),
        ],
      ),
    );
  }

  Widget _buildCallTypePill() {
    final Color color =
    widget.isVideoCall
        ? _primaryBlue
        : _callGreen;

    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.08,
        ),
        borderRadius:
        BorderRadius.circular(99),
        border: Border.all(
          color: color.withValues(
            alpha: 0.18,
          ),
        ),
      ),
      child: Row(
        mainAxisSize:
        MainAxisSize.min,
        children: <Widget>[
          Icon(
            widget.isVideoCall
                ? Icons.videocam_rounded
                : Icons.call_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(
            width: 6,
          ),
          Text(
            widget.isVideoCall
                ? 'VIDEO CALL'
                : 'VOICE CALL',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight:
              FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallTypeInformation() {
    return Row(
      mainAxisAlignment:
      MainAxisAlignment.center,
      children: <Widget>[
        Icon(
          widget.isVideoCall
              ? Icons.videocam_outlined
              : Icons.call_outlined,
          color: _textSecondary,
          size: 18,
        ),
        const SizedBox(
          width: 7,
        ),
        Text(
          widget.isVideoCall
              ? 'JR CALL Video'
              : 'JR CALL Voice',
          style: const TextStyle(
            color: _textSecondary,
            fontSize: 13,
            fontWeight:
            FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ===========================================================
  // Duration
  // ===========================================================

  Widget _buildDuration() {
    if (widget.durationStream == null) {
      final int seconds =
      widget.durationSeconds
          .clamp(
        0,
        _maximumDurationSeconds,
      )
          .toInt();

      return _DurationSurface(
        child: CallTimerWidget(
          duration: Duration(
            seconds: seconds,
          ),
          textColor: _deepBlue,
        ),
      );
    }

    return StreamBuilder<int>(
      stream: widget.durationStream,
      initialData:
      widget.durationSeconds,
      builder: (
          BuildContext context,
          AsyncSnapshot<int> snapshot,
          ) {
        final int seconds =
        (snapshot.data ??
            widget.durationSeconds)
            .clamp(
          0,
          _maximumDurationSeconds,
        )
            .toInt();

        return _DurationSurface(
          child: CallTimerWidget(
            duration: Duration(
              seconds: seconds,
            ),
            textColor: _deepBlue,
          ),
        );
      },
    );
  }

  // ===========================================================
  // Controls
  // ===========================================================

  Widget _buildControlsCard({
    required bool compact,
  }) {
    final bool disabled =
        _controlsDisabled;

    return Container(
      key: const ValueKey<String>(
        'call-controls',
      ),
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical:
        compact ? 18 : 22,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(
          alpha: 0.96,
        ),
        borderRadius:
        BorderRadius.circular(28),
        border:
        Border.all(color: _border),
        boxShadow:
        const <BoxShadow>[
          BoxShadow(
            color:
            Color(0x10087AF5),
            blurRadius: 24,
            offset:
            Offset(0, 8),
          ),
        ],
      ),
      child: Wrap(
        alignment:
        WrapAlignment.center,
        spacing:
        compact ? 8 : 13,
        runSpacing:
        compact ? 16 : 20,
        children: <Widget>[
          _PremiumCallActionButton(
            tooltip: widget.isMuted
                ? 'Unmute microphone'
                : 'Mute microphone',
            label: widget.isMuted
                ? 'Unmute'
                : 'Mute',
            icon: widget.isMuted
                ? Icons.mic_off_rounded
                : Icons.mic_rounded,
            selected:
            widget.isMuted,
            busy: _muteBusy,
            accentColor:
            _primaryBlue,
            onPressed:
            disabled ||
                widget.onToggleMute ==
                    null
                ? null
                : () {
              unawaited(
                _runAction(
                  callback: widget
                      .onToggleMute,
                  busy:
                  _muteBusy,
                  setBusy:
                      (bool value) {
                    _muteBusy =
                        value;
                  },
                  source:
                  'Toggle mute',
                ),
              );
            },
          ),

          _PremiumCallActionButton(
            tooltip:
            widget.isSpeakerEnabled
                ? 'Disable speaker'
                : 'Enable speaker',
            label: 'Speaker',
            icon:
            widget.isSpeakerEnabled
                ? Icons
                .volume_up_rounded
                : Icons
                .volume_down_rounded,
            selected:
            widget.isSpeakerEnabled,
            busy:
            _speakerBusy,
            accentColor:
            _callGreen,
            onPressed:
            disabled ||
                widget.onToggleSpeaker ==
                    null
                ? null
                : () {
              unawaited(
                _runAction(
                  callback: widget
                      .onToggleSpeaker,
                  busy:
                  _speakerBusy,
                  setBusy:
                      (bool value) {
                    _speakerBusy =
                        value;
                  },
                  source:
                  'Toggle speaker',
                ),
              );
            },
          ),

          _PremiumCallActionButton(
            tooltip:
            widget.isBluetoothEnabled
                ? 'Disconnect Bluetooth'
                : 'Use Bluetooth',
            label: 'Bluetooth',
            icon: Icons
                .bluetooth_audio_rounded,
            selected:
            widget.isBluetoothEnabled,
            busy:
            _bluetoothBusy,
            accentColor: _cyan,
            onPressed:
            disabled ||
                widget.onToggleBluetooth ==
                    null
                ? null
                : () {
              unawaited(
                _runAction(
                  callback: widget
                      .onToggleBluetooth,
                  busy:
                  _bluetoothBusy,
                  setBusy:
                      (bool value) {
                    _bluetoothBusy =
                        value;
                  },
                  source:
                  'Toggle Bluetooth',
                ),
              );
            },
          ),

          _PremiumCallActionButton(
            tooltip: _showKeypad
                ? 'Hide keypad'
                : 'Show keypad',
            label: 'Keypad',
            icon:
            Icons.dialpad_rounded,
            selected:
            _showKeypad,
            accentColor:
            _deepBlue,
            onPressed:
            disabled
                ? null
                : _toggleKeypad,
          ),

          if (widget.isVideoCall ||
              widget.onToggleVideo !=
                  null)
            _PremiumCallActionButton(
              tooltip:
              widget.isVideoEnabled
                  ? 'Turn video off'
                  : 'Turn video on',
              label: 'Video',
              icon:
              widget.isVideoEnabled
                  ? Icons
                  .videocam_rounded
                  : Icons
                  .videocam_off_rounded,
              selected:
              widget.isVideoEnabled,
              busy: _videoBusy,
              accentColor:
              _primaryBlue,
              onPressed:
              disabled ||
                  widget.onToggleVideo ==
                      null
                  ? null
                  : () {
                unawaited(
                  _runAction(
                    callback: widget
                        .onToggleVideo,
                    busy:
                    _videoBusy,
                    setBusy:
                        (bool value) {
                      _videoBusy =
                          value;
                    },
                    source:
                    'Toggle video',
                  ),
                );
              },
            ),

          if (widget.isVideoCall &&
              widget.onSwitchCamera !=
                  null)
            _PremiumCallActionButton(
              tooltip:
              'Switch camera',
              label:
              widget.isFrontCamera
                  ? 'Front'
                  : 'Back',
              icon:
              Icons.cameraswitch_rounded,
              busy: _cameraBusy,
              accentColor: _cyan,
              onPressed:
              disabled ||
                  !widget.isVideoEnabled
                  ? null
                  : () {
                unawaited(
                  _runAction(
                    callback: widget
                        .onSwitchCamera,
                    busy:
                    _cameraBusy,
                    setBusy:
                        (bool value) {
                      _cameraBusy =
                          value;
                    },
                    source:
                    'Switch camera',
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ===========================================================
  // Keypad
  // ===========================================================

  Widget _buildKeypad({
    required bool compact,
  }) {
    return Container(
      key: const ValueKey<String>(
        'call-keypad',
      ),
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        14,
        compact ? 16 : 20,
        14,
        compact ? 18 : 24,
      ),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius:
        BorderRadius.circular(28),
        border:
        Border.all(color: _border),
        boxShadow:
        const <BoxShadow>[
          BoxShadow(
            color:
            Color(0x10087AF5),
            blurRadius: 24,
            offset:
            Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize:
        MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                tooltip:
                'Hide keypad',
                onPressed:
                _controlsDisabled
                    ? null
                    : _toggleKeypad,
                icon: const Icon(
                  Icons.arrow_back_rounded,
                ),
                color:
                _textSecondary,
              ),
              const Expanded(
                child: Text(
                  'Keypad',
                  textAlign:
                  TextAlign.center,
                  style: TextStyle(
                    color:
                    _textPrimary,
                    fontSize: 17,
                    fontWeight:
                    FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip:
                'Clear keypad',
                onPressed:
                _controlsDisabled ||
                    _dialedDigits
                        .isEmpty
                    ? null
                    : _clearDigits,
                icon: const Icon(
                  Icons
                      .delete_outline_rounded,
                ),
                color:
                _textSecondary,
              ),
            ],
          ),

          if (_dialedDigits.isNotEmpty)
            ...<Widget>[
              const SizedBox(
                height: 6,
              ),
              Row(
                mainAxisAlignment:
                MainAxisAlignment
                    .center,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      _dialedDigits,
                      maxLines: 1,
                      overflow:
                      TextOverflow
                          .ellipsis,
                      style:
                      const TextStyle(
                        color:
                        _deepBlue,
                        fontSize: 22,
                        fontWeight:
                        FontWeight
                            .w700,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(
                    width: 8,
                  ),
                  IconButton(
                    tooltip:
                    'Delete last digit',
                    onPressed:
                    _controlsDisabled
                        ? null
                        : _removeLastDigit,
                    icon: const Icon(
                      Icons
                          .backspace_outlined,
                      color:
                      _textSecondary,
                    ),
                  ),
                ],
              ),
            ],

          const SizedBox(
            height: 14,
          ),

          _buildKeypadRow(
            const <String>[
              '1',
              '2',
              '3',
            ],
            compact: compact,
          ),

          const SizedBox(
            height: 10,
          ),

          _buildKeypadRow(
            const <String>[
              '4',
              '5',
              '6',
            ],
            compact: compact,
          ),

          const SizedBox(
            height: 10,
          ),

          _buildKeypadRow(
            const <String>[
              '7',
              '8',
              '9',
            ],
            compact: compact,
          ),

          const SizedBox(
            height: 10,
          ),

          _buildKeypadRow(
            const <String>[
              '*',
              '0',
              '#',
            ],
            compact: compact,
          ),
        ],
      ),
    );
  }

  Widget _buildKeypadRow(
      List<String> digits, {
        required bool compact,
      }) {
    final double size =
    compact ? 54 : 62;

    return Row(
      mainAxisAlignment:
      MainAxisAlignment.center,
      children: digits
          .map(
            (String digit) {
          return Padding(
            padding:
            const EdgeInsets
                .symmetric(
              horizontal: 9,
            ),
            child: Semantics(
              button: true,
              enabled:
              !_controlsDisabled,
              label: 'Key $digit',
              child: Material(
                color:
                Colors.transparent,
                shape:
                const CircleBorder(),
                child: InkWell(
                  customBorder:
                  const CircleBorder(),
                  onTap:
                  _controlsDisabled
                      ? null
                      : () {
                    unawaited(
                      _onKeyTap(
                        digit,
                      ),
                    );
                  },
                  child: Container(
                    width: size,
                    height: size,
                    decoration:
                    BoxDecoration(
                      shape:
                      BoxShape.circle,
                      color:
                      const Color(
                        0xFFF7FAFF,
                      ),
                      border:
                      Border.all(
                        color:
                        _border,
                      ),
                      boxShadow:
                      const <
                          BoxShadow
                      >[
                        BoxShadow(
                          color:
                          Color(
                            0x0D087AF5,
                          ),
                          blurRadius:
                          10,
                          offset:
                          Offset(
                            0,
                            4,
                          ),
                        ),
                      ],
                    ),
                    alignment:
                    Alignment
                        .center,
                    child: Text(
                      digit,
                      style:
                      TextStyle(
                        color:
                        _textPrimary,
                        fontSize:
                        compact
                            ? 20
                            : 23,
                        fontWeight:
                        FontWeight
                            .w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      )
          .toList(
        growable: false,
      ),
    );
  }

  // ===========================================================
  // End Call
  // ===========================================================

  Widget _buildEndCallButton() {
    final bool disabled =
        _endingCall ||
            _endActionCompleted ||
            _isCallTerminal;

    return Semantics(
      button: true,
      enabled: !disabled,
      label: 'End call',
      child: AnimatedOpacity(
        opacity:
        disabled ? 0.55 : 1,
        duration: const Duration(
          milliseconds: 150,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius:
          BorderRadius.circular(24),
          child: InkWell(
            borderRadius:
            BorderRadius.circular(
              24,
            ),
            onTap:
            disabled
                ? null
                : () {
              unawaited(
                _handleEndCall(),
              );
            },
            child: Container(
              width: double.infinity,
              constraints:
              const BoxConstraints(
                maxWidth: 300,
              ),
              height: 62,
              decoration: BoxDecoration(
                gradient:
                const LinearGradient(
                  begin:
                  Alignment.topLeft,
                  end:
                  Alignment.bottomRight,
                  colors: <Color>[
                    Color(
                      0xFFFF355E,
                    ),
                    _danger,
                  ],
                ),
                borderRadius:
                BorderRadius.circular(
                  24,
                ),
                boxShadow:
                const <BoxShadow>[
                  BoxShadow(
                    color:
                    Color(
                      0x40FF1744,
                    ),
                    blurRadius: 22,
                    offset:
                    Offset(0, 9),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment:
                MainAxisAlignment
                    .center,
                children: <Widget>[
                  if (_endingCall)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child:
                      CircularProgressIndicator(
                        strokeWidth: 2.3,
                        color:
                        Colors.white,
                      ),
                    )
                  else
                    Container(
                      width: 38,
                      height: 38,
                      decoration:
                      const BoxDecoration(
                        color:
                        Color(
                          0x33FFFFFF,
                        ),
                        shape:
                        BoxShape.circle,
                      ),
                      child:
                      const Icon(
                        Icons
                            .call_end_rounded,
                        color:
                        Colors.white,
                        size: 22,
                      ),
                    ),

                  const SizedBox(
                    width: 11,
                  ),

                  Text(
                    _endingCall
                        ? 'ENDING…'
                        : _isCallTerminal ||
                        _endActionCompleted
                        ? 'CALL ENDED'
                        : 'END CALL',
                    style:
                    const TextStyle(
                      color:
                      Colors.white,
                      fontSize: 15,
                      fontWeight:
                      FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================
  // Helpers
  // ===========================================================

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

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _reportError(
      String source,
      Object error,
      StackTrace stackTrace,
      ) {
    debugPrint(
      'JR CALL [CallScreen/$source] error: $error',
    );

    debugPrintStack(
      label:
      'JR CALL [CallScreen/$source]',
      stackTrace: stackTrace,
    );
  }
}

// ===========================================================
// Call Status Pill
// ===========================================================

class _CallStatusPill extends StatelessWidget {
  const _CallStatusPill({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;

  final String text;

  final Color color;

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.08,
        ),
        borderRadius:
        BorderRadius.circular(99),
        border: Border.all(
          color: color.withValues(
            alpha: 0.18,
          ),
        ),
      ),
      child: Row(
        mainAxisSize:
        MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            color: color,
            size: 17,
          ),
          const SizedBox(
            width: 7,
          ),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow:
              TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight:
                FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================
// Duration Surface
// ===========================================================

class _DurationSurface extends StatelessWidget {
  const _DurationSurface({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color:
        const Color(0xFFF3F8FF),
        borderRadius:
        BorderRadius.circular(99),
        border: Border.all(
          color:
          const Color(0xFFDCE7F5),
        ),
      ),
      child: child,
    );
  }
}

// ===========================================================
// Premium Call Action Button
// ===========================================================

class _PremiumCallActionButton
    extends StatelessWidget {
  const _PremiumCallActionButton({
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.accentColor,
    this.selected = false,
    this.busy = false,
    this.onPressed,
  });

  final String tooltip;

  final String label;

  final IconData icon;

  final Color accentColor;

  final bool selected;

  final bool busy;

  final VoidCallback? onPressed;

  @override
  Widget build(
      BuildContext context,
      ) {
    final bool enabled =
        onPressed != null &&
            !busy;

    final Color iconColor =
    selected
        ? Colors.white
        : enabled
        ? accentColor
        : const Color(
      0xFF98A2B3,
    );

    final Color labelColor =
    enabled
        ? const Color(
      0xFF344054,
    )
        : const Color(
      0xFF98A2B3,
    );

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: SizedBox(
          width: 76,
          child: Column(
            mainAxisSize:
            MainAxisSize.min,
            children: <Widget>[
              Material(
                color:
                Colors.transparent,
                shape:
                const CircleBorder(),
                child: InkWell(
                  onTap:
                  enabled
                      ? onPressed
                      : null,
                  customBorder:
                  const CircleBorder(),
                  child:
                  AnimatedContainer(
                    duration:
                    const Duration(
                      milliseconds: 180,
                    ),
                    width: 58,
                    height: 58,
                    decoration:
                    BoxDecoration(
                      shape:
                      BoxShape.circle,
                      color: selected
                          ? accentColor
                          : const Color(
                        0xFFF7FAFF,
                      ),
                      border:
                      Border.all(
                        color: selected
                            ? accentColor
                            : const Color(
                          0xFFDCE7F5,
                        ),
                      ),
                      boxShadow:
                      <BoxShadow>[
                        BoxShadow(
                          color:
                          accentColor
                              .withValues(
                            alpha:
                            selected
                                ? 0.26
                                : 0.10,
                          ),
                          blurRadius:
                          selected
                              ? 18
                              : 10,
                          spreadRadius:
                          selected
                              ? 1
                              : 0,
                        ),
                      ],
                    ),
                    alignment:
                    Alignment.center,
                    child: busy
                        ? SizedBox(
                      width: 20,
                      height: 20,
                      child:
                      CircularProgressIndicator(
                        strokeWidth:
                        2,
                        color:
                        iconColor,
                      ),
                    )
                        : Icon(
                      icon,
                      color:
                      iconColor,
                      size: 25,
                    ),
                  ),
                ),
              ),

              const SizedBox(
                height: 8,
              ),

              Text(
                label,
                maxLines: 1,
                overflow:
                TextOverflow.ellipsis,
                textAlign:
                TextAlign.center,
                style: TextStyle(
                  color:
                  labelColor,
                  fontSize: 11.5,
                  fontWeight:
                  FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}