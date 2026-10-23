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
  group('Country contract: get_my_country_v1 / set_my_country_v1 1.1', () {
    // The key list is the contract: add keys, never remove or rename them.
    // supabase/tests/database/regional_modules_test.sql asserts the same list
    // against the database.
    const keys = ['country_code', 'effective_regions', 'schema_version'];

    for (final name in const [
      'my_country_v1_1.json',
      'my_country_unset_v1_1.json',
    ]) {
      test('$name carries exactly the contract keys', () {
        final fixture = _fixture(name);
        expect(fixture['schema_version'], '1.1');
        expect(fixture.keys.toList()..sort(), keys);
      });
    }

    test('a stored country reads with the regions in effect', () {
      final region = parseAccountRegion(_fixture('my_country_v1_1.json'));
      expect(region.countryCode, 'AU');
      expect(region.effectiveRegions, ['AU', 'global']);
      expect(region.guidanceCountries, ['AU']);
    });

    test('an unset country can still have a country in effect', () {
      final region = parseAccountRegion(_fixture('my_country_unset_v1_1.json'));
      expect(region.countryCode, isNull);
      expect(region.effectiveRegions, ['IN', 'global']);
      expect(region.guidanceCountries, ['IN']);
    });

    test('with only global in effect there is no guidance country', () {
      const region = AccountRegion();
      expect(region.guidanceCountries, isEmpty);
      // A region with no module (a locale of another country) is no country.
      expect(
        const AccountRegion(
          effectiveRegions: ['FR', 'global'],
        ).guidanceCountries,
        isEmpty,
      );
      // A language of one country and a time zone of another select both.
      expect(
        const AccountRegion(
          effectiveRegions: ['GB', 'IN', 'global'],
        ).guidanceCountries,
        ['GB', 'IN'],
      );
    });

    test('a 1.x answer from a later minor version still reads', () {
      final region = parseAccountRegion({
        ..._fixture('my_country_v1_1.json'),
        'schema_version': '1.2',
        'future_key': true,
      });
      expect(region.countryCode, 'AU');
    });

    test('an unreadable answer is refused, never read as unset', () {
      final good = _fixture('my_country_v1_1.json');
      for (final bad in <Object?>[
        null,
        'AU',
        {
          'country_code': 'AU',
          'effective_regions': ['global'],
        },
        {...good, 'schema_version': '2.0'},
        {...good, 'schema_version': 1.1},
        {...good, 'country_code': 'au'},
        {...good, 'country_code': 'AUS'},
        {...good, 'country_code': 7},
        {...good}..remove('effective_regions'),
        {...good, 'effective_regions': 'global'},
        {
          ...good,
          'effective_regions': ['AU'],
        },
        {
          ...good,
          'effective_regions': ['global', 'australia'],
        },
      ]) {
        expect(
          () => parseAccountRegion(bad),
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
