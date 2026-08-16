// ===============================================================
// JR CALL
// File: main.dart
// Location: lib/main.dart
//
// FINAL PRODUCTION APP ENTRY
//
// STARTUP CONTRACT:
// - App NEVER forces Welcome/Login on startup.
// - Signed-out / Guest -> HomeScreen -> Public Media.
// - Authenticated user -> HomeScreen -> Call.
// - WelcomeScreen remains available only from protected auth flows.
// - Public Media / Reels can be browsed as guest.
// - Protected actions are gated inside feature screens.
// - Firebase initialization preserved.
// - ProviderScope preserved.
// - STUN/TURN pre-warm only for authenticated users.
// - Call Engine / WebRTC ownership untouched.
// - No fake/demo startup state.
// ===============================================================

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/jr_colors.dart';
import 'core/theme/jr_typography.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/call/stun_turn_service.dart';

// ===============================================================
// BOOTSTRAP
// ===============================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _configureFlutterErrors();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    runApp(const ProviderScope(child: JRCallApp()));
  } catch (error, stackTrace) {
    debugPrint('JR CALL bootstrap error: $error');

    debugPrintStack(label: 'JR CALL bootstrap', stackTrace: stackTrace);

    runApp(JRCallBootstrapErrorApp(error: error));
  }
}

// ===============================================================
// GLOBAL FLUTTER ERROR HANDLING
// ===============================================================

void _configureFlutterErrors() {
  final FlutterExceptionHandler? previous = FlutterError.onError;

  FlutterError.onError = (FlutterErrorDetails details) {
    if (previous != null) {
      previous(details);
    } else {
      FlutterError.presentError(details);
    }

    debugPrint('JR CALL Flutter error: ${details.exceptionAsString()}');

    final StackTrace? stack = details.stack;

    if (stack != null) {
      debugPrintStack(label: 'JR CALL Flutter error', stackTrace: stack);
    }
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return const Material(
      color: JrColors.background,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: _FatalDisplayError(),
          ),
        ),
      ),
    );
  };
}

// ===============================================================
// AUTHENTICATED CALL INFRASTRUCTURE PRE-WARM
// ===============================================================

Future<void> _prewarmCallInfrastructure() async {
  if (AuthService.instance.currentUser == null) {
    return;
  }

  try {
    await StunTurnService.instance.loadTokenInitialization();

    debugPrint('JR CALL: STUN/TURN pre-warmed.');
  } catch (error, stackTrace) {
    debugPrint('JR CALL: STUN/TURN pre-warm fallback: $error');

    debugPrintStack(
      label: 'JR CALL STUN/TURN pre-warm',
      stackTrace: stackTrace,
    );
  }
}

// ===============================================================
// APP
// ===============================================================

class JRCallApp extends StatelessWidget {
  const JRCallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JR CALL',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: _buildApplicationTheme(),
      home: const SessionGate(),
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData media = MediaQuery.of(context);

        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.35,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

// ===============================================================
// SESSION GATE
//
// AUTHENTICATED:
//   -> HomeScreen(initialIndex: 0)
//   -> Call surface
//   -> STUN/TURN pre-warm once
//
// SIGNED OUT / GUEST:
//   -> HomeScreen(initialIndex: 2)
//   -> Public Media immediately
//
// IMPORTANT:
//   -> WelcomeScreen is NOT startup.
//   -> Login/Create appears only when a protected action requires it.
// ===============================================================

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  final AuthService _auth = AuthService.instance;

  String? _prewarmedUid;

  void _schedulePrewarm(User? user) {
    final String uid = user?.uid.trim() ?? '';

    if (uid.isEmpty) {
      _prewarmedUid = null;
      return;
    }

    if (_prewarmedUid == uid) {
      return;
    }

    _prewarmedUid = uid;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      if (_auth.currentUser?.uid != uid) {
        return;
      }

      unawaited(_prewarmCallInfrastructure());
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _auth.userChanges,
      initialData: _auth.currentUser,
      builder: (BuildContext context, AsyncSnapshot<User?> snapshot) {
        final User? user = snapshot.hasError
            ? _auth.currentUser
            : snapshot.data;

        if (user == null) {
          _prewarmedUid = null;

          return const HomeScreen(initialIndex: 2);
        }

        _schedulePrewarm(user);

        return const HomeScreen(initialIndex: 0);
      },
    );
  }
}

// ===============================================================
// APPLICATION THEME
// ===============================================================

ThemeData _buildApplicationTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: JrColors.primaryBlue,
    brightness: Brightness.light,
    primary: JrColors.primaryBlue,
    error: JrColors.error,
    surface: JrColors.surface,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: JrColors.background,
    canvasColor: JrColors.background,
    disabledColor: JrColors.disabled,
    dividerColor: JrColors.divider,

    // ===========================================================
    // TYPOGRAPHY
    // ===========================================================
    textTheme:
        TextTheme(
          displayLarge: JrTypography.brandLarge,
          displayMedium: JrTypography.brandTitle,
          headlineLarge: JrTypography.screenTitle,
          headlineMedium: JrTypography.sectionTitle,
          bodyLarge: JrTypography.bodyLarge,
          bodyMedium: JrTypography.body,
          bodySmall: JrTypography.bodySmall,
          labelLarge: JrTypography.buttonLabel,
          labelMedium: JrTypography.navigationLabel,
          labelSmall: JrTypography.metadata,
        ).apply(
          bodyColor: JrColors.textPrimary,
          displayColor: JrColors.textPrimary,
        ),

    // ===========================================================
    // APP BAR
    // ===========================================================
    appBarTheme: const AppBarTheme(
      backgroundColor: JrColors.background,
      foregroundColor: JrColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),

    // ===========================================================
    // FILLED BUTTON
    // ===========================================================
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll<Size>(Size.fromHeight(54)),
        backgroundColor: WidgetStateProperty.resolveWith<Color>((
          Set<WidgetState> states,
        ) {
          if (states.contains(WidgetState.disabled)) {
            return JrColors.disabled;
          }

          return JrColors.primaryBlue;
        }),
        foregroundColor: const WidgetStatePropertyAll<Color>(Colors.white),
        overlayColor: WidgetStatePropertyAll<Color>(
          Colors.white.withValues(alpha: 0.10),
        ),
        textStyle: const WidgetStatePropertyAll<TextStyle>(
          JrTypography.buttonLabel,
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
    ),

    // ===========================================================
    // OUTLINED BUTTON
    // ===========================================================
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll<Size>(Size.fromHeight(54)),
        foregroundColor: const WidgetStatePropertyAll<Color>(
          JrColors.primaryBlue,
        ),
        textStyle: const WidgetStatePropertyAll<TextStyle>(
          JrTypography.buttonLabel,
        ),
        side: WidgetStateProperty.resolveWith<BorderSide>((
          Set<WidgetState> states,
        ) {
          return BorderSide(
            color: states.contains(WidgetState.disabled)
                ? JrColors.disabled
                : JrColors.border,
            width: 1.2,
          );
        }),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
    ),

    // ===========================================================
    // INPUT
    // ===========================================================
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: JrColors.surface,
      hintStyle: JrTypography.inputHint,
      labelStyle: JrTypography.inputLabel,
      errorStyle: JrTypography.inputError,
      prefixIconColor: JrColors.primaryBlue,
      suffixIconColor: JrColors.textSecondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      enabledBorder: _inputBorder(JrColors.border),
      focusedBorder: _inputBorder(JrColors.primaryBlue, width: 1.5),
      errorBorder: _inputBorder(JrColors.error),
      focusedErrorBorder: _inputBorder(JrColors.error, width: 1.5),
      disabledBorder: _inputBorder(JrColors.disabled),
    ),

    // ===========================================================
    // CARD
    // ===========================================================
    cardTheme: CardThemeData(
      color: JrColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: JrColors.border),
      ),
    ),

    // ===========================================================
    // DIALOG
    // ===========================================================
    dialogTheme: DialogThemeData(
      backgroundColor: JrColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: JrTypography.sectionTitle,
      contentTextStyle: JrTypography.bodySecondary,
    ),

    // ===========================================================
    // SNACKBAR
    // ===========================================================
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: JrColors.textPrimary,
      contentTextStyle: JrTypography.body.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),

    // ===========================================================
    // PROGRESS
    // ===========================================================
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: JrColors.primaryBlue,
    ),
  );
}

// ===============================================================
// INPUT BORDER
// ===============================================================

OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(18),
    borderSide: BorderSide(color: color, width: width),
  );
}

// ===============================================================
// DISPLAY ERROR FALLBACK
// ===============================================================

class _FatalDisplayError extends StatelessWidget {
  const _FatalDisplayError();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(
          Icons.error_outline_rounded,
          color: JrColors.error,
          size: 48,
        ),
        const SizedBox(height: 16),
        Text('JR CALL', style: JrTypography.sectionTitle),
        const SizedBox(height: 8),
        Text(
          'Something went wrong while displaying this screen.',
          textAlign: TextAlign.center,
          style: JrTypography.bodySecondary,
        ),
      ],
    );
  }
}

// ===============================================================
// FIREBASE BOOTSTRAP ERROR
// ===============================================================

class JRCallBootstrapErrorApp extends StatelessWidget {
  const JRCallBootstrapErrorApp({required this.error, super.key});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JR CALL',
      debugShowCheckedModeBanner: false,
      theme: _buildApplicationTheme(),
      home: Scaffold(
        backgroundColor: JrColors.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color: JrColors.surface,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: JrColors.border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(
                        Icons.cloud_off_rounded,
                        size: 56,
                        color: JrColors.error,
                      ),
                      const SizedBox(height: 18),
                      Text('JR CALL', style: JrTypography.brandTitle),
                      const SizedBox(height: 10),
                      Text(
                        'Application initialization failed.',
                        textAlign: TextAlign.center,
                        style: JrTypography.sectionTitle,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please check the Firebase configuration '
                        'and restart the application.',
                        textAlign: TextAlign.center,
                        style: JrTypography.bodySecondary,
                      ),
                      if (kDebugMode) ...<Widget>[
                        const SizedBox(height: 20),
                        Text(
                          error.toString(),
                          textAlign: TextAlign.center,
                          style: JrTypography.metadata,
                        ),
                      ],
                    ],
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

// ===============================================================
// END OF FILE
//
// FINAL STARTUP:
//
// Signed-out / Guest
//   -> HomeScreen(initialIndex: 2)
//   -> PUBLIC MEDIA
//
// Authenticated
//   -> HomeScreen(initialIndex: 0)
//   -> CALL
//
// WelcomeScreen
//   -> NOT used as startup gate
//   -> remains available for Login/Create protected flows
//
// Call Engine / WebRTC untouched.
// ===============================================================
