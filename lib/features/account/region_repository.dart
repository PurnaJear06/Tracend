import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/shared/diagnostics.dart';

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

/// The athlete's country as the server reports it: the stored choice (null
/// when none) and the library regions in effect now, which with no choice
/// still follow the account's time zone or language.
class AccountRegion {
  const AccountRegion({
    this.countryCode,
    this.effectiveRegions = const ['global'],
  });

  final String? countryCode;
  final List<String> effectiveRegions;

  /// Every country with national guidance that Coach is using, whether the
  /// athlete chose it or the account's time zone or language selects it (a
  /// language of one country and a time zone of another select both).
  List<String> get guidanceCountries => [
    for (final region in effectiveRegions)
      if (hasRegionalModule(region)) region,
  ];
}

/// Reads the `get_my_country_v1` and `set_my_country_v1` answer (1.x). Anything
/// unreadable is refused, so a changed contract shows up as an error rather
/// than as an unset country.
AccountRegion parseAccountRegion(Object? json) {
  const unreadable = FormatException('The country answer is unreadable.');
  if (json is! Map) throw unreadable;
  final version = json['schema_version'];
  if (version is! String || !version.startsWith('1.')) throw unreadable;
  final code = json['country_code'];
  if (code != null &&
      !(code is String && RegExp(r'^[A-Z]{2}$').hasMatch(code))) {
    throw unreadable;
  }
  final regions = json['effective_regions'];
  if (regions is! List ||
      !regions.contains('global') ||
      !regions.every(
        (region) =>
            region is String && RegExp(r'^(global|[A-Z]{2})$').hasMatch(region),
      )) {
    throw unreadable;
  }
  return AccountRegion(
    countryCode: code as String?,
    effectiveRegions: List<String>.unmodifiable(regions.cast<String>()),
  );
}

/// The athlete's optional country. It only chooses which national guidelines
/// Coach may cite; no plan number depends on it.
abstract interface class RegionRepository {
  Future<AccountRegion> load();

  /// Stores [countryCode] (null clears it) and returns what is now in effect.
  Future<AccountRegion> save(String? countryCode);
}

class SupabaseRegionRepository implements RegionRepository {
  SupabaseRegionRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<AccountRegion> load() async =>
      parseAccountRegion(await _client.rpc<dynamic>('get_my_country_v1'));

  @override
  Future<AccountRegion> save(String? countryCode) async {
    try {
      return parseAccountRegion(
        await _client.rpc<dynamic>(
          'set_my_country_v1',
          params: {'p_country_code': countryCode},
        ),
      );
    } on PostgrestException catch (error) {
      logNonCritical(error, 'country not saved');
      rethrow;
    }
  }
}

/// Builds without a backend: no country is stored and none can be set.
class FixtureRegionRepository implements RegionRepository {
  const FixtureRegionRepository();

  @override
  Future<AccountRegion> load() async => const AccountRegion();

  @override
  Future<AccountRegion> save(String? countryCode) =>
      throw StateError('Configure Supabase.');
}
