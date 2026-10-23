import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Code the database stores for "another country": no national guidance
/// applies, and the time zone is not used to guess one (`set_my_country_v1`).
const otherCountryCode = 'ZZ';

/// The countries whose national food and body-size guidance the research
/// library holds (decision D5), in the order the picker shows them.
const regionalModuleCountries = <String, String>{
  'AU': 'Australia',
  'IN': 'India',
  'GB': 'United Kingdom',
  'US': 'United States',
};

/// The athlete's country in words, or null when none is chosen.
String? countryLabel(String? code) {
  if (code == null) return null;
  if (code == otherCountryCode) return 'Another country';
  return regionalModuleCountries[code] ?? code;
}

/// Whether the library holds national guidance for [code].
bool hasRegionalModule(String? code) =>
    code != null && regionalModuleCountries.containsKey(code);

/// Reads the `get_my_country_v1` and `set_my_country_v1` answer: the stored
/// two-letter code, or null for none. Anything else is refused, so a changed
/// contract shows up as an error rather than as an unset country.
String? parseCountryCode(Object? json) {
  if (json is! Map || json['schema_version'] != '1.0') {
    throw const FormatException('The country answer is unreadable.');
  }
  final code = json['country_code'];
  if (code == null) return null;
  if (code is String && RegExp(r'^[A-Z]{2}$').hasMatch(code)) return code;
  throw const FormatException('The country answer is unreadable.');
}

/// The athlete's optional country. It only chooses which national guidelines
/// Coach may cite; no plan number depends on it.
abstract interface class RegionRepository {
  /// The stored country code, or null when none is chosen.
  Future<String?> load();

  /// Stores [countryCode] (null clears it) and returns what is stored.
  Future<String?> save(String? countryCode);
}

class SupabaseRegionRepository implements RegionRepository {
  SupabaseRegionRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<String?> load() async =>
      parseCountryCode(await _client.rpc<dynamic>('get_my_country_v1'));

  @override
  Future<String?> save(String? countryCode) async {
    try {
      return parseCountryCode(
        await _client.rpc<dynamic>(
          'set_my_country_v1',
          params: {'p_country_code': countryCode},
        ),
      );
    } on PostgrestException catch (error) {
      debugPrint('Non-critical error: country not saved: $error');
      rethrow;
    }
  }
}

/// Builds without a backend: no country is stored and none can be set.
class FixtureRegionRepository implements RegionRepository {
  const FixtureRegionRepository();

  @override
  Future<String?> load() async => null;

  @override
  Future<String?> save(String? countryCode) =>
      throw StateError('Configure Supabase.');
}
