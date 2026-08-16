import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

/// ===============================================================
/// JR CALL
/// File: contact_model.dart
/// Location: lib/models/contact_model.dart
/// Master Step: 29
///
/// PURPOSE:
/// Central contact model for JR CALL.
///
/// RESPONSIBILITIES:
/// - Preserve existing Contacts / Call / future Message APIs
/// - Preserve legacy userId
/// - Carry resolved Firebase UID
/// - Carry public JR CALL ID
/// - Carry public Username
/// - Carry registered / non-registered state
/// - Carry public profile photo
/// - Safe Map / JSON / Firestore serialization
/// - Safe legacy document parsing
/// - Safe Timestamp / DateTime / ISO / epoch parsing
///
/// IDENTITY CONTRACT:
/// - linkedUid = preferred resolved Firebase UID.
/// - userId = preserved legacy identity field.
/// - jrCallUserId = public discovery identity only.
/// - username = public discovery identity only.
/// - Call Engine must ultimately receive Firebase UID.
///
/// SECURITY:
/// - No password
/// - No OTP
/// - No authentication credential
/// ===============================================================

enum ContactStatus { offline, online, busy, away, invisible }

/// ===============================================================
/// CONTACT REGISTRATION STATE
/// ===============================================================

enum ContactRegisteredState { unknown, registered, notRegistered }

/// ===============================================================
/// CONTACT MODEL
/// ===============================================================

class ContactModel {
  /// Existing contact-record identity.
  final String id;

  /// Legacy JR CALL user identity.
  ///
  /// Preserved because existing screens/providers/services may
  /// already depend on this field.
  final String userId;

  /// Display name.
  final String name;

  /// Phone number.
  final String phoneNumber;

  /// Email address.
  final String email;

  /// Profile photo.
  final String photoUrl;

  /// Region/country code.
  final String countryCode;

  /// Country display name.
  final String country;

  /// Public biography.
  final String bio;

  final bool isFavorite;
  final bool isBlocked;
  final bool isVerified;

  final ContactStatus status;

  final DateTime lastSeen;
  final DateTime createdAt;

  // =============================================================
  // JR CALL DISCOVERY IDENTITY
  // =============================================================

  /// Canonical resolved Firebase UID.
  ///
  /// This is the preferred identity to hand to Call Engine.
  final String? linkedUid;

  /// Public JR CALL identity.
  ///
  /// Example:
  /// jrcall_8h2k9p4q
  final String? jrCallUserId;

  /// Public unique username.
  final String? username;

  /// Whether this contact has been matched to an existing
  /// JR CALL account.
  final ContactRegisteredState registeredState;

  const ContactModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.phoneNumber,
    required this.email,
    required this.photoUrl,
    required this.countryCode,
    required this.country,
    required this.bio,
    required this.isFavorite,
    required this.isBlocked,
    required this.isVerified,
    required this.status,
    required this.lastSeen,
    required this.createdAt,
    this.linkedUid,
    this.jrCallUserId,
    this.username,
    this.registeredState = ContactRegisteredState.unknown,
  });

  // =============================================================
  // CONVENIENCE
  // =============================================================

  bool get isOnline {
    return status == ContactStatus.online;
  }

  bool get isRegistered {
    return registeredState == ContactRegisteredState.registered;
  }

  bool get isKnownNotRegistered {
    return registeredState == ContactRegisteredState.notRegistered;
  }

  bool get registrationUnknown {
    return registeredState == ContactRegisteredState.unknown;
  }

  bool get hasLinkedUid {
    return _hasValue(linkedUid);
  }

  bool get hasJrCallUserId {
    return _hasValue(jrCallUserId);
  }

  bool get hasUsername {
    return _hasValue(username);
  }

  bool get hasPhoto {
    return photoUrl.trim().isNotEmpty;
  }

  bool get hasPhone {
    return phoneNumber.trim().isNotEmpty;
  }

  bool get hasEmail {
    return email.trim().isNotEmpty;
  }

  /// Preferred internal Firebase identity.
  ///
  /// linkedUid always wins.
  ///
  /// Legacy userId remains available as backward-compatible
  /// fallback because older JR CALL contact data may have stored
  /// Firebase UID directly in userId.
  String? get resolvedUid {
    final String? linked = _cleanNullableString(linkedUid);

    if (linked != null) {
      return linked;
    }

    final String legacy = userId.trim();

    if (legacy.isEmpty) {
      return null;
    }

    return legacy;
  }

  String get displayName {
    final String normalizedName = name.trim();

    if (normalizedName.isNotEmpty) {
      return normalizedName;
    }

    final String? normalizedUsername = _cleanNullableString(username);

    if (normalizedUsername != null) {
      return normalizedUsername.startsWith('@')
          ? normalizedUsername.substring(1)
          : normalizedUsername;
    }

    final String? normalizedJrCallId = _cleanNullableString(jrCallUserId);

    if (normalizedJrCallId != null) {
      return normalizedJrCallId;
    }

    return 'JR CALL User';
  }

  String? get usernameLabel {
    final String? normalized = _cleanNullableString(username);

    if (normalized == null) {
      return null;
    }

    if (normalized.startsWith('@')) {
      return normalized;
    }

    return '@$normalized';
  }

  String? get publicIdentityLabel {
    final String? jrId = _cleanNullableString(jrCallUserId);

    if (jrId != null) {
      return jrId;
    }

    return usernameLabel;
  }

  // =============================================================
  // INITIAL
  // =============================================================

  factory ContactModel.initial() {
    final DateTime now = DateTime.now();

    return ContactModel(
      id: '',
      userId: '',
      name: '',
      phoneNumber: '',
      email: '',
      photoUrl: '',
      countryCode: '',
      country: '',
      bio: '',
      isFavorite: false,
      isBlocked: false,
      isVerified: false,
      status: ContactStatus.offline,
      lastSeen: now,
      createdAt: now,
      linkedUid: null,
      jrCallUserId: null,
      username: null,
      registeredState: ContactRegisteredState.unknown,
    );
  }

  // =============================================================
  // COPY WITH
  // =============================================================

  ContactModel copyWith({
    String? id,
    String? userId,
    String? name,
    String? phoneNumber,
    String? email,
    String? photoUrl,
    String? countryCode,
    String? country,
    String? bio,
    bool? isFavorite,
    bool? isBlocked,
    bool? isVerified,
    ContactStatus? status,
    DateTime? lastSeen,
    DateTime? createdAt,
    String? linkedUid,
    String? jrCallUserId,
    String? username,
    ContactRegisteredState? registeredState,
    bool clearLinkedUid = false,
    bool clearJrCallUserId = false,
    bool clearUsername = false,
  }) {
    return ContactModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      countryCode: countryCode ?? this.countryCode,
      country: country ?? this.country,
      bio: bio ?? this.bio,
      isFavorite: isFavorite ?? this.isFavorite,
      isBlocked: isBlocked ?? this.isBlocked,
      isVerified: isVerified ?? this.isVerified,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
      createdAt: createdAt ?? this.createdAt,
      linkedUid: clearLinkedUid ? null : linkedUid ?? this.linkedUid,
      jrCallUserId: clearJrCallUserId
          ? null
          : jrCallUserId ?? this.jrCallUserId,
      username: clearUsername ? null : username ?? this.username,
      registeredState: registeredState ?? this.registeredState,
    );
  }

  // =============================================================
  // GENERIC MAP
  // =============================================================

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'userId': userId,
      'name': name,
      'phoneNumber': phoneNumber,
      'email': email,
      'photoUrl': photoUrl,
      'countryCode': countryCode,
      'country': country,
      'bio': bio,
      'isFavorite': isFavorite,
      'isBlocked': isBlocked,
      'isVerified': isVerified,
      'status': status.name,
      'lastSeen': lastSeen.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      if (_hasValue(linkedUid)) 'linkedUid': linkedUid!.trim(),
      if (_hasValue(jrCallUserId)) 'jrCallUserId': jrCallUserId!.trim(),
      if (_hasValue(username)) 'username': username!.trim(),
      'registeredState': registeredState.name,

      /// Compatibility convenience.
      'isRegistered': isRegistered,
    };
  }

  // =============================================================
  // FIRESTORE MAP
  // =============================================================

  Map<String, dynamic> toFirestoreMap() {
    return <String, dynamic>{
      'id': id,
      'userId': userId,
      'name': name,
      'phoneNumber': phoneNumber,
      'email': email,
      'photoUrl': photoUrl,
      'countryCode': countryCode,
      'country': country,
      'bio': bio,
      'isFavorite': isFavorite,
      'isBlocked': isBlocked,
      'isVerified': isVerified,
      'status': status.name,
      'lastSeen': Timestamp.fromDate(lastSeen),
      'createdAt': Timestamp.fromDate(createdAt),
      if (_hasValue(linkedUid)) 'linkedUid': linkedUid!.trim(),
      if (_hasValue(jrCallUserId)) 'jrCallUserId': jrCallUserId!.trim(),
      if (_hasValue(username)) 'username': username!.trim(),
      'registeredState': registeredState.name,
      'isRegistered': isRegistered,
    };
  }

  // =============================================================
  // MAP PARSING
  // =============================================================

  factory ContactModel.fromMap(Map<String, dynamic> map) {
    final DateTime now = DateTime.now();

    final String userId = _firstString(<Object?>[map['userId'], map['uid']]);

    final String? linkedUid = _firstNullableString(<Object?>[
      map['linkedUid'],
      map['linkedUserId'],
      map['linkedUserUid'],
      map['firebaseUid'],
    ]);

    final String? jrCallUserId = _firstNullableString(<Object?>[
      map['jrCallUserId'],
      map['userAddress'],
      map['jrCallId'],
    ]);

    final String? username = _firstNullableString(<Object?>[
      map['username'],
      map['shortName'],
    ]);

    final ContactRegisteredState registeredState = _parseRegisteredState(
      registeredStateValue: map['registeredState'],
      legacyRegisteredValue: map['isRegistered'] ?? map['registered'],
      linkedUid: linkedUid,
    );

    return ContactModel(
      id: _firstString(<Object?>[map['id'], map['contactId']]),
      userId: userId,
      name: _firstString(<Object?>[
        map['name'],
        map['fullName'],
        map['displayName'],
      ]),
      phoneNumber: _firstString(<Object?>[
        map['phoneNumber'],
        map['phone'],
        map['phoneNormalized'],
      ]),
      email: _firstString(<Object?>[map['email'], map['emailNormalized']]),
      photoUrl: _firstString(<Object?>[
        map['photoUrl'],
        map['profilePhotoUrl'],
        map['photoURL'],
      ]),
      countryCode: _firstString(<Object?>[map['countryCode']]),
      country: _firstString(<Object?>[map['country']]),
      bio: _firstString(<Object?>[map['bio']]),
      isFavorite: _parseBool(map['isFavorite']) ?? false,
      isBlocked: _parseBool(map['isBlocked']) ?? false,
      isVerified:
          _parseBool(map['isVerified']) ?? _parseBool(map['verified']) ?? false,
      status: _parseStatus(map['status']),
      lastSeen: _parseDateTime(map['lastSeen'], fallback: now),
      createdAt: _parseDateTime(map['createdAt'], fallback: now),
      linkedUid: linkedUid,
      jrCallUserId: jrCallUserId,
      username: username,
      registeredState: registeredState,
    );
  }

  // =============================================================
  // FIRESTORE DOCUMENT
  // =============================================================

  factory ContactModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final Map<String, dynamic> data =
        document.data() ?? const <String, dynamic>{};

    final Map<String, dynamic> merged = <String, dynamic>{...data};

    if (_firstString(<Object?>[merged['id']]).isEmpty) {
      merged['id'] = document.id;
    }

    return ContactModel.fromMap(merged);
  }

  // =============================================================
  // JSON
  // =============================================================

  String toJson() {
    return jsonEncode(toMap());
  }

  factory ContactModel.fromJson(String source) {
    final Object? decoded = jsonDecode(source);

    if (decoded is! Map) {
      throw const FormatException('ContactModel JSON must contain an object.');
    }

    final Map<String, dynamic> data = <String, dynamic>{};

    decoded.forEach((Object? key, Object? value) {
      data[key.toString()] = value;
    });

    return ContactModel.fromMap(data);
  }

  // =============================================================
  // DEBUG
  // =============================================================

  @override
  String toString() {
    return 'ContactModel('
        'id: $id, '
        'userId: $userId, '
        'linkedUid: $linkedUid, '
        'name: $name, '
        'username: $username, '
        'jrCallUserId: $jrCallUserId, '
        'phoneNumber: $phoneNumber, '
        'registeredState: ${registeredState.name}'
        ')';
  }

  // =============================================================
  // EQUALITY
  // =============================================================

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is ContactModel &&
        other.id == id &&
        other.userId == userId &&
        other.linkedUid == linkedUid;
  }

  @override
  int get hashCode {
    return Object.hash(id, userId, linkedUid);
  }
}

/// ===============================================================
/// PARSING HELPERS
/// ===============================================================

String _firstString(Iterable<Object?> values) {
  return _firstNullableString(values) ?? '';
}

String? _firstNullableString(Iterable<Object?> values) {
  for (final Object? value in values) {
    if (value == null) {
      continue;
    }

    final String text = value.toString().trim();

    if (text.isEmpty) {
      continue;
    }

    if (text.toLowerCase() == 'null') {
      continue;
    }

    return text;
  }

  return null;
}

String? _cleanNullableString(String? value) {
  if (value == null) {
    return null;
  }

  final String normalized = value.trim();

  return normalized.isEmpty ? null : normalized;
}

bool _hasValue(String? value) {
  return value != null && value.trim().isNotEmpty;
}

bool? _parseBool(Object? value) {
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
    switch (value.trim().toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
      case 'registered':
        return true;

      case 'false':
      case '0':
      case 'no':
      case 'notregistered':
      case 'not_registered':
        return false;
    }
  }

  return null;
}

ContactStatus _parseStatus(Object? value) {
  if (value is ContactStatus) {
    return value;
  }

  final String normalized = value?.toString().trim().toLowerCase() ?? '';

  for (final ContactStatus status in ContactStatus.values) {
    if (status.name.toLowerCase() == normalized) {
      return status;
    }
  }

  return ContactStatus.offline;
}

ContactRegisteredState _parseRegisteredState({
  required Object? registeredStateValue,
  required Object? legacyRegisteredValue,
  required String? linkedUid,
}) {
  if (registeredStateValue is ContactRegisteredState) {
    return registeredStateValue;
  }

  final String stateText =
      registeredStateValue?.toString().trim().toLowerCase() ?? '';

  for (final ContactRegisteredState state in ContactRegisteredState.values) {
    if (state.name.toLowerCase() == stateText) {
      return state;
    }
  }

  /// Explicit old bool field has priority over inference.
  final bool? explicitLegacy = _parseBool(legacyRegisteredValue);

  if (explicitLegacy == true) {
    return ContactRegisteredState.registered;
  }

  if (explicitLegacy == false) {
    return ContactRegisteredState.notRegistered;
  }

  /// Resolved Firebase UID is strong evidence that this contact
  /// has already been matched to a JR CALL account.
  if (_hasValue(linkedUid)) {
    return ContactRegisteredState.registered;
  }

  /// Do NOT automatically mark a contact as registered only
  /// because legacy userId contains something.
  ///
  /// userId is retained for compatibility but may represent an
  /// older/local identity rather than a verified discovery match.
  return ContactRegisteredState.unknown;
}

DateTime _parseDateTime(Object? value, {required DateTime fallback}) {
  if (value == null) {
    return fallback;
  }

  if (value is DateTime) {
    return value;
  }

  if (value is Timestamp) {
    return value.toDate();
  }

  if (value is int) {
    return _dateTimeFromNumber(value) ?? fallback;
  }

  if (value is double) {
    return _dateTimeFromNumber(value.toInt()) ?? fallback;
  }

  if (value is String) {
    final String normalized = value.trim();

    if (normalized.isEmpty) {
      return fallback;
    }

    final DateTime? parsed = DateTime.tryParse(normalized);

    if (parsed != null) {
      return parsed;
    }

    final int? numeric = int.tryParse(normalized);

    if (numeric != null) {
      return _dateTimeFromNumber(numeric) ?? fallback;
    }
  }

  if (value is Map) {
    final Object? seconds = value['_seconds'] ?? value['seconds'];

    if (seconds is num) {
      final Object? nanoseconds = value['_nanoseconds'] ?? value['nanoseconds'];

      final double nanos = nanoseconds is num ? nanoseconds.toDouble() : 0;

      final int milliseconds =
          (seconds.toDouble() * 1000).round() + (nanos / 1000000).round();

      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }
  }

  return fallback;
}

DateTime? _dateTimeFromNumber(int value) {
  if (value <= 0) {
    return null;
  }

  /// Seconds since Unix epoch.
  if (value < 100000000000) {
    return DateTime.fromMillisecondsSinceEpoch(value * 1000);
  }

  /// Milliseconds since Unix epoch.
  return DateTime.fromMillisecondsSinceEpoch(value);
}
