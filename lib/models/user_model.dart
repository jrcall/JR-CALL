import 'package:cloud_firestore/cloud_firestore.dart';

/// ===========================================================
/// JR CALL
/// File: user_model.dart
/// Location: lib/models/user_model.dart
/// Master Step: 23
///
/// PURPOSE:
/// Canonical production JR CALL user/profile model.
///
/// IMPORTANT:
/// - Firebase UID = private canonical identity.
/// - JR CALL User ID = public searchable identity.
/// - Email is NEVER automatically used as JR CALL User ID.
/// - Password/OTP/auth secrets are NEVER stored here.
/// - Legacy Firestore documents remain readable.
/// - Current FirestoreService APIs remain compatible.
/// ===========================================================
class UserModel {
  // ===========================================================
  // PRIVATE CANONICAL IDENTITY
  // ===========================================================

  /// Firebase Authentication UID.
  final String uid;

  // ===========================================================
  // LEGACY + CANONICAL PROFILE IDENTITY
  // ===========================================================

  /// Legacy field.
  ///
  /// Canonical alias: [fullName].
  final String name;

  /// Legacy field.
  ///
  /// Canonical alias: [phoneNumber].
  final String phone;

  final String? email;

  // ===========================================================
  // PUBLIC JR CALL IDENTITY
  // ===========================================================

  final String? username;

  /// Legacy public JR CALL address.
  ///
  /// Canonical alias: [jrCallUserId].
  final String? userAddress;

  // ===========================================================
  // PROFILE
  // ===========================================================

  /// Legacy profile image field.
  ///
  /// Canonical alias: [profilePhotoUrl].
  final String? photoUrl;

  /// Legacy cover image field.
  ///
  /// Canonical alias: [coverPhotoUrl].
  final String? coverPhoto;

  final String? bio;

  final String? country;

  final String? countryCode;

  /// Preserved for legacy compatibility.
  final String? gender;

  final DateTime? dateOfBirth;

  // ===========================================================
  // VERIFICATION
  // ===========================================================

  /// Legacy account-level flag.
  final bool verified;

  final bool emailVerified;

  final bool phoneVerified;

  // ===========================================================
  // AUTH PROVIDERS
  // ===========================================================

  /// Legacy single-provider field.
  final String? provider;

  final List<String> signInProviders;

  // ===========================================================
  // DISCOVERY / PRIVACY
  // ===========================================================

  final bool isDiscoverable;

  final bool isDiscoverableByEmail;

  final bool isDiscoverableByPhone;

  // ===========================================================
  // PRESENCE / RUNTIME
  // ===========================================================

  final bool online;

  final String? deviceToken;

  final DateTime createdAt;

  final DateTime? updatedAt;

  final DateTime? lastSeen;

  final DateTime? lastLogin;

  // ===========================================================
  // ACCOUNT STATE
  // ===========================================================

  final bool isBlocked;

  final bool isDeleted;

  // ===========================================================
  // CONSTRUCTOR
  // ===========================================================

  const UserModel({
    required this.uid,
    required this.name,
    required this.phone,
    required this.createdAt,
    this.email,
    this.username,
    this.userAddress,
    this.photoUrl,
    this.coverPhoto,
    this.bio,
    this.country,
    this.countryCode,
    this.gender,
    this.dateOfBirth,
    this.online = false,
    this.verified = false,
    this.emailVerified = false,
    this.phoneVerified = false,
    this.provider,
    this.signInProviders = const <String>[],
    this.isDiscoverable = true,
    this.isDiscoverableByEmail = false,
    this.isDiscoverableByPhone = false,
    this.updatedAt,
    this.lastSeen,
    this.lastLogin,
    this.deviceToken,
    this.isBlocked = false,
    this.isDeleted = false,
  });

  // ===========================================================
  // CANONICAL ALIASES
  // ===========================================================

  String get fullName => name;

  String get displayName => name;

  String get phoneNumber => phone;

  String? get jrCallUserId => userAddress;

  String? get profilePhotoUrl => photoUrl;

  String? get coverPhotoUrl => coverPhoto;

  String? get backgroundPhotoUrl => coverPhoto;

  // ===========================================================
  // NORMALIZED SEARCH VALUES
  // ===========================================================

  String get fullNameLowercase => _normalizeSearchText(name);

  String get normalizedName => fullNameLowercase;

  String? get usernameLowercase {
    final String? value = _cleanNullableString(username);

    if (value == null) {
      return null;
    }

    return _normalizeUsernameValue(value);
  }

  String? get normalizedUsername => usernameLowercase;

  String? get jrCallUserIdLowercase {
    final String? value = _cleanNullableString(userAddress);

    if (value == null) {
      return null;
    }

    return _normalizeUserAddressValue(value);
  }

  String? get normalizedUserAddress => jrCallUserIdLowercase;

  String? get emailNormalized {
    return _cleanNullableString(email)?.toLowerCase();
  }

  String? get phoneNormalized {
    final String? value = _cleanNullableString(phone);

    if (value == null) {
      return null;
    }

    final String normalized = _normalizePhone(value);

    return normalized.isEmpty ? null : normalized;
  }

  // ===========================================================
  // PROVIDER HELPERS
  // ===========================================================

  List<String> get effectiveSignInProviders {
    final List<String> providers = _normalizeProviders(signInProviders);

    if (providers.isNotEmpty) {
      return providers;
    }

    final String? legacy = _cleanNullableString(provider);

    if (legacy == null) {
      return const <String>[];
    }

    return List<String>.unmodifiable(<String>[legacy]);
  }

  bool hasProvider(String providerId) {
    final String normalized = providerId.trim();

    if (normalized.isEmpty) {
      return false;
    }

    return effectiveSignInProviders.any((String value) => value == normalized);
  }

  // ===========================================================
  // PROFILE STATE
  // ===========================================================

  bool get hasFullName => name.trim().isNotEmpty;

  bool get hasProfilePhoto => _cleanNullableString(photoUrl) != null;

  bool get hasCoverPhoto => _cleanNullableString(coverPhoto) != null;

  bool get hasUsername => _cleanNullableString(username) != null;

  bool get hasUserAddress => _cleanNullableString(userAddress) != null;

  bool get hasJrCallUserId => hasUserAddress;

  bool get hasEmail => _cleanNullableString(email) != null;

  bool get hasPhoneNumber => _cleanNullableString(phone) != null;

  bool get hasCountry => _cleanNullableString(country) != null;

  bool get hasBio => _cleanNullableString(bio) != null;

  bool get hasDateOfBirth => dateOfBirth != null;

  bool get isAnyIdentityVerified => verified || emailVerified || phoneVerified;

  bool get isActive => !isBlocked && !isDeleted;

  /// Informational only.
  ///
  /// Account validity must NOT depend on this.
  bool get isProfileComplete {
    return hasJrCallUserId;
  }

  // ===========================================================
  // SERIALIZATION
  // ===========================================================

  Map<String, dynamic> toMap() {
    final String normalizedUid = uid.trim();

    final String normalizedName = name.trim();

    final String normalizedPhone = phone.trim();

    final String? cleanedEmail = _cleanNullableString(email)?.toLowerCase();

    final String? cleanedUsername = _normalizeUsernameNullable(username);

    final String? cleanedUserAddress = _normalizeUserAddressNullable(
      userAddress,
    );

    final String? cleanedPhoto = _cleanNullableString(photoUrl);

    final String? cleanedCover = _cleanNullableString(coverPhoto);

    final String? cleanedBio = _cleanNullableString(bio);

    final String? cleanedCountry = _cleanNullableString(country);

    final String? cleanedCountryCode = _cleanNullableString(
      countryCode,
    )?.toUpperCase();

    final String? cleanedGender = _cleanNullableString(gender);

    final String? cleanedDeviceToken = _cleanNullableString(deviceToken);

    final List<String> providers = _normalizeProviders(<String>[
      ...signInProviders,
      if (_cleanNullableString(provider) != null)
        _cleanNullableString(provider)!,
    ]);

    final String? legacyProvider =
        _cleanNullableString(provider) ??
        (providers.isEmpty ? null : providers.first);

    final String normalizedPhoneSearch = _normalizePhone(normalizedPhone);

    final Map<String, dynamic> map = <String, dynamic>{
      // -------------------------------------------------------
      // UID
      // -------------------------------------------------------
      'uid': normalizedUid,

      // -------------------------------------------------------
      // NAME
      // -------------------------------------------------------
      'name': normalizedName,

      'fullName': normalizedName,

      'normalizedName': _normalizeSearchText(normalizedName),

      'fullNameLowercase': _normalizeSearchText(normalizedName),

      // -------------------------------------------------------
      // PHONE
      // -------------------------------------------------------
      'phone': normalizedPhone,

      'phoneNumber': normalizedPhone,

      'phoneNormalized': normalizedPhoneSearch.isEmpty
          ? null
          : normalizedPhoneSearch,

      // -------------------------------------------------------
      // EMAIL
      // -------------------------------------------------------
      'email': cleanedEmail,

      'emailNormalized': cleanedEmail,

      // -------------------------------------------------------
      // USERNAME
      // -------------------------------------------------------
      'username': cleanedUsername,

      'normalizedUsername': cleanedUsername,

      'usernameLowercase': cleanedUsername,

      // -------------------------------------------------------
      // JR CALL PUBLIC ID
      // -------------------------------------------------------
      'userAddress': cleanedUserAddress,

      'normalizedUserAddress': cleanedUserAddress,

      'jrCallUserId': cleanedUserAddress,

      'jrCallUserIdLowercase': cleanedUserAddress,

      // -------------------------------------------------------
      // PROFILE MEDIA
      // -------------------------------------------------------
      'photoUrl': cleanedPhoto,

      'profilePhotoUrl': cleanedPhoto,

      'coverPhoto': cleanedCover,

      'coverPhotoUrl': cleanedCover,

      'backgroundPhotoUrl': cleanedCover,

      // -------------------------------------------------------
      // PROFILE INFORMATION
      // -------------------------------------------------------
      'bio': cleanedBio,

      'country': cleanedCountry,

      'countryCode': cleanedCountryCode,

      'gender': cleanedGender,

      'dateOfBirth': dateOfBirth == null
          ? null
          : Timestamp.fromDate(_dateOnly(dateOfBirth!)),

      // -------------------------------------------------------
      // VERIFICATION
      // -------------------------------------------------------
      'verified': verified,

      'emailVerified': emailVerified,

      'phoneVerified': phoneVerified,

      // -------------------------------------------------------
      // PROVIDERS
      // -------------------------------------------------------
      'provider': legacyProvider,

      'signInProviders': providers,

      // -------------------------------------------------------
      // DISCOVERY
      // -------------------------------------------------------
      'isDiscoverable': isDiscoverable,

      'isDiscoverableByEmail': isDiscoverableByEmail,

      'isDiscoverableByPhone': isDiscoverableByPhone,

      // -------------------------------------------------------
      // PRESENCE
      // -------------------------------------------------------
      'online': online,

      'deviceToken': cleanedDeviceToken,

      // -------------------------------------------------------
      // TIMESTAMPS
      // -------------------------------------------------------
      'createdAt': Timestamp.fromDate(createdAt),

      'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),

      'lastSeen': lastSeen == null ? null : Timestamp.fromDate(lastSeen!),

      'lastLogin': lastLogin == null ? null : Timestamp.fromDate(lastLogin!),

      // -------------------------------------------------------
      // ACCOUNT STATE
      // -------------------------------------------------------
      'isBlocked': isBlocked,

      'isDeleted': isDeleted,
    };

    map.removeWhere((String key, dynamic value) => value == null);

    return map;
  }

  // ===========================================================
  // FROM MAP
  // ===========================================================

  factory UserModel.fromMap(Map<String, dynamic> map) {
    final String uid = _readString(map['uid']) ?? '';

    final String name =
        _readString(map['name']) ??
        _readString(map['fullName']) ??
        _readString(map['displayName']) ??
        '';

    final String phone =
        _readString(map['phone']) ?? _readString(map['phoneNumber']) ?? '';

    final String? email = _readString(map['email']);

    final String? username = _readString(map['username']);

    final String? userAddress =
        _readString(map['userAddress']) ?? _readString(map['jrCallUserId']);

    final String? photoUrl =
        _readString(map['photoUrl']) ?? _readString(map['profilePhotoUrl']);

    final String? coverPhoto =
        _readString(map['coverPhoto']) ??
        _readString(map['coverPhotoUrl']) ??
        _readString(map['backgroundPhotoUrl']);

    final List<String> storedProviders = _readStringList(
      map['signInProviders'],
    );

    final String? storedProvider = _readString(map['provider']);

    final List<String> effectiveProviders = _normalizeProviders(<String>[
      ...storedProviders,
      ?storedProvider,
    ]);

    final String? effectiveProvider =
        storedProvider ??
        (effectiveProviders.isEmpty ? null : effectiveProviders.first);

    final DateTime createdAt =
        _readDateTime(map['createdAt']) ??
        _readDateTime(map['creationTime']) ??
        DateTime.now();

    final bool explicitEmailVerified = map.containsKey('emailVerified')
        ? _readBool(map['emailVerified'])
        : false;

    final bool explicitPhoneVerified = map.containsKey('phoneVerified')
        ? _readBool(map['phoneVerified'])
        : false;

    final bool legacyVerified = map.containsKey('verified')
        ? _readBool(map['verified'])
        : explicitEmailVerified || explicitPhoneVerified;

    return UserModel(
      uid: uid,
      name: name,
      phone: phone,
      email: email,
      username: username,
      userAddress: userAddress,
      photoUrl: photoUrl,
      coverPhoto: coverPhoto,
      bio: _readString(map['bio']),
      country: _readString(map['country']),
      countryCode: _readString(map['countryCode'])?.toUpperCase(),
      gender: _readString(map['gender']),
      dateOfBirth: _readDateTime(map['dateOfBirth']),
      online: _readBool(map['online']),
      verified: legacyVerified,
      emailVerified: explicitEmailVerified,
      phoneVerified: explicitPhoneVerified,
      provider: effectiveProvider,
      signInProviders: effectiveProviders,

      // Existing documents without explicit email/phone
      // discovery consent remain private for those fields.
      isDiscoverable: map.containsKey('isDiscoverable')
          ? _readBool(map['isDiscoverable'])
          : true,

      isDiscoverableByEmail: map.containsKey('isDiscoverableByEmail')
          ? _readBool(map['isDiscoverableByEmail'])
          : false,

      isDiscoverableByPhone: map.containsKey('isDiscoverableByPhone')
          ? _readBool(map['isDiscoverableByPhone'])
          : false,

      createdAt: createdAt,

      updatedAt: _readDateTime(map['updatedAt']),

      lastSeen: _readDateTime(map['lastSeen']),

      lastLogin: _readDateTime(map['lastLogin']),

      deviceToken: _readString(map['deviceToken']),

      isBlocked: _readBool(map['isBlocked']),

      isDeleted: _readBool(map['isDeleted']),
    );
  }

  // ===========================================================
  // FROM FIRESTORE
  // ===========================================================

  factory UserModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final Map<String, dynamic> data = Map<String, dynamic>.from(
      snapshot.data() ?? const <String, dynamic>{},
    );

    if (_readString(data['uid']) == null) {
      data['uid'] = snapshot.id;
    }

    return UserModel.fromMap(data);
  }

  // ===========================================================
  // COPY WITH
  // ===========================================================

  UserModel copyWith({
    String? uid,
    String? name,
    String? fullName,
    String? phone,
    String? phoneNumber,
    String? email,
    String? username,
    String? userAddress,
    String? jrCallUserId,
    String? photoUrl,
    String? profilePhotoUrl,
    String? coverPhoto,
    String? coverPhotoUrl,
    String? bio,
    String? country,
    String? countryCode,
    String? gender,
    DateTime? dateOfBirth,
    bool? online,
    bool? verified,
    bool? emailVerified,
    bool? phoneVerified,
    String? provider,
    List<String>? signInProviders,
    bool? isDiscoverable,
    bool? isDiscoverableByEmail,
    bool? isDiscoverableByPhone,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSeen,
    DateTime? lastLogin,
    String? deviceToken,
    bool? isBlocked,
    bool? isDeleted,
  }) {
    return UserModel(
      uid: uid ?? this.uid,

      name: fullName ?? name ?? this.name,

      phone: phoneNumber ?? phone ?? this.phone,

      email: email ?? this.email,

      username: username ?? this.username,

      userAddress: jrCallUserId ?? userAddress ?? this.userAddress,

      photoUrl: profilePhotoUrl ?? photoUrl ?? this.photoUrl,

      coverPhoto: coverPhotoUrl ?? coverPhoto ?? this.coverPhoto,

      bio: bio ?? this.bio,

      country: country ?? this.country,

      countryCode: countryCode ?? this.countryCode,

      gender: gender ?? this.gender,

      dateOfBirth: dateOfBirth ?? this.dateOfBirth,

      online: online ?? this.online,

      verified: verified ?? this.verified,

      emailVerified: emailVerified ?? this.emailVerified,

      phoneVerified: phoneVerified ?? this.phoneVerified,

      provider: provider ?? this.provider,

      signInProviders: signInProviders ?? this.signInProviders,

      isDiscoverable: isDiscoverable ?? this.isDiscoverable,

      isDiscoverableByEmail:
          isDiscoverableByEmail ?? this.isDiscoverableByEmail,

      isDiscoverableByPhone:
          isDiscoverableByPhone ?? this.isDiscoverableByPhone,

      createdAt: createdAt ?? this.createdAt,

      updatedAt: updatedAt ?? this.updatedAt,

      lastSeen: lastSeen ?? this.lastSeen,

      lastLogin: lastLogin ?? this.lastLogin,

      deviceToken: deviceToken ?? this.deviceToken,

      isBlocked: isBlocked ?? this.isBlocked,

      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  // ===========================================================
  // EXPLICIT NULLABLE FIELD CLEARING
  // ===========================================================

  UserModel clearEmail() {
    return _copyNullable(email: null, overrideEmail: true);
  }

  UserModel clearUsername() {
    return _copyNullable(username: null, overrideUsername: true);
  }

  UserModel clearProfilePhoto() {
    return _copyNullable(photoUrl: null, overridePhotoUrl: true);
  }

  UserModel clearCoverPhoto() {
    return _copyNullable(coverPhoto: null, overrideCoverPhoto: true);
  }

  UserModel clearBio() {
    return _copyNullable(bio: null, overrideBio: true);
  }

  UserModel clearCountry() {
    return _copyNullable(
      country: null,
      countryCode: null,
      overrideCountry: true,
      overrideCountryCode: true,
    );
  }

  UserModel clearDateOfBirth() {
    return _copyNullable(dateOfBirth: null, overrideDateOfBirth: true);
  }

  UserModel clearDeviceToken() {
    return _copyNullable(deviceToken: null, overrideDeviceToken: true);
  }

  UserModel _copyNullable({
    String? email,
    String? username,
    String? photoUrl,
    String? coverPhoto,
    String? bio,
    String? country,
    String? countryCode,
    DateTime? dateOfBirth,
    String? deviceToken,
    bool overrideEmail = false,
    bool overrideUsername = false,
    bool overridePhotoUrl = false,
    bool overrideCoverPhoto = false,
    bool overrideBio = false,
    bool overrideCountry = false,
    bool overrideCountryCode = false,
    bool overrideDateOfBirth = false,
    bool overrideDeviceToken = false,
  }) {
    return UserModel(
      uid: uid,
      name: name,
      phone: phone,

      email: overrideEmail ? email : this.email,

      username: overrideUsername ? username : this.username,

      userAddress: userAddress,

      photoUrl: overridePhotoUrl ? photoUrl : this.photoUrl,

      coverPhoto: overrideCoverPhoto ? coverPhoto : this.coverPhoto,

      bio: overrideBio ? bio : this.bio,

      country: overrideCountry ? country : this.country,

      countryCode: overrideCountryCode ? countryCode : this.countryCode,

      gender: gender,

      dateOfBirth: overrideDateOfBirth ? dateOfBirth : this.dateOfBirth,

      online: online,

      verified: verified,

      emailVerified: emailVerified,

      phoneVerified: phoneVerified,

      provider: provider,

      signInProviders: signInProviders,

      isDiscoverable: isDiscoverable,

      isDiscoverableByEmail: isDiscoverableByEmail,

      isDiscoverableByPhone: isDiscoverableByPhone,

      createdAt: createdAt,

      updatedAt: updatedAt,

      lastSeen: lastSeen,

      lastLogin: lastLogin,

      deviceToken: overrideDeviceToken ? deviceToken : this.deviceToken,

      isBlocked: isBlocked,

      isDeleted: isDeleted,
    );
  }

  // ===========================================================
  // DEBUG MAP
  // ===========================================================

  Map<String, dynamic> toDebugMap() {
    return <String, dynamic>{
      'uid': uid,
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      'email': email,
      'username': username,
      'jrCallUserId': jrCallUserId,
      'country': country,
      'countryCode': countryCode,
      'emailVerified': emailVerified,
      'phoneVerified': phoneVerified,
      'signInProviders': effectiveSignInProviders,
      'isDiscoverable': isDiscoverable,
      'isDiscoverableByEmail': isDiscoverableByEmail,
      'isDiscoverableByPhone': isDiscoverableByPhone,
      'isBlocked': isBlocked,
      'isDeleted': isDeleted,
    };
  }

  // ===========================================================
  // STRING HELPERS
  // ===========================================================

  static String? _cleanNullableString(String? value) {
    if (value == null) {
      return null;
    }

    final String cleaned = value.trim();

    return cleaned.isEmpty ? null : cleaned;
  }

  static String? _readString(Object? value) {
    if (value is! String) {
      return null;
    }

    final String cleaned = value.trim();

    return cleaned.isEmpty ? null : cleaned;
  }

  // ===========================================================
  // BOOLEAN HELPER
  // ===========================================================

  static bool _readBool(Object? value) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    if (value is String) {
      final String normalized = value.trim().toLowerCase();

      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }

      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }

    return false;
  }

  // ===========================================================
  // PROVIDER LIST HELPERS
  // ===========================================================

  static List<String> _readStringList(Object? value) {
    if (value is! Iterable) {
      return const <String>[];
    }

    final List<String> result = <String>[];

    final Set<String> seen = <String>{};

    for (final Object? item in value) {
      if (item is! String) {
        continue;
      }

      final String cleaned = item.trim();

      if (cleaned.isEmpty) {
        continue;
      }

      final String key = cleaned.toLowerCase();

      if (!seen.add(key)) {
        continue;
      }

      result.add(cleaned);
    }

    return List<String>.unmodifiable(result);
  }

  static List<String> _normalizeProviders(Iterable<String> providers) {
    final List<String> result = <String>[];

    final Set<String> seen = <String>{};

    for (final String provider in providers) {
      final String cleaned = provider.trim();

      if (cleaned.isEmpty) {
        continue;
      }

      final String key = cleaned.toLowerCase();

      if (!seen.add(key)) {
        continue;
      }

      result.add(cleaned);
    }

    return List<String>.unmodifiable(result);
  }

  // ===========================================================
  // TIMESTAMP COMPATIBILITY
  // ===========================================================

  static DateTime? _readDateTime(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is int) {
      return _dateTimeFromEpoch(value);
    }

    if (value is num) {
      return _dateTimeFromEpoch(value.toInt());
    }

    if (value is String) {
      final String normalized = value.trim();

      if (normalized.isEmpty) {
        return null;
      }

      final int? numeric = int.tryParse(normalized);

      if (numeric != null) {
        return _dateTimeFromEpoch(numeric);
      }

      return DateTime.tryParse(normalized);
    }

    return null;
  }

  static DateTime? _dateTimeFromEpoch(int value) {
    try {
      if (value.abs() < 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }

      return DateTime.fromMillisecondsSinceEpoch(value);
    } catch (_) {
      return null;
    }
  }

  // ===========================================================
  // NORMALIZATION
  // ===========================================================

  static String _normalizeSearchText(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _normalizeUsernameValue(String value) {
    String normalized = value.trim().toLowerCase();

    if (normalized.startsWith('@')) {
      normalized = normalized.substring(1);
    }

    return normalized;
  }

  static String? _normalizeUsernameNullable(String? value) {
    final String? cleaned = _cleanNullableString(value);

    if (cleaned == null) {
      return null;
    }

    final String normalized = _normalizeUsernameValue(cleaned);

    return normalized.isEmpty ? null : normalized;
  }

  static String _normalizeUserAddressValue(String value) {
    String normalized = value.trim().toLowerCase();

    if (normalized.startsWith('@')) {
      normalized = normalized.substring(1);
    }

    return normalized;
  }

  static String? _normalizeUserAddressNullable(String? value) {
    final String? cleaned = _cleanNullableString(value);

    if (cleaned == null) {
      return null;
    }

    final String normalized = _normalizeUserAddressValue(cleaned);

    return normalized.isEmpty ? null : normalized;
  }

  static String _normalizePhone(String value) {
    final String trimmed = value.trim();

    if (trimmed.isEmpty) {
      return '';
    }

    final bool hasPlus = trimmed.startsWith('+');

    final String digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) {
      return '';
    }

    return hasPlus ? '+$digits' : digits;
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  // ===========================================================
  // DEBUG
  // ===========================================================

  @override
  String toString() {
    return 'UserModel('
        'uid: $uid, '
        'fullName: $fullName, '
        'username: $username, '
        'jrCallUserId: $jrCallUserId, '
        'emailVerified: $emailVerified, '
        'phoneVerified: $phoneVerified, '
        'isBlocked: $isBlocked, '
        'isDeleted: $isDeleted'
        ')';
  }
}
