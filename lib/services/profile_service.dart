// ===============================================================
// JR CALL
// File: profile_service.dart
// Location: lib/services/profile_service.dart
// Master Repair: FILE 03/05
//
// PRODUCTION PROFILE COORDINATOR
// - Preserves existing Auth / Firestore / Storage ownership.
// - Firebase UID remains canonical private identity.
// - JR CALL ID remains separate public identity.
// - Profile + cover persistence supported.
// - Username / JR CALL ID uniqueness preserved.
// - Auth metadata sync preserved.
// - Existing valid phone/email are never erased merely because
//   Firebase Auth has no corresponding value.
// - New profiles remain discoverable by configured public
//   Name / Username / JR CALL ID / Email / Phone search.
// - Existing privacy choices are never overwritten during sync.
// - No Call Engine / WebRTC logic touched.
// - No password / OTP storage.
// ===============================================================

import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_model.dart';
import 'auth_service.dart';
import 'firebase/firestore_service.dart';
import 'firebase/storage_service.dart';

class ProfileService {
  ProfileService._();

  static final ProfileService instance = ProfileService._();

  final AuthService _authService = AuthService.instance;
  final FirestoreService _firestoreService = FirestoreService.instance;
  final StorageService _storageService = StorageService.instance;

  static const String _jrCallIdPrefix = 'jrcall_';
  static const String _jrCallIdAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const int _jrCallIdRandomLength = 8;
  static const int _maximumJrCallIdGenerationAttempts = 12;

  final Random _secureRandom = Random.secure();

  // =============================================================
  // COMPATIBILITY ACCESS
  // =============================================================

  AuthService get authService => _authService;

  FirestoreService get firestoreService => _firestoreService;

  StorageService get storageService => _storageService;

  User? get currentFirebaseUser => _authService.currentUser;

  String? get currentUserId {
    final String value = _authService.currentUserId?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  bool get hasAuthenticatedUser => currentUserId != null;

  // =============================================================
  // READ / STREAM
  // =============================================================

  Future<UserModel?> getProfile(String uid) {
    return _firestoreService.getUser(_normalizeRequiredUid(uid));
  }

  Future<UserModel?> getUser(String uid) => getProfile(uid);

  Future<UserModel?> getCurrentProfile() {
    final String? uid = currentUserId;

    return uid == null
        ? Future<UserModel?>.value(null)
        : _firestoreService.getUser(uid);
  }

  Stream<UserModel?> profileStream(String uid) {
    final String normalized = uid.trim();

    return normalized.isEmpty
        ? Stream<UserModel?>.value(null)
        : _firestoreService.watchUser(normalized);
  }

  Stream<UserModel?> watchProfile(String uid) => profileStream(uid);

  Stream<UserModel?> currentProfileStream() {
    final String? uid = currentUserId;

    return uid == null
        ? Stream<UserModel?>.value(null)
        : _firestoreService.watchUser(uid);
  }

  // =============================================================
  // ENSURE PROFILE
  // =============================================================

  Future<UserModel> ensureCurrentProfile({
    bool generateJrCallUserId = true,
  }) async {
    final User firebaseUser = _requireCurrentFirebaseUser();

    UserModel? profile = await _firestoreService.getUser(firebaseUser.uid);

    if (profile == null) {
      return createDefaultProfile(generateJrCallUserId: generateJrCallUserId);
    }

    // Synchronize only values Firebase Auth actually owns.
    //
    // IMPORTANT:
    // A missing Auth phone/email must NOT delete an existing
    // Firestore profile phone/email.
    await syncAuthenticationProfile();

    if (generateJrCallUserId && !profile.hasJrCallUserId) {
      await ensureCurrentUserJrCallId();

      profile = await _firestoreService.getUser(firebaseUser.uid);

      if (profile == null) {
        throw StateError(
          'JR CALL profile could not be read after ID generation.',
        );
      }
    }

    return profile;
  }

  // =============================================================
  // CREATE DEFAULT PROFILE
  // =============================================================

  Future<UserModel> createDefaultProfile({
    String? fullName,
    String? username,
    String? jrCallUserId,
    String? country,
    String? countryCode,
    DateTime? dateOfBirth,
    String? bio,
    bool generateJrCallUserId = true,
  }) async {
    final User firebaseUser = _requireCurrentFirebaseUser();

    final UserModel? existing = await _firestoreService.getUser(
      firebaseUser.uid,
    );

    if (existing != null) {
      return existing;
    }

    final String resolvedName =
        _cleanString(fullName) ?? _cleanString(firebaseUser.displayName) ?? '';

    final String resolvedPhone = _cleanString(firebaseUser.phoneNumber) ?? '';

    final String? resolvedEmail = _cleanString(firebaseUser.email);
    final String? resolvedPhoto = _cleanString(firebaseUser.photoURL);

    final List<String> providers = _authService.linkedProviderIds;

    final String? primaryProvider = _cleanString(
      _authService.primaryProviderId,
    );

    String? resolvedJrCallId = _cleanString(jrCallUserId);

    if (resolvedJrCallId == null && generateJrCallUserId) {
      resolvedJrCallId = await _generateAvailableJrCallId();
    }

    UserModel model = UserModel(
      uid: firebaseUser.uid,
      name: resolvedName,
      phone: resolvedPhone,
      email: resolvedEmail,
      username: _cleanString(username),
      userAddress: resolvedJrCallId,
      photoUrl: resolvedPhoto,
      bio: _cleanString(bio),
      country: _cleanString(country),
      countryCode: _cleanString(countryCode)?.toUpperCase(),
      dateOfBirth: dateOfBirth,
      verified: firebaseUser.emailVerified || resolvedPhone.isNotEmpty,
      emailVerified: firebaseUser.emailVerified,
      phoneVerified: resolvedPhone.isNotEmpty,
      provider: primaryProvider,
      signInProviders: providers,

      // ---------------------------------------------------------
      // DISCOVERY DEFAULTS
      //
      // Previous code explicitly wrote false for Email/Phone.
      // That prevented a correctly stored phone from being
      // returned by discovery.
      //
      // These values apply ONLY when creating a brand-new profile.
      // Existing privacy preferences are never overwritten here.
      // ---------------------------------------------------------

      isDiscoverable: true,
      isDiscoverableByEmail: true,
      isDiscoverableByPhone: true,

      createdAt: firebaseUser.metadata.creationTime ?? DateTime.now(),
      lastLogin: firebaseUser.metadata.lastSignInTime,
    );

    try {
      await _firestoreService.createUser(model);
    } on StateError {
      if (jrCallUserId != null || !generateJrCallUserId) {
        rethrow;
      }

      model = model.copyWith(
        userAddress: await _generateAvailableJrCallId(),
      );

      await _firestoreService.createUser(model);
    }

    await syncAuthenticationProfile();

    final UserModel? saved = await _firestoreService.getUser(firebaseUser.uid);

    if (saved == null) {
      throw StateError(
        'JR CALL profile was created but could not be read back.',
      );
    }

    return saved;
  }

  // =============================================================
  // GENERIC UPDATE
  // =============================================================

  Future<void> updateProfile({
    String? fullName,
    String? phoneNumber,
    String? email,
    String? username,
    String? jrCallUserId,
    String? profilePhotoUrl,
    String? coverPhotoUrl,
    String? bio,
    String? country,
    String? countryCode,
    String? gender,
    DateTime? dateOfBirth,
    String? provider,
    String? deviceToken,
  }) async {
    final String uid = _requireCurrentUid();

    await _firestoreService.updateProfile(
      uid: uid,
      name: fullName,
      phone: phoneNumber,
      email: email,
      username: username,
      userAddress: jrCallUserId,
      photoUrl: profilePhotoUrl,
      coverPhoto: coverPhotoUrl,
      bio: bio,
      country: country,
      countryCode: countryCode,
      gender: gender,
      dateOfBirth: dateOfBirth,
      provider: provider,
      deviceToken: deviceToken,
    );

    if (fullName != null) {
      await _syncFirebaseDisplayNameSafely(fullName);
    }

    if (profilePhotoUrl != null) {
      await _syncFirebasePhotoUrlSafely(profilePhotoUrl);
    }
  }

  // =============================================================
  // FULL NAME
  // =============================================================

  Future<void> updateFullName(String fullName) async {
    final String uid = _requireCurrentUid();

    await _firestoreService.updateFullName(
      uid: uid,
      fullName: fullName,
    );

    await _syncFirebaseDisplayNameSafely(fullName);
  }

  // =============================================================
  // USERNAME
  // =============================================================

  Future<bool> isUsernameAvailable(
      String username, {
        String? forUid,
      }) {
    return _firestoreService.isUsernameAvailable(
      username,
      forUid: forUid ?? currentUserId,
    );
  }

  Future<void> updateUsername(String username) {
    return _firestoreService.updateUsername(
      uid: _requireCurrentUid(),
      username: username,
    );
  }

  Future<void> clearUsername() {
    return _firestoreService.clearProfileField(
      uid: _requireCurrentUid(),
      field: UserProfileField.username,
    );
  }

  // =============================================================
  // JR CALL PUBLIC ID
  // =============================================================

  Future<bool> isJrCallUserIdAvailable(
      String jrCallUserId, {
        String? forUid,
      }) {
    return _firestoreService.isUserAddressAvailable(
      jrCallUserId,
      forUid: forUid ?? currentUserId,
    );
  }

  Future<bool> isUserAddressAvailable(
      String userAddress, {
        String? forUid,
      }) {
    return isJrCallUserIdAvailable(
      userAddress,
      forUid: forUid,
    );
  }

  Future<void> updateJrCallUserId(String jrCallUserId) {
    return _firestoreService.updateUserAddress(
      uid: _requireCurrentUid(),
      userAddress: jrCallUserId,
    );
  }

  Future<void> updateUserAddress(String userAddress) {
    return updateJrCallUserId(userAddress);
  }

  Future<String> ensureCurrentUserJrCallId() async {
    final String uid = _requireCurrentUid();

    final UserModel? profile = await _firestoreService.getUser(uid);

    final String? currentId = _cleanString(profile?.jrCallUserId);

    if (currentId != null) {
      return currentId;
    }

    for (
    int attempt = 0;
    attempt < _maximumJrCallIdGenerationAttempts;
    attempt++
    ) {
      final String candidate = _generateJrCallIdCandidate();

      try {
        await _firestoreService.updateUserAddress(
          uid: uid,
          userAddress: candidate,
        );

        return candidate;
      } on StateError {
        // Reservation collision: safely retry.
      }
    }

    throw StateError(
      'Unable to generate a unique JR CALL User ID.',
    );
  }

  Future<void> clearJrCallUserId() {
    return _firestoreService.clearProfileField(
      uid: _requireCurrentUid(),
      field: UserProfileField.userAddress,
    );
  }

  // =============================================================
  // COUNTRY
  // =============================================================

  Future<void> updateCountry({
    required String country,
    required String countryCode,
  }) {
    return _firestoreService.updateCountry(
      uid: _requireCurrentUid(),
      country: country,
      countryCode: countryCode,
    );
  }

  Future<void> clearCountry() async {
    final String uid = _requireCurrentUid();

    await _firestoreService.clearProfileField(
      uid: uid,
      field: UserProfileField.country,
    );

    await _firestoreService.clearProfileField(
      uid: uid,
      field: UserProfileField.countryCode,
    );
  }

  // =============================================================
  // BIO
  // =============================================================

  Future<void> updateBio(String bio) {
    return _firestoreService.updateBio(
      uid: _requireCurrentUid(),
      bio: bio,
    );
  }

  Future<void> clearBio() {
    return _firestoreService.clearProfileField(
      uid: _requireCurrentUid(),
      field: UserProfileField.bio,
    );
  }

  // =============================================================
  // DATE OF BIRTH
  // =============================================================

  Future<void> updateDateOfBirth(DateTime dateOfBirth) {
    return _firestoreService.updateDateOfBirth(
      uid: _requireCurrentUid(),
      dateOfBirth: dateOfBirth,
    );
  }

  Future<void> clearDateOfBirth() {
    return _firestoreService.clearProfileField(
      uid: _requireCurrentUid(),
      field: UserProfileField.dateOfBirth,
    );
  }

  // =============================================================
  // PROFILE PHOTO
  // =============================================================

  Future<String> uploadProfilePhoto({
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final String uid = _requireCurrentUid();

    final String downloadUrl = await _storageService.uploadProfilePhoto(
      uid: uid,
      bytes: bytes,
      contentType: contentType,
    );

    try {
      await _firestoreService.updateProfilePhotoUrl(
        uid: uid,
        photoUrl: downloadUrl,
      );

      await _syncFirebasePhotoUrlSafely(downloadUrl);

      return downloadUrl;
    } catch (_) {
      try {
        await _storageService.deleteProfilePhoto(uid: uid);
      } catch (_) {
        // Best-effort rollback only.
      }

      rethrow;
    }
  }

  Future<void> deleteProfilePhoto() async {
    final String uid = _requireCurrentUid();

    await _storageService.deleteProfilePhoto(uid: uid);

    await _firestoreService.clearProfileField(
      uid: uid,
      field: UserProfileField.photoUrl,
    );

    await _syncFirebasePhotoUrlSafely(null);
  }

  // =============================================================
  // COVER PHOTO
  // =============================================================

  Future<String> uploadCoverPhoto({
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final String uid = _requireCurrentUid();

    final String downloadUrl = await _storageService.uploadCoverPhoto(
      uid: uid,
      bytes: bytes,
      contentType: contentType,
    );

    try {
      await _firestoreService.updateCoverPhotoUrl(
        uid: uid,
        coverPhotoUrl: downloadUrl,
      );

      return downloadUrl;
    } catch (_) {
      try {
        await _storageService.deleteCoverPhoto(uid: uid);
      } catch (_) {
        // Best-effort rollback only.
      }

      rethrow;
    }
  }

  Future<void> deleteCoverPhoto() async {
    final String uid = _requireCurrentUid();

    await _storageService.deleteCoverPhoto(uid: uid);

    await _firestoreService.clearProfileField(
      uid: uid,
      field: UserProfileField.coverPhoto,
    );
  }

  // =============================================================
  // AUTH METADATA SYNC — CRITICAL REPAIR
  // =============================================================

  Future<void> syncAuthenticationProfile() async {
    final User originalUser = _requireCurrentFirebaseUser();

    try {
      await originalUser.reload();
    } catch (_) {
      // Existing authenticated snapshot remains usable.
    }

    final User user = _authService.currentUser ?? originalUser;

    final String? email = _cleanString(user.email);
    final String? phone = _cleanString(user.phoneNumber);

    final List<String> providers = user.providerData
        .map(
          (UserInfo provider) => provider.providerId.trim(),
    )
        .where(
          (String id) => id.isNotEmpty,
    )
        .toSet()
        .toList(growable: false);

    // ---------------------------------------------------------
    // IMPORTANT:
    //
    // OLD BEHAVIOUR:
    //
    // email: email ?? '',
    // phoneNumber: phone ?? '',
    //
    // That converted "Firebase Auth has no value" into an
    // explicit empty-string update.
    //
    // FirestoreService correctly interprets an explicit empty
    // phone/email as "clear this field", so a perfectly valid
    // profile phone saved previously could be erased.
    //
    // NEW BEHAVIOUR:
    //
    // null = Auth has no value to synchronize.
    // non-null = Auth owns a real value and may synchronize it.
    //
    // Therefore existing profile phone/email remain untouched
    // when Firebase Auth has no corresponding value.
    // ---------------------------------------------------------

    await _firestoreService.syncAuthenticationProfile(
      uid: user.uid,
      email: email,
      phoneNumber: phone,
      emailVerified: user.emailVerified,
      phoneVerified: phone != null,
      signInProviders: providers,
    );
  }

  Future<void> syncAuthState() {
    return syncAuthenticationProfile();
  }

  // =============================================================
  // DISCOVERABILITY / PRIVACY
  // =============================================================

  Future<void> updateDiscoverability({
    bool? isDiscoverable,
    bool? isDiscoverableByEmail,
    bool? isDiscoverableByPhone,
  }) {
    return _firestoreService.updateDiscoverability(
      uid: _requireCurrentUid(),
      isDiscoverable: isDiscoverable,
      isDiscoverableByEmail: isDiscoverableByEmail,
      isDiscoverableByPhone: isDiscoverableByPhone,
    );
  }

  // =============================================================
  // CLEAR FIELD
  // =============================================================

  Future<void> clearProfileField(UserProfileField field) async {
    final String uid = _requireCurrentUid();

    if (field == UserProfileField.photoUrl) {
      await deleteProfilePhoto();
      return;
    }

    if (field == UserProfileField.coverPhoto) {
      await deleteCoverPhoto();
      return;
    }

    await _firestoreService.clearProfileField(
      uid: uid,
      field: field,
    );

    if (field == UserProfileField.name) {
      await _syncFirebaseDisplayNameSafely('');
    }
  }

  // =============================================================
  // MEDIA URL HELPERS
  // =============================================================

  Future<String?> getProfilePhotoUrl() {
    return _storageService.getProfilePhotoUrl(
      _requireCurrentUid(),
    );
  }

  Future<String?> getCoverPhotoUrl() {
    return _storageService.getCoverPhotoUrl(
      _requireCurrentUid(),
    );
  }

  // =============================================================
  // PROFILE DATA DELETE
  // =============================================================

  Future<void> deleteCurrentUserProfileData() async {
    final String uid = _requireCurrentUid();

    Object? mediaError;
    StackTrace? mediaStackTrace;

    try {
      await _storageService.deleteUserProfileMedia(uid: uid);
    } catch (error, stackTrace) {
      mediaError = error;
      mediaStackTrace = stackTrace;
    }

    await _firestoreService.deleteUserProfile(uid);

    if (mediaError != null) {
      Error.throwWithStackTrace(
        mediaError,
        mediaStackTrace ?? StackTrace.current,
      );
    }
  }

  Future<void> deleteProfileData() {
    return deleteCurrentUserProfileData();
  }

  Future<void> deleteCurrentAccount() async {
    _requireCurrentUid();

    await deleteCurrentUserProfileData();

    await _authService.deleteCurrentUser();
  }

  // =============================================================
  // JR CALL ID GENERATION
  // =============================================================

  Future<String> _generateAvailableJrCallId() async {
    final String uid = _requireCurrentUid();

    for (
    int attempt = 0;
    attempt < _maximumJrCallIdGenerationAttempts;
    attempt++
    ) {
      final String candidate = _generateJrCallIdCandidate();

      final bool available = await _firestoreService.isUserAddressAvailable(
        candidate,
        forUid: uid,
      );

      if (available) {
        return candidate;
      }
    }

    throw StateError(
      'Unable to generate an available JR CALL User ID.',
    );
  }

  String _generateJrCallIdCandidate() {
    final StringBuffer buffer = StringBuffer(_jrCallIdPrefix);

    for (
    int index = 0;
    index < _jrCallIdRandomLength;
    index++
    ) {
      buffer.write(
        _jrCallIdAlphabet[
        _secureRandom.nextInt(_jrCallIdAlphabet.length)],
      );
    }

    return buffer.toString().toLowerCase();
  }

  // =============================================================
  // FIREBASE AUTH DISPLAY METADATA
  // =============================================================

  Future<void> _syncFirebaseDisplayNameSafely(String value) async {
    try {
      await _authService.updateDisplayName(value);
    } on FirebaseAuthException {
      // Firestore remains canonical profile storage.
    }
  }

  Future<void> _syncFirebasePhotoUrlSafely(String? value) async {
    try {
      await _authService.updatePhotoUrl(value);
    } on FirebaseAuthException {
      // Firestore/Storage remain canonical media storage.
    }
  }

  // =============================================================
  // GUARDS
  // =============================================================

  User _requireCurrentFirebaseUser() {
    final User? user = _authService.currentUser;

    if (user == null) {
      throw StateError(
        'An authenticated Firebase user is required for profile operations.',
      );
    }

    if (user.uid.trim().isEmpty) {
      throw StateError(
        'Authenticated Firebase user has an invalid UID.',
      );
    }

    return user;
  }

  String _requireCurrentUid() {
    return _requireCurrentFirebaseUser().uid.trim();
  }

  String _normalizeRequiredUid(String uid) {
    final String normalized = uid.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(
        uid,
        'uid',
        'Firebase UID cannot be empty.',
      );
    }

    return normalized;
  }

  // =============================================================
  // STRING
  // =============================================================

  String? _cleanString(String? value) {
    final String normalized = value?.trim() ?? '';

    return normalized.isEmpty ? null : normalized;
  }
}

// ===============================================================
// END OF FILE
//
// FILE 03/05
//
// FIXED:
// - Existing saved phone will no longer be erased merely because
//   Firebase Auth phoneNumber is null.
// - Existing saved email receives the same protection.
// - New profiles are discoverable through Email/Phone by default.
// - Existing user's chosen discoverability settings are preserved.
// - Name / Username / JR CALL ID logic unchanged.
// - Profile photo / cover / country / bio / DOB unchanged.
// - Firebase UID ownership unchanged.
// - No Call Engine / WebRTC code touched.
//
// SAVE THIS FILE.
//
// REMAINING MAIN FILES: 2
//
// NEXT FILE: contacts_screen.dart
// Location: lib/screens/contacts_screen.dart
// ===============================================================