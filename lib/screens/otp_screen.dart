// ===============================================================
// JR CALL
// File: otp_screen.dart
// Location: lib/screens/otp_screen.dart
//
// FINAL LOGIN BEHAVIOUR:
// - Phone OTP autofill supported.
// - Complete 6 digits -> verification starts automatically.
// - Manual VERIFY OTP remains available.
// - Email OTP -> JR CALL Cloud Function through AuthService.
// - Phone OTP -> Firebase Auth through AuthService.
// - Successful Login -> HomeScreen immediately.
// ===============================================================

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:uuid/uuid.dart';

import '../core/theme/jr_colors.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firebase/firestore_service.dart';
import 'home_screen.dart';

enum OtpMode {
  phoneSignUp,
  phoneLogin,
  phoneChange,
  emailSignUp,
  emailLogin,
  emailChange,
}

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
  final String? password;
  final String? provider;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final AuthService _authService = AuthService.instance;

  final FirestoreService _firestoreService = FirestoreService.instance;

  final TextEditingController _otpController = TextEditingController();

  static const int _otpLength = 6;
  static const int _resendCooldownSeconds = 60;
  static const int _maximumJrCallIdAttempts = 8;
  static const Uuid _uuid = Uuid();

  late OtpMode _mode;
  late String _verificationId;

  String? _emailChallengeId;

  Timer? _resendTimer;

  int _resendRemaining = _resendCooldownSeconds;

  bool _loading = false;
  bool _resending = false;
  bool _completed = false;
  bool _automaticVerificationRunning = false;
  bool _routeArgumentsResolved = false;

  Map<String, dynamic> _routeData = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();

    _verificationId = widget.verificationId.trim();

    _mode = _modeFromProvider(widget.provider);

    if (_isEmailMode && _verificationId.isNotEmpty) {
      _emailChallengeId = _verificationId;
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

    final Object? rawArguments = ModalRoute.of(context)?.settings.arguments;

    if (rawArguments is Map) {
      _routeData = Map<String, dynamic>.from(rawArguments);

      _resolveRouteMode();

      final String? challengeId = _readString(
        _routeData['emailOtpChallengeId'],
      );

      if (challengeId != null) {
        _emailChallengeId = challengeId;
        _verificationId = challengeId;
      }
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _otpController.dispose();

    super.dispose();
  }

  // =============================================================
  // ROUTE PROFILE DATA
  // =============================================================

  String get _fullName {
    return _readString(_routeData['fullName']) ??
        _readString(_routeData['name']) ??
        '';
  }

  String? get _username {
    return _normalizeUsername(_readString(_routeData['username']));
  }

  String? get _country => _readString(_routeData['country']);

  String? get _countryCode =>
      _readString(_routeData['countryCode'])?.toUpperCase();

  String? get _bio => _readString(_routeData['bio']);

  DateTime? get _dateOfBirth {
    final Object? value = _routeData['dateOfBirth'];

    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }

    if (value is String) {
      final DateTime? parsed = DateTime.tryParse(value);

      if (parsed == null) {
        return null;
      }

      return DateTime(parsed.year, parsed.month, parsed.day);
    }

    return null;
  }

  String? get _jrCallIdCandidate {
    final String? value = _readString(_routeData['jrCallUserIdCandidate']);

    if (value == null) {
      return null;
    }

    final String normalized = value.toLowerCase();

    if (!RegExp(r'^[a-z0-9._-]{3,64}$').hasMatch(normalized)) {
      return null;
    }

    return normalized;
  }

  // =============================================================
  // MODE
  // =============================================================

  OtpMode _modeFromProvider(String? provider) {
    switch (provider?.trim().toLowerCase()) {
      case 'phone_login':
      case 'phonelogin':
        return OtpMode.phoneLogin;

      case 'phone_change':
      case 'phonechange':
        return OtpMode.phoneChange;

      case 'email_login':
      case 'emaillogin':
        return OtpMode.emailLogin;

      case 'email_change':
      case 'emailchange':
        return OtpMode.emailChange;

      case 'email_signup':
      case 'emailsignup':
      case 'email_otp':
        return OtpMode.emailSignUp;

      default:
        return OtpMode.phoneSignUp;
    }
  }

  void _resolveRouteMode() {
    final String? value = _readString(_routeData['mode']);

    switch (value) {
      case 'phoneSignUp':
        _mode = OtpMode.phoneSignUp;
        break;

      case 'phoneLogin':
        _mode = OtpMode.phoneLogin;
        break;

      case 'phoneChange':
        _mode = OtpMode.phoneChange;
        break;

      case 'emailSignUp':
        _mode = OtpMode.emailSignUp;
        break;

      case 'emailLogin':
        _mode = OtpMode.emailLogin;
        break;

      case 'emailChange':
        _mode = OtpMode.emailChange;
        break;
    }
  }

  bool get _isEmailMode {
    return _mode == OtpMode.emailSignUp ||
        _mode == OtpMode.emailLogin ||
        _mode == OtpMode.emailChange;
  }

  // =============================================================
  // VERIFY
  // =============================================================

  Future<void> _verifyOtp() async {
    if (_loading || _resending || _completed || _automaticVerificationRunning) {
      return;
    }

    final String otp = _otpController.text.trim();

    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      _showMessage('Enter the complete 6-digit verification code.');

      return;
    }

    FocusScope.of(context).unfocus();

    _setLoading(true);

    try {
      switch (_mode) {
        case OtpMode.phoneSignUp:
          await _verifyPhoneSignUp(otp);
          break;

        case OtpMode.phoneLogin:
          await _verifyPhoneLogin(otp);
          break;

        case OtpMode.phoneChange:
          await _verifyPhoneChange(otp);
          break;

        case OtpMode.emailSignUp:
          await _verifyEmailOtp(
            otp: otp,
            purpose: AuthService.emailSignUpPurpose,
          );
          break;

        case OtpMode.emailLogin:
          await _verifyEmailOtp(
            otp: otp,
            purpose: AuthService.emailLoginPurpose,
          );
          break;

        case OtpMode.emailChange:
          await _verifyEmailOtp(
            otp: otp,
            purpose: AuthService.emailChangePurpose,
          );
          break;
      }
    } on FirebaseAuthException catch (error) {
      _showMessage(_firebaseAuthMessage(error));
    } on FirebaseFunctionsException catch (error) {
      _showMessage(_functionsMessage(error));
    } on StateError catch (error) {
      _showMessage(error.message);
    } on ArgumentError catch (error) {
      _showMessage(
        error.message?.toString() ?? 'Invalid verification information.',
      );
    } catch (error, stackTrace) {
      debugPrint('JR CALL OTP verification error: $error');

      debugPrintStack(
        label: 'JR CALL OTP verification',
        stackTrace: stackTrace,
      );

      _showMessage('Verification could not be completed. Please try again.');
    } finally {
      if (mounted && !_completed && !_automaticVerificationRunning) {
        _setLoading(false);
      }
    }
  }

  PhoneAuthCredential _createPhoneCredential(String otp) {
    return _authService.createPhoneCredential(
      verificationId: _verificationId,
      smsCode: otp,
    );
  }

  // =============================================================
  // PHONE SIGNUP
  // =============================================================

  Future<void> _verifyPhoneSignUp(String otp) async {
    final PhoneAuthCredential credential = _createPhoneCredential(otp);

    await _completePhoneSignup(credential);
  }

  Future<void> _completePhoneSignup(PhoneAuthCredential credential) async {
    final UserCredential result = await _authService.signInWithPhoneCredential(
      credential,
    );

    final User? user = result.user ?? _authService.currentUser;

    if (user == null) {
      throw StateError('The verified Firebase user is unavailable.');
    }

    final bool firebaseCreatedUser =
        result.additionalUserInfo?.isNewUser == true;

    final UserModel? existing = await _firestoreService.getUser(user.uid);

    if (!firebaseCreatedUser && existing != null) {
      await _safeSignOut();

      throw StateError(
        'An account already exists with this Phone Number. Use Login instead.',
      );
    }

    if (existing == null) {
      await _createMinimumSignupProfile(user);
    }

    await _firestoreService.syncAuthenticationProfile(
      uid: user.uid,
      email: user.email ?? _normalizedOptionalEmail,
      phoneNumber: user.phoneNumber ?? widget.phoneNumber.trim(),
      emailVerified: user.emailVerified,
      phoneVerified: true,
      signInProviders: _authService.linkedProviderIds,
    );

    _completeWithSuccess();
  }

  Future<void> _createMinimumSignupProfile(User user) async {
    final String phoneNumber = user.phoneNumber?.trim().isNotEmpty == true
        ? user.phoneNumber!.trim()
        : widget.phoneNumber.trim();

    if (phoneNumber.isEmpty) {
      throw StateError('The verified Phone Number is unavailable.');
    }

    final DateTime now = DateTime.now();

    for (int attempt = 0; attempt < _maximumJrCallIdAttempts; attempt++) {
      final String publicId = attempt == 0 && _jrCallIdCandidate != null
          ? _jrCallIdCandidate!
          : _generateJrCallUserId();

      final UserModel model = UserModel(
        uid: user.uid,
        name: _fullName,
        phone: phoneNumber,
        email: user.email ?? _normalizedOptionalEmail,
        username: _username,
        userAddress: publicId,
        photoUrl: null,
        coverPhoto: null,
        bio: _bio,
        country: _country,
        countryCode: _countryCode,
        dateOfBirth: _dateOfBirth,
        online: true,
        verified: true,
        createdAt: now,
        updatedAt: now,
        lastSeen: now,
        lastLogin: now,
        provider: 'phone',
        isBlocked: false,
        isDeleted: false,
      );

      try {
        await _firestoreService.createUser(model);

        return;
      } on StateError catch (error) {
        if (error.message.toLowerCase().contains('jr call user address')) {
          continue;
        }

        rethrow;
      }
    }

    throw StateError('A unique JR CALL User ID could not be created.');
  }

  String _generateJrCallUserId() {
    final String randomPart = _uuid
        .v4()
        .replaceAll('-', '')
        .substring(0, 12)
        .toLowerCase();

    return 'jrcall_$randomPart';
  }

  // =============================================================
  // PHONE LOGIN
  // =============================================================

  Future<void> _verifyPhoneLogin(String otp) async {
    final PhoneAuthCredential credential = _createPhoneCredential(otp);

    await _completePhoneLogin(credential);
  }

  Future<void> _completePhoneLogin(PhoneAuthCredential credential) async {
    final UserCredential result = await _authService.signInWithPhoneCredential(
      credential,
    );

    final User? user = result.user ?? _authService.currentUser;

    if (user == null) {
      throw StateError('The authenticated Firebase user is unavailable.');
    }

    if (result.additionalUserInfo?.isNewUser == true) {
      try {
        await user.delete();
      } catch (_) {
        await _safeSignOut();
      }

      throw StateError(
        'No existing JR CALL account was found for this Phone Number.',
      );
    }

    final UserModel? profile = await _firestoreService.getUser(user.uid);

    if (profile == null) {
      await _safeSignOut();

      throw StateError(
        'This account does not have an existing JR CALL profile.',
      );
    }

    if (profile.isDeleted || profile.isBlocked) {
      await _safeSignOut();

      throw StateError('This JR CALL account is currently unavailable.');
    }

    final DateTime now = DateTime.now();

    await _firestoreService.updateUser(
      profile.copyWith(
        phone: user.phoneNumber ?? profile.phone,
        email: user.email ?? profile.email,
        online: true,
        verified: true,
        updatedAt: now,
        lastSeen: now,
        lastLogin: now,
      ),
    );

    await _firestoreService.syncAuthenticationProfile(
      uid: user.uid,
      email: user.email,
      phoneNumber: user.phoneNumber,
      emailVerified: user.emailVerified,
      phoneVerified: true,
      signInProviders: _authService.linkedProviderIds,
    );

    _completeWithSuccess();
  }

  // =============================================================
  // PHONE CHANGE
  // =============================================================

  Future<void> _verifyPhoneChange(String otp) async {
    final PhoneAuthCredential credential = _createPhoneCredential(otp);

    await _completePhoneChange(credential);
  }

  Future<void> _completePhoneChange(PhoneAuthCredential credential) async {
    _requireCurrentUser();

    await _authService.updatePhoneNumber(credential);

    final User user = _requireCurrentUser();

    final UserModel? profile = await _firestoreService.getUser(user.uid);

    if (profile != null) {
      await _firestoreService.updateUser(
        profile.copyWith(
          phone: user.phoneNumber ?? widget.phoneNumber.trim(),
          verified: true,
          updatedAt: DateTime.now(),
        ),
      );
    }

    await _firestoreService.syncAuthenticationProfile(
      uid: user.uid,
      email: user.email,
      phoneNumber: user.phoneNumber,
      emailVerified: user.emailVerified,
      phoneVerified: true,
      signInProviders: _authService.linkedProviderIds,
    );

    _completeWithSuccess();
  }

  // =============================================================
  // EMAIL OTP
  // =============================================================

  Future<void> _verifyEmailOtp({
    required String otp,
    required String purpose,
  }) async {
    final String challengeId = (_emailChallengeId ?? _verificationId).trim();

    if (challengeId.isEmpty) {
      throw StateError('No Email verification challenge is available.');
    }

    final EmailOtpVerificationResult result = await _authService.verifyEmailOtp(
      challengeId: challengeId,
      otp: otp,
      purpose: purpose,
    );

    if (!result.success || !result.verified) {
      throw StateError('Email verification failed.');
    }

    final User user = _requireCurrentUser();

    final UserModel? profile = await _firestoreService.getUser(user.uid);

    if (profile != null) {
      final DateTime now = DateTime.now();

      await _firestoreService.updateUser(
        profile.copyWith(
          email: user.email ?? profile.email,
          verified: true,
          online: true,
          updatedAt: now,
          lastSeen: now,
          lastLogin: now,
        ),
      );
    }

    await _firestoreService.syncAuthenticationProfile(
      uid: user.uid,
      email: user.email ?? _normalizedOptionalEmail,
      phoneNumber: user.phoneNumber,
      emailVerified: true,
      phoneVerified: user.phoneNumber?.trim().isNotEmpty == true,
      signInProviders: _authService.linkedProviderIds,
    );

    _completeWithSuccess();
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

      if (!mounted || _completed) {
        return;
      }

      _otpController.clear();

      _restartResendTimer();

      _showMessage('A new verification code has been sent.');
    } on FirebaseAuthException catch (error) {
      _showMessage(_firebaseAuthMessage(error));
    } on FirebaseFunctionsException catch (error) {
      _showMessage(_functionsMessage(error));
    } on StateError catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted && !_completed) {
        setState(() {
          _resending = false;
        });
      }
    }
  }

  Future<void> _resendEmailOtp() async {
    final String email = widget.email?.trim().isNotEmpty == true
        ? widget.email!.trim()
        : _authService.currentEmail ?? '';

    if (email.isEmpty) {
      throw StateError('No Email address is available.');
    }

    final EmailOtpChallenge challenge;

    switch (_mode) {
      case OtpMode.emailSignUp:
        challenge = await _authService.sendEmailSignUpOtp(email: email);
        break;

      case OtpMode.emailLogin:
        challenge = await _authService.sendEmailLoginOtp(email: email);
        break;

      case OtpMode.emailChange:
        challenge = await _authService.sendEmailChangeOtp(email: email);
        break;

      default:
        throw StateError('Email resend is not available in Phone mode.');
    }

    _emailChallengeId = challenge.challengeId;

    _verificationId = challenge.challengeId;
  }

  Future<void> _resendPhoneOtp() async {
    final String phoneNumber = widget.phoneNumber.trim();

    await _authService.resendPhoneVerificationCode(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) {
        if (_completed || _automaticVerificationRunning) {
          return;
        }

        _automaticVerificationRunning = true;

        unawaited(_handleAutomaticCredential(credential));
      },
      verificationFailed: (FirebaseAuthException error) {
        _showMessage(_firebaseAuthMessage(error));
      },
      codeSent: (String verificationId) {
        _verificationId = verificationId.trim();
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId.trim();
      },
      codeSentWithToken: (String verificationId, int? resendToken) {
        _verificationId = verificationId.trim();
      },
    );
  }

  Future<void> _handleAutomaticCredential(
    PhoneAuthCredential credential,
  ) async {
    if (mounted) {
      _setLoading(true);
    }

    try {
      switch (_mode) {
        case OtpMode.phoneSignUp:
          await _completePhoneSignup(credential);
          break;

        case OtpMode.phoneLogin:
          await _completePhoneLogin(credential);
          break;

        case OtpMode.phoneChange:
          await _completePhoneChange(credential);
          break;

        default:
          return;
      }
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString());
      }
    } finally {
      _automaticVerificationRunning = false;

      if (mounted && !_completed) {
        _setLoading(false);
      }
    }
  }

  // =============================================================
  // TIMER
  // =============================================================

  void _startResendTimer() {
    _resendTimer?.cancel();

    _resendRemaining = _resendCooldownSeconds;

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
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
    });
  }

  void _restartResendTimer() {
    _startResendTimer();
  }

  // =============================================================
  // SUCCESS -> HOME
  // =============================================================

  void _completeWithSuccess() {
    if (!mounted || _completed) {
      return;
    }

    _completed = true;

    _resendTimer?.cancel();

    TextInput.finishAutofillContext(shouldSave: false);

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      (Route<dynamic> route) => false,
    );
  }

  void _cancelVerification() {
    if (!mounted ||
        _completed ||
        _loading ||
        _resending ||
        _automaticVerificationRunning) {
      return;
    }

    _resendTimer?.cancel();

    Navigator.of(context).pop<bool>(false);
  }

  // =============================================================
  // HELPERS
  // =============================================================

  String? get _normalizedOptionalEmail {
    final String value = widget.email?.trim().toLowerCase() ?? '';

    return value.isEmpty ? null : value;
  }

  User _requireCurrentUser() {
    final User? user = _authService.currentUser;

    if (user == null) {
      throw StateError('The authenticated Firebase user is unavailable.');
    }

    return user;
  }

  Future<void> _safeSignOut() async {
    try {
      await _authService.signOut();
    } catch (_) {}
  }

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

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  String? _readString(Object? value) {
    if (value is! String) {
      return null;
    }

    final String normalized = value.trim();

    return normalized.isEmpty ? null : normalized;
  }

  String? _normalizeUsername(String? value) {
    if (value == null) {
      return null;
    }

    String normalized = value.trim().toLowerCase();

    if (normalized.startsWith('@')) {
      normalized = normalized.substring(1);
    }

    return normalized.isEmpty ? null : normalized;
  }

  String _firebaseAuthMessage(FirebaseAuthException error) {
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

      default:
        return error.message ?? 'Verification failed.';
    }
  }

  String _functionsMessage(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'invalid-argument':
        return error.message ?? 'The OTP request is invalid.';

      case 'not-found':
        return 'The OTP challenge was not found or has expired.';

      case 'deadline-exceeded':
        return 'The OTP has expired. Request a new code.';

      case 'permission-denied':
        return error.message ?? 'OTP verification was not authorized.';

      case 'resource-exhausted':
        return error.message ?? 'Too many OTP attempts were made.';

      case 'failed-precondition':
        return error.message ?? 'OTP verification cannot continue right now.';

      case 'unauthenticated':
        return 'The authentication session expired.';

      case 'unavailable':
        return 'The Email OTP service is temporarily unavailable.';

      case 'internal':
        return 'The Email OTP service encountered an internal error.';

      default:
        return error.message ?? 'Email OTP verification failed.';
    }
  }

  String get _destination {
    if (_isEmailMode) {
      return widget.email?.trim().isNotEmpty == true
          ? widget.email!.trim()
          : _authService.currentEmail ?? 'your Email';
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
    }
  }

  String get _screenSubtitle => 'Enter the 6-digit code sent to $_destination';

  // =============================================================
  // UI
  // =============================================================

  @override
  Widget build(BuildContext context) {
    final bool actionBusy =
        _loading || _resending || _automaticVerificationRunning;

    final double screenWidth = MediaQuery.sizeOf(context).width;

    final double availableWidth = (screenWidth - 92).clamp(240.0, 430.0);

    final double fieldWidth = ((availableWidth - 50) / 6).clamp(36.0, 48.0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && !actionBusy) {
          _cancelVerification();
        }
      },
      child: Scaffold(
        backgroundColor: JrColors.background,
        appBar: AppBar(
          backgroundColor: JrColors.surface,
          foregroundColor: JrColors.textPrimary,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            'JR CALL',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(22, 30, 22, 24),
                  decoration: BoxDecoration(
                    color: JrColors.surface,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: JrColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.045),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: AutofillGroup(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: JrColors.primaryBlue.withValues(alpha: 0.08),
                          ),
                          child: Icon(
                            _isEmailMode
                                ? Icons.mark_email_read_outlined
                                : Icons.sms_outlined,
                            size: 42,
                            color: JrColors.primaryBlue,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          _screenTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 26,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                            color: JrColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _screenSubtitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: JrColors.textSecondary,
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: availableWidth,
                          child: PinCodeTextField(
                            appContext: context,
                            controller: _otpController,
                            length: _otpLength,
                            keyboardType: TextInputType.number,
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            animationType: AnimationType.fade,
                            autoFocus: true,
                            enableActiveFill: true,
                            enablePinAutofill: true,
                            useExternalAutoFillGroup: true,
                            autoUnfocus: true,
                            autoDisposeControllers: false,
                            textInputAction: TextInputAction.done,
                            cursorColor: JrColors.primaryBlue,
                            textStyle: const TextStyle(
                              color: JrColors.textPrimary,
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                            ),
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            pinTheme: PinTheme(
                              shape: PinCodeFieldShape.box,
                              borderRadius: BorderRadius.circular(13),
                              fieldHeight: 56,
                              fieldWidth: fieldWidth,
                              activeColor: JrColors.primaryBlue,
                              selectedColor: JrColors.primaryBlue,
                              inactiveColor: JrColors.border,
                              activeFillColor: const Color(0xFFF8FAFC),
                              selectedFillColor: const Color(0xFFEFF6FF),
                              inactiveFillColor: const Color(0xFFF8FAFC),
                            ),
                            onChanged: (_) {},
                            onCompleted: (_) {
                              if (!actionBusy) {
                                unawaited(_verifyOtp());
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: FilledButton(
                            onPressed: actionBusy ? null : _verifyOtp,
                            style: FilledButton.styleFrom(
                              backgroundColor: JrColors.primaryBlue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(17),
                              ),
                            ),
                            child: _loading || _automaticVerificationRunning
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'VERIFY OTP',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_resendRemaining > 0)
                          Text(
                            'Resend code in $_resendRemaining seconds',
                            style: const TextStyle(
                              color: JrColors.textSecondary,
                            ),
                          )
                        else
                          TextButton.icon(
                            onPressed: actionBusy ? null : _resendOtp,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text(
                              'RESEND OTP',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: actionBusy ? null : _cancelVerification,
                          child: const Text(
                            'Back',
                            style: TextStyle(color: JrColors.textSecondary),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            _isEmailMode
                                ? 'Email verification is securely processed by JR CALL.'
                                : 'SMS verification is securely processed by Firebase Authentication.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: JrColors.textSecondary,
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
// ===============================================================
