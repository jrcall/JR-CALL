import 'package:flutter/material.dart';

import 'jr_colors.dart';

/// ===============================================================
/// JR CALL — Global Typography System
/// File: jr_typography.dart
/// Location: lib/core/theme/jr_typography.dart
///
/// DESIGN:
/// Premium Light UI
/// Modern Glassmorphism
/// Soft Neon Gradient
///
/// PURPOSE:
/// Entire JR CALL application typography-এর single source of truth.
/// ===============================================================
abstract final class JrTypography {
  JrTypography._();

  // =============================================================
  // FONT FAMILY
  // =============================================================

  /// Native system font keeps Android, iOS, Web and Desktop stable
  /// without requiring an additional font package.
  static const String? fontFamily = null;

  // =============================================================
  // BRAND / HERO
  // =============================================================

  static const TextStyle brandLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 38,
    height: 1.08,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.2,
    color: JrColors.textPrimary,
  );

  static const TextStyle brandTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 30,
    height: 1.10,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
    color: JrColors.textPrimary,
  );

  static const TextStyle brandAccent = TextStyle(
    fontFamily: fontFamily,
    fontSize: 30,
    height: 1.10,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
    color: JrColors.primaryBlue,
  );

  // =============================================================
  // SCREEN TITLES
  // =============================================================

  static const TextStyle screenTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    height: 1.15,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    color: JrColors.textPrimary,
  );

  static const TextStyle screenSubtitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: JrColors.textSecondary,
  );

  // =============================================================
  // SECTION TITLES
  // =============================================================

  static const TextStyle sectionTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    height: 1.25,
    fontWeight: FontWeight.w700,
    color: JrColors.textPrimary,
  );

  static const TextStyle sectionSubtitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 1.40,
    fontWeight: FontWeight.w400,
    color: JrColors.textSecondary,
  );

  // =============================================================
  // BODY
  // =============================================================

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: JrColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: JrColors.textPrimary,
  );

  static const TextStyle bodySecondary = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: JrColors.textSecondary,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 1.40,
    fontWeight: FontWeight.w400,
    color: JrColors.textSecondary,
  );

  // =============================================================
  // INPUTS
  // =============================================================

  static const TextStyle inputLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 1.20,
    fontWeight: FontWeight.w600,
    color: JrColors.textSecondary,
  );

  static const TextStyle inputText = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    height: 1.30,
    fontWeight: FontWeight.w500,
    color: JrColors.textPrimary,
  );

  static const TextStyle inputHint = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    height: 1.30,
    fontWeight: FontWeight.w400,
    color: JrColors.textSecondary,
  );

  static const TextStyle inputError = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 1.30,
    fontWeight: FontWeight.w500,
    color: JrColors.error,
  );

  // =============================================================
  // BUTTONS
  // =============================================================

  static const TextStyle buttonLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    height: 1.20,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
    color: Colors.white,
  );

  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 1.20,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.1,
    color: Colors.white,
  );

  /// Primary ThemeData / button API.
  ///
  /// `jr_theme.dart` already expects:
  /// JrTypography.buttonLabel
  ///
  /// Keep this public API permanently for compatibility.
  static const TextStyle buttonLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 1.20,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.1,
    color: Colors.white,
  );

  static const TextStyle secondaryButton = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 1.20,
    fontWeight: FontWeight.w700,
    color: JrColors.primaryBlue,
  );

  // =============================================================
  // LINKS / ACTIONS
  // =============================================================

  static const TextStyle link = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 1.30,
    fontWeight: FontWeight.w700,
    color: JrColors.primaryBlue,
  );

  static const TextStyle linkLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 1.30,
    fontWeight: FontWeight.w700,
    color: JrColors.primaryBlue,
  );

  // =============================================================
  // HEADER
  // =============================================================

  static const TextStyle headerBrand = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    height: 1.10,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
    color: JrColors.textPrimary,
  );

  static const TextStyle headerSubtitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 1.30,
    fontWeight: FontWeight.w500,
    color: JrColors.textSecondary,
  );

  // =============================================================
  // PROFILE
  // =============================================================

  static const TextStyle profileName = TextStyle(
    fontFamily: fontFamily,
    fontSize: 25,
    height: 1.15,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
    color: JrColors.textPrimary,
  );

  static const TextStyle profileUsername = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 1.30,
    fontWeight: FontWeight.w500,
    color: JrColors.textSecondary,
  );

  static const TextStyle profileStatValue = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    height: 1.20,
    fontWeight: FontWeight.w800,
    color: JrColors.textPrimary,
  );

  static const TextStyle profileStatLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    height: 1.30,
    fontWeight: FontWeight.w500,
    color: JrColors.textSecondary,
  );

  // =============================================================
  // LIST / FEED / CALL HISTORY
  // =============================================================

  static const TextStyle listTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    height: 1.25,
    fontWeight: FontWeight.w700,
    color: JrColors.textPrimary,
  );

  static const TextStyle listSubtitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 1.35,
    fontWeight: FontWeight.w400,
    color: JrColors.textSecondary,
  );

  static const TextStyle metadata = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 1.30,
    fontWeight: FontWeight.w500,
    color: JrColors.textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    height: 1.30,
    fontWeight: FontWeight.w500,
    color: JrColors.textSecondary,
  );

  // =============================================================
  // NAVIGATION
  // =============================================================

  static const TextStyle navigationLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    height: 1.20,
    fontWeight: FontWeight.w600,
    color: JrColors.textSecondary,
  );

  static const TextStyle navigationLabelSelected = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    height: 1.20,
    fontWeight: FontWeight.w700,
    color: JrColors.primaryBlue,
  );

  // =============================================================
  // OTP
  // =============================================================

  static const TextStyle otpDigit = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    height: 1.10,
    fontWeight: FontWeight.w700,
    color: JrColors.textPrimary,
  );

  // =============================================================
  // STATUS
  // =============================================================

  static const TextStyle success = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 1.30,
    fontWeight: FontWeight.w600,
    color: JrColors.success,
  );

  static const TextStyle warning = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 1.30,
    fontWeight: FontWeight.w600,
    color: JrColors.warning,
  );

  static const TextStyle error = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 1.30,
    fontWeight: FontWeight.w600,
    color: JrColors.error,
  );

  // =============================================================
  // HELPERS
  // =============================================================

  static TextStyle withColor(TextStyle base, Color color) {
    return base.copyWith(color: color);
  }

  static TextStyle withWeight(TextStyle base, FontWeight weight) {
    return base.copyWith(fontWeight: weight);
  }

  static TextStyle withSize(TextStyle base, double size) {
    assert(size > 0, 'Font size must be greater than zero.');
    return base.copyWith(fontSize: size);
  }
}
