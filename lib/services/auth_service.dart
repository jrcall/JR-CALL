// ===============================================================
// JR CALL
// File: auth_service.dart
// Location: lib/services/auth_service.dart
//
// PURPOSE:
// Production Authentication coordinator.
//
// FINAL LOGIN LOGIC:
// - Existing Email account:
//   Email + Password -> Firebase Login -> JR CALL Email OTP.
// - Existing Phone account:
//   Phone -> Firebase SMS OTP -> automatic/manual verification.
// - Successful verification leaves Firebase user authenticated.
// - Screens own final HomeScreen routing.
// - No fake/local OTP.
// - No password/OTP persistence.
// - Email OTP always uses us-central1 Cloud Functions.
// ===============================================================

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  // EMAIL OTP PURPOSE
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
  // PHONE RUNTIME STATE
  // =============================================================

  bool _phoneVerificationInProgress = false;
  int _phoneVerificationGeneration = 0;

  String? _lastVerificationId;
  int? _lastResendToken;
  String? _pendingPhoneNumber;

  bool _credentialOperationInProgress = false;

  bool get isPhoneVerificationInProgress => _phoneVerificationInProgress;

  bool get isCredentialOperationInProgress => _credentialOperationInProgress;

  String? get lastVerificationId => _lastVerificationId;

  int? get lastResendToken => _lastResendToken;

  String? get pendingPhoneNumber => _pendingPhoneNumber;

  // =============================================================
  // CURRENT USER
  // =============================================================

  User? get currentUser => _auth.currentUser;

  bool get isSignedIn => currentUser != null;

  String? get currentUserId {
    final String? uid = currentUser?.uid;

    if (uid == null) {
      return null;
    }

    final String normalized = uid.trim();

    return normalized.isEmpty ? null : normalized;
  }

  String? get currentEmail => _cleanNullableString(currentUser?.email);

  String? get currentPhoneNumber =>
      _cleanNullableString(currentUser?.phoneNumber);

  bool get emailVerified => currentUser?.emailVerified ?? false;

  bool get phoneVerified => currentPhoneNumber != null;

  // =============================================================
  // AUTH STREAMS
  // =============================================================

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Stream<User?> get idTokenChanges => _auth.idTokenChanges();

  Stream<User?> get userChanges => _auth.userChanges();

  // =============================================================
  // PHONE ACCOUNT EXISTS
  // =============================================================

  Future<bool> phoneAccountExists({required String phoneNumber}) async {
    final String normalizedPhone = _normalizePhoneNumber(phoneNumber);

    final HttpsCallable callable = _functions.httpsCallable(
      checkPhoneAccountExistsFunction,
    );

    final HttpsCallableResult<dynamic> result = await callable.call<dynamic>(
      <String, dynamic>{'phoneNumber': normalizedPhone},
    );

    final Map<String, dynamic> data = _asStringMap(result.data);

    final Object? exists = data['exists'];

    if (exists is! bool) {
      throw StateError(
        'JR CALL Phone account service returned an invalid response.',
      );
    }

    return exists;
  }

  Future<bool> checkPhoneAccountExists({required String phoneNumber}) {
    return phoneAccountExists(phoneNumber: phoneNumber);
  }

  // =============================================================
  // PHONE OTP SEND
  // =============================================================

  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(String verificationId) codeSent,
    required void Function(FirebaseAuthException error) verificationFailed,
    void Function(PhoneAuthCredential credential)? verificationCompleted,
    void Function(String verificationId)? codeAutoRetrievalTimeout,
    void Function(String verificationId, int? resendToken)? codeSentWithToken,
    Duration timeout = const Duration(seconds: 60),
    int? forceResendingToken,
  }) async {
    final String normalizedPhone = _normalizePhoneNumber(phoneNumber);

    if (_phoneVerificationInProgress && forceResendingToken == null) {
      verificationFailed(
        FirebaseAuthException(
          code: 'verification-in-progress',
          message: 'Phone verification is already in progress.',
        ),
      );

      return;
    }

    final int generation = ++_phoneVerificationGeneration;

    _phoneVerificationInProgress = true;
    _pendingPhoneNumber = normalizedPhone;

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: normalizedPhone,
        timeout: timeout,
        forceResendingToken: forceResendingToken,
        verificationCompleted: (PhoneAuthCredential credential) {
          if (!_isCurrentPhoneVerification(generation)) {
            return;
          }

          _phoneVerificationInProgress = false;

          verificationCompleted?.call(credential);
        },
        verificationFailed: (FirebaseAuthException error) {
          if (!_isCurrentPhoneVerification(generation)) {
            return;
          }

          _phoneVerificationInProgress = false;

          verificationFailed(error);
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!_isCurrentPhoneVerification(generation)) {
            return;
          }

          final String cleanVerificationId = verificationId.trim();

          if (cleanVerificationId.isNotEmpty) {
            _lastVerificationId = cleanVerificationId;
          }

          _lastResendToken = resendToken;
          _phoneVerificationInProgress = false;

          codeSentWithToken?.call(cleanVerificationId, resendToken);

          codeSent(cleanVerificationId);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (!_isCurrentPhoneVerification(generation)) {
            return;
          }

          final String cleanVerificationId = verificationId.trim();

          if (cleanVerificationId.isNotEmpty) {
            _lastVerificationId = cleanVerificationId;
          }

          _phoneVerificationInProgress = false;

          codeAutoRetrievalTimeout?.call(cleanVerificationId);
        },
      );
    } on FirebaseAuthException {
      if (_isCurrentPhoneVerification(generation)) {
        _phoneVerificationInProgress = false;
      }

      rethrow;
    } catch (_) {
      if (_isCurrentPhoneVerification(generation)) {
        _phoneVerificationInProgress = false;
      }

      rethrow;
    }
  }

  // =============================================================
  // PHONE OTP RESEND
  // =============================================================

  Future<void> resendPhoneVerificationCode({
    required String phoneNumber,
    required void Function(String verificationId) codeSent,
    required void Function(FirebaseAuthException error) verificationFailed,
    void Function(PhoneAuthCredential credential)? verificationCompleted,
    void Function(String verificationId)? codeAutoRetrievalTimeout,
    void Function(String verificationId, int? resendToken)? codeSentWithToken,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final String normalizedPhone = _normalizePhoneNumber(phoneNumber);

    final bool samePhone = _pendingPhoneNumber == normalizedPhone;

    final int? token = samePhone ? _lastResendToken : null;

    await verifyPhoneNumber(
      phoneNumber: normalizedPhone,
      codeSent: codeSent,
      verificationFailed: verificationFailed,
      verificationCompleted: verificationCompleted,
      codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
      codeSentWithToken: codeSentWithToken,
      timeout: timeout,
      forceResendingToken: token,
    );
  }

  // =============================================================
  // PHONE CREDENTIAL
  // =============================================================

  PhoneAuthCredential createPhoneCredential({
    required String verificationId,
    required String smsCode,
  }) {
    final String cleanVerificationId = verificationId.trim();

    if (cleanVerificationId.isEmpty) {
      throw StateError('No active Phone verification session is available.');
    }

    final String cleanSmsCode = _normalizeOtp(smsCode);

    return PhoneAuthProvider.credential(
      verificationId: cleanVerificationId,
      smsCode: cleanSmsCode,
    );
  }

  PhoneAuthCredential createPendingPhoneCredential({required String smsCode}) {
    final String? verificationId = _lastVerificationId;

    if (verificationId == null || verificationId.trim().isEmpty) {
      throw StateError('No active Phone verification session is available.');
    }

    return createPhoneCredential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
  }

  // =============================================================
  // PHONE LOGIN
  // =============================================================

  Future<UserCredential> signInWithOtp({
    required String verificationId,
    required String smsCode,
  }) {
    return signInWithPhoneCredential(
      createPhoneCredential(verificationId: verificationId, smsCode: smsCode),
    );
  }

  Future<UserCredential> signInWithPendingOtp({required String smsCode}) {
    return signInWithPhoneCredential(
      createPendingPhoneCredential(smsCode: smsCode),
    );
  }

  Future<UserCredential> signInWithPhoneCredential(
    PhoneAuthCredential credential,
  ) {
    return _runCredentialOperation<UserCredential>(() async {
      final UserCredential result = await _auth.signInWithCredential(
        credential,
      );

      _clearPhoneVerificationState();

      return result;
    });
  }

  // =============================================================
  // EMAIL/PASSWORD SIGNUP
  // =============================================================

  Future<UserCredential> signUpWithEmailPassword({
    required String email,
    required String password,
  }) {
    final String normalizedEmail = _normalizeEmail(email);

    _validatePassword(password, enforceMinimumLength: true);

    return _runCredentialOperation<UserCredential>(
      () => _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      ),
    );
  }

  // =============================================================
  // EMAIL/PASSWORD LOGIN
  // =============================================================

  Future<UserCredential> signInWithEmailPassword({
    required String email,
    required String password,
  }) {
    final String normalizedEmail = _normalizeEmail(email);

    _validatePassword(password, enforceMinimumLength: false);

    return _runCredentialOperation<UserCredential>(
      () => _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      ),
    );
  }

  // =============================================================
  // EMAIL/PASSWORD LINK
  // =============================================================

  Future<UserCredential> linkEmailPasswordToCurrentUser({
    required String email,
    required String password,
  }) async {
    final String normalizedEmail = _normalizeEmail(email);

    _validatePassword(password, enforceMinimumLength: true);

    User user = _requireCurrentUser();

    try {
      await user.reload();
      user = _requireCurrentUser();
    } catch (_) {}

    if (_userHasProvider(user, 'password')) {
      throw StateError(
        'An Email/Password provider is already linked to this account.',
      );
    }

    final String? existingEmail = _cleanNullableString(user.email);

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

    return linkCredentialToCurrentUser(credential);
  }

  // =============================================================
  // PHONE LINK
  // =============================================================

  Future<UserCredential> linkPhoneCredentialToCurrentUser(
    PhoneAuthCredential credential,
  ) async {
    final UserCredential result = await linkCredentialToCurrentUser(credential);

    _clearPhoneVerificationState();

    return result;
  }

  Future<UserCredential> linkCredentialToCurrentUser(
    AuthCredential credential,
  ) {
    final User user = _requireCurrentUser();

    return _runCredentialOperation<UserCredential>(
      () => user.linkWithCredential(credential),
    );
  }

  // =============================================================
  // EMAIL OTP SEND
  // =============================================================

  Future<EmailOtpChallenge> sendEmailOtp({
    required String email,
    required String purpose,
  }) async {
    final User user = _requireCurrentUser();

    final String normalizedEmail = _normalizeEmail(email);

    final String currentUserEmail = _normalizeEmail(user.email ?? '');

    if (currentUserEmail != normalizedEmail) {
      throw StateError('Authenticated Email does not match the OTP Email.');
    }

    final String normalizedPurpose = _normalizeEmailOtpPurpose(purpose);

    final HttpsCallable callable = _functions.httpsCallable(
      sendEmailOtpFunction,
    );

    final HttpsCallableResult<dynamic> result = await callable.call<dynamic>(
      <String, dynamic>{'email': normalizedEmail, 'purpose': normalizedPurpose},
    );

    final Map<String, dynamic> data = _asStringMap(result.data);

    final String challengeId = _readRequiredString(
      data['challengeId'],
      fieldName: 'challengeId',
    );

    return EmailOtpChallenge(
      challengeId: challengeId,
      expiresInSeconds: _readPositiveInt(data['expiresIn'], fallback: 300),
      resendAfterSeconds: _readPositiveInt(data['resendAfter'], fallback: 60),
    );
  }

  Future<EmailOtpChallenge> sendEmailSignUpOtp({required String email}) {
    return sendEmailOtp(email: email, purpose: emailSignUpPurpose);
  }

  Future<EmailOtpChallenge> sendEmailLoginOtp({required String email}) {
    return sendEmailOtp(email: email, purpose: emailLoginPurpose);
  }

  Future<EmailOtpChallenge> sendEmailChangeOtp({required String email}) {
    return sendEmailOtp(email: email, purpose: emailChangePurpose);
  }

  // =============================================================
  // EMAIL OTP VERIFY
  // =============================================================

  Future<EmailOtpVerificationResult> verifyEmailOtp({
    required String challengeId,
    required String otp,
    required String purpose,
  }) async {
    _requireCurrentUser();

    final String normalizedChallengeId = _normalizeChallengeId(challengeId);

    final String normalizedOtp = _normalizeOtp(otp);

    final String normalizedPurpose = _normalizeEmailOtpPurpose(purpose);

    final HttpsCallable callable = _functions.httpsCallable(
      verifyEmailOtpFunction,
    );

    final HttpsCallableResult<dynamic> result = await callable
        .call<dynamic>(<String, dynamic>{
          'challengeId': normalizedChallengeId,
          'otp': normalizedOtp,
          'purpose': normalizedPurpose,
        });

    final Map<String, dynamic> data = _asStringMap(result.data);

    final bool verified = data['verified'] == true || data['success'] == true;

    if (!verified) {
      throw StateError(
        _readNullableString(data['message']) ??
            'Email OTP verification failed.',
      );
    }

    try {
      await reloadUser();
      await refreshIdToken();
    } catch (_) {}

    return EmailOtpVerificationResult(
      success: true,
      verified: true,
      challengeId:
          _readNullableString(data['challengeId']) ?? normalizedChallengeId,
      purpose: _readNullableString(data['purpose']) ?? normalizedPurpose,
      email: _readNullableString(data['email']),
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
  // PASSWORD RECOVERY
  // =============================================================

  Future<PasswordRecoveryChallenge> sendPasswordRecoveryOtp({
    required String email,
  }) async {
    final String normalizedEmail = _normalizeEmail(email);

    final HttpsCallable callable = _functions.httpsCallable(
      sendPasswordRecoveryOtpFunction,
    );

    final HttpsCallableResult<dynamic> result = await callable.call<dynamic>(
      <String, dynamic>{'email': normalizedEmail},
    );

    final Map<String, dynamic> data = _asStringMap(result.data);

    if (data['success'] != true) {
      throw StateError('Password recovery could not be started.');
    }

    return PasswordRecoveryChallenge(
      accepted: true,
      challengeId: _readNullableString(data['challengeId']),
      expiresInSeconds: _readPositiveInt(data['expiresIn'], fallback: 300),
      resendAfterSeconds: _readPositiveInt(data['resendAfter'], fallback: 60),
    );
  }

  Future<void> verifyPasswordRecoveryOtp({
    required String challengeId,
    required String otp,
    required String newPassword,
  }) async {
    final String normalizedChallengeId = _normalizeChallengeId(challengeId);

    final String normalizedOtp = _normalizeOtp(otp);

    _validatePassword(newPassword, enforceMinimumLength: true);

    final HttpsCallable callable = _functions.httpsCallable(
      verifyPasswordRecoveryOtpFunction,
    );

    final HttpsCallableResult<dynamic> result = await callable
        .call<dynamic>(<String, dynamic>{
          'challengeId': normalizedChallengeId,
          'otp': normalizedOtp,
          'newPassword': newPassword,
        });

    final Map<String, dynamic> data = _asStringMap(result.data);

    if (data['success'] != true || data['passwordReset'] != true) {
      throw StateError('Password recovery did not complete.');
    }

    if (currentUser != null) {
      await signOut();
    }
  }

  // =============================================================
  // STANDARD FIREBASE COMPATIBILITY METHODS
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
    } else {
      await user.sendEmailVerification(actionCodeSettings);
    }
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

  Future<void> requestEmailChange({
    required String newEmail,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    final User user = _requireCurrentUser();

    final String normalizedEmail = _normalizeEmail(newEmail);

    if (actionCodeSettings == null) {
      await user.verifyBeforeUpdateEmail(normalizedEmail);
    } else {
      await user.verifyBeforeUpdateEmail(normalizedEmail, actionCodeSettings);
    }
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

  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    final String normalizedEmail = _normalizeEmail(email);

    if (actionCodeSettings == null) {
      await _auth.sendPasswordResetEmail(email: normalizedEmail);
    } else {
      await _auth.sendPasswordResetEmail(
        email: normalizedEmail,
        actionCodeSettings: actionCodeSettings,
      );
    }
  }

  // =============================================================
  // PASSWORD UPDATE
  // =============================================================

  Future<void> updatePassword({required String newPassword}) async {
    final User user = _requireCurrentUser();

    _validatePassword(newPassword, enforceMinimumLength: true);

    await _runCredentialOperation<void>(() => user.updatePassword(newPassword));
  }

  Future<void> changePassword({required String newPassword}) {
    return updatePassword(newPassword: newPassword);
  }

  // =============================================================
  // PHONE UPDATE
  // =============================================================

  Future<void> updatePhoneNumber(PhoneAuthCredential credential) async {
    final User user = _requireCurrentUser();

    await _runCredentialOperation<void>(() async {
      await user.updatePhoneNumber(credential);
      await user.reload();
    });

    _clearPhoneVerificationState();
  }

  Future<void> changePhoneNumber(PhoneAuthCredential credential) {
    return updatePhoneNumber(credential);
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

  bool hasPhoneNumber() => currentPhoneNumber != null;

  bool hasEmailAddress() => currentEmail != null;

  bool hasProvider(String providerId) {
    final User? user = currentUser;

    if (user == null) {
      return false;
    }

    return _userHasProvider(user, providerId);
  }

  bool _userHasProvider(User user, String providerId) {
    final String normalized = providerId.trim();

    return user.providerData.any(
      (UserInfo provider) => provider.providerId.trim() == normalized,
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

    return List<String>.unmodifiable(ids);
  }

  List<UserInfo> get linkedProviders {
    final User? user = currentUser;

    if (user == null) {
      return const <UserInfo>[];
    }

    return List<UserInfo>.unmodifiable(user.providerData);
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

    return providers.isEmpty ? '' : providers.first;
  }

  // =============================================================
  // PROFILE METADATA
  // =============================================================

  Future<void> updateDisplayName(String name) async {
    final User user = _requireCurrentUser();

    await user.updateDisplayName(_cleanNullableString(name));

    await user.reload();
  }

  Future<void> updatePhotoUrl(String? photoUrl) async {
    final User user = _requireCurrentUser();

    await user.updatePhotoURL(_cleanNullableString(photoUrl));

    await user.reload();
  }

  // =============================================================
  // REAUTHENTICATION
  // =============================================================

  Future<UserCredential> reauthenticateWithPassword({
    required String email,
    required String password,
  }) {
    final User user = _requireCurrentUser();

    final AuthCredential credential = EmailAuthProvider.credential(
      email: _normalizeEmail(email),
      password: password,
    );

    return _runCredentialOperation<UserCredential>(
      () => user.reauthenticateWithCredential(credential),
    );
  }

  Future<UserCredential> reauthenticateWithPhoneCredential(
    PhoneAuthCredential credential,
  ) {
    return reauthenticateWithCredential(credential);
  }

  Future<UserCredential> reauthenticateWithCredential(
    AuthCredential credential,
  ) {
    final User user = _requireCurrentUser();

    return _runCredentialOperation<UserCredential>(
      () => user.reauthenticateWithCredential(credential),
    );
  }

  // =============================================================
  // TOKEN
  // =============================================================

  Future<String?> refreshIdToken() {
    final User user = _requireCurrentUser();

    return user.getIdToken(true);
  }

  // =============================================================
  // DELETE
  // =============================================================

  Future<void> deleteCurrentUser() async {
    final User user = _requireCurrentUser();

    await _runCredentialOperation<void>(() => user.delete());

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
  // PHONE STATE
  // =============================================================

  void clearPhoneVerificationState() {
    _clearPhoneVerificationState();
  }

  void _clearPhoneVerificationState() {
    _phoneVerificationGeneration++;

    _lastVerificationId = null;
    _lastResendToken = null;
    _pendingPhoneNumber = null;
    _phoneVerificationInProgress = false;
  }

  bool _isCurrentPhoneVerification(int generation) {
    return generation == _phoneVerificationGeneration;
  }

  // =============================================================
  // NORMALIZATION
  // =============================================================

  String _normalizeEmail(String email) {
    final String normalized = email.trim().toLowerCase();

    if (normalized.isEmpty ||
        normalized.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)) {
      throw ArgumentError.value(
        email,
        'email',
        'A valid Email address is required.',
      );
    }

    return normalized;
  }

  String _normalizeEmailOtpPurpose(String purpose) {
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

  String _normalizeChallengeId(String challengeId) {
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

  String _normalizePhoneNumber(String phoneNumber) {
    final String normalized = phoneNumber.trim().replaceAll(
      RegExp(r'[\s()\-.]'),
      '',
    );

    if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(normalized)) {
      throw ArgumentError.value(
        phoneNumber,
        'phoneNumber',
        'A valid international Phone Number is required.',
      );
    }

    return normalized;
  }

  String _normalizeOtp(String otp) {
    final String normalized = otp.trim().replaceAll(RegExp(r'\s+'), '');

    if (!RegExp(r'^[0-9]{6}$').hasMatch(normalized)) {
      throw ArgumentError.value(
        otp,
        'otp',
        'OTP must contain exactly 6 digits.',
      );
    }

    return normalized;
  }

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
      throw ArgumentError.value(password, 'password', 'Password is too long.');
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
  // RESPONSE HELPERS
  // =============================================================

  Map<String, dynamic> _asStringMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const <String, dynamic>{};
  }

  String _readRequiredString(Object? value, {required String fieldName}) {
    final String? result = _readNullableString(value);

    if (result == null) {
      throw StateError('JR CALL backend did not return a valid $fieldName.');
    }

    return result;
  }

  String? _readNullableString(Object? value) {
    if (value is! String) {
      return null;
    }

    final String normalized = value.trim();

    return normalized.isEmpty ? null : normalized;
  }

  int _readPositiveInt(Object? value, {required int fallback}) {
    if (value is int && value > 0) {
      return value;
    }

    if (value is num && value > 0) {
      return value.toInt();
    }

    return fallback;
  }

  String? _cleanNullableString(String? value) {
    if (value == null) {
      return null;
    }

    final String cleaned = value.trim();

    return cleaned.isEmpty ? null : cleaned;
  }

  // =============================================================
  // OPERATION GUARD
  // =============================================================

  Future<T> _runCredentialOperation<T>(Future<T> Function() operation) async {
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

  User _requireCurrentUser() {
    final User? user = currentUser;

    if (user == null || user.uid.trim().isEmpty) {
      throw StateError('No authenticated Firebase user is available.');
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

  Duration get expiresIn => Duration(seconds: expiresInSeconds);

  Duration get resendAfter => Duration(seconds: resendAfterSeconds);
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

  bool get hasChallenge =>
      challengeId != null && challengeId!.trim().isNotEmpty;

  Duration get expiresIn => Duration(seconds: expiresInSeconds);

  Duration get resendAfter => Duration(seconds: resendAfterSeconds);
}

// ===============================================================
// END OF FILE
// ===============================================================
