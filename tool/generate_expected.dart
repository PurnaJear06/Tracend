// Regenerates the `expected` oracle blocks for the shared Pass 5 fixtures.
//
// Usage (repo wrapper / pinned SDK dart):
//   dart run tool/generate_expected.dart <fixture-dir> [--force] [--write]
//
// Default: prints one {"fixture": name, "expected": {...}} line per fixture
// that lacks an `expected` block (or all of them with --force). --write
// injects/refreshes the `expected` key inside each fixture file in place
// (single-line JSON preserved — the pgTAP harness \set-captures these files
// via `cat`, which requires no embedded newlines).
//
// Both consumers assert against these numbers: the Dart self-test
// (test/reference/recovery_reference_test.dart) and the pgTAP parity test
// (supabase/tests/database/reference_parity_test.sql). Change a fixture's
// inputs → rerun with --write --force → both sides re-anchor. The
// hand-computed anchors in the Dart/pgTAP suites stay independent of this
// tool, so the oracle is never circular.
//
// The reference is pure Dart with no imports outside dart:convert/math and
// the test/ tree, so this runner also stays runnable by plain `dart run`.

import 'dart:convert';
import 'dart:io';

import '../test/reference/recovery_reference.dart';

double? _z3(double? v) => v == null ? null : double.parse(v.toStringAsFixed(3));
double? _sub1(double? v) =>
    v == null ? null : double.parse(v.toStringAsFixed(1));
double? _x2(double? v) => v == null ? null : double.parse(v.toStringAsFixed(2));

Map<String, Object?> _expectedFor(ReferenceResult result) {
  final day = result.day;
  return {
    'recovery': day.recovery?.round(),
    'data_confidence': day.dataConfidence,
    'missing_components': day.missingComponents,
    'hrv_z': _z3(day.zHrv),
    'rhr_z': _z3(day.zRhr),
    'sleep_z': _z3(day.zSleep),
    'resp_rate_z': _z3(day.zResp),
    'prev_strain_z': _z3(day.zPrevStrain),
    'sleep_quality': day.sleepQuality?.round(),
    'duration_score': _sub1(day.subDurationScore),
    'efficiency_score': _sub1(day.subEfficiencyScore),
    'restorative_score': _sub1(day.subRestorativeScore),
    'consistency_score': _sub1(day.subConsistencyScore),
    'sleep_breakdown_missing': day.sleepBreakdownMissing,
    'sleep_debt_minutes': day.sleepDebtMinutes,
    'daily_strain': _x2(day.dailyStrain),
    'acwr': _x2(day.acwr),
    'monotony': _x2(day.monotony),
    'duration_score_floor_used': result.durationScoreFloorUsed,
  };
}

void main(List<String> args) {
  final force = args.contains('--force');
  final write = args.contains('--write');
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.length != 1) {
    stderr.writeln(
      'usage: dart run tool/generate_expected.dart <fixture-dir> [--force] [--write]',
    );
    exit(64);
  }
  final dir = Directory(positional[0]);
  if (!dir.existsSync()) {
    stderr.writeln('fixture dir not found: ${dir.path}');
    exit(66);
  }
  var written = 0;
  final files = dir.listSync()..sort((a, b) => a.path.compareTo(b.path));
  for (final entity in files) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final decoded = jsonDecode(entity.readAsStringSync());
    if (decoded is! Map<String, dynamic>) continue;
    if (!force && decoded.containsKey('expected') && !write) continue;
    final scenario = ReferenceScenario.fromJson(decoded);
    final expected = _expectedFor(computeReferenceDay(scenario));
    if (write) {
      decoded['expected'] = expected;
      // jsonEncode emits single-line JSON — required by the pgTAP harness
      // (psql \set backtick capture cannot span lines).
      entity.writeAsStringSync(jsonEncode(decoded));
      written++;
      stderr.writeln('wrote expected block: ${scenario.name}');
    } else {
      stdout.writeln(
        jsonEncode({'fixture': scenario.name, 'expected': expected}),
      );
    }
  }
  if (write) stderr.writeln('$written fixture(s) updated.');
}
