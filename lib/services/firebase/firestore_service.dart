import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/user_model.dart';

/// ===========================================================
/// JR CALL
/// File: firestore_service.dart
/// Location: lib/services/firebase/firestore_service.dart
/// Master Repair: FILE 02/05
///
/// Description:
/// Canonical production Firestore repository for JR CALL users.
///
/// Responsibilities:
/// - Create/read/update user profiles
/// - Real-time profile observation
/// - Preserve legacy JR CALL profile fields
/// - Maintain normalized searchable profile fields
/// - Atomic username uniqueness
/// - Atomic JR CALL public address uniqueness
/// - Safe reservation ownership
/// - Remove optional profile fields safely
/// - Exact username lookup
/// - Exact JR CALL address lookup
/// - Name-prefix discovery
/// - Email/phone exact discovery where profile privacy allows
/// - Safe profile deletion and reservation cleanup
///
/// PHONE DISCOVERY REPAIR:
/// - Existing phone / phoneNumber / phoneNormalized preserved.
/// - Multiple exact phone representations indexed safely.
/// - Local/formatted/E.164 values already supplied by the app remain
///   searchable without downloading the whole users collection.
/// - Legacy documents without phoneSearchKeys remain searchable.
/// - No country is hardcoded.
/// - Firebase UID remains canonical internal identity.
///
/// Ownership:
/// - Firebase Authentication -> AuthService
/// - User/profile Firestore data -> FirestoreService
/// - Binary profile/cover images -> Firebase Storage layer
/// - Call signaling -> SignalingService
///
/// Important:
/// - Passwords are NEVER stored here.
/// - OTP values are NEVER stored here.
/// - Firebase UID remains the canonical private account identity.
/// - JR CALL public address is separate from Firebase UID/email.
/// ===========================================================

enum UserProfileField {
  name,
  phone,
  email,
  username,
  userAddress,
  photoUrl,
  coverPhoto,
  bio,
  country,
  countryCode,
  gender,
  dateOfBirth,
  provider,
  deviceToken,
}

class FirestoreService {
  FirestoreService._();

  static final FirestoreService instance = FirestoreService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ===========================================================
  // Collection Names
  // ===========================================================

  static const String _usersCollectionName = 'users';
  static const String _usernameCollectionName = 'usernames';
  static const String _userAddressCollectionName = 'user_addresses';

  static const int _maximumSearchLimit = 50;

  // ===========================================================
  // Validation
  // ===========================================================

  static final RegExp _usernamePattern = RegExp(r'^[a-z0-9._]{3,30}$');

  static final RegExp _userAddressPattern = RegExp(r'^[a-z0-9._-]{3,64}$');

  static final RegExp _basicEmailPattern = RegExp(
    r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
  );

  // ===========================================================
  // Collections
  // ===========================================================

  CollectionReference<Map<String, dynamic>> get usersCollection =>
      _firestore.collection(_usersCollectionName);

  CollectionReference<Map<String, dynamic>> get _usernameReservations =>
      _firestore.collection(_usernameCollectionName);

  CollectionReference<Map<String, dynamic>> get _userAddressReservations =>
      _firestore.collection(_userAddressCollectionName);

  // ===========================================================
  // Create / Upsert User
  // ===========================================================

  Future<void> createUser(UserModel user) async {
    final uid = _requireUid(user.uid);

    final requestedUsername = _normalizeUsername(user.username);
    final requestedAddress = _normalizeUserAddress(user.userAddress);

    _validateUsername(requestedUsername);
    _validateUserAddress(requestedAddress);

    final userRef = usersCollection.doc(uid);

    await _firestore.runTransaction<void>((transaction) async {
      final currentUserSnapshot = await transaction.get(userRef);
      final currentData = currentUserSnapshot.data();

      final currentUsername = _normalizeUsername(currentData?['username']);

      final currentAddress = _normalizeUserAddress(
        currentData?['userAddress'] ?? currentData?['jrCallUserId'],
      );

      final newUsernameRef = requestedUsername == null
          ? null
          : _usernameReservations.doc(requestedUsername);

      final newAddressRef = requestedAddress == null
          ? null
          : _userAddressReservations.doc(requestedAddress);

      final oldUsernameRef =
      currentUsername != null && currentUsername != requestedUsername
          ? _usernameReservations.doc(currentUsername)
          : null;

      final oldAddressRef =
      currentAddress != null && currentAddress != requestedAddress
          ? _userAddressReservations.doc(currentAddress)
          : null;

      DocumentSnapshot<Map<String, dynamic>>? newUsernameSnapshot;
      DocumentSnapshot<Map<String, dynamic>>? newAddressSnapshot;
      DocumentSnapshot<Map<String, dynamic>>? oldUsernameSnapshot;
      DocumentSnapshot<Map<String, dynamic>>? oldAddressSnapshot;

      if (newUsernameRef != null) {
        newUsernameSnapshot = await transaction.get(newUsernameRef);
      }

      if (newAddressRef != null) {
        newAddressSnapshot = await transaction.get(newAddressRef);
      }

      if (oldUsernameRef != null) {
        oldUsernameSnapshot = await transaction.get(oldUsernameRef);
      }

      if (oldAddressRef != null) {
        oldAddressSnapshot = await transaction.get(oldAddressRef);
      }

      _ensureReservationAvailable(
        snapshot: newUsernameSnapshot,
        uid: uid,
        fieldName: 'Username',
        value: requestedUsername,
      );

      _ensureReservationAvailable(
        snapshot: newAddressSnapshot,
        uid: uid,
        fieldName: 'JR CALL User Address',
        value: requestedAddress,
      );

      _deleteReservationIfOwned(
        transaction: transaction,
        reference: oldUsernameRef,
        snapshot: oldUsernameSnapshot,
        ownerUid: uid,
      );

      _deleteReservationIfOwned(
        transaction: transaction,
        reference: oldAddressRef,
        snapshot: oldAddressSnapshot,
        ownerUid: uid,
      );

      if (newUsernameRef != null && requestedUsername != null) {
        transaction.set(
          newUsernameRef,
          _reservationDocument(
            uid: uid,
            value: requestedUsername,
            existing: newUsernameSnapshot?.exists ?? false,
          ),
          SetOptions(merge: true),
        );
      }

      if (newAddressRef != null && requestedAddress != null) {
        transaction.set(
          newAddressRef,
          _reservationDocument(
            uid: uid,
            value: requestedAddress,
            existing: newAddressSnapshot?.exists ?? false,
          ),
          SetOptions(merge: true),
        );
      }

      final document = _buildUserDocument(
        user,
        normalizedUsername: requestedUsername,
        normalizedUserAddress: requestedAddress,
        existingDocument: currentUserSnapshot.exists,
      );

      transaction.set(userRef, document, SetOptions(merge: true));
    });
  }

  // ===========================================================
  // Read User
  // ===========================================================

  Future<UserModel?> getUser(String uid) async {
    final normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      return null;
    }

    final snapshot = await usersCollection.doc(normalizedUid).get();
    final data = snapshot.data();

    if (!snapshot.exists || data == null) {
      return null;
    }

    return _userModelFromDocument(documentId: snapshot.id, data: data);
  }

  // ===========================================================
  // Watch User
  // ===========================================================

  Stream<UserModel?> watchUser(String uid) {
    final normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      return Stream<UserModel?>.value(null);
    }

    return usersCollection.doc(normalizedUid).snapshots().map((snapshot) {
      final data = snapshot.data();

      if (!snapshot.exists || data == null) {
        return null;
      }

      return _userModelFromDocument(documentId: snapshot.id, data: data);
    });
  }

  // ===========================================================
  // Compatibility Aliases
  // ===========================================================

  Future<UserModel?> getCurrentProfile(String uid) {
    return getUser(uid);
  }

  Stream<UserModel?> profileStream(String uid) {
    return watchUser(uid);
  }

  Future<void> updateUser(UserModel user) {
    return createUser(user);
  }

  // ===========================================================
  // Update Profile
  // ===========================================================

  Future<void> updateProfile({
    required String uid,
    String? name,
    String? phone,
    String? email,
    String? username,
    String? userAddress,
    String? photoUrl,
    String? coverPhoto,
    String? bio,
    String? country,
    String? countryCode,
    String? gender,
    DateTime? dateOfBirth,
    String? provider,
    String? deviceToken,
  }) async {
    final normalizedUid = _requireUid(uid);

    _validateProfileInput(
      name: name,
      phone: phone,
      email: email,
      photoUrl: photoUrl,
      coverPhoto: coverPhoto,
      bio: bio,
      country: country,
      countryCode: countryCode,
      gender: gender,
      provider: provider,
      deviceToken: deviceToken,
      dateOfBirth: dateOfBirth,
    );

    final userRef = usersCollection.doc(normalizedUid);

    await _firestore.runTransaction<void>((transaction) async {
      final userSnapshot = await transaction.get(userRef);
      final currentData = userSnapshot.data();

      if (!userSnapshot.exists || currentData == null) {
        throw StateError('User profile does not exist.');
      }

      final currentUsername = _normalizeUsername(currentData['username']);

      final currentAddress = _normalizeUserAddress(
        currentData['userAddress'] ?? currentData['jrCallUserId'],
      );

      final requestedUsername = username == null
          ? currentUsername
          : _normalizeUsername(username);

      final requestedAddress = userAddress == null
          ? currentAddress
          : _normalizeUserAddress(userAddress);

      _validateUsername(requestedUsername);
      _validateUserAddress(requestedAddress);

      final usernameChanged =
          username != null && requestedUsername != currentUsername;

      final addressChanged =
          userAddress != null && requestedAddress != currentAddress;

      final newUsernameRef = usernameChanged && requestedUsername != null
          ? _usernameReservations.doc(requestedUsername)
          : null;

      final oldUsernameRef = usernameChanged && currentUsername != null
          ? _usernameReservations.doc(currentUsername)
          : null;

      final newAddressRef = addressChanged && requestedAddress != null
          ? _userAddressReservations.doc(requestedAddress)
          : null;

      final oldAddressRef = addressChanged && currentAddress != null
          ? _userAddressReservations.doc(currentAddress)
          : null;

      DocumentSnapshot<Map<String, dynamic>>? newUsernameSnapshot;
      DocumentSnapshot<Map<String, dynamic>>? oldUsernameSnapshot;
      DocumentSnapshot<Map<String, dynamic>>? newAddressSnapshot;
      DocumentSnapshot<Map<String, dynamic>>? oldAddressSnapshot;

      if (newUsernameRef != null) {
        newUsernameSnapshot = await transaction.get(newUsernameRef);
      }

      if (oldUsernameRef != null) {
        oldUsernameSnapshot = await transaction.get(oldUsernameRef);
      }

      if (newAddressRef != null) {
        newAddressSnapshot = await transaction.get(newAddressRef);
      }

      if (oldAddressRef != null) {
        oldAddressSnapshot = await transaction.get(oldAddressRef);
      }

      if (usernameChanged && requestedUsername != null) {
        _ensureReservationAvailable(
          snapshot: newUsernameSnapshot,
          uid: normalizedUid,
          fieldName: 'Username',
          value: requestedUsername,
        );
      }

      if (addressChanged && requestedAddress != null) {
        _ensureReservationAvailable(
          snapshot: newAddressSnapshot,
          uid: normalizedUid,
          fieldName: 'JR CALL User Address',
          value: requestedAddress,
        );
      }

      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (name != null) {
        final value = name.trim();

        updates['name'] = value;
        updates['fullName'] = value;
        updates['normalizedName'] = value.toLowerCase();
        updates['fullNameLowercase'] = value.toLowerCase();
      }

      // =======================================================
      // PHONE — REPAIRED
      // =======================================================

      if (phone != null) {
        final value = phone.trim();

        if (value.isEmpty) {
          updates['phone'] = '';
          updates['phoneNumber'] = '';
          updates['phoneNormalized'] = FieldValue.delete();
          updates['phoneDigits'] = FieldValue.delete();
          updates['phoneSearchKeys'] = FieldValue.delete();
        } else {
          final normalizedPhone = _normalizePhoneForSearch(value);
          final searchKeys = _phoneSearchKeys(value);

          updates['phone'] = value;
          updates['phoneNumber'] = value;
          updates['phoneNormalized'] = normalizedPhone;
          updates['phoneDigits'] = _digitsOnlyPhone(value);
          updates['phoneSearchKeys'] = searchKeys;
        }
      }

      if (email != null) {
        final value = email.trim();

        if (value.isEmpty) {
          updates['email'] = FieldValue.delete();
          updates['emailNormalized'] = FieldValue.delete();
        } else {
          updates['email'] = value;
          updates['emailNormalized'] = value.toLowerCase();
        }
      }

      if (photoUrl != null) {
        _applyMirroredOptionalString(
          updates,
          primaryField: 'photoUrl',
          compatibilityField: 'profilePhotoUrl',
          value: photoUrl,
        );
      }

      if (coverPhoto != null) {
        _applyMirroredOptionalString(
          updates,
          primaryField: 'coverPhoto',
          compatibilityField: 'coverPhotoUrl',
          value: coverPhoto,
        );

        final normalized = coverPhoto.trim();

        if (normalized.isEmpty) {
          updates['backgroundPhotoUrl'] = FieldValue.delete();
        } else {
          updates['backgroundPhotoUrl'] = normalized;
        }
      }

      if (bio != null) {
        _applyOptionalString(updates, field: 'bio', value: bio);
      }

      if (country != null) {
        _applyOptionalString(updates, field: 'country', value: country);
      }

      if (countryCode != null) {
        final normalized = countryCode.trim().toUpperCase();

        if (normalized.isEmpty) {
          updates['countryCode'] = FieldValue.delete();
        } else {
          updates['countryCode'] = normalized;
        }
      }

      if (gender != null) {
        _applyOptionalString(updates, field: 'gender', value: gender);
      }

      if (provider != null) {
        _applyOptionalString(updates, field: 'provider', value: provider);
      }

      if (deviceToken != null) {
        _applyOptionalString(updates, field: 'deviceToken', value: deviceToken);
      }

      if (dateOfBirth != null) {
        updates['dateOfBirth'] = Timestamp.fromDate(_dateOnly(dateOfBirth));
      }

      if (username != null) {
        _deleteReservationIfOwned(
          transaction: transaction,
          reference: oldUsernameRef,
          snapshot: oldUsernameSnapshot,
          ownerUid: normalizedUid,
        );

        if (requestedUsername == null) {
          updates['username'] = FieldValue.delete();
          updates['normalizedUsername'] = FieldValue.delete();
          updates['usernameLowercase'] = FieldValue.delete();
        } else {
          updates['username'] = requestedUsername;
          updates['normalizedUsername'] = requestedUsername;
          updates['usernameLowercase'] = requestedUsername;

          transaction.set(
            _usernameReservations.doc(requestedUsername),
            _reservationDocument(
              uid: normalizedUid,
              value: requestedUsername,
              existing: newUsernameSnapshot?.exists ?? false,
            ),
            SetOptions(merge: true),
          );
        }
      }

      if (userAddress != null) {
        _deleteReservationIfOwned(
          transaction: transaction,
          reference: oldAddressRef,
          snapshot: oldAddressSnapshot,
          ownerUid: normalizedUid,
        );

        if (requestedAddress == null) {
          updates['userAddress'] = FieldValue.delete();
          updates['normalizedUserAddress'] = FieldValue.delete();
          updates['jrCallUserId'] = FieldValue.delete();
          updates['jrCallUserIdLowercase'] = FieldValue.delete();
        } else {
          updates['userAddress'] = requestedAddress;
          updates['normalizedUserAddress'] = requestedAddress;
          updates['jrCallUserId'] = requestedAddress;
          updates['jrCallUserIdLowercase'] = requestedAddress;

          transaction.set(
            _userAddressReservations.doc(requestedAddress),
            _reservationDocument(
              uid: normalizedUid,
              value: requestedAddress,
              existing: newAddressSnapshot?.exists ?? false,
            ),
            SetOptions(merge: true),
          );
        }
      }

      transaction.update(userRef, updates);
    });
  }

  // ===========================================================
  // Convenience Field Updates
  // ===========================================================

  Future<void> updateFullName({required String uid, required String fullName}) {
    return updateProfile(uid: uid, name: fullName);
  }

  Future<void> updateUsername({required String uid, required String username}) {
    return updateProfile(uid: uid, username: username);
  }

  Future<void> updateUserAddress({
    required String uid,
    required String userAddress,
  }) {
    return updateProfile(uid: uid, userAddress: userAddress);
  }

  Future<void> updateCountry({
    required String uid,
    required String country,
    required String countryCode,
  }) {
    return updateProfile(uid: uid, country: country, countryCode: countryCode);
  }

  Future<void> updateBio({required String uid, required String bio}) {
    return updateProfile(uid: uid, bio: bio);
  }

  Future<void> updateDateOfBirth({
    required String uid,
    required DateTime dateOfBirth,
  }) {
    return updateProfile(uid: uid, dateOfBirth: dateOfBirth);
  }

  Future<void> updateProfilePhotoUrl({
    required String uid,
    required String photoUrl,
  }) {
    return updateProfile(uid: uid, photoUrl: photoUrl);
  }

  Future<void> updateCoverPhotoUrl({
    required String uid,
    required String coverPhotoUrl,
  }) {
    return updateProfile(uid: uid, coverPhoto: coverPhotoUrl);
  }

  // ===========================================================
  // Authentication Metadata Sync
  // ===========================================================

  Future<void> syncAuthenticationProfile({
    required String uid,
    String? email,
    String? phoneNumber,
    bool? emailVerified,
    bool? phoneVerified,
    List<String>? signInProviders,
  }) async {
    final normalizedUid = _requireUid(uid);

    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (email != null) {
      final normalized = email.trim();

      if (normalized.isEmpty) {
        updates['email'] = FieldValue.delete();
        updates['emailNormalized'] = FieldValue.delete();
      } else {
        _validateEmail(normalized);

        updates['email'] = normalized;
        updates['emailNormalized'] = normalized.toLowerCase();
      }
    }

    // =========================================================
    // AUTH PHONE — REPAIRED
    //
    // arrayUnion deliberately preserves earlier legitimate
    // representations previously written by create/update.
    // =========================================================

    if (phoneNumber != null) {
      final normalized = phoneNumber.trim();

      if (normalized.isEmpty) {
        updates['phone'] = '';
        updates['phoneNumber'] = '';
        updates['phoneNormalized'] = FieldValue.delete();
        updates['phoneDigits'] = FieldValue.delete();
        updates['phoneSearchKeys'] = FieldValue.delete();
      } else {
        final searchKeys = _phoneSearchKeys(normalized);

        updates['phone'] = normalized;
        updates['phoneNumber'] = normalized;
        updates['phoneNormalized'] = _normalizePhoneForSearch(normalized);
        updates['phoneDigits'] = _digitsOnlyPhone(normalized);

        if (searchKeys.isNotEmpty) {
          updates['phoneSearchKeys'] = FieldValue.arrayUnion(searchKeys);
        }
      }
    }

    if (emailVerified != null) {
      updates['emailVerified'] = emailVerified;
    }

    if (phoneVerified != null) {
      updates['phoneVerified'] = phoneVerified;
    }

    if (signInProviders != null) {
      final providers = signInProviders
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false);

      updates['signInProviders'] = providers;
    }

    await usersCollection
        .doc(normalizedUid)
        .set(updates, SetOptions(merge: true));
  }

  // ===========================================================
  // Discoverability Flags
  // ===========================================================

  Future<void> updateDiscoverability({
    required String uid,
    bool? isDiscoverable,
    bool? isDiscoverableByEmail,
    bool? isDiscoverableByPhone,
  }) async {
    final normalizedUid = _requireUid(uid);

    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (isDiscoverable != null) {
      updates['isDiscoverable'] = isDiscoverable;
    }

    if (isDiscoverableByEmail != null) {
      updates['isDiscoverableByEmail'] = isDiscoverableByEmail;
    }

    if (isDiscoverableByPhone != null) {
      updates['isDiscoverableByPhone'] = isDiscoverableByPhone;
    }

    if (updates.length == 1) {
      return;
    }

    await usersCollection
        .doc(normalizedUid)
        .set(updates, SetOptions(merge: true));
  }

  // ===========================================================
  // Clear Profile Field
  // ===========================================================

  Future<void> clearProfileField({
    required String uid,
    required UserProfileField field,
  }) async {
    final normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      return;
    }

    final userRef = usersCollection.doc(normalizedUid);

    await _firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(userRef);
      final data = snapshot.data();

      if (!snapshot.exists || data == null) {
        return;
      }

      DocumentReference<Map<String, dynamic>>? reservationRef;
      DocumentSnapshot<Map<String, dynamic>>? reservationSnapshot;

      if (field == UserProfileField.username) {
        final username = _normalizeUsername(data['username']);

        if (username != null) {
          reservationRef = _usernameReservations.doc(username);
          reservationSnapshot = await transaction.get(reservationRef);
        }
      }

      if (field == UserProfileField.userAddress) {
        final address = _normalizeUserAddress(
          data['userAddress'] ?? data['jrCallUserId'],
        );

        if (address != null) {
          reservationRef = _userAddressReservations.doc(address);
          reservationSnapshot = await transaction.get(reservationRef);
        }
      }

      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      switch (field) {
        case UserProfileField.name:
          updates['name'] = '';
          updates['fullName'] = '';
          updates['normalizedName'] = '';
          updates['fullNameLowercase'] = '';
          break;

        case UserProfileField.phone:
          updates['phone'] = '';
          updates['phoneNumber'] = '';
          updates['phoneNormalized'] = FieldValue.delete();
          updates['phoneDigits'] = FieldValue.delete();
          updates['phoneSearchKeys'] = FieldValue.delete();
          break;

        case UserProfileField.email:
          updates['email'] = FieldValue.delete();
          updates['emailNormalized'] = FieldValue.delete();
          break;

        case UserProfileField.username:
          _deleteReservationIfOwned(
            transaction: transaction,
            reference: reservationRef,
            snapshot: reservationSnapshot,
            ownerUid: normalizedUid,
          );

          updates['username'] = FieldValue.delete();
          updates['normalizedUsername'] = FieldValue.delete();
          updates['usernameLowercase'] = FieldValue.delete();
          break;

        case UserProfileField.userAddress:
          _deleteReservationIfOwned(
            transaction: transaction,
            reference: reservationRef,
            snapshot: reservationSnapshot,
            ownerUid: normalizedUid,
          );

          updates['userAddress'] = FieldValue.delete();
          updates['normalizedUserAddress'] = FieldValue.delete();
          updates['jrCallUserId'] = FieldValue.delete();
          updates['jrCallUserIdLowercase'] = FieldValue.delete();
          break;

        case UserProfileField.photoUrl:
          updates['photoUrl'] = FieldValue.delete();
          updates['profilePhotoUrl'] = FieldValue.delete();
          break;

        case UserProfileField.coverPhoto:
          updates['coverPhoto'] = FieldValue.delete();
          updates['coverPhotoUrl'] = FieldValue.delete();
          updates['backgroundPhotoUrl'] = FieldValue.delete();
          break;

        case UserProfileField.bio:
          updates['bio'] = FieldValue.delete();
          break;

        case UserProfileField.country:
          updates['country'] = FieldValue.delete();
          break;

        case UserProfileField.countryCode:
          updates['countryCode'] = FieldValue.delete();
          break;

        case UserProfileField.gender:
          updates['gender'] = FieldValue.delete();
          break;

        case UserProfileField.dateOfBirth:
          updates['dateOfBirth'] = FieldValue.delete();
          break;

        case UserProfileField.provider:
          updates['provider'] = FieldValue.delete();
          break;

        case UserProfileField.deviceToken:
          updates['deviceToken'] = FieldValue.delete();
          break;
      }

      transaction.update(userRef, updates);
    });
  }

  // ===========================================================
  // Username Availability
  // ===========================================================

  Future<bool> isUsernameAvailable(String username, {String? forUid}) async {
    final normalized = _normalizeUsername(username);

    if (normalized == null) {
      return false;
    }

    _validateUsername(normalized);

    final snapshot = await _usernameReservations.doc(normalized).get();

    if (!snapshot.exists) {
      return true;
    }

    final ownerUid = _cleanString(snapshot.data()?['uid']);
    final normalizedForUid = forUid?.trim();

    return normalizedForUid != null &&
        normalizedForUid.isNotEmpty &&
        ownerUid == normalizedForUid;
  }

  // ===========================================================
  // JR CALL Address Availability
  // ===========================================================

  Future<bool> isUserAddressAvailable(
      String userAddress, {
        String? forUid,
      }) async {
    final normalized = _normalizeUserAddress(userAddress);

    if (normalized == null) {
      return false;
    }

    _validateUserAddress(normalized);

    final snapshot = await _userAddressReservations.doc(normalized).get();

    if (!snapshot.exists) {
      return true;
    }

    final ownerUid = _cleanString(snapshot.data()?['uid']);
    final normalizedForUid = forUid?.trim();

    return normalizedForUid != null &&
        normalizedForUid.isNotEmpty &&
        ownerUid == normalizedForUid;
  }

  // ===========================================================
  // Exact Username Lookup
  // ===========================================================

  Future<UserModel?> getUserByUsername(String username) async {
    final normalized = _normalizeUsername(username);

    if (normalized == null) {
      return null;
    }

    _validateUsername(normalized);

    final reservation = await _usernameReservations.doc(normalized).get();

    if (!reservation.exists) {
      return null;
    }

    final uid = _cleanString(reservation.data()?['uid']);

    if (uid == null) {
      return null;
    }

    return getUser(uid);
  }

  // ===========================================================
  // Exact JR CALL Address Lookup
  // ===========================================================

  Future<UserModel?> getUserByAddress(String userAddress) async {
    final normalized = _normalizeUserAddress(userAddress);

    if (normalized == null) {
      return null;
    }

    _validateUserAddress(normalized);

    final reservation = await _userAddressReservations.doc(normalized).get();

    if (!reservation.exists) {
      return null;
    }

    final uid = _cleanString(reservation.data()?['uid']);

    if (uid == null) {
      return null;
    }

    return getUser(uid);
  }

  Future<UserModel?> getUserByJrCallUserId(String jrCallUserId) {
    return getUserByAddress(jrCallUserId);
  }

  // ===========================================================
  // Exact Email Lookup
  // ===========================================================

  Future<List<UserModel>> getUsersByEmail(
      String email, {
        int limit = 10,
        String? excludeUid,
      }) async {
    final normalized = email.trim().toLowerCase();

    if (normalized.isEmpty || !_basicEmailPattern.hasMatch(normalized)) {
      return const <UserModel>[];
    }

    final safeLimit = _safeSearchLimit(limit);

    final snapshot = await usersCollection
        .where('emailNormalized', isEqualTo: normalized)
        .limit(safeLimit)
        .get();

    return _modelsFromQuery(
      snapshot,
      excludeUid: excludeUid,
      requireDiscoverableEmail: true,
    );
  }

  // ===========================================================
  // Exact Phone Lookup — REPAIRED
  // ===========================================================

  Future<List<UserModel>> getUsersByPhone(
      String phone, {
        int limit = 10,
        String? excludeUid,
      }) async {
    final searchKeys = _phoneSearchKeys(phone);

    if (searchKeys.isEmpty) {
      return const <UserModel>[];
    }

    final safeLimit = _safeSearchLimit(limit);
    final results = <String, UserModel>{};

    // ---------------------------------------------------------
    // 1. New production compatibility index.
    // ---------------------------------------------------------

    final QuerySnapshot<Map<String, dynamic>> indexedSnapshot =
    await usersCollection
        .where(
      'phoneSearchKeys',
      arrayContainsAny: searchKeys.take(30).toList(growable: false),
    )
        .limit(safeLimit)
        .get();

    _addQueryModels(
      results,
      indexedSnapshot,
      limit: safeLimit,
      excludeUid: excludeUid,
      requireDiscoverablePhone: true,
    );

    // ---------------------------------------------------------
    // 2. Legacy phoneNormalized fallback.
    // ---------------------------------------------------------

    if (results.length < safeLimit) {
      for (final key in searchKeys) {
        if (results.length >= safeLimit) {
          break;
        }

        final snapshot = await usersCollection
            .where('phoneNormalized', isEqualTo: key)
            .limit(safeLimit - results.length)
            .get();

        _addQueryModels(
          results,
          snapshot,
          limit: safeLimit,
          excludeUid: excludeUid,
          requireDiscoverablePhone: true,
        );
      }
    }

    // ---------------------------------------------------------
    // 3. Legacy phoneNumber fallback.
    // ---------------------------------------------------------

    if (results.length < safeLimit) {
      for (final key in searchKeys) {
        if (results.length >= safeLimit) {
          break;
        }

        final snapshot = await usersCollection
            .where('phoneNumber', isEqualTo: key)
            .limit(safeLimit - results.length)
            .get();

        _addQueryModels(
          results,
          snapshot,
          limit: safeLimit,
          excludeUid: excludeUid,
          requireDiscoverablePhone: true,
        );
      }
    }

    // ---------------------------------------------------------
    // 4. Oldest phone field fallback.
    // ---------------------------------------------------------

    if (results.length < safeLimit) {
      for (final key in searchKeys) {
        if (results.length >= safeLimit) {
          break;
        }

        final snapshot = await usersCollection
            .where('phone', isEqualTo: key)
            .limit(safeLimit - results.length)
            .get();

        _addQueryModels(
          results,
          snapshot,
          limit: safeLimit,
          excludeUid: excludeUid,
          requireDiscoverablePhone: true,
        );
      }
    }

    return List<UserModel>.unmodifiable(
      results.values.take(safeLimit),
    );
  }

  // ===========================================================
  // Search Users
  // ===========================================================

  Future<List<UserModel>> searchUsers(
      String query, {
        int limit = 20,
        String? excludeUid,
      }) async {
    final normalizedQuery = query.trim().toLowerCase();

    if (normalizedQuery.isEmpty) {
      return const <UserModel>[];
    }

    final safeLimit = _safeSearchLimit(limit);
    final normalizedExcludeUid = excludeUid?.trim();

    final results = <String, UserModel>{};

    // ---------------------------------------------------------
    // Exact JR CALL address
    // ---------------------------------------------------------

    final address = _normalizeUserAddress(normalizedQuery);

    if (address != null) {
      try {
        final reservation = await _userAddressReservations.doc(address).get();

        final uid = _cleanString(reservation.data()?['uid']);

        if (uid != null) {
          final user = await getUser(uid);

          if (user != null) {
            _addSearchModel(results, user, excludeUid: normalizedExcludeUid);
          }
        }
      } on ArgumentError {
        // Not a valid JR CALL address.
      }
    }

    // ---------------------------------------------------------
    // Exact username
    // ---------------------------------------------------------

    if (results.length < safeLimit) {
      final username = _normalizeUsername(normalizedQuery);

      if (username != null) {
        try {
          final reservation = await _usernameReservations.doc(username).get();

          final uid = _cleanString(reservation.data()?['uid']);

          if (uid != null) {
            final user = await getUser(uid);

            if (user != null) {
              _addSearchModel(results, user, excludeUid: normalizedExcludeUid);
            }
          }
        } on ArgumentError {
          // Not a valid username.
        }
      }
    }

    // ---------------------------------------------------------
    // Exact email
    // ---------------------------------------------------------

    if (results.length < safeLimit &&
        normalizedQuery.contains('@') &&
        _basicEmailPattern.hasMatch(normalizedQuery)) {
      final emailResults = await getUsersByEmail(
        normalizedQuery,
        limit: safeLimit - results.length,
        excludeUid: normalizedExcludeUid,
      );

      for (final user in emailResults) {
        _addSearchModel(results, user, excludeUid: normalizedExcludeUid);
      }
    }

    // ---------------------------------------------------------
    // Exact phone
    // ---------------------------------------------------------

    if (results.length < safeLimit && _looksLikePhone(normalizedQuery)) {
      final phoneResults = await getUsersByPhone(
        normalizedQuery,
        limit: safeLimit - results.length,
        excludeUid: normalizedExcludeUid,
      );

      for (final user in phoneResults) {
        _addSearchModel(results, user, excludeUid: normalizedExcludeUid);
      }
    }

    // ---------------------------------------------------------
    // Name prefix
    // ---------------------------------------------------------

    if (results.length < safeLimit) {
      final remaining = safeLimit - results.length;

      final snapshot = await usersCollection
          .where('normalizedName', isGreaterThanOrEqualTo: normalizedQuery)
          .where(
        'normalizedName',
        isLessThanOrEqualTo: '$normalizedQuery\uf8ff',
      )
          .limit(remaining)
          .get();

      for (final document in snapshot.docs) {
        final data = document.data();

        if (!_isGenerallyDiscoverable(data)) {
          continue;
        }

        final model = _userModelFromDocument(
          documentId: document.id,
          data: data,
        );

        _addSearchModel(results, model, excludeUid: normalizedExcludeUid);
      }
    }

    return List<UserModel>.unmodifiable(
      results.values.take(safeLimit),
    );
  }

  // ===========================================================
  // Delete Firestore User Profile
  // ===========================================================

  Future<void> deleteUserProfile(String uid) async {
    final normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      return;
    }

    final userRef = usersCollection.doc(normalizedUid);

    await _firestore.runTransaction<void>((transaction) async {
      final userSnapshot = await transaction.get(userRef);
      final data = userSnapshot.data();

      if (!userSnapshot.exists || data == null) {
        return;
      }

      final username = _normalizeUsername(data['username']);

      final address = _normalizeUserAddress(
        data['userAddress'] ?? data['jrCallUserId'],
      );

      final usernameRef = username == null
          ? null
          : _usernameReservations.doc(username);

      final addressRef = address == null
          ? null
          : _userAddressReservations.doc(address);

      DocumentSnapshot<Map<String, dynamic>>? usernameSnapshot;
      DocumentSnapshot<Map<String, dynamic>>? addressSnapshot;

      if (usernameRef != null) {
        usernameSnapshot = await transaction.get(usernameRef);
      }

      if (addressRef != null) {
        addressSnapshot = await transaction.get(addressRef);
      }

      _deleteReservationIfOwned(
        transaction: transaction,
        reference: usernameRef,
        snapshot: usernameSnapshot,
        ownerUid: normalizedUid,
      );

      _deleteReservationIfOwned(
        transaction: transaction,
        reference: addressRef,
        snapshot: addressSnapshot,
        ownerUid: normalizedUid,
      );

      transaction.delete(userRef);
    });
  }

  // ===========================================================
  // Main User Document Builder
  // ===========================================================

  Map<String, dynamic> _buildUserDocument(
      UserModel user, {
        required String? normalizedUsername,
        required String? normalizedUserAddress,
        required bool existingDocument,
      }) {
    final data = Map<String, dynamic>.from(user.toMap());

    final uid = _requireUid(user.uid);
    final fullName = user.name.trim();
    final phone = user.phone.trim();
    final email = user.email?.trim();

    data['uid'] = uid;

    // ---------------------------------------------------------
    // Name compatibility
    // ---------------------------------------------------------

    data['name'] = fullName;
    data['fullName'] = fullName;
    data['normalizedName'] = fullName.toLowerCase();
    data['fullNameLowercase'] = fullName.toLowerCase();

    // ---------------------------------------------------------
    // Phone compatibility — REPAIRED
    // ---------------------------------------------------------

    data['phone'] = phone;
    data['phoneNumber'] = phone;

    if (phone.isEmpty) {
      data['phoneNormalized'] = FieldValue.delete();
      data['phoneDigits'] = FieldValue.delete();
      data['phoneSearchKeys'] = FieldValue.delete();
    } else {
      data['phoneNormalized'] = _normalizePhoneForSearch(phone);
      data['phoneDigits'] = _digitsOnlyPhone(phone);
      data['phoneSearchKeys'] = _phoneSearchKeys(phone);
    }

    // ---------------------------------------------------------
    // Email
    // ---------------------------------------------------------

    if (email == null || email.isEmpty) {
      data['email'] = FieldValue.delete();
      data['emailNormalized'] = FieldValue.delete();
    } else {
      data['email'] = email;
      data['emailNormalized'] = email.toLowerCase();
    }

    // ---------------------------------------------------------
    // Username
    // ---------------------------------------------------------

    if (normalizedUsername == null) {
      data['username'] = FieldValue.delete();
      data['normalizedUsername'] = FieldValue.delete();
      data['usernameLowercase'] = FieldValue.delete();
    } else {
      data['username'] = normalizedUsername;
      data['normalizedUsername'] = normalizedUsername;
      data['usernameLowercase'] = normalizedUsername;
    }

    // ---------------------------------------------------------
    // JR CALL ID/address
    // ---------------------------------------------------------

    if (normalizedUserAddress == null) {
      data['userAddress'] = FieldValue.delete();
      data['normalizedUserAddress'] = FieldValue.delete();
      data['jrCallUserId'] = FieldValue.delete();
      data['jrCallUserIdLowercase'] = FieldValue.delete();
    } else {
      data['userAddress'] = normalizedUserAddress;
      data['normalizedUserAddress'] = normalizedUserAddress;
      data['jrCallUserId'] = normalizedUserAddress;
      data['jrCallUserIdLowercase'] = normalizedUserAddress;
    }

    // ---------------------------------------------------------
    // Media compatibility
    // ---------------------------------------------------------

    final profilePhoto = user.photoUrl?.trim();

    if (profilePhoto == null || profilePhoto.isEmpty) {
      data.remove('profilePhotoUrl');
    } else {
      data['profilePhotoUrl'] = profilePhoto;
    }

    final coverPhoto = user.coverPhoto?.trim();

    if (coverPhoto == null || coverPhoto.isEmpty) {
      data.remove('coverPhotoUrl');
      data.remove('backgroundPhotoUrl');
    } else {
      data['coverPhotoUrl'] = coverPhoto;
      data['backgroundPhotoUrl'] = coverPhoto;
    }

    // ---------------------------------------------------------
    // Discoverability defaults
    // ---------------------------------------------------------

    if (!existingDocument) {
      data.putIfAbsent('isDiscoverable', () => true);
      data.putIfAbsent('isDiscoverableByEmail', () => true);
      data.putIfAbsent('isDiscoverableByPhone', () => true);
    }

    data.removeWhere((key, value) => value == null);

    if (existingDocument) {
      data.remove('createdAt');
    } else {
      data['createdAt'] = Timestamp.fromDate(user.createdAt);
    }

    data['updatedAt'] = FieldValue.serverTimestamp();

    return data;
  }

  // ===========================================================
  // Reservation Document
  // ===========================================================

  Map<String, dynamic> _reservationDocument({
    required String uid,
    required String value,
    required bool existing,
  }) {
    return <String, dynamic>{
      'uid': uid,
      'value': value,
      if (!existing) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  // ===========================================================
  // Reservation Availability
  // ===========================================================

  void _ensureReservationAvailable({
    required DocumentSnapshot<Map<String, dynamic>>? snapshot,
    required String uid,
    required String fieldName,
    required String? value,
  }) {
    if (snapshot == null || !snapshot.exists) {
      return;
    }

    final ownerUid = _cleanString(snapshot.data()?['uid']);

    if (ownerUid == uid) {
      return;
    }

    throw StateError('$fieldName "$value" is already in use.');
  }

  // ===========================================================
  // Safe Reservation Delete
  // ===========================================================

  void _deleteReservationIfOwned({
    required Transaction transaction,
    required DocumentReference<Map<String, dynamic>>? reference,
    required DocumentSnapshot<Map<String, dynamic>>? snapshot,
    required String ownerUid,
  }) {
    if (reference == null || snapshot == null || !snapshot.exists) {
      return;
    }

    final reservationOwner = _cleanString(snapshot.data()?['uid']);

    if (reservationOwner != ownerUid) {
      return;
    }

    transaction.delete(reference);
  }

  // ===========================================================
  // Query Parsing
  // ===========================================================

  List<UserModel> _modelsFromQuery(
      QuerySnapshot<Map<String, dynamic>> snapshot, {
        String? excludeUid,
        bool requireDiscoverableEmail = false,
        bool requireDiscoverablePhone = false,
      }) {
    final normalizedExclude = excludeUid?.trim();
    final models = <UserModel>[];

    for (final document in snapshot.docs) {
      final data = document.data();

      if (!_isGenerallyDiscoverable(data)) {
        continue;
      }

      if (requireDiscoverableEmail &&
          !_isDiscoveryFlagAllowed(data['isDiscoverableByEmail'])) {
        continue;
      }

      if (requireDiscoverablePhone &&
          !_isDiscoveryFlagAllowed(data['isDiscoverableByPhone'])) {
        continue;
      }

      final model = _userModelFromDocument(
        documentId: document.id,
        data: data,
      );

      if (model.isDeleted || model.isBlocked || model.uid.trim().isEmpty) {
        continue;
      }

      if (normalizedExclude != null &&
          normalizedExclude.isNotEmpty &&
          model.uid == normalizedExclude) {
        continue;
      }

      models.add(model);
    }

    return List<UserModel>.unmodifiable(models);
  }

  void _addQueryModels(
      Map<String, UserModel> results,
      QuerySnapshot<Map<String, dynamic>> snapshot, {
        required int limit,
        String? excludeUid,
        bool requireDiscoverableEmail = false,
        bool requireDiscoverablePhone = false,
      }) {
    if (results.length >= limit) {
      return;
    }

    final models = _modelsFromQuery(
      snapshot,
      excludeUid: excludeUid,
      requireDiscoverableEmail: requireDiscoverableEmail,
      requireDiscoverablePhone: requireDiscoverablePhone,
    );

    for (final model in models) {
      if (results.length >= limit) {
        break;
      }

      _addSearchModel(results, model, excludeUid: excludeUid);
    }
  }

  UserModel _userModelFromDocument({
    required String documentId,
    required Map<String, dynamic> data,
  }) {
    final normalized = Map<String, dynamic>.from(data);

    final storedUid = _cleanString(normalized['uid']);

    if (storedUid == null) {
      normalized['uid'] = documentId;
    }

    normalized['name'] ??= normalized['fullName'];
    normalized['phone'] ??= normalized['phoneNumber'];
    normalized['userAddress'] ??= normalized['jrCallUserId'];
    normalized['photoUrl'] ??= normalized['profilePhotoUrl'];

    normalized['coverPhoto'] ??=
        normalized['coverPhotoUrl'] ?? normalized['backgroundPhotoUrl'];

    return UserModel.fromMap(normalized);
  }

  bool _isGenerallyDiscoverable(Map<String, dynamic> data) {
    if (data['isDiscoverable'] == false) {
      return false;
    }

    if (_readBool(data['isDeleted'])) {
      return false;
    }

    if (_readBool(data['isBlocked'])) {
      return false;
    }

    return true;
  }

  bool _isDiscoveryFlagAllowed(Object? value) {
    if (value == null) {
      // Legacy records did not always contain the dedicated flag.
      return true;
    }

    return _readBool(value);
  }

  // ===========================================================
  // Search Result Helper
  // ===========================================================

  void _addSearchModel(
      Map<String, UserModel> results,
      UserModel model, {
        String? excludeUid,
      }) {
    final uid = model.uid.trim();

    if (uid.isEmpty || model.isDeleted || model.isBlocked) {
      return;
    }

    if (excludeUid != null && excludeUid.isNotEmpty && uid == excludeUid) {
      return;
    }

    results[uid] = model;
  }

  // ===========================================================
  // Optional String Helpers
  // ===========================================================

  void _applyOptionalString(
      Map<String, dynamic> updates, {
        required String field,
        required String value,
      }) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      updates[field] = FieldValue.delete();
    } else {
      updates[field] = normalized;
    }
  }

  void _applyMirroredOptionalString(
      Map<String, dynamic> updates, {
        required String primaryField,
        required String compatibilityField,
        required String value,
      }) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      updates[primaryField] = FieldValue.delete();
      updates[compatibilityField] = FieldValue.delete();
    } else {
      updates[primaryField] = normalized;
      updates[compatibilityField] = normalized;
    }
  }

  // ===========================================================
  // UID Validation
  // ===========================================================

  String _requireUid(String uid) {
    final normalized = uid.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'User UID cannot be empty.');
    }

    return normalized;
  }

  // ===========================================================
  // Username Normalization
  // ===========================================================

  String? _normalizeUsername(Object? value) {
    if (value is! String) {
      return null;
    }

    var normalized = value.trim().toLowerCase();

    if (normalized.startsWith('@')) {
      normalized = normalized.substring(1);
    }

    return normalized.isEmpty ? null : normalized;
  }

  // ===========================================================
  // JR CALL Address Normalization
  // ===========================================================

  String? _normalizeUserAddress(Object? value) {
    if (value is! String) {
      return null;
    }

    var normalized = value.trim().toLowerCase();

    if (normalized.startsWith('@')) {
      normalized = normalized.substring(1);
    }

    return normalized.isEmpty ? null : normalized;
  }

  // ===========================================================
  // Phone Search Normalization
  // ===========================================================

  String _normalizePhoneForSearch(String phone) {
    final value = phone.trim();

    if (value.isEmpty) {
      return '';
    }

    final bool hasLeadingPlus = value.startsWith('+');
    final String digits = _digitsOnlyPhone(value);

    if (digits.isEmpty) {
      return '';
    }

    return hasLeadingPlus ? '+$digits' : digits;
  }

  String _digitsOnlyPhone(String phone) {
    return phone.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Generates only exact representations that can safely be derived
  /// without guessing a country or changing numbering semantics.
  ///
  /// Examples:
  /// +880 17-1234-5678
  /// -> +8801712345678
  /// -> 8801712345678
  ///
  /// 01712 345678
  /// -> 01712345678
  ///
  /// If the app has previously stored both local and E.164 forms,
  /// syncAuthenticationProfile preserves both through arrayUnion.
  List<String> _phoneSearchKeys(String phone) {
    final String trimmed = phone.trim();

    if (trimmed.isEmpty) {
      return const <String>[];
    }

    final Set<String> values = <String>{};

    final String normalized = _normalizePhoneForSearch(trimmed);
    final String digits = _digitsOnlyPhone(trimmed);

    if (normalized.isNotEmpty) {
      values.add(normalized);
    }

    if (digits.isNotEmpty) {
      values.add(digits);
    }

    if (trimmed.startsWith('+') && digits.isNotEmpty) {
      values.add('+$digits');
    }

    return List<String>.unmodifiable(values);
  }

  bool _looksLikePhone(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\s()+\-]'), '');

    return cleaned.length >= 6 && RegExp(r'^[0-9]+$').hasMatch(cleaned);
  }

  // ===========================================================
  // Username Validation
  // ===========================================================

  void _validateUsername(String? username) {
    if (username == null) {
      return;
    }

    if (!_usernamePattern.hasMatch(username)) {
      throw ArgumentError(
        'Username must be 3-30 characters and may contain '
            'lowercase letters, numbers, dots, and underscores.',
      );
    }

    if (username.startsWith('.') ||
        username.endsWith('.') ||
        username.contains('..')) {
      throw ArgumentError(
        'Username cannot start/end with a dot '
            'or contain consecutive dots.',
      );
    }
  }

  // ===========================================================
  // JR CALL Address Validation
  // ===========================================================

  void _validateUserAddress(String? userAddress) {
    if (userAddress == null) {
      return;
    }

    if (!_userAddressPattern.hasMatch(userAddress)) {
      throw ArgumentError(
        'User address must be 3-64 characters and may contain '
            'lowercase letters, numbers, dots, underscores, and hyphens.',
      );
    }

    if (userAddress.startsWith('.') ||
        userAddress.endsWith('.') ||
        userAddress.contains('..')) {
      throw ArgumentError(
        'User address cannot start/end with a dot '
            'or contain consecutive dots.',
      );
    }
  }

  // ===========================================================
  // General Profile Validation
  // ===========================================================

  void _validateProfileInput({
    String? name,
    String? phone,
    String? email,
    String? photoUrl,
    String? coverPhoto,
    String? bio,
    String? country,
    String? countryCode,
    String? gender,
    String? provider,
    String? deviceToken,
    DateTime? dateOfBirth,
  }) {
    if (name != null && name.trim().length > 80) {
      throw ArgumentError('Full name cannot exceed 80 characters.');
    }

    if (phone != null && phone.trim().length > 32) {
      throw ArgumentError('Phone number is too long.');
    }

    if (email != null) {
      final normalized = email.trim();

      if (normalized.length > 254) {
        throw ArgumentError('Email address is too long.');
      }

      if (normalized.isNotEmpty) {
        _validateEmail(normalized);
      }
    }

    if (bio != null && bio.trim().length > 300) {
      throw ArgumentError('Bio cannot exceed 300 characters.');
    }

    if (country != null && country.trim().length > 80) {
      throw ArgumentError('Country cannot exceed 80 characters.');
    }

    if (countryCode != null) {
      final normalized = countryCode.trim();

      if (normalized.length > 8) {
        throw ArgumentError('Country code is invalid.');
      }
    }

    if (gender != null && gender.trim().length > 40) {
      throw ArgumentError('Gender value is too long.');
    }

    if (provider != null && provider.trim().length > 80) {
      throw ArgumentError('Provider value is too long.');
    }

    if (deviceToken != null && deviceToken.trim().length > 4096) {
      throw ArgumentError('Device token is invalid.');
    }

    _validateUrlLength(photoUrl, fieldName: 'Profile photo URL');
    _validateUrlLength(coverPhoto, fieldName: 'Cover photo URL');

    if (dateOfBirth != null) {
      final today = _dateOnly(DateTime.now());
      final birthDate = _dateOnly(dateOfBirth);

      if (birthDate.isAfter(today)) {
        throw ArgumentError('Date of birth cannot be in the future.');
      }

      if (birthDate.year < 1900) {
        throw ArgumentError('Date of birth is invalid.');
      }
    }
  }

  void _validateEmail(String value) {
    if (!_basicEmailPattern.hasMatch(value.trim())) {
      throw ArgumentError('Email address format is invalid.');
    }
  }

  void _validateUrlLength(String? value, {required String fieldName}) {
    if (value == null) {
      return;
    }

    final normalized = value.trim();

    if (normalized.length > 4096) {
      throw ArgumentError('$fieldName is too long.');
    }
  }

  // ===========================================================
  // Utility Helpers
  // ===========================================================

  int _safeSearchLimit(int value) {
    if (value < 1) {
      return 1;
    }

    if (value > _maximumSearchLimit) {
      return _maximumSearchLimit;
    }

    return value;
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  String? _cleanString(Object? value) {
    if (value is! String) {
      return null;
    }

    final normalized = value.trim();

    return normalized.isEmpty ? null : normalized;
  }

  bool _readBool(Object? value) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    if (value is String) {
      final normalized = value.trim().toLowerCase();

      return normalized == 'true' || normalized == '1';
    }

    return false;
  }
}

// ===========================================================
// END OF FILE
//
// FILE 02/05
//
// PHONE DISCOVERY REPAIRED:
// - phone / phoneNumber compatibility preserved
// - phoneNormalized preserved
// - phoneDigits added as safe compatibility index
// - phoneSearchKeys added for exact multi-format lookup
// - Auth E.164 sync preserves earlier legitimate search forms
// - Legacy phoneNormalized / phoneNumber / phone queried as fallback
// - Name/Username/JR ID/Email logic preserved
// - Firebase UID semantics unchanged
// - No country hardcoding
// - No full users collection download
// - No Call Engine/WebRTC change
//
// SAVE THIS FILE.
//
// REMAINING MAIN FILES: 3
//
// NEXT FILE: profile_service.dart
// Location: lib/services/profile_service.dart
// ===========================================================