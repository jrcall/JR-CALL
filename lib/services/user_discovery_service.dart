// ===============================================================
// JR CALL
// File: user_discovery_service.dart
// Location: lib/services/user_discovery_service.dart
// Fixes: PHONE DISCOVERY / BUG 03
//
// Production-safe replacement
// Existing public APIs preserved
//
// FIXED IN THIS FILE:
// - 017... local phone search now reaches phone discovery.
// - Formatted local numbers are normalized safely.
// - International +E.164 numbers remain supported.
// - Legacy phone / phoneNumber / phoneNormalized fields preserved.
// - No Bangladesh hardcode.
// - No full users collection download.
// - Name / Username / JR CALL ID / Email logic preserved.
// - Firebase UID remains canonical Call/Message identity.
// - Privacy flags preserved.
// ===============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ===============================================================
// SEARCH TYPE
// ===============================================================

enum DiscoverySearchType { automatic, jrCallId, username, name, email, phone }

// ===============================================================
// DISCOVERY USER
// ===============================================================

class DiscoveryUser {
  const DiscoveryUser({
    required this.uid,
    required this.fullName,
    required this.username,
    required this.jrCallUserId,
    required this.profilePhotoUrl,
    required this.coverPhotoUrl,
    required this.country,
    required this.countryCode,
    required this.bio,
    required this.email,
    required this.phoneNumber,
    required this.online,
    required this.verified,
    required this.isDiscoverable,
    required this.isDiscoverableByEmail,
    required this.isDiscoverableByPhone,
  });

  /// Firebase Authentication UID.
  ///
  /// This is the canonical internal identity that must be passed
  /// into Call / Message / internal account operations.
  final String uid;

  final String fullName;
  final String? username;
  final String? jrCallUserId;

  final String? profilePhotoUrl;
  final String? coverPhotoUrl;
  final String? country;
  final String? countryCode;
  final String? bio;

  /// Exposed only when [isDiscoverableByEmail] is true.
  final String? email;

  /// Exposed only when [isDiscoverableByPhone] is true.
  final String? phoneNumber;

  final bool online;
  final bool verified;

  final bool isDiscoverable;
  final bool isDiscoverableByEmail;
  final bool isDiscoverableByPhone;

  bool get hasUsername => _cleanString(username) != null;

  bool get hasJrCallUserId => _cleanString(jrCallUserId) != null;

  bool get hasProfilePhoto => _cleanString(profilePhotoUrl) != null;

  bool get hasCoverPhoto => _cleanString(coverPhotoUrl) != null;

  bool get hasBio => _cleanString(bio) != null;

  String get displayName {
    final String cleanName = fullName.trim();

    if (cleanName.isNotEmpty) {
      return cleanName;
    }

    final String? cleanUsername = _cleanString(username);

    if (cleanUsername != null) {
      return cleanUsername;
    }

    final String? cleanJrCallId = _cleanString(jrCallUserId);

    if (cleanJrCallId != null) {
      return cleanJrCallId;
    }

    return 'JR CALL User';
  }

  String? get usernameLabel {
    final String? value = _cleanString(username);

    if (value == null) {
      return null;
    }

    return value.startsWith('@') ? value : '@$value';
  }

  String? get publicIdentityLabel {
    final String? jrId = _cleanString(jrCallUserId);

    if (jrId != null) {
      return jrId;
    }

    return usernameLabel;
  }

  // =============================================================
  // FIRESTORE
  // =============================================================

  factory DiscoveryUser.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return DiscoveryUser.fromMap(
      document.data() ?? const <String, dynamic>{},
      documentId: document.id,
    );
  }

  factory DiscoveryUser.fromMap(
    Map<String, dynamic> data, {
    String? documentId,
  }) {
    final String fallbackUid = documentId?.trim() ?? '';

    final String uid =
        _firstNonEmptyString(<Object?>[
          data['uid'],
          data['userId'],
          fallbackUid,
        ]) ??
        fallbackUid;

    final String fullName =
        _firstNonEmptyString(<Object?>[
          data['fullName'],
          data['name'],
          data['displayName'],
        ]) ??
        '';

    final String? username = _firstNonEmptyString(<Object?>[
      data['username'],
      data['shortName'],
    ]);

    final String? jrCallUserId = _firstNonEmptyString(<Object?>[
      data['jrCallUserId'],
      data['userAddress'],
      data['jrCallId'],
    ]);

    final String? profilePhotoUrl = _firstNonEmptyString(<Object?>[
      data['profilePhotoUrl'],
      data['photoUrl'],
      data['photoURL'],
    ]);

    final String? coverPhotoUrl = _firstNonEmptyString(<Object?>[
      data['coverPhotoUrl'],
      data['coverPhoto'],
      data['backgroundPhotoUrl'],
    ]);

    final String? country = _firstNonEmptyString(<Object?>[data['country']]);

    final String? countryCode = _firstNonEmptyString(<Object?>[
      data['countryCode'],
    ]);

    final String? bio = _firstNonEmptyString(<Object?>[data['bio']]);

    final bool isDiscoverable = _readBool(data['isDiscoverable']) ?? true;

    final bool isDiscoverableByEmail =
        _readBool(data['isDiscoverableByEmail']) ?? false;

    final bool isDiscoverableByPhone =
        _readBool(data['isDiscoverableByPhone']) ?? false;

    final String? rawEmail = _firstNonEmptyString(<Object?>[
      data['email'],
      data['emailNormalized'],
    ]);

    final String? rawPhone = _firstNonEmptyString(<Object?>[
      data['phoneNumber'],
      data['phone'],
      data['phoneNormalized'],
    ]);

    final bool emailVerified = _readBool(data['emailVerified']) ?? false;

    final bool phoneVerified = _readBool(data['phoneVerified']) ?? false;

    final bool legacyVerified = _readBool(data['verified']) ?? false;

    return DiscoveryUser(
      uid: uid,
      fullName: fullName,
      username: username,
      jrCallUserId: jrCallUserId,
      profilePhotoUrl: profilePhotoUrl,
      coverPhotoUrl: coverPhotoUrl,
      country: country,
      countryCode: countryCode,
      bio: bio,
      email: isDiscoverableByEmail ? rawEmail : null,
      phoneNumber: isDiscoverableByPhone ? rawPhone : null,
      online: _readBool(data['online']) ?? false,
      verified: emailVerified || phoneVerified || legacyVerified,
      isDiscoverable: isDiscoverable,
      isDiscoverableByEmail: isDiscoverableByEmail,
      isDiscoverableByPhone: isDiscoverableByPhone,
    );
  }

  @override
  String toString() {
    return 'DiscoveryUser('
        'uid: $uid, '
        'displayName: $displayName, '
        'username: $username, '
        'jrCallUserId: $jrCallUserId'
        ')';
  }

  static String? _cleanString(String? value) {
    final String normalized = value?.trim() ?? '';

    return normalized.isEmpty ? null : normalized;
  }
}

// ===============================================================
// PAGINATED RESULT
// ===============================================================

class DiscoveryPage {
  const DiscoveryPage({
    required this.users,
    required this.hasMore,
    this.nextCursor,
  });

  final List<DiscoveryUser> users;
  final bool hasMore;

  final DocumentSnapshot<Map<String, dynamic>>? nextCursor;

  static const DiscoveryPage empty = DiscoveryPage(
    users: <DiscoveryUser>[],
    hasMore: false,
  );
}

// ===============================================================
// USER DISCOVERY SERVICE
// ===============================================================

class UserDiscoveryService {
  UserDiscoveryService._();

  static final UserDiscoveryService instance = UserDiscoveryService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // =============================================================
  // COLLECTION CONTRACT
  // =============================================================

  static const String usersCollection = 'users';

  static const String usernamesCollection = 'usernames';

  /// Matches the existing FirestoreService reservation collection.
  static const String jrCallIdsCollection = 'user_addresses';

  static const String userAddressesCollection = jrCallIdsCollection;

  static const int defaultPageSize = 20;
  static const int maximumPageSize = 50;

  CollectionReference<Map<String, dynamic>> get _users {
    return _firestore.collection(usersCollection);
  }

  // =============================================================
  // MAIN SEARCH
  // =============================================================

  Future<DiscoveryPage> search(
    String value, {
    DiscoverySearchType type = DiscoverySearchType.automatic,
    int limit = defaultPageSize,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    bool excludeCurrentUser = true,
  }) async {
    final String query = value.trim();

    if (query.isEmpty) {
      return DiscoveryPage.empty;
    }

    final int safeLimit = _safeLimit(limit);

    switch (type) {
      case DiscoverySearchType.jrCallId:
        return _singleResultPage(
          await searchByJrCallId(query, excludeCurrentUser: excludeCurrentUser),
        );

      case DiscoverySearchType.username:
        return _singleResultPage(
          await searchByUsername(query, excludeCurrentUser: excludeCurrentUser),
        );

      case DiscoverySearchType.name:
        return searchByName(
          query,
          limit: safeLimit,
          cursor: cursor,
          excludeCurrentUser: excludeCurrentUser,
        );

      case DiscoverySearchType.email:
        return _singleResultPage(
          await searchByEmail(query, excludeCurrentUser: excludeCurrentUser),
        );

      case DiscoverySearchType.phone:
        return _singleResultPage(
          await searchByPhone(query, excludeCurrentUser: excludeCurrentUser),
        );

      case DiscoverySearchType.automatic:
        return _automaticSearch(
          query,
          limit: safeLimit,
          cursor: cursor,
          excludeCurrentUser: excludeCurrentUser,
        );
    }
  }

  // =============================================================
  // AUTOMATIC SEARCH
  // =============================================================

  Future<DiscoveryPage> _automaticSearch(
    String query, {
    required int limit,
    required DocumentSnapshot<Map<String, dynamic>>? cursor,
    required bool excludeCurrentUser,
  }) async {
    final String trimmed = query.trim();

    if (trimmed.isEmpty) {
      return DiscoveryPage.empty;
    }

    // -----------------------------------------------------------
    // Exact Email
    // -----------------------------------------------------------

    if (_looksLikeEmail(trimmed)) {
      final DiscoveryUser? emailUser = await searchByEmail(
        trimmed,
        excludeCurrentUser: excludeCurrentUser,
      );

      if (emailUser != null) {
        return _singleResultPage(emailUser);
      }
    }

    // -----------------------------------------------------------
    // Exact Phone
    //
    // IMPORTANT FIX:
    // Local numbers such as 017..., formatted numbers, and
    // international +numbers now enter phone discovery.
    // -----------------------------------------------------------

    if (_looksLikePhone(trimmed)) {
      final DiscoveryUser? phoneUser = await searchByPhone(
        trimmed,
        excludeCurrentUser: excludeCurrentUser,
      );

      if (phoneUser != null) {
        return _singleResultPage(phoneUser);
      }
    }

    // -----------------------------------------------------------
    // Explicit @username
    // -----------------------------------------------------------

    if (trimmed.startsWith('@')) {
      final DiscoveryUser? user = await searchByUsername(
        trimmed,
        excludeCurrentUser: excludeCurrentUser,
      );

      if (user != null) {
        return _singleResultPage(user);
      }
    }

    // -----------------------------------------------------------
    // Strong JR CALL ID pattern
    // -----------------------------------------------------------

    if (_looksLikeJrCallId(trimmed)) {
      final DiscoveryUser? user = await searchByJrCallId(
        trimmed,
        excludeCurrentUser: excludeCurrentUser,
      );

      if (user != null) {
        return _singleResultPage(user);
      }
    }

    // -----------------------------------------------------------
    // Exact Username
    // -----------------------------------------------------------

    final DiscoveryUser? usernameUser = await searchByUsername(
      trimmed,
      excludeCurrentUser: excludeCurrentUser,
    );

    if (usernameUser != null) {
      return _singleResultPage(usernameUser);
    }

    // -----------------------------------------------------------
    // Exact JR CALL ID
    // -----------------------------------------------------------

    final DiscoveryUser? jrCallUser = await searchByJrCallId(
      trimmed,
      excludeCurrentUser: excludeCurrentUser,
    );

    if (jrCallUser != null) {
      return _singleResultPage(jrCallUser);
    }

    // -----------------------------------------------------------
    // Full Name prefix
    // -----------------------------------------------------------

    return searchByName(
      trimmed,
      limit: limit,
      cursor: cursor,
      excludeCurrentUser: excludeCurrentUser,
    );
  }

  // =============================================================
  // EXACT JR CALL ID
  // =============================================================

  Future<DiscoveryUser?> searchByJrCallId(
    String value, {
    bool excludeCurrentUser = true,
  }) async {
    final String normalized = normalizeJrCallId(value);

    if (!isValidJrCallId(normalized)) {
      return null;
    }

    final String? reservedUid = await _resolveReservationUid(
      collection: jrCallIdsCollection,
      normalizedValue: normalized,
    );

    if (reservedUid != null) {
      final DiscoveryUser? reservedUser = await getUserByUid(
        reservedUid,
        excludeCurrentUser: excludeCurrentUser,
      );

      if (reservedUser != null &&
          normalizeJrCallId(reservedUser.jrCallUserId ?? '') == normalized) {
        return reservedUser;
      }
    }

    final DiscoveryUser? canonical = await _findExactUserByField(
      field: 'jrCallUserIdLowercase',
      value: normalized,
      excludeCurrentUser: excludeCurrentUser,
      compare: (DiscoveryUser user) {
        return normalizeJrCallId(user.jrCallUserId ?? '') == normalized;
      },
    );

    if (canonical != null) {
      return canonical;
    }

    final DiscoveryUser? normalizedAddress = await _findExactUserByField(
      field: 'normalizedUserAddress',
      value: normalized,
      excludeCurrentUser: excludeCurrentUser,
      compare: (DiscoveryUser user) {
        return normalizeJrCallId(user.jrCallUserId ?? '') == normalized;
      },
    );

    if (normalizedAddress != null) {
      return normalizedAddress;
    }

    final DiscoveryUser? legacyLowercase = await _findExactUserByField(
      field: 'userAddressLowercase',
      value: normalized,
      excludeCurrentUser: excludeCurrentUser,
      compare: (DiscoveryUser user) {
        return normalizeJrCallId(user.jrCallUserId ?? '') == normalized;
      },
    );

    if (legacyLowercase != null) {
      return legacyLowercase;
    }

    return _findExactUserByField(
      field: 'userAddress',
      value: normalized,
      excludeCurrentUser: excludeCurrentUser,
      compare: (DiscoveryUser user) {
        return normalizeJrCallId(user.jrCallUserId ?? '') == normalized;
      },
    );
  }

  // =============================================================
  // EXACT USERNAME
  // =============================================================

  Future<DiscoveryUser?> searchByUsername(
    String value, {
    bool excludeCurrentUser = true,
  }) async {
    final String normalized = normalizeUsername(value);

    if (!isValidUsername(normalized)) {
      return null;
    }

    final String? reservedUid = await _resolveReservationUid(
      collection: usernamesCollection,
      normalizedValue: normalized,
    );

    if (reservedUid != null) {
      final DiscoveryUser? reservedUser = await getUserByUid(
        reservedUid,
        excludeCurrentUser: excludeCurrentUser,
      );

      if (reservedUser != null &&
          normalizeUsername(reservedUser.username ?? '') == normalized) {
        return reservedUser;
      }
    }

    final DiscoveryUser? canonical = await _findExactUserByField(
      field: 'usernameLowercase',
      value: normalized,
      excludeCurrentUser: excludeCurrentUser,
      compare: (DiscoveryUser user) {
        return normalizeUsername(user.username ?? '') == normalized;
      },
    );

    if (canonical != null) {
      return canonical;
    }

    final DiscoveryUser? normalizedUsername = await _findExactUserByField(
      field: 'normalizedUsername',
      value: normalized,
      excludeCurrentUser: excludeCurrentUser,
      compare: (DiscoveryUser user) {
        return normalizeUsername(user.username ?? '') == normalized;
      },
    );

    if (normalizedUsername != null) {
      return normalizedUsername;
    }

    return _findExactUserByField(
      field: 'username',
      value: normalized,
      excludeCurrentUser: excludeCurrentUser,
      compare: (DiscoveryUser user) {
        return normalizeUsername(user.username ?? '') == normalized;
      },
    );
  }

  // =============================================================
  // FULL NAME PREFIX SEARCH
  // =============================================================

  Future<DiscoveryPage> searchByName(
    String value, {
    int limit = defaultPageSize,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    bool excludeCurrentUser = true,
  }) async {
    final String normalized = normalizeName(value);

    if (normalized.isEmpty) {
      return DiscoveryPage.empty;
    }

    final int safeLimit = _safeLimit(limit);

    final DiscoveryPage canonical = await _queryNameField(
      field: 'fullNameLowercase',
      normalized: normalized,
      limit: safeLimit,
      cursor: cursor,
      excludeCurrentUser: excludeCurrentUser,
    );

    if (canonical.users.isNotEmpty || canonical.hasMore || cursor != null) {
      return canonical;
    }

    final DiscoveryPage normalizedNamePage = await _queryNameField(
      field: 'normalizedName',
      normalized: normalized,
      limit: safeLimit,
      cursor: null,
      excludeCurrentUser: excludeCurrentUser,
    );

    if (normalizedNamePage.users.isNotEmpty || normalizedNamePage.hasMore) {
      return normalizedNamePage;
    }

    return _queryNameField(
      field: 'nameLowercase',
      normalized: normalized,
      limit: safeLimit,
      cursor: null,
      excludeCurrentUser: excludeCurrentUser,
    );
  }

  Future<DiscoveryPage> _queryNameField({
    required String field,
    required String normalized,
    required int limit,
    required DocumentSnapshot<Map<String, dynamic>>? cursor,
    required bool excludeCurrentUser,
  }) async {
    Query<Map<String, dynamic>> query = _users
        .orderBy(field)
        .startAt(<Object?>[normalized])
        .endAt(<Object?>['$normalized\uf8ff'])
        .limit(limit + 1);

    if (cursor != null) {
      query = query.startAfterDocument(cursor);
    }

    final QuerySnapshot<Map<String, dynamic>> snapshot = await query.get();

    if (snapshot.docs.isEmpty) {
      return DiscoveryPage.empty;
    }

    final List<DiscoveryUser> accepted = <DiscoveryUser>[];
    final Set<String> acceptedUids = <String>{};

    DocumentSnapshot<Map<String, dynamic>>? lastAcceptedDocument;

    bool extraAcceptedUserFound = false;

    for (final QueryDocumentSnapshot<Map<String, dynamic>> document
        in snapshot.docs) {
      final DiscoveryUser? user = _acceptedDiscoveryUser(
        document,
        excludeCurrentUser: excludeCurrentUser,
      );

      if (user == null) {
        continue;
      }

      final String uid = user.uid.trim();

      if (uid.isEmpty || !acceptedUids.add(uid)) {
        continue;
      }

      if (accepted.length >= limit) {
        extraAcceptedUserFound = true;
        break;
      }

      accepted.add(user);
      lastAcceptedDocument = document;
    }

    final bool serverReturnedExtra = snapshot.docs.length > limit;

    final bool hasMore = extraAcceptedUserFound || serverReturnedExtra;

    DocumentSnapshot<Map<String, dynamic>>? nextCursor;

    if (hasMore) {
      if (lastAcceptedDocument != null) {
        nextCursor = lastAcceptedDocument;
      } else if (snapshot.docs.isNotEmpty) {
        nextCursor = snapshot.docs.last;
      }
    }

    return DiscoveryPage(
      users: List<DiscoveryUser>.unmodifiable(accepted),
      hasMore: hasMore,
      nextCursor: nextCursor,
    );
  }

  // =============================================================
  // EXACT EMAIL
  // =============================================================

  Future<DiscoveryUser?> searchByEmail(
    String value, {
    bool excludeCurrentUser = true,
  }) async {
    final String normalized = normalizeEmail(value);

    if (!_isValidEmail(normalized)) {
      return null;
    }

    final DiscoveryUser? canonical = await _findExactUserByField(
      field: 'emailNormalized',
      value: normalized,
      excludeCurrentUser: excludeCurrentUser,
      compare: (DiscoveryUser user) {
        if (!user.isDiscoverableByEmail) {
          return false;
        }

        return normalizeEmail(user.email ?? '') == normalized;
      },
    );

    if (canonical != null) {
      return canonical;
    }

    return _findExactUserByField(
      field: 'email',
      value: normalized,
      excludeCurrentUser: excludeCurrentUser,
      compare: (DiscoveryUser user) {
        if (!user.isDiscoverableByEmail) {
          return false;
        }

        return normalizeEmail(user.email ?? '') == normalized;
      },
    );
  }

  // =============================================================
  // EXACT PHONE
  // =============================================================

  Future<DiscoveryUser?> searchByPhone(
    String value, {
    bool excludeCurrentUser = true,
  }) async {
    final List<String> candidates = _phoneSearchCandidates(value);

    if (candidates.isEmpty) {
      return null;
    }

    const List<String> searchableFields = <String>[
      'phoneNormalized',
      'phoneNumber',
      'phone',
    ];

    for (final String field in searchableFields) {
      for (final String candidate in candidates) {
        final DiscoveryUser? user = await _findExactUserByField(
          field: field,
          value: candidate,
          excludeCurrentUser: excludeCurrentUser,
          compare: (DiscoveryUser result) {
            if (!result.isDiscoverableByPhone) {
              return false;
            }

            final String? phone = result.phoneNumber;

            if (phone == null || phone.trim().isEmpty) {
              return false;
            }

            final Set<String> resultCandidates = _phoneSearchCandidates(
              phone,
            ).toSet();

            return candidates.any(resultCandidates.contains);
          },
        );

        if (user != null) {
          return user;
        }
      }
    }

    return null;
  }

  // =============================================================
  // UID LOOKUP
  // =============================================================

  Future<DiscoveryUser?> getUserByUid(
    String uid, {
    bool excludeCurrentUser = false,
  }) async {
    final String normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      return null;
    }

    final DocumentSnapshot<Map<String, dynamic>> document = await _users
        .doc(normalizedUid)
        .get();

    if (!document.exists) {
      return null;
    }

    return _acceptedDiscoveryUser(
      document,
      excludeCurrentUser: excludeCurrentUser,
    );
  }

  // =============================================================
  // PUBLIC IDENTITY -> FIREBASE UID
  // =============================================================

  Future<String?> resolveUid(
    String value, {
    DiscoverySearchType type = DiscoverySearchType.automatic,
  }) async {
    final DiscoveryPage result = await search(
      value,
      type: type,
      limit: 1,
      excludeCurrentUser: false,
    );

    if (result.users.isEmpty) {
      return null;
    }

    final String uid = result.users.first.uid.trim();

    return uid.isEmpty ? null : uid;
  }

  Future<DiscoveryUser?> resolveUser(
    String value, {
    DiscoverySearchType type = DiscoverySearchType.automatic,
    bool excludeCurrentUser = true,
  }) async {
    final DiscoveryPage result = await search(
      value,
      type: type,
      limit: 1,
      excludeCurrentUser: excludeCurrentUser,
    );

    return result.users.isEmpty ? null : result.users.first;
  }

  // =============================================================
  // EXACT FIELD QUERY
  // =============================================================

  Future<DiscoveryUser?> _findExactUserByField({
    required String field,
    required String value,
    required bool excludeCurrentUser,
    bool Function(DiscoveryUser user)? compare,
  }) async {
    if (field.trim().isEmpty || value.trim().isEmpty) {
      return null;
    }

    final QuerySnapshot<Map<String, dynamic>> snapshot = await _users
        .where(field, isEqualTo: value)
        .limit(5)
        .get();

    final Set<String> checkedUids = <String>{};

    for (final QueryDocumentSnapshot<Map<String, dynamic>> document
        in snapshot.docs) {
      final DiscoveryUser? user = _acceptedDiscoveryUser(
        document,
        excludeCurrentUser: excludeCurrentUser,
      );

      if (user == null) {
        continue;
      }

      final String uid = user.uid.trim();

      if (uid.isEmpty || !checkedUids.add(uid)) {
        continue;
      }

      if (compare != null && !compare(user)) {
        continue;
      }

      return user;
    }

    return null;
  }

  // =============================================================
  // RESERVATION LOOKUP
  // =============================================================

  Future<String?> _resolveReservationUid({
    required String collection,
    required String normalizedValue,
  }) async {
    final String collectionName = collection.trim();
    final String documentId = normalizedValue.trim();

    if (collectionName.isEmpty || documentId.isEmpty) {
      return null;
    }

    final DocumentSnapshot<Map<String, dynamic>> reservation = await _firestore
        .collection(collectionName)
        .doc(documentId)
        .get();

    if (!reservation.exists) {
      return null;
    }

    final Map<String, dynamic> data =
        reservation.data() ?? const <String, dynamic>{};

    return _firstNonEmptyString(<Object?>[
      data['uid'],
      data['ownerUid'],
      data['userId'],
    ]);
  }

  // =============================================================
  // PRIVACY / ACCOUNT FILTER
  // =============================================================

  DiscoveryUser? _acceptedDiscoveryUser(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required bool excludeCurrentUser,
  }) {
    if (!document.exists) {
      return null;
    }

    final Map<String, dynamic> data =
        document.data() ?? const <String, dynamic>{};

    if (_readBool(data['isDeleted']) == true) {
      return null;
    }

    if (_readBool(data['isBlocked']) == true) {
      return null;
    }

    final DiscoveryUser user = DiscoveryUser.fromDocument(document);

    final String uid = user.uid.trim();

    if (uid.isEmpty) {
      return null;
    }

    if (!user.isDiscoverable) {
      return null;
    }

    final String currentUid = _auth.currentUser?.uid.trim() ?? '';

    if (excludeCurrentUser && currentUid.isNotEmpty && currentUid == uid) {
      return null;
    }

    return user;
  }

  // =============================================================
  // NORMALIZATION
  // =============================================================

  String normalizeJrCallId(String value) {
    String normalized = value.trim().toLowerCase();

    if (normalized.startsWith('@')) {
      normalized = normalized.substring(1);
    }

    return normalized.trim();
  }

  String normalizeUsername(String value) {
    String normalized = value.trim().toLowerCase();

    if (normalized.startsWith('@')) {
      normalized = normalized.substring(1);
    }

    return normalized.trim();
  }

  String normalizeName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String normalizeEmail(String value) {
    return value.trim().toLowerCase();
  }

  /// Preserves the previous public normalization API.
  ///
  /// Examples:
  /// +880 1756-660774 -> +8801756660774
  /// 01756-660774     -> 01756660774
  String normalizePhone(String value) {
    final String trimmed = value.trim();

    if (trimmed.isEmpty) {
      return '';
    }

    final bool hasLeadingPlus = trimmed.startsWith('+');

    final String digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) {
      return '';
    }

    return hasLeadingPlus ? '+$digits' : digits;
  }

  // =============================================================
  // PHONE SEARCH NORMALIZATION
  // =============================================================

  List<String> _phoneSearchCandidates(String value) {
    final String trimmed = value.trim();

    if (trimmed.isEmpty) {
      return const <String>[];
    }

    final String normalized = normalizePhone(trimmed);

    if (!_isValidPhoneQuery(normalized)) {
      return const <String>[];
    }

    final Set<String> candidates = <String>{normalized};

    final String digitsOnly = normalized.replaceAll(RegExp(r'[^0-9]'), '');

    if (digitsOnly.isNotEmpty) {
      candidates.add(digitsOnly);
    }

    // Preserve exact legacy formatted storage as a fallback.
    //
    // This does not replace phoneNormalized; it only allows an
    // older document whose phone/phoneNumber was stored exactly
    // in the entered representation to remain discoverable.
    if (trimmed != normalized) {
      candidates.add(trimmed);
    }

    return List<String>.unmodifiable(candidates);
  }

  // =============================================================
  // PUBLIC VALIDATION
  // =============================================================

  bool isValidUsername(String value) {
    final String normalized = normalizeUsername(value);

    if (!RegExp(r'^[a-z0-9._]{3,30}$').hasMatch(normalized)) {
      return false;
    }

    if (normalized.startsWith('.') ||
        normalized.endsWith('.') ||
        normalized.contains('..')) {
      return false;
    }

    return true;
  }

  bool isValidJrCallId(String value) {
    final String normalized = normalizeJrCallId(value);

    if (!RegExp(r'^[a-z0-9._-]{3,64}$').hasMatch(normalized)) {
      return false;
    }

    if (normalized.startsWith('.') ||
        normalized.endsWith('.') ||
        normalized.contains('..')) {
      return false;
    }

    return true;
  }

  bool isValidEmail(String value) {
    return _isValidEmail(normalizeEmail(value));
  }

  /// Accepts both:
  /// - international +number representation
  /// - local/searchable digit representation
  ///
  /// Country conversion is intentionally NOT guessed here.
  bool isValidPhone(String value) {
    return _isValidPhoneQuery(normalizePhone(value));
  }

  // =============================================================
  // INTERNAL VALIDATION
  // =============================================================

  bool _isValidEmail(String value) {
    if (value.isEmpty || value.length > 254) {
      return false;
    }

    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);
  }

  bool _isValidE164Phone(String value) {
    return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value);
  }

  bool _isValidLocalPhone(String value) {
    if (!RegExp(r'^\d{6,15}$').hasMatch(value)) {
      return false;
    }

    return true;
  }

  bool _isValidPhoneQuery(String value) {
    if (value.isEmpty) {
      return false;
    }

    if (value.startsWith('+')) {
      return _isValidE164Phone(value);
    }

    return _isValidLocalPhone(value);
  }

  bool _looksLikeEmail(String value) {
    return _isValidEmail(normalizeEmail(value));
  }

  bool _looksLikePhone(String value) {
    final String normalized = normalizePhone(value);

    return _isValidPhoneQuery(normalized);
  }

  bool _looksLikeJrCallId(String value) {
    final String normalized = normalizeJrCallId(value);

    return normalized.startsWith('jrcall_') ||
        normalized.startsWith('jr_call_');
  }

  // =============================================================
  // HELPERS
  // =============================================================

  int _safeLimit(int value) {
    if (value < 1) {
      return 1;
    }

    if (value > maximumPageSize) {
      return maximumPageSize;
    }

    return value;
  }

  DiscoveryPage _singleResultPage(DiscoveryUser? user) {
    if (user == null) {
      return DiscoveryPage.empty;
    }

    return DiscoveryPage(
      users: List<DiscoveryUser>.unmodifiable(<DiscoveryUser>[user]),
      hasMore: false,
    );
  }
}

// ===============================================================
// SHARED SAFE PARSING
// ===============================================================

String? _firstNonEmptyString(Iterable<Object?> values) {
  for (final Object? value in values) {
    if (value is! String) {
      continue;
    }

    final String normalized = value.trim();

    if (normalized.isNotEmpty) {
      return normalized;
    }
  }

  return null;
}

bool? _readBool(Object? value) {
  if (value is bool) {
    return value;
  }

  if (value is num) {
    if (value == 1) {
      return true;
    }

    if (value == 0) {
      return false;
    }
  }

  if (value is String) {
    final String normalized = value.trim().toLowerCase();

    switch (normalized) {
      case 'true':
      case '1':
      case 'yes':
      case 'y':
        return true;

      case 'false':
      case '0':
      case 'no':
      case 'n':
        return false;
    }
  }

  return null;
}

// ===============================================================
// END OF FILE
//
// FIXED:
// - Local phone number such as 017... is no longer rejected.
// - Formatted phone input is normalized before exact search.
// - +international phone search remains supported.
// - phoneNormalized / phoneNumber / phone legacy fields checked.
// - Phone privacy remains enforced.
// - Firebase UID remains canonical resolved identity.
// - Existing Name / Username / JR ID / Email discovery preserved.
// - No country hardcoding.
// - No full users collection download.
//
// STATUS: READY FOR FORMAT + ANALYZE
//
// RUN:
// dart format lib/services/user_discovery_service.dart
// flutter analyze
//
// FILE 01: COMPLETE AFTER ANALYZER PASSES
// REMAINING MAIN FILES: 4
//
// NEXT FILE: firestore_service.dart
// Location: lib/services/firebase/firestore_service.dart
// ===============================================================
