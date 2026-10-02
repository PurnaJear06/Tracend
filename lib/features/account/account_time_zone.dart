import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps `user_accounts.timezone` equal to the device's IANA time zone, so the
/// server's local dates (onboarding, the Coach, check-ins, approval) match the
/// athlete's day. Without it every account stays at the default UTC.
class AccountTimeZone {
  AccountTimeZone({
    required Future<String?> Function() deviceZone,
    required Future<String?> Function() storedZone,
    required Future<void> Function(String zone) storeZone,
  }) : _deviceZone = deviceZone,
       _storedZone = storedZone,
       _storeZone = storeZone;

  factory AccountTimeZone.supabase(SupabaseClient client) {
    const channel = MethodChannel('com.tracend.app/time_zone');
    return AccountTimeZone(
      deviceZone: () => channel.invokeMethod<String>('identifier'),
      storedZone: () async {
        final user = client.auth.currentUser;
        if (user == null) return null;
        final row = await client
            .from('user_accounts')
            .select('timezone')
            .eq('id', user.id)
            .maybeSingle();
        return row?['timezone'] as String?;
      },
      storeZone: (zone) => client.rpc<dynamic>(
        'set_my_timezone',
        params: {'timezone_name': zone},
      ),
    );
  }

  final Future<String?> Function() _deviceZone;
  final Future<String?> Function() _storedZone;
  final Future<void> Function(String zone) _storeZone;

  /// Stores the device zone when it differs from the account's. Never throws:
  /// a failure leaves the stored zone as it was, and the next launch retries.
  Future<void> sync() async {
    try {
      final device = await _deviceZone();
      if (device == null || device.isEmpty) return;
      if (await _storedZone() == device) return;
      await _storeZone(device);
    } catch (error) {
      debugPrint('Non-critical error: time zone not stored: $error');
    }
  }
}
