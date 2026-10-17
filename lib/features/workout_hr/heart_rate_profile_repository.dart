import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/workout_hr/heart_rate_profile.dart';

/// Anything that can work out the athlete's heart-rate profile. The Apple
/// Health repository offers it so the Health sheet can show the zones.
abstract interface class HeartRateProfileSource {
  /// The profile as of today, or null when the server could not be read.
  Future<HeartRateProfile?> loadHeartRateProfile();
}

/// Reads `get_my_heart_rate_inputs_v1` and works the profile out on the phone.
class SupabaseHeartRateProfileRepository implements HeartRateProfileSource {
  SupabaseHeartRateProfileRepository(this._client, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final SupabaseClient _client;
  final DateTime Function() _now;

  @override
  Future<HeartRateProfile?> loadHeartRateProfile() async {
    final today = _now();
    final value = await _client.rpc(
      'get_my_heart_rate_inputs_v1',
      params: {
        'local_date':
            '${today.year.toString().padLeft(4, '0')}-'
            '${today.month.toString().padLeft(2, '0')}-'
            '${today.day.toString().padLeft(2, '0')}',
      },
    );
    final inputs = HeartRateInputs.tryParse(value);
    return inputs == null ? null : buildHeartRateProfile(inputs);
  }
}
