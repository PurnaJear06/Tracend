import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/health/health_models.dart';

// The stale-sync rule is shared with the Coach watch-outs (watch_outs.ts), which read the same
// cases: elapsed time since the last successful sync is more than two days, so the two cannot
// drift apart.
const _casesPath =
    'supabase/functions/_shared/coach_context/contributors/stale_sync_cases.json';

void main() {
  final cases =
      (jsonDecode(File(_casesPath).readAsStringSync())
              as Map<String, dynamic>)['cases']
          as List;

  test('the stale-sync cases are the app rule', () {
    expect(cases, isNotEmpty);
    for (final item in cases) {
      final entry = item as Map<String, dynamic>;
      final state = deriveHealthConnectionState(
        now: DateTime.parse(entry['now'] as String),
        lastSuccessfulSync: DateTime.parse(entry['last_sync'] as String),
        availableMetrics: HealthMetric.values.toSet(),
      );
      expect(
        state == HealthConnectionState.stale,
        entry['stale'] as bool,
        reason: entry['name'] as String,
      );
    }
  });
}
