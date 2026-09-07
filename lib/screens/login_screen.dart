// ===============================================================
// JR CALL
// File: login_screen.dart
// Location: lib/screens/login_screen.dart
//
// OTP / AUTH MASTER FILE 04 / 09
//
// GLOBAL PRODUCTION LOGIN SCREEN
//
// LANGUAGE CONTRACT:
//
// - All production user-facing text in this file is English.
// - No hard-coded Bengali or mixed-language production messages.
// - Full multilingual localization can be added later through the
//   centralized JR CALL localization/i18n system.
//
// GUEST MODE:
//
// - Login is optional for browsing JR CALL.
// - Protected actions may open this screen with guestReturn=true.
// - Successful direct login returns to the protected caller when possible.
//
// FINAL LOGIN CONTRACT:
//
// EMAIL LOGIN:
//
// Email + Password
//      ↓
// Firebase Authentication
//      ↓
// Existing JR CALL Profile
//      ↓
// Login Complete
//
// IMPORTANT:
//
// ✓ NO Email OTP during normal Email Login.
// ✓ NO Email verification requirement during normal Email Login.
// ✓ Email + Password must belong to an existing Firebase/JR CALL account.
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
// SMS OTP / automatic verification
//      ↓
// Firebase UID
//
// IMPORTANT:
//
// ✓ Phone Login always requires Firebase Phone verification.
// ✓ Phone Login does NOT require a password.
// ✓ A Phone password can never bypass Phone OTP.
// ✓ NO phoneAccountExists() pre-login blocker.
// ✓ NO fake/local OTP.
// ✓ NO OTP persistence.
// ✓ NO Play Integrity/reCAPTCHA bypass.
//
// AUTHORITY:
//
// ✓ Firebase Authentication is the authentication authority.
// ✓ A successfully authenticated Firebase Phone user is never
//   signed out merely because a nested route returned null/false.
// ✓ Blocked/deleted account protection remains intact.
// ✓ Existing legitimate sessions are never revoked by route cleanup.
//
// GLOBAL PHONE SUPPORT:
//
// ✓ IntlPhoneField keeps the international country selector.
// ✓ E.164 international Phone Numbers are supported.
// ✓ Device locale is used only for the initial country selection.
// ✓ Users can manually select any supported country.
//
// PASSWORD RECOVERY:
//
// Existing ForgotPasswordScreen flow remains unchanged.
//
// PROTECTED:
//
// ✓ Call Engine untouched.
// ✓ Message Engine untouched.
// ✓ WebRTC untouched.
// ✓ Signaling untouched.
//
// ===============================================================

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

import '../core/theme/jr_colors.dart';
import '../core/theme/jr_typography.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firebase/firestore_service.dart';
import '../services/profile_service.dart';
import 'create_account_screen.dart';
import 'create_profile_setup_screen.dart';
import 'forgot_password_screen.dart';
import 'home_screen.dart';
import 'login_otp_manager.dart';
import 'otp_screen.dart';

// ===============================================================
// LOGIN METHOD
// ===============================================================

enum _LoginMethod { email, phone }

// ===============================================================
// LOGIN SCREEN
// ===============================================================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

// ===============================================================
// LOGIN SCREEN STATE
// ===============================================================

class _LoginScreenState extends State<LoginScreen> {
  // =============================================================
  // SERVICES
  // =============================================================

  final AuthService _authService = AuthService.instance;

  final FirestoreService _firestoreService = FirestoreService.instance;

  final ProfileService _profileService = ProfileService.instance;

  late final LoginOtpManager _loginOtpManager;

  // =============================================================
  // CONTROLLERS
  // =============================================================

  final TextEditingController _emailController = TextEditingController();

  final TextEditingController _passwordController = TextEditingController();

  final TextEditingController _phoneController = TextEditingController();

  // =============================================================
  // FOCUS NODES
  // =============================================================

  final FocusNode _emailFocus = FocusNode();

  final FocusNode _passwordFocus = FocusNode();

  final FocusNode _phoneFocus = FocusNode();

  // =============================================================
  // LOGIN STATE
  // =============================================================

  _LoginMethod _method = _LoginMethod.email;

  String _completePhoneNumber = '';

  String? _requestedAction;

  bool _guestReturn = false;

  bool _routeArgumentsResolved = false;

  bool _loading = false;

  bool _showPassword = false;

  bool _otpRouteRunning = false;

  bool _automaticPhoneVerificationRunning = false;

  LoginOtpResult? _pendingAutomaticPhoneResult;

  // =============================================================
  // BUSY STATE
  // =============================================================

  bool get _busy {
    return _loading ||
        _otpRouteRunning ||
        _automaticPhoneVerificationRunning ||
        _loginOtpManager.isBusy;
  }

  // =============================================================
  // GLOBAL INITIAL COUNTRY
  //
  // Uses the device locale only as an initial convenience.
  //
  // This does NOT restrict the country selector.
  // =============================================================

  String get _initialCountryCode {
    final String rawCode =
        WidgetsBinding.instance.platformDispatcher.locale.countryCode
            ?.trim()
            .toUpperCase() ??
        '';

    if (RegExp(r'^[A-Z]{2}$').hasMatch(rawCode)) {
      return rawCode;
    }

    return 'US';
  }

  // =============================================================
  // INIT
  // =============================================================

  @override
  void initState() {
    super.initState();

    _loginOtpManager = LoginOtpManager(
      authService: _authService,
      firestoreService: _firestoreService,
    );
  }

  // =============================================================
  // ROUTE ARGUMENTS
  // =============================================================

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_routeArgumentsResolved) {
      return;
    }

    _routeArgumentsResolved = true;

    final Object? arguments = ModalRoute.of(context)?.settings.arguments;

    if (arguments is! Map) {
      return;
    }

    final Map<String, dynamic> data = Map<String, dynamic>.from(arguments);

    _guestReturn = data['guestReturn'] == true;

    final Object? requestedAction = data['requestedAction'];

    if (requestedAction is String && requestedAction.trim().isNotEmpty) {
      _requestedAction = requestedAction.trim();
    }
  }

  // =============================================================
  // DISPOSE
  // =============================================================

  @override
  void dispose() {
    _loginOtpManager.cancel();

    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();

    _emailFocus.dispose();
    _passwordFocus.dispose();
    _phoneFocus.dispose();

    super.dispose();
  }

  // =============================================================
  // LOGIN
  // =============================================================

  Future<void> _login() async {
    if (_busy) {
      return;
    }

    FocusScope.of(context).unfocus();

    if (_method == _LoginMethod.email) {
      await _loginWithEmail();
      return;
    }

    await _loginWithPhone();
  }

  // =============================================================
  // EMAIL LOGIN
  //
  // FINAL CONTRACT:
  //
  // Email + Password
  //      ↓
  // Firebase signInWithEmailAndPassword()
  //      ↓
  // Existing JR CALL profile
  //      ↓
  // Login complete
  //
  // NO Email OTP.
  // =============================================================

  Future<void> _loginWithEmail() async {
    if (_busy) {
      return;
    }

    final String email = _normalizeEmail(_emailController.text);

    final String password = _passwordController.text;

    if (!_isValidEmail(email)) {
      _showMessage('Enter a valid email address.');

      return;
    }

    if (password.isEmpty) {
      _showMessage('Enter your password.');

      return;
    }

    _setLoading(true);

    bool signedIn = false;

    try {
      final UserCredential credential = await _authService
          .signInWithEmailPassword(email: email, password: password);

      final User? user = credential.user ?? _authService.currentUser;

      if (user == null || user.uid.trim().isEmpty) {
        throw StateError('The authenticated Firebase user is unavailable.');
      }

      signedIn = true;

      // ---------------------------------------------------------
      // EMAIL LOGIN IS FOR AN EXISTING JR CALL ACCOUNT.
      //
      // Account creation remains Phone-owned.
      //
      // A Firebase Email user without users/{uid} must NOT silently
      // become a new JR CALL account from the Login screen.
      // ---------------------------------------------------------

      final UserModel profile = await _requireExistingProfile(user.uid);

      _assertProfileCanLogin(profile);

      // ---------------------------------------------------------
      // PRESERVE EXISTING PROFILE.
      //
      // Synchronize authentication-owned metadata only.
      // ---------------------------------------------------------

      await _firestoreService.syncAuthenticationProfile(
        uid: user.uid,
        email: user.email,
        phoneNumber: user.phoneNumber,
        emailVerified: user.emailVerified,
        phoneVerified: user.phoneNumber?.trim().isNotEmpty ?? false,
        signInProviders: _authService.linkedProviderIds,
      );

      if (!mounted) {
        return;
      }

      TextInput.finishAutofillContext(shouldSave: true);

      _setLoading(false);

      // ---------------------------------------------------------
      // DIRECT SUCCESS.
      //
      // NO sendEmailLoginOtp().
      // NO Email OtpScreen.
      // ---------------------------------------------------------

      _finishSuccessfulLogin();
    } on FirebaseAuthException catch (error) {
      if (signedIn) {
        await _safeSignOut();
      }

      _showMessage(_firebaseAuthMessage(error));
    } on StateError catch (error) {
      if (signedIn) {
        await _safeSignOut();
      }

      _showMessage(error.message);
    } catch (error, stackTrace) {
      if (signedIn) {
        await _safeSignOut();
      }

      debugPrint('JR CALL Email Login error: $error');

      debugPrintStack(label: 'JR CALL Email Login', stackTrace: stackTrace);

      _showMessage('Login could not be completed. Please try again.');
    } finally {
      if (mounted && !_otpRouteRunning) {
        _setLoading(false);
      }
    }
  }

  // =============================================================
  // PHONE LOGIN
  //
  // Phone OTP implementation is owned by LoginOtpManager.
  //
  // Phone Login ALWAYS enters Firebase Phone verification.
  // =============================================================

  Future<void> _loginWithPhone() async {
    if (_busy) {
      return;
    }

    final String localNumber = _phoneController.text.trim();

    final String phoneNumber = localNumber.isEmpty
        ? ''
        : _normalizePhone(_completePhoneNumber);

    if (localNumber.isEmpty || !_isValidE164Phone(phoneNumber)) {
      _showMessage('Enter a valid phone number with the correct country code.');

      return;
    }

    _pendingAutomaticPhoneResult = null;

    _setLoading(true);

    try {
      await _loginOtpManager.startPhoneLogin(
        phoneNumber: phoneNumber,

        // -------------------------------------------------------
        // MANUAL OTP
        // -------------------------------------------------------
        onCodeSent: (String verificationId) {
          if (!mounted ||
              _automaticPhoneVerificationRunning ||
              _pendingAutomaticPhoneResult != null) {
            return;
          }

          final String cleanVerificationId = verificationId.trim();

          if (cleanVerificationId.isEmpty) {
            _setLoading(false);

            _showMessage(
              'The OTP verification session is unavailable. Request a new code.',
            );

            return;
          }

          _setLoading(false);

          unawaited(
            _handleManualPhoneOtp(
              verificationId: cleanVerificationId,
              phoneNumber: phoneNumber,
            ),
          );
        },

        // -------------------------------------------------------
        // AUTOMATIC FIREBASE PHONE VERIFICATION
        // -------------------------------------------------------
        onAutomaticVerified: (LoginOtpResult result) {
          if (!mounted) {
            return;
          }

          unawaited(_receiveAutomaticPhoneResult(result));
        },

        // -------------------------------------------------------
        // FAILURE
        // -------------------------------------------------------
        onVerificationFailed: (FirebaseAuthException error) {
          if (!mounted) {
            return;
          }

          _setLoading(false);

          _showMessage(_firebaseAuthMessage(error));
        },

        // -------------------------------------------------------
        // AUTO RETRIEVAL TIMEOUT
        //
        // Manual OTP remains valid.
        // -------------------------------------------------------
        onAutoRetrievalTimeout: (String verificationId) {
          if (!mounted || _automaticPhoneVerificationRunning) {
            return;
          }

          if (!_otpRouteRunning) {
            _setLoading(false);
          }
        },
      );
    } on FirebaseAuthException catch (error) {
      _showMessage(_firebaseAuthMessage(error));
    } on ArgumentError catch (error) {
      _showMessage(error.message?.toString() ?? 'The phone number is invalid.');
    } on StateError catch (error) {
      _showMessage(error.message);
    } catch (error, stackTrace) {
      debugPrint('JR CALL Phone Login error: $error');

      debugPrintStack(label: 'JR CALL Phone Login', stackTrace: stackTrace);

      _showMessage(
        'Phone verification could not be started. Please try again.',
      );
    } finally {
      if (mounted &&
          !_otpRouteRunning &&
          !_automaticPhoneVerificationRunning &&
          !_loginOtpManager.isBusy) {
        _setLoading(false);
      }
    }
  }

  // =============================================================
  // MANUAL PHONE OTP
  //
  // IMPORTANT:
  //
  // Firebase Authentication is authoritative.
  //
  // A nested OTP/Profile route returning null/false must NEVER
  // destroy a valid Firebase Phone session.
  // =============================================================

  Future<void> _handleManualPhoneOtp({
    required String verificationId,
    required String phoneNumber,
  }) async {
    if (!mounted || _otpRouteRunning || _automaticPhoneVerificationRunning) {
      return;
    }

    final bool verified = await _openPhoneOtpScreen(
      verificationId: verificationId,
      phoneNumber: phoneNumber,
    );

    if (!mounted) {
      return;
    }

    // -----------------------------------------------------------
    // AUTOMATIC VERIFICATION MAY HAVE FINISHED WHILE THE MANUAL
    // OTP SCREEN WAS OPEN.
    // -----------------------------------------------------------

    final LoginOtpResult? automaticResult = _takePendingAutomaticPhoneResult();

    if (automaticResult != null) {
      await _handleAutomaticPhoneResult(automaticResult);

      return;
    }

    // -----------------------------------------------------------
    // OtpScreen reported explicit success.
    //
    // OtpScreen owns successful manual Phone OTP routing.
    // -----------------------------------------------------------

    if (verified) {
      return;
    }

    // -----------------------------------------------------------
    // ROUTE RESULT WAS FALSE / NULL.
    //
    // OLD BROKEN BEHAVIOR:
    //
    // Any existing Firebase currentUser was signed out here.
    //
    // CORRECT PRODUCTION BEHAVIOR:
    //
    // A valid Firebase session remains authoritative.
    //
    // If Firebase currently holds the exact Phone identity that
    // this login attempt requested, authentication has already
    // succeeded and the session must be preserved.
    // -----------------------------------------------------------

    final User? authenticatedUser = _authService.currentUser;

    if (authenticatedUser == null || authenticatedUser.uid.trim().isEmpty) {
      // Genuine cancelled/incomplete authentication.
      return;
    }

    final String authenticatedPhone = _normalizePhone(
      authenticatedUser.phoneNumber ?? '',
    );

    if (authenticatedPhone.isEmpty || authenticatedPhone != phoneNumber) {
      // Never sign out an unrelated legitimate Firebase session.
      return;
    }

    // -----------------------------------------------------------
    // Firebase has an authenticated user for the exact requested
    // Phone Number.
    //
    // Preserve the authenticated session and complete login.
    // -----------------------------------------------------------

    _finishSuccessfulLogin();
  }

  // =============================================================
  // AUTOMATIC PHONE RESULT
  // =============================================================

  Future<void> _receiveAutomaticPhoneResult(LoginOtpResult result) async {
    if (!mounted) {
      return;
    }

    _pendingAutomaticPhoneResult = result;

    // -----------------------------------------------------------
    // IF MANUAL OTP SCREEN IS OPEN:
    //
    // Close it and process the automatic Firebase result here.
    // -----------------------------------------------------------

    if (_otpRouteRunning) {
      final NavigatorState navigator = Navigator.of(context);

      if (navigator.canPop()) {
        navigator.pop<bool>(true);
      }

      return;
    }

    final LoginOtpResult? pending = _takePendingAutomaticPhoneResult();

    if (pending == null) {
      return;
    }

    await _handleAutomaticPhoneResult(pending);
  }

  // =============================================================
  // TAKE PENDING AUTOMATIC RESULT
  // =============================================================

  LoginOtpResult? _takePendingAutomaticPhoneResult() {
    final LoginOtpResult? result = _pendingAutomaticPhoneResult;

    _pendingAutomaticPhoneResult = null;

    return result;
  }

  // =============================================================
  // HANDLE AUTOMATIC PHONE RESULT
  // =============================================================

  Future<void> _handleAutomaticPhoneResult(LoginOtpResult result) async {
    if (!mounted || _automaticPhoneVerificationRunning) {
      return;
    }

    _automaticPhoneVerificationRunning = true;

    _setLoading(true);

    try {
      // ---------------------------------------------------------
      // EXISTING JR CALL ACCOUNT
      // ---------------------------------------------------------

      if (result.hasExistingProfile) {
        _finishSuccessfulLogin();

        return;
      }

      // ---------------------------------------------------------
      // NEW FIREBASE PHONE ACCOUNT
      //
      // Phone has already been verified by Firebase.
      //
      // Create the minimum JR CALL profile identity and then open
      // optional Profile Setup.
      // ---------------------------------------------------------

      if (result.requiresProfileSetup) {
        await _profileService.ensureCurrentProfile(generateJrCallUserId: true);

        if (!mounted) {
          return;
        }

        await _openNewPhoneProfileSetup();

        if (!mounted) {
          return;
        }

        // -------------------------------------------------------
        // Profile Setup may simply return to LoginScreen.
        //
        // If the exact authenticated Firebase UID is still active,
        // login is complete.
        // -------------------------------------------------------

        final User? currentUser = _authService.currentUser;

        if (currentUser != null &&
            currentUser.uid.trim().isNotEmpty &&
            currentUser.uid.trim() == result.user.uid.trim()) {
          _finishSuccessfulLogin();
        }

        return;
      }

      throw StateError('The Phone authentication state is invalid.');
    } on FirebaseAuthException catch (error) {
      _showMessage(_firebaseAuthMessage(error));
    } on StateError catch (error) {
      _showMessage(error.message);
    } catch (error, stackTrace) {
      debugPrint('JR CALL automatic Phone Login error: $error');

      debugPrintStack(
        label: 'JR CALL automatic Phone Login',
        stackTrace: stackTrace,
      );

      _showMessage(
        'Phone verification could not be completed. Please try again.',
      );
    } finally {
      _automaticPhoneVerificationRunning = false;

      if (mounted && !_otpRouteRunning) {
        _setLoading(false);
      }
    }
  }

  // =============================================================
  // NEW PHONE PROFILE SETUP
  // =============================================================

  Future<void> _openNewPhoneProfileSetup() async {
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const CreateProfileSetupScreen(),
      ),
    );
  }

  // =============================================================
  // PHONE OTP SCREEN
  //
  // Normal Email Login NEVER enters this route.
  // =============================================================

  Future<bool> _openPhoneOtpScreen({
    required String verificationId,
    required String phoneNumber,
  }) async {
    if (!mounted || _otpRouteRunning) {
      return false;
    }

    _otpRouteRunning = true;

    try {
      final bool? result = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          settings: RouteSettings(
            arguments: <String, dynamic>{
              'mode': 'phoneLogin',
              'guestReturn': _guestReturn,
              if (_requestedAction != null) 'requestedAction': _requestedAction,
            },
          ),
          builder: (BuildContext context) => OtpScreen(
            verificationId: verificationId,
            phoneNumber: phoneNumber,
            email: '',
            provider: 'phone_login',
          ),
        ),
      );

      return result == true;
    } finally {
      _otpRouteRunning = false;
    }
  }

  // =============================================================
  // PROFILE VALIDATION
  // =============================================================

  Future<UserModel> _requireExistingProfile(String uid) async {
    final String normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      throw StateError('The authenticated Firebase UID is unavailable.');
    }

    final UserModel? profile = await _firestoreService.getUser(normalizedUid);

    if (profile == null) {
      throw StateError(
        'This Firebase account is not linked to an existing JR CALL profile.',
      );
    }

    return profile;
  }

  // =============================================================
  // PROFILE LOGIN PERMISSION
  // =============================================================

  void _assertProfileCanLogin(UserModel profile) {
    if (profile.isDeleted || profile.isBlocked) {
      throw StateError('This JR CALL account is currently unavailable.');
    }
  }

  // =============================================================
  // SUCCESS
  // =============================================================

  void _finishSuccessfulLogin() {
    if (!mounted) {
      return;
    }

    // -----------------------------------------------------------
    // PROTECTED ACTION LOGIN
    //
    // Return to caller.
    // -----------------------------------------------------------

    if (_guestReturn && Navigator.of(context).canPop()) {
      Navigator.of(context).pop<bool>(true);

      return;
    }

    // -----------------------------------------------------------
    // NORMAL LOGIN
    // -----------------------------------------------------------

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const HomeScreen(),
      ),
      (Route<dynamic> route) => false,
    );
  }

  // =============================================================
  // CONTINUE AS GUEST
  // =============================================================

  void _continueAsGuest() {
    if (!mounted || _busy) {
      return;
    }

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop<bool>(false);

      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const HomeScreen(),
      ),
      (Route<dynamic> route) => false,
    );
  }

  // =============================================================
  // FORGOT PASSWORD
  //
  // Recovery flow remains separate from normal Email Login.
  // =============================================================

  Future<void> _openForgotPassword() async {
    if (_busy) {
      return;
    }

    FocusScope.of(context).unfocus();

    final String initialEmail = _method == _LoginMethod.email
        ? _emailController.text.trim()
        : '';

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ForgotPasswordScreen(initialValue: initialEmail),
      ),
    );
  }

  // =============================================================
  // CREATE ACCOUNT
  //
  // Phone-required account creation is owned by:
  //
  // CreateAccountScreen
  // CreateAccountOtpManager
  // AuthService
  // =============================================================

  Future<void> _openCreateAccount() async {
    if (_busy) {
      return;
    }

    FocusScope.of(context).unfocus();

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: RouteSettings(
          arguments: <String, dynamic>{
            'guestReturn': _guestReturn,
            if (_requestedAction != null) 'requestedAction': _requestedAction,
          },
        ),
        builder: (BuildContext context) => const CreateAccountScreen(),
      ),
    );
  }

  // =============================================================
  // SELECT LOGIN METHOD
  // =============================================================

  void _selectMethod(_LoginMethod method) {
    if (_busy || _method == method) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _method = method;
    });
  }

  // =============================================================
  // EMAIL NORMALIZATION
  // =============================================================

  String _normalizeEmail(String value) {
    return value.trim().toLowerCase();
  }

  // =============================================================
  // PHONE NORMALIZATION
  // =============================================================

  String _normalizePhone(String value) {
    return value.trim().replaceAll(RegExp(r'[\s\-()]'), '');
  }

  // =============================================================
  // EMAIL VALIDATION
  // =============================================================

  bool _isValidEmail(String value) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);
  }

  // =============================================================
  // E.164 PHONE VALIDATION
  // =============================================================

  bool _isValidE164Phone(String value) {
    return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value);
  }

  // =============================================================
  // SAFE SIGN OUT
  //
  // IMPORTANT:
  //
  // This method remains available for genuine rejected account
  // states and Email Login cleanup.
  //
  // It is NEVER called merely because an OTP route returned
  // false/null.
  // =============================================================

  Future<void> _safeSignOut() async {
    try {
      await _authService.signOut();
    } catch (error) {
      debugPrint('JR CALL safe sign-out skipped: $error');
    }
  }

  // =============================================================
  // FIREBASE AUTH ERROR TEXT
  // =============================================================

  String _firebaseAuthMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-credential':
      case 'wrong-password':
        return 'The email address or password is incorrect.';

      case 'user-not-found':
        return 'No JR CALL account was found for this email address.';

      case 'invalid-email':
        return 'The email address is invalid.';

      case 'user-disabled':
        return 'This account has been disabled.';

      case 'invalid-phone-number':
        return 'The phone number is invalid.';

      case 'invalid-verification-code':
        return 'The verification code is incorrect.';

      case 'invalid-verification-id':
        return 'The verification session is invalid. Request a new OTP.';

      case 'operation-not-allowed':
        return 'This sign-in method is not enabled in Firebase.';

      case 'too-many-requests':
        return 'Too many attempts were made. Please try again later.';

      case 'quota-exceeded':
        return 'The OTP service quota has been reached. Please try again later.';

      case 'network-request-failed':
        return 'A network connection could not be established. Check your internet connection.';

      case 'app-not-authorized':
        return 'This application is not authorized for Firebase Authentication.';

      case 'invalid-app-credential':
        return 'Firebase could not verify this application.';

      case 'captcha-check-failed':
        return 'Firebase security verification failed. Please try again.';

      case 'session-expired':
        return 'The verification session has expired. Request a new OTP.';

      case 'verification-in-progress':
        return 'Phone verification is already in progress.';

      case 'phone-login-state-error':
        return error.message ?? 'The Phone authentication state is invalid.';

      case 'phone-login-invalid-argument':
        return error.message ??
            'The Phone authentication information is invalid.';

      case 'phone-verification-failed':
        return error.message ?? 'Phone verification could not be completed.';

      default:
        return error.message ?? 'Authentication failed. Please try again.';
    }
  }

  // =============================================================
  // UI HELPERS
  // =============================================================

  void _setLoading(bool value) {
    if (!mounted || _loading == value) {
      return;
    }

    setState(() {
      _loading = value;
    });
  }

  // =============================================================
  // MESSAGE
  // =============================================================

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

  // =============================================================
  // FIELD DECORATION
  // =============================================================

  InputDecoration _fieldDecoration({
    required String hintText,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(19),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      hintText: hintText,
      hintStyle: JrTypography.inputHint,
      prefixIcon: Icon(icon, color: JrColors.primaryBlue),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 19),
      border: border(JrColors.border),
      enabledBorder: border(JrColors.border),
      focusedBorder: border(JrColors.primaryBlue, 1.5),
    );
  }

  // =============================================================
  // UI
  // =============================================================

  @override
  Widget build(BuildContext context) {
    final bool emailMode = _method == _LoginMethod.email;

    return Scaffold(
      backgroundColor: JrColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AutofillGroup(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
                  decoration: BoxDecoration(
                    color: JrColors.surface,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: JrColors.border),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.045),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Align(
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: JrColors.primaryBlue.withValues(alpha: 0.08),
                          ),
                          child: const Icon(
                            Icons.phone_in_talk_rounded,
                            color: JrColors.primaryBlue,
                            size: 42,
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      Text(
                        'JR CALL',
                        textAlign: TextAlign.center,
                        style: JrTypography.brandTitle,
                      ),

                      const SizedBox(height: 6),

                      Text(
                        _requestedAction == null
                            ? 'Secure Global Login'
                            : 'Sign in to $_requestedAction',
                        textAlign: TextAlign.center,
                        style: JrTypography.screenSubtitle,
                      ),

                      const SizedBox(height: 26),

                      // =================================================
                      // EMAIL / PHONE SELECTOR
                      // =================================================
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F3F7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: _MethodButton(
                                selected: emailMode,
                                icon: Icons.email_outlined,
                                label: 'Email',
                                onTap: () => _selectMethod(_LoginMethod.email),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: _MethodButton(
                                selected: !emailMode,
                                icon: Icons.phone_outlined,
                                label: 'Phone',
                                onTap: () => _selectMethod(_LoginMethod.phone),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 26),

                      // =================================================
                      // EMAIL LOGIN
                      // =================================================
                      if (emailMode) ...<Widget>[
                        TextField(
                          controller: _emailController,
                          focusNode: _emailFocus,
                          enabled: !_busy,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const <String>[
                            AutofillHints.email,
                            AutofillHints.username,
                          ],
                          autocorrect: false,
                          enableSuggestions: false,
                          style: JrTypography.inputText,
                          onSubmitted: (String value) {
                            _passwordFocus.requestFocus();
                          },
                          decoration: _fieldDecoration(
                            hintText: 'Email Address',
                            icon: Icons.email_outlined,
                          ),
                        ),

                        const SizedBox(height: 18),

                        TextField(
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          enabled: !_busy,
                          obscureText: !_showPassword,
                          keyboardType: TextInputType.visiblePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const <String>[AutofillHints.password],
                          autocorrect: false,
                          enableSuggestions: false,
                          style: JrTypography.inputText,
                          onSubmitted: (String value) {
                            if (!_busy) {
                              unawaited(_login());
                            }
                          },
                          decoration: _fieldDecoration(
                            hintText: 'Password',
                            icon: Icons.lock_outline,
                            suffixIcon: IconButton(
                              onPressed: _busy
                                  ? null
                                  : () {
                                      setState(() {
                                        _showPassword = !_showPassword;
                                      });
                                    },
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: JrColors.primaryBlue,
                              ),
                            ),
                          ),
                        ),

                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _busy ? null : _openForgotPassword,
                            child: Text(
                              'Forgot Password?',
                              style: JrTypography.link,
                            ),
                          ),
                        ),
                      ],

                      // =================================================
                      // PHONE LOGIN
                      // =================================================
                      if (!emailMode) ...<Widget>[
                        IntlPhoneField(
                          controller: _phoneController,
                          focusNode: _phoneFocus,
                          enabled: !_busy,
                          initialCountryCode: _initialCountryCode,
                          disableLengthCheck: true,
                          disableAutoFillHints: false,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.done,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: JrTypography.inputText,
                          dropdownTextStyle: JrTypography.inputText,
                          dropdownIcon: const Icon(
                            Icons.arrow_drop_down,
                            color: JrColors.primaryBlue,
                          ),
                          decoration: _fieldDecoration(
                            hintText: 'Phone Number',
                            icon: Icons.phone_outlined,
                          ),
                          onChanged: (phone) {
                            if (_phoneController.text.trim().isEmpty) {
                              _completePhoneNumber = '';

                              return;
                            }

                            _completePhoneNumber = _normalizePhone(
                              phone.completeNumber,
                            );
                          },
                          onCountryChanged: (country) {
                            if (_phoneController.text.trim().isEmpty) {
                              _completePhoneNumber = '';
                            }
                          },
                          onSubmitted: (String value) {
                            if (!_busy) {
                              unawaited(_login());
                            }
                          },
                        ),

                        const SizedBox(height: 18),
                      ],

                      // =================================================
                      // LOGIN BUTTON
                      // =================================================
                      SizedBox(
                        height: 56,
                        child: FilledButton(
                          onPressed: _busy ? null : _login,
                          child:
                              _loading ||
                                  _automaticPhoneVerificationRunning ||
                                  _loginOtpManager.isBusy
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  emailMode ? 'LOGIN WITH EMAIL' : 'SEND OTP',
                                  style: JrTypography.buttonLabel,
                                ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // =================================================
                      // GUEST
                      // =================================================
                      TextButton.icon(
                        onPressed: _busy ? null : _continueAsGuest,
                        icon: const Icon(Icons.public_rounded),
                        label: const Text(
                          'CONTINUE AS GUEST',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // =================================================
                      // SECURITY INFO
                      // =================================================
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Icon(
                              Icons.verified_user_outlined,
                              color: JrColors.textSecondary,
                              size: 21,
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Text(
                                emailMode
                                    ? 'Email login uses your Firebase email address and password directly.'
                                    : 'Phone login uses secure Firebase SMS verification with automatic or manual OTP verification.',
                                style: JrTypography.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // =================================================
                      // CREATE ACCOUNT
                      // =================================================
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              "Don't have an account?",
                              style: JrTypography.bodySecondary,
                            ),
                          ),
                          TextButton(
                            onPressed: _busy ? null : _openCreateAccount,
                            child: Text(
                              'Create Account',
                              style: JrTypography.link,
                            ),
                          ),
                        ],
                      ),
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
// METHOD BUTTON
// ===============================================================

class _MethodButton extends StatelessWidget {
  const _MethodButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;

  final IconData icon;

  final String label;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? JrColors.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                icon,
                size: 22,
                color: selected ? JrColors.primaryBlue : JrColors.textSecondary,
              ),
              const SizedBox(width: 9),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? JrColors.textPrimary
                      : JrColors.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===============================================================
// END OF FILE
//
// OTP / AUTH MASTER FILE 04 / 09
//
// FIXED:
//
// ✓ Manual Phone OTP route false/null no longer signs out a valid
//   Firebase authenticated user.
//
// ✓ Exact authenticated Firebase Phone Number is checked before
//   fallback login completion.
//
// ✓ Unrelated legitimate Firebase sessions are not destroyed.
//
// ✓ Automatic new-profile Phone authentication completes Login
//   after optional Profile Setup returns.
//
// ✓ Missing Firebase currentUser remains an incomplete/cancelled
//   authentication state.
//
// GLOBAL:
//
// ✓ All hard-coded production user-facing strings are English.
// ✓ No Bengali production strings remain in this file.
// ✓ International Phone country selector preserved.
// ✓ Device locale provides the initial country selection only.
// ✓ E.164 international Phone validation preserved.
//
// PRESERVED:
//
// ✓ Email + Password Login.
// ✓ Existing JR CALL profile requirement for Email Login.
// ✓ Phone OTP through LoginOtpManager.
// ✓ Firebase automatic Phone verification.
// ✓ Manual 6-digit Phone OTP.
// ✓ New-profile creation ownership.
// ✓ Guest mode.
// ✓ requestedAction.
// ✓ Profile Setup.
// ✓ Forgot Password.
// ✓ Create Account.
// ✓ Existing UI structure.
// ✓ Existing JR theme/colors/typography.
// ✓ No fake OTP.
// ✓ No OTP persistence.
// ✓ No Phone-password bypass.
// ✓ No Play Integrity/reCAPTCHA bypass.
//
// UNCHANGED:
//
// ✓ login_otp_manager.dart.
// ✓ AuthService API.
// ✓ FirestoreService API.
// ✓ ProfileService API.
// ✓ Call Engine.
// ✓ Message Engine.
// ✓ WebRTC.
// ✓ Signaling.
//
// ===============================================================
