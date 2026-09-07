// ===============================================================
// JR CALL
// File: auth_service.dart
// Location: lib/services/auth_service.dart
//
// OTP / AUTH MASTER FILE 01 / 09
//
// FINAL PRODUCTION AUTHENTICATION COORDINATOR
//
// ===============================================================
//
// JR CALL AUTH CONTRACT
//
// ACCOUNT CREATION:
//
// ✓ Phone Number is mandatory.
// ✓ Phone ownership must be verified with Firebase Phone Auth.
// ✓ Phone verification creates/signs-in the canonical Firebase user.
// ✓ Firebase UID remains the permanent private account identity.
// ✓ Email is optional during account creation.
// ✓ If Email is added, Password is mandatory.
// ✓ Email/Password is LINKED to the already Phone-authenticated user.
// ✓ Email/Password must NEVER create a second Firebase UID.
//
// PHONE LOGIN:
//
// ✓ Phone login always requires Firebase Phone verification.
// ✓ Phone login may be OTP-only.
// ✓ Supplying a Password beside a Phone Number does NOT bypass OTP.
// ✓ No Phone Password authentication exists.
// ✓ No account-exists pre-login blocker.
// ✓ No fake/local OTP.
// ✓ No OTP persistence.
// ✓ No security-verification bypass.
//
// EMAIL LOGIN:
//
// ✓ Email + Password signs in directly.
// ✓ No JR CALL Email Login OTP is required.
// ✓ No Email verification gate is required for normal login.
// ✓ Existing linked Firebase UID is restored.
//
// PHONE PLATFORM CONTRACT:
//
// Android / iOS:
// FirebaseAuth.verifyPhoneNumber()
//
// Web:
// FirebaseAuth.signInWithPhoneNumber()
// ConfirmationResult.confirm()
//
// Desktop browser:
// Uses Firebase Web Phone Authentication.
//
// Native unsupported desktop platforms must not silently bypass
// Firebase security verification.
//
// EMAIL OTP:
//
// ✓ Normal Email Login does NOT use Email OTP.
// ✓ Legacy Email OTP APIs remain for compatibility.
// ✓ Email Signup/Change backend APIs remain available.
// ✓ Password recovery OTP remains available.
//
// PASSWORD RECOVERY:
//
// ✓ Existing backend recovery OTP contract preserved.
// ✓ Password recovery OTP remains server-owned.
// ✓ Raw OTP is never persisted here.
// ✓ Raw Password is never persisted here.
//
// PROVIDER LINKING:
//
// Phone authenticated Firebase UID
//      ↓
// EmailAuthProvider credential
//      ↓
// linkWithCredential()
//      ↓
// SAME Firebase UID
//
// SECURITY:
//
// ✓ Firebase security verification remains authoritative.
// ✓ No Play Integrity bypass.
// ✓ No reCAPTCHA bypass.
// ✓ No App Verification bypass.
// ✓ Stale Phone sessions rejected.
// ✓ Different Phone sessions cannot inherit resend/verification state.
// ✓ Credential mutation is guarded.
// ✓ Sign-out clears Phone verification state.
//
// PROTECTED:
//
// ✓ Call Engine untouched.
// ✓ Message Engine untouched.
// ✓ WebRTC untouched.
// ✓ Signaling untouched.
// ===============================================================

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

// ===============================================================
// AUTH SERVICE
// ===============================================================

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  // =============================================================
  // FIREBASE AUTH
  // =============================================================

  FirebaseAuth get _auth => FirebaseAuth.instance;

  FirebaseAuth get auth => _auth;

  // =============================================================
  // CLOUD FUNCTIONS
  // =============================================================

  static const String functionsRegion = 'us-central1';

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: functionsRegion);

  FirebaseFunctions get functions => _functions;

  // =============================================================
  // BACKEND FUNCTION NAMES
  // =============================================================

  static const String checkPhoneAccountExistsFunction =
      'checkPhoneAccountExists';

  static const String sendEmailOtpFunction = 'sendEmailOtp';

  static const String verifyEmailOtpFunction = 'verifyEmailOtp';

  static const String sendPasswordRecoveryOtpFunction =
      'sendPasswordRecoveryOtp';

  static const String verifyPasswordRecoveryOtpFunction =
      'verifyPasswordRecoveryOtp';

  // =============================================================
  // EMAIL OTP PURPOSES
  //
  // emailLogin remains for backend/API compatibility only.
  // Normal login uses Email + Password directly.
  // =============================================================

  static const String emailSignUpPurpose = 'emailSignUp';

  static const String emailLoginPurpose = 'emailLogin';

  static const String emailChangePurpose = 'emailChange';

  static const Set<String> _supportedEmailOtpPurposes = <String>{
    emailSignUpPurpose,
    emailLoginPurpose,
    emailChangePurpose,
  };

  // =============================================================
  // PHONE VERIFICATION STATE
  // =============================================================

  bool _phoneVerificationInProgress = false;

  int _phoneVerificationGeneration = 0;

  String? _lastVerificationId;

  int? _lastResendToken;

  String? _pendingPhoneNumber;

  ConfirmationResult? _webConfirmationResult;

  String? _webConfirmationPhone;

  bool _credentialOperationInProgress = false;

  // =============================================================
  // PHONE STATE GETTERS
  // =============================================================

  bool get isPhoneVerificationInProgress => _phoneVerificationInProgress;

  bool get isCredentialOperationInProgress => _credentialOperationInProgress;

  String? get lastVerificationId => _lastVerificationId;

  int? get lastResendToken => _lastResendToken;

  String? get pendingPhoneNumber => _pendingPhoneNumber;

  bool get hasPendingPhoneVerification {
    final String? verificationId = _cleanNullableString(
      _lastVerificationId,
    );

    final String? phone = _cleanNullableString(
      _pendingPhoneNumber,
    );

    if (verificationId == null || phone == null) {
      return false;
    }

    if (kIsWeb) {
      return _webConfirmationResult != null &&
          _webConfirmationPhone == phone;
    }

    return true;
  }

  // =============================================================
  // CURRENT USER
  // =============================================================

  User? get currentUser => _auth.currentUser;

  bool get isSignedIn => currentUser != null;

  String? get currentUserId {
    return _cleanNullableString(
      currentUser?.uid,
    );
  }

  String? get currentEmail {
    return _cleanNullableString(
      currentUser?.email,
    );
  }

  String? get currentPhoneNumber {
    return _cleanNullableString(
      currentUser?.phoneNumber,
    );
  }

  bool get emailVerified {
    return currentUser?.emailVerified ?? false;
  }

  bool get phoneVerified {
    return currentPhoneNumber != null;
  }

  // =============================================================
  // AUTH STREAMS
  // =============================================================

  Stream<User?> get authStateChanges {
    return _auth.authStateChanges();
  }

  Stream<User?> get idTokenChanges {
    return _auth.idTokenChanges();
  }

  Stream<User?> get userChanges {
    return _auth.userChanges();
  }

  // =============================================================
  // PHONE ACCOUNT EXISTS
  //
  // COMPATIBILITY ONLY.
  //
  // IMPORTANT:
  //
  // Phone Login must NEVER require this before Firebase Phone Auth.
  // =============================================================

  Future<bool> phoneAccountExists({
    required String phoneNumber,
  }) async {
    final String normalizedPhone = _normalizePhoneNumber(
      phoneNumber,
    );

    final HttpsCallable callable = _functions.httpsCallable(
      checkPhoneAccountExistsFunction,
    );

    final HttpsCallableResult<dynamic> result =
    await callable.call<dynamic>(
      <String, dynamic>{
        'phoneNumber': normalizedPhone,
      },
    );

    final Map<String, dynamic> data = _asStringMap(
      result.data,
    );

    final Object? exists = data['exists'];

    if (exists is! bool) {
      throw StateError(
        'JR CALL Phone account service returned an invalid response.',
      );
    }

    return exists;
  }

  Future<bool> checkPhoneAccountExists({
    required String phoneNumber,
  }) {
    return phoneAccountExists(
      phoneNumber: phoneNumber,
    );
  }

  // =============================================================
  // START PHONE VERIFICATION
  //
  // NATIVE:
  // FirebaseAuth.verifyPhoneNumber()
  //
  // WEB:
  // FirebaseAuth.signInWithPhoneNumber()
  // =============================================================

  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(String verificationId) codeSent,
    required void Function(FirebaseAuthException error) verificationFailed,
    void Function(PhoneAuthCredential credential)? verificationCompleted,
    void Function(String verificationId)? codeAutoRetrievalTimeout,
    void Function(
        String verificationId,
        int? resendToken,
        )? codeSentWithToken,
    Duration timeout = const Duration(seconds: 60),
    int? forceResendingToken,
  }) async {
    final String normalizedPhone = _normalizePhoneNumber(
      phoneNumber,
    );

    if (kIsWeb) {
      await _verifyPhoneNumberWeb(
        phoneNumber: normalizedPhone,
        codeSent: codeSent,
        verificationFailed: verificationFailed,
        codeSentWithToken: codeSentWithToken,
      );

      return;
    }

    await _verifyPhoneNumberNative(
      phoneNumber: normalizedPhone,
      codeSent: codeSent,
      verificationFailed: verificationFailed,
      verificationCompleted: verificationCompleted,
      codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
      codeSentWithToken: codeSentWithToken,
      timeout: timeout,
      forceResendingToken: forceResendingToken,
    );
  }

  // =============================================================
  // NATIVE PHONE VERIFICATION
  // =============================================================

  Future<void> _verifyPhoneNumberNative({
    required String phoneNumber,
    required void Function(String verificationId) codeSent,
    required void Function(FirebaseAuthException error) verificationFailed,
    required void Function(PhoneAuthCredential credential)?
    verificationCompleted,
    required void Function(String verificationId)? codeAutoRetrievalTimeout,
    required void Function(
        String verificationId,
        int? resendToken,
        )? codeSentWithToken,
    required Duration timeout,
    required int? forceResendingToken,
  }) async {
    final bool samePhone = _pendingPhoneNumber == phoneNumber;

    if (_phoneVerificationInProgress && forceResendingToken == null) {
      verificationFailed(
        FirebaseAuthException(
          code: 'verification-in-progress',
          message: 'Phone verification is already in progress.',
        ),
      );

      return;
    }

    if (!samePhone) {
      _invalidatePendingPhoneSession(
        preserveGeneration: true,
      );
    }

    final int generation = ++_phoneVerificationGeneration;

    _phoneVerificationInProgress = true;
    _pendingPhoneNumber = phoneNumber;

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: timeout,
        forceResendingToken: forceResendingToken,

        // -------------------------------------------------------
        // AUTOMATIC ANDROID VERIFICATION
        // -------------------------------------------------------

        verificationCompleted: (
            PhoneAuthCredential credential,
            ) {
          if (!_isCurrentPhoneVerification(generation)) {
            return;
          }

          _phoneVerificationInProgress = false;

          verificationCompleted?.call(
            credential,
          );
        },

        // -------------------------------------------------------
        // FAILURE
        // -------------------------------------------------------

        verificationFailed: (
            FirebaseAuthException error,
            ) {
          if (!_isCurrentPhoneVerification(generation)) {
            return;
          }

          _phoneVerificationInProgress = false;

          verificationFailed(
            error,
          );
        },

        // -------------------------------------------------------
        // SMS SENT
        // -------------------------------------------------------

        codeSent: (
            String verificationId,
            int? resendToken,
            ) {
          if (!_isCurrentPhoneVerification(generation)) {
            return;
          }

          final String cleanVerificationId = verificationId.trim();

          if (cleanVerificationId.isEmpty) {
            _phoneVerificationInProgress = false;

            verificationFailed(
              FirebaseAuthException(
                code: 'invalid-verification-id',
                message:
                'Firebase did not provide a valid verification session.',
              ),
            );

            return;
          }

          _lastVerificationId = cleanVerificationId;
          _lastResendToken = resendToken;
          _pendingPhoneNumber = phoneNumber;
          _webConfirmationResult = null;
          _webConfirmationPhone = null;
          _phoneVerificationInProgress = false;

          codeSentWithToken?.call(
            cleanVerificationId,
            resendToken,
          );

          codeSent(
            cleanVerificationId,
          );
        },

        // -------------------------------------------------------
        // ANDROID AUTO RETRIEVAL TIMEOUT
        //
        // Manual OTP remains valid.
        // -------------------------------------------------------

        codeAutoRetrievalTimeout: (
            String verificationId,
            ) {
          if (!_isCurrentPhoneVerification(generation)) {
            return;
          }

          final String cleanVerificationId = verificationId.trim();

          if (cleanVerificationId.isNotEmpty) {
            _lastVerificationId = cleanVerificationId;
          }

          _phoneVerificationInProgress = false;

          codeAutoRetrievalTimeout?.call(
            cleanVerificationId,
          );
        },
      );
    } on FirebaseAuthException catch (error) {
      if (!_isCurrentPhoneVerification(generation)) {
        return;
      }

      _phoneVerificationInProgress = false;

      verificationFailed(
        error,
      );
    } catch (_) {
      if (_isCurrentPhoneVerification(generation)) {
        _phoneVerificationInProgress = false;
      }

      rethrow;
    }
  }

  // =============================================================
  // WEB PHONE VERIFICATION
  //
  // Firebase Web handles reCAPTCHA/security verification.
  // =============================================================

  Future<void> _verifyPhoneNumberWeb({
    required String phoneNumber,
    required void Function(String verificationId) codeSent,
    required void Function(FirebaseAuthException error) verificationFailed,
    required void Function(
        String verificationId,
        int? resendToken,
        )? codeSentWithToken,
  }) async {
    if (_phoneVerificationInProgress) {
      verificationFailed(
        FirebaseAuthException(
          code: 'verification-in-progress',
          message: 'Phone verification is already in progress.',
        ),
      );

      return;
    }

    final bool samePhone = _pendingPhoneNumber == phoneNumber;

    if (!samePhone) {
      _invalidatePendingPhoneSession(
        preserveGeneration: true,
      );
    }

    final int generation = ++_phoneVerificationGeneration;

    _phoneVerificationInProgress = true;
    _pendingPhoneNumber = phoneNumber;

    try {
      final ConfirmationResult confirmation =
      await _auth.signInWithPhoneNumber(
        phoneNumber,
      );

      if (!_isCurrentPhoneVerification(generation)) {
        return;
      }

      final String verificationId = confirmation.verificationId.trim();

      if (verificationId.isEmpty) {
        _phoneVerificationInProgress = false;

        verificationFailed(
          FirebaseAuthException(
            code: 'invalid-verification-id',
            message:
            'Firebase did not provide a valid Web verification session.',
          ),
        );

        return;
      }

      _webConfirmationResult = confirmation;
      _webConfirmationPhone = phoneNumber;

      _lastVerificationId = verificationId;
      _lastResendToken = null;
      _pendingPhoneNumber = phoneNumber;
      _phoneVerificationInProgress = false;

      codeSentWithToken?.call(
        verificationId,
        null,
      );

      codeSent(
        verificationId,
      );
    } on FirebaseAuthException catch (error) {
      if (!_isCurrentPhoneVerification(generation)) {
        return;
      }

      _phoneVerificationInProgress = false;

      verificationFailed(
        error,
      );
    } catch (_) {
      if (_isCurrentPhoneVerification(generation)) {
        _phoneVerificationInProgress = false;
      }

      rethrow;
    }
  }

  // =============================================================
  // RESEND PHONE OTP
  // =============================================================

  Future<void> resendPhoneVerificationCode({
    required String phoneNumber,
    required void Function(String verificationId) codeSent,
    required void Function(FirebaseAuthException error) verificationFailed,
    void Function(PhoneAuthCredential credential)? verificationCompleted,
    void Function(String verificationId)? codeAutoRetrievalTimeout,
    void Function(
        String verificationId,
        int? resendToken,
        )? codeSentWithToken,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final String normalizedPhone = _normalizePhoneNumber(
      phoneNumber,
    );

    final bool samePhone = _pendingPhoneNumber == normalizedPhone;

    final int? resendToken = samePhone
        ? _lastResendToken
        : null;

    await verifyPhoneNumber(
      phoneNumber: normalizedPhone,
      codeSent: codeSent,
      verificationFailed: verificationFailed,
      verificationCompleted: verificationCompleted,
      codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
      codeSentWithToken: codeSentWithToken,
      timeout: timeout,
      forceResendingToken: resendToken,
    );
  }

  // =============================================================
  // PHONE CREDENTIAL CREATION
  //
  // Native credential path.
  // =============================================================

  PhoneAuthCredential createPhoneCredential({
    required String verificationId,
    required String smsCode,
  }) {
    final String cleanVerificationId = _normalizeVerificationId(
      verificationId,
    );

    final String cleanSmsCode = _normalizeOtp(
      smsCode,
    );

    return PhoneAuthProvider.credential(
      verificationId: cleanVerificationId,
      smsCode: cleanSmsCode,
    );
  }

  PhoneAuthCredential createPendingPhoneCredential({
    required String smsCode,
  }) {
    final String? verificationId = _cleanNullableString(
      _lastVerificationId,
    );

    if (verificationId == null) {
      throw StateError(
        'No active Phone verification session is available.',
      );
    }

    return createPhoneCredential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
  }

  // =============================================================
  // PHONE OTP SIGN-IN
  //
  // Native -> PhoneAuthCredential
  // Web    -> ConfirmationResult.confirm()
  // =============================================================

  Future<UserCredential> signInWithOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    final String cleanVerificationId = _normalizeVerificationId(
      verificationId,
    );

    final String cleanSmsCode = _normalizeOtp(
      smsCode,
    );

    if (kIsWeb) {
      return _confirmWebPhoneOtp(
        verificationId: cleanVerificationId,
        smsCode: cleanSmsCode,
      );
    }

    final PhoneAuthCredential credential = PhoneAuthProvider.credential(
      verificationId: cleanVerificationId,
      smsCode: cleanSmsCode,
    );

    return signInWithPhoneCredential(
      credential,
    );
  }

  Future<UserCredential> signInWithPendingOtp({
    required String smsCode,
  }) async {
    final String? verificationId = _cleanNullableString(
      _lastVerificationId,
    );

    if (verificationId == null) {
      throw StateError(
        'No active Phone verification session is available.',
      );
    }

    return signInWithOtp(
      verificationId: verificationId,
      smsCode: smsCode,
    );
  }

  // =============================================================
  // WEB OTP CONFIRM
  // =============================================================

  Future<UserCredential> _confirmWebPhoneOtp({
    required String verificationId,
    required String smsCode,
  }) {
    final ConfirmationResult? confirmation =
        _webConfirmationResult;

    final String? pendingId = _cleanNullableString(
      _lastVerificationId,
    );

    if (confirmation == null ||
        pendingId == null ||
        pendingId != verificationId) {
      throw StateError(
        'The Web Phone verification session is no longer valid.',
      );
    }

    return _runCredentialOperation<UserCredential>(
          () async {
        final UserCredential result = await confirmation.confirm(
          smsCode,
        );

        final User? authenticatedUser = result.user ?? _auth.currentUser;

        if (authenticatedUser == null ||
            authenticatedUser.uid.trim().isEmpty) {
          throw StateError(
            'Firebase Phone verification completed without a valid user.',
          );
        }

        _clearPhoneVerificationState();

        return result;
      },
    );
  }

  // =============================================================
  // NATIVE PHONE SIGN-IN
  // =============================================================

  Future<UserCredential> signInWithPhoneCredential(
      PhoneAuthCredential credential,
      ) {
    return _runCredentialOperation<UserCredential>(
          () async {
        final UserCredential result = await _auth.signInWithCredential(
          credential,
        );

        final User? authenticatedUser = result.user ?? _auth.currentUser;

        if (authenticatedUser == null ||
            authenticatedUser.uid.trim().isEmpty) {
          throw StateError(
            'Firebase Phone verification completed without a valid user.',
          );
        }

        _clearPhoneVerificationState();

        return result;
      },
    );
  }

  // =============================================================
  // EMAIL/PASSWORD ACCOUNT CREATION
  //
  // JR CALL RULE:
  //
  // Standalone Email account creation is NOT allowed.
  //
  // A Phone-authenticated Firebase account must already exist.
  // Email/Password is linked to that SAME UID.
  // =============================================================

  Future<UserCredential> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {
    _requirePhoneAuthenticatedUser();

    return linkEmailPasswordToCurrentUser(
      email: email,
      password: password,
    );
  }

  // =============================================================
  // DIRECT EMAIL/PASSWORD LOGIN
  //
  // NO EMAIL OTP.
  // NO Email verification gate.
  // =============================================================

  Future<UserCredential> signInWithEmailPassword({
    required String email,
    required String password,
  }) {
    final String normalizedEmail = _normalizeEmail(
      email,
    );

    _validatePassword(
      password,
      enforceMinimumLength: false,
    );

    return _runCredentialOperation<UserCredential>(
          () async {
        final UserCredential result =
        await _auth.signInWithEmailAndPassword(
          email: normalizedEmail,
          password: password,
        );

        final User? user = result.user ?? _auth.currentUser;

        if (user == null || user.uid.trim().isEmpty) {
          throw StateError(
            'Email/Password authentication completed without a valid user.',
          );
        }

        _clearPhoneVerificationState();

        return result;
      },
    );
  }

  // =============================================================
  // EMAIL/PASSWORD LINK
  //
  // SAME FIREBASE UID.
  //
  // Phone identity is mandatory before adding Email/Password.
  // =============================================================

  Future<UserCredential> linkEmailPasswordToCurrentUser({
    required String email,
    required String password,
  }) async {
    final String normalizedEmail = _normalizeEmail(
      email,
    );

    _validatePassword(
      password,
      enforceMinimumLength: true,
    );

    User user = _requirePhoneAuthenticatedUser();

    try {
      await user.reload();

      user = _requirePhoneAuthenticatedUser();
    } catch (_) {
      user = _requirePhoneAuthenticatedUser();
    }

    final bool passwordAlreadyLinked = _userHasProvider(
      user,
      'password',
    );

    if (passwordAlreadyLinked) {
      throw StateError(
        'An Email/Password provider is already linked to this account.',
      );
    }

    final String? existingEmail = _cleanNullableString(
      user.email,
    );

    if (existingEmail != null &&
        existingEmail.toLowerCase() != normalizedEmail) {
      throw StateError(
        'A different Email address is already linked to this account.',
      );
    }

    final AuthCredential credential = EmailAuthProvider.credential(
      email: normalizedEmail,
      password: password,
    );

    final String originalUid = user.uid;

    final UserCredential result = await linkCredentialToCurrentUser(
      credential,
    );

    final User? linkedUser = result.user ?? _auth.currentUser;

    if (linkedUser == null ||
        linkedUser.uid.trim().isEmpty ||
        linkedUser.uid != originalUid) {
      throw StateError(
        'Email/Password linking did not preserve the Firebase account.',
      );
    }

    return result;
  }

  // =============================================================
  // PHONE CREDENTIAL LINK
  // =============================================================

  Future<UserCredential> linkPhoneCredentialToCurrentUser(
      PhoneAuthCredential credential,
      ) async {
    final UserCredential result =
    await linkCredentialToCurrentUser(
      credential,
    );

    _clearPhoneVerificationState();

    return result;
  }

  Future<UserCredential> linkCredentialToCurrentUser(
      AuthCredential credential,
      ) {
    final User user = _requireCurrentUser();

    return _runCredentialOperation<UserCredential>(
          () => user.linkWithCredential(
        credential,
      ),
    );
  }

  // =============================================================
  // EMAIL OTP SEND
  //
  // COMPATIBILITY / SIGNUP-CHANGE BACKEND SUPPORT.
  //
  // Normal Email login does NOT call this.
  // =============================================================

  Future<EmailOtpChallenge> sendEmailOtp({
    required String email,
    required String purpose,
  }) async {
    final User user = _requireCurrentUser();

    final String normalizedEmail = _normalizeEmail(
      email,
    );

    final String normalizedPurpose = _normalizeEmailOtpPurpose(
      purpose,
    );

    if (normalizedPurpose == emailLoginPurpose) {
      final String? currentUserEmail = _cleanNullableString(
        user.email,
      );

      if (currentUserEmail == null) {
        throw StateError(
          'The authenticated Firebase user does not have an Email address.',
        );
      }

      if (_normalizeEmail(currentUserEmail) != normalizedEmail) {
        throw StateError(
          'Authenticated Email does not match the OTP Email.',
        );
      }
    }

    final HttpsCallable callable = _functions.httpsCallable(
      sendEmailOtpFunction,
    );

    final HttpsCallableResult<dynamic> result =
    await callable.call<dynamic>(
      <String, dynamic>{
        'email': normalizedEmail,
        'purpose': normalizedPurpose,
      },
    );

    final Map<String, dynamic> data = _asStringMap(
      result.data,
    );

    final String challengeId = _readRequiredString(
      data['challengeId'],
      fieldName: 'challengeId',
    );

    return EmailOtpChallenge(
      challengeId: challengeId,
      expiresInSeconds: _readPositiveInt(
        data['expiresIn'],
        fallback: 300,
      ),
      resendAfterSeconds: _readPositiveInt(
        data['resendAfter'],
        fallback: 60,
      ),
    );
  }

  Future<EmailOtpChallenge> sendEmailSignUpOtp({
    required String email,
  }) {
    return sendEmailOtp(
      email: email,
      purpose: emailSignUpPurpose,
    );
  }

  Future<EmailOtpChallenge> sendEmailLoginOtp({
    required String email,
  }) {
    return sendEmailOtp(
      email: email,
      purpose: emailLoginPurpose,
    );
  }

  Future<EmailOtpChallenge> sendEmailChangeOtp({
    required String email,
  }) {
    return sendEmailOtp(
      email: email,
      purpose: emailChangePurpose,
    );
  }

  // =============================================================
  // EMAIL OTP VERIFY
  //
  // COMPATIBILITY / SIGNUP-CHANGE BACKEND SUPPORT.
  // =============================================================

  Future<EmailOtpVerificationResult> verifyEmailOtp({
    required String challengeId,
    required String otp,
    required String purpose,
  }) async {
    _requireCurrentUser();

    final String normalizedChallengeId = _normalizeChallengeId(
      challengeId,
    );

    final String normalizedOtp = _normalizeOtp(
      otp,
    );

    final String normalizedPurpose = _normalizeEmailOtpPurpose(
      purpose,
    );

    final HttpsCallable callable = _functions.httpsCallable(
      verifyEmailOtpFunction,
    );

    final HttpsCallableResult<dynamic> result =
    await callable.call<dynamic>(
      <String, dynamic>{
        'challengeId': normalizedChallengeId,
        'otp': normalizedOtp,
        'purpose': normalizedPurpose,
      },
    );

    final Map<String, dynamic> data = _asStringMap(
      result.data,
    );

    final bool verified =
        data['success'] == true &&
            data['verified'] == true;

    if (!verified) {
      throw StateError(
        _readNullableString(
          data['message'],
        ) ??
            'Email OTP verification failed.',
      );
    }

    try {
      await reloadUser();
      await refreshIdToken();
    } catch (_) {
      // Backend verification result remains authoritative.
    }

    return EmailOtpVerificationResult(
      success: true,
      verified: true,
      challengeId: _readNullableString(
        data['challengeId'],
      ) ??
          normalizedChallengeId,
      purpose: _readNullableString(
        data['purpose'],
      ) ??
          normalizedPurpose,
      email: _readNullableString(
        data['email'],
      ),
    );
  }

  Future<EmailOtpVerificationResult> verifyEmailSignUpOtp({
    required String challengeId,
    required String otp,
  }) {
    return verifyEmailOtp(
      challengeId: challengeId,
      otp: otp,
      purpose: emailSignUpPurpose,
    );
  }

  Future<EmailOtpVerificationResult> verifyEmailLoginOtp({
    required String challengeId,
    required String otp,
  }) {
    return verifyEmailOtp(
      challengeId: challengeId,
      otp: otp,
      purpose: emailLoginPurpose,
    );
  }

  Future<EmailOtpVerificationResult> verifyEmailChangeOtp({
    required String challengeId,
    required String otp,
  }) {
    return verifyEmailOtp(
      challengeId: challengeId,
      otp: otp,
      purpose: emailChangePurpose,
    );
  }

  // =============================================================
  // PASSWORD RECOVERY OTP
  // =============================================================

  Future<PasswordRecoveryChallenge> sendPasswordRecoveryOtp({
    required String email,
  }) async {
    final String normalizedEmail = _normalizeEmail(
      email,
    );

    final HttpsCallable callable = _functions.httpsCallable(
      sendPasswordRecoveryOtpFunction,
    );

    final HttpsCallableResult<dynamic> result =
    await callable.call<dynamic>(
      <String, dynamic>{
        'email': normalizedEmail,
      },
    );

    final Map<String, dynamic> data = _asStringMap(
      result.data,
    );

    if (data['success'] != true) {
      throw StateError(
        'Password recovery could not be started.',
      );
    }

    return PasswordRecoveryChallenge(
      accepted: true,
      challengeId: _readNullableString(
        data['challengeId'],
      ),
      expiresInSeconds: _readPositiveInt(
        data['expiresIn'],
        fallback: 300,
      ),
      resendAfterSeconds: _readPositiveInt(
        data['resendAfter'],
        fallback: 60,
      ),
    );
  }

  Future<void> verifyPasswordRecoveryOtp({
    required String challengeId,
    required String otp,
    required String newPassword,
  }) async {
    final String normalizedChallengeId = _normalizeChallengeId(
      challengeId,
    );

    final String normalizedOtp = _normalizeOtp(
      otp,
    );

    _validatePassword(
      newPassword,
      enforceMinimumLength: true,
    );

    final HttpsCallable callable = _functions.httpsCallable(
      verifyPasswordRecoveryOtpFunction,
    );

    final HttpsCallableResult<dynamic> result =
    await callable.call<dynamic>(
      <String, dynamic>{
        'challengeId': normalizedChallengeId,
        'otp': normalizedOtp,
        'newPassword': newPassword,
      },
    );

    final Map<String, dynamic> data = _asStringMap(
      result.data,
    );

    if (data['success'] != true ||
        data['passwordReset'] != true) {
      throw StateError(
        'Password recovery did not complete.',
      );
    }

    if (currentUser != null) {
      await signOut();
    }
  }

  // =============================================================
  // FIREBASE EMAIL VERIFICATION
  //
  // Settings compatibility.
  // Not required by normal Email/Password login.
  // =============================================================

  Future<void> sendEmailVerification({
    ActionCodeSettings? actionCodeSettings,
  }) async {
    final User user = _requireCurrentUser();

    if (user.emailVerified) {
      return;
    }

    if (actionCodeSettings == null) {
      await user.sendEmailVerification();
      return;
    }

    await user.sendEmailVerification(
      actionCodeSettings,
    );
  }

  bool isEmailVerified() {
    return currentUser?.emailVerified ?? false;
  }

  Future<bool> refreshEmailVerificationStatus() async {
    final User? user = currentUser;

    if (user == null) {
      return false;
    }

    await user.reload();

    return currentUser?.emailVerified ?? false;
  }

  // =============================================================
  // EMAIL CHANGE
  // =============================================================

  Future<void> requestEmailChange({
    required String newEmail,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    final User user = _requireCurrentUser();

    final String normalizedEmail = _normalizeEmail(
      newEmail,
    );

    if (actionCodeSettings == null) {
      await user.verifyBeforeUpdateEmail(
        normalizedEmail,
      );

      return;
    }

    await user.verifyBeforeUpdateEmail(
      normalizedEmail,
      actionCodeSettings,
    );
  }

  Future<void> changeEmail({
    required String newEmail,
    ActionCodeSettings? actionCodeSettings,
  }) {
    return requestEmailChange(
      newEmail: newEmail,
      actionCodeSettings: actionCodeSettings,
    );
  }

  // =============================================================
  // FIREBASE PASSWORD RESET EMAIL
  //
  // Compatibility API.
  // JR CALL primary recovery remains recovery OTP backend.
  // =============================================================

  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    final String normalizedEmail = _normalizeEmail(
      email,
    );

    if (actionCodeSettings == null) {
      await _auth.sendPasswordResetEmail(
        email: normalizedEmail,
      );

      return;
    }

    await _auth.sendPasswordResetEmail(
      email: normalizedEmail,
      actionCodeSettings: actionCodeSettings,
    );
  }

  // =============================================================
  // PASSWORD UPDATE
  // =============================================================

  Future<void> updatePassword({
    required String newPassword,
  }) async {
    final User user = _requireCurrentUser();

    _validatePassword(
      newPassword,
      enforceMinimumLength: true,
    );

    await _runCredentialOperation<void>(
          () => user.updatePassword(
        newPassword,
      ),
    );
  }

  Future<void> changePassword({
    required String newPassword,
  }) {
    return updatePassword(
      newPassword: newPassword,
    );
  }

  // =============================================================
  // PHONE UPDATE
  //
  // Native PhoneAuthCredential compatibility.
  // =============================================================

  Future<void> updatePhoneNumber(
      PhoneAuthCredential credential,
      ) async {
    final User user = _requireCurrentUser();

    await _runCredentialOperation<void>(
          () async {
        await user.updatePhoneNumber(
          credential,
        );

        await user.reload();
      },
    );

    _clearPhoneVerificationState();
  }

  Future<void> changePhoneNumber(
      PhoneAuthCredential credential,
      ) {
    return updatePhoneNumber(
      credential,
    );
  }

  // =============================================================
  // USER RELOAD
  // =============================================================

  Future<void> reloadUser() async {
    final User? user = currentUser;

    if (user == null) {
      return;
    }

    await user.reload();
  }

  Future<User?> checkAndReloadUser() async {
    final User? user = currentUser;

    if (user == null) {
      return null;
    }

    await user.reload();

    return currentUser;
  }

  // =============================================================
  // PROVIDERS
  // =============================================================

  bool hasPhoneNumber() {
    return currentPhoneNumber != null;
  }

  bool hasEmailAddress() {
    return currentEmail != null;
  }

  bool hasProvider(
      String providerId,
      ) {
    final User? user = currentUser;

    if (user == null) {
      return false;
    }

    return _userHasProvider(
      user,
      providerId,
    );
  }

  bool _userHasProvider(
      User user,
      String providerId,
      ) {
    final String normalized = providerId.trim();

    if (normalized.isEmpty) {
      return false;
    }

    return user.providerData.any(
          (UserInfo provider) =>
      provider.providerId.trim() == normalized,
    );
  }

  List<String> get linkedProviderIds {
    final User? user = currentUser;

    if (user == null) {
      return const <String>[];
    }

    final Set<String> ids = <String>{};

    for (final UserInfo provider in user.providerData) {
      final String id = provider.providerId.trim();

      if (id.isNotEmpty) {
        ids.add(id);
      }
    }

    return List<String>.unmodifiable(
      ids,
    );
  }

  List<UserInfo> get linkedProviders {
    final User? user = currentUser;

    if (user == null) {
      return const <UserInfo>[];
    }

    return List<UserInfo>.unmodifiable(
      user.providerData,
    );
  }

  String get primaryProviderId {
    final List<String> providers = linkedProviderIds;

    if (providers.contains('google.com')) {
      return 'google.com';
    }

    if (providers.contains('password')) {
      return 'password';
    }

    if (providers.contains('phone')) {
      return 'phone';
    }

    if (providers.isEmpty) {
      return '';
    }

    return providers.first;
  }

  // =============================================================
  // PROFILE METADATA
  // =============================================================

  Future<void> updateDisplayName(
      String name,
      ) async {
    final User user = _requireCurrentUser();

    await user.updateDisplayName(
      _cleanNullableString(name),
    );

    await user.reload();
  }

  Future<void> updatePhotoUrl(
      String? photoUrl,
      ) async {
    final User user = _requireCurrentUser();

    await user.updatePhotoURL(
      _cleanNullableString(photoUrl),
    );

    await user.reload();
  }

  // =============================================================
  // REAUTHENTICATION — PASSWORD
  // =============================================================

  Future<UserCredential> reauthenticateWithPassword({
    required String email,
    required String password,
  }) {
    final User user = _requireCurrentUser();

    final String normalizedEmail = _normalizeEmail(
      email,
    );

    _validatePassword(
      password,
      enforceMinimumLength: false,
    );

    final AuthCredential credential = EmailAuthProvider.credential(
      email: normalizedEmail,
      password: password,
    );

    return _runCredentialOperation<UserCredential>(
          () => user.reauthenticateWithCredential(
        credential,
      ),
    );
  }

  // =============================================================
  // REAUTHENTICATION — PHONE CREDENTIAL
  // =============================================================

  Future<UserCredential> reauthenticateWithPhoneCredential(
      PhoneAuthCredential credential,
      ) {
    return reauthenticateWithCredential(
      credential,
    );
  }

  Future<UserCredential> reauthenticateWithCredential(
      AuthCredential credential,
      ) {
    final User user = _requireCurrentUser();

    return _runCredentialOperation<UserCredential>(
          () => user.reauthenticateWithCredential(
        credential,
      ),
    );
  }

  // =============================================================
  // ID TOKEN
  // =============================================================

  Future<String?> refreshIdToken() {
    final User user = _requireCurrentUser();

    return user.getIdToken(
      true,
    );
  }

  // =============================================================
  // DELETE CURRENT USER
  // =============================================================

  Future<void> deleteCurrentUser() async {
    final User user = _requireCurrentUser();

    await _runCredentialOperation<void>(
          () => user.delete(),
    );

    _clearPhoneVerificationState();
  }

  Future<void> deleteAccount() {
    return deleteCurrentUser();
  }

  // =============================================================
  // SIGN OUT
  // =============================================================

  Future<void> signOut() async {
    _clearPhoneVerificationState();

    await _auth.signOut();
  }

  Future<void> logout() {
    return signOut();
  }

  // =============================================================
  // PHONE STATE — PUBLIC CLEAR
  // =============================================================

  void clearPhoneVerificationState() {
    _clearPhoneVerificationState();
  }

  // =============================================================
  // PHONE STATE — INTERNAL CLEAR
  // =============================================================

  void _clearPhoneVerificationState() {
    _phoneVerificationGeneration++;

    _lastVerificationId = null;
    _lastResendToken = null;
    _pendingPhoneNumber = null;

    _webConfirmationResult = null;
    _webConfirmationPhone = null;

    _phoneVerificationInProgress = false;
  }

  void _invalidatePendingPhoneSession({
    required bool preserveGeneration,
  }) {
    if (!preserveGeneration) {
      _phoneVerificationGeneration++;
    }

    _lastVerificationId = null;
    _lastResendToken = null;

    _webConfirmationResult = null;
    _webConfirmationPhone = null;

    _pendingPhoneNumber = null;
    _phoneVerificationInProgress = false;
  }

  bool _isCurrentPhoneVerification(
      int generation,
      ) {
    return generation == _phoneVerificationGeneration;
  }

  // =============================================================
  // CURRENT PHONE-AUTHENTICATED USER GUARD
  // =============================================================

  User _requirePhoneAuthenticatedUser() {
    final User user = _requireCurrentUser();

    final String? phone = _cleanNullableString(
      user.phoneNumber,
    );

    final bool hasPhoneProvider = _userHasProvider(
      user,
      'phone',
    );

    if (phone == null || !hasPhoneProvider) {
      throw StateError(
        'A Firebase-verified Phone Number is required before adding '
            'Email/Password to this JR CALL account.',
      );
    }

    return user;
  }

  // =============================================================
  // NORMALIZATION — EMAIL
  // =============================================================

  String _normalizeEmail(
      String email,
      ) {
    final String normalized = email.trim().toLowerCase();

    final bool valid = normalized.isNotEmpty &&
        normalized.length <= 254 &&
        RegExp(
          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
        ).hasMatch(normalized);

    if (!valid) {
      throw ArgumentError.value(
        email,
        'email',
        'A valid Email address is required.',
      );
    }

    return normalized;
  }

  // =============================================================
  // NORMALIZATION — EMAIL PURPOSE
  // =============================================================

  String _normalizeEmailOtpPurpose(
      String purpose,
      ) {
    final String normalized = purpose.trim();

    if (!_supportedEmailOtpPurposes.contains(normalized)) {
      throw ArgumentError.value(
        purpose,
        'purpose',
        'Unsupported Email OTP purpose.',
      );
    }

    return normalized;
  }

  // =============================================================
  // NORMALIZATION — CHALLENGE ID
  // =============================================================

  String _normalizeChallengeId(
      String challengeId,
      ) {
    final String normalized = challengeId.trim();

    if (normalized.isEmpty || normalized.length > 256) {
      throw ArgumentError.value(
        challengeId,
        'challengeId',
        'OTP challenge ID is invalid.',
      );
    }

    return normalized;
  }

  // =============================================================
  // NORMALIZATION — VERIFICATION ID
  // =============================================================

  String _normalizeVerificationId(
      String verificationId,
      ) {
    final String normalized = verificationId.trim();

    if (normalized.isEmpty) {
      throw StateError(
        'No active Phone verification session is available.',
      );
    }

    return normalized;
  }

  // =============================================================
  // NORMALIZATION — PHONE
  // =============================================================

  String _normalizePhoneNumber(
      String phoneNumber,
      ) {
    final String normalized = phoneNumber
        .trim()
        .replaceAll(
      RegExp(r'[\s()\-.]'),
      '',
    );

    final bool valid = RegExp(
      r'^\+[1-9][0-9]{7,14}$',
    ).hasMatch(normalized);

    if (!valid) {
      throw ArgumentError.value(
        phoneNumber,
        'phoneNumber',
        'A valid international Phone Number is required.',
      );
    }

    return normalized;
  }

  // =============================================================
  // NORMALIZATION — OTP
  // =============================================================

  String _normalizeOtp(
      String otp,
      ) {
    final String normalized = otp
        .trim()
        .replaceAll(
      RegExp(r'\s+'),
      '',
    );

    if (!RegExp(r'^[0-9]{6}$').hasMatch(normalized)) {
      throw ArgumentError.value(
        otp,
        'otp',
        'OTP must contain exactly 6 digits.',
      );
    }

    return normalized;
  }

  // =============================================================
  // PASSWORD VALIDATION
  // =============================================================

  void _validatePassword(
      String password, {
        required bool enforceMinimumLength,
      }) {
    if (password.isEmpty) {
      throw ArgumentError.value(
        password,
        'password',
        'Password cannot be empty.',
      );
    }

    if (password.length > 4096) {
      throw ArgumentError.value(
        password,
        'password',
        'Password is too long.',
      );
    }

    if (enforceMinimumLength && password.length < 6) {
      throw ArgumentError.value(
        password,
        'password',
        'Password must contain at least 6 characters.',
      );
    }
  }

  // =============================================================
  // RESPONSE — MAP
  // =============================================================

  Map<String, dynamic> _asStringMap(
      Object? value,
      ) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(
        value,
      );
    }

    return const <String, dynamic>{};
  }

  // =============================================================
  // RESPONSE — REQUIRED STRING
  // =============================================================

  String _readRequiredString(
      Object? value, {
        required String fieldName,
      }) {
    final String? result = _readNullableString(
      value,
    );

    if (result == null) {
      throw StateError(
        'JR CALL backend did not return a valid $fieldName.',
      );
    }

    return result;
  }

  // =============================================================
  // RESPONSE — NULLABLE STRING
  // =============================================================

  String? _readNullableString(
      Object? value,
      ) {
    if (value is! String) {
      return null;
    }

    final String normalized = value.trim();

    if (normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  // =============================================================
  // RESPONSE — POSITIVE INTEGER
  // =============================================================

  int _readPositiveInt(
      Object? value, {
        required int fallback,
      }) {
    if (value is int && value > 0) {
      return value;
    }

    if (value is num && value > 0) {
      return value.toInt();
    }

    return fallback;
  }

  // =============================================================
  // CLEAN NULLABLE STRING
  // =============================================================

  String? _cleanNullableString(
      String? value,
      ) {
    if (value == null) {
      return null;
    }

    final String cleaned = value.trim();

    if (cleaned.isEmpty) {
      return null;
    }

    return cleaned;
  }

  // =============================================================
  // CREDENTIAL OPERATION GUARD
  // =============================================================

  Future<T> _runCredentialOperation<T>(
      Future<T> Function() operation,
      ) async {
    if (_credentialOperationInProgress) {
      throw StateError(
        'Another authentication operation is already in progress.',
      );
    }

    _credentialOperationInProgress = true;

    try {
      return await operation();
    } finally {
      _credentialOperationInProgress = false;
    }
  }

  // =============================================================
  // CURRENT USER GUARD
  // =============================================================

  User _requireCurrentUser() {
    final User? user = currentUser;

    if (user == null || user.uid.trim().isEmpty) {
      throw StateError(
        'No authenticated Firebase user is available.',
      );
    }

    return user;
  }
}

// ===============================================================
// EMAIL OTP CHALLENGE
// ===============================================================

class EmailOtpChallenge {
  const EmailOtpChallenge({
    required this.challengeId,
    required this.expiresInSeconds,
    required this.resendAfterSeconds,
  });

  final String challengeId;

  final int expiresInSeconds;

  final int resendAfterSeconds;

  Duration get expiresIn {
    return Duration(
      seconds: expiresInSeconds,
    );
  }

  Duration get resendAfter {
    return Duration(
      seconds: resendAfterSeconds,
    );
  }
}

// ===============================================================
// EMAIL OTP RESULT
// ===============================================================

class EmailOtpVerificationResult {
  const EmailOtpVerificationResult({
    required this.success,
    required this.verified,
    required this.challengeId,
    required this.purpose,
    this.email,
  });

  final bool success;

  final bool verified;

  final String challengeId;

  final String purpose;

  final String? email;
}

// ===============================================================
// PASSWORD RECOVERY CHALLENGE
// ===============================================================

class PasswordRecoveryChallenge {
  const PasswordRecoveryChallenge({
    required this.accepted,
    required this.challengeId,
    required this.expiresInSeconds,
    required this.resendAfterSeconds,
  });

  final bool accepted;

  final String? challengeId;

  final int expiresInSeconds;

  final int resendAfterSeconds;

  bool get hasChallenge {
    final String? value = challengeId;

    return value != null && value.trim().isNotEmpty;
  }

  Duration get expiresIn {
    return Duration(
      seconds: expiresInSeconds,
    );
  }

  Duration get resendAfter {
    return Duration(
      seconds: resendAfterSeconds,
    );
  }
}

// ===============================================================
// END OF FILE
//
// OTP / AUTH MASTER FILE 01 / 09
//
// FINAL JR CALL CONTRACT:
//
// ✓ Phone is mandatory account identity.
// ✓ Phone Signup requires Firebase Phone OTP.
// ✓ Phone Login requires Firebase Phone OTP.
// ✓ Phone + typed Password never bypasses Phone OTP.
// ✓ No Phone Password authentication.
// ✓ No account-exists blocker before Phone Login.
// ✓ No local/fake Phone OTP.
// ✓ No OTP persistence.
// ✓ No Password persistence.
//
// ✓ Android/iOS native Phone verification supported.
// ✓ Android automatic verification supported.
// ✓ Manual 6-digit native OTP supported.
// ✓ Native resend token supported.
// ✓ Web Firebase Phone verification supported.
// ✓ Web manual OTP confirmation supported.
// ✓ Firebase-managed Web security verification preserved.
// ✓ Different Phone sessions cannot reuse stale verification state.
//
// ✓ Standalone Email account creation blocked by service contract.
// ✓ Email/Password can be added after verified Phone authentication.
// ✓ Email/Password linking preserves same Firebase UID.
// ✓ Email + Password Login is direct.
// ✓ Email Login does NOT require JR CALL Email OTP.
// ✓ Email Login does NOT require Email verification.
//
// ✓ Legacy Email OTP APIs preserved for compatibility.
// ✓ Email Signup/Change OTP APIs preserved.
// ✓ Password Recovery OTP APIs preserved.
// ✓ Firebase reset Email compatibility API preserved.
//
// ✓ Existing AuthService public APIs preserved.
// ✓ Provider APIs preserved.
// ✓ Reauthentication APIs preserved.
// ✓ Settings APIs preserved.
// ✓ Profile metadata APIs preserved.
// ✓ Delete/Logout APIs preserved.
//
// ✓ Multiple Firebase sessions are not deliberately revoked.
// ✓ Call Engine untouched.
// ✓ Message Engine untouched.
// ✓ WebRTC untouched.
// ✓ Signaling untouched.
//
// REPLACE:
//
// lib/services/auth_service.dart
//
// NEXT OTP FILE:
//
// lib/screens/login_otp_manager.dart
// ===============================================================