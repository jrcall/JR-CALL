import 'package:flutter/material.dart';

import 'jr_colors.dart';

/// ============================================================================
/// JR CALL — GLOBAL VISUAL EFFECTS
/// File: jr_effects.dart
/// Location: lib/core/theme/jr_effects.dart
///
/// Central source for:
/// - premium soft shadows
/// - glassmorphism shadows
/// - feature-specific neon glows
/// - reusable gradients
///
/// IMPORTANT:
/// Do not place screen-specific business logic here.
/// Do not duplicate these effects throughout individual screens.
/// ============================================================================
abstract final class JrEffects {
  JrEffects._();

  // ==========================================================================
  // STANDARD SHADOWS
  // ==========================================================================

  static const List<BoxShadow> softShadow = <BoxShadow>[
    BoxShadow(
      color: Color(0x120F172A),
      blurRadius: 18,
      spreadRadius: 0,
      offset: Offset(0, 8),
    ),
    BoxShadow(
      color: Color(0x08FFFFFF),
      blurRadius: 4,
      spreadRadius: 0,
      offset: Offset(0, -1),
    ),
  ];

  static const List<BoxShadow> cardShadow = <BoxShadow>[
    BoxShadow(
      color: Color(0x100F172A),
      blurRadius: 24,
      spreadRadius: 0,
      offset: Offset(0, 10),
    ),
  ];

  static const List<BoxShadow> elevatedShadow = <BoxShadow>[
    BoxShadow(
      color: Color(0x160F172A),
      blurRadius: 30,
      spreadRadius: 1,
      offset: Offset(0, 14),
    ),
  ];

  // ==========================================================================
  // GLASSMORPHISM
  // ==========================================================================

  static const List<BoxShadow> glassShadow = <BoxShadow>[
    BoxShadow(
      color: Color(0x0D0F172A),
      blurRadius: 24,
      spreadRadius: 0,
      offset: Offset(0, 10),
    ),
    BoxShadow(
      color: Color(0x70FFFFFF),
      blurRadius: 6,
      spreadRadius: 0,
      offset: Offset(0, -2),
    ),
  ];

  static const List<BoxShadow> glassFloatingShadow = <BoxShadow>[
    BoxShadow(
      color: Color(0x140F172A),
      blurRadius: 32,
      spreadRadius: 0,
      offset: Offset(0, 14),
    ),
    BoxShadow(
      color: Color(0x90FFFFFF),
      blurRadius: 8,
      spreadRadius: -2,
      offset: Offset(0, -2),
    ),
  ];

  // ==========================================================================
  // PRIMARY BLUE EFFECT
  // ==========================================================================

  static List<BoxShadow> get blueGlow => <BoxShadow>[
    BoxShadow(
      color: JrColors.primaryBlue.withValues(alpha: 0.22),
      blurRadius: 22,
      spreadRadius: 1,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: JrColors.secondaryBlue.withValues(alpha: 0.12),
      blurRadius: 12,
      spreadRadius: 0,
      offset: const Offset(0, 2),
    ),
  ];

  // ==========================================================================
  // CALL — GREEN / CYAN
  // ==========================================================================

  static List<BoxShadow> get callGlow => <BoxShadow>[
    BoxShadow(
      color: JrColors.callGreen.withValues(alpha: 0.24),
      blurRadius: 24,
      spreadRadius: 1,
      offset: const Offset(0, 8),
    ),
  ];

  // ==========================================================================
  // MESSAGE — PURPLE
  // ==========================================================================

  static List<BoxShadow> get messageGlow => <BoxShadow>[
    BoxShadow(
      color: JrColors.messagePurple.withValues(alpha: 0.24),
      blurRadius: 24,
      spreadRadius: 1,
      offset: const Offset(0, 8),
    ),
  ];

  // ==========================================================================
  // PUBLIC MEDIA — ORANGE / AMBER
  // ==========================================================================

  static List<BoxShadow> get mediaGlow => <BoxShadow>[
    BoxShadow(
      color: JrColors.mediaOrange.withValues(alpha: 0.24),
      blurRadius: 24,
      spreadRadius: 1,
      offset: const Offset(0, 8),
    ),
  ];

  // ==========================================================================
  // VIDEO REELS — CYAN / BLUE
  // ==========================================================================

  static List<BoxShadow> get reelsGlow => <BoxShadow>[
    BoxShadow(
      color: JrColors.reelsCyan.withValues(alpha: 0.24),
      blurRadius: 24,
      spreadRadius: 1,
      offset: const Offset(0, 8),
    ),
  ];

  // ==========================================================================
  // AI TOOLS — VIOLET / MAGENTA
  // ==========================================================================

  static List<BoxShadow> get aiGlow => <BoxShadow>[
    BoxShadow(
      color: JrColors.aiPurple.withValues(alpha: 0.26),
      blurRadius: 26,
      spreadRadius: 1,
      offset: const Offset(0, 8),
    ),
  ];

  // ==========================================================================
  // STATUS EFFECTS
  // ==========================================================================

  static List<BoxShadow> get successGlow => <BoxShadow>[
    BoxShadow(
      color: JrColors.success.withValues(alpha: 0.20),
      blurRadius: 18,
      spreadRadius: 0,
      offset: const Offset(0, 6),
    ),
  ];

  static List<BoxShadow> get warningGlow => <BoxShadow>[
    BoxShadow(
      color: JrColors.warning.withValues(alpha: 0.18),
      blurRadius: 18,
      spreadRadius: 0,
      offset: const Offset(0, 6),
    ),
  ];

  static List<BoxShadow> get errorGlow => <BoxShadow>[
    BoxShadow(
      color: JrColors.error.withValues(alpha: 0.20),
      blurRadius: 18,
      spreadRadius: 0,
      offset: const Offset(0, 6),
    ),
  ];

  // ==========================================================================
  // PREMIUM GRADIENTS
  // ==========================================================================

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[JrColors.secondaryBlue, JrColors.primaryBlue],
  );

  static LinearGradient get glassGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Colors.white.withValues(alpha: 0.92),
      JrColors.surfaceGlass.withValues(alpha: 0.82),
    ],
  );

  static LinearGradient get callGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      JrColors.callGreen.withValues(alpha: 0.16),
      JrColors.reelsCyan.withValues(alpha: 0.08),
    ],
  );

  static LinearGradient get messageGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      JrColors.messagePurple.withValues(alpha: 0.15),
      JrColors.aiPurple.withValues(alpha: 0.07),
    ],
  );

  static LinearGradient get mediaGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      JrColors.mediaOrange.withValues(alpha: 0.16),
      JrColors.warning.withValues(alpha: 0.06),
    ],
  );

  static LinearGradient get reelsGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      JrColors.reelsCyan.withValues(alpha: 0.16),
      JrColors.primaryBlue.withValues(alpha: 0.07),
    ],
  );

  static LinearGradient get aiGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      JrColors.aiPurple.withValues(alpha: 0.16),
      JrColors.messagePurple.withValues(alpha: 0.07),
    ],
  );

  // ==========================================================================
  // BORDER HELPERS
  // ==========================================================================

  static Border get glassBorder =>
      Border.all(color: JrColors.border.withValues(alpha: 0.72), width: 1);

  static Border get subtleBorder =>
      Border.all(color: JrColors.border.withValues(alpha: 0.48), width: 1);

  static Border featureBorder(Color color) =>
      Border.all(color: color.withValues(alpha: 0.22), width: 1);

  // ==========================================================================
  // DYNAMIC FEATURE EFFECT
  // ==========================================================================

  static List<BoxShadow> featureGlow(
    Color color, {
    double opacity = 0.22,
    double blurRadius = 24,
    double spreadRadius = 1,
    Offset offset = const Offset(0, 8),
  }) {
    return <BoxShadow>[
      BoxShadow(
        color: color.withValues(alpha: opacity),
        blurRadius: blurRadius,
        spreadRadius: spreadRadius,
        offset: offset,
      ),
    ];
  }
}
