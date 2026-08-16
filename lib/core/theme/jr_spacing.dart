import 'package:flutter/widgets.dart';

/// ===============================================================
/// JR CALL — Global Spacing System
/// File: jr_spacing.dart
/// Location: lib/core/theme/jr_spacing.dart
///
/// PURPOSE:
/// Single source of truth for spacing, padding, gaps and sizing
/// throughout the JR CALL application.
///
/// DESIGN TARGET:
/// Modern Glassmorphism + Soft Neon Gradient + Premium Light UI
///
/// RULE:
/// Individual screens should avoid random hard-coded spacing values.
/// Reuse these constants so Login, Account, Profile, Call, Message,
/// Public Media, Video Reels and AI Tools stay visually consistent.
/// ===============================================================
abstract final class JrSpacing {
  // =============================================================
  // BASE SPACING SCALE
  // =============================================================

  /// Extra-small spacing.
  static const double xs = 4.0;

  /// Small spacing.
  static const double sm = 8.0;

  /// Medium spacing.
  static const double md = 12.0;

  /// Standard content spacing.
  static const double lg = 16.0;

  /// Large section spacing.
  static const double xl = 24.0;

  /// Extra-large section spacing.
  static const double xxl = 32.0;

  /// Major layout separation.
  static const double xxxl = 40.0;

  /// Large hero-section separation.
  static const double hero = 48.0;

  // =============================================================
  // SCREEN PADDING
  // =============================================================

  /// Standard horizontal padding for mobile screens.
  static const double screenHorizontal = 20.0;

  /// Standard vertical content padding.
  static const double screenVertical = 16.0;

  /// Compact-screen horizontal padding.
  static const double screenHorizontalCompact = 16.0;

  /// Larger phone / tablet horizontal padding.
  static const double screenHorizontalWide = 28.0;

  /// Maximum horizontal padding used on very wide layouts.
  static const double screenHorizontalDesktop = 32.0;

  static const EdgeInsets screenPadding = EdgeInsets.symmetric(
    horizontal: screenHorizontal,
    vertical: screenVertical,
  );

  static const EdgeInsets screenHorizontalPadding = EdgeInsets.symmetric(
    horizontal: screenHorizontal,
  );

  // =============================================================
  // CARD SPACING
  // =============================================================

  /// Default internal card padding.
  static const double cardPadding = 16.0;

  /// Compact card padding.
  static const double cardPaddingCompact = 12.0;

  /// Large/profile/dashboard card padding.
  static const double cardPaddingLarge = 20.0;

  static const EdgeInsets cardInsets = EdgeInsets.all(cardPadding);

  static const EdgeInsets cardInsetsCompact = EdgeInsets.all(
    cardPaddingCompact,
  );

  static const EdgeInsets cardInsetsLarge = EdgeInsets.all(cardPaddingLarge);

  // =============================================================
  // SECTION SPACING
  // =============================================================

  /// Gap between related elements.
  static const double itemGap = 12.0;

  /// Gap between cards.
  static const double cardGap = 14.0;

  /// Gap between normal sections.
  static const double sectionGap = 24.0;

  /// Gap between major page sections.
  static const double majorSectionGap = 32.0;

  /// Gap used around hero/branding sections.
  static const double heroSectionGap = 40.0;

  // =============================================================
  // INPUT FIELD METRICS
  // =============================================================

  /// Standard premium input height.
  static const double inputHeight = 58.0;

  /// Compact input height for dense layouts.
  static const double inputHeightCompact = 52.0;

  /// Horizontal padding inside inputs.
  static const double inputHorizontalPadding = 16.0;

  /// Vertical padding inside multiline inputs.
  static const double inputVerticalPadding = 14.0;

  /// Gap between input icon and text.
  static const double inputIconGap = 12.0;

  /// Gap between consecutive form fields.
  static const double formFieldGap = 14.0;

  static const EdgeInsets inputContentPadding = EdgeInsets.symmetric(
    horizontal: inputHorizontalPadding,
    vertical: inputVerticalPadding,
  );

  // =============================================================
  // BUTTON METRICS
  // =============================================================

  /// Main CTA height used by:
  /// Login, Continue, Create Account, Verify OTP, Save.
  static const double buttonHeight = 58.0;

  /// Compact secondary button height.
  static const double buttonHeightCompact = 48.0;

  /// Large action button height when required.
  static const double buttonHeightLarge = 64.0;

  /// Horizontal content padding inside standard buttons.
  static const double buttonHorizontalPadding = 24.0;

  /// Gap between button icon and label.
  static const double buttonIconGap = 10.0;

  // =============================================================
  // HEADER METRICS
  // =============================================================

  /// Header content height excluding SafeArea.
  static const double headerHeight = 72.0;

  /// Internal horizontal header padding.
  static const double headerHorizontalPadding = 20.0;

  /// Gap between logo and JR CALL title.
  static const double headerLogoGap = 12.0;

  /// Gap between right-side header actions.
  static const double headerActionGap = 10.0;

  /// Main JR logo size in authenticated header.
  static const double headerLogoSize = 52.0;

  /// Profile avatar size in authenticated header.
  static const double headerAvatarSize = 48.0;

  /// Search/menu circular action size.
  static const double headerActionSize = 46.0;

  // =============================================================
  // BOTTOM NAVIGATION
  // =============================================================

  /// Height of reusable 5-destination navigation area.
  static const double bottomNavigationHeight = 82.0;

  /// Horizontal padding around bottom navigation.
  static const double bottomNavigationHorizontal = 14.0;

  /// Vertical content padding inside bottom navigation.
  static const double bottomNavigationVertical = 8.0;

  /// Icon visual size.
  static const double bottomNavigationIconSize = 28.0;

  /// Selected destination visual/container size.
  static const double bottomNavigationItemSize = 52.0;

  /// Space between nav icon and text.
  static const double bottomNavigationLabelGap = 4.0;

  /// Badge minimum size.
  static const double badgeSize = 20.0;

  // =============================================================
  // PROFILE / AVATAR
  // =============================================================

  /// Small avatar used in feed rows.
  static const double avatarSmall = 36.0;

  /// Standard list/search avatar.
  static const double avatarMedium = 52.0;

  /// Large avatar used in profile/header areas.
  static const double avatarLarge = 92.0;

  /// Profile dashboard hero avatar.
  static const double avatarProfile = 112.0;

  /// Small online-status dot.
  static const double statusDotSmall = 10.0;

  /// Standard online-status dot.
  static const double statusDot = 14.0;

  /// Profile camera overlay button.
  static const double avatarActionButton = 38.0;

  // =============================================================
  // ICON SIZES
  // =============================================================

  static const double iconXs = 16.0;
  static const double iconSm = 20.0;
  static const double iconMd = 24.0;
  static const double iconLg = 28.0;
  static const double iconXl = 32.0;
  static const double iconHero = 48.0;

  // =============================================================
  // DIALOG / SHEET
  // =============================================================

  static const double dialogPadding = 24.0;
  static const double dialogGap = 16.0;
  static const double sheetPadding = 20.0;

  static const EdgeInsets dialogInsets = EdgeInsets.all(dialogPadding);

  static const EdgeInsets sheetInsets = EdgeInsets.all(sheetPadding);

  // =============================================================
  // AUTH / ACCOUNT FLOW
  // =============================================================

  /// Logo/brand spacing on Login/Create Account screens.
  static const double authBrandTopGap = 20.0;

  /// Space between brand block and form.
  static const double authBrandToFormGap = 28.0;

  /// Space between form and main CTA.
  static const double authFormToButtonGap = 24.0;

  /// Space below the primary CTA.
  static const double authButtonBottomGap = 20.0;

  /// Step indicator area height.
  static const double accountStepIndicatorHeight = 42.0;

  /// Gap between step indicator and page title.
  static const double accountStepToTitleGap = 20.0;

  // =============================================================
  // CALL UI
  // =============================================================

  /// Call history/contact card vertical padding.
  static const double callCardVerticalPadding = 14.0;

  /// Gap between call list cards.
  static const double callCardGap = 12.0;

  /// Size of call action circle.
  static const double callActionSize = 52.0;

  /// Large in-call circular action.
  static const double callControlSize = 58.0;

  /// Primary End Call button size.
  static const double endCallControlSize = 64.0;

  // =============================================================
  // FEED / MEDIA UI
  // =============================================================

  static const double feedCardGap = 14.0;
  static const double feedContentGap = 10.0;
  static const double feedAvatarSize = 42.0;
  static const double mediaThumbnailHeight = 180.0;

  // =============================================================
  // RESPONSIVE BREAKPOINTS
  // =============================================================

  /// Small/compact mobile width.
  static const double compactBreakpoint = 360.0;

  /// Tablet-style layout begins here.
  static const double tabletBreakpoint = 600.0;

  /// Wide desktop-style layout begins here.
  static const double desktopBreakpoint = 1024.0;

  /// Maximum readable form/content width.
  static const double maxContentWidth = 720.0;

  /// Maximum auth form width on tablets/desktops.
  static const double maxAuthContentWidth = 520.0;

  // =============================================================
  // RESPONSIVE HELPERS
  // =============================================================

  /// Returns appropriate screen horizontal padding based on width.
  static double horizontalForWidth(double width) {
    if (width >= desktopBreakpoint) {
      return screenHorizontalDesktop;
    }

    if (width >= tabletBreakpoint) {
      return screenHorizontalWide;
    }

    if (width <= compactBreakpoint) {
      return screenHorizontalCompact;
    }

    return screenHorizontal;
  }

  /// Returns responsive screen padding without requiring BuildContext.
  static EdgeInsets screenInsetsForWidth(double width) {
    return EdgeInsets.symmetric(
      horizontal: horizontalForWidth(width),
      vertical: screenVertical,
    );
  }

  /// Returns the safest available content width.
  ///
  /// Useful for centered Login/Create Account/Profile forms on
  /// larger displays while keeping the mobile reference proportions.
  static double constrainedContentWidth(
    double availableWidth, {
    double maxWidth = maxContentWidth,
  }) {
    final horizontal = horizontalForWidth(availableWidth) * 2;
    final usableWidth = availableWidth - horizontal;

    if (usableWidth <= 0) {
      return availableWidth;
    }

    return usableWidth > maxWidth ? maxWidth : usableWidth;
  }
}
