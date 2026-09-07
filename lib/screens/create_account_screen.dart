// ===============================================================
// JR CALL
// File: create_account_screen.dart
// Location: lib/screens/create_account_screen.dart
//
// OTP / AUTH MASTER FILE 05 / 09
//
// FINAL PRODUCTION SIGNUP OWNER
//
// ===============================================================
//
// ACCOUNT CREATION CONTRACT:
//
// Phone Number
//      ↓
// REQUIRED
//      ↓
// CreateAccountOtpManager
//      ↓
// AuthService
//      ↓
// Firebase Phone Authentication
//      ↓
// Verified Firebase Phone UID
//      ↓
// JR CALL Profile
//
// ===============================================================
//
// PHONE:
//
// ✓ Phone Number is mandatory.
// ✓ Phone ownership must be verified by Firebase.
// ✓ Phone OTP cannot be bypassed.
// ✓ Password beside Phone does not replace Phone OTP.
// ✓ Firebase UID is canonical account identity.
// ✓ Existing Phone account must use Login instead.
// ✓ No phoneAccountExists() pre-verification blocker.
// ✓ No fake/local OTP.
// ✓ No OTP persistence.
// ✓ No Firebase security bypass.
//
// ===============================================================
//
// OPTIONAL EMAIL:
//
// Phone-authenticated Firebase UID
//      ↓
// Optional Email + mandatory Password
//      ↓
// EmailAuthProvider credential
//      ↓
// linkWithCredential()
//      ↓
// SAME Firebase UID
//
// IMPORTANT:
//
// ✓ Email is optional during signup.
// ✓ If Email is entered, Password is mandatory.
// ✓ Email signup does NOT require JR CALL Email OTP.
// ✓ Email/Password is linked only AFTER Phone verification.
// ✓ Standalone Email account creation is impossible here.
// ✓ Email/Password never creates a second Firebase UID.
// ✓ Later Email + Password login can directly restore this account.
//
// ===============================================================
//
// OPTIONAL PROFILE:
//
// ✓ Full Name optional.
// ✓ Short Name optional.
// ✓ Date of Birth optional.
// ✓ Profile Photo optional.
// ✓ Cover Photo optional.
// ✓ Country derives from selected Phone country.
// ✓ JR CALL public User ID generated automatically.
//
// ===============================================================
//
// PROTECTED:
//
// ✓ Call Engine untouched.
// ✓ Message Engine untouched.
// ✓ WebRTC untouched.
// ✓ Signaling untouched.
// ===============================================================

import 'dart:async';

import 'package:country_picker/country_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:uuid/uuid.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firebase/firestore_service.dart';
import '../utils/permissions.dart';
import 'create_account_otp_manager.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'otp_screen.dart';

// ===============================================================
// CREATE ACCOUNT SCREEN
// ===============================================================

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({
    super.key,
  });

  @override
  State<CreateAccountScreen> createState() =>
      _CreateAccountScreenState();
}

// ===============================================================
// CREATE ACCOUNT STATE
// ===============================================================

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  // =============================================================
  // SERVICES
  // =============================================================

  final AuthService _auth = AuthService.instance;

  final FirestoreService _firestore =
      FirestoreService.instance;

  final FirebaseStorage _storage =
      FirebaseStorage.instance;

  final ImagePicker _picker =
  ImagePicker();

  late final CreateAccountOtpManager _otpManager;

  // =============================================================
  // CONSTANTS
  // =============================================================

  static const Uuid _uuid =
  Uuid();

  static const int _profileLimit =
      5 * 1024 * 1024;

  static const int _coverLimit =
      10 * 1024 * 1024;

  static const Color _background =
  Color(0xFFF8FAFF);

  static const Color _surface =
      Colors.white;

  static const Color _blue =
  Color(0xFF1769F5);

  static const Color _blueLight =
  Color(0xFF4194FF);

  static const Color _text =
  Color(0xFF111827);

  static const Color _secondary =
  Color(0xFF68758C);

  static const Color _border =
  Color(0xFFE3E8F1);

  static const Color _field =
  Color(0xFFFBFCFF);

  // =============================================================
  // CONTROLLERS
  // =============================================================

  final TextEditingController _phone =
  TextEditingController();

  final TextEditingController _email =
  TextEditingController();

  final TextEditingController _password =
  TextEditingController();

  final TextEditingController _confirmPassword =
  TextEditingController();

  final TextEditingController _name =
  TextEditingController();

  final TextEditingController _username =
  TextEditingController();

  // =============================================================
  // STATE
  // =============================================================

  int _step = 1;

  String _completePhone = '';

  String _phoneCountryCode = 'BD';

  String? _countryName;

  String? _countryCode;

  DateTime? _dob;

  Uint8List? _profileBytes;

  Uint8List? _coverBytes;

  bool _loading = false;

  bool _pickingMedia = false;

  bool _passwordVisible = false;

  bool _confirmVisible = false;

  bool _automaticSignupRunning = false;

  bool _manualSignupFinalizing = false;

  bool _routeArgumentsResolved = false;

  bool _guestReturn = false;

  String? _requestedAction;

  late final String _jrIdCandidate =
  _generateJrId();

  // =============================================================
  // DERIVED
  // =============================================================

  bool get _busy {
    return _loading ||
        _pickingMedia ||
        _automaticSignupRunning ||
        _manualSignupFinalizing ||
        _otpManager.isBusy ||
        _auth.isCredentialOperationInProgress;
  }

  String get _normalizedEmail {
    return _email.text
        .trim()
        .toLowerCase();
  }

  bool get _hasEmail {
    return _normalizedEmail.isNotEmpty;
  }

  String? get _normalizedUsername {
    return _normalizeUsername(
      _username.text,
    );
  }

  // =============================================================
  // LIFECYCLE
  // =============================================================

  @override
  void initState() {
    super.initState();

    _otpManager =
        CreateAccountOtpManager(
          authService: _auth,
        );

    _initializeCountry();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_routeArgumentsResolved) {
      return;
    }

    _routeArgumentsResolved = true;

    final Object? arguments =
        ModalRoute.of(context)
            ?.settings
            .arguments;

    if (arguments is! Map) {
      return;
    }

    final Map<String, dynamic> data =
    Map<String, dynamic>.from(
      arguments,
    );

    _guestReturn =
        data['guestReturn'] == true;

    final Object? action =
    data['requestedAction'];

    if (action is String &&
        action.trim().isNotEmpty) {
      _requestedAction =
          action.trim();
    }
  }

  @override
  void dispose() {
    _otpManager.dispose();

    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _name.dispose();
    _username.dispose();

    super.dispose();
  }

  // =============================================================
  // COUNTRY INITIALIZATION
  // =============================================================

  void _initializeCountry() {
    try {
      final Country? country =
      Country.tryParse(
        _phoneCountryCode,
      );

      _countryName =
          country?.name;

      _countryCode =
          country?.countryCode
              .toUpperCase() ??
              _phoneCountryCode;
    } catch (error) {
      debugPrint(
        'JR CALL default country resolution skipped: $error',
      );

      _countryCode =
          _phoneCountryCode;
    }
  }

  // =============================================================
  // STEP ONE VALIDATION
  // =============================================================

  void _continue() {
    if (_busy) {
      return;
    }

    FocusScope.of(context)
        .unfocus();

    final String? error =
    _validate();

    if (error != null) {
      _message(
        error,
      );

      return;
    }

    setState(() {
      _step = 2;
    });
  }

  // =============================================================
  // COMPLETE VALIDATION
  // =============================================================

  String? _validate() {
    final String phoneNumber =
    _currentPhone();

    final String email =
        _normalizedEmail;

    final String name =
    _name.text.trim();

    final String? username =
        _normalizedUsername;

    // -----------------------------------------------------------
    // PHONE IS MANDATORY
    // -----------------------------------------------------------

    if (!_isValidPhone(
      phoneNumber,
    )) {
      return 'Enter a valid Phone Number with country code.';
    }

    // -----------------------------------------------------------
    // EMAIL OPTIONAL
    //
    // If Email exists:
    // Password + Confirm Password become mandatory.
    // -----------------------------------------------------------

    if (email.isNotEmpty) {
      if (!_isValidEmail(
        email,
      )) {
        return 'Enter a valid Email address.';
      }

      if (_password.text.isEmpty) {
        return 'Password is required when Email is added.';
      }

      if (_password.text.length < 6) {
        return 'Password must contain at least 6 characters.';
      }

      if (_password.text.length > 4096) {
        return 'Password is too long.';
      }

      if (_confirmPassword.text.isEmpty) {
        return 'Confirm Password is required.';
      }

      if (_password.text !=
          _confirmPassword.text) {
        return 'Password and Confirm Password do not match.';
      }
    }

    // -----------------------------------------------------------
    // NO EMAIL
    //
    // Hidden/stale Password values must not affect Phone-only
    // account creation.
    // -----------------------------------------------------------

    if (name.length > 80) {
      return 'Full Name cannot exceed 80 characters.';
    }

    if (username != null &&
        !_isValidUsername(
          username,
        )) {
      return 'Short Name must be 3-30 characters using letters, '
          'numbers, dots or underscores.';
    }

    final DateTime? dob =
        _dob;

    if (dob != null &&
        dob.isAfter(
          DateTime.now(),
        )) {
      return 'Date of Birth cannot be in the future.';
    }

    return null;
  }

  // =============================================================
  // START ACCOUNT CREATION
  // =============================================================

  Future<void> _createAccount() async {
    if (_busy) {
      return;
    }

    FocusScope.of(context)
        .unfocus();

    final String? error =
    _validate();

    if (error != null) {
      _message(
        error,
      );

      _goStepOne();

      return;
    }

    final String phoneNumber =
    _currentPhone();

    _otpManager.reset();

    _setLoading(
      true,
    );

    try {
      await _otpManager.startVerification(
        phoneNumber:
        phoneNumber,

        // -------------------------------------------------------
        // MANUAL OTP
        // -------------------------------------------------------

        onCodeSent: (
            String verificationId,
            ) async {
          if (!mounted) {
            return;
          }

          final String normalizedId =
          verificationId.trim();

          if (normalizedId.isEmpty) {
            _setLoading(
              false,
            );

            _message(
              'Firebase did not return a valid Phone verification session.',
            );

            return;
          }

          _setLoading(
            false,
          );

          await _openPhoneOtp(
            normalizedId,
          );
        },

        // -------------------------------------------------------
        // AUTOMATIC NATIVE VERIFICATION
        // -------------------------------------------------------

        onAutomaticCredential: (
            PhoneAuthCredential credential,
            ) async {
          if (!mounted) {
            return;
          }

          await _completeAutomaticSignupSafely(
            credential,
          );
        },

        // -------------------------------------------------------
        // FAILURE
        // -------------------------------------------------------

        onVerificationFailed: (
            FirebaseAuthException error,
            ) {
          if (!mounted) {
            return;
          }

          _setLoading(
            false,
          );

          _message(
            _authError(
              error,
            ),
          );
        },

        // -------------------------------------------------------
        // AUTO VERIFICATION WON WHILE OTP SCREEN WAS OPEN
        // -------------------------------------------------------

        onCloseOtpRoute: () {
          if (!mounted ||
              !_otpManager.isOtpRouteOpen) {
            return;
          }

          final NavigatorState navigator =
          Navigator.of(
            context,
          );

          if (navigator.canPop()) {
            navigator.pop<bool>(
              false,
            );
          }
        },

        // -------------------------------------------------------
        // AUTO-RETRIEVAL TIMEOUT
        //
        // Manual OTP remains valid.
        // -------------------------------------------------------

        onAutoRetrievalTimeout: (
            String verificationId,
            ) {
          if (!mounted) {
            return;
          }

          if (!_otpManager.isOtpRouteOpen &&
              !_automaticSignupRunning &&
              !_manualSignupFinalizing) {
            _setLoading(
              false,
            );
          }
        },
      );
    } on FirebaseAuthException catch (error) {
      _setLoading(
        false,
      );

      _message(
        _authError(
          error,
        ),
      );
    } on ArgumentError catch (error) {
      _setLoading(
        false,
      );

      _message(
        error.message?.toString() ??
            'Invalid account information.',
      );
    } on StateError catch (error) {
      _setLoading(
        false,
      );

      _message(
        error.message,
      );
    } catch (error, stackTrace) {
      _setLoading(
        false,
      );

      debugPrint(
        'JR CALL account creation start error: $error',
      );

      debugPrintStack(
        label:
        'JR CALL account creation',
        stackTrace:
        stackTrace,
      );

      _message(
        'Account creation could not be started. Please try again.',
      );
    }
  }

  // =============================================================
  // PHONE OTP SCREEN
  // =============================================================

  Future<void> _openPhoneOtp(
      String verificationId,
      ) async {
    if (!mounted ||
        _automaticSignupRunning ||
        _manualSignupFinalizing) {
      return;
    }

    bool verified = false;

    _otpManager
        .markOtpRouteOpening();

    try {
      final bool? result =
      await Navigator.of(context)
          .push<bool>(
        MaterialPageRoute<bool>(
          settings:
          RouteSettings(
            arguments:
            <String, dynamic>{
              'mode':
              'phoneSignUp',
              'fullName':
              _name.text
                  .trim()
                  .isEmpty
                  ? null
                  : _name.text
                  .trim(),
              'username':
              _normalizedUsername,
              'country':
              _countryName,
              'countryCode':
              _countryCode,
              'dateOfBirth':
              _dob?.toIso8601String(),
              'jrCallUserIdCandidate':
              _jrIdCandidate,
              'guestReturn':
              _guestReturn,
              if (_requestedAction !=
                  null)
                'requestedAction':
                _requestedAction,
            },
          ),
          builder: (
              BuildContext context,
              ) {
            return OtpScreen(
              verificationId:
              verificationId,
              phoneNumber:
              _currentPhone(),
              email:
              _hasEmail
                  ? _normalizedEmail
                  : null,
              provider:
              'phone_signup',
            );
          },
        ),
      );

      verified =
          result == true;
    } finally {
      _otpManager
          .markOtpRouteClosed();
    }

    if (!mounted) {
      return;
    }

    // -----------------------------------------------------------
    // AUTOMATIC VERIFICATION ARRIVED WHILE MANUAL OTP SCREEN OPEN
    // -----------------------------------------------------------

    final PhoneAuthCredential?
    automaticCredential =
    _otpManager
        .takePendingAutomaticCredential();

    if (automaticCredential != null) {
      await _completeAutomaticSignupSafely(
        automaticCredential,
      );

      return;
    }

    // -----------------------------------------------------------
    // MANUAL OTP SUCCEEDED
    // -----------------------------------------------------------

    if (verified) {
      await _finishManualSignup();
    }
  }

  // =============================================================
  // MANUAL PHONE SIGNUP FINALIZATION
  // =============================================================

  Future<void> _finishManualSignup() async {
    if (!mounted ||
        _automaticSignupRunning ||
        _manualSignupFinalizing) {
      return;
    }

    _manualSignupFinalizing = true;

    _setLoading(
      true,
    );

    try {
      User user =
      _requireUser();

      final String? authenticatedPhone =
      _cleanNullable(
        user.phoneNumber,
      );

      if (authenticatedPhone == null) {
        throw StateError(
          'Firebase Phone verification did not provide a verified Phone Number.',
        );
      }

      if (authenticatedPhone !=
          _currentPhone()) {
        throw StateError(
          'Verified Phone Number does not match the signup Phone Number.',
        );
      }

      // ---------------------------------------------------------
      // EXISTING PROFILE
      //
      // Existing Phone identity must use Login, never Signup.
      //
      // The final OtpScreen contract does not create users/{uid}
      // during manual OTP verification. Therefore an existing
      // profile here means an existing JR CALL account.
      // ---------------------------------------------------------

      final UserModel? existingProfile =
      await _firestore.getUser(
        user.uid,
      );

      if (existingProfile != null) {
        await _safeSignOut();

        throw StateError(
          'An account already exists with this Phone Number. Use Login instead.',
        );
      }

      // ---------------------------------------------------------
      // OPTIONAL EMAIL + PASSWORD
      //
      // No Email Signup OTP.
      // Link directly to same Phone-authenticated Firebase UID.
      // ---------------------------------------------------------

      if (_hasEmail) {
        await _linkOptionalEmailPassword();

        user =
            _requireUser();
      }

      // ---------------------------------------------------------
      // OPTIONAL USERNAME UNIQUENESS
      // ---------------------------------------------------------

      final String? username =
          _normalizedUsername;

      if (username != null) {
        final bool available =
        await _firestore
            .isUsernameAvailable(
          username,
          forUid:
          user.uid,
        );

        if (!available) {
          throw StateError(
            'This Short Name is already in use.',
          );
        }
      }

      // ---------------------------------------------------------
      // CREATE JR CALL PROFILE
      // ---------------------------------------------------------

      await _createProfile(
        user,
      );

      await _syncAuthProfile(
        user,
      );

      await _uploadMediaSafely(
        user.uid,
      );

      _finishSignup();
    } on FirebaseAuthException catch (error) {
      _message(
        _authError(
          error,
        ),
      );
    } on FirebaseException catch (error) {
      _message(
        _firebaseError(
          error,
        ),
      );
    } on StateError catch (error) {
      _message(
        error.message,
      );
    } on ArgumentError catch (error) {
      _message(
        error.message?.toString() ??
            'Invalid account information.',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'JR CALL manual signup finalization error: $error',
      );

      debugPrintStack(
        label:
        'JR CALL manual signup finalization',
        stackTrace:
        stackTrace,
      );

      _message(
        'Account setup could not be finalized.',
      );
    } finally {
      _manualSignupFinalizing =
      false;

      if (mounted) {
        _setLoading(
          false,
        );
      }
    }
  }

  // =============================================================
  // AUTOMATIC SIGNUP SAFE ENTRY
  // =============================================================

  Future<void> _completeAutomaticSignupSafely(
      PhoneAuthCredential credential,
      ) async {
    if (!mounted ||
        _automaticSignupRunning ||
        _manualSignupFinalizing) {
      return;
    }

    _automaticSignupRunning =
    true;

    try {
      await _completeAutomaticSignup(
        credential,
      );
    } finally {
      _automaticSignupRunning =
      false;

      _otpManager
          .automaticCompletionFinished();

      if (mounted) {
        setState(() {});
      }
    }
  }

  // =============================================================
  // AUTOMATIC PHONE SIGNUP
  // =============================================================

  Future<void> _completeAutomaticSignup(
      PhoneAuthCredential credential,
      ) async {
    bool createdAuthUser = false;
    bool createdProfile = false;

    _setLoading(
      true,
    );

    try {
      final UserCredential result =
      await _auth
          .signInWithPhoneCredential(
        credential,
      );

      User user =
          result.user ??
              _requireUser();

      final String uid =
      user.uid.trim();

      if (uid.isEmpty) {
        throw StateError(
          'Authenticated Firebase UID was not found.',
        );
      }

      final String? authenticatedPhone =
      _cleanNullable(
        user.phoneNumber,
      );

      if (authenticatedPhone == null) {
        throw StateError(
          'Firebase Phone verification completed without a verified Phone Number.',
        );
      }

      if (authenticatedPhone !=
          _currentPhone()) {
        throw StateError(
          'Verified Phone Number does not match the signup Phone Number.',
        );
      }

      createdAuthUser =
          result.additionalUserInfo
              ?.isNewUser ==
              true;

      // ---------------------------------------------------------
      // EXISTING FIREBASE PHONE IDENTITY
      // ---------------------------------------------------------

      if (!createdAuthUser) {
        await _safeSignOut();

        throw StateError(
          'An account already exists with this Phone Number. Use Login instead.',
        );
      }

      // ---------------------------------------------------------
      // DEFENSIVE PROFILE COLLISION CHECK
      // ---------------------------------------------------------

      final UserModel? existingProfile =
      await _firestore.getUser(
        uid,
      );

      if (existingProfile != null) {
        await _safeSignOut();

        throw StateError(
          'A JR CALL profile already exists for this account. Use Login instead.',
        );
      }

      // ---------------------------------------------------------
      // OPTIONAL EMAIL/PASSWORD
      //
      // Direct link to same verified Phone UID.
      // NO Email OTP.
      // ---------------------------------------------------------

      if (_hasEmail) {
        await _linkOptionalEmailPassword();

        user =
            _requireUser();
      }

      // ---------------------------------------------------------
      // USERNAME
      // ---------------------------------------------------------

      final String? username =
          _normalizedUsername;

      if (username != null) {
        final bool available =
        await _firestore
            .isUsernameAvailable(
          username,
          forUid:
          user.uid,
        );

        if (!available) {
          throw StateError(
            'This Short Name is already in use.',
          );
        }
      }

      // ---------------------------------------------------------
      // CREATE PROFILE
      // ---------------------------------------------------------

      await _createProfile(
        user,
      );

      createdProfile = true;

      await _syncAuthProfile(
        user,
      );

      await _uploadMediaSafely(
        user.uid,
      );

      _finishSignup();
    } on FirebaseAuthException catch (error) {
      if (createdAuthUser &&
          !createdProfile) {
        await _rollbackCurrentUser();
      }

      _message(
        _authError(
          error,
        ),
      );
    } on FirebaseException catch (error) {
      if (createdAuthUser &&
          !createdProfile) {
        await _rollbackCurrentUser();
      }

      _message(
        _firebaseError(
          error,
        ),
      );
    } on StateError catch (error) {
      if (createdAuthUser &&
          !createdProfile) {
        await _rollbackCurrentUser();
      }

      _message(
        error.message,
      );
    } on ArgumentError catch (error) {
      if (createdAuthUser &&
          !createdProfile) {
        await _rollbackCurrentUser();
      }

      _message(
        error.message?.toString() ??
            'Invalid account information.',
      );
    } catch (error, stackTrace) {
      if (createdAuthUser &&
          !createdProfile) {
        await _rollbackCurrentUser();
      }

      debugPrint(
        'JR CALL automatic signup error: $error',
      );

      debugPrintStack(
        label:
        'JR CALL automatic signup',
        stackTrace:
        stackTrace,
      );

      _message(
        'Phone verification could not be completed.',
      );
    } finally {
      if (mounted) {
        _setLoading(
          false,
        );
      }
    }
  }

  // =============================================================
  // OPTIONAL EMAIL/PASSWORD LINK
  //
  // IMPORTANT:
  //
  // Phone verification already established account ownership.
  //
  // Email + Password is linked directly to that same Firebase UID.
  //
  // No Email OTP is used by this signup flow.
  // =============================================================

  Future<void> _linkOptionalEmailPassword() async {
    if (!_hasEmail) {
      return;
    }

    final String email =
        _normalizedEmail;

    final String password =
        _password.text;

    if (!_isValidEmail(
      email,
    )) {
      throw ArgumentError(
        'Enter a valid Email address.',
      );
    }

    if (password.length < 6) {
      throw ArgumentError(
        'Password must contain at least 6 characters.',
      );
    }

    if (password.length > 4096) {
      throw ArgumentError(
        'Password is too long.',
      );
    }

    if (password !=
        _confirmPassword.text) {
      throw ArgumentError(
        'Password and Confirm Password do not match.',
      );
    }

    User userBefore =
    _requireUser();

    final String originalUid =
        userBefore.uid;

    final String? verifiedPhone =
    _cleanNullable(
      userBefore.phoneNumber,
    );

    if (verifiedPhone == null) {
      throw StateError(
        'A Firebase-verified Phone Number is required before adding Email/Password.',
      );
    }

    try {
      await userBefore.reload();

      userBefore =
          _requireUser();
    } catch (error) {
      debugPrint(
        'JR CALL pre-link user reload skipped: $error',
      );
    }

    if (userBefore.uid !=
        originalUid) {
      throw StateError(
        'Authenticated Firebase account changed before Email linking.',
      );
    }

    final bool alreadyLinked =
    userBefore.providerData.any(
          (
          UserInfo provider,
          ) {
        return provider.providerId
            .trim() ==
            'password';
      },
    );

    if (alreadyLinked) {
      final String? existingEmail =
      _cleanNullable(
        userBefore.email,
      )?.toLowerCase();

      if (existingEmail ==
          email) {
        return;
      }

      throw StateError(
        'A different Email/Password login is already linked to this account.',
      );
    }

    final String? existingEmail =
    _cleanNullable(
      userBefore.email,
    )?.toLowerCase();

    if (existingEmail != null &&
        existingEmail != email) {
      throw StateError(
        'A different Email address is already linked to this account.',
      );
    }

    final UserCredential linkedResult =
    await _auth
        .linkEmailPasswordToCurrentUser(
      email:
      email,
      password:
      password,
    );

    User linkedUser =
        linkedResult.user ??
            _requireUser();

    if (linkedUser.uid !=
        originalUid) {
      throw StateError(
        'Email/Password linking changed the Firebase UID.',
      );
    }

    try {
      await linkedUser.reload();

      linkedUser =
          _requireUser();
    } catch (error) {
      debugPrint(
        'JR CALL linked user reload skipped: $error',
      );
    }

    if (linkedUser.uid !=
        originalUid) {
      throw StateError(
        'Email/Password linking did not preserve the Firebase account.',
      );
    }

    final bool passwordLinked =
    linkedUser.providerData.any(
          (
          UserInfo provider,
          ) {
        return provider.providerId
            .trim() ==
            'password';
      },
    );

    final String? linkedEmail =
    _cleanNullable(
      linkedUser.email,
    )?.toLowerCase();

    if (!passwordLinked ||
        linkedEmail != email) {
      throw StateError(
        'Email Login could not be safely linked to this account.',
      );
    }

    final String? linkedPhone =
    _cleanNullable(
      linkedUser.phoneNumber,
    );

    if (linkedPhone == null) {
      throw StateError(
        'Phone identity was lost while linking Email/Password.',
      );
    }
  }

  // =============================================================
  // CREATE PROFILE
  // =============================================================

  Future<void> _createProfile(
      User user,
      ) async {
    const int attempts = 8;

    final String uid =
    user.uid.trim();

    if (uid.isEmpty) {
      throw StateError(
        'Authenticated Firebase UID is invalid.',
      );
    }

    final String authPhone =
        user.phoneNumber
            ?.trim() ??
            '';

    final String resolvedPhone =
    authPhone.isNotEmpty
        ? authPhone
        : _currentPhone();

    if (!_isValidPhone(
      resolvedPhone,
    )) {
      throw StateError(
        'A verified Phone Number is required to create a JR CALL profile.',
      );
    }

    for (int index = 0;
    index < attempts;
    index++) {
      final String publicId =
      index == 0
          ? _jrIdCandidate
          : _generateJrId();

      final DateTime now =
      DateTime.now();

      final String authEmail =
          user.email
              ?.trim()
              .toLowerCase() ??
              '';

      final List<String> providers =
          _auth.linkedProviderIds;

      final bool passwordLinked =
      providers.contains(
        'password',
      );

      final UserModel model =
      UserModel(
        uid:
        uid,
        name:
        _name.text.trim(),
        phone:
        resolvedPhone,
        email:
        authEmail.isEmpty
            ? null
            : authEmail,
        username:
        _normalizedUsername,
        userAddress:
        publicId,
        photoUrl:
        null,
        coverPhoto:
        null,
        bio:
        null,
        country:
        _countryName,
        countryCode:
        _countryCode,
        dateOfBirth:
        _dob,
        online:
        true,
        verified:
        true,
        emailVerified:
        user.emailVerified,
        phoneVerified:
        true,
        signInProviders:
        providers,
        isDiscoverable:
        true,
        isDiscoverableByEmail:
        authEmail.isNotEmpty,
        isDiscoverableByPhone:
        true,
        createdAt:
        now,
        updatedAt:
        now,
        lastSeen:
        now,
        lastLogin:
        now,
        provider:
        passwordLinked
            ? 'phone_email'
            : 'phone',
        isBlocked:
        false,
        isDeleted:
        false,
      );

      try {
        await _firestore.createUser(
          model,
        );

        return;
      } on StateError catch (error) {
        final String message =
        error.message
            .toLowerCase();

        if (message.contains(
          'jr call user address',
        )) {
          continue;
        }

        rethrow;
      }
    }

    throw StateError(
      'A unique JR CALL User ID could not be generated.',
    );
  }

  // =============================================================
  // AUTH PROFILE SYNC
  // =============================================================

  Future<void> _syncAuthProfile(
      User user,
      ) async {
    User effectiveUser =
        user;

    try {
      await user.reload();

      effectiveUser =
          _auth.currentUser ??
              user;
    } catch (error) {
      debugPrint(
        'JR CALL user reload skipped: $error',
      );
    }

    final String uid =
    effectiveUser.uid.trim();

    if (uid.isEmpty) {
      throw StateError(
        'Authenticated Firebase UID is invalid.',
      );
    }

    final String phone =
        effectiveUser.phoneNumber
            ?.trim() ??
            '';

    if (!_isValidPhone(
      phone,
    )) {
      throw StateError(
        'Verified Phone Number is missing from Firebase Authentication.',
      );
    }

    await _firestore
        .syncAuthenticationProfile(
      uid:
      uid,
      email:
      effectiveUser.email,
      phoneNumber:
      phone,
      emailVerified:
      effectiveUser.emailVerified,
      phoneVerified:
      true,
      signInProviders:
      _auth.linkedProviderIds,
    );
  }

  // =============================================================
  // FINAL ROUTING
  // =============================================================

  void _finishSignup() {
    if (!mounted) {
      return;
    }

    _otpManager.reset();

    TextInput.finishAutofillContext(
      shouldSave:
      true,
    );

    if (_guestReturn &&
        Navigator.of(context)
            .canPop()) {
      Navigator.of(context)
          .pop<bool>(
        true,
      );

      return;
    }

    Navigator.of(context)
        .pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (
            BuildContext context,
            ) {
          return const HomeScreen();
        },
      ),
          (
          Route<dynamic> route,
          ) {
        return false;
      },
    );
  }

  // =============================================================
  // ROLLBACK INCOMPLETE NEW AUTH USER
  // =============================================================

  Future<void> _rollbackCurrentUser() async {
    final User? user =
        _auth.currentUser;

    if (user == null) {
      return;
    }

    try {
      await user.delete();

      _auth.clearPhoneVerificationState();
    } catch (error) {
      debugPrint(
        'JR CALL Auth rollback delete failed: $error',
      );

      await _safeSignOut();
    }
  }

  // =============================================================
  // SAFE SIGN OUT
  // =============================================================

  Future<void> _safeSignOut() async {
    _otpManager.reset();

    try {
      await _auth.signOut();
    } catch (error) {
      debugPrint(
        'JR CALL safe sign-out skipped: $error',
      );
    }
  }

  // =============================================================
  // REQUIRE USER
  // =============================================================

  User _requireUser() {
    final User? user =
        _auth.currentUser;

    if (user == null ||
        user.uid.trim().isEmpty) {
      throw StateError(
        'Authenticated Firebase user was not found.',
      );
    }

    return user;
  }

  // =============================================================
  // JR CALL PUBLIC ID
  // =============================================================

  String _generateJrId() {
    final String random =
    _uuid
        .v4()
        .replaceAll(
      '-',
      '',
    )
        .substring(
      0,
      12,
    )
        .toLowerCase();

    return 'jrcall_$random';
  }

  // =============================================================
  // PROFILE PHOTO SOURCE
  // =============================================================

  Future<void> _chooseProfilePhoto() async {
    if (_busy) {
      return;
    }

    final ImageSource? source =
    await showModalBottomSheet<ImageSource>(
      context:
      context,
      showDragHandle:
      true,
      builder: (
          BuildContext sheetContext,
          ) {
        return SafeArea(
          child:
          Column(
            mainAxisSize:
            MainAxisSize.min,
            children:
            <Widget>[
              if (_supportsCamera)
                ListTile(
                  leading:
                  const Icon(
                    Icons.camera_alt_outlined,
                  ),
                  title:
                  const Text(
                    'Take Photo',
                  ),
                  onTap:
                      () {
                    Navigator.of(
                      sheetContext,
                    ).pop(
                      ImageSource.camera,
                    );
                  },
                ),
              ListTile(
                leading:
                const Icon(
                  Icons.photo_library_outlined,
                ),
                title:
                const Text(
                  'Choose from Gallery',
                ),
                onTap:
                    () {
                  Navigator.of(
                    sheetContext,
                  ).pop(
                    ImageSource.gallery,
                  );
                },
              ),
              ListTile(
                leading:
                const Icon(
                  Icons.close_rounded,
                ),
                title:
                const Text(
                  'Cancel',
                ),
                onTap:
                    () {
                  Navigator.of(
                    sheetContext,
                  ).pop();
                },
              ),
            ],
          ),
        );
      },
    );

    if (source == null) {
      return;
    }

    await _pickProfile(
      source,
    );
  }

  // =============================================================
  // PROFILE PHOTO PICK
  // =============================================================

  Future<void> _pickProfile(
      ImageSource source,
      ) async {
    if (_busy) {
      return;
    }

    _setPicking(
      true,
    );

    try {
      if (source ==
          ImageSource.camera &&
          _isMobile) {
        final bool allowed =
        await AppPermissions
            .requestCamera();

        if (!allowed) {
          _message(
            'Camera permission is required.',
          );

          return;
        }
      }

      final XFile? file =
      await _picker.pickImage(
        source:
        source,
        imageQuality:
        95,
        maxWidth:
        2400,
        maxHeight:
        2400,
        requestFullMetadata:
        false,
      );

      if (file == null) {
        return;
      }

      final Uint8List? bytes =
      await _cropOrRead(
        file:
        file,
        title:
        'Crop Profile Photo',
        ratio:
        const CropAspectRatio(
          ratioX:
          1,
          ratioY:
          1,
        ),
        maxWidth:
        1200,
        maxHeight:
        1200,
      );

      if (bytes == null) {
        return;
      }

      _validateBytes(
        bytes,
        _profileLimit,
        'Profile Photo',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _profileBytes =
            bytes;
      });
    } on ArgumentError catch (error) {
      _message(
        error.message?.toString() ??
            'Invalid Profile Photo.',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'JR CALL Profile Photo error: $error',
      );

      debugPrintStack(
        label:
        'JR CALL Profile Photo',
        stackTrace:
        stackTrace,
      );

      _message(
        'Profile Photo could not be selected.',
      );
    } finally {
      _setPicking(
        false,
      );
    }
  }

  // =============================================================
  // COVER PHOTO PICK
  // =============================================================

  Future<void> _chooseCoverPhoto() async {
    if (_busy) {
      return;
    }

    _setPicking(
      true,
    );

    try {
      final XFile? file =
      await _picker.pickImage(
        source:
        ImageSource.gallery,
        imageQuality:
        95,
        maxWidth:
        3200,
        maxHeight:
        2000,
        requestFullMetadata:
        false,
      );

      if (file == null) {
        return;
      }

      final Uint8List? bytes =
      await _cropOrRead(
        file:
        file,
        title:
        'Crop Cover Photo',
        ratio:
        const CropAspectRatio(
          ratioX:
          16,
          ratioY:
          9,
        ),
        maxWidth:
        1920,
        maxHeight:
        1080,
      );

      if (bytes == null) {
        return;
      }

      _validateBytes(
        bytes,
        _coverLimit,
        'Cover Photo',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _coverBytes =
            bytes;
      });
    } on ArgumentError catch (error) {
      _message(
        error.message?.toString() ??
            'Invalid Cover Photo.',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'JR CALL Cover Photo error: $error',
      );

      debugPrintStack(
        label:
        'JR CALL Cover Photo',
        stackTrace:
        stackTrace,
      );

      _message(
        'Cover Photo could not be selected.',
      );
    } finally {
      _setPicking(
        false,
      );
    }
  }

  // =============================================================
  // IMAGE CROP / READ
  // =============================================================

  Future<Uint8List?> _cropOrRead({
    required XFile file,
    required String title,
    required CropAspectRatio ratio,
    required int maxWidth,
    required int maxHeight,
  }) async {
    if (!_supportsCropper) {
      return file.readAsBytes();
    }

    final CroppedFile? cropped =
    await ImageCropper()
        .cropImage(
      sourcePath:
      file.path,
      aspectRatio:
      ratio,
      compressFormat:
      ImageCompressFormat.jpg,
      compressQuality:
      88,
      maxWidth:
      maxWidth,
      maxHeight:
      maxHeight,
      uiSettings:
      <PlatformUiSettings>[
        AndroidUiSettings(
          toolbarTitle:
          title,
          lockAspectRatio:
          true,
          hideBottomControls:
          false,
        ),
        IOSUiSettings(
          title:
          title,
          aspectRatioLockEnabled:
          true,
          resetAspectRatioEnabled:
          false,
        ),
        WebUiSettings(
          context:
          context,
          presentStyle:
          WebPresentStyle.dialog,
          size:
          const CropperSize(
            width:
            520,
            height:
            520,
          ),
        ),
      ],
    );

    if (cropped == null) {
      return null;
    }

    return cropped.readAsBytes();
  }

  // =============================================================
  // PLATFORM
  // =============================================================

  bool get _isMobile {
    return !kIsWeb &&
        (defaultTargetPlatform ==
            TargetPlatform.android ||
            defaultTargetPlatform ==
                TargetPlatform.iOS);
  }

  bool get _supportsCamera {
    return _isMobile;
  }

  bool get _supportsCropper {
    return kIsWeb ||
        _isMobile;
  }

  // =============================================================
  // BYTE VALIDATION
  // =============================================================

  void _validateBytes(
      Uint8List bytes,
      int limit,
      String label,
      ) {
    if (bytes.isEmpty) {
      throw ArgumentError(
        '$label is empty.',
      );
    }

    if (bytes.lengthInBytes >
        limit) {
      throw ArgumentError(
        '$label is too large.',
      );
    }
  }

  // =============================================================
  // OPTIONAL MEDIA UPLOAD
  // =============================================================

  Future<void> _uploadMediaSafely(
      String uid,
      ) async {
    try {
      await _uploadMedia(
        uid,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'JR CALL optional media upload skipped: $error',
      );

      debugPrintStack(
        label:
        'JR CALL signup media',
        stackTrace:
        stackTrace,
      );
    }
  }

  Future<void> _uploadMedia(
      String uid,
      ) async {
    String? photoUrl;

    String? coverUrl;

    final Uint8List? profileBytes =
        _profileBytes;

    if (profileBytes != null) {
      photoUrl =
      await _uploadImage(
        path:
        'users/$uid/profile/profile.jpg',
        bytes:
        profileBytes,
        limit:
        _profileLimit,
      );
    }

    final Uint8List? coverBytes =
        _coverBytes;

    if (coverBytes != null) {
      coverUrl =
      await _uploadImage(
        path:
        'users/$uid/cover/cover.jpg',
        bytes:
        coverBytes,
        limit:
        _coverLimit,
      );
    }

    if (photoUrl == null &&
        coverUrl == null) {
      return;
    }

    await _firestore.updateProfile(
      uid:
      uid,
      photoUrl:
      photoUrl,
      coverPhoto:
      coverUrl,
    );

    if (photoUrl != null) {
      try {
        await _auth.updatePhotoUrl(
          photoUrl,
        );
      } catch (error) {
        debugPrint(
          'JR CALL Auth photo sync skipped: $error',
        );
      }
    }
  }

  // =============================================================
  // STORAGE UPLOAD
  // =============================================================

  Future<String> _uploadImage({
    required String path,
    required Uint8List bytes,
    required int limit,
  }) async {
    _validateBytes(
      bytes,
      limit,
      'Image',
    );

    final TaskSnapshot snapshot =
    await _storage
        .ref()
        .child(
      path,
    )
        .putData(
      bytes,
      SettableMetadata(
        contentType:
        'image/jpeg',
        cacheControl:
        'public,max-age=86400',
      ),
    );

    if (snapshot.state !=
        TaskState.success) {
      throw StateError(
        'Image upload did not complete.',
      );
    }

    final String url =
    await snapshot.ref
        .getDownloadURL();

    if (url.trim().isEmpty) {
      throw StateError(
        'Firebase Storage returned no image URL.',
      );
    }

    return url;
  }

  // =============================================================
  // DATE OF BIRTH
  // =============================================================

  Future<void> _selectDob() async {
    if (_busy) {
      return;
    }

    final DateTime now =
    DateTime.now();

    final DateTime initialDate =
        _dob ??
            DateTime(
              now.year - 18,
              now.month,
              now.day,
            );

    final DateTime? selected =
    await showDatePicker(
      context:
      context,
      initialDate:
      initialDate,
      firstDate:
      DateTime(
        1900,
      ),
      lastDate:
      now,
    );

    if (selected == null ||
        !mounted) {
      return;
    }

    setState(() {
      _dob =
          DateTime(
            selected.year,
            selected.month,
            selected.day,
          );
    });
  }

  // =============================================================
  // STEP NAVIGATION
  // =============================================================

  void _goStepOne() {
    if (_busy) {
      return;
    }

    setState(() {
      _step = 1;
    });
  }

  // =============================================================
  // OPEN LOGIN
  // =============================================================

  void _openLogin() {
    if (_busy) {
      return;
    }

    _otpManager.reset();

    TextInput.finishAutofillContext(
      shouldSave:
      false,
    );

    Navigator.of(context)
        .pushReplacement(
      MaterialPageRoute<void>(
        settings:
        RouteSettings(
          arguments:
          <String, dynamic>{
            'guestReturn':
            _guestReturn,
            if (_requestedAction !=
                null)
              'requestedAction':
              _requestedAction,
          },
        ),
        builder: (
            BuildContext context,
            ) {
          return const LoginScreen();
        },
      ),
    );
  }

  // =============================================================
  // CURRENT PHONE
  // =============================================================

  String _currentPhone() {
    if (_phone.text
        .trim()
        .isEmpty) {
      return '';
    }

    return _normalizePhone(
      _completePhone,
    );
  }

  // =============================================================
  // NORMALIZE PHONE
  // =============================================================

  String _normalizePhone(
      String value,
      ) {
    return value
        .trim()
        .replaceAll(
      RegExp(
        r'[\s()\-.]',
      ),
      '',
    );
  }

  // =============================================================
  // NORMALIZE USERNAME
  // =============================================================

  String? _normalizeUsername(
      String value,
      ) {
    String normalized =
    value
        .trim()
        .toLowerCase();

    if (normalized.startsWith(
      '@',
    )) {
      normalized =
          normalized.substring(
            1,
          );
    }

    if (normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  // =============================================================
  // CLEAN STRING
  // =============================================================

  String? _cleanNullable(
      String? value,
      ) {
    if (value == null) {
      return null;
    }

    final String normalized =
    value.trim();

    if (normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  // =============================================================
  // VALID PHONE
  // =============================================================

  bool _isValidPhone(
      String value,
      ) {
    return RegExp(
      r'^\+[1-9][0-9]{7,14}$',
    ).hasMatch(
      value,
    );
  }

  // =============================================================
  // VALID EMAIL
  // =============================================================

  bool _isValidEmail(
      String value,
      ) {
    return value.length <= 254 &&
        RegExp(
          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
        ).hasMatch(
          value,
        );
  }

  // =============================================================
  // VALID USERNAME
  // =============================================================

  bool _isValidUsername(
      String value,
      ) {
    return RegExp(
      r'^[a-z0-9._]{3,30}$',
    ).hasMatch(
      value,
    ) &&
        !value.startsWith(
          '.',
        ) &&
        !value.endsWith(
          '.',
        ) &&
        !value.contains(
          '..',
        );
  }

  // =============================================================
  // FORMAT DATE
  // =============================================================

  String _formatDate(
      DateTime date,
      ) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  // =============================================================
  // FIREBASE AUTH ERROR
  // =============================================================

  String _authError(
      FirebaseAuthException error,
      ) {
    switch (error.code) {
      case 'invalid-phone-number':
        return 'Enter a valid Phone Number.';

      case 'credential-already-in-use':
      case 'phone-number-already-exists':
        return 'This Phone Number is already linked to another account.';

      case 'email-already-in-use':
        return 'This Email is already linked to another JR CALL account.';

      case 'provider-already-linked':
        return 'Email Login is already linked to this account.';

      case 'operation-not-allowed':
        return 'This authentication method is currently unavailable.';

      case 'network-request-failed':
        return 'Check your Internet connection and try again.';

      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';

      case 'quota-exceeded':
        return 'OTP service quota has been reached.';

      case 'app-not-authorized':
        return 'This application is not authorized for Firebase Authentication.';

      case 'invalid-app-credential':
        return 'Firebase could not verify this application.';

      case 'captcha-check-failed':
        return 'Firebase security verification failed.';

      case 'session-expired':
        return 'Verification session expired. Request a new OTP.';

      case 'invalid-verification-code':
        return 'The SMS verification code is incorrect.';

      case 'invalid-verification-id':
        return 'The verification session is invalid. Request a new OTP.';

      case 'verification-in-progress':
        return 'Phone verification is already in progress.';

      case 'phone-verification-state-error':
      case 'phone-verification-invalid-argument':
      case 'phone-verification-failed':
        return error.message ??
            'Phone verification could not be completed.';

      case 'weak-password':
        return 'Password must contain at least 6 characters.';

      case 'invalid-email':
        return 'Enter a valid Email address.';

      case 'requires-recent-login':
        return 'Please authenticate again before continuing.';

      default:
        return error.message ??
            'Authentication failed.';
    }
  }

  // =============================================================
  // FIREBASE GENERIC ERROR
  // =============================================================

  String _firebaseError(
      FirebaseException error,
      ) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthorized':
      case 'storage/unauthorized':
        return 'Permission denied while updating your account.';

      case 'network-request-failed':
      case 'unavailable':
        return 'Firebase is temporarily unavailable.';

      case 'storage/canceled':
      case 'canceled':
        return 'Upload was cancelled.';

      case 'storage/quota-exceeded':
      case 'quota-exceeded':
        return 'Firebase Storage quota has been exceeded.';

      default:
        return error.message ??
            'Firebase operation failed.';
    }
  }

  // =============================================================
  // LOADING STATE
  // =============================================================

  void _setLoading(
      bool value,
      ) {
    if (!mounted ||
        _loading == value) {
      return;
    }

    setState(() {
      _loading =
          value;
    });
  }

  // =============================================================
  // PICKING STATE
  // =============================================================

  void _setPicking(
      bool value,
      ) {
    if (!mounted ||
        _pickingMedia ==
            value) {
      return;
    }

    setState(() {
      _pickingMedia =
          value;
    });
  }

  // =============================================================
  // MESSAGE
  // =============================================================

  void _message(
      String message,
      ) {
    final String normalized =
    message.trim();

    if (!mounted ||
        normalized.isEmpty) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    )
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior:
          SnackBarBehavior.floating,
          content:
          Text(
            normalized,
          ),
        ),
      );
  }

  // =============================================================
  // ROOT UI
  // =============================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    return PopScope(
      canPop:
      _step == 1 &&
          !_busy,
      onPopInvokedWithResult: (
          bool didPop,
          Object? result,
          ) {
        if (!didPop &&
            _step == 2 &&
            !_busy) {
          _goStepOne();
        }
      },
      child:
      Scaffold(
        backgroundColor:
        _background,
        body:
        SafeArea(
          child:
          Center(
            child:
            SingleChildScrollView(
              padding:
              const EdgeInsets.all(
                20,
              ),
              keyboardDismissBehavior:
              ScrollViewKeyboardDismissBehavior
                  .onDrag,
              child:
              ConstrainedBox(
                constraints:
                const BoxConstraints(
                  maxWidth:
                  520,
                ),
                child:
                Container(
                  padding:
                  const EdgeInsets.all(
                    22,
                  ),
                  decoration:
                  BoxDecoration(
                    color:
                    _surface,
                    borderRadius:
                    BorderRadius.circular(
                      28,
                    ),
                    border:
                    Border.all(
                      color:
                      _border,
                    ),
                  ),
                  child:
                  AutofillGroup(
                    child:
                    AnimatedSwitcher(
                      duration:
                      const Duration(
                        milliseconds:
                        200,
                      ),
                      child:
                      _step == 1
                          ? _buildStepOne()
                          : _buildStepTwo(),
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

  // =============================================================
  // HEADER
  // =============================================================

  Widget _header() {
    return Row(
      children:
      <Widget>[
        IconButton.filledTonal(
          onPressed:
          _busy
              ? null
              : () {
            if (_step ==
                2) {
              _goStepOne();
            } else {
              Navigator.of(
                context,
              ).maybePop();
            }
          },
          icon:
          const Icon(
            Icons.arrow_back_rounded,
          ),
        ),
        const SizedBox(
          width:
          12,
        ),
        ClipRRect(
          borderRadius:
          BorderRadius.circular(
            15,
          ),
          child:
          Image.asset(
            'assets/images/logo.png',
            width:
            58,
            height:
            58,
            fit:
            BoxFit.cover,
            errorBuilder: (
                BuildContext context,
                Object error,
                StackTrace? stackTrace,
                ) {
              return Container(
                width:
                58,
                height:
                58,
                alignment:
                Alignment.center,
                color:
                const Color(
                  0xFFEAF3FF,
                ),
                child:
                const Icon(
                  Icons.phone_in_talk,
                  color:
                  _blue,
                ),
              );
            },
          ),
        ),
        const SizedBox(
          width:
          12,
        ),
        const Expanded(
          child:
          Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children:
            <Widget>[
              Text.rich(
                TextSpan(
                  children:
                  <InlineSpan>[
                    TextSpan(
                      text:
                      'JR ',
                      style:
                      TextStyle(
                        color:
                        _text,
                      ),
                    ),
                    TextSpan(
                      text:
                      'CALL',
                      style:
                      TextStyle(
                        color:
                        _blue,
                      ),
                    ),
                  ],
                ),
                style:
                TextStyle(
                  fontSize:
                  25,
                  fontWeight:
                  FontWeight.w800,
                ),
              ),
              Text(
                'Premium Calling Experience',
                style:
                TextStyle(
                  color:
                  _secondary,
                  fontSize:
                  12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =============================================================
  // PROGRESS
  // =============================================================

  Widget _progress() {
    return Row(
      children:
      <Widget>[
        _stepCircle(
          1,
        ),
        Expanded(
          child:
          Container(
            height:
            2,
            margin:
            const EdgeInsets.symmetric(
              horizontal:
              14,
            ),
            color:
            _step == 2
                ? _blue
                : _border,
          ),
        ),
        _stepCircle(
          2,
        ),
      ],
    );
  }

  Widget _stepCircle(
      int number,
      ) {
    final bool active =
        number <= _step;

    return CircleAvatar(
      radius:
      17,
      backgroundColor:
      active
          ? _blue
          : _border,
      child:
      number < _step
          ? const Icon(
        Icons.check_rounded,
        color:
        Colors.white,
        size:
        18,
      )
          : Text(
        '$number',
        style:
        TextStyle(
          color:
          active
              ? Colors.white
              : _secondary,
          fontWeight:
          FontWeight.w700,
        ),
      ),
    );
  }

  // =============================================================
  // STEP ONE
  // =============================================================

  Widget _buildStepOne() {
    return Column(
      key:
      const ValueKey<String>(
        'step1',
      ),
      crossAxisAlignment:
      CrossAxisAlignment.stretch,
      children:
      <Widget>[
        _header(),
        const SizedBox(
          height:
          28,
        ),
        _progress(),
        const SizedBox(
          height:
          30,
        ),
        const Text(
          'Create Your Account',
          textAlign:
          TextAlign.center,
          style:
          TextStyle(
            color:
            _text,
            fontSize:
            26,
            fontWeight:
            FontWeight.w800,
          ),
        ),
        const SizedBox(
          height:
          7,
        ),
        const Text(
          'Phone Number is required. Everything else is optional.',
          textAlign:
          TextAlign.center,
          style:
          TextStyle(
            color:
            _secondary,
          ),
        ),
        const SizedBox(
          height:
          26,
        ),

        // -------------------------------------------------------
        // REQUIRED PHONE
        // -------------------------------------------------------

        IntlPhoneField(
          controller:
          _phone,
          initialCountryCode:
          _phoneCountryCode,
          enabled:
          !_busy,
          disableLengthCheck:
          true,
          keyboardType:
          TextInputType.phone,
          textInputAction:
          TextInputAction.next,
          decoration:
          _decoration(
            label:
            'Phone Number *',
            icon:
            Icons.phone_outlined,
          ),
          onChanged: (
              phone,
              ) {
            _completePhone =
            _phone.text
                .trim()
                .isEmpty
                ? ''
                : _normalizePhone(
              phone.completeNumber,
            );
          },
          onCountryChanged: (
              country,
              ) {
            _phoneCountryCode =
                country.code;

            _countryCode =
                country.code
                    .toUpperCase();

            try {
              _countryName =
                  Country.tryParse(
                    country.code,
                  )?.name;
            } catch (error) {
              debugPrint(
                'JR CALL country resolution skipped: $error',
              );

              _countryName =
              null;
            }
          },
        ),

        const SizedBox(
          height:
          14,
        ),

        // -------------------------------------------------------
        // OPTIONAL EMAIL
        // -------------------------------------------------------

        TextField(
          controller:
          _email,
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
          autocorrect:
          false,
          enableSuggestions:
          false,
          onChanged: (
              String value,
              ) {
            if (!mounted) {
              return;
            }

            setState(() {});
          },
          decoration:
          _decoration(
            label:
            'Email Address (Optional)',
            icon:
            Icons.email_outlined,
          ),
        ),

        // -------------------------------------------------------
        // PASSWORD REQUIRED ONLY WITH EMAIL
        // -------------------------------------------------------

        if (_hasEmail)
          ...<Widget>[
            const SizedBox(
              height:
              14,
            ),
            TextField(
              controller:
              _password,
              enabled:
              !_busy,
              obscureText:
              !_passwordVisible,
              keyboardType:
              TextInputType.visiblePassword,
              textInputAction:
              TextInputAction.next,
              autofillHints:
              const <String>[
                AutofillHints.newPassword,
              ],
              autocorrect:
              false,
              enableSuggestions:
              false,
              decoration:
              _decoration(
                label:
                'Password *',
                icon:
                Icons.lock_outline,
                suffix:
                IconButton(
                  onPressed:
                  _busy
                      ? null
                      : () {
                    setState(() {
                      _passwordVisible =
                      !_passwordVisible;
                    });
                  },
                  icon:
                  Icon(
                    _passwordVisible
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                ),
              ),
            ),
            const SizedBox(
              height:
              14,
            ),
            TextField(
              controller:
              _confirmPassword,
              enabled:
              !_busy,
              obscureText:
              !_confirmVisible,
              keyboardType:
              TextInputType.visiblePassword,
              textInputAction:
              TextInputAction.next,
              autofillHints:
              const <String>[
                AutofillHints.newPassword,
              ],
              autocorrect:
              false,
              enableSuggestions:
              false,
              decoration:
              _decoration(
                label:
                'Confirm Password *',
                icon:
                Icons.lock_reset,
                suffix:
                IconButton(
                  onPressed:
                  _busy
                      ? null
                      : () {
                    setState(() {
                      _confirmVisible =
                      !_confirmVisible;
                    });
                  },
                  icon:
                  Icon(
                    _confirmVisible
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                ),
              ),
            ),
          ],

        const SizedBox(
          height:
          14,
        ),

        // -------------------------------------------------------
        // OPTIONAL NAME
        // -------------------------------------------------------

        TextField(
          controller:
          _name,
          enabled:
          !_busy,
          keyboardType:
          TextInputType.name,
          textCapitalization:
          TextCapitalization.words,
          textInputAction:
          TextInputAction.next,
          maxLength:
          80,
          decoration:
          _decoration(
            label:
            'Full Name (Optional)',
            icon:
            Icons.person_outline,
          ).copyWith(
            counterText:
            '',
          ),
        ),

        const SizedBox(
          height:
          14,
        ),

        // -------------------------------------------------------
        // OPTIONAL USERNAME
        // -------------------------------------------------------

        TextField(
          controller:
          _username,
          enabled:
          !_busy,
          autocorrect:
          false,
          enableSuggestions:
          false,
          textInputAction:
          TextInputAction.next,
          maxLength:
          30,
          decoration:
          _decoration(
            label:
            'Short Name (Optional)',
            icon:
            Icons.person_add_alt_1_outlined,
          ).copyWith(
            counterText:
            '',
          ),
        ),

        const SizedBox(
          height:
          14,
        ),

        // -------------------------------------------------------
        // OPTIONAL DOB
        // -------------------------------------------------------

        InkWell(
          onTap:
          _busy
              ? null
              : _selectDob,
          borderRadius:
          BorderRadius.circular(
            18,
          ),
          child:
          InputDecorator(
            decoration:
            _decoration(
              label:
              'Date of Birth (Optional)',
              icon:
              Icons.calendar_month_outlined,
              suffix:
              _dob == null
                  ? null
                  : IconButton(
                onPressed:
                _busy
                    ? null
                    : () {
                  setState(() {
                    _dob =
                    null;
                  });
                },
                icon:
                const Icon(
                  Icons.close,
                ),
              ),
            ),
            child:
            Text(
              _dob == null
                  ? 'Select Date of Birth'
                  : _formatDate(
                _dob!,
              ),
              style:
              TextStyle(
                color:
                _dob == null
                    ? _secondary
                    : _text,
              ),
            ),
          ),
        ),

        const SizedBox(
          height:
          26,
        ),

        _PrimaryButton(
          label:
          'Continue',
          loading:
          false,
          enabled:
          !_busy,
          onPressed:
          _continue,
        ),

        const SizedBox(
          height:
          10,
        ),

        Row(
          mainAxisAlignment:
          MainAxisAlignment.center,
          children:
          <Widget>[
            const Flexible(
              child:
              Text(
                'Already have an account?',
                style:
                TextStyle(
                  color:
                  _secondary,
                ),
              ),
            ),
            TextButton(
              onPressed:
              _busy
                  ? null
                  : _openLogin,
              child:
              const Text(
                'Login',
              ),
            ),
          ],
        ),
      ],
    );
  }

  // =============================================================
  // STEP TWO
  // =============================================================

  Widget _buildStepTwo() {
    return Column(
      key:
      const ValueKey<String>(
        'step2',
      ),
      crossAxisAlignment:
      CrossAxisAlignment.stretch,
      children:
      <Widget>[
        _header(),
        const SizedBox(
          height:
          28,
        ),
        _progress(),
        const SizedBox(
          height:
          30,
        ),
        const Text(
          'Your Profile',
          textAlign:
          TextAlign.center,
          style:
          TextStyle(
            color:
            _text,
            fontSize:
            26,
            fontWeight:
            FontWeight.w800,
          ),
        ),
        const SizedBox(
          height:
          7,
        ),
        const Text(
          'Profile & Cover Photos are optional',
          textAlign:
          TextAlign.center,
          style:
          TextStyle(
            color:
            _secondary,
          ),
        ),
        const SizedBox(
          height:
          28,
        ),
        Center(
          child:
          _profileSelector(),
        ),
        const SizedBox(
          height:
          28,
        ),
        _coverSelector(),
        const SizedBox(
          height:
          28,
        ),
        _PrimaryButton(
          label:
          'Create Account',
          loading:
          _loading ||
              _automaticSignupRunning ||
              _manualSignupFinalizing,
          enabled:
          !_busy,
          onPressed:
          _createAccount,
        ),
        const SizedBox(
          height:
          8,
        ),
        TextButton(
          onPressed:
          _busy
              ? null
              : _createAccount,
          child:
          const Text(
            'Skip Photos & Create Account',
            style:
            TextStyle(
              color:
              _blue,
              fontWeight:
              FontWeight.w700,
            ),
          ),
        ),
        if (_pickingMedia)
          const Center(
            child:
            Padding(
              padding:
              EdgeInsets.only(
                top:
                8,
              ),
              child:
              SizedBox(
                width:
                20,
                height:
                20,
                child:
                CircularProgressIndicator(
                  strokeWidth:
                  2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // =============================================================
  // PROFILE SELECTOR
  // =============================================================

  Widget _profileSelector() {
    return Stack(
      clipBehavior:
      Clip.none,
      children:
      <Widget>[
        InkWell(
          onTap:
          _busy
              ? null
              : _chooseProfilePhoto,
          customBorder:
          const CircleBorder(),
          child:
          CircleAvatar(
            radius:
            70,
            backgroundColor:
            const Color(
              0xFFF1F5FB,
            ),
            backgroundImage:
            _profileBytes == null
                ? null
                : MemoryImage(
              _profileBytes!,
            ),
            child:
            _profileBytes == null
                ? const Icon(
              Icons.person_rounded,
              size:
              70,
              color:
              Color(
                0xFF9AA7B8,
              ),
            )
                : null,
          ),
        ),
        Positioned(
          right:
          -5,
          bottom:
          5,
          child:
          IconButton.filled(
            onPressed:
            _busy
                ? null
                : _chooseProfilePhoto,
            icon:
            const Icon(
              Icons.camera_alt,
            ),
          ),
        ),
        if (_profileBytes != null)
          Positioned(
            left:
            -5,
            bottom:
            5,
            child:
            IconButton.filledTonal(
              onPressed:
              _busy
                  ? null
                  : () {
                setState(() {
                  _profileBytes =
                  null;
                });
              },
              icon:
              const Icon(
                Icons.close,
              ),
            ),
          ),
      ],
    );
  }

  // =============================================================
  // COVER SELECTOR
  // =============================================================

  Widget _coverSelector() {
    return AspectRatio(
      aspectRatio:
      16 / 7,
      child:
      Stack(
        fit:
        StackFit.expand,
        children:
        <Widget>[
          InkWell(
            onTap:
            _busy
                ? null
                : _chooseCoverPhoto,
            borderRadius:
            BorderRadius.circular(
              18,
            ),
            child:
            Container(
              clipBehavior:
              Clip.antiAlias,
              decoration:
              BoxDecoration(
                color:
                const Color(
                  0xFFF2F6FC,
                ),
                borderRadius:
                BorderRadius.circular(
                  18,
                ),
                border:
                Border.all(
                  color:
                  _border,
                ),
              ),
              child:
              _coverBytes == null
                  ? const Column(
                mainAxisAlignment:
                MainAxisAlignment.center,
                children:
                <Widget>[
                  Icon(
                    Icons.landscape_outlined,
                    color:
                    _blue,
                    size:
                    42,
                  ),
                  SizedBox(
                    height:
                    6,
                  ),
                  Text(
                    'Add Cover Photo',
                    style:
                    TextStyle(
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),
                ],
              )
                  : Image.memory(
                _coverBytes!,
                fit:
                BoxFit.cover,
              ),
            ),
          ),
          if (_coverBytes != null)
            Positioned(
              left:
              10,
              bottom:
              10,
              child:
              IconButton.filledTonal(
                onPressed:
                _busy
                    ? null
                    : () {
                  setState(() {
                    _coverBytes =
                    null;
                  });
                },
                icon:
                const Icon(
                  Icons.close,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // =============================================================
  // FIELD DECORATION
  // =============================================================

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    OutlineInputBorder makeBorder(
        Color color, [
          double width = 1,
        ]) {
      return OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(
          18,
        ),
        borderSide:
        BorderSide(
          color:
          color,
          width:
          width,
        ),
      );
    }

    return InputDecoration(
      labelText:
      label,
      prefixIcon:
      Icon(
        icon,
        color:
        _blue,
      ),
      suffixIcon:
      suffix,
      filled:
      true,
      fillColor:
      _field,
      border:
      makeBorder(
        _border,
      ),
      enabledBorder:
      makeBorder(
        _border,
      ),
      focusedBorder:
      makeBorder(
        _blue,
        1.5,
      ),
      disabledBorder:
      makeBorder(
        _border,
      ),
    );
  }
}

// ===============================================================
// PRIMARY BUTTON
// ===============================================================

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.enabled,
    required this.onPressed,
  });

  final String label;

  final bool loading;

  final bool enabled;

  final VoidCallback onPressed;

  @override
  Widget build(
      BuildContext context,
      ) {
    return Opacity(
      opacity:
      enabled
          ? 1
          : 0.55,
      child:
      Container(
        height:
        58,
        decoration:
        BoxDecoration(
          borderRadius:
          BorderRadius.circular(
            18,
          ),
          gradient:
          const LinearGradient(
            colors:
            <Color>[
              _CreateAccountScreenState
                  ._blueLight,
              _CreateAccountScreenState
                  ._blue,
            ],
          ),
        ),
        child:
        Material(
          color:
          Colors.transparent,
          child:
          InkWell(
            onTap:
            enabled &&
                !loading
                ? onPressed
                : null,
            borderRadius:
            BorderRadius.circular(
              18,
            ),
            child:
            Center(
              child:
              loading
                  ? const SizedBox(
                width:
                24,
                height:
                24,
                child:
                CircularProgressIndicator(
                  strokeWidth:
                  2.4,
                  color:
                  Colors.white,
                ),
              )
                  : Text(
                label,
                style:
                const TextStyle(
                  color:
                  Colors.white,
                  fontSize:
                  17,
                  fontWeight:
                  FontWeight.w800,
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
// OTP / AUTH MASTER FILE 05 / 09
//
// FINAL CONTRACT:
//
// ✓ Phone Number mandatory.
// ✓ Phone OTP mandatory.
// ✓ Firebase Phone Auth authoritative.
// ✓ Automatic Phone verification supported.
// ✓ Manual Phone OTP supported.
// ✓ Existing Phone account rejected from Signup.
// ✓ Existing Phone account must use Login.
// ✓ No Phone password authentication.
// ✓ Password cannot bypass Phone OTP.
// ✓ No phoneAccountExists() pre-verification blocker.
// ✓ No fake/local OTP.
// ✓ No OTP persistence.
//
// ✓ Email optional.
// ✓ Password mandatory when Email is entered.
// ✓ Confirm Password mandatory when Email is entered.
// ✓ Email Signup OTP removed from this signup flow.
// ✓ Email/Password linked only after Phone authentication.
// ✓ Email/Password linked to SAME Firebase UID.
// ✓ Standalone Email signup impossible.
// ✓ Later direct Email + Password Login supported.
//
// ✓ Full Name optional.
// ✓ Short Name optional.
// ✓ DOB optional.
// ✓ Profile Photo optional.
// ✓ Cover Photo optional.
// ✓ JR CALL ID generated automatically.
// ✓ Profile media upload preserved.
// ✓ Guest-return routing preserved.
// ✓ requestedAction routing preserved.
//
// ✓ Call Engine untouched.
// ✓ Message Engine untouched.
// ✓ WebRTC untouched.
// ✓ Signaling untouched.
//
// SAVE / REPLACE:
//
// lib/screens/create_account_screen.dart
//
// NEXT OTP FILE:
//
// lib/screens/otp_screen.dart
// ===============================================================