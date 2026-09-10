import 'dart:async';

import 'package:flutter/material.dart';

import '../services/call/audio_manager.dart';
import '../services/call/video_manager.dart';

// ===========================================================
// JR CALL
// File: call_bottom_bar.dart
// Location: lib/widgets/call_bottom_bar.dart
//
// Description:
// Production-safe reusable JR CALL in-call control bar.
//
// Responsibilities:
// - Microphone mute / unmute
// - Speaker on / off
// - Camera on / off
// - Switch front / rear camera
// - In-call keypad
// - Optional dial-tone digit forwarding
// - End call
//
// Architecture:
// - Audio logic -> AudioManager
// - Video logic -> VideoManager
// - Call lifecycle -> parent screen / CallService
// - Dial-tone digit logic -> parent / WebRTC layer
// - This widget owns presentation state only
//
// Design:
// - JR CALL premium light UI
// - Modern glassmorphism
// - Soft blue/cyan CALL glow
// - Responsive small/large phone layout
// - No duplicate call-engine logic
//
// Important:
// - AudioManager is the audio source of truth.
// - VideoManager is the video source of truth.
// - This widget never creates duplicate audio/video state.
// - This widget never disposes shared call-engine managers.
// ===========================================================

class CallBottomBar extends StatefulWidget {
  const CallBottomBar({
    super.key,
    required this.onEndCall,
    this.showVideoControls = true,
    this.onKeypadDigit,
  });

  final FutureOr<void> Function() onEndCall;

  final bool showVideoControls;

  final ValueChanged<String>? onKeypadDigit;

  @override
  State<CallBottomBar> createState() => _CallBottomBarState();
}

class _CallBottomBarState extends State<CallBottomBar> {
  final AudioManager _audioManager = AudioManager.instance;
  final VideoManager _videoManager = VideoManager.instance;

  bool _muteLoading = false;
  bool _speakerLoading = false;
  bool _cameraLoading = false;
  bool _switchCameraLoading = false;
  bool _endCallLoading = false;

  // ===========================================================
  // Authoritative Manager State
  // ===========================================================

  bool get _isMuted => _audioManager.microphone.isMuted;

  bool get _isSpeakerEnabled =>
      _audioManager.speaker.speakerEnabled;

  bool get _isCameraEnabled => _videoManager.videoEnabled;

  // ===========================================================
  // Lifecycle
  // ===========================================================

  @override
  void initState() {
    super.initState();

    _audioManager.addListener(_handleAudioManagerChanged);
    _videoManager.addListener(_handleVideoManagerChanged);
  }

  @override
  void dispose() {
    _audioManager.removeListener(_handleAudioManagerChanged);
    _videoManager.removeListener(_handleVideoManagerChanged);

    super.dispose();
  }

  void _handleAudioManagerChanged() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  void _handleVideoManagerChanged() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  // ===========================================================
  // Microphone
  // ===========================================================

  Future<void> _toggleMute() async {
    if (_muteLoading || _endCallLoading) {
      return;
    }

    setState(() {
      _muteLoading = true;
    });

    try {
      await _audioManager.toggleMute();
    } catch (error, stackTrace) {
      _reportError(
        'Toggle microphone',
        error,
        stackTrace,
      );

      _showError(
        'Unable to change microphone state.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _muteLoading = false;
        });
      }
    }
  }

  // ===========================================================
  // Speaker
  // ===========================================================

  Future<void> _toggleSpeaker() async {
    if (_speakerLoading || _endCallLoading) {
      return;
    }

    setState(() {
      _speakerLoading = true;
    });

    try {
      await _audioManager.toggleSpeaker();
    } catch (error, stackTrace) {
      _reportError(
        'Toggle speaker',
        error,
        stackTrace,
      );

      _showError(
        'Unable to change speaker state.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _speakerLoading = false;
        });
      }
    }
  }

  // ===========================================================
  // Camera
  // ===========================================================

  Future<void> _toggleCamera() async {
    if (_cameraLoading ||
        _endCallLoading ||
        !widget.showVideoControls) {
      return;
    }

    setState(() {
      _cameraLoading = true;
    });

    try {
      await _videoManager.toggleVideo();
    } catch (error, stackTrace) {
      _reportError(
        'Toggle camera',
        error,
        stackTrace,
      );

      _showError(
        'Unable to change camera state.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _cameraLoading = false;
        });
      }
    }
  }

  // ===========================================================
  // Switch Camera
  // ===========================================================

  Future<void> _switchCamera() async {
    if (_switchCameraLoading ||
        _endCallLoading ||
        !_isCameraEnabled ||
        !widget.showVideoControls) {
      return;
    }

    setState(() {
      _switchCameraLoading = true;
    });

    try {
      await _videoManager.switchCamera();
    } catch (error, stackTrace) {
      _reportError(
        'Switch camera',
        error,
        stackTrace,
      );

      _showError(
        'Unable to switch camera.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _switchCameraLoading = false;
        });
      }
    }
  }

  // ===========================================================
  // End Call
  // ===========================================================

  Future<void> _endCall() async {
    if (_endCallLoading) {
      return;
    }

    setState(() {
      _endCallLoading = true;
    });

    try {
      await widget.onEndCall();
    } catch (error, stackTrace) {
      _reportError(
        'End call',
        error,
        stackTrace,
      );

      if (mounted) {
        setState(() {
          _endCallLoading = false;
        });
      }

      _showError(
        'Unable to end the call.',
      );
    }
  }

  // ===========================================================
  // Keypad
  // ===========================================================

  Future<void> _openKeypad() async {
    if (!mounted || _endCallLoading) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x66000000),
      builder: (BuildContext context) {
        return _CallKeypadSheet(
          onDigitPressed: widget.onKeypadDigit,
        );
      },
    );
  }

  // ===========================================================
  // Error
  // ===========================================================

  void _showError(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _reportError(
      String source,
      Object error,
      StackTrace stackTrace,
      ) {
    debugPrint(
      'JR CALL [CallBottomBar/$source] error: $error',
    );

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
      child: LayoutBuilder(
        builder: (
            BuildContext context,
            BoxConstraints constraints,
            ) {
          final int controlCount =
          widget.showVideoControls ? 6 : 4;

          final double horizontalPadding =
          constraints.maxWidth < 360 ? 6 : 10;

          final double usableWidth =
              constraints.maxWidth -
                  (horizontalPadding * 2);

          final double availablePerControl =
              usableWidth / controlCount;

          final double buttonSize =
          (availablePerControl - 7)
              .clamp(
            42.0,
            56.0,
          )
              .toDouble();

          final double iconSize =
          buttonSize < 48 ? 21 : 24;

          return Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 14,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xFFFDFEFF),
                  Color(0xFFF4F9FF),
                  Color(0xFFEEF8FF),
                ],
              ),
              borderRadius:
              const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: const Border(
                top: BorderSide(
                  color: Color(0xFFDCE7F5),
                ),
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x16087AF5),
                  blurRadius: 28,
                  offset: Offset(0, -8),
                ),
                BoxShadow(
                  color: Color(0x1000B8D9),
                  blurRadius: 20,
                  offset: Offset(0, -3),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment:
              MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                _CallControlButton(
                  tooltip:
                  _isMuted ? 'Unmute' : 'Mute',
                  icon: _isMuted
                      ? Icons.mic_off_rounded
                      : Icons.mic_rounded,
                  foregroundColor: _isMuted
                      ? const Color(0xFFE5484D)
                      : const Color(0xFF087AF5),
                  selected: _isMuted,
                  loading: _muteLoading,
                  size: buttonSize,
                  iconSize: iconSize,
                  onPressed: _toggleMute,
                ),
                _CallControlButton(
                  tooltip: _isSpeakerEnabled
                      ? 'Speaker off'
                      : 'Speaker on',
                  icon: _isSpeakerEnabled
                      ? Icons.volume_up_rounded
                      : Icons.hearing_rounded,
                  foregroundColor: _isSpeakerEnabled
                      ? const Color(0xFF00AFCB)
                      : const Color(0xFF1557D0),
                  selected: _isSpeakerEnabled,
                  loading: _speakerLoading,
                  size: buttonSize,
                  iconSize: iconSize,
                  onPressed: _toggleSpeaker,
                ),
                if (widget.showVideoControls)
                  ...<Widget>[
                    _CallControlButton(
                      tooltip: _isCameraEnabled
                          ? 'Camera off'
                          : 'Camera on',
                      icon: _isCameraEnabled
                          ? Icons.videocam_rounded
                          : Icons
                          .videocam_off_rounded,
                      foregroundColor:
                      _isCameraEnabled
                          ? const Color(
                        0xFF087AF5,
                      )
                          : const Color(
                        0xFFE5484D,
                      ),
                      selected:
                      !_isCameraEnabled,
                      loading:
                      _cameraLoading,
                      size: buttonSize,
                      iconSize: iconSize,
                      onPressed:
                      _toggleCamera,
                    ),
                    _CallControlButton(
                      tooltip:
                      'Switch camera',
                      icon: Icons
                          .flip_camera_android_rounded,
                      foregroundColor:
                      const Color(
                        0xFF087AF5,
                      ),
                      enabled:
                      _isCameraEnabled,
                      loading:
                      _switchCameraLoading,
                      size: buttonSize,
                      iconSize: iconSize,
                      onPressed:
                      _switchCamera,
                    ),
                  ],
                _CallControlButton(
                  tooltip: 'Keypad',
                  icon: Icons.dialpad_rounded,
                  foregroundColor:
                  const Color(
                    0xFF00AFCB,
                  ),
                  size: buttonSize,
                  iconSize: iconSize,
                  onPressed: _openKeypad,
                ),
                _CallControlButton(
                  tooltip: 'End call',
                  icon:
                  Icons.call_end_rounded,
                  foregroundColor:
                  Colors.white,
                  backgroundColor:
                  const Color(
                    0xFFFF4D5E,
                  ),
                  loading:
                  _endCallLoading,
                  size: buttonSize,
                  iconSize: iconSize,
                  onPressed: _endCall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ===========================================================
// Internal Call Control Button
// ===========================================================

class _CallControlButton extends StatelessWidget {
  const _CallControlButton({
    required this.tooltip,
    required this.icon,
    required this.foregroundColor,
    required this.size,
    required this.iconSize,
    required this.onPressed,
    this.backgroundColor,
    this.enabled = true,
    this.loading = false,
    this.selected = false,
  });

  final String tooltip;

  final IconData icon;

  final Color foregroundColor;

  final Color? backgroundColor;

  final double size;

  final double iconSize;

  final VoidCallback onPressed;

  final bool enabled;

  final bool loading;

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final Color effectiveBackground =
        backgroundColor ??
            (selected
                ? foregroundColor.withValues(
              alpha: 0.14,
            )
                : Colors.white.withValues(
              alpha: 0.88,
            ));

    final Color effectiveBorder =
    backgroundColor != null
        ? backgroundColor!.withValues(
      alpha: 0.90,
    )
        : selected
        ? foregroundColor.withValues(
      alpha: 0.30,
    )
        : const Color(0xFFDCE7F5);

    final List<BoxShadow> shadows =
    backgroundColor != null
        ? const <BoxShadow>[
      BoxShadow(
        color: Color(0x33FF4D5E),
        blurRadius: 14,
        offset: Offset(0, 5),
      ),
    ]
        : selected
        ? <BoxShadow>[
      BoxShadow(
        color:
        foregroundColor.withValues(
          alpha: 0.14,
        ),
        blurRadius: 14,
        offset:
        const Offset(0, 4),
      ),
    ]
        : const <BoxShadow>[
      BoxShadow(
        color: Color(0x12087AF5),
        blurRadius: 12,
        offset: Offset(0, 4),
      ),
    ];

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled && !loading,
        selected: selected,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder:
            const CircleBorder(),
            onTap: enabled && !loading
                ? onPressed
                : null,
            child: AnimatedContainer(
              duration:
              const Duration(
                milliseconds: 160,
              ),
              curve:
              Curves.easeOutCubic,
              width: size,
              height: size,
              alignment:
              Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled
                    ? effectiveBackground
                    : const Color(
                  0xFFF1F4F8,
                ),
                border: Border.all(
                  color: enabled
                      ? effectiveBorder
                      : const Color(
                    0xFFE4E9F0,
                  ),
                ),
                boxShadow:
                enabled ? shadows : null,
              ),
              child: loading
                  ? SizedBox(
                width:
                iconSize - 3,
                height:
                iconSize - 3,
                child:
                CircularProgressIndicator(
                  strokeWidth: 2,
                  color:
                  foregroundColor,
                ),
              )
                  : Icon(
                icon,
                size: iconSize,
                color: enabled
                    ? foregroundColor
                    : const Color(
                  0xFF98A2B3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================
// JR CALL In-Call Keypad
// ===========================================================

class _CallKeypadSheet extends StatefulWidget {
  const _CallKeypadSheet({
    this.onDigitPressed,
  });

  final ValueChanged<String>? onDigitPressed;

  @override
  State<_CallKeypadSheet> createState() =>
      _CallKeypadSheetState();
}

class _CallKeypadSheetState
    extends State<_CallKeypadSheet> {
  static const int _maxInputLength = 64;

  String _input = '';

  void _append(String value) {
    if (_input.length >= _maxInputLength) {
      return;
    }

    setState(() {
      _input += value;
    });

    try {
      widget.onDigitPressed?.call(
        value,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'JR CALL [CallBottomBar/Keypad digit] '
            'error: $error',
      );

      debugPrintStack(
        label:
        'JR CALL '
            '[CallBottomBar/Keypad digit]',
        stackTrace: stackTrace,
      );
    }
  }

  void _backspace() {
    if (_input.isEmpty) {
      return;
    }

    setState(() {
      _input = _input.substring(
        0,
        _input.length - 1,
      );
    });
  }

  void _clear() {
    if (_input.isEmpty) {
      return;
    }

    setState(() {
      _input = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset =
        MediaQuery.viewInsetsOf(
          context,
        ).bottom;

    return Container(
      decoration:
      const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFFFFFFF),
            Color(0xFFF7FAFF),
            Color(0xFFF0F8FF),
          ],
        ),
        borderRadius:
        BorderRadius.vertical(
          top: Radius.circular(30),
        ),
        border: Border(
          top: BorderSide(
            color: Color(0xFFDCE7F5),
          ),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x1A087AF5),
            blurRadius: 28,
            offset: Offset(0, -8),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        24 + bottomInset,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize:
          MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 42,
              height: 4,
              decoration:
              BoxDecoration(
                color: const Color(
                  0xFF98A2B3,
                ).withValues(
                  alpha: 0.40,
                ),
                borderRadius:
                BorderRadius.circular(
                  100,
                ),
              ),
            ),
            const SizedBox(
              height: 18,
            ),
            const Row(
              mainAxisAlignment:
              MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.dialpad_rounded,
                  color:
                  Color(0xFF087AF5),
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  'Keypad',
                  style: TextStyle(
                    color:
                    Color(0xFF101828),
                    fontSize: 17,
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 6,
            ),
            const Text(
              'JR CALL',
              style: TextStyle(
                color:
                Color(0xFF58677F),
                fontSize: 12,
                fontWeight:
                FontWeight.w600,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(
              height: 16,
            ),
            Container(
              constraints:
              const BoxConstraints(
                minHeight: 58,
              ),
              padding:
              const EdgeInsets.symmetric(
                horizontal: 12,
              ),
              decoration:
              BoxDecoration(
                color:
                Colors.white.withValues(
                  alpha: 0.82,
                ),
                borderRadius:
                BorderRadius.circular(
                  18,
                ),
                border: Border.all(
                  color:
                  const Color(
                    0xFFDCE7F5,
                  ),
                ),
                boxShadow:
                const <BoxShadow>[
                  BoxShadow(
                    color:
                    Color(0x0F087AF5),
                    blurRadius: 14,
                    offset:
                    Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _input.isEmpty
                          ? 'Enter digits'
                          : _input,
                      maxLines: 1,
                      overflow:
                      TextOverflow
                          .ellipsis,
                      textAlign:
                      TextAlign.center,
                      style: TextStyle(
                        color:
                        _input.isEmpty
                            ? const Color(
                          0xFF98A2B3,
                        )
                            : const Color(
                          0xFF087AF5,
                        ),
                        fontSize:
                        _input.isEmpty
                            ? 16
                            : 27,
                        fontWeight:
                        FontWeight
                            .w700,
                        letterSpacing:
                        _input.isEmpty
                            ? 0
                            : 2,
                      ),
                    ),
                  ),
                  if (_input.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear',
                      onPressed:
                      _clear,
                      icon:
                      const Icon(
                        Icons
                            .close_rounded,
                        color: Color(
                          0xFF58677F,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(
              height: 20,
            ),
            _buildRow(
              const <String>[
                '1',
                '2',
                '3',
              ],
            ),
            const SizedBox(
              height: 14,
            ),
            _buildRow(
              const <String>[
                '4',
                '5',
                '6',
              ],
            ),
            const SizedBox(
              height: 14,
            ),
            _buildRow(
              const <String>[
                '7',
                '8',
                '9',
              ],
            ),
            const SizedBox(
              height: 14,
            ),
            _buildRow(
              const <String>[
                '*',
                '0',
                '#',
              ],
            ),
            const SizedBox(
              height: 18,
            ),
            _KeypadIconButton(
              icon: Icons
                  .backspace_outlined,
              tooltip: 'Backspace',
              onPressed: _backspace,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(
      List<String> values,
      ) {
    return Row(
      mainAxisAlignment:
      MainAxisAlignment.spaceEvenly,
      children: values
          .map(
            (String value) =>
            _KeypadButton(
              label: value,
              onPressed: () {
                _append(value);
              },
            ),
      )
          .toList(
        growable: false,
      ),
    );
  }
}

// ===========================================================
// Keypad Digit Button
// ===========================================================

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({
    required this.label,
    required this.onPressed,
  });

  final String label;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Key $label',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder:
          const CircleBorder(),
          onTap: onPressed,
          child: Container(
            width: 64,
            height: 64,
            alignment:
            Alignment.center,
            decoration:
            BoxDecoration(
              shape: BoxShape.circle,
              gradient:
              const LinearGradient(
                begin:
                Alignment.topLeft,
                end: Alignment
                    .bottomRight,
                colors: <Color>[
                  Color(0xFFFFFFFF),
                  Color(0xFFF2F8FF),
                ],
              ),
              border: Border.all(
                color: const Color(
                  0xFFDCE7F5,
                ),
              ),
              boxShadow:
              const <BoxShadow>[
                BoxShadow(
                  color:
                  Color(0x12087AF5),
                  blurRadius: 14,
                  offset:
                  Offset(0, 5),
                ),
              ],
            ),
            child: Text(
              label,
              style:
              const TextStyle(
                color:
                Color(0xFF101828),
                fontSize: 23,
                fontWeight:
                FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================
// Keypad Backspace Button
// ===========================================================

class _KeypadIconButton
    extends StatelessWidget {
  const _KeypadIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;

  final String tooltip;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          borderRadius:
          BorderRadius.circular(
            28,
          ),
          child: InkWell(
            borderRadius:
            BorderRadius.circular(
              28,
            ),
            onTap: onPressed,
            child: Container(
              width: 78,
              height: 52,
              alignment:
              Alignment.center,
              decoration:
              BoxDecoration(
                borderRadius:
                BorderRadius.circular(
                  26,
                ),
                color: const Color(
                  0xFFFFF1F2,
                ),
                border: Border.all(
                  color: const Color(
                    0xFFFFD4D8,
                  ),
                ),
                boxShadow:
                const <BoxShadow>[
                  BoxShadow(
                    color:
                    Color(0x14FF4D5E),
                    blurRadius: 12,
                    offset:
                    Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                icon,
                color: const Color(
                  0xFFFF4D5E,
                ),
                size: 23,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
