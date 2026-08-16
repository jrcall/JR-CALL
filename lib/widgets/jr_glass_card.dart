import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme/jr_colors.dart';

/// ===============================================================
/// JR CALL — Premium Glass Card
/// File: jr_glass_card.dart
/// Location: lib/widgets/jr_glass_card.dart
///
/// DESIGN:
/// Premium Light UI
/// Modern Glassmorphism
/// Soft Neon Gradient
///
/// PURPOSE:
/// JR CALL-এর card / panel / tile / section UI-এর জন্য
/// একটি reusable glassmorphism component.
///
/// This widget contains UI presentation only.
/// No authentication, Firebase, profile, discovery or Call Engine
/// business logic belongs in this file.
/// ===============================================================
class JrGlassCard extends StatelessWidget {
  const JrGlassCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.width,
    this.height,
    this.borderRadius = 24,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1,
    this.blur = 18,
    this.opacity = 0.76,
    this.shadowOpacity = 0.08,
    this.glowColor,
    this.glowOpacity = 0.12,
    this.glowBlur = 24,
    this.onTap,
    this.alignment,
    this.clipBehavior = Clip.antiAlias,
    this.enableGlassBlur = true,
  }) : assert(borderRadius >= 0),
       assert(borderWidth >= 0),
       assert(blur >= 0),
       assert(opacity >= 0 && opacity <= 1),
       assert(shadowOpacity >= 0 && shadowOpacity <= 1),
       assert(glowOpacity >= 0 && glowOpacity <= 1),
       assert(glowBlur >= 0);

  /// Card content.
  final Widget child;

  /// Inner spacing.
  final EdgeInsetsGeometry padding;

  /// Outer spacing.
  final EdgeInsetsGeometry? margin;

  /// Optional fixed width.
  final double? width;

  /// Optional fixed height.
  final double? height;

  /// Card corner radius.
  final double borderRadius;

  /// Optional glass surface override.
  ///
  /// When null, the JR CALL shared glass surface is used.
  final Color? backgroundColor;

  /// Optional border override.
  final Color? borderColor;

  /// Border thickness.
  final double borderWidth;

  /// Backdrop blur intensity.
  final double blur;

  /// Glass surface opacity.
  final double opacity;

  /// Main soft shadow opacity.
  final double shadowOpacity;

  /// Optional feature glow.
  ///
  /// Examples:
  /// Call        → green/cyan
  /// Message     → purple/pink
  /// PublicMedia → orange/amber
  /// Video Reels → cyan/blue
  /// AI Tools    → violet/magenta
  final Color? glowColor;

  /// Glow opacity.
  final double glowOpacity;

  /// Glow blur radius.
  final double glowBlur;

  /// Optional tap callback.
  final VoidCallback? onTap;

  /// Optional child alignment.
  final AlignmentGeometry? alignment;

  /// Clip behavior for rounded content.
  final Clip clipBehavior;

  /// Disable only where BackdropFilter is not desirable.
  final bool enableGlassBlur;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    final Color effectiveBackground = (backgroundColor ?? JrColors.surfaceGlass)
        .withValues(alpha: opacity);

    final Color effectiveBorder =
        borderColor ?? JrColors.border.withValues(alpha: 0.72);

    final List<BoxShadow> shadows = <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: shadowOpacity),
        blurRadius: 24,
        offset: const Offset(0, 10),
        spreadRadius: -8,
      ),
      BoxShadow(
        color: Colors.white.withValues(alpha: 0.72),
        blurRadius: 12,
        offset: const Offset(-3, -3),
        spreadRadius: -6,
      ),
      if (glowColor != null)
        BoxShadow(
          color: glowColor!.withValues(alpha: glowOpacity),
          blurRadius: glowBlur,
          spreadRadius: 0,
          offset: Offset.zero,
        ),
    ];

    Widget content = Container(
      width: width,
      height: height,
      alignment: alignment,
      padding: padding,
      decoration: BoxDecoration(
        color: effectiveBackground,
        borderRadius: radius,
        border: Border.all(color: effectiveBorder, width: borderWidth),
        boxShadow: shadows,
      ),
      child: child,
    );

    if (enableGlassBlur && blur > 0) {
      content = ClipRRect(
        borderRadius: radius,
        clipBehavior: clipBehavior,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: content,
        ),
      );
    } else {
      content = ClipRRect(
        borderRadius: radius,
        clipBehavior: clipBehavior,
        child: content,
      );
    }

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          splashColor: JrColors.primaryBlue.withValues(alpha: 0.06),
          highlightColor: JrColors.primaryBlue.withValues(alpha: 0.035),
          child: content,
        ),
      );
    }

    if (margin != null) {
      content = Padding(padding: margin!, child: content);
    }

    return content;
  }
}
