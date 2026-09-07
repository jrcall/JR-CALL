import 'dart:async';

import 'package:flutter/material.dart';

/// ===============================================================
/// JR CALL
/// File: call_actions_screen.dart
/// Location: lib/screens/call_actions_screen.dart
///
/// Description:
/// Production-safe presentation surface for call-related actions.
///
/// Responsibilities:
/// - Provide the JR CALL dial pad.
/// - Accept dial input.
/// - Support 0-9, *, and #.
/// - Support leading + through long-press 0.
/// - Support delete and clear.
/// - Forward voice-call action to the parent.
/// - Forward video-call action to the parent.
/// - Prevent rapid duplicate/contradictory UI actions.
///
/// Architecture:
/// - Presentation/input only.
/// - No Firebase ownership.
/// - No discovery ownership.
/// - No CallService ownership.
/// - No signaling ownership.
/// - No WebRTC ownership.
/// - No ICE ownership.
/// - No recovery ownership.
/// - No call-history ownership.
/// - No navigation ownership.
///
/// Parent/provider owns actual call resolution and lifecycle.
/// ===============================================================

class CallActionsScreen extends StatefulWidget {
  const CallActionsScreen({
    super.key,
    this.initialNumber = '',
    this.onVoiceCall,
    this.onVideoCall,
  });

  final String initialNumber;

  final ValueChanged<String>? onVoiceCall;

  final ValueChanged<String>? onVideoCall;

  @override
  State<CallActionsScreen> createState() => _CallActionsScreenState();
}

class _CallActionsScreenState extends State<CallActionsScreen> {
  static const int _maximumInputLength = 32;

  static const Duration _callActionLockDuration = Duration(
    milliseconds: 650,
  );

  late String _number;

  bool _callActionLocked = false;

  Timer? _callActionUnlockTimer;

  // =============================================================
  // Lifecycle
  // =============================================================

  @override
  void initState() {
    super.initState();

    _number = _sanitizeInitialNumber(
      widget.initialNumber,
    );
  }

  @override
  void didUpdateWidget(
      covariant CallActionsScreen oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.initialNumber == widget.initialNumber) {
      return;
    }

    _number = _sanitizeInitialNumber(
      widget.initialNumber,
    );
  }

  // =============================================================
  // Number Input
  // =============================================================

  void _append(String value) {
    if (_number.length >= _maximumInputLength) {
      return;
    }

    if (value == '+') {
      if (_number.isNotEmpty) {
        return;
      }
    } else if (!_isDialCharacter(value)) {
      return;
    }

    setState(() {
      _number += value;
    });
  }

  /// Long-press zero produces the international prefix marker.
  ///
  /// The marker is allowed only at the beginning.
  /// It is never inserted into the middle or end of a number.
  void _replaceZeroWithPlus() {
    if (_number.isEmpty) {
      _append('+');
      return;
    }

    if (_number.startsWith('+')) {
      return;
    }

    if (!_number.startsWith('0')) {
      return;
    }

    setState(() {
      _number = '+${_number.substring(1)}';
    });
  }

  void _deleteLast() {
    if (_number.isEmpty) {
      return;
    }

    setState(() {
      _number = _number.substring(
        0,
        _number.length - 1,
      );
    });
  }

  void _clearNumber() {
    if (_number.isEmpty) {
      return;
    }

    setState(() {
      _number = '';
    });
  }

  bool _isDialCharacter(String value) {
    if (value.length != 1) {
      return false;
    }

    final int codeUnit = value.codeUnitAt(0);

    final bool isDigit =
        codeUnit >= 48 &&
            codeUnit <= 57;

    return isDigit ||
        value == '*' ||
        value == '#';
  }

  String _sanitizeInitialNumber(String value) {
    final StringBuffer buffer = StringBuffer();

    for (final int codePoint in value.trim().runes) {
      if (buffer.length >= _maximumInputLength) {
        break;
      }

      final String character = String.fromCharCode(
        codePoint,
      );

      if (character == '+') {
        if (buffer.isEmpty) {
          buffer.write(character);
        }

        continue;
      }

      if (_isDialCharacter(character)) {
        buffer.write(character);
      }
    }

    return buffer.toString();
  }

  // =============================================================
  // Call Actions
  // =============================================================

  void _startVoiceCall() {
    _runCallAction(
      widget.onVoiceCall,
      actionName: 'Voice call',
    );
  }

  void _startVideoCall() {
    _runCallAction(
      widget.onVideoCall,
      actionName: 'Video call',
    );
  }

  void _runCallAction(
      ValueChanged<String>? callback, {
        required String actionName,
      }) {
    final String number = _number.trim();

    if (number.isEmpty) {
      _showNumberRequiredMessage();
      return;
    }

    if (callback == null) {
      _showCallIntegrationMessage();
      return;
    }

    if (_callActionLocked) {
      return;
    }

    setState(() {
      _callActionLocked = true;
    });

    try {
      callback(number);
    } catch (error, stackTrace) {
      _reportError(
        actionName,
        error,
        stackTrace,
      );

      _releaseCallActionLock();

      _showCallActionFailedMessage();

      return;
    }

    if (!mounted) {
      return;
    }

    _callActionUnlockTimer?.cancel();

    _callActionUnlockTimer = Timer(
      _callActionLockDuration,
      _releaseCallActionLock,
    );
  }

  void _releaseCallActionLock() {
    _callActionUnlockTimer?.cancel();
    _callActionUnlockTimer = null;

    if (!_callActionLocked) {
      return;
    }

    if (!mounted) {
      _callActionLocked = false;
      return;
    }

    setState(() {
      _callActionLocked = false;
    });
  }

  // =============================================================
  // User Messages
  // =============================================================

  void _showNumberRequiredMessage() {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a phone number first.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _showCallIntegrationMessage() {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Call action is not connected yet.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _showCallActionFailedMessage() {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to start the call.',
          ),
          behavior: SnackBarBehavior.floating,
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
      'JR CALL [CallActionsScreen/$source] error: $error',
    );

    debugPrintStack(
      label: 'JR CALL [CallActionsScreen/$source]',
      stackTrace: stackTrace,
    );
  }

  // =============================================================
  // UI
  // =============================================================

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final bool hasNumber = _number.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(0xFFFAFAFA),
        foregroundColor: const Color(0xFF111111),
        centerTitle: true,
        title: const Text(
          'Dial Pad',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (
              BuildContext context,
              BoxConstraints constraints,
              ) {
            final double availableHeight =
                constraints.maxHeight;

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: availableHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    24,
                    18,
                    24,
                    24,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      _NumberDisplay(
                        number: _number,
                        onDelete: _deleteLast,
                        onClear: _clearNumber,
                      ),

                      const SizedBox(height: 30),

                      _DialPad(
                        onPressed: _append,
                        onZeroLongPressed:
                        _replaceZeroWithPlus,
                      ),

                      const SizedBox(height: 28),

                      _CallButtons(
                        voiceEnabled: hasNumber,
                        videoEnabled: hasNumber,
                        actionsLocked: _callActionLocked,
                        onVoiceCall: _startVoiceCall,
                        onVideoCall: _startVideoCall,
                      ),

                      const SizedBox(height: 12),

                      Text(
                        'JR CALL',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: const Color(0xFF9A9A9A),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // =============================================================
  // Dispose
  // =============================================================

  @override
  void dispose() {
    _callActionUnlockTimer?.cancel();
    _callActionUnlockTimer = null;

    super.dispose();
  }
}

/// ===============================================================
/// Number Display
/// ===============================================================

class _NumberDisplay extends StatelessWidget {
  const _NumberDisplay({
    required this.number,
    required this.onDelete,
    required this.onClear,
  });

  final String number;

  final VoidCallback onDelete;

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 48),

          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(
                milliseconds: 150,
              ),
              child: Text(
                number.isEmpty
                    ? 'Enter number'
                    : number,
                key: ValueKey<String>(number),
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize:
                  number.length > 18 ? 24 : 31,
                  height: 1,
                  fontWeight: FontWeight.w400,
                  color: number.isEmpty
                      ? const Color(0xFFB0B0B0)
                      : const Color(0xFF111111),
                ),
              ),
            ),
          ),

          SizedBox(
            width: 48,
            child: number.isEmpty
                ? const SizedBox.shrink()
                : GestureDetector(
              onLongPress: onClear,
              child: IconButton(
                tooltip: 'Delete',
                onPressed: onDelete,
                icon: const Icon(
                  Icons.backspace_outlined,
                  size: 25,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================================================
/// Dial Pad
/// ===============================================================

class _DialPad extends StatelessWidget {
  const _DialPad({
    required this.onPressed,
    required this.onZeroLongPressed,
  });

  final ValueChanged<String> onPressed;

  final VoidCallback onZeroLongPressed;

  static const List<_DialKeyData> _keys = <_DialKeyData>[
    _DialKeyData('1', ''),
    _DialKeyData('2', 'A' 'B' 'C'),
    _DialKeyData('3', 'D' 'E' 'F'),
    _DialKeyData('4', 'G' 'H' 'I'),
    _DialKeyData('5', 'J' 'K' 'L'),
    _DialKeyData('6', 'M' 'N' 'O'),
    _DialKeyData('7', 'P' 'Q' 'R' 'S'),
    _DialKeyData('8', 'T' 'U' 'V'),
    _DialKeyData('9', 'W' 'X' 'Y' 'Z'),
    _DialKeyData('*', ''),
    _DialKeyData('0', '+'),
    _DialKeyData('#', ''),
  ];

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: 330,
      ),
      child: GridView.builder(
        itemCount: _keys.length,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate:
        const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 15,
          crossAxisSpacing: 24,
          childAspectRatio: 1,
        ),
        itemBuilder: (
            BuildContext context,
            int index,
            ) {
          final _DialKeyData keyData =
          _keys[index];

          return _DialKey(
            data: keyData,
            onTap: () {
              onPressed(
                keyData.value,
              );
            },
            onLongPress: keyData.value == '0'
                ? onZeroLongPressed
                : null,
          );
        },
      ),
    );
  }
}

/// ===============================================================
/// Dial Key
/// ===============================================================

class _DialKey extends StatelessWidget {
  const _DialKey({
    required this.data,
    required this.onTap,
    this.onLongPress,
  });

  final _DialKeyData data;

  final VoidCallback onTap;

  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: data.subtitle.isEmpty
          ? 'Key ${data.value}'
          : 'Key ${data.value}, ${data.subtitle}',
      child: Material(
        color: const Color(0xFFF0F0F0),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          customBorder: const CircleBorder(),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  data.value,
                  style: const TextStyle(
                    color: Color(0xFF111111),
                    fontSize: 31,
                    height: 1,
                    fontWeight: FontWeight.w400,
                  ),
                ),

                if (data.subtitle.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    data.subtitle,
                    style: const TextStyle(
                      color: Color(0xFF555555),
                      fontSize: 10,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ===============================================================
/// Call Buttons
/// ===============================================================

class _CallButtons extends StatelessWidget {
  const _CallButtons({
    required this.voiceEnabled,
    required this.videoEnabled,
    required this.actionsLocked,
    required this.onVoiceCall,
    required this.onVideoCall,
  });

  final bool voiceEnabled;

  final bool videoEnabled;

  final bool actionsLocked;

  final VoidCallback onVoiceCall;

  final VoidCallback onVideoCall;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _CallActionButton(
          tooltip: 'Voice Call',
          icon: Icons.call_rounded,
          enabled: voiceEnabled,
          interactionLocked: actionsLocked,
          onPressed: onVoiceCall,
        ),

        const SizedBox(width: 28),

        _CallActionButton(
          tooltip: 'Video Call',
          icon: Icons.videocam_rounded,
          enabled: videoEnabled,
          interactionLocked: actionsLocked,
          onPressed: onVideoCall,
        ),
      ],
    );
  }
}

/// ===============================================================
/// Call Action Button
/// ===============================================================

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.interactionLocked,
    required this.onPressed,
  });

  final String tooltip;

  final IconData icon;

  final bool enabled;

  final bool interactionLocked;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bool interactive =
        enabled && !interactionLocked;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: interactive,
        label: tooltip,
        child: Material(
          color: enabled
              ? const Color(0xFF00C72C)
              : const Color(0xFFB8DDBF),
          shape: const CircleBorder(),
          elevation: enabled ? 3 : 0,
          child: InkWell(
            onTap: interactive
                ? onPressed
                : null,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 72,
              height: 72,
              child: Icon(
                icon,
                color: Colors.white,
                size: 34,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ===============================================================
/// Dial Key Data
/// ===============================================================

class _DialKeyData {
  const _DialKeyData(
      this.value,
      this.subtitle,
      );

  final String value;

  final String subtitle;
}