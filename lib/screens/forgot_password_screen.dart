// ===============================================================
// JR CALL
// File: forgot_password_screen.dart
// Location: lib/screens/forgot_password_screen.dart
//
// OTP / AUTH MASTER FILE 07 / 09
//
// PRODUCTION PASSWORD RECOVERY ENTRY COORDINATOR
//
// ===============================================================
//
// FINAL JR CALL AUTH CONTRACT:
//
// NORMAL EMAIL LOGIN:
//
// Email + Password
//      ↓
// Firebase Authentication
//      ↓
// Direct Login
//
// ✓ Normal Email Login does NOT require Email OTP.
// ✓ Normal Email Login does NOT require Email verification.
//
// PASSWORD RECOVERY:
//
// Email
//      ↓
// New Password + Confirm Password
//      ↓
// AuthService.sendPasswordRecoveryOtp()
//      ↓
// JR CALL Cloud Functions backend
//      ↓
// Recovery OTP delivered to Email
//      ↓
// OtpScreen
//      ↓
// AuthService.verifyPasswordRecoveryOtp()
//      ↓
// Backend Firebase Admin password update
//      ↓
// Refresh tokens revoked
//      ↓
// Return TRUE
//      ↓
// Password Updated
//
// IMPORTANT:
//
// ✓ ForgotPasswordScreen does NOT verify OTP itself.
// ✓ ForgotPasswordScreen does NOT resend OTP itself.
// ✓ OtpScreen is the single OTP-entry / verify / resend owner.
// ✓ AuthService owns authentication/backend coordination.
// ✓ Password recovery OTP remains backend-owned.
// ✓ Password remains memory-only.
// ✓ OTP remains memory-only.
// ✓ No raw Password persistence.
// ✓ No raw OTP persistence.
// ✓ No Firebase reset Email link required.
// ✓ No fake/local OTP.
// ✓ No account-existence disclosure.
// ✓ Phone Signup OTP untouched.
// ✓ Phone Login OTP untouched.
// ✓ Phone Change OTP untouched.
// ✓ Multiple-device Firebase login behavior untouched.
// ✓ Call Engine untouched.
// ✓ Message Engine untouched.
// ✓ WebRTC untouched.
// ✓ Signaling untouched.
// ===============================================================

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import 'otp_screen.dart';

// ===============================================================
// RECOVERY STEP
// ===============================================================

enum _RecoveryStep {
  form,
  success,
}

// ===============================================================
// SCREEN
// ===============================================================

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    super.key,
    this.initialValue = '',
  });

  final String initialValue;

  @override
  State<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

// ===============================================================
// STATE
// ===============================================================

class _ForgotPasswordScreenState
    extends State<ForgotPasswordScreen> {
  // =============================================================
  // SERVICE
  // =============================================================

  final AuthService _authService = AuthService.instance;

  // =============================================================
  // CONTROLLERS
  // =============================================================

  final TextEditingController _emailController =
  TextEditingController();

  final TextEditingController _passwordController =
  TextEditingController();

  final TextEditingController _confirmPasswordController =
  TextEditingController();

  // =============================================================
  // FOCUS
  // =============================================================

  final FocusNode _emailFocusNode = FocusNode();

  final FocusNode _passwordFocusNode = FocusNode();

  final FocusNode _confirmPasswordFocusNode = FocusNode();

  // =============================================================
  // STATE
  // =============================================================

  _RecoveryStep _step = _RecoveryStep.form;

  bool _loading = false;

  bool _otpRouteRunning = false;

  bool _showPassword = false;

  bool _showConfirmPassword = false;

  bool _completed = false;

  String _recoveryEmail = '';

  // =============================================================
  // DERIVED STATE
  // =============================================================

  bool get _busy {
    return _loading ||
        _otpRouteRunning ||
        _completed;
  }

  // =============================================================
  // LIFECYCLE
  // =============================================================

  @override
  void initState() {
    super.initState();

    final String initialEmail = _normalizeEmail(
      widget.initialValue,
    );

    if (_isValidEmail(initialEmail)) {
      _emailController.text = initialEmail;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();

    _passwordController.dispose();

    _confirmPasswordController.dispose();

    _emailFocusNode.dispose();

    _passwordFocusNode.dispose();

    _confirmPasswordFocusNode.dispose();

    super.dispose();
  }

  // =============================================================
  // START PASSWORD RECOVERY
  // =============================================================

  Future<void> _startRecovery() async {
    if (_busy) {
      return;
    }

    FocusScope.of(context).unfocus();

    final String email = _normalizeEmail(
      _emailController.text,
    );

    final String newPassword =
        _passwordController.text;

    final String confirmation =
        _confirmPasswordController.text;

    if (!_isValidEmail(email)) {
      _showMessage(
        'Enter a valid Email address.',
      );

      return;
    }

    final String? passwordError =
    _validatePassword(
      newPassword,
      confirmation,
    );

    if (passwordError != null) {
      _showMessage(
        passwordError,
      );

      return;
    }

    _setLoading(true);

    try {
      final PasswordRecoveryChallenge challenge =
      await _authService.sendPasswordRecoveryOtp(
        email: email,
      );

      if (!mounted) {
        return;
      }

      if (!challenge.accepted) {
        throw StateError(
          'Password recovery could not be started.',
        );
      }

      final String challengeId =
          challenge.challengeId?.trim() ?? '';

      if (challengeId.isEmpty) {
        throw StateError(
          'Password recovery session could not be created.',
        );
      }

      _recoveryEmail = email;

      TextInput.finishAutofillContext(
        shouldSave: false,
      );

      _setLoading(false);

      final bool verified =
      await _openOtpScreen(
        challengeId: challengeId,
        email: email,
        newPassword: newPassword,
        resendAfterSeconds:
        challenge.resendAfterSeconds,
      );

      if (!mounted) {
        return;
      }

      if (!verified) {
        return;
      }

      _passwordController.clear();

      _confirmPasswordController.clear();

      setState(() {
        _completed = true;
        _step = _RecoveryStep.success;
      });
    } on FirebaseFunctionsException catch (error) {
      _showMessage(
        _functionsMessage(error),
      );
    } on FirebaseAuthException catch (error) {
      _showMessage(
        _firebaseAuthMessage(error),
      );
    } on ArgumentError catch (error) {
      _showMessage(
        error.message?.toString() ??
            'Invalid recovery information.',
      );
    } on StateError catch (error) {
      _showMessage(
        error.message,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'JR CALL password recovery start error: $error',
      );

      debugPrintStack(
        label:
        'JR CALL password recovery start',
        stackTrace: stackTrace,
      );

      _showMessage(
        'Password recovery could not be started. '
            'Please try again.',
      );
    } finally {
      if (mounted &&
          !_otpRouteRunning &&
          !_completed) {
        _setLoading(false);
      }
    }
  }

  // =============================================================
  // OPEN OTP SCREEN
  //
  // OtpScreen owns:
  //
  // ✓ OTP entry.
  // ✓ OTP verification.
  // ✓ OTP resend.
  // ✓ OTP cooldown.
  // ✓ Recovery completion.
  //
  // This screen only starts the recovery challenge and receives
  // the final TRUE/FALSE result.
  // =============================================================

  Future<bool> _openOtpScreen({
    required String challengeId,
    required String email,
    required String newPassword,
    required int resendAfterSeconds,
  }) async {
    if (!mounted ||
        _otpRouteRunning) {
      return false;
    }

    _otpRouteRunning = true;

    try {
      final bool? result =
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          settings: RouteSettings(
            arguments: <String, dynamic>{
              'mode': 'passwordRecovery',
              'passwordRecoveryChallengeId':
              challengeId,
              'challengeId': challengeId,
              'resendAfterSeconds':
              resendAfterSeconds,

              // -------------------------------------------------
              // Compatibility fallback.
              //
              // OtpScreen receives newPassword directly below.
              // This route value preserves the existing fallback
              // API without persisting the Password anywhere.
              // -------------------------------------------------

              'newPassword': newPassword,
            },
          ),
          builder: (
              BuildContext context,
              ) {
            return OtpScreen(
              verificationId: challengeId,
              phoneNumber: '',
              email: email,
              password: newPassword,
              provider: 'password_recovery',
            );
          },
        ),
      );

      return result == true;
    } finally {
      _otpRouteRunning = false;
    }
  }

  // =============================================================
  // BACK
  // =============================================================

  void _goBack() {
    if (_loading ||
        _otpRouteRunning) {
      return;
    }

    Navigator.of(context).maybePop();
  }

  void _returnToLogin() {
    if (!mounted) {
      return;
    }

    Navigator.of(context).pop();
  }

  // =============================================================
  // NORMALIZATION
  // =============================================================

  String _normalizeEmail(
      String value,
      ) {
    return value
        .trim()
        .toLowerCase();
  }

  // =============================================================
  // VALIDATION — EMAIL
  // =============================================================

  bool _isValidEmail(
      String value,
      ) {
    return value.isNotEmpty &&
        value.length <= 254 &&
        RegExp(
          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
        ).hasMatch(value);
  }

  // =============================================================
  // VALIDATION — PASSWORD
  // =============================================================

  String? _validatePassword(
      String password,
      String confirmation,
      ) {
    if (password.isEmpty) {
      return 'Enter a new password.';
    }

    if (password.length < 6) {
      return 'Password must contain at least 6 characters.';
    }

    if (password.length > 4096) {
      return 'Password is too long.';
    }

    if (password != confirmation) {
      return 'Password and Confirm Password do not match.';
    }

    return null;
  }

  // =============================================================
  // CLOUD FUNCTIONS ERROR
  // =============================================================

  String _functionsMessage(
      FirebaseFunctionsException error,
      ) {
    switch (error.code) {
      case 'invalid-argument':
        return error.message ??
            'Recovery information is invalid.';

      case 'deadline-exceeded':
        return 'The recovery session expired. '
            'Request a new code.';

      case 'resource-exhausted':
        return error.message ??
            'Too many recovery requests. '
                'Please try again later.';

      case 'failed-precondition':
        return error.message ??
            'Password recovery cannot continue right now.';

      case 'permission-denied':
        return error.message ??
            'Password recovery was not authorized.';

      case 'not-found':
        return 'The password recovery service is unavailable.';

      case 'unauthenticated':
        return 'The authentication session is no longer valid.';

      case 'unavailable':
        return 'Password recovery service is temporarily unavailable.';

      case 'internal':
        return 'Password recovery service encountered an internal error.';

      default:
        return error.message ??
            'Password recovery could not be started.';
    }
  }

  // =============================================================
  // FIREBASE AUTH ERROR
  // =============================================================

  String _firebaseAuthMessage(
      FirebaseAuthException error,
      ) {
    switch (error.code) {
      case 'invalid-email':
        return 'Enter a valid Email address.';

      case 'weak-password':
        return 'Password must contain at least 6 characters.';

      case 'user-disabled':
        return 'This JR CALL account is currently unavailable.';

      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';

      case 'network-request-failed':
        return 'Check your Internet connection and try again.';

      case 'operation-not-allowed':
        return 'Email/Password authentication is currently unavailable.';

      case 'app-not-authorized':
        return 'Firebase could not authorize this application.';

      case 'invalid-app-credential':
        return 'Firebase could not verify this application.';

      default:
        return error.message ??
            'Authentication failed.';
    }
  }

  // =============================================================
  // STATE HELPERS
  // =============================================================

  void _setLoading(
      bool value,
      ) {
    if (!mounted ||
        _loading == value) {
      return;
    }

    setState(() {
      _loading = value;
    });
  }

  void _showMessage(
      String message,
      ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
          ),
          behavior:
          SnackBarBehavior.floating,
        ),
      );
  }

  // =============================================================
  // FIELD DECORATION
  // =============================================================

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    const Color borderColor =
    Color(0xFFDCE4F0);

    const Color primaryBlue =
    Color(0xFF1769FF);

    OutlineInputBorder border(
        Color color, [
          double width = 1,
        ]) {
      return OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(
          16,
        ),
        borderSide: BorderSide(
          color: color,
          width: width,
        ),
      );
    }

    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(
        icon,
        color: primaryBlue,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor:
      const Color(
        0xFFF9FBFF,
      ),
      contentPadding:
      const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 18,
      ),
      border:
      border(
        borderColor,
      ),
      enabledBorder:
      border(
        borderColor,
      ),
      focusedBorder:
      border(
        primaryBlue,
        1.5,
      ),
      disabledBorder:
      border(
        borderColor,
      ),
    );
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    const Color background =
    Color(0xFFF5F8FD);

    const Color textPrimary =
    Color(0xFF0F172A);

    return PopScope(
      canPop:
      !_loading &&
          !_otpRouteRunning,
      child: Scaffold(
        backgroundColor: background,
        appBar: AppBar(
          backgroundColor: background,
          foregroundColor: textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            onPressed:
            _loading ||
                _otpRouteRunning
                ? null
                : _goBack,
            icon: const Icon(
              Icons.arrow_back_rounded,
            ),
          ),
          title: const Text(
            'Account Recovery',
            style: TextStyle(
              fontWeight:
              FontWeight.w800,
            ),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior:
              ScrollViewKeyboardDismissBehavior
                  .onDrag,
              padding:
              const EdgeInsets.fromLTRB(
                20,
                20,
                20,
                32,
              ),
              child: ConstrainedBox(
                constraints:
                const BoxConstraints(
                  maxWidth: 520,
                ),
                child: Container(
                  width:
                  double.infinity,
                  padding:
                  const EdgeInsets.fromLTRB(
                    22,
                    28,
                    22,
                    24,
                  ),
                  decoration:
                  BoxDecoration(
                    color:
                    Colors.white.withValues(
                      alpha: 0.96,
                    ),
                    borderRadius:
                    BorderRadius.circular(
                      28,
                    ),
                    border:
                    Border.all(
                      color:
                      const Color(
                        0xFFDCE4F0,
                      ),
                    ),
                    boxShadow:
                    const <BoxShadow>[
                      BoxShadow(
                        color:
                        Color(
                          0x120F172A,
                        ),
                        blurRadius: 28,
                        offset:
                        Offset(
                          0,
                          12,
                        ),
                      ),
                    ],
                  ),
                  child:
                  AnimatedSwitcher(
                    duration:
                    const Duration(
                      milliseconds: 200,
                    ),
                    child:
                    _step ==
                        _RecoveryStep
                            .success
                        ? _buildSuccessStep()
                        : _buildRecoveryForm(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =============================================================
  // RECOVERY FORM
  // =============================================================

  Widget _buildRecoveryForm() {
    return AutofillGroup(
      key:
      const ValueKey<String>(
        'recovery-form',
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.stretch,
        children: <Widget>[
          _recoveryIcon(
            Icons.lock_reset_rounded,
          ),

          const SizedBox(
            height: 22,
          ),

          const Text(
            'Reset Your Password',
            textAlign:
            TextAlign.center,
            style: TextStyle(
              color:
              Color(
                0xFF0F172A,
              ),
              fontSize: 27,
              fontWeight:
              FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),

          const SizedBox(
            height: 10,
          ),

          const Text(
            'Enter your Email and choose a new password. '
                'JR CALL will send a secure 6-digit recovery code.',
            textAlign:
            TextAlign.center,
            style: TextStyle(
              color:
              Color(
                0xFF64748B,
              ),
              fontSize: 14,
              height: 1.5,
            ),
          ),

          const SizedBox(
            height: 28,
          ),

          TextField(
            controller:
            _emailController,
            focusNode:
            _emailFocusNode,
            enabled:
            !_busy,
            keyboardType:
            TextInputType.emailAddress,
            textInputAction:
            TextInputAction.next,
            autofillHints:
            const <String>[
              AutofillHints.email,
            ],
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization:
            TextCapitalization.none,
            onSubmitted: (_) {
              _passwordFocusNode
                  .requestFocus();
            },
            decoration:
            _fieldDecoration(
              label: 'Email Address',
              icon:
              Icons.email_outlined,
            ),
          ),

          const SizedBox(
            height: 14,
          ),

          TextField(
            controller:
            _passwordController,
            focusNode:
            _passwordFocusNode,
            enabled:
            !_busy,
            obscureText:
            !_showPassword,
            keyboardType:
            TextInputType.visiblePassword,
            textInputAction:
            TextInputAction.next,
            autofillHints:
            const <String>[
              AutofillHints.newPassword,
            ],
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) {
              _confirmPasswordFocusNode
                  .requestFocus();
            },
            decoration:
            _fieldDecoration(
              label: 'New Password',
              icon:
              Icons.lock_outline,
              suffixIcon:
              IconButton(
                onPressed:
                _busy
                    ? null
                    : () {
                  setState(() {
                    _showPassword =
                    !_showPassword;
                  });
                },
                icon: Icon(
                  _showPassword
                      ? Icons.visibility_off
                      : Icons.visibility,
                ),
              ),
            ),
          ),

          const SizedBox(
            height: 14,
          ),

          TextField(
            controller:
            _confirmPasswordController,
            focusNode:
            _confirmPasswordFocusNode,
            enabled:
            !_busy,
            obscureText:
            !_showConfirmPassword,
            keyboardType:
            TextInputType.visiblePassword,
            textInputAction:
            TextInputAction.done,
            autofillHints:
            const <String>[
              AutofillHints.newPassword,
            ],
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) {
              if (!_busy) {
                unawaited(
                  _startRecovery(),
                );
              }
            },
            decoration:
            _fieldDecoration(
              label:
              'Confirm New Password',
              icon:
              Icons.lock_reset_outlined,
              suffixIcon:
              IconButton(
                onPressed:
                _busy
                    ? null
                    : () {
                  setState(() {
                    _showConfirmPassword =
                    !_showConfirmPassword;
                  });
                },
                icon: Icon(
                  _showConfirmPassword
                      ? Icons.visibility_off
                      : Icons.visibility,
                ),
              ),
            ),
          ),

          const SizedBox(
            height: 22,
          ),

          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed:
              _busy
                  ? null
                  : _startRecovery,
              style:
              FilledButton.styleFrom(
                backgroundColor:
                const Color(
                  0xFF1769FF,
                ),
                foregroundColor:
                Colors.white,
                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(
                    16,
                  ),
                ),
              ),
              child:
              _loading
                  ? const SizedBox(
                width: 24,
                height: 24,
                child:
                CircularProgressIndicator(
                  strokeWidth:
                  2.4,
                  color:
                  Colors.white,
                ),
              )
                  : const Text(
                'SEND RECOVERY CODE',
                style:
                TextStyle(
                  fontSize: 15,
                  fontWeight:
                  FontWeight.w800,
                ),
              ),
            ),
          ),

          const SizedBox(
            height: 22,
          ),

          _securityNotice(
            'For privacy, JR CALL does not reveal whether an Email '
                'address is registered. The recovery OTP and new password '
                'are never stored on this screen or in Firestore.',
          ),

          const SizedBox(
            height: 14,
          ),

          TextButton.icon(
            onPressed:
            _busy
                ? null
                : _returnToLogin,
            icon: const Icon(
              Icons.arrow_back_rounded,
            ),
            label: const Text(
              'BACK TO LOGIN',
              style: TextStyle(
                fontWeight:
                FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =============================================================
  // SUCCESS
  // =============================================================

  Widget _buildSuccessStep() {
    return Column(
      key:
      const ValueKey<String>(
        'recovery-success',
      ),
      crossAxisAlignment:
      CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: Container(
            width: 90,
            height: 90,
            decoration:
            const BoxDecoration(
              shape:
              BoxShape.circle,
              color:
              Color(
                0xFFF0FDF4,
              ),
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              size: 52,
              color:
              Color(
                0xFF16A34A,
              ),
            ),
          ),
        ),

        const SizedBox(
          height: 22,
        ),

        const Text(
          'Password Updated',
          textAlign:
          TextAlign.center,
          style: TextStyle(
            color:
            Color(
              0xFF0F172A,
            ),
            fontSize: 27,
            fontWeight:
            FontWeight.w800,
          ),
        ),

        const SizedBox(
          height: 10,
        ),

        Text(
          'The password for $_recoveryEmail has been reset successfully.',
          textAlign:
          TextAlign.center,
          style:
          const TextStyle(
            color:
            Color(
              0xFF64748B,
            ),
            fontSize: 14,
            height: 1.5,
          ),
        ),

        const SizedBox(
          height: 28,
        ),

        SizedBox(
          height: 56,
          child:
          FilledButton.icon(
            onPressed:
            _returnToLogin,
            style:
            FilledButton.styleFrom(
              backgroundColor:
              const Color(
                0xFF1769FF,
              ),
              foregroundColor:
              Colors.white,
              shape:
              RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(
                  16,
                ),
              ),
            ),
            icon: const Icon(
              Icons.login_rounded,
            ),
            label: const Text(
              'BACK TO LOGIN',
              style: TextStyle(
                fontSize: 15,
                fontWeight:
                FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // =============================================================
  // UI HELPERS
  // =============================================================

  Widget _recoveryIcon(
      IconData icon,
      ) {
    return Center(
      child: Container(
        width: 90,
        height: 90,
        decoration:
        const BoxDecoration(
          shape:
          BoxShape.circle,
          gradient:
          LinearGradient(
            begin:
            Alignment.topLeft,
            end:
            Alignment.bottomRight,
            colors:
            <Color>[
              Color(
                0xFFEAF2FF,
              ),
              Color(
                0xFFF4F0FF,
              ),
            ],
          ),
        ),
        child: Icon(
          icon,
          size: 46,
          color:
          const Color(
            0xFF1769FF,
          ),
        ),
      ),
    );
  }

  Widget _securityNotice(
      String text,
      ) {
    return Container(
      padding:
      const EdgeInsets.all(
        14,
      ),
      decoration:
      BoxDecoration(
        color:
        const Color(
          0xFFF8FAFC,
        ),
        borderRadius:
        BorderRadius.circular(
          14,
        ),
        border:
        Border.all(
          color:
          const Color(
            0xFFE8EEF6,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.verified_user_outlined,
            color:
            Color(
              0xFF64748B,
            ),
            size: 20,
          ),

          const SizedBox(
            width: 9,
          ),

          Expanded(
            child: Text(
              text,
              style:
              const TextStyle(
                color:
                Color(
                  0xFF64748B,
                ),
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===============================================================
// END OF FILE
//
// OTP / AUTH MASTER FILE 07 / 09
//
// FINAL RESPONSIBILITY:
//
// ForgotPasswordScreen
//      ↓
// AuthService.sendPasswordRecoveryOtp()
//      ↓
// JR CALL Backend
//      ↓
// OtpScreen
//      ↓
// AuthService.verifyPasswordRecoveryOtp()
//      ↓
// Firebase Admin Password Update
//
// GUARANTEES:
//
// ✓ Normal Email Login remains direct Email + Password.
// ✓ Normal Email Login has NO OTP dependency.
// ✓ Password Recovery keeps secure Email OTP.
// ✓ OtpScreen remains single recovery OTP owner.
// ✓ No duplicate OTP verification here.
// ✓ No duplicate resend logic here.
// ✓ No duplicate OTP timer here.
// ✓ No Firebase Password-reset Email-link dependency.
// ✓ Password memory-only.
// ✓ OTP memory-only.
// ✓ No fake/local OTP.
// ✓ No account-enumeration disclosure.
// ✓ Existing initialValue API preserved.
// ✓ Existing recovery UI preserved.
// ✓ Existing success UI preserved.
// ✓ Phone Signup/Login OTP unaffected.
// ✓ Multiple-device Firebase sessions unaffected.
// ✓ Call Engine untouched.
// ✓ Message Engine untouched.
// ✓ WebRTC untouched.
// ✓ Signaling untouched.
//
// REPLACE:
//
// lib/screens/forgot_password_screen.dart
//
// SAVE THIS FILE.
// ===============================================================