import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../services/auth_service.dart';

/// ===============================================================
/// JR CALL
/// File: create_account_otp_manager.dart
/// Location: lib/screens/create_account_otp_manager.dart
///
/// OTP / AUTH MASTER FILE 03 / 09
///
/// PRODUCTION CREATE-ACCOUNT PHONE OTP COORDINATOR
///
/// ===============================================================
///
/// JR CALL SIGNUP CONTRACT:
///
/// Phone Number
///      ↓
/// REQUIRED
///      ↓
/// Firebase Phone Authentication
///      ↓
/// SMS OTP / automatic verification
///      ↓
/// Firebase authenticated Phone UID
///      ↓
/// CreateAccountScreen finalizes JR CALL profile
///
/// ===============================================================
///
/// OWNERSHIP:
///
/// ✓ Phone signup OTP request coordination.
/// ✓ Firebase Phone verification orchestration.
/// ✓ Native automatic Phone verification.
/// ✓ Manual OTP-session delivery.
/// ✓ Native/Web codeSent compatibility through AuthService.
/// ✓ Automatic/manual race protection.
/// ✓ Stale callback rejection.
/// ✓ Duplicate request protection.
/// ✓ OTP route ownership.
/// ✓ Pending automatic credential ownership.
/// ✓ Same-session callback safety.
/// ✓ Verification reset/disposal.
///
/// ===============================================================
///
/// ACCOUNT RULES:
///
/// ✓ Phone Number is mandatory for account creation.
/// ✓ Phone ownership must be verified by Firebase.
/// ✓ Phone OTP cannot be bypassed by Password.
/// ✓ Email is optional.
/// ✓ Password is required only when optional Email is supplied.
/// ✓ Email/Password linking is NOT owned here.
/// ✓ Firebase UID remains canonical.
/// ✓ No fake/local OTP.
/// ✓ No OTP persistence.
/// ✓ No Password persistence.
/// ✓ No phoneAccountExists() pre-verification blocker.
/// ✓ No Play Integrity bypass.
/// ✓ No reCAPTCHA bypass.
/// ✓ No Firebase App Verification bypass.
///
/// ===============================================================
///
/// PLATFORM CONTRACT:
///
/// Android / iOS:
///
/// AuthService.verifyPhoneNumber()
///      ├── verificationCompleted
///      │      → PhoneAuthCredential
///      │      → automatic signup path
///      │
///      └── codeSent
///             → verificationId
///             → OtpScreen
///
/// Web:
///
/// AuthService.verifyPhoneNumber()
///      ↓
/// Firebase Web Phone Authentication
///      ↓
/// codeSent
///      ↓
/// OtpScreen
///      ↓
/// AuthService.signInWithOtp()
///
/// Web does not require PhoneAuthCredential to pass through this
/// manager's automatic path.
///
/// ===============================================================
///
/// DOES NOT OWN:
///
/// ✓ Widget/UI.
/// ✓ Firestore profile creation.
/// ✓ Email/Password linking.
/// ✓ Email OTP.
/// ✓ Media upload.
/// ✓ Final navigation.
/// ✓ Call Engine.
/// ✓ Message Engine.
/// ✓ WebRTC.
/// ✓ Signaling.
///
/// ===============================================================

class CreateAccountOtpManager {
  CreateAccountOtpManager({
    AuthService? authService,
  }) : _authService = authService ?? AuthService.instance;

  // =============================================================
  // DEPENDENCY
  // =============================================================

  final AuthService _authService;

  // =============================================================
  // OPERATION STATE
  // =============================================================

  int _generation = 0;

  bool _disposed = false;

  bool _verificationRunning = false;

  bool _otpRouteOpen = false;

  bool _automaticCredentialDispatched = false;

  bool _closingOtpRoute = false;

  String? _activePhoneNumber;

  String? _activeVerificationId;

  PhoneAuthCredential? _pendingAutomaticCredential;

  // =============================================================
  // PUBLIC STATE
  // =============================================================

  bool get isVerificationRunning {
    return _verificationRunning;
  }

  bool get isOtpRouteOpen {
    return _otpRouteOpen;
  }

  bool get hasPendingAutomaticCredential {
    return _pendingAutomaticCredential != null;
  }

  bool get isAutomaticCredentialDispatched {
    return _automaticCredentialDispatched;
  }

  bool get isClosingOtpRoute {
    return _closingOtpRoute;
  }

  bool get isDisposed {
    return _disposed;
  }

  bool get isBusy {
    return _verificationRunning ||
        _automaticCredentialDispatched ||
        _closingOtpRoute;
  }

  int get generation {
    return _generation;
  }

  String? get activePhoneNumber {
    return _activePhoneNumber;
  }

  String? get activeVerificationId {
    return _activeVerificationId;
  }

  bool get hasActiveVerification {
    return _cleanNullable(
      _activePhoneNumber,
    ) !=
        null &&
        _cleanNullable(
          _activeVerificationId,
        ) !=
            null;
  }

  // =============================================================
  // START PHONE SIGNUP VERIFICATION
  // =============================================================

  Future<void> startVerification({
    required String phoneNumber,
    required FutureOr<void> Function(
        String verificationId,
        ) onCodeSent,
    required FutureOr<void> Function(
        PhoneAuthCredential credential,
        ) onAutomaticCredential,
    required FutureOr<void> Function(
        FirebaseAuthException error,
        ) onVerificationFailed,
    required FutureOr<void> Function() onCloseOtpRoute,
    FutureOr<void> Function(
        String verificationId,
        )? onAutoRetrievalTimeout,
  }) async {
    _ensureUsable();

    final String normalizedPhone = _normalizePhone(
      phoneNumber,
    );

    if (_verificationRunning ||
        _automaticCredentialDispatched ||
        _closingOtpRoute) {
      await _safeDispatchVerificationFailure(
        error: FirebaseAuthException(
          code: 'verification-in-progress',
          message: 'Phone verification is already in progress.',
        ),
        generation: _generation,
        callback: onVerificationFailed,
      );

      return;
    }

    final int operationGeneration = ++_generation;

    _verificationRunning = true;
    _otpRouteOpen = false;
    _automaticCredentialDispatched = false;
    _closingOtpRoute = false;

    _activePhoneNumber = normalizedPhone;
    _activeVerificationId = null;

    _pendingAutomaticCredential = null;

    try {
      await _authService.verifyPhoneNumber(
        phoneNumber: normalizedPhone,

        // -------------------------------------------------------
        // NATIVE AUTOMATIC FIREBASE VERIFICATION
        // -------------------------------------------------------

        verificationCompleted: (
            PhoneAuthCredential credential,
            ) {
          if (!_isCurrent(operationGeneration)) {
            return;
          }

          _verificationRunning = false;

          unawaited(
            _handleAutomaticCredential(
              credential: credential,
              generation: operationGeneration,
              onAutomaticCredential: onAutomaticCredential,
              onCloseOtpRoute: onCloseOtpRoute,
              onVerificationFailed: onVerificationFailed,
            ),
          );
        },

        // -------------------------------------------------------
        // VERIFICATION FAILURE
        // -------------------------------------------------------

        verificationFailed: (
            FirebaseAuthException error,
            ) {
          if (!_isCurrent(operationGeneration)) {
            return;
          }

          _verificationRunning = false;

          unawaited(
            _safeDispatchVerificationFailure(
              error: error,
              generation: operationGeneration,
              callback: onVerificationFailed,
            ),
          );
        },

        // -------------------------------------------------------
        // MANUAL OTP SESSION
        //
        // Native:
        // Firebase verificationId.
        //
        // Web:
        // AuthService Web verification session ID.
        // -------------------------------------------------------

        codeSent: (
            String verificationId,
            ) {
          if (!_isCurrent(operationGeneration)) {
            return;
          }

          final String normalizedVerificationId =
          verificationId.trim();

          _verificationRunning = false;

          if (normalizedVerificationId.isEmpty) {
            _activeVerificationId = null;

            unawaited(
              _safeDispatchVerificationFailure(
                error: FirebaseAuthException(
                  code: 'invalid-verification-id',
                  message:
                  'Firebase did not provide a valid verification session.',
                ),
                generation: operationGeneration,
                callback: onVerificationFailed,
              ),
            );

            return;
          }

          _activeVerificationId =
              normalizedVerificationId;

          // Automatic verification may win before codeSent reaches
          // CreateAccountScreen. In that case manual OTP navigation
          // must not also start.
          if (_automaticCredentialDispatched ||
              _pendingAutomaticCredential != null) {
            return;
          }

          unawaited(
            _safeDispatchCodeSent(
              verificationId: normalizedVerificationId,
              generation: operationGeneration,
              callback: onCodeSent,
              onVerificationFailed: onVerificationFailed,
            ),
          );
        },

        // -------------------------------------------------------
        // AUTO-RETRIEVAL TIMEOUT
        //
        // IMPORTANT:
        //
        // The manual verification session remains valid.
        // -------------------------------------------------------

        codeAutoRetrievalTimeout: (
            String verificationId,
            ) {
          if (!_isCurrent(operationGeneration)) {
            return;
          }

          _verificationRunning = false;

          final String normalizedVerificationId =
          verificationId.trim();

          if (normalizedVerificationId.isNotEmpty) {
            _activeVerificationId =
                normalizedVerificationId;
          }

          if (onAutoRetrievalTimeout == null) {
            return;
          }

          unawaited(
            _safeDispatchAutoRetrievalTimeout(
              verificationId: normalizedVerificationId,
              generation: operationGeneration,
              callback: onAutoRetrievalTimeout,
              onVerificationFailed: onVerificationFailed,
            ),
          );
        },
      );
    } on FirebaseAuthException catch (error) {
      if (!_isCurrent(operationGeneration)) {
        return;
      }

      _verificationRunning = false;

      await _safeDispatchVerificationFailure(
        error: error,
        generation: operationGeneration,
        callback: onVerificationFailed,
      );
    } on ArgumentError {
      if (_isCurrent(operationGeneration)) {
        _verificationRunning = false;
      }

      rethrow;
    } on StateError catch (error) {
      if (!_isCurrent(operationGeneration)) {
        return;
      }

      _verificationRunning = false;

      await _safeDispatchVerificationFailure(
        error: FirebaseAuthException(
          code: 'phone-verification-state-error',
          message: error.message,
        ),
        generation: operationGeneration,
        callback: onVerificationFailed,
      );
    } catch (error) {
      if (!_isCurrent(operationGeneration)) {
        return;
      }

      _verificationRunning = false;

      await _safeDispatchVerificationFailure(
        error: _convertToFirebaseAuthException(
          error,
        ),
        generation: operationGeneration,
        callback: onVerificationFailed,
      );
    }
  }

  // =============================================================
  // CODE SENT DISPATCH
  // =============================================================

  Future<void> _safeDispatchCodeSent({
    required String verificationId,
    required int generation,
    required FutureOr<void> Function(
        String verificationId,
        ) callback,
    required FutureOr<void> Function(
        FirebaseAuthException error,
        ) onVerificationFailed,
  }) async {
    if (!_isCurrent(generation) ||
        _automaticCredentialDispatched ||
        _pendingAutomaticCredential != null) {
      return;
    }

    try {
      await callback(
        verificationId,
      );
    } catch (error) {
      if (!_isCurrent(generation)) {
        return;
      }

      await _safeDispatchVerificationFailure(
        error: _convertToFirebaseAuthException(
          error,
        ),
        generation: generation,
        callback: onVerificationFailed,
      );
    }
  }

  // =============================================================
  // FAILURE DISPATCH
  // =============================================================

  Future<void> _safeDispatchVerificationFailure({
    required FirebaseAuthException error,
    required int generation,
    required FutureOr<void> Function(
        FirebaseAuthException error,
        ) callback,
  }) async {
    if (!_isCurrent(generation)) {
      return;
    }

    try {
      await callback(
        error,
      );
    } catch (_) {
      // UI callback failure must not create an unhandled Future.
    }
  }

  // =============================================================
  // AUTO-RETRIEVAL TIMEOUT DISPATCH
  // =============================================================

  Future<void> _safeDispatchAutoRetrievalTimeout({
    required String verificationId,
    required int generation,
    required FutureOr<void> Function(
        String verificationId,
        ) callback,
    required FutureOr<void> Function(
        FirebaseAuthException error,
        ) onVerificationFailed,
  }) async {
    if (!_isCurrent(generation)) {
      return;
    }

    try {
      await callback(
        verificationId,
      );
    } catch (error) {
      if (!_isCurrent(generation)) {
        return;
      }

      await _safeDispatchVerificationFailure(
        error: _convertToFirebaseAuthException(
          error,
        ),
        generation: generation,
        callback: onVerificationFailed,
      );
    }
  }

  // =============================================================
  // AUTOMATIC PHONE CREDENTIAL
  // =============================================================

  Future<void> _handleAutomaticCredential({
    required PhoneAuthCredential credential,
    required int generation,
    required FutureOr<void> Function(
        PhoneAuthCredential credential,
        ) onAutomaticCredential,
    required FutureOr<void> Function() onCloseOtpRoute,
    required FutureOr<void> Function(
        FirebaseAuthException error,
        ) onVerificationFailed,
  }) async {
    if (!_isCurrent(generation)) {
      return;
    }

    // -----------------------------------------------------------
    // MANUAL OTP SCREEN IS ALREADY OPEN
    //
    // Firebase automatic verification arrived after codeSent.
    //
    // Preserve credential.
    // Ask CreateAccountScreen to close OTP route.
    // CreateAccountScreen then consumes credential through
    // takePendingAutomaticCredential().
    // -----------------------------------------------------------

    if (_otpRouteOpen) {
      _pendingAutomaticCredential ??=
          credential;

      if (_closingOtpRoute) {
        return;
      }

      _closingOtpRoute = true;

      try {
        await onCloseOtpRoute();
      } catch (error) {
        if (!_isCurrent(generation)) {
          return;
        }

        await _safeDispatchVerificationFailure(
          error: _convertToFirebaseAuthException(
            error,
          ),
          generation: generation,
          callback: onVerificationFailed,
        );
      } finally {
        if (_isCurrent(generation)) {
          _closingOtpRoute = false;
        }
      }

      return;
    }

    // -----------------------------------------------------------
    // AUTOMATIC PATH WINS
    // -----------------------------------------------------------

    if (_automaticCredentialDispatched) {
      return;
    }

    _automaticCredentialDispatched = true;

    try {
      await onAutomaticCredential(
        credential,
      );
    } catch (error) {
      if (!_isCurrent(generation)) {
        return;
      }

      _automaticCredentialDispatched = false;

      await _safeDispatchVerificationFailure(
        error: _convertToFirebaseAuthException(
          error,
        ),
        generation: generation,
        callback: onVerificationFailed,
      );
    }
  }

  // =============================================================
  // OTP ROUTE OPENING
  // =============================================================

  void markOtpRouteOpening() {
    _ensureUsable();

    if (_automaticCredentialDispatched) {
      return;
    }

    _otpRouteOpen = true;
  }

  // =============================================================
  // OTP ROUTE CLOSED
  // =============================================================

  void markOtpRouteClosed() {
    if (_disposed) {
      return;
    }

    _otpRouteOpen = false;
    _closingOtpRoute = false;
  }

  // =============================================================
  // PENDING AUTOMATIC CREDENTIAL
  //
  // Used when Firebase automatic verification completes while the
  // manual OTP screen is already visible.
  // =============================================================

  PhoneAuthCredential? takePendingAutomaticCredential() {
    if (_disposed) {
      return null;
    }

    final PhoneAuthCredential? credential =
        _pendingAutomaticCredential;

    _pendingAutomaticCredential = null;

    if (credential != null) {
      _automaticCredentialDispatched = true;
    }

    return credential;
  }

  // =============================================================
  // AUTOMATIC COMPLETION FINISHED
  // =============================================================

  void automaticCompletionFinished() {
    if (_disposed) {
      return;
    }

    _automaticCredentialDispatched = false;
    _closingOtpRoute = false;
  }

  // =============================================================
  // RESET CURRENT SIGNUP OTP SESSION
  // =============================================================

  void reset() {
    if (_disposed) {
      return;
    }

    ++_generation;

    _verificationRunning = false;
    _otpRouteOpen = false;
    _automaticCredentialDispatched = false;
    _closingOtpRoute = false;

    _activePhoneNumber = null;
    _activeVerificationId = null;

    _pendingAutomaticCredential = null;

    _authService.clearPhoneVerificationState();
  }

  // =============================================================
  // DISPOSE
  // =============================================================

  void dispose() {
    if (_disposed) {
      return;
    }

    ++_generation;

    _disposed = true;

    _verificationRunning = false;
    _otpRouteOpen = false;
    _automaticCredentialDispatched = false;
    _closingOtpRoute = false;

    _activePhoneNumber = null;
    _activeVerificationId = null;

    _pendingAutomaticCredential = null;

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

  bool _isCurrent(
      int generation,
      ) {
    return !_disposed &&
        generation == _generation;
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
        code: 'phone-verification-state-error',
        message: error.message,
      );
    }

    if (error is ArgumentError) {
      return FirebaseAuthException(
        code: 'phone-verification-invalid-argument',
        message:
        error.message?.toString() ??
            'Phone verification information is invalid.',
      );
    }

    return FirebaseAuthException(
      code: 'phone-verification-failed',
      message:
      'Phone verification could not be completed. Please try again.',
    );
  }

  // =============================================================
  // USABILITY GUARD
  // =============================================================

  void _ensureUsable() {
    if (_disposed) {
      throw StateError(
        'CreateAccountOtpManager has already been disposed.',
      );
    }
  }
}

// ===============================================================
// END OF FILE
//
// OTP / AUTH MASTER FILE 03 / 09
//
// FINAL RESPONSIBILITY:
//
// CreateAccountScreen
//      ↓
// CreateAccountOtpManager
//      ↓
// AuthService
//      ↓
// Firebase Authentication
//      ↓
// Verified Phone Firebase UID
//
// ===============================================================
//
// GUARANTEES:
//
// ✓ Phone Number remains mandatory.
// ✓ Account creation always starts with Firebase Phone Auth.
// ✓ Phone OTP cannot be bypassed with Password.
// ✓ Native automatic Phone verification supported.
// ✓ Native manual 6-digit OTP supported.
// ✓ Web manual Firebase Phone OTP path remains supported.
// ✓ AuthService owns platform-specific Firebase implementation.
// ✓ Same verification session cannot execute duplicate paths.
// ✓ Automatic/manual verification race protected.
// ✓ Automatic credential preserved while OTP route is open.
// ✓ OTP route can be safely closed after automatic verification.
// ✓ Stale Firebase callbacks rejected.
// ✓ Reset invalidates previous callbacks.
// ✓ Dispose invalidates previous callbacks.
// ✓ Invalid E.164 Phone Number rejected.
// ✓ No account-exists pre-verification blocker.
// ✓ No fake/local OTP.
// ✓ No OTP persistence.
// ✓ No Password persistence.
// ✓ No Play Integrity bypass.
// ✓ No reCAPTCHA bypass.
// ✓ No Firebase App Verification bypass.
//
// ===============================================================
//
// NOT OWNED HERE:
//
// ✓ Firestore account/profile creation.
// ✓ Email/Password linking.
// ✓ Email OTP.
// ✓ Password recovery.
// ✓ Profile photo.
// ✓ Cover photo.
// ✓ Navigation.
// ✓ Call Engine.
// ✓ Message Engine.
// ✓ WebRTC.
// ✓ Signaling.
//
// ===============================================================
//
// SAVE / REPLACE:
//
// lib/screens/create_account_otp_manager.dart
//
// NEXT OTP FILE:
//
// lib/screens/login_screen.dart
//
// ===============================================================