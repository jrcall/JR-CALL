// ===============================================================
// JR CALL
// File: login_otp_manager.dart
// Location: lib/screens/login_otp_manager.dart
//
// OTP / AUTH MASTER FILE 02 / 09
//
// PRODUCTION PHONE LOGIN OTP COORDINATOR
//
// ===============================================================
//
// OWNERSHIP:
//
// ✓ Phone Login OTP request coordination.
// ✓ Native Firebase automatic Phone verification.
// ✓ Manual 6-digit Phone OTP completion.
// ✓ Native resend coordination.
// ✓ Web Phone OTP compatibility through AuthService.
// ✓ Stale callback rejection.
// ✓ Duplicate request protection.
// ✓ Automatic credential single-flight protection.
// ✓ Firebase UID resolution.
// ✓ Existing / missing Firestore profile resolution.
// ✓ Existing profile authentication-metadata synchronization.
// ✓ Deleted / blocked profile rejection.
//
// ===============================================================
//
// JR CALL PHONE LOGIN CONTRACT
//
// Phone Number
//      ↓
// ALWAYS Firebase Phone Authentication
//      ↓
// OTP verification required
//      ↓
// Firebase UID
//      ↓
// Firestore users/{uid}
//
// IMPORTANT:
//
// ✓ Phone Login always requires Firebase Phone verification.
// ✓ Password entered beside a Phone Number NEVER bypasses OTP.
// ✓ Phone Login can work with Phone Number only.
// ✓ NO Phone password authentication.
// ✓ NO phoneAccountExists() pre-login blocker.
// ✓ NO fake/local OTP.
// ✓ NO OTP persistence.
// ✓ NO reCAPTCHA bypass.
// ✓ NO Play Integrity bypass.
// ✓ NO Firebase App Verification bypass.
//
// EMAIL LOGIN:
//
// Email + Password direct login is owned by:
// LoginScreen → AuthService.signInWithEmailPassword()
//
// Email Login does NOT pass through LoginOtpManager.
//
// ===============================================================
//
// ACCOUNT STATE:
//
// Existing Firebase UID + existing users/{uid}
//      → existingProfile
//
// Successful Firebase Phone Auth + missing users/{uid}
//      → newProfileRequired
//
// Missing profile is NOT an authentication failure.
//
// This manager NEVER creates the JR CALL profile.
// This manager NEVER deletes a newly authenticated Firebase user.
//
// ===============================================================
//
// PLATFORM CONTRACT:
//
// Android / iOS:
//
// AuthService.verifyPhoneNumber()
//      ├── verificationCompleted
//      │      → automatic credential
//      └── codeSent
//             → verificationId
//             → manual 6-digit OTP
//
// Web:
//
// AuthService.verifyPhoneNumber()
//      ↓
// Firebase Web Phone Auth
//      ↓
// codeSent
//      ↓
// AuthService.signInWithOtp()
//      ↓
// ConfirmationResult.confirm()
//
// ===============================================================
//
// PROTECTED:
//
// ✓ Call Engine untouched.
// ✓ Message Engine untouched.
// ✓ WebRTC untouched.
// ✓ Signaling untouched.
// ✓ Profile creation ownership untouched.
// ===============================================================

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firebase/firestore_service.dart';

// ===============================================================
// ACCOUNT STATE
// ===============================================================

enum LoginOtpAccountState {
  existingProfile,
  newProfileRequired,
}

// ===============================================================
// LOGIN OTP RESULT
// ===============================================================

class LoginOtpResult {
  const LoginOtpResult({
    required this.user,
    required this.accountState,
    this.profile,
  });

  final User user;

  final LoginOtpAccountState accountState;

  final UserModel? profile;

  bool get hasExistingProfile {
    return accountState == LoginOtpAccountState.existingProfile;
  }

  bool get requiresProfileSetup {
    return accountState == LoginOtpAccountState.newProfileRequired;
  }
}

// ===============================================================
// LOGIN OTP MANAGER
// ===============================================================

class LoginOtpManager {
  LoginOtpManager({
    AuthService? authService,
    FirestoreService? firestoreService,
  }) : _authService = authService ?? AuthService.instance,
        _firestoreService = firestoreService ?? FirestoreService.instance;

  // =============================================================
  // DEPENDENCIES
  // =============================================================

  final AuthService _authService;

  final FirestoreService _firestoreService;

  // =============================================================
  // VERIFICATION STATE
  // =============================================================

  bool _startingVerification = false;

  bool _automaticCredentialRunning = false;

  bool _manualCredentialRunning = false;

  int _operationGeneration = 0;

  String? _activePhoneNumber;

  String? _activeVerificationId;

  // =============================================================
  // PUBLIC STATE
  // =============================================================

  bool get isStartingVerification {
    return _startingVerification;
  }

  bool get isAutomaticCredentialRunning {
    return _automaticCredentialRunning;
  }

  bool get isManualCredentialRunning {
    return _manualCredentialRunning;
  }

  bool get isBusy {
    return _startingVerification ||
        _automaticCredentialRunning ||
        _manualCredentialRunning;
  }

  String? get activePhoneNumber {
    return _activePhoneNumber;
  }

  String? get activeVerificationId {
    return _activeVerificationId;
  }

  bool get hasActiveVerification {
    final String? phone = _cleanNullable(
      _activePhoneNumber,
    );

    final String? verificationId = _cleanNullable(
      _activeVerificationId,
    );

    return phone != null && verificationId != null;
  }

  // =============================================================
  // START PHONE LOGIN
  // =============================================================

  Future<void> startPhoneLogin({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(LoginOtpResult result) onAutomaticVerified,
    required void Function(FirebaseAuthException error) onVerificationFailed,
    void Function(String verificationId)? onAutoRetrievalTimeout,
  }) async {
    final String normalizedPhone = _normalizePhone(
      phoneNumber,
    );

    if (isBusy) {
      onVerificationFailed(
        FirebaseAuthException(
          code: 'verification-in-progress',
          message: 'Phone verification is already in progress.',
        ),
      );

      return;
    }

    await _startVerification(
      phoneNumber: normalizedPhone,
      resend: false,
      onCodeSent: onCodeSent,
      onAutomaticVerified: onAutomaticVerified,
      onVerificationFailed: onVerificationFailed,
      onAutoRetrievalTimeout: onAutoRetrievalTimeout,
    );
  }

  // =============================================================
  // RESEND PHONE OTP
  // =============================================================

  Future<void> resendPhoneOtp({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(LoginOtpResult result) onAutomaticVerified,
    required void Function(FirebaseAuthException error) onVerificationFailed,
    void Function(String verificationId)? onAutoRetrievalTimeout,
  }) async {
    final String normalizedPhone = _normalizePhone(
      phoneNumber,
    );

    if (isBusy) {
      onVerificationFailed(
        FirebaseAuthException(
          code: 'verification-in-progress',
          message: 'Phone verification is already in progress.',
        ),
      );

      return;
    }

    await _startVerification(
      phoneNumber: normalizedPhone,
      resend: true,
      onCodeSent: onCodeSent,
      onAutomaticVerified: onAutomaticVerified,
      onVerificationFailed: onVerificationFailed,
      onAutoRetrievalTimeout: onAutoRetrievalTimeout,
    );
  }

  // =============================================================
  // INTERNAL VERIFICATION START
  // =============================================================

  Future<void> _startVerification({
    required String phoneNumber,
    required bool resend,
    required void Function(String verificationId) onCodeSent,
    required void Function(LoginOtpResult result) onAutomaticVerified,
    required void Function(FirebaseAuthException error) onVerificationFailed,
    required void Function(String verificationId)? onAutoRetrievalTimeout,
  }) async {
    final int generation = ++_operationGeneration;

    _startingVerification = true;

    _activePhoneNumber = phoneNumber;

    if (!resend) {
      _activeVerificationId = null;
    }

    try {
      if (resend) {
        await _authService.resendPhoneVerificationCode(
          phoneNumber: phoneNumber,

          // -----------------------------------------------------
          // NATIVE AUTOMATIC VERIFICATION
          // -----------------------------------------------------

          verificationCompleted: (
              PhoneAuthCredential credential,
              ) {
            _handleVerificationCompleted(
              credential: credential,
              phoneNumber: phoneNumber,
              generation: generation,
              onAutomaticVerified: onAutomaticVerified,
              onVerificationFailed: onVerificationFailed,
            );
          },

          // -----------------------------------------------------
          // FAILURE
          // -----------------------------------------------------

          verificationFailed: (
              FirebaseAuthException error,
              ) {
            _handleVerificationFailure(
              error: error,
              generation: generation,
              onVerificationFailed: onVerificationFailed,
            );
          },

          // -----------------------------------------------------
          // OTP SENT
          // -----------------------------------------------------

          codeSent: (
              String verificationId,
              ) {
            _handleCodeSent(
              verificationId: verificationId,
              generation: generation,
              onCodeSent: onCodeSent,
              onVerificationFailed: onVerificationFailed,
            );
          },

          // -----------------------------------------------------
          // NATIVE AUTO RETRIEVAL TIMEOUT
          // -----------------------------------------------------

          codeAutoRetrievalTimeout: (
              String verificationId,
              ) {
            _handleAutoRetrievalTimeout(
              verificationId: verificationId,
              generation: generation,
              onAutoRetrievalTimeout: onAutoRetrievalTimeout,
            );
          },
        );

        return;
      }

      await _authService.verifyPhoneNumber(
        phoneNumber: phoneNumber,

        // -------------------------------------------------------
        // NATIVE AUTOMATIC VERIFICATION
        // -------------------------------------------------------

        verificationCompleted: (
            PhoneAuthCredential credential,
            ) {
          _handleVerificationCompleted(
            credential: credential,
            phoneNumber: phoneNumber,
            generation: generation,
            onAutomaticVerified: onAutomaticVerified,
            onVerificationFailed: onVerificationFailed,
          );
        },

        // -------------------------------------------------------
        // FAILURE
        // -------------------------------------------------------

        verificationFailed: (
            FirebaseAuthException error,
            ) {
          _handleVerificationFailure(
            error: error,
            generation: generation,
            onVerificationFailed: onVerificationFailed,
          );
        },

        // -------------------------------------------------------
        // OTP SENT
        // -------------------------------------------------------

        codeSent: (
            String verificationId,
            ) {
          _handleCodeSent(
            verificationId: verificationId,
            generation: generation,
            onCodeSent: onCodeSent,
            onVerificationFailed: onVerificationFailed,
          );
        },

        // -------------------------------------------------------
        // NATIVE AUTO RETRIEVAL TIMEOUT
        // -------------------------------------------------------

        codeAutoRetrievalTimeout: (
            String verificationId,
            ) {
          _handleAutoRetrievalTimeout(
            verificationId: verificationId,
            generation: generation,
            onAutoRetrievalTimeout: onAutoRetrievalTimeout,
          );
        },
      );
    } on FirebaseAuthException catch (error) {
      if (!_isCurrentOperation(generation)) {
        return;
      }

      _startingVerification = false;

      onVerificationFailed(
        error,
      );
    } on ArgumentError {
      if (_isCurrentOperation(generation)) {
        _startingVerification = false;
      }

      rethrow;
    } on StateError catch (error) {
      if (!_isCurrentOperation(generation)) {
        return;
      }

      _startingVerification = false;

      onVerificationFailed(
        FirebaseAuthException(
          code: 'phone-verification-state-error',
          message: error.message,
        ),
      );
    } catch (error) {
      if (!_isCurrentOperation(generation)) {
        return;
      }

      _startingVerification = false;

      onVerificationFailed(
        _convertToFirebaseAuthException(
          error,
        ),
      );
    }
  }

  // =============================================================
  // VERIFICATION COMPLETED
  //
  // Android native automatic verification path.
  // =============================================================

  void _handleVerificationCompleted({
    required PhoneAuthCredential credential,
    required String phoneNumber,
    required int generation,
    required void Function(LoginOtpResult result) onAutomaticVerified,
    required void Function(FirebaseAuthException error) onVerificationFailed,
  }) {
    if (!_isCurrentOperation(generation)) {
      return;
    }

    _startingVerification = false;

    unawaited(
      _runAutomaticCredential(
        credential: credential,
        phoneNumber: phoneNumber,
        generation: generation,
        onSuccess: onAutomaticVerified,
        onFailure: onVerificationFailed,
      ),
    );
  }

  // =============================================================
  // VERIFICATION FAILED
  // =============================================================

  void _handleVerificationFailure({
    required FirebaseAuthException error,
    required int generation,
    required void Function(FirebaseAuthException error) onVerificationFailed,
  }) {
    if (!_isCurrentOperation(generation)) {
      return;
    }

    _startingVerification = false;

    onVerificationFailed(
      error,
    );
  }

  // =============================================================
  // CODE SENT
  // =============================================================

  void _handleCodeSent({
    required String verificationId,
    required int generation,
    required void Function(String verificationId) onCodeSent,
    required void Function(FirebaseAuthException error) onVerificationFailed,
  }) {
    if (!_isCurrentOperation(generation)) {
      return;
    }

    final String normalizedVerificationId = verificationId.trim();

    _startingVerification = false;

    if (normalizedVerificationId.isEmpty) {
      _activeVerificationId = null;

      onVerificationFailed(
        FirebaseAuthException(
          code: 'invalid-verification-id',
          message:
          'Firebase did not provide a valid Phone verification session.',
        ),
      );

      return;
    }

    _activeVerificationId = normalizedVerificationId;

    onCodeSent(
      normalizedVerificationId,
    );
  }

  // =============================================================
  // AUTO RETRIEVAL TIMEOUT
  //
  // IMPORTANT:
  //
  // Timeout does NOT invalidate the manual OTP session.
  // =============================================================

  void _handleAutoRetrievalTimeout({
    required String verificationId,
    required int generation,
    required void Function(String verificationId)? onAutoRetrievalTimeout,
  }) {
    if (!_isCurrentOperation(generation)) {
      return;
    }

    _startingVerification = false;

    final String normalizedVerificationId = verificationId.trim();

    if (normalizedVerificationId.isEmpty) {
      return;
    }

    _activeVerificationId = normalizedVerificationId;

    onAutoRetrievalTimeout?.call(
      normalizedVerificationId,
    );
  }

  // =============================================================
  // AUTOMATIC PHONE CREDENTIAL
  // =============================================================

  Future<void> _runAutomaticCredential({
    required PhoneAuthCredential credential,
    required String phoneNumber,
    required int generation,
    required void Function(LoginOtpResult result) onSuccess,
    required void Function(FirebaseAuthException error) onFailure,
  }) async {
    if (!_isCurrentOperation(generation)) {
      return;
    }

    if (_automaticCredentialRunning ||
        _manualCredentialRunning) {
      return;
    }

    _automaticCredentialRunning = true;

    try {
      final LoginOtpResult result = await signInWithPhoneCredential(
        credential: credential,
        fallbackPhoneNumber: phoneNumber,
      );

      if (!_isCurrentOperation(generation)) {
        return;
      }

      onSuccess(
        result,
      );
    } on FirebaseAuthException catch (error) {
      if (_isCurrentOperation(generation)) {
        onFailure(
          error,
        );
      }
    } on StateError catch (error) {
      if (_isCurrentOperation(generation)) {
        onFailure(
          FirebaseAuthException(
            code: 'phone-login-state-error',
            message: error.message,
          ),
        );
      }
    } on ArgumentError catch (error) {
      if (_isCurrentOperation(generation)) {
        onFailure(
          FirebaseAuthException(
            code: 'phone-login-invalid-argument',
            message:
            error.message?.toString() ??
                'Phone authentication information is invalid.',
          ),
        );
      }
    } catch (error) {
      if (_isCurrentOperation(generation)) {
        onFailure(
          _convertToFirebaseAuthException(
            error,
          ),
        );
      }
    } finally {
      _automaticCredentialRunning = false;
    }
  }

  // =============================================================
  // MANUAL OTP SIGN-IN
  //
  // IMPORTANT:
  //
  // This calls AuthService.signInWithOtp().
  //
  // Therefore:
  //
  // Native:
  // verificationId + smsCode
  //      → PhoneAuthCredential
  //      → Firebase signInWithCredential()
  //
  // Web:
  // verificationId + smsCode
  //      → AuthService Web pending ConfirmationResult
  //      → confirm()
  //
  // One manager API therefore works with the AuthService platform
  // contract without duplicating Firebase Web Phone logic here.
  // =============================================================

  Future<LoginOtpResult> signInWithManualOtp({
    required String verificationId,
    required String smsCode,
    String? fallbackPhoneNumber,
  }) async {
    if (_manualCredentialRunning ||
        _automaticCredentialRunning) {
      throw StateError(
        'Phone authentication is already being completed.',
      );
    }

    final String normalizedVerificationId =
    _normalizeVerificationId(
      verificationId,
    );

    final String normalizedOtp = _normalizeOtp(
      smsCode,
    );

    _manualCredentialRunning = true;

    try {
      final UserCredential credentialResult =
      await _authService.signInWithOtp(
        verificationId: normalizedVerificationId,
        smsCode: normalizedOtp,
      );

      return _resolveAuthenticatedCredential(
        credentialResult: credentialResult,
        fallbackPhoneNumber:
        fallbackPhoneNumber ?? _activePhoneNumber,
      );
    } finally {
      _manualCredentialRunning = false;
    }
  }

  // =============================================================
  // MANUAL OTP USING ACTIVE VERIFICATION SESSION
  // =============================================================

  Future<LoginOtpResult> signInWithActiveOtp({
    required String smsCode,
  }) async {
    final String? verificationId = _cleanNullable(
      _activeVerificationId,
    );

    if (verificationId == null) {
      throw StateError(
        'No active Phone verification session is available.',
      );
    }

    return signInWithManualOtp(
      verificationId: verificationId,
      smsCode: smsCode,
      fallbackPhoneNumber: _activePhoneNumber,
    );
  }

  // =============================================================
  // SIGN IN WITH NATIVE PHONE CREDENTIAL
  //
  // Used by automatic native verification.
  // Also remains reusable by native callers.
  // =============================================================

  Future<LoginOtpResult> signInWithPhoneCredential({
    required PhoneAuthCredential credential,
    String? fallbackPhoneNumber,
  }) async {
    final UserCredential credentialResult =
    await _authService.signInWithPhoneCredential(
      credential,
    );

    return _resolveAuthenticatedCredential(
      credentialResult: credentialResult,
      fallbackPhoneNumber: fallbackPhoneNumber,
    );
  }

  // =============================================================
  // RESOLVE AUTHENTICATED FIREBASE USER
  // =============================================================

  Future<LoginOtpResult> _resolveAuthenticatedCredential({
    required UserCredential credentialResult,
    String? fallbackPhoneNumber,
  }) async {
    final User? user =
        credentialResult.user ??
            _authService.currentUser;

    if (user == null ||
        user.uid.trim().isEmpty) {
      throw StateError(
        'Firebase Phone verification succeeded but no authenticated '
            'Firebase user was returned.',
      );
    }

    final String uid = user.uid.trim();

    final UserModel? profile =
    await _firestoreService.getUser(
      uid,
    );

    // -----------------------------------------------------------
    // AUTH SUCCESS + PROFILE MISSING
    //
    // This is a valid authenticated Firebase account.
    //
    // Profile setup is owned by CreateProfileSetupScreen /
    // account creation flow.
    // -----------------------------------------------------------

    if (profile == null) {
      _clearSuccessfulManagerState();

      return LoginOtpResult(
        user: user,
        accountState: LoginOtpAccountState.newProfileRequired,
      );
    }

    // -----------------------------------------------------------
    // DELETED ACCOUNT
    // -----------------------------------------------------------

    if (profile.isDeleted) {
      await _safeSignOut();

      throw StateError(
        'This JR CALL account has been deleted.',
      );
    }

    // -----------------------------------------------------------
    // BLOCKED ACCOUNT
    // -----------------------------------------------------------

    if (profile.isBlocked) {
      await _safeSignOut();

      throw StateError(
        'This JR CALL account is currently unavailable.',
      );
    }

    // -----------------------------------------------------------
    // EXISTING PROFILE
    //
    // Only Firebase authentication-owned metadata is synchronized.
    //
    // Existing:
    // - Name
    // - Username
    // - JR CALL ID
    // - Bio
    // - Photos
    // - Public profile information
    //
    // are NOT recreated here.
    // -----------------------------------------------------------

    await _synchronizeExistingProfile(
      user: user,
      profile: profile,
      fallbackPhoneNumber: fallbackPhoneNumber,
    );

    final UserModel refreshedProfile =
        await _firestoreService.getUser(
          uid,
        ) ??
            profile;

    if (refreshedProfile.isDeleted) {
      await _safeSignOut();

      throw StateError(
        'This JR CALL account has been deleted.',
      );
    }

    if (refreshedProfile.isBlocked) {
      await _safeSignOut();

      throw StateError(
        'This JR CALL account is currently unavailable.',
      );
    }

    _clearSuccessfulManagerState();

    return LoginOtpResult(
      user: user,
      accountState: LoginOtpAccountState.existingProfile,
      profile: refreshedProfile,
    );
  }

  // =============================================================
  // AUTHENTICATION METADATA SYNCHRONIZATION
  // =============================================================

  Future<void> _synchronizeExistingProfile({
    required User user,
    required UserModel profile,
    String? fallbackPhoneNumber,
  }) async {
    final String authenticatedPhone =
        _cleanNullable(
          user.phoneNumber,
        ) ??
            '';

    final String fallbackPhone =
        _cleanNullable(
          fallbackPhoneNumber,
        ) ??
            '';

    final String profilePhone =
        _cleanNullable(
          profile.phone,
        ) ??
            '';

    final String resolvedPhone;

    if (authenticatedPhone.isNotEmpty) {
      resolvedPhone = authenticatedPhone;
    } else if (fallbackPhone.isNotEmpty) {
      resolvedPhone = fallbackPhone;
    } else {
      resolvedPhone = profilePhone;
    }

    final String? authenticatedEmail = _cleanNullable(
      user.email,
    );

    await _firestoreService.syncAuthenticationProfile(
      uid: user.uid,
      email: authenticatedEmail,
      phoneNumber:
      resolvedPhone.isEmpty
          ? null
          : resolvedPhone,
      emailVerified: user.emailVerified,
      phoneVerified: resolvedPhone.isNotEmpty,
      signInProviders: _authService.linkedProviderIds,
    );
  }

  // =============================================================
  // SUCCESSFUL MANAGER STATE CLEAR
  //
  // AuthService clears its own Phone session after successful
  // authentication.
  //
  // This clears manager-local UI coordination state.
  // =============================================================

  void _clearSuccessfulManagerState() {
    _startingVerification = false;
    _automaticCredentialRunning = false;

    _activeVerificationId = null;
    _activePhoneNumber = null;
  }

  // =============================================================
  // CANCEL / INVALIDATE CALLBACKS
  //
  // Used when LoginScreen is disposed or abandons current Phone
  // verification flow.
  // =============================================================

  void cancel() {
    _operationGeneration++;

    _startingVerification = false;
    _automaticCredentialRunning = false;
    _manualCredentialRunning = false;

    _activePhoneNumber = null;
    _activeVerificationId = null;

    _authService.clearPhoneVerificationState();
  }

  // =============================================================
  // PHONE NORMALIZATION
  // =============================================================

  String _normalizePhone(
      String value,
      ) {
    final String normalized = value
        .trim()
        .replaceAll(
      RegExp(r'[\s()\-.]'),
      '',
    );

    if (!RegExp(
      r'^\+[1-9][0-9]{7,14}$',
    ).hasMatch(normalized)) {
      throw ArgumentError.value(
        value,
        'phoneNumber',
        'A valid international Phone Number is required.',
      );
    }

    return normalized;
  }

  // =============================================================
  // VERIFICATION ID NORMALIZATION
  // =============================================================

  String _normalizeVerificationId(
      String verificationId,
      ) {
    final String normalized =
    verificationId.trim();

    if (normalized.isEmpty) {
      throw StateError(
        'No active Phone verification session is available.',
      );
    }

    return normalized;
  }

  // =============================================================
  // OTP NORMALIZATION
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

    if (!RegExp(
      r'^[0-9]{6}$',
    ).hasMatch(normalized)) {
      throw ArgumentError.value(
        otp,
        'smsCode',
        'OTP must contain exactly 6 digits.',
      );
    }

    return normalized;
  }

  // =============================================================
  // STRING CLEANER
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
  // GENERATION GUARD
  // =============================================================

  bool _isCurrentOperation(
      int generation,
      ) {
    return generation == _operationGeneration;
  }

  // =============================================================
  // ERROR CONVERSION
  // =============================================================

  FirebaseAuthException _convertToFirebaseAuthException(
      Object error,
      ) {
    if (error is FirebaseAuthException) {
      return error;
    }

    if (error is StateError) {
      return FirebaseAuthException(
        code: 'phone-login-state-error',
        message: error.message,
      );
    }

    if (error is ArgumentError) {
      return FirebaseAuthException(
        code: 'phone-login-invalid-argument',
        message:
        error.message?.toString() ??
            'Phone authentication information is invalid.',
      );
    }

    return FirebaseAuthException(
      code: 'phone-verification-failed',
      message:
      'Phone verification could not be completed. '
          'Please try again.',
    );
  }

  // =============================================================
  // SAFE SIGN OUT
  // =============================================================

  Future<void> _safeSignOut() async {
    try {
      await _authService.signOut();
    } catch (_) {
      // Best-effort authentication cleanup.
    } finally {
      _clearSuccessfulManagerState();
    }
  }
}

// ===============================================================
// END OF FILE
//
// OTP / AUTH MASTER FILE 02 / 09
//
// FINAL RESPONSIBILITY:
//
// LoginScreen
//      ↓
// LoginOtpManager
//      ↓
// AuthService
//      ↓
// Firebase Authentication
//      ↓
// Firebase UID
//      ↓
// Firestore users/{uid}
//
// ===============================================================
//
// PHONE LOGIN:
//
// ✓ Phone Login always enters Firebase Phone verification.
// ✓ Phone Number only login supported.
// ✓ Phone + Password still requires Phone OTP.
// ✓ Password cannot bypass Phone verification.
// ✓ Native automatic verification supported.
// ✓ Manual 6-digit OTP supported.
// ✓ Native resend supported.
// ✓ Web manual Phone OTP supported through AuthService.
// ✓ Same Firebase Phone Number restores same Firebase UID.
// ✓ Multiple legitimate Firebase sessions are not revoked here.
//
// ===============================================================
//
// PROFILE RESOLUTION:
//
// ✓ Existing users/{uid} → existingProfile.
// ✓ Missing users/{uid} → newProfileRequired.
// ✓ Missing profile is not authentication failure.
// ✓ Existing profile is not recreated.
// ✓ New Firebase Phone user is not deleted.
// ✓ Deleted account rejected.
// ✓ Blocked account rejected.
// ✓ Authentication-owned metadata synchronized.
//
// ===============================================================
//
// SAFETY:
//
// ✓ No phoneAccountExists() pre-login blocker.
// ✓ No Phone password.
// ✓ No Email Login OTP ownership.
// ✓ No fake/local OTP.
// ✓ No OTP persistence.
// ✓ No Password persistence.
// ✓ No reCAPTCHA bypass.
// ✓ No Play Integrity bypass.
// ✓ No Firebase App Verification bypass.
// ✓ Stale callbacks rejected.
// ✓ Duplicate request rejected.
// ✓ Automatic credential duplicate guarded.
// ✓ Manual credential duplicate guarded.
//
// ===============================================================
//
// PROTECTED:
//
// ✓ Call Engine untouched.
// ✓ Message Engine untouched.
// ✓ WebRTC untouched.
// ✓ Signaling untouched.
//
// ===============================================================
//
// SAVE / REPLACE:
//
// lib/screens/login_otp_manager.dart
//
// NEXT OTP FILE:
//
// lib/screens/create_account_otp_manager.dart
//
// ===============================================================