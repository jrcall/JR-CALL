// ===============================================================
// JR CALL
// File: login_screen.dart
// Location: lib/screens/login_screen.dart
//
// GUEST MODE:
// - Login is optional for browsing JR CALL.
// - Protected actions may open this screen with guestReturn=true.
// - Successful direct login returns to the protected caller when possible.
// - Email: Password -> Firebase -> JR CALL Email OTP.
// - Phone: Existing account -> Firebase SMS OTP.
// - No fake/local OTP.
// ===============================================================

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

import '../core/theme/jr_colors.dart';
import '../core/theme/jr_typography.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firebase/firestore_service.dart';
import 'create_account_screen.dart';
import 'forgot_password_screen.dart';
import 'home_screen.dart';
import 'otp_screen.dart';

enum _LoginMethod { email, phone }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService.instance;
  final FirestoreService _firestoreService = FirestoreService.instance;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();

  _LoginMethod _method = _LoginMethod.email;

  String _completePhoneNumber = '';
  String? _requestedAction;

  bool _guestReturn = false;
  bool _routeArgumentsResolved = false;
  bool _loading = false;
  bool _showPassword = false;
  bool _otpRouteRunning = false;
  bool _automaticPhoneVerificationRunning = false;

  bool get _busy =>
      _loading || _otpRouteRunning || _automaticPhoneVerificationRunning;

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

  @override
  void dispose() {
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
    } else {
      await _loginWithPhone();
    }
  }

  // =============================================================
  // EMAIL LOGIN
  // =============================================================

  Future<void> _loginWithEmail() async {
    if (_busy) {
      return;
    }

    final String email = _normalizeEmail(_emailController.text);
    final String password = _passwordController.text;

    if (!_isValidEmail(email)) {
      _showMessage('সঠিক Email Address দিন।');
      return;
    }

    if (password.isEmpty) {
      _showMessage('Password দিন।');
      return;
    }

    _setLoading(true);

    bool signedIn = false;

    try {
      final UserCredential credential = await _authService
          .signInWithEmailPassword(email: email, password: password);

      final User? user = credential.user ?? _authService.currentUser;

      if (user == null) {
        throw StateError('Authenticated Firebase user পাওয়া যায়নি।');
      }

      signedIn = true;

      final UserModel profile = await _requireExistingProfile(user.uid);

      _assertProfileCanLogin(profile);

      final EmailOtpChallenge challenge = await _authService.sendEmailLoginOtp(
        email: email,
      );

      if (!mounted) {
        return;
      }

      TextInput.finishAutofillContext(shouldSave: true);

      _setLoading(false);

      final bool verified = await _openOtpScreen(
        verificationId: challenge.challengeId,
        phoneNumber: '',
        email: email,
        provider: 'email_login',
        mode: 'emailLogin',
      );

      if (!verified &&
          mounted &&
          _authService.currentUser != null &&
          !_guestReturn) {
        await _safeSignOut();
      }
    } on FirebaseAuthException catch (error) {
      if (signedIn) {
        await _safeSignOut();
      }

      _showMessage(_firebaseAuthMessage(error));
    } on FirebaseFunctionsException catch (error) {
      if (signedIn) {
        await _safeSignOut();
      }

      _showMessage(_functionsMessage(error));
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

      _showMessage('Login সম্পন্ন করা যায়নি। আবার চেষ্টা করুন।');
    } finally {
      if (mounted && !_otpRouteRunning) {
        _setLoading(false);
      }
    }
  }

  // =============================================================
  // PHONE LOGIN
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
      _showMessage('Country code সহ সঠিক Phone Number দিন।');
      return;
    }

    _setLoading(true);

    try {
      final bool exists = await _authService.phoneAccountExists(
        phoneNumber: phoneNumber,
      );

      if (!exists) {
        _showMessage(
          'এই Phone Number-এর JR CALL account পাওয়া যায়নি। Create Account ব্যবহার করুন।',
        );
        return;
      }

      await _authService.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) {
          unawaited(
            _handleAutomaticPhoneVerification(
              credential: credential,
              phoneNumber: phoneNumber,
            ),
          );
        },
        verificationFailed: (FirebaseAuthException error) {
          if (!mounted) {
            return;
          }

          _setLoading(false);
          _showMessage(_firebaseAuthMessage(error));
        },
        codeSent: (String verificationId) {
          if (!mounted ||
              _otpRouteRunning ||
              _automaticPhoneVerificationRunning) {
            return;
          }

          _setLoading(false);

          unawaited(
            _handleManualPhoneOtp(
              verificationId: verificationId,
              phoneNumber: phoneNumber,
            ),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (mounted &&
              !_otpRouteRunning &&
              !_automaticPhoneVerificationRunning) {
            _setLoading(false);
          }
        },
      );
    } on FirebaseFunctionsException catch (error) {
      _showMessage(_functionsMessage(error));
    } on FirebaseAuthException catch (error) {
      _showMessage(_firebaseAuthMessage(error));
    } on ArgumentError catch (error) {
      _showMessage(error.message?.toString() ?? 'Invalid Phone Number.');
    } on StateError catch (error) {
      _showMessage(error.message);
    } catch (error, stackTrace) {
      debugPrint('JR CALL Phone Login error: $error');

      debugPrintStack(label: 'JR CALL Phone Login', stackTrace: stackTrace);

      _showMessage('Phone verification শুরু করা যায়নি।');
    } finally {
      if (mounted && !_otpRouteRunning && !_automaticPhoneVerificationRunning) {
        _setLoading(false);
      }
    }
  }

  // =============================================================
  // MANUAL PHONE OTP
  // =============================================================

  Future<void> _handleManualPhoneOtp({
    required String verificationId,
    required String phoneNumber,
  }) async {
    final bool verified = await _openOtpScreen(
      verificationId: verificationId,
      phoneNumber: phoneNumber,
      email: '',
      provider: 'phone_login',
      mode: 'phoneLogin',
    );

    if (!mounted) {
      return;
    }

    if (verified) {
      _finishSuccessfulLogin();
      return;
    }

    if (!_guestReturn && _authService.currentUser != null) {
      await _safeSignOut();
    }
  }

  // =============================================================
  // AUTOMATIC PHONE OTP
  // =============================================================

  Future<void> _handleAutomaticPhoneVerification({
    required PhoneAuthCredential credential,
    required String phoneNumber,
  }) async {
    if (_automaticPhoneVerificationRunning || _otpRouteRunning) {
      return;
    }

    _automaticPhoneVerificationRunning = true;

    if (mounted) {
      _setLoading(true);
    }

    try {
      final UserCredential result = await _authService
          .signInWithPhoneCredential(credential);

      final User? user = result.user ?? _authService.currentUser;

      if (user == null) {
        throw StateError('Authenticated Firebase user পাওয়া যায়নি।');
      }

      if (result.additionalUserInfo?.isNewUser == true) {
        try {
          await user.delete();
        } catch (error) {
          debugPrint('JR CALL temporary Phone user cleanup failed: $error');

          await _safeSignOut();
        }

        throw StateError(
          'এই Phone Number-এর existing JR CALL account পাওয়া যায়নি।',
        );
      }

      final UserModel profile = await _requireExistingProfile(user.uid);

      _assertProfileCanLogin(profile);

      await _syncPhoneProfile(
        user: user,
        phoneNumber: phoneNumber,
        profile: profile,
      );

      if (!mounted) {
        return;
      }

      _finishSuccessfulLogin();
    } on FirebaseAuthException catch (error) {
      await _safeSignOut();
      _showMessage(_firebaseAuthMessage(error));
    } on StateError catch (error) {
      await _safeSignOut();
      _showMessage(error.message);
    } catch (error, stackTrace) {
      await _safeSignOut();

      debugPrint('JR CALL automatic Phone Login error: $error');

      debugPrintStack(
        label: 'JR CALL automatic Phone Login',
        stackTrace: stackTrace,
      );

      _showMessage(
        'Automatic verification সম্পন্ন হয়নি। SMS OTP ব্যবহার করুন।',
      );
    } finally {
      _automaticPhoneVerificationRunning = false;

      if (mounted && !_otpRouteRunning) {
        _setLoading(false);
      }
    }
  }

  // =============================================================
  // OTP SCREEN
  // =============================================================

  Future<bool> _openOtpScreen({
    required String verificationId,
    required String phoneNumber,
    required String email,
    required String provider,
    required String mode,
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
              'mode': mode,
              if (mode.startsWith('email'))
                'emailOtpChallengeId': verificationId,
              'guestReturn': _guestReturn,
              if (_requestedAction != null) 'requestedAction': _requestedAction,
            },
          ),
          builder: (BuildContext context) => OtpScreen(
            verificationId: verificationId,
            phoneNumber: phoneNumber,
            email: email,
            provider: provider,
          ),
        ),
      );

      return result == true;
    } finally {
      _otpRouteRunning = false;
    }
  }

  // =============================================================
  // PROFILE VALIDATION / SYNC
  // =============================================================

  Future<UserModel> _requireExistingProfile(String uid) async {
    final UserModel? profile = await _firestoreService.getUser(uid);

    if (profile == null) {
      throw StateError('এই account-এর JR CALL profile পাওয়া যায়নি।');
    }

    return profile;
  }

  void _assertProfileCanLogin(UserModel profile) {
    if (profile.isDeleted || profile.isBlocked) {
      throw StateError('এই JR CALL account বর্তমানে ব্যবহার করা যাবে না।');
    }
  }

  Future<void> _syncPhoneProfile({
    required User user,
    required String phoneNumber,
    required UserModel profile,
  }) async {
    final DateTime now = DateTime.now();

    final String resolvedPhone = user.phoneNumber?.trim().isNotEmpty == true
        ? user.phoneNumber!.trim()
        : phoneNumber;

    await _firestoreService.updateUser(
      profile.copyWith(
        phone: resolvedPhone,
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
      phoneNumber: resolvedPhone,
      emailVerified: user.emailVerified,
      phoneVerified: true,
      signInProviders: _authService.linkedProviderIds,
    );
  }

  // =============================================================
  // SUCCESS
  // =============================================================

  void _finishSuccessfulLogin() {
    if (!mounted) {
      return;
    }

    if (_guestReturn && Navigator.of(context).canPop()) {
      Navigator.of(context).pop<bool>(true);
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
  // GUEST / CREATE / PASSWORD
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

  Future<void> _openForgotPassword() async {
    if (_busy) {
      return;
    }

    FocusScope.of(context).unfocus();

    final String initialEmail = _method == _LoginMethod.email
        ? _emailController.text.trim()
        : '';

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ForgotPasswordScreen(initialValue: initialEmail),
      ),
    );
  }

  Future<void> _openCreateAccount() async {
    if (_busy) {
      return;
    }

    FocusScope.of(context).unfocus();

    await Navigator.of(context).push(
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
  // METHOD
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
  // VALIDATION
  // =============================================================

  String _normalizeEmail(String value) => value.trim().toLowerCase();

  String _normalizePhone(String value) =>
      value.trim().replaceAll(RegExp(r'[\s\-()]'), '');

  bool _isValidEmail(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);

  bool _isValidE164Phone(String value) =>
      RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value);

  Future<void> _safeSignOut() async {
    try {
      await _authService.signOut();
    } catch (error) {
      debugPrint('JR CALL safe sign-out skipped: $error');
    }
  }

  // =============================================================
  // ERROR TEXT
  // =============================================================

  String _firebaseAuthMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-credential':
      case 'wrong-password':
        return 'Email অথবা Password সঠিক নয়।';

      case 'user-not-found':
        return 'এই Email-এর JR CALL account পাওয়া যায়নি।';

      case 'invalid-email':
        return 'Email Address সঠিক নয়।';

      case 'user-disabled':
        return 'এই account disable করা হয়েছে।';

      case 'invalid-phone-number':
        return 'Phone Number সঠিক নয়।';

      case 'operation-not-allowed':
        return 'এই Login method Firebase-এ enabled নয়।';

      case 'too-many-requests':
        return 'অনেকবার চেষ্টা করা হয়েছে। কিছুক্ষণ পরে আবার চেষ্টা করুন।';

      case 'quota-exceeded':
        return 'OTP service quota শেষ হয়েছে।';

      case 'network-request-failed':
        return 'Internet connection check করুন।';

      case 'app-not-authorized':
        return 'Firebase application configuration verify করুন।';

      case 'invalid-app-credential':
        return 'Firebase এই application verify করতে পারেনি।';

      case 'captcha-check-failed':
        return 'Firebase security verification failed।';

      case 'session-expired':
        return 'Verification session expired। নতুন OTP request করুন।';

      default:
        return error.message ?? 'Authentication failed.';
    }
  }

  String _functionsMessage(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'unauthenticated':
        return 'Login session expired। আবার Login করুন।';

      case 'permission-denied':
        return error.message ?? 'এই request অনুমোদিত নয়।';

      case 'invalid-argument':
        return error.message ?? 'Request information সঠিক নয়।';

      case 'failed-precondition':
        return error.message ?? 'Verification এখন শুরু করা যাচ্ছে না।';

      case 'resource-exhausted':
        return 'অনেকবার request করা হয়েছে। কিছুক্ষণ পরে চেষ্টা করুন।';

      case 'deadline-exceeded':
        return 'Verification service timeout হয়েছে।';

      case 'unavailable':
        return 'Verification service সাময়িকভাবে unavailable।';

      case 'not-found':
        return 'Required JR CALL backend function পাওয়া যাচ্ছে না।';

      case 'internal':
        return 'Verification service internal error দিয়েছে।';

      default:
        return error.message ?? 'Verification request সম্পন্ন হয়নি।';
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

                      // -----------------------------------------
                      // METHOD SELECTOR
                      // -----------------------------------------
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

                      // -----------------------------------------
                      // EMAIL
                      // -----------------------------------------
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

                      // -----------------------------------------
                      // PHONE
                      // -----------------------------------------
                      if (!emailMode) ...<Widget>[
                        IntlPhoneField(
                          controller: _phoneController,
                          focusNode: _phoneFocus,
                          enabled: !_busy,
                          initialCountryCode: 'BD',
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

                      // -----------------------------------------
                      // LOGIN BUTTON
                      // -----------------------------------------
                      SizedBox(
                        height: 56,
                        child: FilledButton(
                          onPressed: _busy ? null : _login,
                          child: _loading || _automaticPhoneVerificationRunning
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

                      // -----------------------------------------
                      // GUEST
                      // -----------------------------------------
                      TextButton.icon(
                        onPressed: _busy ? null : _continueAsGuest,
                        icon: const Icon(Icons.public_rounded),
                        label: const Text(
                          'CONTINUE AS GUEST',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),

                      const SizedBox(height: 12),

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
                                    ? 'Email login uses your password and JR CALL secure Email OTP verification.'
                                    : 'Existing Phone accounts use secure Firebase SMS OTP verification.',
                                style: JrTypography.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

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
// ===============================================================
