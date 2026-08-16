import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';

/// ===========================================================
/// JR CALL
/// File: forgot_password_screen.dart
/// Location: lib/screens/forgot_password_screen.dart
///
/// Description:
/// Production email password recovery screen for JR CALL.
///
/// Responsibilities:
/// - Accept an email address.
/// - Validate and normalize the email.
/// - Send Firebase password-reset email through AuthService.
/// - Prevent duplicate reset requests.
/// - Apply resend cooldown.
/// - Provide safe loading / success / error states.
/// - Preserve existing `initialValue` constructor compatibility.
///
/// Security / Architecture:
/// - Email password reset is handled by Firebase Authentication.
/// - Phone authentication/recovery remains Firebase SMS OTP.
/// - This screen does NOT generate OTP.
/// - This screen does NOT store passwords or OTPs.
/// - This screen does NOT sign a user in.
/// - This screen does NOT route directly to Home.
/// - Firebase reset link is responsible for secure password change.
/// ===========================================================

class ForgotPasswordScreen extends StatefulWidget {
  /// Existing JR CALL constructor compatibility.
  ///
  /// LoginScreen may pass the currently entered value.
  /// It is pre-filled only when it looks like an email address.
  final String initialValue;

  const ForgotPasswordScreen({super.key, this.initialValue = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  // ===========================================================
  // Constants
  // ===========================================================

  static const int _resendCooldownSeconds = 60;

  // ===========================================================
  // Services
  // ===========================================================

  final AuthService _authService = AuthService.instance;

  // ===========================================================
  // Controllers / Focus
  // ===========================================================

  final TextEditingController _emailController = TextEditingController();

  final FocusNode _emailFocusNode = FocusNode();

  // ===========================================================
  // Runtime State
  // ===========================================================

  Timer? _cooldownTimer;

  bool _loading = false;
  bool _requestCompleted = false;

  int _remainingCooldown = 0;

  String _lastRequestedEmail = '';

  // ===========================================================
  // Lifecycle
  // ===========================================================

  @override
  void initState() {
    super.initState();

    final initialEmail = widget.initialValue.trim();

    if (_looksLikeEmail(initialEmail)) {
      _emailController.text = initialEmail;
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();

    _emailController.dispose();
    _emailFocusNode.dispose();

    super.dispose();
  }

  // ===========================================================
  // Password Reset
  // ===========================================================

  Future<void> _sendResetEmail() async {
    if (_loading || _remainingCooldown > 0) {
      return;
    }

    FocusScope.of(context).unfocus();

    final email = _normalizeEmail(_emailController.text);

    if (email.isEmpty) {
      _showMessage('আপনার JR CALL account-এর Email address দিন।');
      return;
    }

    if (!_isValidEmail(email)) {
      _showMessage('সঠিক Email address দিন।');
      return;
    }

    _setLoading(true);

    try {
      await _authService.sendPasswordResetEmail(email: email);

      if (!mounted) {
        return;
      }

      TextInput.finishAutofillContext(shouldSave: false);

      setState(() {
        _requestCompleted = true;
        _lastRequestedEmail = email;
      });

      _startCooldown();

      _showSuccessMessage(
        'Password reset Email পাঠানো হয়েছে। '
        'Inbox এবং Spam/Junk folder check করুন।',
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(_firebaseAuthMessage(error));
    } on ArgumentError catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(error.message?.toString() ?? 'Email address সঠিক নয়।');
    } catch (error, stackTrace) {
      debugPrint('JR CALL forgot-password error: $error');

      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      _showMessage(
        'Password reset request সম্পন্ন করা যায়নি। '
        'Internet connection check করে আবার চেষ্টা করুন।',
      );
    } finally {
      if (mounted) {
        _setLoading(false);
      }
    }
  }

  // ===========================================================
  // Cooldown
  // ===========================================================

  void _startCooldown() {
    _cooldownTimer?.cancel();

    setState(() {
      _remainingCooldown = _resendCooldownSeconds;
    });

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_remainingCooldown <= 1) {
        timer.cancel();

        setState(() {
          _remainingCooldown = 0;
        });

        return;
      }

      setState(() {
        _remainingCooldown--;
      });
    });
  }

  // ===========================================================
  // Validation / Normalization
  // ===========================================================

  String _normalizeEmail(String value) {
    return value.trim().toLowerCase();
  }

  bool _looksLikeEmail(String value) {
    final normalized = value.trim();

    return normalized.contains('@') && normalized.contains('.');
  }

  bool _isValidEmail(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty || normalized.length > 254) {
      return false;
    }

    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized);
  }

  // ===========================================================
  // Firebase Error Mapping
  // ===========================================================

  String _firebaseAuthMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-email':
        return 'Email address সঠিক নয়।';

      case 'user-disabled':
        return 'এই JR CALL account বর্তমানে disabled।';

      case 'operation-not-allowed':
        return 'Email/Password authentication বর্তমানে available নয়।';

      case 'too-many-requests':
        return 'অনেকবার reset request করা হয়েছে। '
            'কিছুক্ষণ পরে আবার চেষ্টা করুন।';

      case 'network-request-failed':
        return 'Internet connection check করুন।';

      case 'app-not-authorized':
        return 'Firebase Authentication app configuration '
            'verify করা প্রয়োজন।';

      case 'invalid-app-credential':
        return 'Firebase application verification ব্যর্থ হয়েছে।';

      case 'missing-email':
        return 'Email address দিন।';

      default:
        return error.message ?? 'Password reset request সম্পন্ন হয়নি।';
    }
  }

  // ===========================================================
  // UI State
  // ===========================================================

  void _setLoading(bool value) {
    if (!mounted || _loading == value) {
      return;
    }

    setState(() {
      _loading = value;
    });
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  void _showSuccessMessage(String message) {
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF15803D),
        ),
      );
  }

  // ===========================================================
  // UI Helpers
  // ===========================================================

  InputDecoration _emailDecoration() {
    const borderColor = Color(0xFFDCE4F0);
    const primaryBlue = Color(0xFF1769FF);

    return InputDecoration(
      labelText: 'Email Address',
      hintText: 'name@example.com',
      prefixIcon: const Icon(Icons.email_outlined, color: primaryBlue),
      filled: true,
      fillColor: const Color(0xFFF9FBFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: primaryBlue, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: borderColor),
      ),
    );
  }

  String get _primaryButtonText {
    if (_loading) {
      return '';
    }

    if (_requestCompleted) {
      return 'RESET EMAIL SENT';
    }

    return 'SEND RESET EMAIL';
  }

  // ===========================================================
  // Build
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFFF5F8FD);
    const textPrimary = Color(0xFF0F172A);
    const textSecondary = Color(0xFF64748B);
    const primaryBlue = Color(0xFF1769FF);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Account Recovery',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 50,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: const Color(0xFFDCE4F0)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x120F172A),
                            blurRadius: 28,
                            offset: Offset(0, 12),
                          ),
                          BoxShadow(
                            color: Color(0x0A1769FF),
                            blurRadius: 34,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Container(
                                width: 90,
                                height: 90,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFFEAF2FF),
                                      Color(0xFFF4F0FF),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0x221769FF),
                                      blurRadius: 24,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.lock_reset_rounded,
                                  size: 46,
                                  color: primaryBlue,
                                ),
                              ),
                            ),

                            const SizedBox(height: 22),

                            const Text(
                              'Reset Your Password',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 27,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                              ),
                            ),

                            const SizedBox(height: 10),

                            const Text(
                              'আপনার JR CALL Email account-এর Email address দিন। '
                              'আমরা একটি secure password-reset link পাঠাব।',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),

                            const SizedBox(height: 28),

                            TextField(
                              controller: _emailController,
                              focusNode: _emailFocusNode,
                              enabled: !_loading,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.email],
                              autocorrect: false,
                              enableSuggestions: false,
                              smartDashesType: SmartDashesType.disabled,
                              smartQuotesType: SmartQuotesType.disabled,
                              textCapitalization: TextCapitalization.none,
                              style: const TextStyle(
                                color: textPrimary,
                                fontSize: 15,
                              ),
                              onSubmitted: (_) {
                                if (!_loading && _remainingCooldown == 0) {
                                  _sendResetEmail();
                                }
                              },
                              decoration: _emailDecoration(),
                            ),

                            const SizedBox(height: 22),

                            SizedBox(
                              height: 56,
                              child: FilledButton(
                                onPressed: _loading || _remainingCooldown > 0
                                    ? null
                                    : _sendResetEmail,
                                style: FilledButton.styleFrom(
                                  backgroundColor: primaryBlue,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: _requestCompleted
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFFA7C7FF),
                                  disabledForegroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: _loading
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _requestCompleted
                                                ? Icons.check_circle_outline
                                                : Icons
                                                      .mark_email_unread_outlined,
                                          ),
                                          const SizedBox(width: 9),
                                          Flexible(
                                            child: Text(
                                              _primaryButtonText,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),

                            if (_requestCompleted) ...[
                              const SizedBox(height: 16),

                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: const Color(0xFFBBF7D0),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.mark_email_read_outlined,
                                      color: Color(0xFF15803D),
                                      size: 21,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _lastRequestedEmail.isEmpty
                                            ? 'Reset Email পাঠানো হয়েছে। Inbox এবং Spam/Junk folder check করুন।'
                                            : 'Reset link $_lastRequestedEmail ঠিকানায় পাঠানো হয়েছে। Inbox এবং Spam/Junk folder check করুন।',
                                        style: const TextStyle(
                                          color: Color(0xFF166534),
                                          fontSize: 13,
                                          height: 1.45,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 12),

                              OutlinedButton.icon(
                                onPressed: _remainingCooldown > 0 || _loading
                                    ? null
                                    : _sendResetEmail,
                                icon: const Icon(Icons.refresh_rounded),
                                label: Text(
                                  _remainingCooldown > 0
                                      ? 'SEND AGAIN IN ${_remainingCooldown}s'
                                      : 'SEND AGAIN',
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primaryBlue,
                                  side: const BorderSide(
                                    color: Color(0xFFBFDBFE),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ],

                            const SizedBox(height: 22),

                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFE8EEF6),
                                ),
                              ),
                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.verified_user_outlined,
                                    color: textSecondary,
                                    size: 20,
                                  ),
                                  SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      'Phone-only JR CALL account-এর জন্য password reset প্রয়োজন নেই। '
                                      'Login screen থেকে Phone নির্বাচন করে Firebase SMS OTP দিয়ে login করুন।',
                                      style: TextStyle(
                                        color: textSecondary,
                                        fontSize: 12,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 14),

                            TextButton.icon(
                              onPressed: _loading
                                  ? null
                                  : () {
                                      Navigator.of(context).pop();
                                    },
                              icon: const Icon(Icons.arrow_back_rounded),
                              label: const Text(
                                'BACK TO LOGIN',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
