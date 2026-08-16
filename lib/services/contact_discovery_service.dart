import 'dart:async';

import 'package:permission_handler/permission_handler.dart';

import 'user_discovery_service.dart';

/// ===========================================================
/// JR CALL
/// File: contact_discovery_service.dart
/// Location: lib/services/contact_discovery_service.dart
///
/// Description:
/// Privacy-conscious JR CALL contact-discovery coordinator.
///
/// Responsibilities:
/// - Request Contacts permission only when contact sync is started.
/// - Never request Contacts permission during normal app startup.
/// - Accept device contacts through an injected contact loader.
/// - Normalize and deduplicate phone numbers.
/// - Match registered JR CALL users through UserDiscoveryService.
/// - Preserve Firebase UID as the canonical matched identity.
/// - Avoid storing/uploading the whole raw address book.
/// - Prevent duplicate contact-discovery runs.
/// - Provide deterministic production-safe result objects.
///
/// Architecture:
/// - UserDiscoveryService remains the owner of JR CALL user lookup.
/// - This service does NOT query Firestore directly.
/// - This service does NOT own UI.
/// - This service does NOT own Call Engine logic.
/// - This service does NOT send SMS.
/// - This service does NOT silently enable joined-user notifications.
///
/// Important dependency rule:
/// The current established JR CALL dependency baseline does not contain
/// a native address-book reader package such as flutter_contacts.
///
/// Therefore device-contact reading is injected through
/// [DeviceContactsLoader]. This keeps FILE 19 compile-safe now and
/// allows a native contact reader to be connected later without
/// rewriting discovery/matching logic.
/// ===========================================================

enum ContactAccessState {
  notDetermined,
  granted,
  denied,
  permanentlyDenied,
  restricted,
  limited,
  unavailable,
}

/// ===========================================================
/// Device Contact Candidate
/// ===========================================================

class DeviceContactCandidate {
  const DeviceContactCandidate({
    required this.displayName,
    required this.phoneNumbers,
    this.localId,
  });

  /// Platform/local contact identifier when available.
  ///
  /// This value is local-device metadata only and must not become
  /// the canonical JR CALL identity.
  final String? localId;

  final String displayName;

  final List<String> phoneNumbers;

  DeviceContactCandidate copyWith({
    String? localId,
    String? displayName,
    List<String>? phoneNumbers,
  }) {
    return DeviceContactCandidate(
      localId: localId ?? this.localId,
      displayName: displayName ?? this.displayName,
      phoneNumbers: phoneNumbers ?? this.phoneNumbers,
    );
  }
}

/// ===========================================================
/// Matched JR CALL Contact
/// ===========================================================

class ContactDiscoveryMatch {
  const ContactDiscoveryMatch({
    required this.localContact,
    required this.user,
    required this.matchedPhoneNumber,
  });

  /// Original local-device contact.
  final DeviceContactCandidate localContact;

  /// Registered JR CALL profile.
  final DiscoveryUser user;

  /// Normalized number that produced the match.
  final String matchedPhoneNumber;

  /// Canonical internal identity.
  String get uid => user.uid;

  String get displayName {
    final String localName = localContact.displayName.trim();

    if (localName.isNotEmpty) {
      return localName;
    }

    return user.displayName;
  }
}

/// ===========================================================
/// Contact Discovery Result
/// ===========================================================

class ContactDiscoveryResult {
  const ContactDiscoveryResult({
    required this.accessState,
    required this.matches,
    required this.contactsRead,
    required this.uniquePhoneNumbers,
    required this.phoneNumbersChecked,
    required this.invalidPhoneNumbers,
    required this.truncated,
  });

  final ContactAccessState accessState;

  final List<ContactDiscoveryMatch> matches;

  /// Number of device contacts supplied by the native loader.
  final int contactsRead;

  /// Number of unique valid E.164 numbers discovered locally.
  final int uniquePhoneNumbers;

  /// Number of numbers actually checked against JR CALL.
  final int phoneNumbersChecked;

  /// Number of phone values ignored because they could not be
  /// safely normalized into E.164 format.
  final int invalidPhoneNumbers;

  /// True when safety limits prevented every local number
  /// from being queried during this run.
  final bool truncated;

  bool get permissionGranted =>
      accessState == ContactAccessState.granted ||
      accessState == ContactAccessState.limited;

  bool get hasMatches => matches.isNotEmpty;

  static const ContactDiscoveryResult permissionDenied = ContactDiscoveryResult(
    accessState: ContactAccessState.denied,
    matches: <ContactDiscoveryMatch>[],
    contactsRead: 0,
    uniquePhoneNumbers: 0,
    phoneNumbersChecked: 0,
    invalidPhoneNumbers: 0,
    truncated: false,
  );
}

/// ===========================================================
/// Injected Device Contacts Loader
/// ===========================================================

typedef DeviceContactsLoader = Future<List<DeviceContactCandidate>> Function();

/// ===========================================================
/// Contact Discovery Service
/// ===========================================================

class ContactDiscoveryService {
  ContactDiscoveryService._();

  static final ContactDiscoveryService instance = ContactDiscoveryService._();

  final UserDiscoveryService _userDiscoveryService =
      UserDiscoveryService.instance;

  /// Prevent accidental huge client-side Firestore lookup bursts.
  ///
  /// A future privacy-preserving backend batch matcher may replace
  /// one-by-one exact lookup without changing the public result model.
  static const int defaultMaximumPhoneLookups = 250;

  static const int absoluteMaximumPhoneLookups = 500;

  bool _discoveryInProgress = false;

  bool get discoveryInProgress => _discoveryInProgress;

  // ===========================================================
  // Permission
  // ===========================================================

  Future<ContactAccessState> getContactAccessState() async {
    try {
      final PermissionStatus status = await Permission.contacts.status;

      return _mapPermissionStatus(status);
    } catch (_) {
      return ContactAccessState.unavailable;
    }
  }

  /// Requests Contacts permission only when the user explicitly
  /// starts a contact-sync/discovery action.
  Future<ContactAccessState> requestContactAccess() async {
    try {
      final PermissionStatus current = await Permission.contacts.status;

      if (current.isGranted) {
        return ContactAccessState.granted;
      }

      if (current.isLimited) {
        return ContactAccessState.limited;
      }

      if (current.isPermanentlyDenied) {
        return ContactAccessState.permanentlyDenied;
      }

      if (current.isRestricted) {
        return ContactAccessState.restricted;
      }

      final PermissionStatus requested = await Permission.contacts.request();

      return _mapPermissionStatus(requested);
    } catch (_) {
      return ContactAccessState.unavailable;
    }
  }

  Future<bool> openContactPermissionSettings() {
    return openAppSettings();
  }

  // ===========================================================
  // Main Contact Discovery
  // ===========================================================

  Future<ContactDiscoveryResult> discoverContacts({
    required DeviceContactsLoader loadContacts,
    String? defaultCountryCallingCode,
    int maximumPhoneLookups = defaultMaximumPhoneLookups,
    bool requestPermissionIfNeeded = true,
  }) async {
    if (_discoveryInProgress) {
      throw StateError('JR CALL contact discovery is already running.');
    }

    _discoveryInProgress = true;

    try {
      ContactAccessState accessState = await getContactAccessState();

      if (!_isUsablePermission(accessState) && requestPermissionIfNeeded) {
        accessState = await requestContactAccess();
      }

      if (!_isUsablePermission(accessState)) {
        return ContactDiscoveryResult(
          accessState: accessState,
          matches: const <ContactDiscoveryMatch>[],
          contactsRead: 0,
          uniquePhoneNumbers: 0,
          phoneNumbersChecked: 0,
          invalidPhoneNumbers: 0,
          truncated: false,
        );
      }

      final List<DeviceContactCandidate> contacts = await loadContacts();

      return _matchContacts(
        contacts,
        accessState: accessState,
        defaultCountryCallingCode: defaultCountryCallingCode,
        maximumPhoneLookups: maximumPhoneLookups,
      );
    } finally {
      _discoveryInProgress = false;
    }
  }

  // ===========================================================
  // Matching
  // ===========================================================

  Future<ContactDiscoveryResult> _matchContacts(
    List<DeviceContactCandidate> contacts, {
    required ContactAccessState accessState,
    required String? defaultCountryCallingCode,
    required int maximumPhoneLookups,
  }) async {
    final int safeLookupLimit = _safeLookupLimit(maximumPhoneLookups);

    final Map<String, DeviceContactCandidate> ownerByPhone =
        <String, DeviceContactCandidate>{};

    int invalidPhoneNumbers = 0;

    for (final DeviceContactCandidate contact in contacts) {
      for (final String rawPhone in contact.phoneNumbers) {
        final String? normalized = normalizePhoneToE164(
          rawPhone,
          defaultCountryCallingCode: defaultCountryCallingCode,
        );

        if (normalized == null) {
          invalidPhoneNumbers++;
          continue;
        }

        ownerByPhone.putIfAbsent(normalized, () => contact);
      }
    }

    final List<String> uniquePhones = ownerByPhone.keys.toList(growable: false);

    final bool truncated = uniquePhones.length > safeLookupLimit;

    final Iterable<String> phonesToCheck = uniquePhones.take(safeLookupLimit);

    final Map<String, ContactDiscoveryMatch> matchByUid =
        <String, ContactDiscoveryMatch>{};

    int checked = 0;

    for (final String phone in phonesToCheck) {
      checked++;

      final DiscoveryUser? user = await _userDiscoveryService.searchByPhone(
        phone,
        excludeCurrentUser: true,
      );

      if (user == null) {
        continue;
      }

      final String uid = user.uid.trim();

      if (uid.isEmpty) {
        continue;
      }

      final DeviceContactCandidate? localContact = ownerByPhone[phone];

      if (localContact == null) {
        continue;
      }

      matchByUid.putIfAbsent(
        uid,
        () => ContactDiscoveryMatch(
          localContact: localContact,
          user: user,
          matchedPhoneNumber: phone,
        ),
      );
    }

    final List<ContactDiscoveryMatch> matches =
        matchByUid.values.toList(growable: false)
          ..sort((ContactDiscoveryMatch a, ContactDiscoveryMatch b) {
            final String aName = a.displayName.trim().toLowerCase();

            final String bName = b.displayName.trim().toLowerCase();

            return aName.compareTo(bName);
          });

    return ContactDiscoveryResult(
      accessState: accessState,
      matches: List<ContactDiscoveryMatch>.unmodifiable(matches),
      contactsRead: contacts.length,
      uniquePhoneNumbers: uniquePhones.length,
      phoneNumbersChecked: checked,
      invalidPhoneNumbers: invalidPhoneNumbers,
      truncated: truncated,
    );
  }

  // ===========================================================
  // Phone Normalization
  // ===========================================================

  /// Converts a phone value into E.164 where enough information
  /// is available.
  ///
  /// Supported examples:
  ///
  /// +8801712345678
  /// 008801712345678
  ///
  /// Local numbers can also be normalized when
  /// [defaultCountryCallingCode] is supplied.
  ///
  /// Example:
  ///
  /// raw:
  /// 01712345678
  ///
  /// defaultCountryCallingCode:
  /// +880
  ///
  /// result:
  /// +8801712345678
  ///
  /// This method deliberately does not guess a country.
  String? normalizePhoneToE164(
    String value, {
    String? defaultCountryCallingCode,
  }) {
    String raw = value.trim();

    if (raw.isEmpty) {
      return null;
    }

    raw = raw.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');

    if (raw.startsWith('00')) {
      raw = '+${raw.substring(2)}';
    }

    if (raw.startsWith('+')) {
      final String digits = raw.substring(1).replaceAll(RegExp(r'[^0-9]'), '');

      final String candidate = '+$digits';

      return _isValidE164(candidate) ? candidate : null;
    }

    final String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) {
      return null;
    }

    final String? callingCode = _normalizeCallingCode(
      defaultCountryCallingCode,
    );

    if (callingCode == null) {
      return null;
    }

    String nationalNumber = digits;

    while (nationalNumber.startsWith('0')) {
      nationalNumber = nationalNumber.substring(1);

      if (nationalNumber.isEmpty) {
        return null;
      }
    }

    final String candidate = '$callingCode$nationalNumber';

    return _isValidE164(candidate) ? candidate : null;
  }

  /// Exposed for future contact adapters/tests.
  bool isValidE164Phone(String value) {
    return _isValidE164(value.trim());
  }

  // ===========================================================
  // Helpers
  // ===========================================================

  bool _isUsablePermission(ContactAccessState state) {
    return state == ContactAccessState.granted ||
        state == ContactAccessState.limited;
  }

  ContactAccessState _mapPermissionStatus(PermissionStatus status) {
    if (status.isGranted) {
      return ContactAccessState.granted;
    }

    if (status.isLimited) {
      return ContactAccessState.limited;
    }

    if (status.isPermanentlyDenied) {
      return ContactAccessState.permanentlyDenied;
    }

    if (status.isRestricted) {
      return ContactAccessState.restricted;
    }

    if (status.isDenied) {
      return ContactAccessState.denied;
    }

    return ContactAccessState.notDetermined;
  }

  String? _normalizeCallingCode(String? value) {
    if (value == null) {
      return null;
    }

    String normalized = value.trim();

    if (normalized.isEmpty) {
      return null;
    }

    if (normalized.startsWith('00')) {
      normalized = '+${normalized.substring(2)}';
    }

    final String digits = normalized.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) {
      return null;
    }

    final String result = '+$digits';

    if (!RegExp(r'^\+[1-9]\d{0,3}$').hasMatch(result)) {
      return null;
    }

    return result;
  }

  bool _isValidE164(String value) {
    return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value);
  }

  int _safeLookupLimit(int value) {
    if (value < 1) {
      return 1;
    }

    if (value > absoluteMaximumPhoneLookups) {
      return absoluteMaximumPhoneLookups;
    }

    return value;
  }
}
