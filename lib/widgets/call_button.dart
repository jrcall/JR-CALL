import 'dart:async';

import 'package:flutter/material.dart';

/// ===========================================================
/// JR CALL
/// File: call_button.dart
/// Location: lib/widgets/call_button.dart
///
/// Description:
/// Production-ready reusable JR CALL voice-call action button.
///
/// Responsibilities:
/// - Render voice-call action control.
/// - Preserve parent supplied callback.
/// - Prevent accidental rapid repeated taps.
/// - Support enabled / disabled state.
/// - Provide premium JR CALL visual feedback.
/// - Provide accessibility semantics.
///
/// Architecture:
/// - UI only.
/// - No Firebase logic.
/// - No navigation logic.
/// - No CallService logic.
/// - No WebRTC logic.
/// - No AudioManager logic.
/// - No call-lifecycle ownership.
///
/// This widget is the voice-call counterpart of VideoButton.
///
/// Parent/provider/screen owns the actual call action.
/// CallButton only renders and forwards the user action.
/// ===========================================================

class CallButton extends StatefulWidget {
  const CallButton({
    super.key,
    required this.onPressed,
    this.size = 64,
    this.backgroundColor = const Color(0xFF12B76A),
    this.iconColor = Colors.white,
    this.icon = Icons.call_rounded,
    this.enabled = true,
    this.tooltip,
  }) : assert(
  size > 0,
  'CallButton size must be greater than zero.',
  );

  /// Parent supplied voice-call action.
  final VoidCallback? onPressed;

  /// Circular button diameter.
  final double size;

  /// Main active call accent.
  final Color backgroundColor;

  /// Icon foreground color.
  final Color iconColor;

  /// Display icon.
  final IconData icon;

  /// Whether interaction is enabled.
  final bool enabled;

  /// Optional tooltip / accessibility description.
  final String? tooltip;

  @override
  State<CallButton> createState() => _CallButtonState();
}

class _CallButtonState extends State<CallButton> {
  static const double _fallbackSize = 64;

  static const Duration _pressAnimationDuration =
  Duration(milliseconds: 110);

  static const Duration _containerAnimationDuration =
  Duration(milliseconds: 180);

  static const Duration _tapLockDuration =
  Duration(milliseconds: 350);

  bool _isPressed = false;
  bool _tapLocked = false;

  Timer? _unlockTimer;

  // ===========================================================
  // Derived State
  // ===========================================================

  bool get _isInteractive {
    return widget.enabled && widget.onPressed != null;
  }

  double get _effectiveSize {
    final double value = widget.size;

    if (!value.isFinite || value <= 0) {
      return _fallbackSize;
    }

    return value;
  }

  String get _semanticLabel {
    final String? value = widget.tooltip?.trim();

    if (value != null && value.isNotEmpty) {
      return value;
    }

    return 'Voice call';
  }

  // ===========================================================
  // Widget Updates
  // ===========================================================

  @override
  void didUpdateWidget(covariant CallButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    final bool wasInteractive =
        oldWidget.enabled && oldWidget.onPressed != null;

    if (wasInteractive && !_isInteractive) {
      _resetTransientInteractionState();
    }
  }

  void _resetTransientInteractionState() {
    _unlockTimer?.cancel();
    _unlockTimer = null;

    _tapLocked = false;
    _isPressed = false;
  }

  // ===========================================================
  // Press State
  // ===========================================================

  void _setPressed(bool value) {
    if (!mounted) {
      return;
    }

    if (value && !_isInteractive) {
      return;
    }

    if (_isPressed == value) {
      return;
    }

    setState(() {
      _isPressed = value;
    });
  }

  // ===========================================================
  // Tap Handling
  // ===========================================================

  void _handleTap() {
    if (!_isInteractive || _tapLocked) {
      return;
    }

    final VoidCallback? callback = widget.onPressed;

    if (callback == null) {
      return;
    }

    _tapLocked = true;

    try {
      callback();
    } finally {
      _unlockTimer?.cancel();

      _unlockTimer = Timer(
        _tapLockDuration,
            () {
          _tapLocked = false;
          _unlockTimer = null;
        },
      );
    }
  }

  // ===========================================================
  // Build
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    final double size = _effectiveSize;

    final Color activeColor = widget.backgroundColor;

    final Color effectiveBackground = _isInteractive
        ? activeColor
        : const Color(0xFFE8EDF5);

    final Color effectiveIconColor = _isInteractive
        ? widget.iconColor
        : const Color(0xFF98A2B3);

    final double scale =
    _isPressed && _isInteractive ? 0.94 : 1.0;

    final Widget button = Semantics(
      button: true,
      enabled: _isInteractive,
      label: _semanticLabel,
      child: AnimatedScale(
        scale: scale,
        duration: _pressAnimationDuration,
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: _containerAnimationDuration,
          curve: Curves.easeOutCubic,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: _isInteractive
                ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                activeColor.withValues(alpha: 0.96),
                const Color(0xFF00AFCB),
              ],
            )
                : null,
            color: _isInteractive ? null : effectiveBackground,
            border: Border.all(
              color: _isInteractive
                  ? Colors.white.withValues(alpha: 0.82)
                  : const Color(0xFFDDE3EC),
              width: 1,
            ),
            boxShadow: _isInteractive
                ? <BoxShadow>[
              BoxShadow(
                color: activeColor.withValues(alpha: 0.26),
                blurRadius: 22,
                spreadRadius: 1,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: const Color(
                  0xFF22D3EE,
                ).withValues(alpha: 0.12),
                blurRadius: 28,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ]
                : <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _isInteractive ? _handleTap : null,
              onTapDown: _isInteractive
                  ? (_) {
                _setPressed(true);
              }
                  : null,
              onTapUp: _isInteractive
                  ? (_) {
                _setPressed(false);
              }
                  : null,
              onTapCancel: _isInteractive
                  ? () {
                _setPressed(false);
              }
                  : null,
              splashColor:
              widget.iconColor.withValues(alpha: 0.14),
              highlightColor:
              widget.iconColor.withValues(alpha: 0.06),
              hoverColor:
              widget.iconColor.withValues(alpha: 0.05),
              focusColor:
              widget.iconColor.withValues(alpha: 0.07),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (_isInteractive)
                    Align(
                      alignment: const Alignment(-0.35, -0.55),
                      child: Container(
                        width: size * 0.54,
                        height: size * 0.26,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(size),
                          gradient: LinearGradient(
                            colors: <Color>[
                              Colors.white.withValues(alpha: 0.28),
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Center(
                    child: Icon(
                      widget.icon,
                      color: effectiveIconColor,
                      size: size * 0.44,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final String? tooltipValue = widget.tooltip?.trim();

    if (tooltipValue == null || tooltipValue.isEmpty) {
      return button;
    }

    return Tooltip(
      message: tooltipValue,
      child: button,
    );
  }

  // ===========================================================
  // Dispose
  // ===========================================================

  @override
  void dispose() {
    _unlockTimer?.cancel();
    _unlockTimer = null;

    super.dispose();
  }
}