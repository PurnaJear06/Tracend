import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/account/region_repository.dart';

Map<String, dynamic> _fixture(String name) {
  final file = File('test/contract/fixtures/$name');
  if (!file.existsSync()) {
    throw FileSystemException('Contract fixture not found: $name');
  }
  return Map<String, dynamic>.from(json.decode(file.readAsStringSync()) as Map);
}

void main() {
  group('Country contract: get_my_country_v1 / set_my_country_v1 1.0', () {
    // The key list is the contract: add keys, never remove or rename them.
    // supabase/tests/database/regional_modules_test.sql asserts the same list
    // against the database.
    const keys = ['country_code', 'schema_version'];

    for (final name in const [
      'my_country_v1_0.json',
      'my_country_unset_v1_0.json',
    ]) {
      test('$name carries exactly the contract keys', () {
        final fixture = _fixture(name);
        expect(fixture['schema_version'], '1.0');
        expect(fixture.keys.toList()..sort(), keys);
      });
    }

    test('a stored country reads as its code and an unset one as null', () {
      expect(parseCountryCode(_fixture('my_country_v1_0.json')), 'AU');
      expect(parseCountryCode(_fixture('my_country_unset_v1_0.json')), isNull);
    });

    test('an unreadable answer is refused, never read as unset', () {
      for (final bad in <Object?>[
        null,
        'AU',
        {'country_code': 'AU'},
        {'schema_version': '2.0', 'country_code': 'AU'},
        {'schema_version': '1.0', 'country_code': 'au'},
        {'schema_version': '1.0', 'country_code': 'AUS'},
        {'schema_version': '1.0', 'country_code': 7},
      ]) {
        expect(
          () => parseCountryCode(bad),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });

    test('the countries with national guidance match the library regions', () {
      // Each code is a region tag of at least one source in
      // supabase/library/sources (library_content_test.ts asserts the same
      // four from the other side).
      expect(regionalModuleCountries.keys.toSet(), {'AU', 'IN', 'GB', 'US'});
      expect(otherCountryCode, 'ZZ');
      expect(hasRegionalModule('AU'), isTrue);
      expect(hasRegionalModule('ZZ'), isFalse);
      expect(hasRegionalModule(null), isFalse);
      expect(countryLabel('GB'), 'United Kingdom');
      expect(countryLabel('ZZ'), 'Another country');
      expect(countryLabel('FR'), 'FR');
      expect(countryLabel(null), isNull);
    });
  });
}
