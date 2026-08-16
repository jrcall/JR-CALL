import 'dart:async';

import 'package:flutter/material.dart';

/// ===========================================================
/// JR CALL
/// File: video_button.dart
/// Location: lib/widgets/video_button.dart
///
/// Description:
/// Production-ready reusable JR CALL video action button.
///
/// Responsibilities:
/// - Render video action control
/// - Preserve parent supplied callback
/// - Prevent accidental rapid repeated taps
/// - Support enabled / disabled state
/// - Provide premium JR CALL visual feedback
/// - Provide accessibility semantics
///
/// Architecture:
/// - UI only
/// - No Firebase logic
/// - No navigation logic
/// - No CallService logic
/// - No WebRTC logic
/// - No VideoManager logic
///
/// Existing public API preserved.
///
/// Used by:
/// - contacts_screen.dart
/// - outgoing_call_screen.dart
/// - voice_call_screen.dart
/// - video_call_screen.dart
/// ===========================================================

class VideoButton extends StatefulWidget {
  const VideoButton({
    super.key,
    required this.onPressed,
    this.size = 64,
    this.backgroundColor = const Color(0xFF087AF5),
    this.iconColor = Colors.white,
    this.icon = Icons.videocam_rounded,
    this.enabled = true,
    this.tooltip,
  }) : assert(size > 0, 'VideoButton size must be greater than zero.');

  /// Parent supplied video action.
  final VoidCallback? onPressed;

  /// Circular button diameter.
  final double size;

  /// Main active accent.
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
  State<VideoButton> createState() => _VideoButtonState();
}

class _VideoButtonState extends State<VideoButton> {
  bool _isPressed = false;
  bool _tapLocked = false;

  Timer? _unlockTimer;

  bool get _isInteractive {
    return widget.enabled && widget.onPressed != null;
  }

  String get _semanticLabel {
    final String? value = widget.tooltip?.trim();

    if (value != null && value.isNotEmpty) {
      return value;
    }

    return 'Video call';
  }

  void _setPressed(bool value) {
    if (!_isInteractive || !mounted) {
      return;
    }

    if (_isPressed == value) {
      return;
    }

    setState(() {
      _isPressed = value;
    });
  }

  void _handleTap() {
    if (!_isInteractive || _tapLocked) {
      return;
    }

    _tapLocked = true;

    try {
      widget.onPressed?.call();
    } finally {
      _unlockTimer?.cancel();

      _unlockTimer = Timer(const Duration(milliseconds: 350), () {
        _tapLocked = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color activeColor = widget.backgroundColor;

    final Color effectiveBackground = _isInteractive
        ? activeColor
        : const Color(0xFFE8EDF5);

    final Color effectiveIconColor = _isInteractive
        ? widget.iconColor
        : const Color(0xFF98A2B3);

    final double scale = _isPressed && _isInteractive ? 0.94 : 1.0;

    final Widget button = Semantics(
      button: true,
      enabled: _isInteractive,
      label: _semanticLabel,
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: _isInteractive
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      activeColor.withValues(alpha: 0.96),
                      const Color(0xFF1557D9),
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
                      color: const Color(0xFF22D3EE).withValues(alpha: 0.12),
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
              splashColor: widget.iconColor.withValues(alpha: 0.14),
              highlightColor: widget.iconColor.withValues(alpha: 0.06),
              hoverColor: widget.iconColor.withValues(alpha: 0.05),
              focusColor: widget.iconColor.withValues(alpha: 0.07),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (_isInteractive)
                    Align(
                      alignment: const Alignment(-0.35, -0.55),
                      child: Container(
                        width: widget.size * 0.54,
                        height: widget.size * 0.26,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(widget.size),
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
                      size: widget.size * 0.44,
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

    return Tooltip(message: tooltipValue, child: button);
  }

  @override
  void dispose() {
    _unlockTimer?.cancel();
    _unlockTimer = null;

    super.dispose();
  }
}
