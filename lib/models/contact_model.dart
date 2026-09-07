import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

/// ===============================================================
/// JR CALL
/// File: contact_model.dart
/// Location: lib/models/contact_model.dart
///
/// FINAL PRODUCTION CONTRACT:
/// - Existing Contacts / Search / Call APIs preserved.
/// - Legacy userId preserved.
/// - linkedUid carries resolved Firebase UID.
/// - Public JR CALL ID / username remain discovery identities only.
/// - Explicit notRegistered state can never become a Call target.
/// - Strict Call Engine target getter provided.
/// - Firestore / JSON / legacy parsing hardened.
/// - Contact permission/query/E.164 ownership stays in services.
/// ===============================================================

enum ContactStatus {
  offline,
  online,
  busy,
  away,
  invisible,
}

enum ContactRegisteredState {
  unknown,
  registered,
  notRegistered,
}

class ContactModel {
  final String id;

  /// Preserved legacy identity field.
  final String userId;

  final String name;
  final String phoneNumber;
  final String email;
  final String photoUrl;
  final String countryCode;
  final String country;
  final String bio;

  final bool isFavorite;
  final bool isBlocked;
  final bool isVerified;

  final ContactStatus status;

  final DateTime lastSeen;
  final DateTime createdAt;

  /// Preferred resolved Firebase UID.
  final String? linkedUid;

  /// Public JR CALL discovery identity.
  final String? jrCallUserId;

  /// Public unique username.
  final String? username;

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

  bool get isOnline => status == ContactStatus.online;

  bool get isRegistered =>
      registeredState == ContactRegisteredState.registered;

  bool get isKnownNotRegistered =>
      registeredState == ContactRegisteredState.notRegistered;

  bool get registrationUnknown =>
      registeredState == ContactRegisteredState.unknown;

  bool get hasLinkedUid => _hasValue(linkedUid);

  bool get hasJrCallUserId => _hasValue(jrCallUserId);

  bool get hasUsername => _hasValue(username);

  bool get hasPhoto => photoUrl.trim().isNotEmpty;

  bool get hasPhone => phoneNumber.trim().isNotEmpty;

  bool get hasEmail => email.trim().isNotEmpty;

  // =============================================================
  // DISCOVERY NORMALIZATION
  // =============================================================

  String get normalizedName {
    return _normalizeSearchText(name);
  }

  String? get normalizedUsername {
    return _normalizeUsernameNullable(username);
  }

  String? get normalizedJrCallUserId {
    return _normalizePublicIdentityNullable(jrCallUserId);
  }

  String? get normalizedEmail {
    return _normalizeEmailNullable(email);
  }

  /// Formatting-only normalized phone value.
  ///
  /// True E.164 canonicalization requiring country context is owned
  /// by contact_discovery_service.dart.
  String? get normalizedPhone {
    return _normalizePhoneNullable(phoneNumber);
  }

  // =============================================================
  // IDENTITY
  // =============================================================

  /// Backward-compatible resolved identity.
  ///
  /// linkedUid is preferred.
  /// Explicitly not-registered contacts never resolve.
  /// Legacy userId remains available for old data compatibility.
  String? get resolvedUid {
    if (registeredState == ContactRegisteredState.notRegistered) {
      return null;
    }

    final String? linked = _cleanNullableString(linkedUid);

    if (linked != null) {
      return linked;
    }

    final String legacy = userId.trim();

    return legacy.isEmpty ? null : legacy;
  }

  /// Strict Firebase UID target for Call Engine.
  ///
  /// Use this for new Call Engine integration.
  String? get callTargetUid {
    if (registeredState == ContactRegisteredState.notRegistered) {
      return null;
    }

    final String? linked = _cleanNullableString(linkedUid);

    if (linked != null) {
      return linked;
    }

    if (registeredState != ContactRegisteredState.registered) {
      return null;
    }

    final String legacy = userId.trim();

    return legacy.isEmpty ? null : legacy;
  }

  bool get canStartJrCall {
    return !isBlocked && callTargetUid != null;
  }

  bool get canInvite {
    return !isBlocked && isKnownNotRegistered && hasPhone;
  }

  String get displayName {
    final String cleanedName = name.trim();

    if (cleanedName.isNotEmpty) {
      return cleanedName;
    }

    final String? cleanedUsername =
    _cleanNullableString(username);

    if (cleanedUsername != null) {
      return cleanedUsername.startsWith('@')
          ? cleanedUsername.substring(1)
          : cleanedUsername;
    }

    final String? cleanedJrCallId =
    _cleanNullableString(jrCallUserId);

    if (cleanedJrCallId != null) {
      return cleanedJrCallId;
    }

    return 'JR CALL User';
  }

  String? get usernameLabel {
    final String? normalized =
    _cleanNullableString(username);

    if (normalized == null) {
      return null;
    }

    return normalized.startsWith('@')
        ? normalized
        : '@$normalized';
  }

  String? get publicIdentityLabel {
    final String? jrId =
    _cleanNullableString(jrCallUserId);

    return jrId ?? usernameLabel;
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
  // COPY
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
      linkedUid:
      clearLinkedUid ? null : linkedUid ?? this.linkedUid,
      jrCallUserId: clearJrCallUserId
          ? null
          : jrCallUserId ?? this.jrCallUserId,
      username:
      clearUsername ? null : username ?? this.username,
      registeredState:
      registeredState ?? this.registeredState,
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
      'lastSeen': lastSeen.toUtc().toIso8601String(),
      'createdAt': createdAt.toUtc().toIso8601String(),
      if (_hasValue(linkedUid))
        'linkedUid': linkedUid!.trim(),
      if (_hasValue(jrCallUserId))
        'jrCallUserId': jrCallUserId!.trim(),
      if (_hasValue(username))
        'username': username!.trim(),
      'registeredState': registeredState.name,
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
      if (_hasValue(linkedUid))
        'linkedUid': linkedUid!.trim(),
      if (_hasValue(jrCallUserId))
        'jrCallUserId': jrCallUserId!.trim(),
      if (_hasValue(username))
        'username': username!.trim(),
      'registeredState': registeredState.name,
      'isRegistered': isRegistered,
    };
  }

  // =============================================================
  // MAP PARSING
  // =============================================================

  factory ContactModel.fromMap(
      Map<String, dynamic> map,
      ) {
    final DateTime epoch =
    DateTime.fromMillisecondsSinceEpoch(
      0,
      isUtc: true,
    );

    final String userId = _firstString(
      <Object?>[
        map['userId'],
        map['uid'],
      ],
    );

    final String? linkedUid =
    _firstNullableString(
      <Object?>[
        map['linkedUid'],
        map['linkedUserId'],
        map['linkedUserUid'],
        map['firebaseUid'],
      ],
    );

    final String? jrCallUserId =
    _firstNullableString(
      <Object?>[
        map['jrCallUserId'],
        map['userAddress'],
        map['jrCallId'],
      ],
    );

    final String? username =
    _firstNullableString(
      <Object?>[
        map['username'],
        map['shortName'],
      ],
    );

    final ContactRegisteredState registeredState =
    _parseRegisteredState(
      registeredStateValue: map['registeredState'],
      legacyRegisteredValue:
      map['isRegistered'] ?? map['registered'],
      linkedUid: linkedUid,
    );

    return ContactModel(
      id: _firstString(
        <Object?>[
          map['id'],
          map['contactId'],
        ],
      ),
      userId: userId,
      name: _firstString(
        <Object?>[
          map['name'],
          map['fullName'],
          map['displayName'],
        ],
      ),
      phoneNumber: _firstString(
        <Object?>[
          map['phoneNumber'],
          map['phone'],
          map['phoneNormalized'],
        ],
      ),
      email: _firstString(
        <Object?>[
          map['email'],
          map['emailNormalized'],
        ],
      ),
      photoUrl: _firstString(
        <Object?>[
          map['photoUrl'],
          map['profilePhotoUrl'],
          map['photoURL'],
        ],
      ),
      countryCode: _firstString(
        <Object?>[
          map['countryCode'],
        ],
      ),
      country: _firstString(
        <Object?>[
          map['country'],
        ],
      ),
      bio: _firstString(
        <Object?>[
          map['bio'],
        ],
      ),
      isFavorite:
      _parseBool(map['isFavorite']) ?? false,
      isBlocked:
      _parseBool(map['isBlocked']) ?? false,
      isVerified:
      _parseBool(map['isVerified']) ??
          _parseBool(map['verified']) ??
          false,
      status: _parseStatus(map['status']),
      lastSeen: _parseDateTime(
        map['lastSeen'],
        fallback: epoch,
      ),
      createdAt: _parseDateTime(
        map['createdAt'],
        fallback: epoch,
      ),
      linkedUid: linkedUid,
      jrCallUserId: jrCallUserId,
      username: username,
      registeredState: registeredState,
    );
  }

  // =============================================================
  // FIRESTORE
  // =============================================================

  factory ContactModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> document,
      ) {
    final Map<String, dynamic> data =
        document.data() ?? const <String, dynamic>{};

    final Map<String, dynamic> merged =
    <String, dynamic>{
      ...data,
    };

    if (_firstString(
      <Object?>[
        merged['id'],
      ],
    ).isEmpty) {
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
    try {
      final Object? decoded = jsonDecode(source);

      if (decoded is Map<String, dynamic>) {
        return ContactModel.fromMap(decoded);
      }

      if (decoded is Map) {
        final Map<String, dynamic> normalized =
        <String, dynamic>{};

        for (final MapEntry<dynamic, dynamic> entry
        in decoded.entries) {
          normalized[entry.key.toString()] =
              entry.value;
        }

        return ContactModel.fromMap(normalized);
      }
    } on FormatException {
      // Malformed legacy JSON falls through to safe defaults.
    } catch (_) {
      // Corrupted local data must not crash Contacts/Call UI.
    }

    return ContactModel.fromMap(
      const <String, dynamic>{},
    );
  }

  // =============================================================
  // DEBUG / OBJECT
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
    return Object.hash(
      id,
      userId,
      linkedUid,
    );
  }
}

// ===============================================================
// PARSING HELPERS
// ===============================================================

String _firstString(Iterable<Object?> values) {
  return _firstNullableString(values) ?? '';
}

String? _firstNullableString(
    Iterable<Object?> values,
    ) {
  for (final Object? value in values) {
    if (value == null) {
      continue;
    }

    final String text = value.toString().trim();

    if (text.isEmpty ||
        text.toLowerCase() == 'null') {
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
  return value != null &&
      value.trim().isNotEmpty;
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

  switch (
  value?.toString().trim().toLowerCase()) {
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
    case 'not-registered':
      return false;
  }

  return null;
}

String _enumToken(Object? value) {
  final String raw =
      value?.toString().trim().toLowerCase() ?? '';

  if (raw.isEmpty) {
    return '';
  }

  final int dot = raw.lastIndexOf('.');

  return dot >= 0
      ? raw.substring(dot + 1)
      : raw;
}

ContactStatus _parseStatus(Object? value) {
  if (value is ContactStatus) {
    return value;
  }

  if (value is num) {
    final int index = value.toInt();

    if (index >= 0 &&
        index < ContactStatus.values.length) {
      return ContactStatus.values[index];
    }
  }

  final String normalized = _enumToken(value);

  for (final ContactStatus status
  in ContactStatus.values) {
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
  if (registeredStateValue
  is ContactRegisteredState) {
    return registeredStateValue;
  }

  if (registeredStateValue is num) {
    final int index =
    registeredStateValue.toInt();

    if (index >= 0 &&
        index <
            ContactRegisteredState.values.length) {
      return ContactRegisteredState.values[index];
    }
  }

  final String normalized =
  _enumToken(registeredStateValue);

  for (final ContactRegisteredState state
  in ContactRegisteredState.values) {
    if (state.name.toLowerCase() == normalized) {
      return state;
    }
  }

  final bool? explicitLegacy =
  _parseBool(legacyRegisteredValue);

  if (explicitLegacy == true) {
    return ContactRegisteredState.registered;
  }

  if (explicitLegacy == false) {
    return ContactRegisteredState.notRegistered;
  }

  if (_hasValue(linkedUid)) {
    return ContactRegisteredState.registered;
  }

  return ContactRegisteredState.unknown;
}

DateTime _parseDateTime(
    Object? value, {
      required DateTime fallback,
    }) {
  if (value == null) {
    return fallback;
  }

  if (value is DateTime) {
    return value;
  }

  if (value is Timestamp) {
    return value.toDate();
  }

  if (value is num) {
    return _dateTimeFromNumber(value) ??
        fallback;
  }

  if (value is String) {
    final String normalized = value.trim();

    if (normalized.isEmpty) {
      return fallback;
    }

    final DateTime? parsed =
    DateTime.tryParse(normalized);

    if (parsed != null) {
      return parsed;
    }

    final num? numeric =
    num.tryParse(normalized);

    if (numeric != null) {
      return _dateTimeFromNumber(numeric) ??
          fallback;
    }
  }

  if (value is Map) {
    final Object? seconds =
        value['_seconds'] ?? value['seconds'];

    if (seconds is num) {
      final Object? nanoseconds =
          value['_nanoseconds'] ??
              value['nanoseconds'];

      final double nanos = nanoseconds is num
          ? nanoseconds.toDouble()
          : 0;

      try {
        final int microseconds =
            (seconds.toDouble() * 1000000).round() +
                (nanos / 1000).round();

        return DateTime.fromMicrosecondsSinceEpoch(
          microseconds,
        );
      } on RangeError {
        return fallback;
      } on ArgumentError {
        return fallback;
      }
    }
  }

  try {
    final dynamic converted =
    (value as dynamic).toDate();

    if (converted is DateTime) {
      return converted;
    }
  } catch (_) {
    // Not Timestamp-compatible.
  }

  return fallback;
}

DateTime? _dateTimeFromNumber(num value) {
  try {
    final int raw = value.toInt();
    final int absolute = raw.abs();

    if (absolute < 100000000000) {
      return DateTime.fromMillisecondsSinceEpoch(
        raw * 1000,
      );
    }

    if (absolute >= 100000000000000) {
      return DateTime.fromMicrosecondsSinceEpoch(
        raw,
      );
    }

    return DateTime.fromMillisecondsSinceEpoch(
      raw,
    );
  } on RangeError {
    return null;
  } on ArgumentError {
    return null;
  }
}

// ===============================================================
// DISCOVERY NORMALIZATION
// ===============================================================

String _normalizeSearchText(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(
    RegExp(r'\s+'),
    ' ',
  );
}

String? _normalizeUsernameNullable(
    String? value,
    ) {
  final String? cleaned =
  _cleanNullableString(value);

  if (cleaned == null) {
    return null;
  }

  String normalized = cleaned.toLowerCase();

  if (normalized.startsWith('@')) {
    normalized = normalized.substring(1);
  }

  return normalized.isEmpty
      ? null
      : normalized;
}

String? _normalizePublicIdentityNullable(
    String? value,
    ) {
  final String? cleaned =
  _cleanNullableString(value);

  if (cleaned == null) {
    return null;
  }

  String normalized = cleaned.toLowerCase();

  if (normalized.startsWith('@')) {
    normalized = normalized.substring(1);
  }

  return normalized.isEmpty
      ? null
      : normalized;
}

String? _normalizeEmailNullable(
    String? value,
    ) {
  final String? cleaned =
  _cleanNullableString(value);

  return cleaned?.toLowerCase();
}

String? _normalizePhoneNullable(
    String? value,
    ) {
  final String? cleaned =
  _cleanNullableString(value);

  if (cleaned == null) {
    return null;
  }

  final bool hasPlus =
  cleaned.startsWith('+');

  final String digits = cleaned.replaceAll(
    RegExp(r'[^0-9]'),
    '',
  );

  if (digits.isEmpty) {
    return null;
  }

  return hasPlus
      ? '+$digits'
      : digits;
}