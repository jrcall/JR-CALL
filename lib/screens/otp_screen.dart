// ===============================================================
// JR CALL
// File: otp_screen.dart
// Location: lib/screens/otp_screen.dart
//
// OTP / AUTH MASTER FILE 06 / 09
//
// PRODUCTION OTP ENTRY / VERIFY / RESEND COORDINATOR
//
// FINAL JR CALL CONTRACT:
//
// PHONE SIGNUP:
//
// Phone Number
//      ↓
// Firebase Phone Authentication
//      ↓
// Manual / Automatic verification
//      ↓
// Firebase UID
//      ↓
// Return TRUE to CreateAccountScreen
//      ↓
// CreateAccountScreen finalizes profile / optional Email linking
//
// PHONE LOGIN:
//
// Phone Number
//      ↓
// LoginOtpManager
//      ↓
// AuthService
//      ↓
// Firebase Phone Authentication
//      ↓
// Firebase UID
//      ↓
// Existing profile / profile setup
//
// EMAIL LOGIN:
//
// Normal Email + Password Login does NOT use this screen.
// Email Login OTP mode remains compatibility-only.
//
// EMAIL SIGNUP / CHANGE:
//
// Authenticated Firebase UID
//      ↓
// JR CALL backend Email OTP
//      ↓
// verification result
//
// PASSWORD RECOVERY:
//
// ForgotPasswordScreen
//      ↓
// OtpScreen
//      ↓
// AuthService.verifyPasswordRecoveryOtp()
//      ↓
// Backend password reset
//
// IMPORTANT:
//
// ✓ Phone Signup always requires Firebase Phone verification.
// ✓ Phone Login always requires Firebase Phone verification.
// ✓ Phone Number never authenticates by Password.
// ✓ Email + Password normal Login requires NO Email OTP.
// ✓ No fake/local OTP.
// ✓ No OTP persistence.
// ✓ No Password persistence.
// ✓ No account-exists pre-login blocker.
// ✓ No Firebase security bypass.
// ✓ Native automatic verification supported.
// ✓ Manual six-digit verification supported.
// ✓ Web manual Phone OTP supported through AuthService.
// ✓ Resend supported.
// ✓ Call Engine untouched.
// ✓ Message Engine untouched.
// ✓ WebRTC untouched.
// ===============================================================

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import '../core/theme/jr_colors.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firebase/firestore_service.dart';
import '../services/profile_service.dart';
import 'create_profile_setup_screen.dart';
import 'home_screen.dart';
import 'login_otp_manager.dart';

// ===============================================================
// OTP MODE
// ===============================================================

enum OtpMode {
  phoneSignUp,
  phoneLogin,
  phoneChange,
  emailSignUp,
  emailLogin,
  emailChange,
  passwordRecovery,
}

// ===============================================================
// OTP SCREEN
// ===============================================================

class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.verificationId,
    required this.phoneNumber,
    this.email,
    this.password,
    this.provider,
  });

  final String verificationId;

  final String phoneNumber;

  final String? email;

  /// Used only by Password Recovery.
  ///
  /// Memory-only. Never persisted by this screen.
  final String? password;

  final String? provider;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

// ===============================================================
// STATE
// ===============================================================

class _OtpScreenState extends State<OtpScreen> {
  // =============================================================
  // SERVICES
  // =============================================================

  final AuthService _authService = AuthService.instance;

  final FirestoreService _firestoreService =
      FirestoreService.instance;

  final ProfileService _profileService =
      ProfileService.instance;

  late final LoginOtpManager _loginOtpManager;

  // =============================================================
  // CONTROLLER
  // =============================================================

  final TextEditingController _otpController =
  TextEditingController();

  // =============================================================
  // CONSTANTS
  // =============================================================

  static const int _otpLength = 6;

  static const int _defaultResendCooldownSeconds = 60;

  // =============================================================
  // MODE / SESSION
  // =============================================================

  late OtpMode _mode;

  late String _verificationId;

  String? _emailChallengeId;

  // =============================================================
  // TIMER
  // =============================================================

  Timer? _resendTimer;

  int _resendCooldownSeconds =
      _defaultResendCooldownSeconds;

  int _resendRemaining =
      _defaultResendCooldownSeconds;

  // =============================================================
  // STATE
  // =============================================================

  bool _loading = false;

  bool _resending = false;

  bool _completed = false;

  bool _automaticVerificationRunning = false;

  bool _routeArgumentsResolved = false;

  Map<String, dynamic> _routeData =
  const <String, dynamic>{};

  // =============================================================
  // LIFECYCLE
  // =============================================================

  @override
  void initState() {
    super.initState();

    _loginOtpManager = LoginOtpManager(
      authService: _authService,
      firestoreService: _firestoreService,
    );

    _verificationId =
        widget.verificationId.trim();

    _mode = _modeFromProvider(
      widget.provider,
    );

    if (_usesBackendEmailChallenge &&
        _verificationId.isNotEmpty) {
      _emailChallengeId =
          _verificationId;
    }

    _startResendTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_routeArgumentsResolved) {
      return;
    }

    _routeArgumentsResolved = true;

    final Object? rawArguments =
        ModalRoute.of(context)?.settings.arguments;

    if (rawArguments is! Map) {
      return;
    }

    _routeData =
    Map<String, dynamic>.from(
      rawArguments,
    );

    _resolveRouteMode();

    final String? emailChallengeId =
    _readString(
      _routeData['emailOtpChallengeId'],
    );

    final String? recoveryChallengeId =
    _readString(
      _routeData['passwordRecoveryChallengeId'],
    );

    final String? genericChallengeId =
    _readString(
      _routeData['challengeId'],
    );

    final String? resolvedChallengeId =
        recoveryChallengeId ??
            emailChallengeId ??
            genericChallengeId;

    if (resolvedChallengeId != null) {
      _emailChallengeId =
          resolvedChallengeId;

      _verificationId =
          resolvedChallengeId;
    }

    final Object? resendAfter =
    _routeData['resendAfterSeconds'];

    if (resendAfter is int &&
        resendAfter > 0) {
      _resendCooldownSeconds =
          resendAfter;

      _restartResendTimer();
    }
  }

  @override
  void dispose() {
    _loginOtpManager.cancel();

    _resendTimer?.cancel();

    _otpController.dispose();

    super.dispose();
  }

  // =============================================================
  // MODE
  // =============================================================

  OtpMode _modeFromProvider(
      String? provider,
      ) {
    switch (provider?.trim().toLowerCase()) {
      case 'phone_login':
      case 'phonelogin':
        return OtpMode.phoneLogin;

      case 'phone_change':
      case 'phonechange':
        return OtpMode.phoneChange;

      case 'email_signup':
      case 'emailsignup':
      case 'email_otp':
        return OtpMode.emailSignUp;

      case 'email_login':
      case 'emaillogin':
        return OtpMode.emailLogin;

      case 'email_change':
      case 'emailchange':
        return OtpMode.emailChange;

      case 'password_recovery':
      case 'passwordrecovery':
      case 'password_recovery_otp':
      case 'forgot_password':
        return OtpMode.passwordRecovery;

      case 'phone_signup':
      case 'phonesignup':
      default:
        return OtpMode.phoneSignUp;
    }
  }

  void _resolveRouteMode() {
    final String? value =
    _readString(
      _routeData['mode'],
    );

    switch (value) {
      case 'phoneSignUp':
        _mode = OtpMode.phoneSignUp;
        return;

      case 'phoneLogin':
        _mode = OtpMode.phoneLogin;
        return;

      case 'phoneChange':
        _mode = OtpMode.phoneChange;
        return;

      case 'emailSignUp':
        _mode = OtpMode.emailSignUp;
        return;

      case 'emailLogin':
        _mode = OtpMode.emailLogin;
        return;

      case 'emailChange':
        _mode = OtpMode.emailChange;
        return;

      case 'passwordRecovery':
      case 'password_recovery':
        _mode = OtpMode.passwordRecovery;
        return;
    }
  }

  bool get _isEmailMode {
    return _mode == OtpMode.emailSignUp ||
        _mode == OtpMode.emailLogin ||
        _mode == OtpMode.emailChange ||
        _mode == OtpMode.passwordRecovery;
  }

  bool get _usesBackendEmailChallenge {
    return _isEmailMode;
  }

  bool get _isSignUpMode {
    return _mode == OtpMode.phoneSignUp ||
        _mode == OtpMode.emailSignUp;
  }

  bool get _isChangeMode {
    return _mode == OtpMode.phoneChange ||
        _mode == OtpMode.emailChange;
  }

  bool get _isPasswordRecovery {
    return _mode == OtpMode.passwordRecovery;
  }

  // =============================================================
  // VERIFY
  // =============================================================

  Future<void> _verifyOtp() async {
    if (_loading ||
        _resending ||
        _completed ||
        _automaticVerificationRunning) {
      return;
    }

    final String otp =
    _otpController.text.trim();

    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      _showMessage(
        'Enter the complete 6-digit verification code.',
      );

      return;
    }

    FocusScope.of(context).unfocus();

    _setLoading(true);

    try {
      switch (_mode) {
        case OtpMode.phoneSignUp:
          await _verifyPhoneSignUp(
            otp,
          );
          return;

        case OtpMode.phoneLogin:
          await _verifyPhoneLogin(
            otp,
          );
          return;

        case OtpMode.phoneChange:
          await _verifyPhoneChange(
            otp,
          );
          return;

        case OtpMode.emailSignUp:
          await _verifyEmailOtp(
            otp: otp,
            purpose:
            AuthService.emailSignUpPurpose,
          );
          return;

        case OtpMode.emailLogin:
          await _verifyEmailOtp(
            otp: otp,
            purpose:
            AuthService.emailLoginPurpose,
          );
          return;

        case OtpMode.emailChange:
          await _verifyEmailOtp(
            otp: otp,
            purpose:
            AuthService.emailChangePurpose,
          );
          return;

        case OtpMode.passwordRecovery:
          await _verifyPasswordRecoveryOtp(
            otp,
          );
          return;
      }
    } on FirebaseAuthException catch (error) {
      _showMessage(
        _firebaseAuthMessage(error),
      );
    } on FirebaseFunctionsException catch (error) {
      _showMessage(
        _functionsMessage(error),
      );
    } on StateError catch (error) {
      _showMessage(
        error.message,
      );
    } on ArgumentError catch (error) {
      _showMessage(
        error.message?.toString() ??
            'Invalid verification information.',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'JR CALL OTP verification error: $error',
      );

      debugPrintStack(
        label: 'JR CALL OTP verification',
        stackTrace: stackTrace,
      );

      _showMessage(
        'Verification could not be completed. Please try again.',
      );
    } finally {
      if (mounted &&
          !_completed &&
          !_automaticVerificationRunning) {
        _setLoading(false);
      }
    }
  }

  // =============================================================
  // PHONE SIGNUP — MANUAL OTP
  //
  // IMPORTANT:
  //
  // OtpScreen authenticates the Phone only.
  //
  // CreateAccountScreen owns:
  //
  // - Optional Email/Password linking.
  // - Firestore profile finalization.
  // - Profile media.
  // - Final Signup routing.
  // =============================================================

  Future<void> _verifyPhoneSignUp(
      String otp,
      ) async {
    final String verificationId =
    _requirePhoneVerificationId();

    final UserCredential result =
    await _authService.signInWithOtp(
      verificationId: verificationId,
      smsCode: otp,
    );

    await _completeVerifiedPhoneSignup(
      result,
    );
  }

  // =============================================================
  // PHONE SIGNUP — AUTOMATIC NATIVE CREDENTIAL
  // =============================================================

  Future<void> _completeAutomaticPhoneSignup(
      PhoneAuthCredential credential,
      ) async {
    final UserCredential result =
    await _authService
        .signInWithPhoneCredential(
      credential,
    );

    await _completeVerifiedPhoneSignup(
      result,
    );
  }

  // =============================================================
  // PHONE SIGNUP — AUTH RESULT
  // =============================================================

  Future<void> _completeVerifiedPhoneSignup(
      UserCredential result,
      ) async {
    final User? user =
        result.user ??
            _authService.currentUser;

    if (user == null ||
        user.uid.trim().isEmpty) {
      throw StateError(
        'The verified Firebase user is unavailable.',
      );
    }

    final String verifiedPhone =
        user.phoneNumber?.trim() ?? '';

    if (verifiedPhone.isEmpty) {
      throw StateError(
        'Firebase did not return the verified Phone Number.',
      );
    }

    final bool isNewFirebaseUser =
        result.additionalUserInfo?.isNewUser ==
            true;

    if (!isNewFirebaseUser) {
      await _safeSignOut();

      throw StateError(
        'An account already exists with this Phone Number. '
            'Use Login instead.',
      );
    }

    _completeWithSuccess();
  }

  // =============================================================
  // PHONE LOGIN
  // =============================================================

  Future<void> _verifyPhoneLogin(
      String otp,
      ) async {
    final LoginOtpResult result =
    await _loginOtpManager
        .signInWithManualOtp(
      verificationId:
      _requirePhoneVerificationId(),
      smsCode: otp,
      fallbackPhoneNumber:
      widget.phoneNumber.trim(),
    );

    await _completePhoneLoginResult(
      result,
    );
  }

  Future<void> _completePhoneLoginResult(
      LoginOtpResult result,
      ) async {
    if (result.hasExistingProfile) {
      _completeWithSuccess();

      return;
    }

    if (result.requiresProfileSetup) {
      await _profileService
          .ensureCurrentProfile(
        generateJrCallUserId: true,
      );

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (
              BuildContext context,
              ) =>
          const CreateProfileSetupScreen(),
        ),
      );

      if (!mounted) {
        return;
      }

      if (!_completed) {
        _completeWithSuccess();
      }

      return;
    }

    throw StateError(
      'Phone authentication state is invalid.',
    );
  }

  // =============================================================
  // PHONE CHANGE
  // =============================================================

  Future<void> _verifyPhoneChange(
      String otp,
      ) async {
    final PhoneAuthCredential credential =
    _authService.createPhoneCredential(
      verificationId:
      _requirePhoneVerificationId(),
      smsCode: otp,
    );

    await _completePhoneChange(
      credential,
    );
  }

  Future<void> _completePhoneChange(
      PhoneAuthCredential credential,
      ) async {
    _requireCurrentUser();

    await _authService.updatePhoneNumber(
      credential,
    );

    final User user =
    _requireCurrentUser();

    final String verifiedPhone =
        user.phoneNumber?.trim() ?? '';

    if (verifiedPhone.isEmpty) {
      throw StateError(
        'The verified Phone Number is unavailable.',
      );
    }

    final UserModel? profile =
    await _firestoreService.getUser(
      user.uid,
    );

    if (profile != null) {
      await _firestoreService.updateUser(
        profile.copyWith(
          phone: verifiedPhone,
          verified: true,
          phoneVerified: true,
          updatedAt: DateTime.now(),
        ),
      );
    }

    await _firestoreService
        .syncAuthenticationProfile(
      uid: user.uid,
      email: user.email,
      phoneNumber: verifiedPhone,
      emailVerified:
      user.emailVerified,
      phoneVerified: true,
      signInProviders:
      _authService.linkedProviderIds,
    );

    _completeWithSuccess();
  }

  // =============================================================
  // EMAIL OTP
  //
  // Normal Email Login does NOT use this path.
  //
  // emailLogin remains compatibility-only.
  // =============================================================

  Future<void> _verifyEmailOtp({
    required String otp,
    required String purpose,
  }) async {
    final String challengeId =
    (_emailChallengeId ??
        _verificationId)
        .trim();

    if (challengeId.isEmpty) {
      throw StateError(
        'No Email verification challenge is available.',
      );
    }

    final EmailOtpVerificationResult result =
    await _authService.verifyEmailOtp(
      challengeId: challengeId,
      otp: otp,
      purpose: purpose,
    );

    if (!result.success ||
        !result.verified) {
      throw StateError(
        'Email verification failed.',
      );
    }

    final User user =
    _requireCurrentUser();

    final UserModel? profile =
    await _firestoreService.getUser(
      user.uid,
    );

    if (profile != null) {
      final DateTime now =
      DateTime.now();

      await _firestoreService.updateUser(
        profile.copyWith(
          email:
          user.email ??
              profile.email,
          verified: true,
          emailVerified: true,
          online: true,
          updatedAt: now,
          lastSeen: now,
          lastLogin: now,
        ),
      );
    }

    final String? authenticatedPhone =
    _cleanNullable(
      user.phoneNumber,
    );

    await _firestoreService
        .syncAuthenticationProfile(
      uid: user.uid,
      email:
      user.email ??
          _normalizedOptionalEmail,
      phoneNumber:
      authenticatedPhone,
      emailVerified: true,
      phoneVerified:
      authenticatedPhone != null,
      signInProviders:
      _authService.linkedProviderIds,
    );

    _completeWithSuccess();
  }

  // =============================================================
  // PASSWORD RECOVERY
  // =============================================================

  Future<void> _verifyPasswordRecoveryOtp(
      String otp,
      ) async {
    final String challengeId =
    (_emailChallengeId ??
        _verificationId)
        .trim();

    if (challengeId.isEmpty) {
      throw StateError(
        'Password recovery session is unavailable. '
            'Request a new recovery code.',
      );
    }

    final String newPassword =
    _resolveRecoveryPassword();

    if (newPassword.length < 6) {
      throw ArgumentError.value(
        newPassword,
        'newPassword',
        'Password must contain at least 6 characters.',
      );
    }

    await _authService
        .verifyPasswordRecoveryOtp(
      challengeId: challengeId,
      otp: otp,
      newPassword: newPassword,
    );

    if (!mounted) {
      return;
    }

    _completeWithSuccess();
  }

  String _resolveRecoveryPassword() {
    final String widgetPassword =
        widget.password ?? '';

    if (widgetPassword.isNotEmpty) {
      return widgetPassword;
    }

    final Object? routePassword =
    _routeData['newPassword'];

    if (routePassword is String &&
        routePassword.isNotEmpty) {
      return routePassword;
    }

    final Object? fallbackPassword =
    _routeData['password'];

    if (fallbackPassword is String &&
        fallbackPassword.isNotEmpty) {
      return fallbackPassword;
    }

    throw StateError(
      'The new password is unavailable. '
          'Restart password recovery.',
    );
  }

  // =============================================================
  // RESEND
  // =============================================================

  Future<void> _resendOtp() async {
    if (_loading ||
        _resending ||
        _completed ||
        _automaticVerificationRunning ||
        _resendRemaining > 0) {
      return;
    }

    setState(() {
      _resending = true;
    });

    try {
      if (_isEmailMode) {
        await _resendEmailOtp();
      } else {
        await _resendPhoneOtp();
      }

      if (!mounted ||
          _completed) {
        return;
      }

      _otpController.clear();

      _restartResendTimer();

      _showMessage(
        'A new verification code has been sent.',
      );
    } on FirebaseAuthException catch (error) {
      _showMessage(
        _firebaseAuthMessage(error),
      );
    } on FirebaseFunctionsException catch (error) {
      _showMessage(
        _functionsMessage(error),
      );
    } on StateError catch (error) {
      _showMessage(
        error.message,
      );
    } on ArgumentError catch (error) {
      _showMessage(
        error.message?.toString() ??
            'Invalid verification information.',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'JR CALL OTP resend error: $error',
      );

      debugPrintStack(
        label: 'JR CALL OTP resend',
        stackTrace: stackTrace,
      );

      _showMessage(
        'A new verification code could not be sent.',
      );
    } finally {
      if (mounted &&
          !_completed) {
        setState(() {
          _resending = false;
        });
      }
    }
  }

  // =============================================================
  // EMAIL / RECOVERY RESEND
  // =============================================================

  Future<void> _resendEmailOtp() async {
    final String email =
    widget.email?.trim().isNotEmpty ==
        true
        ? widget.email!.trim()
        : _authService.currentEmail ??
        '';

    if (email.isEmpty) {
      throw StateError(
        'No Email address is available.',
      );
    }

    if (_mode ==
        OtpMode.passwordRecovery) {
      final PasswordRecoveryChallenge
      challenge =
      await _authService
          .sendPasswordRecoveryOtp(
        email: email,
      );

      final String? challengeId =
      _cleanNullable(
        challenge.challengeId,
      );

      if (challengeId == null) {
        throw StateError(
          'Password recovery session is no longer available.',
        );
      }

      _emailChallengeId =
          challengeId;

      _verificationId =
          challengeId;

      _resendCooldownSeconds =
      challenge.resendAfterSeconds > 0
          ? challenge.resendAfterSeconds
          : _defaultResendCooldownSeconds;

      return;
    }

    final EmailOtpChallenge challenge;

    switch (_mode) {
      case OtpMode.emailSignUp:
        challenge =
        await _authService
            .sendEmailSignUpOtp(
          email: email,
        );
        break;

      case OtpMode.emailLogin:
        challenge =
        await _authService
            .sendEmailLoginOtp(
          email: email,
        );
        break;

      case OtpMode.emailChange:
        challenge =
        await _authService
            .sendEmailChangeOtp(
          email: email,
        );
        break;

      case OtpMode.phoneSignUp:
      case OtpMode.phoneLogin:
      case OtpMode.phoneChange:
        throw StateError(
          'Email resend is not available in Phone mode.',
        );

      case OtpMode.passwordRecovery:
        throw StateError(
          'Password recovery resend state is invalid.',
        );
    }

    final String challengeId =
    challenge.challengeId.trim();

    if (challengeId.isEmpty) {
      throw StateError(
        'Email verification session could not be created.',
      );
    }

    _emailChallengeId =
        challengeId;

    _verificationId =
        challengeId;

    _resendCooldownSeconds =
    challenge.resendAfterSeconds > 0
        ? challenge.resendAfterSeconds
        : _defaultResendCooldownSeconds;
  }

  // =============================================================
  // PHONE RESEND
  // =============================================================

  Future<void> _resendPhoneOtp() async {
    final String phoneNumber =
    widget.phoneNumber.trim();

    if (phoneNumber.isEmpty) {
      throw StateError(
        'No Phone Number is available.',
      );
    }

    // -----------------------------------------------------------
    // LOGIN RESEND
    // -----------------------------------------------------------

    if (_mode ==
        OtpMode.phoneLogin) {
      await _loginOtpManager.resendPhoneOtp(
        phoneNumber: phoneNumber,
        onCodeSent: (
            String verificationId,
            ) {
          _updatePhoneVerificationId(
            verificationId,
          );
        },
        onAutomaticVerified: (
            LoginOtpResult result,
            ) {
          if (!mounted ||
              _completed ||
              _automaticVerificationRunning) {
            return;
          }

          _automaticVerificationRunning =
          true;

          unawaited(
            _handleAutomaticLoginResult(
              result,
            ),
          );
        },
        onVerificationFailed: (
            FirebaseAuthException error,
            ) {
          if (!mounted ||
              _completed) {
            return;
          }

          _showMessage(
            _firebaseAuthMessage(
              error,
            ),
          );
        },
        onAutoRetrievalTimeout: (
            String verificationId,
            ) {
          _updatePhoneVerificationId(
            verificationId,
          );
        },
      );

      return;
    }

    // -----------------------------------------------------------
    // SIGNUP / PHONE CHANGE RESEND
    // -----------------------------------------------------------

    await _authService
        .resendPhoneVerificationCode(
      phoneNumber: phoneNumber,
      verificationCompleted: (
          PhoneAuthCredential credential,
          ) {
        if (!mounted ||
            _completed ||
            _automaticVerificationRunning) {
          return;
        }

        _automaticVerificationRunning =
        true;

        unawaited(
          _handleAutomaticCredential(
            credential,
          ),
        );
      },
      verificationFailed: (
          FirebaseAuthException error,
          ) {
        if (!mounted ||
            _completed) {
          return;
        }

        _showMessage(
          _firebaseAuthMessage(
            error,
          ),
        );
      },
      codeSent: (
          String verificationId,
          ) {
        _updatePhoneVerificationId(
          verificationId,
        );
      },
      codeAutoRetrievalTimeout: (
          String verificationId,
          ) {
        _updatePhoneVerificationId(
          verificationId,
        );
      },
      codeSentWithToken: (
          String verificationId,
          int? resendToken,
          ) {
        _updatePhoneVerificationId(
          verificationId,
        );
      },
    );
  }

  void _updatePhoneVerificationId(
      String verificationId,
      ) {
    final String normalizedId =
    verificationId.trim();

    if (normalizedId.isEmpty) {
      return;
    }

    _verificationId =
        normalizedId;
  }

  // =============================================================
  // AUTOMATIC LOGIN RESULT
  // =============================================================

  Future<void> _handleAutomaticLoginResult(
      LoginOtpResult result,
      ) async {
    if (_completed) {
      _automaticVerificationRunning =
      false;

      return;
    }

    if (mounted) {
      _setLoading(true);
    }

    try {
      await _completePhoneLoginResult(
        result,
      );
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        _showMessage(
          _firebaseAuthMessage(
            error,
          ),
        );
      }
    } on StateError catch (error) {
      if (mounted) {
        _showMessage(
          error.message,
        );
      }
    } on ArgumentError catch (error) {
      if (mounted) {
        _showMessage(
          error.message?.toString() ??
              'Invalid verification information.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint(
        'JR CALL automatic Login OTP error: $error',
      );

      debugPrintStack(
        label:
        'JR CALL automatic Login OTP',
        stackTrace: stackTrace,
      );

      if (mounted) {
        _showMessage(
          'Phone verification could not be completed.',
        );
      }
    } finally {
      _automaticVerificationRunning =
      false;

      if (mounted &&
          !_completed) {
        _setLoading(false);
      }
    }
  }

  // =============================================================
  // AUTOMATIC PHONE CREDENTIAL
  // =============================================================

  Future<void> _handleAutomaticCredential(
      PhoneAuthCredential credential,
      ) async {
    if (_completed) {
      _automaticVerificationRunning =
      false;

      return;
    }

    if (mounted) {
      _setLoading(true);
    }

    try {
      switch (_mode) {
        case OtpMode.phoneSignUp:
          await _completeAutomaticPhoneSignup(
            credential,
          );
          return;

        case OtpMode.phoneChange:
          await _completePhoneChange(
            credential,
          );
          return;

        case OtpMode.phoneLogin:
          throw StateError(
            'Phone Login automatic verification must use LoginOtpManager.',
          );

        case OtpMode.emailSignUp:
        case OtpMode.emailLogin:
        case OtpMode.emailChange:
        case OtpMode.passwordRecovery:
          return;
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        _showMessage(
          _firebaseAuthMessage(
            error,
          ),
        );
      }
    } on StateError catch (error) {
      if (mounted) {
        _showMessage(
          error.message,
        );
      }
    } on ArgumentError catch (error) {
      if (mounted) {
        _showMessage(
          error.message?.toString() ??
              'Invalid verification information.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint(
        'JR CALL automatic OTP error: $error',
      );

      debugPrintStack(
        label: 'JR CALL automatic OTP',
        stackTrace: stackTrace,
      );

      if (mounted) {
        _showMessage(
          'Phone verification could not be completed.',
        );
      }
    } finally {
      _automaticVerificationRunning =
      false;

      if (mounted &&
          !_completed) {
        _setLoading(false);
      }
    }
  }

  // =============================================================
  // TIMER
  // =============================================================

  void _startResendTimer() {
    _resendTimer?.cancel();

    _resendRemaining =
        _resendCooldownSeconds;

    _resendTimer = Timer.periodic(
      const Duration(
        seconds: 1,
      ),
          (
          Timer timer,
          ) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (_resendRemaining <= 1) {
          timer.cancel();

          setState(() {
            _resendRemaining = 0;
          });

          return;
        }

        setState(() {
          _resendRemaining--;
        });
      },
    );
  }

  void _restartResendTimer() {
    _startResendTimer();
  }

  // =============================================================
  // SUCCESS
  // =============================================================

  void _completeWithSuccess() {
    if (!mounted ||
        _completed) {
      return;
    }

    _completed = true;

    _resendTimer?.cancel();

    TextInput.finishAutofillContext(
      shouldSave: false,
    );

    // -----------------------------------------------------------
    // PASSWORD RECOVERY
    // -----------------------------------------------------------

    if (_isPasswordRecovery) {
      Navigator.of(context).pop<bool>(
        true,
      );

      return;
    }

    // -----------------------------------------------------------
    // SIGNUP
    //
    // CreateAccountScreen owns final profile/account completion.
    // -----------------------------------------------------------

    if (_isSignUpMode) {
      Navigator.of(context).pop<bool>(
        true,
      );

      return;
    }

    // -----------------------------------------------------------
    // ACCOUNT CHANGE
    // -----------------------------------------------------------

    if (_isChangeMode) {
      Navigator.of(context).pop<bool>(
        true,
      );

      return;
    }

    // -----------------------------------------------------------
    // LOGIN
    // -----------------------------------------------------------

    Navigator.of(context)
        .pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (
            BuildContext context,
            ) =>
        const HomeScreen(),
      ),
          (
          Route<dynamic> route,
          ) =>
      false,
    );
  }

  // =============================================================
  // CANCEL
  // =============================================================

  void _cancelVerification() {
    if (!mounted ||
        _completed ||
        _loading ||
        _resending ||
        _automaticVerificationRunning) {
      return;
    }

    _loginOtpManager.cancel();

    _resendTimer?.cancel();

    Navigator.of(context).pop<bool>(
      false,
    );
  }

  // =============================================================
  // HELPERS
  // =============================================================

  String _requirePhoneVerificationId() {
    final String verificationId =
    _verificationId.trim();

    if (verificationId.isEmpty) {
      throw StateError(
        'Phone verification session is unavailable. '
            'Request a new OTP.',
      );
    }

    return verificationId;
  }

  String? get _normalizedOptionalEmail {
    final String value =
        widget.email
            ?.trim()
            .toLowerCase() ??
            '';

    return value.isEmpty
        ? null
        : value;
  }

  User _requireCurrentUser() {
    final User? user =
        _authService.currentUser;

    if (user == null ||
        user.uid.trim().isEmpty) {
      throw StateError(
        'The authenticated Firebase user is unavailable.',
      );
    }

    return user;
  }

  Future<void> _safeSignOut() async {
    try {
      await _authService.signOut();
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  String? _cleanNullable(
      String? value,
      ) {
    if (value == null) {
      return null;
    }

    final String normalized =
    value.trim();

    return normalized.isEmpty
        ? null
        : normalized;
  }

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

  String? _readString(
      Object? value,
      ) {
    if (value is! String) {
      return null;
    }

    final String normalized =
    value.trim();

    return normalized.isEmpty
        ? null
        : normalized;
  }

  // =============================================================
  // AUTH ERROR
  // =============================================================

  String _firebaseAuthMessage(
      FirebaseAuthException error,
      ) {
    switch (error.code) {
      case 'invalid-verification-code':
        return 'The verification code is incorrect.';

      case 'session-expired':
        return 'The verification session expired. Request a new code.';

      case 'invalid-verification-id':
        return 'The verification session is invalid. Request a new code.';

      case 'too-many-requests':
        return 'Too many attempts were made. Please try again later.';

      case 'quota-exceeded':
        return 'The verification quota has been reached.';

      case 'network-request-failed':
        return 'Check your Internet connection and try again.';

      case 'operation-not-allowed':
        return 'This authentication method is not enabled.';

      case 'invalid-phone-number':
        return 'The Phone Number is invalid.';

      case 'app-not-authorized':
        return 'Firebase could not authorize this application.';

      case 'invalid-app-credential':
        return 'Firebase could not verify this application.';

      case 'captcha-check-failed':
        return 'Firebase security verification failed.';

      case 'credential-already-in-use':
      case 'phone-number-already-exists':
        return 'This Phone Number already belongs to another account.';

      case 'verification-in-progress':
        return 'Phone verification is already in progress.';

      case 'phone-login-state-error':
      case 'phone-verification-state-error':
        return error.message ??
            'Phone authentication state is invalid.';

      case 'phone-login-invalid-argument':
        return error.message ??
            'Phone authentication information is invalid.';

      case 'phone-verification-failed':
        return error.message ??
            'Phone verification could not be completed.';

      case 'weak-password':
        return 'The new password is too weak.';

      default:
        return error.message ??
            'Verification failed.';
    }
  }

  // =============================================================
  // FUNCTIONS ERROR
  // =============================================================

  String _functionsMessage(
      FirebaseFunctionsException error,
      ) {
    switch (error.code) {
      case 'invalid-argument':
        return error.message ??
            'The OTP request is invalid.';

      case 'not-found':
        return 'The OTP challenge was not found or has expired.';

      case 'deadline-exceeded':
        return 'The OTP has expired. Request a new code.';

      case 'permission-denied':
        return error.message ??
            'OTP verification was not authorized.';

      case 'resource-exhausted':
        return error.message ??
            'Too many OTP attempts were made.';

      case 'failed-precondition':
        return error.message ??
            'OTP verification cannot continue right now.';

      case 'unauthenticated':
        return 'The authentication session expired.';

      case 'unavailable':
        return 'The Email OTP service is temporarily unavailable.';

      case 'internal':
        return 'The Email OTP service encountered an internal error.';

      case 'already-exists':
        return error.message ??
            'This information is already used by another account.';

      default:
        return error.message ??
            'Email OTP verification failed.';
    }
  }

  // =============================================================
  // DISPLAY
  // =============================================================

  String get _destination {
    if (_isEmailMode) {
      return widget.email
          ?.trim()
          .isNotEmpty ==
          true
          ? widget.email!.trim()
          : _authService.currentEmail ??
          'your Email';
    }

    return widget.phoneNumber.trim();
  }

  String get _screenTitle {
    switch (_mode) {
      case OtpMode.phoneSignUp:
        return 'Verify Phone Number';

      case OtpMode.phoneLogin:
        return 'Verify Login';

      case OtpMode.phoneChange:
        return 'Verify New Phone Number';

      case OtpMode.emailSignUp:
        return 'Verify Email';

      case OtpMode.emailLogin:
        return 'Verify Login';

      case OtpMode.emailChange:
        return 'Verify New Email';

      case OtpMode.passwordRecovery:
        return 'Verify Recovery Code';
    }
  }

  String get _screenSubtitle {
    if (_isPasswordRecovery) {
      return 'Enter the 6-digit recovery code sent to $_destination';
    }

    return 'Enter the 6-digit code sent to $_destination';
  }

  String get _securityText {
    if (_isPasswordRecovery) {
      return 'Password recovery is securely verified by JR CALL. '
          'Your OTP and new password are never stored on this screen.';
    }

    if (_isEmailMode) {
      return 'Email verification is securely processed by JR CALL.';
    }

    return 'SMS verification is securely processed by Firebase Authentication.';
  }

  // =============================================================
  // UI
  // =============================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    final bool actionBusy =
        _loading ||
            _resending ||
            _automaticVerificationRunning;

    final double screenWidth =
        MediaQuery.sizeOf(
          context,
        ).width;

    final double availableWidth =
    (screenWidth - 92).clamp(
      240.0,
      430.0,
    );

    final double fieldWidth =
    ((availableWidth - 50) / 6).clamp(
      36.0,
      48.0,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (
          bool didPop,
          Object? result,
          ) {
        if (!didPop &&
            !actionBusy) {
          _cancelVerification();
        }
      },
      child: Scaffold(
        backgroundColor:
        JrColors.background,
        appBar: AppBar(
          backgroundColor:
          JrColors.surface,
          foregroundColor:
          JrColors.textPrimary,
          surfaceTintColor:
          Colors.transparent,
          elevation: 0,
          title: const Text(
            'JR CALL',
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
              const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints:
                const BoxConstraints(
                  maxWidth: 520,
                ),
                child: Container(
                  width: double.infinity,
                  padding:
                  const EdgeInsets.fromLTRB(
                    22,
                    30,
                    22,
                    24,
                  ),
                  decoration:
                  BoxDecoration(
                    color:
                    JrColors.surface,
                    borderRadius:
                    BorderRadius.circular(
                      28,
                    ),
                    border:
                    Border.all(
                      color:
                      JrColors.border,
                    ),
                    boxShadow:
                    <BoxShadow>[
                      BoxShadow(
                        color:
                        Colors.black.withValues(
                          alpha: 0.045,
                        ),
                        blurRadius: 28,
                        offset:
                        const Offset(
                          0,
                          10,
                        ),
                      ),
                    ],
                  ),
                  child: AutofillGroup(
                    child: Column(
                      mainAxisSize:
                      MainAxisSize.min,
                      children:
                      <Widget>[
                        Container(
                          width: 88,
                          height: 88,
                          decoration:
                          BoxDecoration(
                            shape:
                            BoxShape.circle,
                            color:
                            JrColors.primaryBlue
                                .withValues(
                              alpha: 0.08,
                            ),
                          ),
                          child: Icon(
                            _isPasswordRecovery
                                ? Icons
                                .lock_reset_rounded
                                : _isEmailMode
                                ? Icons
                                .mark_email_read_outlined
                                : Icons
                                .sms_outlined,
                            size: 42,
                            color:
                            JrColors.primaryBlue,
                          ),
                        ),
                        const SizedBox(
                          height: 24,
                        ),
                        Text(
                          _screenTitle,
                          textAlign:
                          TextAlign.center,
                          style:
                          const TextStyle(
                            fontSize: 26,
                            height: 1.15,
                            fontWeight:
                            FontWeight.w800,
                            color:
                            JrColors.textPrimary,
                          ),
                        ),
                        const SizedBox(
                          height: 10,
                        ),
                        Text(
                          _screenSubtitle,
                          textAlign:
                          TextAlign.center,
                          style:
                          const TextStyle(
                            color:
                            JrColors.textSecondary,
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(
                          height: 32,
                        ),
                        SizedBox(
                          width:
                          availableWidth,
                          child:
                          PinCodeTextField(
                            appContext:
                            context,
                            controller:
                            _otpController,
                            length:
                            _otpLength,
                            keyboardType:
                            TextInputType.number,
                            inputFormatters:
                            <TextInputFormatter>[
                              FilteringTextInputFormatter
                                  .digitsOnly,
                            ],
                            animationType:
                            AnimationType.fade,
                            autoFocus: true,
                            enableActiveFill:
                            true,
                            enablePinAutofill:
                            !_isEmailMode,
                            useExternalAutoFillGroup:
                            true,
                            autoUnfocus:
                            true,
                            autoDisposeControllers:
                            false,
                            textInputAction:
                            TextInputAction.done,
                            cursorColor:
                            JrColors.primaryBlue,
                            textStyle:
                            const TextStyle(
                              color:
                              JrColors.textPrimary,
                              fontSize: 21,
                              fontWeight:
                              FontWeight.w700,
                            ),
                            mainAxisAlignment:
                            MainAxisAlignment
                                .spaceBetween,
                            pinTheme:
                            PinTheme(
                              shape:
                              PinCodeFieldShape.box,
                              borderRadius:
                              BorderRadius.circular(
                                13,
                              ),
                              fieldHeight:
                              56,
                              fieldWidth:
                              fieldWidth,
                              activeColor:
                              JrColors.primaryBlue,
                              selectedColor:
                              JrColors.primaryBlue,
                              inactiveColor:
                              JrColors.border,
                              activeFillColor:
                              const Color(
                                0xFFF8FAFC,
                              ),
                              selectedFillColor:
                              const Color(
                                0xFFEFF6FF,
                              ),
                              inactiveFillColor:
                              const Color(
                                0xFFF8FAFC,
                              ),
                            ),
                            onChanged:
                                (_) {},
                            onCompleted:
                                (_) {
                              if (!actionBusy) {
                                unawaited(
                                  _verifyOtp(),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(
                          height: 28,
                        ),
                        SizedBox(
                          width:
                          double.infinity,
                          height: 56,
                          child:
                          FilledButton(
                            onPressed:
                            actionBusy
                                ? null
                                : _verifyOtp,
                            style:
                            FilledButton.styleFrom(
                              backgroundColor:
                              JrColors.primaryBlue,
                              foregroundColor:
                              Colors.white,
                              shape:
                              RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(
                                  17,
                                ),
                              ),
                            ),
                            child:
                            _loading ||
                                _automaticVerificationRunning
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
                                : Text(
                              _isPasswordRecovery
                                  ? 'VERIFY & RESET'
                                  : 'VERIFY OTP',
                              style:
                              const TextStyle(
                                fontSize:
                                16,
                                fontWeight:
                                FontWeight.w800,
                                letterSpacing:
                                0.2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(
                          height: 20,
                        ),
                        if (_resendRemaining >
                            0)
                          Text(
                            'Resend code in $_resendRemaining seconds',
                            style:
                            const TextStyle(
                              color:
                              JrColors.textSecondary,
                            ),
                          )
                        else
                          TextButton.icon(
                            onPressed:
                            actionBusy
                                ? null
                                : _resendOtp,
                            icon:
                            const Icon(
                              Icons.refresh_rounded,
                            ),
                            label:
                            const Text(
                              'RESEND OTP',
                              style:
                              TextStyle(
                                fontWeight:
                                FontWeight.w700,
                              ),
                            ),
                          ),
                        const SizedBox(
                          height: 4,
                        ),
                        TextButton(
                          onPressed:
                          actionBusy
                              ? null
                              : _cancelVerification,
                          child:
                          const Text(
                            'Back',
                            style:
                            TextStyle(
                              color:
                              JrColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(
                          height: 10,
                        ),
                        Container(
                          width:
                          double.infinity,
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
                          ),
                          child: Text(
                            _securityText,
                            textAlign:
                            TextAlign.center,
                            style:
                            const TextStyle(
                              color:
                              JrColors.textSecondary,
                              fontSize: 12,
                              height: 1.4,
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

// ===============================================================
// END OF FILE
//
// OTP / AUTH MASTER FILE 06 / 09
//
// FINAL:
//
// ✓ Phone Signup verifies Phone only.
// ✓ CreateAccountScreen owns Signup profile finalization.
// ✓ Existing Phone identity rejected from Signup.
// ✓ New Phone Firebase UID preserved for CreateAccountScreen.
// ✓ Phone Login uses LoginOtpManager.
// ✓ Web manual Phone Login/Signup uses AuthService.signInWithOtp().
// ✓ Native automatic verification preserved.
// ✓ Phone resend preserved.
// ✓ Email normal Login does not require this screen.
// ✓ Legacy Email Login OTP compatibility preserved.
// ✓ Email Signup/Change OTP preserved.
// ✓ Password Recovery preserved.
// ✓ No fake/local OTP.
// ✓ No OTP persistence.
// ✓ No Password persistence.
// ✓ Call/Message/WebRTC untouched.
// ===============================================================