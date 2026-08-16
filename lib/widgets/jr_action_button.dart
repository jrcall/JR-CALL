import 'dart:ui';

import 'package:flutter/material.dart';

/// ===========================================================
/// JR CALL
/// File: jr_action_button.dart
/// Location: lib/widgets/jr_action_button.dart
///
/// Description:
/// Production reusable premium JR CALL action button.
///
/// Design:
/// - Modern glassmorphism
/// - Soft neon glow
/// - Premium light UI
/// - Responsive layout
/// - Loading / disabled / selected states
///
/// Architecture:
/// - UI only
/// - No Firebase logic
/// - No navigation logic
/// - No CallService logic
/// - No business logic
/// ===========================================================

enum JRActionButtonStyle { glass, luminous, clean }

class JRActionButton extends StatefulWidget {
  const JRActionButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.subtitle,
    this.style = JRActionButtonStyle.glass,
    this.isLoading = false,
    this.isSelected = false,
    this.enabled = true,
    this.width,
    this.height = 82,
    this.iconSize = 27,
    this.borderRadius = 24,
    this.accentColor,
    this.trailing,
    this.padding,
    this.semanticLabel,
  });

  static const Color pageBackground = Color(0xFFF8FAFC);

  final String label;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onPressed;
  final JRActionButtonStyle style;
  final bool isLoading;
  final bool isSelected;
  final bool enabled;
  final double? width;
  final double height;
  final double iconSize;
  final double borderRadius;
  final Color? accentColor;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;
  final String? semanticLabel;

  @override
  State<JRActionButton> createState() => _JRActionButtonState();
}

class _JRActionButtonState extends State<JRActionButton> {
  bool _pressed = false;

  bool get _canPress =>
      widget.enabled && !widget.isLoading && widget.onPressed != null;

  Color get _accentColor => widget.accentColor ?? const Color(0xFF087AF5);

  void _updatePressed(bool value) {
    if (!_canPress || !mounted || _pressed == value) {
      return;
    }

    setState(() {
      _pressed = value;
    });
  }

  void _handleTap() {
    if (!_canPress) {
      return;
    }

    widget.onPressed?.call();
  }

  _JRButtonVisualStyle get _visualStyle {
    switch (widget.style) {
      case JRActionButtonStyle.glass:
        return _JRButtonVisualStyle(
          blurSigma: 22,
          surfaceColor: const Color(0xFFFFFFFF).withValues(alpha: 0.68),
          selectedSurfaceColor: _accentColor.withValues(alpha: 0.10),
          borderColor: const Color(0xFFFFFFFF).withValues(alpha: 0.92),
          selectedBorderColor: _accentColor.withValues(alpha: 0.42),
          titleColor: const Color(0xFF101828),
          subtitleColor: const Color(0xFF667085),
          iconSurfaceColor: _accentColor.withValues(alpha: 0.10),
          shadowOpacity: 0.08,
          glowOpacity: 0.10,
        );

      case JRActionButtonStyle.luminous:
        return _JRButtonVisualStyle(
          blurSigma: 28,
          surfaceColor: const Color(0xFFFDFEFF).withValues(alpha: 0.82),
          selectedSurfaceColor: _accentColor.withValues(alpha: 0.13),
          borderColor: _accentColor.withValues(alpha: 0.18),
          selectedBorderColor: _accentColor.withValues(alpha: 0.58),
          titleColor: const Color(0xFF0F172A),
          subtitleColor: const Color(0xFF64748B),
          iconSurfaceColor: _accentColor.withValues(alpha: 0.14),
          shadowOpacity: 0.12,
          glowOpacity: 0.20,
        );

      case JRActionButtonStyle.clean:
        return _JRButtonVisualStyle(
          blurSigma: 0,
          surfaceColor: const Color(0xFFFFFFFF),
          selectedSurfaceColor: _accentColor.withValues(alpha: 0.07),
          borderColor: const Color(0xFFE7ECF3),
          selectedBorderColor: _accentColor.withValues(alpha: 0.40),
          titleColor: const Color(0xFF111827),
          subtitleColor: const Color(0xFF6B7280),
          iconSurfaceColor: const Color(0xFFF2F4F7),
          shadowOpacity: 0.06,
          glowOpacity: 0,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final _JRButtonVisualStyle visualStyle = _visualStyle;

    final BorderRadius radius = BorderRadius.circular(widget.borderRadius);

    final Color surfaceColor = widget.isSelected
        ? visualStyle.selectedSurfaceColor
        : visualStyle.surfaceColor;

    final Color borderColor = widget.isSelected
        ? visualStyle.selectedBorderColor
        : visualStyle.borderColor;

    return Semantics(
      button: true,
      enabled: _canPress,
      selected: widget.isSelected,
      label: widget.semanticLabel ?? widget.label,
      child: AnimatedScale(
        scale: _pressed ? 0.975 : 1,
        duration: const Duration(milliseconds: 115),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: widget.enabled ? 1 : 0.48,
          duration: const Duration(milliseconds: 160),
          child: SizedBox(
            width: widget.width,
            height: widget.height,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (visualStyle.glowOpacity > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        margin: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: _accentColor.withValues(
                                alpha: visualStyle.glowOpacity,
                              ),
                              blurRadius: 30,
                              spreadRadius: 1,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ClipRRect(
                  borderRadius: radius,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: visualStyle.blurSigma,
                      sigmaY: visualStyle.blurSigma,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        color: surfaceColor,
                        borderRadius: radius,
                        border: Border.all(
                          color: borderColor,
                          width: widget.isSelected ? 1.5 : 1,
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: visualStyle.shadowOpacity,
                            ),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.82),
                            blurRadius: 8,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: radius,
                          onTap: _canPress ? _handleTap : null,
                          onTapDown: _canPress
                              ? (_) => _updatePressed(true)
                              : null,
                          onTapUp: _canPress
                              ? (_) => _updatePressed(false)
                              : null,
                          onTapCancel: _canPress
                              ? () => _updatePressed(false)
                              : null,
                          splashColor: _accentColor.withValues(alpha: 0.08),
                          highlightColor: _accentColor.withValues(alpha: 0.04),
                          child: Padding(
                            padding:
                                widget.padding ??
                                const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                            child: _buildContent(visualStyle),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.style != JRActionButtonStyle.clean)
                  Positioned(
                    left: 14,
                    right: 14,
                    top: 1,
                    child: IgnorePointer(
                      child: Container(
                        height: 1,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(100),
                          gradient: LinearGradient(
                            colors: <Color>[
                              Colors.transparent,
                              Colors.white.withValues(alpha: 0.95),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(_JRButtonVisualStyle visualStyle) {
    if (widget.isLoading) {
      return Center(
        child: SizedBox(
          width: 25,
          height: 25,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: _accentColor,
          ),
        ),
      );
    }

    return Row(
      children: <Widget>[
        if (widget.icon != null) ...<Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? _accentColor.withValues(alpha: 0.16)
                  : visualStyle.iconSurfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _accentColor.withValues(
                  alpha: widget.isSelected ? 0.28 : 0.10,
                ),
              ),
              boxShadow: widget.isSelected
                  ? <BoxShadow>[
                      BoxShadow(
                        color: _accentColor.withValues(alpha: 0.16),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: _accentColor,
            ),
          ),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: visualStyle.titleColor,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                ),
              ),
              if (widget.subtitle != null &&
                  widget.subtitle!.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  widget.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: visualStyle.subtitleColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        if (widget.trailing != null)
          widget.trailing!
        else
          Icon(
            Icons.chevron_right_rounded,
            color: visualStyle.subtitleColor.withValues(alpha: 0.72),
            size: 24,
          ),
      ],
    );
  }
}

class _JRButtonVisualStyle {
  const _JRButtonVisualStyle({
    required this.blurSigma,
    required this.surfaceColor,
    required this.selectedSurfaceColor,
    required this.borderColor,
    required this.selectedBorderColor,
    required this.titleColor,
    required this.subtitleColor,
    required this.iconSurfaceColor,
    required this.shadowOpacity,
    required this.glowOpacity,
  });

  final double blurSigma;
  final Color surfaceColor;
  final Color selectedSurfaceColor;
  final Color borderColor;
  final Color selectedBorderColor;
  final Color titleColor;
  final Color subtitleColor;
  final Color iconSurfaceColor;
  final double shadowOpacity;
  final double glowOpacity;
}
