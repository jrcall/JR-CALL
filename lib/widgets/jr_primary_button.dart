import 'package:flutter/material.dart';

import '../core/theme/jr_colors.dart';
import '../core/theme/jr_radius.dart';
import '../core/theme/jr_typography.dart';

/// ===============================================================
/// JR CALL — Premium Primary Button
/// File: jr_primary_button.dart
/// Location: lib/widgets/jr_primary_button.dart
///
/// PURPOSE:
/// JR CALL-এর সব primary CTA button-এর shared production UI.
///
/// Used for:
/// - LOGIN
/// - CONTINUE
/// - CREATE ACCOUNT
/// - VERIFY OTP
/// - SAVE
///
/// No Auth/Firebase/Call business logic belongs here.
/// ===============================================================
class JrPrimaryButton extends StatelessWidget {
  const JrPrimaryButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.isLoading = false,
    this.isEnabled = true,
    this.icon,
    this.width = double.infinity,
    this.height = 58,
    this.backgroundColor,
    this.foregroundColor = Colors.white,
    this.loadingSize = 22,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  }) : assert(height > 0),
       assert(loadingSize > 0);

  /// Button text.
  final String label;

  /// Button callback.
  ///
  /// Ignored automatically while loading or disabled.
  final VoidCallback? onPressed;

  /// Shows loading indicator and blocks duplicate taps.
  final bool isLoading;

  /// Controls enabled/disabled state.
  final bool isEnabled;

  /// Optional leading icon.
  final IconData? icon;

  /// Button width.
  final double width;

  /// Button height.
  final double height;

  /// Optional background override.
  final Color? backgroundColor;

  /// Text/icon color.
  final Color foregroundColor;

  /// Loading spinner size.
  final double loadingSize;

  /// Internal horizontal padding.
  final EdgeInsetsGeometry padding;

  bool get _canPress => isEnabled && !isLoading && onPressed != null;

  @override
  Widget build(BuildContext context) {
    final Color baseColor = backgroundColor ?? JrColors.primaryBlue;

    final Color effectiveBackground = _canPress ? baseColor : JrColors.disabled;

    return Semantics(
      button: true,
      enabled: _canPress,
      label: label,
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(JrRadius.button),
            gradient: _canPress
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      baseColor.withValues(alpha: 0.92),
                      baseColor,
                    ],
                  )
                : null,
            color: _canPress ? null : effectiveBackground,
            boxShadow: _canPress
                ? <BoxShadow>[
                    BoxShadow(
                      color: baseColor.withValues(alpha: 0.22),
                      blurRadius: 18,
                      spreadRadius: 0,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.35),
                      blurRadius: 8,
                      spreadRadius: -4,
                      offset: const Offset(0, -2),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _canPress ? onPressed : null,
              borderRadius: BorderRadius.circular(JrRadius.button),
              splashColor: Colors.white.withValues(alpha: 0.12),
              highlightColor: Colors.white.withValues(alpha: 0.06),
              child: Padding(
                padding: padding,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: isLoading
                        ? SizedBox(
                            key: const ValueKey<String>('loading'),
                            width: loadingSize,
                            height: loadingSize,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                foregroundColor,
                              ),
                            ),
                          )
                        : Row(
                            key: const ValueKey<String>('content'),
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              if (icon != null) ...<Widget>[
                                Icon(icon, size: 21, color: foregroundColor),
                                const SizedBox(width: 10),
                              ],
                              Flexible(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: JrTypography.buttonLabel.copyWith(
                                    color: _canPress
                                        ? foregroundColor
                                        : foregroundColor.withValues(
                                            alpha: 0.72,
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
