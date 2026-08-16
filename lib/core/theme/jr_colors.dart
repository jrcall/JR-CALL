import 'package:flutter/material.dart';

/// ===============================================================
/// JR CALL — Global Color System
/// File: jr_colors.dart
/// Location: lib/core/theme/jr_colors.dart
///
/// PURPOSE:
/// Single source of truth for all JR CALL application colors.
///
/// DESIGN:
/// Modern Glassmorphism + Soft Neon Gradient + Premium Light UI
///
/// IMPORTANT:
/// - Do not hard-code duplicate colors inside individual screens.
/// - All future JR CALL UI should use colors from this class.
/// - Feature colors are intentionally separated so Call, Message,
///   Public Media, Video Reels and AI Tools keep their own identity.
/// ===============================================================
abstract final class JrColors {
  // =============================================================
  // BRAND / PRIMARY
  // =============================================================

  /// Main JR CALL premium blue.
  static const Color primaryBlue = Color(0xFF2F6FEF);

  /// Lighter blue used for gradients, highlights and active states.
  static const Color secondaryBlue = Color(0xFF4B9CFF);

  /// Deeper blue for stronger emphasis when required.
  static const Color deepBlue = Color(0xFF1554D1);

  /// Very light blue tint used behind primary icons/cards.
  static const Color primaryBlueSoft = Color(0xFFEAF3FF);

  // =============================================================
  // APP BACKGROUND
  // =============================================================

  /// Main app background.
  ///
  /// Intentionally not pure white.
  /// Matches the soft cool-white / blue-grey reference design.
  static const Color background = Color(0xFFF6F8FD);

  /// Slightly brighter alternative background.
  static const Color backgroundLight = Color(0xFFFAFBFF);

  /// Standard solid card/sheet surface.
  static const Color surface = Color(0xFFFFFFFF);

  /// Secondary surface for input areas and soft cards.
  static const Color surfaceSoft = Color(0xFFF8FAFE);

  /// Glassmorphism surface with transparency.
  static const Color surfaceGlass = Color(0xD9FFFFFF);

  /// Softer transparent glass layer.
  static const Color surfaceGlassSoft = Color(0xBFFFFFFF);

  /// Stronger glass layer for important cards/dialogs.
  static const Color surfaceGlassStrong = Color(0xF2FFFFFF);

  // =============================================================
  // FEATURE IDENTITY COLORS
  // =============================================================

  /// CALL — green / cyan family.
  static const Color callGreen = Color(0xFF18D6A1);

  static const Color callCyan = Color(0xFF25D8E8);

  static const Color callSoft = Color(0xFFE9FFF8);

  /// MESSAGE — purple / pink family.
  static const Color messagePurple = Color(0xFFA855F7);

  static const Color messagePink = Color(0xFFE84DCE);

  static const Color messageSoft = Color(0xFFF8EEFF);

  /// PUBLIC MEDIA — orange / amber family.
  static const Color mediaOrange = Color(0xFFFF9838);

  static const Color mediaAmber = Color(0xFFFFB52E);

  static const Color mediaSoft = Color(0xFFFFF4E8);

  /// VIDEO REELS — cyan / blue family.
  static const Color reelsCyan = Color(0xFF21C7F3);

  static const Color reelsBlue = Color(0xFF2389FF);

  static const Color reelsSoft = Color(0xFFEAF9FF);

  /// AI TOOLS — violet / magenta family.
  static const Color aiPurple = Color(0xFF8457F5);

  static const Color aiMagenta = Color(0xFFD946EF);

  static const Color aiSoft = Color(0xFFF5EDFF);

  // =============================================================
  // TEXT
  // =============================================================

  /// Primary titles, names and important text.
  static const Color textPrimary = Color(0xFF111827);

  /// Normal secondary text.
  static const Color textSecondary = Color(0xFF667085);

  /// Less important metadata.
  static const Color textTertiary = Color(0xFF98A2B3);

  /// Placeholder / hint text.
  static const Color textHint = Color(0xFFA8B0BF);

  /// Text displayed on strong blue/dark surfaces.
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // =============================================================
  // ICONS
  // =============================================================

  static const Color iconPrimary = primaryBlue;

  static const Color iconSecondary = Color(0xFF66758A);

  static const Color iconMuted = Color(0xFF98A2B3);

  // =============================================================
  // INPUTS
  // =============================================================

  static const Color inputFill = Color(0xFFF9FAFD);

  static const Color inputFillFocused = Color(0xFFFFFFFF);

  static const Color inputBorder = Color(0xFFDDE4F0);

  static const Color inputBorderFocused = primaryBlue;

  static const Color inputBorderError = Color(0xFFFF4D67);

  // =============================================================
  // BORDER / DIVIDER
  // =============================================================

  /// General glass/card border.
  static const Color border = Color(0xFFDCE4F0);

  /// Softer border for subtle surfaces.
  static const Color borderSoft = Color(0xFFE9EEF6);

  /// Shared divider color.
  static const Color divider = Color(0xFFE8EDF5);

  // =============================================================
  // STATUS
  // =============================================================

  static const Color success = Color(0xFF16C784);

  static const Color successSoft = Color(0xFFE8FFF5);

  static const Color warning = Color(0xFFFFB020);

  static const Color warningSoft = Color(0xFFFFF7E5);

  static const Color error = Color(0xFFFF3B5C);

  static const Color errorSoft = Color(0xFFFFEDF1);

  static const Color info = Color(0xFF2F80ED);

  static const Color infoSoft = Color(0xFFEBF4FF);

  // =============================================================
  // CALL STATES
  // =============================================================

  static const Color incomingCall = Color(0xFF168BFF);

  static const Color outgoingCall = Color(0xFF2379EF);

  static const Color missedCall = Color(0xFFFF3159);

  static const Color videoCall = Color(0xFF8B4CF6);

  static const Color online = Color(0xFF13CE66);

  static const Color offline = Color(0xFF98A2B3);

  // =============================================================
  // SOCIAL / PROFILE
  // =============================================================

  static const Color verified = Color(0xFF168BFF);

  static const Color like = Color(0xFFFF3159);

  static const Color comment = Color(0xFF4671C9);

  static const Color earnings = Color(0xFF18BD7F);

  static const Color live = Color(0xFFFF2448);

  // =============================================================
  // NAVIGATION
  // =============================================================

  static const Color navigationBackground = Color(0xF5FFFFFF);

  static const Color navigationSelected = primaryBlue;

  static const Color navigationUnselected = Color(0xFF667085);

  static const Color badge = Color(0xFFFF263F);

  static const Color badgeText = Color(0xFFFFFFFF);

  // =============================================================
  // DISABLED
  // =============================================================

  static const Color disabled = Color(0xFFC8D0DC);

  static const Color disabledBackground = Color(0xFFF0F2F6);

  static const Color disabledText = Color(0xFF9EA7B5);

  // =============================================================
  // OVERLAYS
  // =============================================================

  static const Color overlayLight = Color(0x14000000);

  static const Color overlayMedium = Color(0x52000000);

  static const Color overlayDark = Color(0x99000000);

  // =============================================================
  // BASIC
  // =============================================================

  static const Color white = Color(0xFFFFFFFF);

  static const Color black = Color(0xFF000000);

  static const Color transparent = Colors.transparent;
}
