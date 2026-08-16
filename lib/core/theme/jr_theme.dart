import 'package:flutter/material.dart';

import 'jr_colors.dart';
import 'jr_radius.dart';
import 'jr_spacing.dart';
import 'jr_typography.dart';

/// ============================================================================
/// JR CALL — GLOBAL APPLICATION THEME
/// File: jr_theme.dart
/// Location: lib/core/theme/jr_theme.dart
///
/// Central ThemeData authority for JR CALL.
///
/// Design direction:
/// Modern Glassmorphism + Soft Neon Gradient + Premium Light UI.
///
/// This file owns Flutter's application-level ThemeData.
/// Screen-specific UI must reuse the centralized design system instead of
/// creating unrelated colors, radii, typography, or component styles.
/// ============================================================================
abstract final class JrTheme {
  JrTheme._();

  // ==========================================================================
  // PUBLIC THEME
  // ==========================================================================

  static ThemeData get light {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: JrColors.primaryBlue,
      brightness: Brightness.light,
      primary: JrColors.primaryBlue,
      secondary: JrColors.secondaryBlue,
      error: JrColors.error,
      surface: JrColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      // ----------------------------------------------------------------------
      // GLOBAL COLORS
      // ----------------------------------------------------------------------
      colorScheme: colorScheme,
      scaffoldBackgroundColor: JrColors.background,
      canvasColor: JrColors.background,
      cardColor: JrColors.surface,
      dividerColor: JrColors.divider,
      disabledColor: JrColors.disabled,

      // ----------------------------------------------------------------------
      // TYPOGRAPHY
      // ----------------------------------------------------------------------
      textTheme: _textTheme,
      primaryTextTheme: _textTheme,

      // ----------------------------------------------------------------------
      // APP BAR
      // ----------------------------------------------------------------------
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: JrColors.textPrimary,
        titleTextStyle: JrTypography.screenTitle,
        iconTheme: const IconThemeData(color: JrColors.textPrimary, size: 24),
      ),

      // ----------------------------------------------------------------------
      // CARDS
      // ----------------------------------------------------------------------
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: JrColors.surface,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JrRadius.card),
          side: const BorderSide(color: JrColors.border, width: 1),
        ),
      ),

      // ----------------------------------------------------------------------
      // INPUTS
      // ----------------------------------------------------------------------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: JrColors.surfaceGlass,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: JrSpacing.md,
          vertical: JrSpacing.md,
        ),
        hintStyle: JrTypography.inputText.copyWith(
          color: JrColors.textSecondary,
        ),
        labelStyle: JrTypography.inputLabel.copyWith(
          color: JrColors.textSecondary,
        ),
        floatingLabelStyle: JrTypography.inputLabel.copyWith(
          color: JrColors.primaryBlue,
        ),
        prefixIconColor: JrColors.primaryBlue,
        suffixIconColor: JrColors.textSecondary,
        border: _inputBorder(JrColors.border),
        enabledBorder: _inputBorder(JrColors.border),
        disabledBorder: _inputBorder(JrColors.disabled),
        focusedBorder: _inputBorder(JrColors.primaryBlue, width: 1.5),
        errorBorder: _inputBorder(JrColors.error, width: 1.2),
        focusedErrorBorder: _inputBorder(JrColors.error, width: 1.5),
        errorStyle: JrTypography.caption.copyWith(color: JrColors.error),
      ),

      // ----------------------------------------------------------------------
      // PRIMARY FILLED BUTTON
      // ----------------------------------------------------------------------
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStateProperty.all(
            const Size.fromHeight(JrSpacing.buttonHeight),
          ),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(
              horizontal: JrSpacing.lg,
              vertical: JrSpacing.sm,
            ),
          ),
          elevation: WidgetStateProperty.all(0),
          backgroundColor: WidgetStateProperty.resolveWith<Color>((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.disabled)) {
              return JrColors.disabled;
            }
            return JrColors.primaryBlue;
          }),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          overlayColor: WidgetStateProperty.all(
            Colors.white.withValues(alpha: 0.10),
          ),
          textStyle: WidgetStateProperty.all(JrTypography.buttonLabel),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(JrRadius.button),
            ),
          ),
        ),
      ),

      // ----------------------------------------------------------------------
      // ELEVATED BUTTON
      // ----------------------------------------------------------------------
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStateProperty.all(
            const Size.fromHeight(JrSpacing.buttonHeight),
          ),
          elevation: WidgetStateProperty.all(0),
          shadowColor: WidgetStateProperty.all(Colors.transparent),
          backgroundColor: WidgetStateProperty.resolveWith<Color>((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.disabled)) {
              return JrColors.disabled;
            }
            return JrColors.primaryBlue;
          }),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          textStyle: WidgetStateProperty.all(JrTypography.buttonLabel),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(JrRadius.button),
            ),
          ),
        ),
      ),

      // ----------------------------------------------------------------------
      // OUTLINED BUTTON
      // ----------------------------------------------------------------------
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStateProperty.all(
            const Size.fromHeight(JrSpacing.buttonHeight),
          ),
          backgroundColor: WidgetStateProperty.all(JrColors.surfaceGlass),
          foregroundColor: WidgetStateProperty.all(JrColors.primaryBlue),
          textStyle: WidgetStateProperty.all(JrTypography.buttonLabel),
          side: WidgetStateProperty.resolveWith<BorderSide>((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.disabled)) {
              return const BorderSide(color: JrColors.disabled);
            }

            return const BorderSide(color: JrColors.border, width: 1);
          }),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(JrRadius.button),
            ),
          ),
        ),
      ),

      // ----------------------------------------------------------------------
      // TEXT BUTTON
      // ----------------------------------------------------------------------
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith<Color>((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.disabled)) {
              return JrColors.disabled;
            }
            return JrColors.primaryBlue;
          }),
          textStyle: WidgetStateProperty.all(JrTypography.buttonLabel),
          overlayColor: WidgetStateProperty.all(
            JrColors.primaryBlue.withValues(alpha: 0.08),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(JrRadius.button),
            ),
          ),
        ),
      ),

      // ----------------------------------------------------------------------
      // ICON BUTTON
      // ----------------------------------------------------------------------
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith<Color>((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.disabled)) {
              return JrColors.disabled;
            }
            return JrColors.textPrimary;
          }),
          overlayColor: WidgetStateProperty.all(
            JrColors.primaryBlue.withValues(alpha: 0.08),
          ),
        ),
      ),

      // ----------------------------------------------------------------------
      // FLOATING ACTION BUTTON
      // ----------------------------------------------------------------------
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        backgroundColor: JrColors.primaryBlue,
        foregroundColor: Colors.white,
        shape: CircleBorder(),
      ),

      // ----------------------------------------------------------------------
      // DIALOGS
      // ----------------------------------------------------------------------
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: JrColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JrRadius.dialog),
          side: const BorderSide(color: JrColors.border, width: 1),
        ),
        titleTextStyle: JrTypography.sectionTitle,
        contentTextStyle: JrTypography.body,
      ),

      // ----------------------------------------------------------------------
      // BOTTOM SHEET
      // ----------------------------------------------------------------------
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 0,
        modalElevation: 0,
        backgroundColor: JrColors.surface,
        modalBackgroundColor: JrColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: JrColors.divider,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(JrRadius.dialog),
          ),
        ),
      ),

      // ----------------------------------------------------------------------
      // NAVIGATION BAR
      // ----------------------------------------------------------------------
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 72,
        backgroundColor: JrColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: JrColors.primaryBlue.withValues(alpha: 0.10),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((
          Set<WidgetState> states,
        ) {
          if (states.contains(WidgetState.selected)) {
            return JrTypography.navigationLabel.copyWith(
              color: JrColors.primaryBlue,
              fontWeight: FontWeight.w700,
            );
          }

          return JrTypography.navigationLabel.copyWith(
            color: JrColors.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((
          Set<WidgetState> states,
        ) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: JrColors.primaryBlue, size: 25);
          }

          return const IconThemeData(color: JrColors.textSecondary, size: 24);
        }),
      ),

      // ----------------------------------------------------------------------
      // TABS
      // ----------------------------------------------------------------------
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorColor: JrColors.primaryBlue,
        labelColor: JrColors.primaryBlue,
        unselectedLabelColor: JrColors.textSecondary,
        labelStyle: JrTypography.navigationLabel.copyWith(
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: JrTypography.navigationLabel,
      ),

      // ----------------------------------------------------------------------
      // CHIPS
      // ----------------------------------------------------------------------
      chipTheme: ChipThemeData(
        elevation: 0,
        pressElevation: 0,
        backgroundColor: JrColors.surfaceGlass,
        selectedColor: JrColors.primaryBlue.withValues(alpha: 0.10),
        disabledColor: JrColors.disabled.withValues(alpha: 0.12),
        side: const BorderSide(color: JrColors.border, width: 1),
        labelStyle: JrTypography.caption.copyWith(color: JrColors.textPrimary),
        secondaryLabelStyle: JrTypography.caption.copyWith(
          color: JrColors.primaryBlue,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JrRadius.button),
        ),
      ),

      // ----------------------------------------------------------------------
      // CHECKBOX / RADIO / SWITCH
      // ----------------------------------------------------------------------
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        fillColor: WidgetStateProperty.resolveWith<Color?>((
          Set<WidgetState> states,
        ) {
          if (states.contains(WidgetState.selected)) {
            return JrColors.primaryBlue;
          }
          return null;
        }),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color?>((
          Set<WidgetState> states,
        ) {
          if (states.contains(WidgetState.selected)) {
            return JrColors.primaryBlue;
          }
          return JrColors.textSecondary;
        }),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>((
          Set<WidgetState> states,
        ) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return JrColors.surface;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color?>((
          Set<WidgetState> states,
        ) {
          if (states.contains(WidgetState.selected)) {
            return JrColors.primaryBlue;
          }
          return JrColors.disabled;
        }),
      ),

      // ----------------------------------------------------------------------
      // PROGRESS
      // ----------------------------------------------------------------------
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: JrColors.primaryBlue,
        linearTrackColor: JrColors.divider,
        circularTrackColor: JrColors.divider,
      ),

      // ----------------------------------------------------------------------
      // SNACKBAR
      // ----------------------------------------------------------------------
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: JrColors.textPrimary,
        contentTextStyle: JrTypography.body.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JrRadius.card),
        ),
      ),

      // ----------------------------------------------------------------------
      // DIVIDER
      // ----------------------------------------------------------------------
      dividerTheme: const DividerThemeData(
        color: JrColors.divider,
        thickness: 1,
        space: 1,
      ),

      // ----------------------------------------------------------------------
      // TOOLTIP
      // ----------------------------------------------------------------------
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: JrColors.textPrimary,
          borderRadius: BorderRadius.circular(JrRadius.input),
        ),
        textStyle: JrTypography.caption.copyWith(color: Colors.white),
      ),

      // ----------------------------------------------------------------------
      // SELECTION / CURSOR
      // ----------------------------------------------------------------------
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: JrColors.primaryBlue,
        selectionColor: JrColors.primaryBlue.withValues(alpha: 0.22),
        selectionHandleColor: JrColors.primaryBlue,
      ),

      // ----------------------------------------------------------------------
      // SPLASH / TOUCH FEEDBACK
      // ----------------------------------------------------------------------
      splashColor: JrColors.primaryBlue.withValues(alpha: 0.06),
      highlightColor: Colors.transparent,
      hoverColor: JrColors.primaryBlue.withValues(alpha: 0.04),
      focusColor: JrColors.primaryBlue.withValues(alpha: 0.06),

      // ----------------------------------------------------------------------
      // VISUAL DENSITY
      // ----------------------------------------------------------------------
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }

  // ==========================================================================
  // TEXT THEME
  // ==========================================================================

  static TextTheme get _textTheme => TextTheme(
    displayLarge: JrTypography.brandTitle,
    displayMedium: JrTypography.brandTitle,
    displaySmall: JrTypography.screenTitle,
    headlineLarge: JrTypography.screenTitle,
    headlineMedium: JrTypography.screenTitle,
    headlineSmall: JrTypography.sectionTitle,
    titleLarge: JrTypography.sectionTitle,
    titleMedium: JrTypography.sectionTitle,
    titleSmall: JrTypography.inputLabel,
    bodyLarge: JrTypography.body,
    bodyMedium: JrTypography.body,
    bodySmall: JrTypography.caption,
    labelLarge: JrTypography.buttonLabel,
    labelMedium: JrTypography.navigationLabel,
    labelSmall: JrTypography.metadata,
  ).apply(bodyColor: JrColors.textPrimary, displayColor: JrColors.textPrimary);

  // ==========================================================================
  // HELPERS
  // ==========================================================================

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(JrRadius.input),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
