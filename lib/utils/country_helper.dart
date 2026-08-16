import 'package:country_picker/country_picker.dart';

// ===========================================================
// JR CALL
// File: country_helper.dart
// Location: lib/utils/country_helper.dart
//
// Description:
// Canonical production global country and phone normalization utility.
//
// Responsibilities:
// - Support the complete country_picker country collection
// - Normalize ISO alpha-2 country codes
// - Resolve countries by ISO code, country name, and dial code
// - Search the complete global country list
// - Build safe E.164-style international phone candidates
// - Support Auth, Profile, Discovery, Contacts, and Call identity flow
// - Preserve backward-compatible JR CALL helper APIs
//
// Architecture:
// - Country UI selection belongs to screens/widgets
// - Firebase Phone Authentication belongs to AuthService
// - User discovery belongs to UserDiscoveryService
// - Contact sync belongs to ContactDiscoveryService
// - Call Engine receives canonical Firebase UID only
//
// Important:
// - No country is forced for authentication
// - Bangladesh is supported like every other country
// - This helper does NOT call Firebase
// - This helper does NOT request permissions
// - This helper does NOT perform phone authentication
// - This helper does NOT contain Call Engine/WebRTC logic
// - Phone validation here is structural only
// ===========================================================

class CountryHelper {
  CountryHelper._();

  // ===========================================================
  // Legacy Compatibility Constants
  // ===========================================================
  //
  // These constants are preserved because older finalized files
  // may still reference them.
  //
  // IMPORTANT:
  // They are compatibility values only.
  // They MUST NOT be used to force Bangladesh as the selected
  // country for worldwide authentication/profile flows.
  // ===========================================================

  static const String defaultCountryCode = 'BD';
  static const String defaultCountryName = 'Bangladesh';
  static const String defaultPhoneCode = '880';

  // ===========================================================
  // Cached Global Country Collection
  // ===========================================================

  static List<Country>? _cachedCountries;

  /// Complete global country list supplied by country_picker.
  ///
  /// The collection is alphabetically sorted and immutable.
  static List<Country> get allCountries {
    final cached = _cachedCountries;

    if (cached != null) {
      return cached;
    }

    final countries = List<Country>.from(
      CountryService().getAll(),
      growable: true,
    );

    countries.sort(
      (first, second) =>
          first.name.toLowerCase().compareTo(second.name.toLowerCase()),
    );

    final immutableCountries = List<Country>.unmodifiable(countries);

    _cachedCountries = immutableCountries;

    return immutableCountries;
  }

  /// Backward-compatible API.
  static List<Country> getAllCountries() => allCountries;

  // ===========================================================
  // Legacy Default Country
  // ===========================================================

  /// Backward-compatible fallback only.
  ///
  /// New worldwide screens should prefer:
  ///
  /// resolveSavedCountryOrNull(...)
  ///
  /// and explicitly require/select a country when none exists.
  static Country get defaultCountry {
    final resolved = fromCountryCode(defaultCountryCode);

    if (resolved != null) {
      return resolved;
    }

    return Country.parse(defaultCountryCode);
  }

  // ===========================================================
  // ISO Country Code
  // ===========================================================

  /// Resolves a supported country by ISO alpha-2 code.
  ///
  /// Examples:
  /// US
  /// GB
  /// BD
  /// au
  /// " CA "
  static Country? fromCountryCode(String code) {
    final normalizedCode = normalizeCountryCode(code);

    if (normalizedCode == null) {
      return null;
    }

    for (final country in allCountries) {
      if (country.countryCode.trim().toUpperCase() == normalizedCode) {
        return country;
      }
    }

    return null;
  }

  /// Backward-compatible alias.
  static Country? fromIsoCode(String code) {
    return fromCountryCode(code);
  }

  /// Normalizes ISO alpha-2 format.
  ///
  /// Example:
  /// " us " -> "US"
  static String? normalizeCountryCode(String? value) {
    if (value == null) {
      return null;
    }

    final normalized = value.trim().toUpperCase();

    if (!RegExp(r'^[A-Z]{2}$').hasMatch(normalized)) {
      return null;
    }

    return normalized;
  }

  /// Returns true only if the code resolves to a country
  /// supported by country_picker.
  static bool isValidCountryCode(String? code) {
    final normalizedCode = normalizeCountryCode(code);

    if (normalizedCode == null) {
      return false;
    }

    return fromCountryCode(normalizedCode) != null;
  }

  // ===========================================================
  // Country Name
  // ===========================================================

  /// Resolves a country by exact normalized country name.
  ///
  /// Matching is:
  /// - case-insensitive
  /// - whitespace-normalized
  static Country? fromCountryName(String name) {
    final normalizedName = normalizeCountryName(name);

    if (normalizedName == null) {
      return null;
    }

    for (final country in allCountries) {
      if (_normalizeSearchText(country.name) == normalizedName) {
        return country;
      }
    }

    return null;
  }

  static String? normalizeCountryName(String? value) {
    if (value == null) {
      return null;
    }

    final normalized = _normalizeSearchText(value);

    if (normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  /// Existing compatibility API.
  static String getCountryName(String code) {
    return fromCountryCode(code)?.name ?? 'Unknown';
  }

  // ===========================================================
  // Flag
  // ===========================================================

  static String getFlag(String code) {
    return fromCountryCode(code)?.flagEmoji ?? '🌍';
  }

  // ===========================================================
  // Dial / Calling Code
  // ===========================================================

  /// Resolves the first country matching a calling code.
  ///
  /// Examples:
  /// 1
  /// +1
  /// 44
  /// +880
  /// 00880
  ///
  /// Multiple countries can share calling codes.
  /// Use [countriesFromPhoneCode] when every match is needed.
  static Country? fromPhoneCode(String phoneCode) {
    final normalizedPhoneCode = normalizePhoneCode(phoneCode);

    if (normalizedPhoneCode == null) {
      return null;
    }

    for (final country in allCountries) {
      if (_normalizedCountryPhoneCode(country) == normalizedPhoneCode) {
        return country;
      }
    }

    return null;
  }

  /// Returns every country using the supplied calling code.
  static List<Country> countriesFromPhoneCode(String phoneCode) {
    final normalizedPhoneCode = normalizePhoneCode(phoneCode);

    if (normalizedPhoneCode == null) {
      return const <Country>[];
    }

    final matches = allCountries
        .where(
          (country) =>
              _normalizedCountryPhoneCode(country) == normalizedPhoneCode,
        )
        .toList(growable: false);

    return List<Country>.unmodifiable(matches);
  }

  /// Normalizes a calling code to digits only.
  ///
  /// Examples:
  /// +880  -> 880
  /// 00880 -> 880
  /// +44   -> 44
  /// +1    -> 1
  static String? normalizePhoneCode(String? value) {
    if (value == null) {
      return null;
    }

    var normalized = value.trim();

    if (normalized.isEmpty) {
      return null;
    }

    if (normalized.startsWith('+')) {
      normalized = normalized.substring(1);
    } else if (normalized.startsWith('00')) {
      normalized = normalized.substring(2);
    }

    final digits = _digitsOnly(normalized);

    if (digits.isEmpty || digits.startsWith('0')) {
      return null;
    }

    return digits;
  }

  /// Returns '+' prefixed calling code.
  ///
  /// Example:
  /// US -> +1
  /// GB -> +44
  /// BD -> +880
  static String getDialCode(String countryCode) {
    final rawPhoneCode = getRawPhoneCode(countryCode);

    if (rawPhoneCode == null || rawPhoneCode.isEmpty) {
      return '';
    }

    return '+$rawPhoneCode';
  }

  /// Returns calling code without '+'.
  static String? getRawPhoneCode(String countryCode) {
    final country = fromCountryCode(countryCode);

    if (country == null) {
      return null;
    }

    return normalizePhoneCode(country.phoneCode);
  }

  // ===========================================================
  // International Phone Normalization
  // ===========================================================

  /// Builds an E.164-style international phone candidate.
  ///
  /// Supported input styles:
  ///
  /// +14155552671
  /// 0014155552671
  /// local/national number + selected country
  ///
  /// Important:
  /// This helper intentionally does NOT implement every country's
  /// national numbering plan.
  ///
  /// It performs safe structural normalization only.
  ///
  /// Firebase Phone Auth / backend verification remains the
  /// authoritative ownership validation.
  static String buildInternationalNumber({
    required String countryCode,
    required String phoneNumber,
  }) {
    final rawPhone = phoneNumber.trim();

    if (rawPhone.isEmpty) {
      return '';
    }

    // Already supplied in +international format.
    if (rawPhone.startsWith('+')) {
      final normalized = normalizeInternationalPhone(rawPhone);

      if (!isPlausibleInternationalPhone(normalized)) {
        return '';
      }

      return normalized!;
    }

    // International 00 prefix.
    if (rawPhone.startsWith('00')) {
      final normalized = normalizeInternationalPhone(rawPhone);

      if (!isPlausibleInternationalPhone(normalized)) {
        return '';
      }

      return normalized!;
    }

    final country = fromCountryCode(countryCode);

    if (country == null) {
      return '';
    }

    final callingCode = normalizePhoneCode(country.phoneCode);

    if (callingCode == null || callingCode.isEmpty) {
      return '';
    }

    var phoneDigits = _digitsOnly(rawPhone);

    if (phoneDigits.isEmpty) {
      return '';
    }

    // If the user entered the selected international calling
    // code manually without '+', do not prepend it twice.
    if (phoneDigits.startsWith(callingCode)) {
      final candidate = '+$phoneDigits';

      return isPlausibleInternationalPhone(candidate) ? candidate : '';
    }

    // Generic trunk-prefix compatibility.
    //
    // Many national formats use leading zeroes that are not part
    // of the international representation.
    //
    // This is intentionally conservative and does NOT claim full
    // national numbering-plan parsing.
    phoneDigits = phoneDigits.replaceFirst(RegExp(r'^0+'), '');

    if (phoneDigits.isEmpty) {
      return '';
    }

    final candidate = '+$callingCode$phoneDigits';

    return isPlausibleInternationalPhone(candidate) ? candidate : '';
  }

  /// Normalizes an international-formatted phone number.
  ///
  /// Examples:
  ///
  /// +1 (415) 555-2671
  /// -> +14155552671
  ///
  /// 0044 7700 900123
  /// -> +447700900123
  static String? normalizeInternationalPhone(String? phoneNumber) {
    if (phoneNumber == null) {
      return null;
    }

    var normalized = phoneNumber.trim();

    if (normalized.isEmpty) {
      return null;
    }

    if (normalized.startsWith('+')) {
      normalized = normalized.substring(1);
    } else if (normalized.startsWith('00')) {
      normalized = normalized.substring(2);
    }

    final digits = _digitsOnly(normalized);

    if (digits.isEmpty || digits.startsWith('0')) {
      return null;
    }

    return '+$digits';
  }

  /// Backward-compatible structural phone validator.
  ///
  /// This does NOT verify:
  /// - real ownership
  /// - SIM existence
  /// - assignment
  /// - carrier validity
  ///
  /// Firebase SMS verification remains authoritative.
  static bool isValidPhone({
    required String countryCode,
    required String phoneNumber,
  }) {
    final normalized = buildInternationalNumber(
      countryCode: countryCode,
      phoneNumber: phoneNumber,
    );

    if (normalized.isEmpty) {
      return false;
    }

    return isPlausibleInternationalPhone(normalized);
  }

  /// Conservative E.164 structural validation.
  ///
  /// E.164 permits at most 15 digits after '+'.
  ///
  /// Minimum 7 digits is used only to reject obviously
  /// incomplete values.
  static bool isPlausibleInternationalPhone(String? phoneNumber) {
    if (phoneNumber == null) {
      return false;
    }

    final trimmed = phoneNumber.trim();

    if (!trimmed.startsWith('+')) {
      return false;
    }

    final normalized = normalizeInternationalPhone(trimmed);

    if (normalized == null) {
      return false;
    }

    final digits = normalized.substring(1);

    if (digits.length < 7 || digits.length > 15) {
      return false;
    }

    if (digits.startsWith('0')) {
      return false;
    }

    return RegExp(r'^[0-9]+$').hasMatch(digits);
  }

  // ===========================================================
  // Country Search
  // ===========================================================

  /// Searches globally by:
  /// - country name
  /// - ISO country code
  /// - dial code
  ///
  /// Examples:
  /// United States
  /// united
  /// US
  /// +1
  /// United Kingdom
  /// GB
  /// +44
  /// Bangladesh
  /// BD
  /// +880
  ///
  /// Empty query returns the complete country collection.
  static List<Country> search(String keyword) {
    final query = _normalizeSearchText(keyword);

    if (query.isEmpty) {
      return allCountries;
    }

    final upperQuery = query.toUpperCase();

    final dialDigits = _digitsOnly(query);

    final results = <Country>[];

    for (final country in allCountries) {
      final normalizedName = _normalizeSearchText(country.name);

      final isoCode = country.countryCode.trim().toUpperCase();

      final phoneCode = _normalizedCountryPhoneCode(country);

      final matchesName = normalizedName.contains(query);

      final matchesIso =
          isoCode == upperQuery || isoCode.startsWith(upperQuery);

      final matchesDialCode =
          dialDigits.isNotEmpty && phoneCode.startsWith(dialDigits);

      if (matchesName || matchesIso || matchesDialCode) {
        results.add(country);
      }
    }

    return List<Country>.unmodifiable(results);
  }

  // ===========================================================
  // Profile / Account Persistence
  // ===========================================================

  /// Canonical users/{uid} country fields.
  static Map<String, String> toProfileData(Country country) {
    return <String, String>{
      'country': country.name.trim(),
      'countryCode': country.countryCode.trim().toUpperCase(),
    };
  }

  /// Full canonical country payload useful for:
  /// - Create Account
  /// - Login
  /// - Profile
  /// - Settings
  static Map<String, String> toCountryData(Country country) {
    final rawPhoneCode = normalizePhoneCode(country.phoneCode) ?? '';

    return <String, String>{
      'name': country.name.trim(),
      'country': country.name.trim(),
      'countryCode': country.countryCode.trim().toUpperCase(),
      'phoneCode': rawPhoneCode,
      'dialCode': rawPhoneCode.isEmpty ? '' : '+$rawPhoneCode',
      'flag': country.flagEmoji,
    };
  }

  // ===========================================================
  // Saved Country Resolution
  // ===========================================================

  /// Worldwide-neutral saved-country resolver.
  ///
  /// Returns null when no valid persisted country exists.
  ///
  /// Preferred for new JR CALL code because it does NOT
  /// silently force any country.
  static Country? resolveSavedCountryOrNull({
    String? country,
    String? countryCode,
    Country? fallback,
  }) {
    final normalizedCode = normalizeCountryCode(countryCode);

    if (normalizedCode != null) {
      final byCode = fromCountryCode(normalizedCode);

      if (byCode != null) {
        return byCode;
      }
    }

    final normalizedName = normalizeCountryName(country);

    if (normalizedName != null) {
      for (final item in allCountries) {
        if (_normalizeSearchText(item.name) == normalizedName) {
          return item;
        }
      }
    }

    return fallback;
  }

  /// Backward-compatible saved-country resolver.
  ///
  /// Existing finalized screens may depend on a guaranteed
  /// non-null Country return value.
  ///
  /// New worldwide screens should prefer
  /// [resolveSavedCountryOrNull].
  static Country resolveSavedCountry({
    String? country,
    String? countryCode,
    Country? fallback,
  }) {
    return resolveSavedCountryOrNull(
          country: country,
          countryCode: countryCode,
          fallback: fallback,
        ) ??
        defaultCountry;
  }

  // ===========================================================
  // Country Equality
  // ===========================================================

  static bool isSameCountry(Country? first, Country? second) {
    if (identical(first, second)) {
      return true;
    }

    if (first == null || second == null) {
      return false;
    }

    return first.countryCode.trim().toUpperCase() ==
        second.countryCode.trim().toUpperCase();
  }

  // ===========================================================
  // Internal Helpers
  // ===========================================================

  static String _normalizedCountryPhoneCode(Country country) {
    return normalizePhoneCode(country.phoneCode) ?? '';
  }

  static String _digitsOnly(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  static String _normalizeSearchText(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  // ===========================================================
  // Cache Management
  // ===========================================================

  /// Primarily useful for tests and development/hot reload.
  static void clearCache() {
    _cachedCountries = null;
  }
}
