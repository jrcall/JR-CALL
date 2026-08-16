// ===========================================================
// JR CALL
// File: widget_test.dart
// Location: test/widget_test.dart
//
// Description:
// Production-safe JR CALL foundation contract tests.
//
// Purpose:
// - Remove the default Flutter counter template test.
// - Verify global country support.
// - Verify ISO country-code normalization.
// - Verify international/E.164-style phone normalization.
// - Verify country search behavior.
// - Verify profile country persistence data.
// - Keep tests deterministic and independent from live Firebase,
//   WebRTC, permissions, network access, and production backends.
//
// Important:
// - Do NOT initialize real Firebase in this test file.
// - Do NOT perform real phone OTP.
// - Do NOT contact TURN/STUN servers.
// - Do NOT request device permissions.
// - Real Auth/Profile/Discovery/Call acceptance testing belongs
//   to integration and real-device validation.
// ===========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:jr_call/utils/country_helper.dart';

void main() {
  group('JR CALL CountryHelper', () {
    setUp(() {
      CountryHelper.clearCache();
    });

    test('provides a complete global country collection', () {
      final countries = CountryHelper.allCountries;

      expect(countries, isNotEmpty);
      expect(countries.length, greaterThan(100));

      expect(CountryHelper.fromCountryCode('BD')?.name, 'Bangladesh');

      expect(CountryHelper.fromCountryCode('US')?.countryCode, 'US');

      expect(CountryHelper.fromCountryCode('GB')?.countryCode, 'GB');

      expect(CountryHelper.fromCountryCode('IN')?.countryCode, 'IN');
    });

    test('normalizes ISO alpha-2 country codes safely', () {
      expect(CountryHelper.normalizeCountryCode(' bd '), 'BD');

      expect(CountryHelper.normalizeCountryCode('us'), 'US');

      expect(CountryHelper.normalizeCountryCode('GB'), 'GB');

      expect(CountryHelper.normalizeCountryCode(''), isNull);

      expect(CountryHelper.normalizeCountryCode('USA'), isNull);

      expect(CountryHelper.normalizeCountryCode('1'), isNull);
    });

    test('validates supported country codes globally', () {
      expect(CountryHelper.isValidCountryCode('BD'), isTrue);

      expect(CountryHelper.isValidCountryCode('US'), isTrue);

      expect(CountryHelper.isValidCountryCode('GB'), isTrue);

      expect(CountryHelper.isValidCountryCode('IN'), isTrue);

      expect(CountryHelper.isValidCountryCode('ZZ'), isFalse);
    });

    test('resolves countries by name and ISO code', () {
      final bangladesh = CountryHelper.fromCountryName(' Bangladesh ');

      final unitedStates = CountryHelper.fromIsoCode('us');

      final unitedKingdom = CountryHelper.fromCountryName('united kingdom');

      expect(bangladesh?.countryCode, 'BD');

      expect(unitedStates?.countryCode, 'US');

      expect(unitedKingdom?.countryCode, 'GB');
    });

    test('resolves international calling codes', () {
      final bangladesh = CountryHelper.fromPhoneCode('+880');

      expect(bangladesh?.countryCode, 'BD');

      expect(CountryHelper.getDialCode('BD'), '+880');

      expect(CountryHelper.getRawPhoneCode('BD'), '880');

      expect(CountryHelper.getDialCode('US'), '+1');

      expect(CountryHelper.getDialCode('GB'), '+44');
    });

    test('supports countries that share the same calling code', () {
      final countries = CountryHelper.countriesFromPhoneCode('+1');

      expect(countries, isNotEmpty);

      expect(countries.any((country) => country.countryCode == 'US'), isTrue);
    });

    test('builds Bangladesh phone number in international format', () {
      final phone = CountryHelper.buildInternationalNumber(
        countryCode: 'BD',
        phoneNumber: '01712345678',
      );

      expect(phone, '+8801712345678');

      expect(CountryHelper.isPlausibleInternationalPhone(phone), isTrue);
    });

    test('builds US phone number in international format', () {
      final phone = CountryHelper.buildInternationalNumber(
        countryCode: 'US',
        phoneNumber: '(415) 555-2671',
      );

      expect(phone, '+14155552671');

      expect(CountryHelper.isPlausibleInternationalPhone(phone), isTrue);
    });

    test('preserves already international phone numbers', () {
      final ukNumber = CountryHelper.buildInternationalNumber(
        countryCode: 'GB',
        phoneNumber: '+447911123456',
      );

      expect(ukNumber, '+447911123456');

      expect(CountryHelper.isPlausibleInternationalPhone(ukNumber), isTrue);
    });

    test('normalizes 00 international prefix', () {
      final normalized = CountryHelper.normalizeInternationalPhone(
        '0044 7911 123456',
      );

      expect(normalized, '+447911123456');
    });

    test('rejects clearly invalid international phone values', () {
      expect(CountryHelper.isPlausibleInternationalPhone('+123'), isFalse);

      expect(
        CountryHelper.isPlausibleInternationalPhone('+1234567890123456'),
        isFalse,
      );

      expect(CountryHelper.isPlausibleInternationalPhone(''), isFalse);

      expect(CountryHelper.isPlausibleInternationalPhone(null), isFalse);
    });

    test('searches countries by country name', () {
      final results = CountryHelper.search('Bangladesh');

      expect(results.any((country) => country.countryCode == 'BD'), isTrue);
    });

    test('searches countries by ISO country code', () {
      final results = CountryHelper.search('US');

      expect(results.any((country) => country.countryCode == 'US'), isTrue);
    });

    test('searches countries by international calling code', () {
      final results = CountryHelper.search('+880');

      expect(results.any((country) => country.countryCode == 'BD'), isTrue);
    });

    test('empty country search returns complete collection', () {
      final results = CountryHelper.search('');

      expect(results.length, CountryHelper.allCountries.length);
    });

    test('creates canonical profile country data', () {
      final country = CountryHelper.fromCountryCode('BD');

      expect(country, isNotNull);

      final profileData = CountryHelper.toProfileData(country!);

      expect(profileData['country'], 'Bangladesh');

      expect(profileData['countryCode'], 'BD');
    });

    test('creates canonical account country data', () {
      final country = CountryHelper.fromCountryCode('US');

      expect(country, isNotNull);

      final countryData = CountryHelper.toCountryData(country!);

      expect(countryData['countryCode'], 'US');

      expect(countryData['phoneCode'], '1');

      expect(countryData['dialCode'], '+1');

      expect(countryData['flag'], isNotEmpty);
    });

    test('resolves saved profile country by ISO code first', () {
      final country = CountryHelper.resolveSavedCountry(
        country: 'Bangladesh',
        countryCode: 'US',
      );

      expect(country.countryCode, 'US');
    });

    test('resolves saved profile country from country name', () {
      final country = CountryHelper.resolveSavedCountry(
        country: 'United Kingdom',
      );

      expect(country.countryCode, 'GB');
    });

    test('falls back safely when saved country data is invalid', () {
      final country = CountryHelper.resolveSavedCountry(
        country: 'Invalid Country',
        countryCode: 'ZZ',
      );

      expect(country.countryCode, CountryHelper.defaultCountryCode);
    });

    test('country comparison uses canonical ISO identity', () {
      final first = CountryHelper.fromCountryCode('BD');
      final second = CountryHelper.fromCountryCode('bd');
      final different = CountryHelper.fromCountryCode('US');

      expect(CountryHelper.isSameCountry(first, second), isTrue);

      expect(CountryHelper.isSameCountry(first, different), isFalse);
    });
  });
}
