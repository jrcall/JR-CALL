import 'package:flutter/widgets.dart';

/// ===============================================================
/// JR CALL — Global Radius System
/// File: jr_radius.dart
/// Location: lib/core/theme/jr_radius.dart
///
/// PURPOSE:
/// Central source of truth for every rounded corner used by JR CALL.
///
/// DESIGN:
/// Modern Glassmorphism + Soft Neon Gradient + Premium Light UI
///
/// IMPORTANT:
/// Screens/widgets should reuse these values instead of adding
/// random BorderRadius values.
/// ===============================================================
abstract final class JrRadius {
  // =============================================================
  // RAW RADIUS SCALE
  // =============================================================

  static const double xs = 6.0;
  static const double sm = 10.0;
  static const double md = 14.0;
  static const double lg = 18.0;
  static const double xl = 24.0;
  static const double xxl = 30.0;
  static const double xxxl = 36.0;

  // =============================================================
  // PRIMARY COMPONENT RADII
  // =============================================================

  /// Standard text/input field radius.
  static const double input = 18.0;

  /// Main CTA button radius.
  static const double button = 18.0;

  /// Secondary/compact button radius.
  static const double buttonCompact = 14.0;

  /// Standard glass card radius.
  static const double card = 22.0;

  /// Large premium/profile/dashboard card radius.
  static const double cardLarge = 28.0;

  /// Small feed/list card radius.
  static const double cardCompact = 18.0;

  /// Header/search container radius.
  static const double header = 24.0;

  /// Bottom navigation shell radius.
  static const double bottomNavigation = 28.0;

  /// Segmented control outer radius.
  static const double segmentedControl = 20.0;

  /// Selected segmented item radius.
  static const double segmentedItem = 16.0;

  /// Dialog radius.
  static const double dialog = 26.0;

  /// Bottom sheet top radius.
  static const double sheet = 28.0;

  /// Media/image/card preview radius.
  static const double media = 18.0;

  /// Cover photo radius.
  static const double cover = 22.0;

  /// OTP digit field radius.
  static const double otp = 16.0;

  /// Call-history/action card radius.
  static const double callCard = 22.0;

  /// Search box radius.
  static const double search = 22.0;

  // =============================================================
  // CIRCULAR / AVATAR
  // =============================================================

  /// Full circle.
  static const double circle = 999.0;

  /// Avatar/profile circle.
  static const BorderRadius avatar = BorderRadius.all(Radius.circular(circle));

  /// Circular icon/action button.
  static const BorderRadius circularButton = BorderRadius.all(
    Radius.circular(circle),
  );

  // =============================================================
  // READY-TO-USE BORDER RADIUS OBJECTS
  // =============================================================

  static const BorderRadius inputBorder = BorderRadius.all(
    Radius.circular(input),
  );

  static const BorderRadius buttonBorder = BorderRadius.all(
    Radius.circular(button),
  );

  static const BorderRadius buttonCompactBorder = BorderRadius.all(
    Radius.circular(buttonCompact),
  );

  static const BorderRadius cardBorder = BorderRadius.all(
    Radius.circular(card),
  );

  static const BorderRadius cardLargeBorder = BorderRadius.all(
    Radius.circular(cardLarge),
  );

  static const BorderRadius cardCompactBorder = BorderRadius.all(
    Radius.circular(cardCompact),
  );

  static const BorderRadius headerBorder = BorderRadius.all(
    Radius.circular(header),
  );

  static const BorderRadius bottomNavigationBorder = BorderRadius.all(
    Radius.circular(bottomNavigation),
  );

  static const BorderRadius segmentedControlBorder = BorderRadius.all(
    Radius.circular(segmentedControl),
  );

  static const BorderRadius segmentedItemBorder = BorderRadius.all(
    Radius.circular(segmentedItem),
  );

  static const BorderRadius dialogBorder = BorderRadius.all(
    Radius.circular(dialog),
  );

  static const BorderRadius mediaBorder = BorderRadius.all(
    Radius.circular(media),
  );

  static const BorderRadius coverBorder = BorderRadius.all(
    Radius.circular(cover),
  );

  static const BorderRadius otpBorder = BorderRadius.all(Radius.circular(otp));

  static const BorderRadius callCardBorder = BorderRadius.all(
    Radius.circular(callCard),
  );

  static const BorderRadius searchBorder = BorderRadius.all(
    Radius.circular(search),
  );

  // =============================================================
  // BOTTOM SHEET
  // =============================================================

  static const BorderRadius sheetBorder = BorderRadius.only(
    topLeft: Radius.circular(sheet),
    topRight: Radius.circular(sheet),
  );

  // =============================================================
  // SPECIAL PROFILE / MEDIA SHAPES
  // =============================================================

  /// Cover image with slightly softer lower edge.
  static const BorderRadius profileCoverBorder = BorderRadius.only(
    topLeft: Radius.circular(cover),
    topRight: Radius.circular(cover),
    bottomLeft: Radius.circular(md),
    bottomRight: Radius.circular(md),
  );

  /// Feed media thumbnail.
  static const BorderRadius feedMediaBorder = BorderRadius.all(
    Radius.circular(media),
  );

  // =============================================================
  // HELPERS
  // =============================================================

  /// Creates a custom circular radius while keeping a single API.
  static BorderRadius all(double value) {
    assert(value >= 0, 'Radius cannot be negative.');
    return BorderRadius.circular(value);
  }

  /// Creates top-only rounded corners.
  static BorderRadius top(double value) {
    assert(value >= 0, 'Radius cannot be negative.');
    return BorderRadius.only(
      topLeft: Radius.circular(value),
      topRight: Radius.circular(value),
    );
  }

  /// Creates bottom-only rounded corners.
  static BorderRadius bottom(double value) {
    assert(value >= 0, 'Radius cannot be negative.');
    return BorderRadius.only(
      bottomLeft: Radius.circular(value),
      bottomRight: Radius.circular(value),
    );
  }
}
