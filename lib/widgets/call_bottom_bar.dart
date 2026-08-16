// ===========================================================
// JR CALL
// File: call_bottom_bar.dart
// Location: lib/widgets/call_bottom_bar.dart
//
// Description:
// Production call-control bottom bar.
//
// Responsibilities:
// - Mute / Unmute
// - Speaker on / off
// - Camera on / off
// - Switch camera
// - In-call keypad presentation
// - End call
//
// Architecture ownership:
// - Audio behavior        -> AudioManager
// - Video behavior        -> VideoManager
// - End-call lifecycle    -> Parent Call Screen / CallService
// - This widget owns UI state only
//
// Production rules:
// - Preserve public API
// - No CallService duplication
// - No signaling
// - No Firestore
// - No ICE
// - No WebRTC lifecycle
// - No duplicate call timer
// ===========================================================

import 'package:flutter/material.dart';

import '../services/call/audio_manager.dart';
import '../services/call/video_manager.dart';

class CallBottomBar extends StatefulWidget {
  const CallBottomBar({super.key, required this.onEndCall});

  final VoidCallback onEndCall;

  @override
  State<CallBottomBar> createState() => _CallBottomBarState();
}

class _CallBottomBarState extends State<CallBottomBar> {
  // ===========================================================
  // Existing real managers
  // ===========================================================

  final AudioManager _audioManager = AudioManager.instance;
  final VideoManager _videoManager = VideoManager.instance;

  // ===========================================================
  // Presentation state
  // ===========================================================

  bool _isMuted = false;
  bool _isSpeakerEnabled = false;
  bool _isCameraEnabled = true;

  bool _muteBusy = false;
  bool _speakerBusy = false;
  bool _cameraBusy = false;
  bool _switchCameraBusy = false;
  bool _endCallBusy = false;

  // ===========================================================
  // Design
  // ===========================================================

  static const Color _surface = Color(0xF5FFFFFF);
  static const Color _primaryBlue = Color(0xFF087AF5);
  static const Color _callGreen = Color(0xFF00D99B);
  static const Color _cyan = Color(0xFF04BDF5);
  static const Color _border = Color(0xFFDCE7F5);
  static const Color _danger = Color(0xFFFF1744);

  // ===========================================================
  // Microphone
  // ===========================================================

  Future<void> _toggleMute() async {
    if (_muteBusy || _endCallBusy) {
      return;
    }

    _setMuteBusy(true);

    try {
      await _audioManager.toggleMute();

      if (!mounted) {
        return;
      }

      setState(() {
        _isMuted = !_isMuted;
      });
    } catch (error, stackTrace) {
      _reportError('Toggle mute', error, stackTrace);

      _showActionError('Unable to change microphone state.');
    } finally {
      _setMuteBusy(false);
    }
  }

  // ===========================================================
  // Speaker
  // ===========================================================

  Future<void> _toggleSpeaker() async {
    if (_speakerBusy || _endCallBusy) {
      return;
    }

    _setSpeakerBusy(true);

    try {
      await _audioManager.toggleSpeaker();

      if (!mounted) {
        return;
      }

      setState(() {
        _isSpeakerEnabled = !_isSpeakerEnabled;
      });
    } catch (error, stackTrace) {
      _reportError('Toggle speaker', error, stackTrace);

      _showActionError('Unable to change speaker state.');
    } finally {
      _setSpeakerBusy(false);
    }
  }

  // ===========================================================
  // Camera
  // ===========================================================

  Future<void> _toggleCamera() async {
    if (_cameraBusy || _endCallBusy) {
      return;
    }

    _setCameraBusy(true);

    try {
      await _videoManager.toggleVideo();

      if (!mounted) {
        return;
      }

      setState(() {
        _isCameraEnabled = !_isCameraEnabled;
      });
    } catch (error, stackTrace) {
      _reportError('Toggle camera', error, stackTrace);

      _showActionError('Unable to change camera state.');
    } finally {
      _setCameraBusy(false);
    }
  }

  // ===========================================================
  // Switch Camera
  // ===========================================================

  Future<void> _switchCamera() async {
    if (_switchCameraBusy || !_isCameraEnabled || _endCallBusy) {
      return;
    }

    _setSwitchCameraBusy(true);

    try {
      await _videoManager.switchCamera();
    } catch (error, stackTrace) {
      _reportError('Switch camera', error, stackTrace);

      _showActionError('Unable to switch camera.');
    } finally {
      _setSwitchCameraBusy(false);
    }
  }

  // ===========================================================
  // End Call
  // ===========================================================

  void _endCall() {
    if (_endCallBusy) {
      return;
    }

    setState(() {
      _endCallBusy = true;
    });

    try {
      widget.onEndCall();
    } catch (error, stackTrace) {
      _reportError('End call', error, stackTrace);

      if (mounted) {
        setState(() {
          _endCallBusy = false;
        });
      }

      _showActionError('Unable to end the call.');
    }
  }

  // ===========================================================
  // Keypad
  // ===========================================================

  Future<void> _openKeypad() async {
    if (!mounted || _endCallBusy) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x730F172A),
      builder: (BuildContext sheetContext) {
        return const _CallKeypadSheet();
      },
    );
  }

  // ===========================================================
  // Busy helpers
  // ===========================================================

  void _setMuteBusy(bool value) {
    if (!mounted) {
      return;
    }

    setState(() {
      _muteBusy = value;
    });
  }

  void _setSpeakerBusy(bool value) {
    if (!mounted) {
      return;
    }

    setState(() {
      _speakerBusy = value;
    });
  }

  void _setCameraBusy(bool value) {
    if (!mounted) {
      return;
    }

    setState(() {
      _cameraBusy = value;
    });
  }

  void _setSwitchCameraBusy(bool value) {
    if (!mounted) {
      return;
    }

    setState(() {
      _switchCameraBusy = value;
    });
  }

  // ===========================================================
  // Error presentation
  // ===========================================================

  void _showActionError(String message) {
    if (!mounted) {
      return;
    }

    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );

    if (messenger == null) {
      return;
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  void _reportError(String source, Object error, StackTrace stackTrace) {
    debugPrint('JR CALL [CallBottomBar/$source] error: $error');

    debugPrintStack(
      label: 'JR CALL [CallBottomBar/$source]',
      stackTrace: stackTrace,
    );
  }

  // ===========================================================
  // Build
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double availableWidth = constraints.maxWidth;

            final bool compact = availableWidth < 390;

            final double buttonSize = compact ? 44 : 50;
            final double iconSize = compact ? 21 : 23;

            return Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 7 : 10,
                vertical: compact ? 9 : 11,
              ),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: _border, width: 1),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x14087AF5),
                    blurRadius: 30,
                    offset: Offset(0, 10),
                  ),
                  BoxShadow(
                    color: Color(0x1000D99B),
                    blurRadius: 24,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  _CallControlButton(
                    tooltip: _isMuted ? 'Unmute microphone' : 'Mute microphone',
                    icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    active: _isMuted,
                    activeColor: _danger,
                    buttonSize: buttonSize,
                    iconSize: iconSize,
                    loading: _muteBusy,
                    enabled: !_endCallBusy,
                    onTap: _toggleMute,
                  ),

                  _CallControlButton(
                    tooltip: _isSpeakerEnabled
                        ? 'Turn speaker off'
                        : 'Turn speaker on',
                    icon: _isSpeakerEnabled
                        ? Icons.volume_up_rounded
                        : Icons.volume_down_rounded,
                    active: _isSpeakerEnabled,
                    activeColor: _cyan,
                    buttonSize: buttonSize,
                    iconSize: iconSize,
                    loading: _speakerBusy,
                    enabled: !_endCallBusy,
                    onTap: _toggleSpeaker,
                  ),

                  _CallControlButton(
                    tooltip: _isCameraEnabled
                        ? 'Turn camera off'
                        : 'Turn camera on',
                    icon: _isCameraEnabled
                        ? Icons.videocam_rounded
                        : Icons.videocam_off_rounded,
                    active: !_isCameraEnabled,
                    activeColor: _danger,
                    buttonSize: buttonSize,
                    iconSize: iconSize,
                    loading: _cameraBusy,
                    enabled: !_endCallBusy,
                    onTap: _toggleCamera,
                  ),

                  _CallControlButton(
                    tooltip: 'Switch camera',
                    icon: Icons.cameraswitch_rounded,
                    active: false,
                    activeColor: _primaryBlue,
                    buttonSize: buttonSize,
                    iconSize: iconSize,
                    loading: _switchCameraBusy,
                    enabled: _isCameraEnabled && !_endCallBusy,
                    onTap: _switchCamera,
                  ),

                  _CallControlButton(
                    tooltip: 'Keypad',
                    icon: Icons.dialpad_rounded,
                    active: false,
                    activeColor: _callGreen,
                    buttonSize: buttonSize,
                    iconSize: iconSize,
                    enabled: !_endCallBusy,
                    onTap: _openKeypad,
                  ),

                  _CallControlButton(
                    tooltip: 'End call',
                    icon: Icons.call_end_rounded,
                    active: true,
                    activeColor: _danger,
                    buttonSize: buttonSize,
                    iconSize: iconSize,
                    loading: _endCallBusy,
                    enabled: !_endCallBusy,
                    destructive: true,
                    onTap: _endCall,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ===========================================================
// Private call control button
// ===========================================================

class _CallControlButton extends StatelessWidget {
  const _CallControlButton({
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.buttonSize,
    required this.iconSize,
    required this.enabled,
    required this.onTap,
    this.loading = false,
    this.destructive = false,
  });

  final String tooltip;
  final IconData icon;

  final bool active;
  final Color activeColor;

  final double buttonSize;
  final double iconSize;

  final bool enabled;
  final bool loading;
  final bool destructive;

  final VoidCallback onTap;

  static const Color _primaryBlue = Color(0xFF087AF5);
  static const Color _textSecondary = Color(0xFF58677F);
  static const Color _border = Color(0xFFDCE7F5);

  @override
  Widget build(BuildContext context) {
    final bool interactive = enabled && !loading;

    final Color backgroundColor;

    if (destructive) {
      backgroundColor = activeColor;
    } else if (active) {
      backgroundColor = activeColor.withValues(alpha: 0.12);
    } else {
      backgroundColor = const Color(0xFFF7FAFF);
    }

    final Color foregroundColor;

    if (!enabled) {
      foregroundColor = _textSecondary.withValues(alpha: 0.35);
    } else if (destructive) {
      foregroundColor = Colors.white;
    } else if (active) {
      foregroundColor = activeColor;
    } else {
      foregroundColor = _primaryBlue;
    }

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: interactive,
        selected: active,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: interactive ? onTap : null,
            customBorder: const CircleBorder(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: backgroundColor,
                border: Border.all(
                  color: destructive
                      ? activeColor
                      : active
                      ? activeColor.withValues(alpha: 0.26)
                      : _border,
                ),
                boxShadow: destructive
                    ? <BoxShadow>[
                        BoxShadow(
                          color: activeColor.withValues(alpha: 0.30),
                          blurRadius: 16,
                          offset: const Offset(0, 5),
                        ),
                      ]
                    : active
                    ? <BoxShadow>[
                        BoxShadow(
                          color: activeColor.withValues(alpha: 0.18),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : const <BoxShadow>[],
              ),
              child: Center(
                child: loading
                    ? SizedBox(
                        width: iconSize - 3,
                        height: iconSize - 3,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.1,
                          color: destructive ? Colors.white : activeColor,
                        ),
                      )
                    : Icon(icon, size: iconSize, color: foregroundColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================
// Premium keypad sheet
// ===========================================================

class _CallKeypadSheet extends StatefulWidget {
  const _CallKeypadSheet();

  @override
  State<_CallKeypadSheet> createState() => _CallKeypadSheetState();
}

class _CallKeypadSheetState extends State<_CallKeypadSheet> {
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _background = Color(0xFFF5F8FE);
  static const Color _primaryBlue = Color(0xFF087AF5);
  static const Color _callGreen = Color(0xFF00D99B);
  static const Color _textPrimary = Color(0xFF101828);
  static const Color _textSecondary = Color(0xFF58677F);
  static const Color _border = Color(0xFFDCE7F5);
  static const Color _danger = Color(0xFFFF1744);

  static const List<List<String>> _rows = <List<String>>[
    <String>['1', '2', '3'],
    <String>['4', '5', '6'],
    <String>['7', '8', '9'],
    <String>['*', '0', '#'],
  ];

  String _digits = '';

  void _appendDigit(String value) {
    setState(() {
      _digits += value;
    });
  }

  void _removeDigit() {
    if (_digits.isEmpty) {
      return;
    }

    setState(() {
      _digits = _digits.substring(0, _digits.length - 1);
    });
  }

  void _clearDigits() {
    if (_digits.isEmpty) {
      return;
    }

    setState(() {
      _digits = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 22 + bottomInset),
      decoration: const BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: _textSecondary.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(100),
              ),
            ),

            const SizedBox(height: 18),

            const Text(
              'JR CALL Keypad',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'In-call keypad',
              style: TextStyle(
                color: _textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 18),

            Container(
              width: double.infinity,
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _border),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x10087AF5),
                    blurRadius: 16,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _digits.isEmpty ? 'Enter digits' : _digits,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _digits.isEmpty ? _textSecondary : _primaryBlue,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: _digits.isEmpty ? 0 : 2,
                      ),
                    ),
                  ),

                  if (_digits.isNotEmpty)
                    IconButton(
                      tooltip: 'Delete digit',
                      onPressed: _removeDigit,
                      icon: const Icon(
                        Icons.backspace_outlined,
                        color: _danger,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            for (
              int rowIndex = 0;
              rowIndex < _rows.length;
              rowIndex++
            ) ...<Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _rows[rowIndex]
                    .map(
                      (String digit) => _KeypadButton(
                        label: digit,
                        onTap: () {
                          _appendDigit(digit);
                        },
                      ),
                    )
                    .toList(growable: false),
              ),

              if (rowIndex < _rows.length - 1) const SizedBox(height: 12),
            ],

            const SizedBox(height: 18),

            if (_digits.isNotEmpty)
              TextButton.icon(
                onPressed: _clearDigits,
                icon: const Icon(Icons.clear_all_rounded, color: _danger),
                label: const Text(
                  'Clear',
                  style: TextStyle(color: _danger, fontWeight: FontWeight.w700),
                ),
              ),

            const SizedBox(height: 4),

            Container(
              height: 4,
              width: 92,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[_callGreen, _primaryBlue],
                ),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================
// Keypad digit button
// ===========================================================

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _textPrimary = Color(0xFF101828);
  static const Color _border = Color(0xFFDCE7F5);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Key $label',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _surface,
              shape: BoxShape.circle,
              border: Border.all(color: _border),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x11087AF5),
                  blurRadius: 14,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 23,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
