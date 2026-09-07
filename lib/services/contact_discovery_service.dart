// ===============================================================
// JR CALL
// File: contact_discovery_service.dart
// Location: lib/services/contact_discovery_service.dart
//
// PRODUCTION CONTACT DISCOVERY SERVICE
//
// RESPONSIBILITIES:
// - Request Contacts permission only when contact sync is started.
// - Never request Contacts permission during normal app startup.
// - Accept device contacts through an injected contact loader.
// - Normalize and deduplicate phone numbers.
// - Match registered JR CALL users through UserDiscoveryService.
// - Preserve Firebase UID as the canonical matched identity.
// - Avoid storing/uploading the whole raw address book.
// - Prevent duplicate contact-discovery runs.
// - Bound network lookup volume.
// - Use bounded concurrency for faster production matching.
// - Preserve deterministic production-safe result objects.
//
// ARCHITECTURE:
// - UserDiscoveryService remains the owner of JR CALL user lookup.
// - This service does NOT query Firestore directly.
// - This service does NOT own global Name/Username/JR ID search.
// - This service does NOT own UI.
// - This service does NOT own Call Engine logic.
// - This service does NOT send SMS.
// - This service does NOT own OTP.
// - This service does NOT silently enable joined-user notifications.
//
// PHONE CONTRACT:
// - International E.164 is the canonical matching form here.
// - + international prefix is supported.
// - 00 international prefix is supported.
// - International numbers without + can be normalized when the
//   supplied country calling code confirms the prefix.
// - Local numbers can be normalized when country calling context
//   is supplied.
// - No Bangladesh-specific or country-specific hardcoding.
// - Country-specific numbering-plan rules are NOT invented.
//
// IMPORTANT:
// Device-contact reading remains injected through
// [DeviceContactsLoader] so this service does not become coupled
// to a specific native contacts package.
// ===============================================================

import 'dart:async';

import 'package:permission_handler/permission_handler.dart';

import 'user_discovery_service.dart';

// ===============================================================
// CONTACT ACCESS STATE
// ===============================================================

enum ContactAccessState {
  notDetermined,
  granted,
  denied,
  permanentlyDenied,
  restricted,
  limited,
  unavailable,
}

// ===============================================================
// DEVICE CONTACT CANDIDATE
// ===============================================================

class DeviceContactCandidate {
  const DeviceContactCandidate({
    required this.displayName,
    required this.phoneNumbers,
    this.localId,
  });

  /// Platform/local contact identifier when available.
  ///
  /// This value is local-device metadata only and must never become
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

// ===============================================================
// MATCHED JR CALL CONTACT
// ===============================================================

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

  /// Canonical normalized number that produced the match.
  final String matchedPhoneNumber;

  /// Firebase UID remains the canonical internal identity.
  String get uid => user.uid;

  String get displayName {
    final String localName = localContact.displayName.trim();

    if (localName.isNotEmpty) {
      return localName;
    }

    return user.displayName;
  }
}

// ===============================================================
// CONTACT DISCOVERY RESULT
// ===============================================================

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

  /// Number of unique valid canonical E.164 numbers discovered
  /// locally for this matching run.
  final int uniquePhoneNumbers;

  /// Number of phone numbers actually checked against JR CALL.
  final int phoneNumbersChecked;

  /// Number of raw phone values ignored because they could not be
  /// safely normalized into a canonical E.164 value.
  final int invalidPhoneNumbers;

  /// True when safety limits prevented all unique numbers from
  /// being queried in this discovery run.
  final bool truncated;

  bool get permissionGranted {
    return accessState == ContactAccessState.granted ||
        accessState == ContactAccessState.limited;
  }

  bool get hasMatches => matches.isNotEmpty;

  static const ContactDiscoveryResult permissionDenied =
  ContactDiscoveryResult(
    accessState: ContactAccessState.denied,
    matches: <ContactDiscoveryMatch>[],
    contactsRead: 0,
    uniquePhoneNumbers: 0,
    phoneNumbersChecked: 0,
    invalidPhoneNumbers: 0,
    truncated: false,
  );
}

// ===============================================================
// INJECTED DEVICE CONTACTS LOADER
// ===============================================================

typedef DeviceContactsLoader =
Future<List<DeviceContactCandidate>> Function();

// ===============================================================
// CONTACT DISCOVERY SERVICE
// ===============================================================

class ContactDiscoveryService {
  ContactDiscoveryService._();

  static final ContactDiscoveryService instance =
  ContactDiscoveryService._();

  final UserDiscoveryService _userDiscoveryService =
      UserDiscoveryService.instance;

  // =============================================================
  // SAFETY / PERFORMANCE LIMITS
  // =============================================================

  /// Prevent accidental large client-side lookup bursts.
  ///
  /// A future privacy-preserving backend batch matcher can replace
  /// this implementation without changing the public API.
  static const int defaultMaximumPhoneLookups = 250;

  static const int absoluteMaximumPhoneLookups = 500;

  /// Small bounded concurrency improves real device-contact sync
  /// performance without creating a large Firestore request burst.
  static const int _maximumConcurrentPhoneLookups = 6;

  bool _discoveryInProgress = false;

  bool get discoveryInProgress => _discoveryInProgress;

  // =============================================================
  // PERMISSION
  // =============================================================

  Future<ContactAccessState> getContactAccessState() async {
    try {
      final PermissionStatus status =
      await Permission.contacts.status;

      return _mapPermissionStatus(
        status,
      );
    } catch (_) {
      return ContactAccessState.unavailable;
    }
  }

  /// Requests Contacts permission only when the user explicitly
  /// starts contact sync/discovery.
  Future<ContactAccessState> requestContactAccess() async {
    try {
      final PermissionStatus current =
      await Permission.contacts.status;

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

      final PermissionStatus requested =
      await Permission.contacts.request();

      return _mapPermissionStatus(
        requested,
      );
    } catch (_) {
      return ContactAccessState.unavailable;
    }
  }

  Future<bool> openContactPermissionSettings() {
    return openAppSettings();
  }

  // =============================================================
  // MAIN CONTACT DISCOVERY
  // =============================================================

  Future<ContactDiscoveryResult> discoverContacts({
    required DeviceContactsLoader loadContacts,
    String? defaultCountryCallingCode,
    int maximumPhoneLookups = defaultMaximumPhoneLookups,
    bool requestPermissionIfNeeded = true,
  }) async {
    if (_discoveryInProgress) {
      throw StateError(
        'JR CALL contact discovery is already running.',
      );
    }

    _discoveryInProgress = true;

    try {
      ContactAccessState accessState =
      await getContactAccessState();

      if (!_isUsablePermission(accessState) &&
          requestPermissionIfNeeded) {
        accessState =
        await requestContactAccess();
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

      final List<DeviceContactCandidate> contacts =
      await loadContacts();

      return _matchContacts(
        contacts,
        accessState: accessState,
        defaultCountryCallingCode:
        defaultCountryCallingCode,
        maximumPhoneLookups:
        maximumPhoneLookups,
      );
    } finally {
      _discoveryInProgress = false;
    }
  }

  // =============================================================
  // MATCHING
  // =============================================================

  Future<ContactDiscoveryResult> _matchContacts(
      List<DeviceContactCandidate> contacts, {
        required ContactAccessState accessState,
        required String? defaultCountryCallingCode,
        required int maximumPhoneLookups,
      }) async {
    final int safeLookupLimit =
    _safeLookupLimit(
      maximumPhoneLookups,
    );

    // -----------------------------------------------------------
    // NORMALIZE + DEDUPLICATE
    //
    // Dart Map preserves insertion order.
    // First local contact owning a duplicated canonical number wins.
    // -----------------------------------------------------------

    final Map<String, DeviceContactCandidate> ownerByPhone =
    <String, DeviceContactCandidate>{};

    int invalidPhoneNumbers = 0;

    for (final DeviceContactCandidate contact in contacts) {
      for (final String rawPhone in contact.phoneNumbers) {
        final String? normalized =
        normalizePhoneToE164(
          rawPhone,
          defaultCountryCallingCode:
          defaultCountryCallingCode,
        );

        if (normalized == null) {
          invalidPhoneNumbers++;
          continue;
        }

        ownerByPhone.putIfAbsent(
          normalized,
              () => contact,
        );
      }
    }

    final List<String> uniquePhones =
    ownerByPhone.keys.toList(
      growable: false,
    );

    final bool truncated =
        uniquePhones.length >
            safeLookupLimit;

    final List<String> phonesToCheck =
    uniquePhones
        .take(
      safeLookupLimit,
    )
        .toList(
      growable: false,
    );

    // -----------------------------------------------------------
    // MATCHED USERS
    //
    // UID deduplication guarantees the same JR CALL account is not
    // returned twice when several local numbers resolve to it.
    // -----------------------------------------------------------

    final Map<String, ContactDiscoveryMatch> matchByUid =
    <String, ContactDiscoveryMatch>{};

    int checked = 0;

    // -----------------------------------------------------------
    // BOUNDED CONCURRENCY
    //
    // Sequentially checking hundreds of contacts is unnecessarily
    // slow. Sending hundreds simultaneously is also undesirable.
    //
    // Small deterministic batches provide a production balance.
    // Future.wait preserves the input order of each batch.
    // -----------------------------------------------------------

    for (
    int start = 0;
    start < phonesToCheck.length;
    start += _maximumConcurrentPhoneLookups
    ) {
      final int end =
      start + _maximumConcurrentPhoneLookups <
          phonesToCheck.length
          ? start + _maximumConcurrentPhoneLookups
          : phonesToCheck.length;

      final List<String> batch =
      phonesToCheck.sublist(
        start,
        end,
      );

      final List<_PhoneLookupResult> lookupResults =
      await Future.wait<_PhoneLookupResult>(
        batch.map(
              (
              String phone,
              ) async {
            final DiscoveryUser? user =
            await _userDiscoveryService.searchByPhone(
              phone,
              excludeCurrentUser: true,
            );

            return _PhoneLookupResult(
              phone: phone,
              user: user,
            );
          },
        ),
      );

      checked += batch.length;

      for (final _PhoneLookupResult lookup
      in lookupResults) {
        final DiscoveryUser? user =
            lookup.user;

        if (user == null) {
          continue;
        }

        final String uid =
        user.uid.trim();

        if (uid.isEmpty) {
          continue;
        }

        final DeviceContactCandidate? localContact =
        ownerByPhone[lookup.phone];

        if (localContact == null) {
          continue;
        }

        matchByUid.putIfAbsent(
          uid,
              () => ContactDiscoveryMatch(
            localContact: localContact,
            user: user,
            matchedPhoneNumber: lookup.phone,
          ),
        );
      }
    }

    // -----------------------------------------------------------
    // DETERMINISTIC PRESENTATION ORDER
    // -----------------------------------------------------------

    final List<ContactDiscoveryMatch> matches =
    matchByUid.values.toList(
      growable: false,
    )
      ..sort(
            (
            ContactDiscoveryMatch first,
            ContactDiscoveryMatch second,
            ) {
          final String firstName =
          first.displayName
              .trim()
              .toLowerCase();

          final String secondName =
          second.displayName
              .trim()
              .toLowerCase();

          final int nameComparison =
          firstName.compareTo(
            secondName,
          );

          if (nameComparison != 0) {
            return nameComparison;
          }

          return first.uid.compareTo(
            second.uid,
          );
        },
      );

    return ContactDiscoveryResult(
      accessState: accessState,
      matches:
      List<ContactDiscoveryMatch>.unmodifiable(
        matches,
      ),
      contactsRead: contacts.length,
      uniquePhoneNumbers:
      uniquePhones.length,
      phoneNumbersChecked: checked,
      invalidPhoneNumbers:
      invalidPhoneNumbers,
      truncated: truncated,
    );
  }

  // =============================================================
  // PHONE NORMALIZATION
  // =============================================================

  /// Converts a phone value to canonical international E.164 form
  /// when enough information is available.
  ///
  /// Supported:
  ///
  /// +8801712345678
  /// 008801712345678
  ///
  /// Local/national numbers can also be normalized when
  /// [defaultCountryCallingCode] is supplied.
  ///
  /// IMPORTANT:
  ///
  /// Country calling code alone cannot describe every country's
  /// complete national numbering plan.
  ///
  /// Therefore this method performs only deterministic,
  /// non-country-hardcoded normalization and never invents a
  /// country.
  String? normalizePhoneToE164(
      String value, {
        String? defaultCountryCallingCode,
      }) {
    String raw = value.trim();

    if (raw.isEmpty) {
      return null;
    }

    // -----------------------------------------------------------
    // Do not silently absorb letters/extensions into the number.
    //
    // Example:
    // 123456789 ext 22
    //
    // Converting that into 12345678922 would be unsafe.
    // -----------------------------------------------------------

    if (RegExp(
      r'[A-Za-z]',
    ).hasMatch(
      raw,
    )) {
      return null;
    }

    // -----------------------------------------------------------
    // Remove common visual separators only.
    // -----------------------------------------------------------

    raw = raw.replaceAll(
      RegExp(r'[\s().-]'),
      '',
    );

    if (raw.isEmpty) {
      return null;
    }

    // -----------------------------------------------------------
    // INTERNATIONAL ACCESS PREFIX
    //
    // 00xxxxxxxx -> +xxxxxxxx
    // -----------------------------------------------------------

    if (raw.startsWith('00')) {
      raw = '+${raw.substring(2)}';
    }

    // -----------------------------------------------------------
    // ALREADY INTERNATIONAL
    // -----------------------------------------------------------

    if (raw.startsWith('+')) {
      final String digits =
      raw
          .substring(1)
          .replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );

      if (digits.isEmpty) {
        return null;
      }

      final String candidate =
          '+$digits';

      return _isValidE164(
        candidate,
      )
          ? candidate
          : null;
    }

    // -----------------------------------------------------------
    // NATIONAL / INTERNATIONAL-WITHOUT-PLUS
    // -----------------------------------------------------------

    final String digits =
    raw.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    if (digits.isEmpty) {
      return null;
    }

    final String? callingCode =
    _normalizeCallingCode(
      defaultCountryCallingCode,
    );

    // Without country context, a non-international local number
    // cannot safely be converted into a globally unique E.164 ID.
    if (callingCode == null) {
      return null;
    }

    final String callingCodeDigits =
    callingCode.substring(1);

    // -----------------------------------------------------------
    // INTERNATIONAL NUMBER WITHOUT +
    //
    // Example:
    // calling code: +880
    // raw: 8801712345678
    // -> +8801712345678
    //
    // Prevents accidental:
    // +8808801712345678
    // -----------------------------------------------------------

    if (digits.startsWith(
      callingCodeDigits,
    ) &&
        digits.length >
            callingCodeDigits.length) {
      final String candidate =
          '+$digits';

      if (_isValidE164(
        candidate,
      )) {
        return candidate;
      }
    }

    // -----------------------------------------------------------
    // NATIONAL TRUNK PREFIX
    //
    // A single leading 0 is the common national trunk-prefix form.
    //
    // We intentionally remove at most ONE zero.
    // Repeatedly stripping all zeroes could alter a legitimate
    // national significant number.
    // -----------------------------------------------------------

    String nationalNumber =
        digits;

    if (nationalNumber.startsWith('0') &&
        nationalNumber.length > 1) {
      nationalNumber =
          nationalNumber.substring(
            1,
          );
    }

    if (nationalNumber.isEmpty) {
      return null;
    }

    final String candidate =
        '$callingCode$nationalNumber';

    return _isValidE164(
      candidate,
    )
        ? candidate
        : null;
  }

  /// Existing public API preserved for adapters/tests.
  bool isValidE164Phone(
      String value,
      ) {
    return _isValidE164(
      value.trim(),
    );
  }

  // =============================================================
  // PERMISSION HELPERS
  // =============================================================

  bool _isUsablePermission(
      ContactAccessState state,
      ) {
    return state ==
        ContactAccessState.granted ||
        state ==
            ContactAccessState.limited;
  }

  ContactAccessState _mapPermissionStatus(
      PermissionStatus status,
      ) {
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

  // =============================================================
  // COUNTRY CALLING CODE
  // =============================================================

  String? _normalizeCallingCode(
      String? value,
      ) {
    String raw =
        value?.trim() ?? '';

    if (raw.isEmpty) {
      return null;
    }

    if (raw.startsWith('00')) {
      raw = '+${raw.substring(2)}';
    }

    final String digits =
    raw.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    if (digits.isEmpty) {
      return null;
    }

    final String result =
        '+$digits';

    // E.164 geographic country codes are 1-3 digits.
    if (!RegExp(
      r'^\+[1-9]\d{0,2}$',
    ).hasMatch(
      result,
    )) {
      return null;
    }

    return result;
  }

  // =============================================================
  // E.164 VALIDATION
  // =============================================================

  bool _isValidE164(
      String value,
      ) {
    // JR CALL keeps the existing practical phone-number minimum
    // while enforcing E.164's 15-digit maximum and non-zero start.
    return RegExp(
      r'^\+[1-9]\d{7,14}$',
    ).hasMatch(
      value,
    );
  }

  // =============================================================
  // LOOKUP LIMIT
  // =============================================================

  int _safeLookupLimit(
      int value,
      ) {
    if (value < 1) {
      return 1;
    }

    if (value >
        absoluteMaximumPhoneLookups) {
      return absoluteMaximumPhoneLookups;
    }

    return value;
  }
}

// ===============================================================
// PRIVATE LOOKUP RESULT
// ===============================================================

class _PhoneLookupResult {
  const _PhoneLookupResult({
    required this.phone,
    required this.user,
  });

  final String phone;

  final DiscoveryUser? user;
}

// ===============================================================
// END OF FILE
//
// FILE 6 GUARANTEES:
//
// PERMISSION:
// ✓ Contacts permission is not requested during normal startup.
// ✓ Permission is requested only for explicit contact discovery.
// ✓ Granted / Limited / Denied / Permanently Denied / Restricted
//   states remain represented.
// ✓ App-settings API preserved.
//
// CONTACT PRIVACY:
// ✓ Raw address book is not persisted here.
// ✓ Raw address book is not bulk-uploaded here.
// ✓ Only bounded normalized phone lookups are performed.
// ✓ Local contact ID never becomes JR CALL identity.
//
// PHONE:
// ✓ E.164 canonical representation preserved.
// ✓ + international form preserved.
// ✓ 00 international prefix supported.
// ✓ International number without + supported with matching context.
// ✓ Country calling code limited to official 1-3 digit structure.
// ✓ Local trunk-prefix handling hardened.
// ✓ No Bangladesh-specific logic.
// ✓ No personal number hardcoding.
// ✓ Duplicate canonical numbers removed.
// ✓ Unsafe alphabetic/extension values are rejected instead of
//   silently being converted into the wrong phone number.
//
// PERFORMANCE:
// ✓ Lookup ceiling preserved.
// ✓ Absolute safety ceiling preserved.
// ✓ Contact sync truncation reporting preserved.
// ✓ Small bounded concurrent lookup batches added.
// ✓ Hundreds of requests are not launched simultaneously.
// ✓ Deterministic lookup order preserved.
// ✓ Deterministic result sorting preserved.
// ✓ Duplicate JR CALL accounts removed by Firebase UID.
//
// IDENTITY:
// ✓ Firebase UID remains canonical matched identity.
// ✓ Device localId never replaces Firebase UID.
// ✓ UserDiscoveryService remains lookup owner.
//
// PUBLIC API PRESERVED:
// ✓ ContactAccessState
// ✓ DeviceContactCandidate
// ✓ ContactDiscoveryMatch
// ✓ ContactDiscoveryResult
// ✓ DeviceContactsLoader
// ✓ ContactDiscoveryService.instance
// ✓ discoverContacts(...)
// ✓ normalizePhoneToE164(...)
// ✓ isValidE164Phone(...)
// ✓ defaultMaximumPhoneLookups
// ✓ absoluteMaximumPhoneLookups
//
// PROTECTED:
// ✓ No direct Firestore ownership added.
// ✓ Call Engine untouched.
// ✓ Message Engine untouched.
// ✓ WebRTC untouched.
// ✓ OTP/Auth ownership untouched.
//
// NEXT:
// FILE 7 — firestore.rules
// ===============================================================