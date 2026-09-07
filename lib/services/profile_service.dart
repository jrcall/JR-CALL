// ===============================================================
// JR CALL
// File: profile_service.dart
// Location: lib/services/profile_service.dart
//
// OTP / AUTH MASTER PROFILE COORDINATOR
//
// MASTER CONTRACT:
//
// Firebase Authentication
//      ↓
// verified Firebase UID
//      ↓
// ProfileService
//      ↓
// FirestoreService
//      ↓
// EXISTING users/{uid}
//
// IMPORTANT:
//
// - Authentication metadata NEVER creates a missing profile.
// - Explicit profile creation belongs to createDefaultProfile().
// - Missing Login profile remains Profile Setup state.
// - Firebase UID remains canonical private identity.
// - JR CALL ID remains separate public/search identity.
// - Existing profile phone/email are never erased merely because
//   Firebase Authentication currently has no corresponding value.
// - No password / OTP persistence.
// - Call Engine / Message Engine / WebRTC untouched.
// ===============================================================

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../models/user_model.dart';
import 'auth_service.dart';
import 'firebase/firestore_service.dart';
import 'firebase/storage_service.dart';

class ProfileService {
  ProfileService._();

  static final ProfileService instance = ProfileService._();

  // =============================================================
  // SERVICES
  // =============================================================

  final AuthService _authService = AuthService.instance;
  final FirestoreService _firestoreService = FirestoreService.instance;
  final StorageService _storageService = StorageService.instance;
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  // =============================================================
  // JR CALL ID CONFIGURATION
  // =============================================================

  static const String _jrCallIdPrefix = 'jrcall_';

  static const String _jrCallIdAlphabet =
      'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static const int _jrCallIdRandomLength = 8;
  static const int _maximumJrCallIdGenerationAttempts = 12;

  final Random _secureRandom = Random.secure();

  // =============================================================
  // FCM TOKEN STATE
  // =============================================================

  StreamSubscription<String>? _fcmTokenSubscription;

  String? _lastSavedFcmToken;
  String? _tokenSyncUid;

  bool _startingTokenSync = false;

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

  bool get isDeviceTokenSyncActive => _fcmTokenSubscription != null;

  // =============================================================
  // READ / STREAM
  // =============================================================

  Future<UserModel?> getProfile(String uid) {
    return _firestoreService.getUser(
      _normalizeRequiredUid(uid),
    );
  }

  Future<UserModel?> getUser(String uid) {
    return getProfile(uid);
  }

  Future<UserModel?> getCurrentProfile() {
    final String? uid = currentUserId;

    if (uid == null) {
      return Future<UserModel?>.value(null);
    }

    return _firestoreService.getUser(uid);
  }

  Stream<UserModel?> profileStream(String uid) {
    final String normalized = uid.trim();

    if (normalized.isEmpty) {
      return Stream<UserModel?>.value(null);
    }

    return _firestoreService.watchUser(normalized);
  }

  Stream<UserModel?> watchProfile(String uid) {
    return profileStream(uid);
  }

  Stream<UserModel?> currentProfileStream() {
    final String? uid = currentUserId;

    if (uid == null) {
      return Stream<UserModel?>.value(null);
    }

    return _firestoreService.watchUser(uid);
  }

  // =============================================================
  // DISCOVERY
  // =============================================================

  Future<List<UserModel>> searchProfiles(
      String query, {
        int limit = 20,
        bool excludeCurrentUser = true,
      }) {
    final String normalized = query.trim();

    if (normalized.isEmpty) {
      return Future<List<UserModel>>.value(
        const <UserModel>[],
      );
    }

    return _firestoreService.searchUsers(
      normalized,
      limit: limit,
      excludeUid: excludeCurrentUser ? currentUserId : null,
    );
  }

  // =============================================================
  // PHONE DISCOVERY
  // =============================================================

  Future<List<UserModel>> searchProfilesByPhone(
      String phoneNumber, {
        int limit = 20,
        bool excludeCurrentUser = true,
      }) {
    final String normalized = phoneNumber.trim();

    if (normalized.isEmpty) {
      return Future<List<UserModel>>.value(
        const <UserModel>[],
      );
    }

    return _firestoreService.getUsersByPhone(
      normalized,
      limit: limit,
      excludeUid: excludeCurrentUser ? currentUserId : null,
    );
  }

  Future<List<UserModel>> searchUsersByPhone(
      String phoneNumber, {
        int limit = 20,
        bool excludeCurrentUser = true,
      }) {
    return searchProfilesByPhone(
      phoneNumber,
      limit: limit,
      excludeCurrentUser: excludeCurrentUser,
    );
  }

  // =============================================================
  // EMAIL DISCOVERY
  // =============================================================

  Future<List<UserModel>> searchProfilesByEmail(
      String email, {
        int limit = 20,
        bool excludeCurrentUser = true,
      }) {
    final String normalized = email.trim().toLowerCase();

    if (normalized.isEmpty) {
      return Future<List<UserModel>>.value(
        const <UserModel>[],
      );
    }

    return _firestoreService.getUsersByEmail(
      normalized,
      limit: limit,
      excludeUid: excludeCurrentUser ? currentUserId : null,
    );
  }

  // =============================================================
  // ENSURE PROFILE
  // =============================================================

  Future<UserModel> ensureCurrentProfile({
    bool generateJrCallUserId = true,
  }) async {
    final User firebaseUser = _requireCurrentFirebaseUser();

    UserModel? profile = await _firestoreService.getUser(
      firebaseUser.uid,
    );

    if (profile == null) {
      return createDefaultProfile(
        generateJrCallUserId: generateJrCallUserId,
      );
    }

    await syncAuthenticationProfile();

    if (generateJrCallUserId && !profile.hasJrCallUserId) {
      await ensureCurrentUserJrCallId();

      profile = await _firestoreService.getUser(
        firebaseUser.uid,
      );

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
      await syncAuthenticationProfile();

      return await _firestoreService.getUser(firebaseUser.uid) ?? existing;
    }

    final String resolvedName =
        _cleanString(fullName) ??
            _cleanString(firebaseUser.displayName) ??
            '';

    final String resolvedPhone =
        _cleanString(firebaseUser.phoneNumber) ?? '';

    final String? resolvedEmail = _cleanString(
      firebaseUser.email,
    );

    final String? resolvedPhoto = _cleanString(
      firebaseUser.photoURL,
    );

    final List<String> providers = _authService.linkedProviderIds;

    final String? primaryProvider = _cleanString(
      _authService.primaryProviderId,
    );

    String? resolvedJrCallId = _cleanString(
      jrCallUserId,
    );

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
      verified:
      firebaseUser.emailVerified ||
          resolvedPhone.isNotEmpty,
      emailVerified: firebaseUser.emailVerified,
      phoneVerified: resolvedPhone.isNotEmpty,
      provider: primaryProvider,
      signInProviders: providers,
      isDiscoverable: true,
      isDiscoverableByEmail: true,
      isDiscoverableByPhone: true,
      createdAt:
      firebaseUser.metadata.creationTime ??
          DateTime.now(),
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

    final UserModel? saved = await _firestoreService.getUser(
      firebaseUser.uid,
    );

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

    final String? normalizedPhone = phoneNumber?.trim();

    await _firestoreService.updateProfile(
      uid: uid,
      name: fullName,
      phone: normalizedPhone,
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
      await _syncFirebaseDisplayNameSafely(
        fullName,
      );
    }

    if (profilePhotoUrl != null) {
      await _syncFirebasePhotoUrlSafely(
        profilePhotoUrl,
      );
    }
  }

  // =============================================================
  // PHONE
  // =============================================================

  Future<void> updatePhoneNumber(
      String phoneNumber,
      ) async {
    final String normalized = phoneNumber.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(
        phoneNumber,
        'phoneNumber',
        'Phone number cannot be empty.',
      );
    }

    await _firestoreService.updateProfile(
      uid: _requireCurrentUid(),
      phone: normalized,
    );
  }

  Future<void> clearPhoneNumber() {
    return _firestoreService.clearProfileField(
      uid: _requireCurrentUid(),
      field: UserProfileField.phone,
    );
  }

  // =============================================================
  // FULL NAME
  // =============================================================

  Future<void> updateFullName(
      String fullName,
      ) async {
    final String uid = _requireCurrentUid();

    await _firestoreService.updateFullName(
      uid: uid,
      fullName: fullName,
    );

    await _syncFirebaseDisplayNameSafely(
      fullName,
    );
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

  Future<void> updateUsername(
      String username,
      ) {
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

  Future<void> updateJrCallUserId(
      String jrCallUserId,
      ) {
    return _firestoreService.updateUserAddress(
      uid: _requireCurrentUid(),
      userAddress: jrCallUserId,
    );
  }

  Future<void> updateUserAddress(
      String userAddress,
      ) {
    return updateJrCallUserId(
      userAddress,
    );
  }

  Future<String> ensureCurrentUserJrCallId() async {
    final String uid = _requireCurrentUid();

    final UserModel? profile = await _firestoreService.getUser(
      uid,
    );

    if (profile == null) {
      throw StateError(
        'JR CALL profile does not exist.',
      );
    }

    final String? currentId = _cleanString(
      profile.jrCallUserId,
    );

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
        // Reservation collision.
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

  Future<void> updateBio(
      String bio,
      ) {
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

  Future<void> updateDateOfBirth(
      DateTime dateOfBirth,
      ) {
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

    final String downloadUrl =
    await _storageService.uploadProfilePhoto(
      uid: uid,
      bytes: bytes,
      contentType: contentType,
    );

    try {
      await _firestoreService.updateProfilePhotoUrl(
        uid: uid,
        photoUrl: downloadUrl,
      );

      await _syncFirebasePhotoUrlSafely(
        downloadUrl,
      );

      return downloadUrl;
    } catch (_) {
      try {
        await _storageService.deleteProfilePhoto(
          uid: uid,
        );
      } catch (_) {
        // Best-effort rollback.
      }

      rethrow;
    }
  }

  Future<void> deleteProfilePhoto() async {
    final String uid = _requireCurrentUid();

    await _storageService.deleteProfilePhoto(
      uid: uid,
    );

    await _firestoreService.clearProfileField(
      uid: uid,
      field: UserProfileField.photoUrl,
    );

    await _syncFirebasePhotoUrlSafely(
      null,
    );
  }

  // =============================================================
  // COVER PHOTO
  // =============================================================

  Future<String> uploadCoverPhoto({
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final String uid = _requireCurrentUid();

    final String downloadUrl =
    await _storageService.uploadCoverPhoto(
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
        await _storageService.deleteCoverPhoto(
          uid: uid,
        );
      } catch (_) {
        // Best-effort rollback.
      }

      rethrow;
    }
  }

  Future<void> deleteCoverPhoto() async {
    final String uid = _requireCurrentUid();

    await _storageService.deleteCoverPhoto(
      uid: uid,
    );

    await _firestoreService.clearProfileField(
      uid: uid,
      field: UserProfileField.coverPhoto,
    );
  }

  // =============================================================
  // AUTH METADATA SYNC
  //
  // IMPORTANT:
  // Never creates a missing users/{uid}.
  // =============================================================

  Future<void> syncAuthenticationProfile() async {
    final User originalUser = _requireCurrentFirebaseUser();

    try {
      await originalUser.reload();
    } catch (_) {
      // Existing authenticated snapshot remains usable.
    }

    final User user =
        _authService.currentUser ??
            originalUser;

    final UserModel? existingProfile =
    await _firestoreService.getUser(
      user.uid,
    );

    if (existingProfile == null) {
      return;
    }

    final String? email = _cleanString(
      user.email,
    );

    final String? phone = _cleanString(
      user.phoneNumber,
    );

    final List<String> providers =
    user.providerData
        .map(
          (UserInfo provider) =>
          provider.providerId.trim(),
    )
        .where(
          (String id) =>
      id.isNotEmpty,
    )
        .toSet()
        .toList(
      growable: false,
    );

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
  // FCM DEVICE TOKEN
  // =============================================================

  Future<String?> syncCurrentDeviceToken() async {
    final String uid = _requireCurrentUid();

    final UserModel? profile =
    await _firestoreService.getUser(
      uid,
    );

    if (profile == null) {
      return null;
    }

    try {
      final String? rawToken =
      await _firebaseMessaging.getToken();

      final String token =
          rawToken?.trim() ?? '';

      if (token.isEmpty) {
        return null;
      }

      if (_tokenSyncUid == uid &&
          _lastSavedFcmToken == token) {
        return token;
      }

      await _firestoreService.updateProfile(
        uid: uid,
        deviceToken: token,
      );

      _tokenSyncUid = uid;
      _lastSavedFcmToken = token;

      return token;
    } catch (_) {
      return null;
    }
  }

  // =============================================================
  // FCM TOKEN REFRESH
  // =============================================================

  Future<void> startDeviceTokenSync() async {
    if (_startingTokenSync) {
      return;
    }

    final String uid = _requireCurrentUid();

    final UserModel? profile =
    await _firestoreService.getUser(
      uid,
    );

    if (profile == null) {
      return;
    }

    if (_fcmTokenSubscription != null &&
        _tokenSyncUid == uid) {
      await syncCurrentDeviceToken();

      return;
    }

    _startingTokenSync = true;

    try {
      await stopDeviceTokenSync(
        clearCachedToken: false,
      );

      _tokenSyncUid = uid;

      await syncCurrentDeviceToken();

      if (_authService.currentUser?.uid != uid) {
        return;
      }

      _fcmTokenSubscription =
          _firebaseMessaging.onTokenRefresh.listen(
                (String token) {
              final String normalizedToken =
              token.trim();

              if (normalizedToken.isEmpty) {
                return;
              }

              final User? currentUser =
                  _authService.currentUser;

              if (currentUser == null ||
                  currentUser.uid != uid) {
                return;
              }

              unawaited(
                _persistRefreshedDeviceToken(
                  uid: uid,
                  token: normalizedToken,
                ),
              );
            },
            onError: (Object _) {
              // Non-fatal.
            },
          );
    } finally {
      _startingTokenSync = false;
    }
  }

  Future<void> _persistRefreshedDeviceToken({
    required String uid,
    required String token,
  }) async {
    if (_authService.currentUser?.uid != uid) {
      return;
    }

    if (_tokenSyncUid == uid &&
        _lastSavedFcmToken == token) {
      return;
    }

    try {
      final UserModel? profile =
      await _firestoreService.getUser(
        uid,
      );

      if (profile == null) {
        return;
      }

      await _firestoreService.updateProfile(
        uid: uid,
        deviceToken: token,
      );

      if (_authService.currentUser?.uid == uid) {
        _tokenSyncUid = uid;
        _lastSavedFcmToken = token;
      }
    } catch (_) {
      // FCM must not destabilize authentication/profile state.
    }
  }

  Future<void> stopDeviceTokenSync({
    bool clearCachedToken = true,
  }) async {
    final StreamSubscription<String>? subscription =
        _fcmTokenSubscription;

    _fcmTokenSubscription = null;

    if (subscription != null) {
      try {
        await subscription.cancel();
      } catch (_) {
        // Already closed.
      }
    }

    if (clearCachedToken) {
      _tokenSyncUid = null;
      _lastSavedFcmToken = null;
    }
  }

  // =============================================================
  // CLEAR DEVICE TOKEN
  // =============================================================

  Future<void> clearCurrentDeviceToken() async {
    final String uid = _requireCurrentUid();

    await stopDeviceTokenSync();

    final UserModel? profile =
    await _firestoreService.getUser(
      uid,
    );

    if (profile == null) {
      return;
    }

    await _firestoreService.clearProfileField(
      uid: uid,
      field: UserProfileField.deviceToken,
    );
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
      isDiscoverableByEmail:
      isDiscoverableByEmail,
      isDiscoverableByPhone:
      isDiscoverableByPhone,
    );
  }

  // =============================================================
  // CLEAR FIELD
  // =============================================================

  Future<void> clearProfileField(
      UserProfileField field,
      ) async {
    final String uid = _requireCurrentUid();

    if (field == UserProfileField.photoUrl) {
      await deleteProfilePhoto();
      return;
    }

    if (field == UserProfileField.coverPhoto) {
      await deleteCoverPhoto();
      return;
    }

    if (field == UserProfileField.deviceToken) {
      await stopDeviceTokenSync();
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

    await stopDeviceTokenSync();

    Object? mediaError;
    StackTrace? mediaStackTrace;

    try {
      await _storageService.deleteUserProfileMedia(
        uid: uid,
      );
    } catch (error, stackTrace) {
      mediaError = error;
      mediaStackTrace = stackTrace;
    }

    await _firestoreService.deleteUserProfile(
      uid,
    );

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
      final String candidate =
      _generateJrCallIdCandidate();

      final bool available =
      await _firestoreService.isUserAddressAvailable(
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
    final StringBuffer buffer =
    StringBuffer(
      _jrCallIdPrefix,
    );

    for (
    int index = 0;
    index < _jrCallIdRandomLength;
    index++
    ) {
      buffer.write(
        _jrCallIdAlphabet[
        _secureRandom.nextInt(
          _jrCallIdAlphabet.length,
        )],
      );
    }

    return buffer
        .toString()
        .toLowerCase();
  }

  // =============================================================
  // FIREBASE AUTH DISPLAY METADATA
  // =============================================================

  Future<void> _syncFirebaseDisplayNameSafely(
      String value,
      ) async {
    try {
      await _authService.updateDisplayName(
        value,
      );
    } on FirebaseAuthException {
      // Firestore remains canonical profile storage.
    }
  }

  Future<void> _syncFirebasePhotoUrlSafely(
      String? value,
      ) async {
    try {
      await _authService.updatePhotoUrl(
        value,
      );
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
        'An authenticated Firebase user is required '
            'for profile operations.',
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
    return _requireCurrentFirebaseUser()
        .uid
        .trim();
  }

  String _normalizeRequiredUid(
      String uid,
      ) {
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

  String? _cleanString(
      String? value,
      ) {
    final String normalized =
        value?.trim() ?? '';

    return normalized.isEmpty
        ? null
        : normalized;
  }
}

// ===============================================================
// END OF FILE
//
// OTP/AUTH MASTER PROFILE CONTRACT:
//
// ✓ Firebase UID canonical.
// ✓ Missing profile is never created by Auth metadata sync.
// ✓ Missing Login profile remains distinguishable.
// ✓ Explicit profile creation remains explicit.
// ✓ Existing phone/email preservation remains intact.
// ✓ Firestore phone-search metadata remains intact.
// ✓ Username/JR CALL ID uniqueness remains intact.
// ✓ Profile/Cover Storage remains intact.
// ✓ FCM cannot create a missing profile.
// ✓ OTP/password are never stored.
// ✓ Call Engine untouched.
// ✓ Message Engine untouched.
// ✓ WebRTC untouched.
//
// FIXED:
//
// ✓ Invalid catch(error, stackTrace,) syntax repaired.
// ✓ Valid Dart syntax is catch(error, stackTrace).
//
// SAVE/REPLACE THIS WHOLE FILE.
// ===============================================================