import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/shared/diagnostics.dart';

/// The athlete's agreement to Tracend keeping her cycle data. It is recorded
/// apart from [LegalConsent] on purpose: that enum is asked of every athlete,
/// and this is asked only of someone who turns cycle tracking on. The
/// database refuses to turn tracking on until it holds a grant.
abstract final class CycleConsent {
  /// The `consent_type` stored.
  static const type = 'cycle_data';

  /// `site/src/pages/privacy.astro`, the page that names cycle data. It is the
  /// same date as the privacy notice version (`test/legal_versions_test.dart`).
  static const noticeVersion = '2026-11-27';
}

abstract interface class _Coded {
  String get code;
}

/// How her cycle works, in her own words (`cycle_settings.status`).
enum CycleStatus implements _Coded {
  regular('regular'),
  irregular('irregular'),
  hormonalContraception('hormonal_contraception'),
  noPeriods('no_periods');

  const CycleStatus(this.code);

  @override
  final String code;

  /// Whether the cycle is worked out from her logs and given a phase.
  bool get hasCycleDays => this == regular || this == irregular;
}

enum CyclePhase implements _Coded {
  period('period'),
  firstHalf('first_half'),
  secondHalf('second_half');

  const CyclePhase(this.code);

  @override
  final String code;
}

enum CycleConfidence implements _Coded {
  low('low'),
  medium('medium'),
  high('high');

  const CycleConfidence(this.code);

  @override
  final String code;
}

/// How heavy a day's bleeding was. No bleeding is a null flow, never a value.
enum PeriodFlow implements _Coded {
  spotting('spotting'),
  light('light'),
  medium('medium'),
  heavy('heavy'),
  unspecified('unspecified');

  const PeriodFlow(this.code);

  @override
  final String code;

  /// Whether the day counts as a period day (spotting does not).
  bool get isPeriodDay => this != spotting;
}

enum CycleCramps implements _Coded {
  none('none'),
  mild('mild'),
  strong('strong');

  const CycleCramps(this.code);

  @override
  final String code;
}

enum CycleSource implements _Coded {
  manual('manual'),
  appleHealth('apple_health');

  const CycleSource(this.code);

  @override
  final String code;
}

/// One day she logged, or Apple Health holds.
class CycleDay {
  const CycleDay({
    required this.date,
    required this.flow,
    required this.cramps,
    required this.isStart,
    required this.source,
  });

  final DateTime date;

  /// Null is "no bleeding this day", said by her.
  final PeriodFlow? flow;
  final CycleCramps? cramps;
  final bool isStart;
  final CycleSource source;
}

/// One cycle as the server counted it: where it began and how long it ran.
class CycleRecord {
  const CycleRecord({
    required this.startDate,
    required this.lengthDays,
    required this.used,
  });

  final DateTime startDate;

  /// Null for the cycle still going.
  final int? lengthDays;

  /// False for the cycle still going and for a length left out of the typical
  /// length (a month that went unlogged).
  final bool used;
}

/// What the server works out from her answers and logs today
/// (`private.cycle_state`). Every field is null when it cannot be known.
class CycleState {
  const CycleState({
    this.cycleDay,
    this.periodDay,
    this.phase,
    this.confidence,
    this.expectedFrom,
    this.expectedTo,
    this.lateDays,
    this.noPeriodLong = false,
    this.weightWaterWindow = false,
  });

  final int? cycleDay;
  final int? periodDay;
  final CyclePhase? phase;
  final CycleConfidence? confidence;
  final DateTime? expectedFrom;
  final DateTime? expectedTo;
  final int? lateDays;

  /// No period for 3 months (regular) or 6 months (irregular).
  final bool noPeriodLong;

  /// Weight tends to run higher now (the days around a period).
  final bool weightWaterWindow;
}

/// The cycle answer (`get_my_cycle_v1` and the RPCs that change it, 1.x).
class CycleAnswer {
  const CycleAnswer({
    this.trackingEnabled = false,
    this.status,
    this.typicalCycleDays,
    this.appleHealthEnabled = false,
    this.state = const CycleState(),
    this.recentDays = const [],
    this.cycles = const [],
  });

  /// Tracking is off: what Today and every other screen shows for anyone who
  /// never turned it on.
  static const off = CycleAnswer();

  final bool trackingEnabled;
  final CycleStatus? status;
  final int? typicalCycleDays;
  final bool appleHealthEnabled;
  final CycleState state;

  /// The last 60 days she logged or Apple Health holds, oldest first.
  final List<CycleDay> recentDays;

  /// The last up to 7 cycles, oldest first; the newest is the one going now.
  final List<CycleRecord> cycles;

  /// The day she logged for [date], if any.
  CycleDay? dayOn(DateTime date) {
    for (final day in recentDays) {
      if (day.date == DateTime(date.year, date.month, date.day)) return day;
    }
    return null;
  }
}

/// What an import into the database changed (`import_cycle_days_v1`).
class CycleImport {
  const CycleImport({required this.imported, required this.removed});

  final int imported;
  final int removed;
}

/// A period day read from Apple Health, ready to send.
class CycleHealthDay {
  const CycleHealthDay({
    required this.date,
    required this.flow,
    required this.isStart,
  });

  final DateTime date;
  final PeriodFlow flow;
  final bool isStart;
}

/// `YYYY-MM-DD` for [date], the form the database takes.
String cycleDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

const _unreadable = FormatException('The cycle answer is unreadable.');

T? _coded<T extends _Coded>(Object? raw, List<T> values) {
  if (raw == null) return null;
  for (final value in values) {
    if (value.code == raw) return value;
  }
  throw _unreadable;
}

bool _flag(Object? raw) {
  if (raw is! bool) throw _unreadable;
  return raw;
}

int? _count(Object? raw, {required int min, required int max}) {
  if (raw == null) return null;
  if (raw is! int || raw < min || raw > max) throw _unreadable;
  return raw;
}

final _dateShape = RegExp(r'^\d{4}-\d{2}-\d{2}$');

DateTime? _date(Object? raw) {
  if (raw == null) return null;
  if (raw is! String || !_dateShape.hasMatch(raw)) throw _unreadable;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null || cycleDateKey(parsed) != raw) throw _unreadable;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

DateTime _requiredDate(Object? raw) => _date(raw) ?? (throw _unreadable);

Map<Object?, Object?> _map(Object? raw) {
  if (raw is! Map) throw _unreadable;
  return raw;
}

/// Reads the `get_my_cycle_v1` answer (1.x). Anything unreadable is refused,
/// so a changed contract shows up as an error rather than as a cycle that is
/// off: Today then shows no cycle line, and Account says the answer could not
/// be read.
CycleAnswer parseCycleAnswer(Object? json) {
  final root = _map(json);
  final version = root['schema_version'];
  if (version is! String || !version.startsWith('1.')) throw _unreadable;
  final state = _map(root['state']);
  final recent = root['recent_days'];
  final cycles = root['cycles'];
  if (recent is! List || cycles is! List) throw _unreadable;
  return CycleAnswer(
    trackingEnabled: _flag(root['tracking_enabled']),
    status: _coded(root['status'], CycleStatus.values),
    typicalCycleDays: _count(root['typical_cycle_days'], min: 15, max: 60),
    appleHealthEnabled: _flag(root['apple_health_enabled']),
    state: CycleState(
      cycleDay: _count(state['cycle_day'], min: 1, max: 100000),
      periodDay: _count(state['period_day'], min: 1, max: 100000),
      phase: _coded(state['phase'], CyclePhase.values),
      confidence: _coded(state['confidence'], CycleConfidence.values),
      expectedFrom: _date(state['expected_from']),
      expectedTo: _date(state['expected_to']),
      lateDays: _count(state['late_days'], min: 0, max: 100000),
      noPeriodLong: _flag(state['no_period_long']),
      weightWaterWindow: _flag(state['weight_water_window']),
    ),
    recentDays: List.unmodifiable([
      for (final item in recent)
        () {
          final day = _map(item);
          final source = _coded(day['source'], CycleSource.values);
          if (source == null) throw _unreadable;
          return CycleDay(
            date: _requiredDate(day['local_date']),
            flow: _coded(day['flow'], PeriodFlow.values),
            cramps: _coded(day['cramps'], CycleCramps.values),
            isStart: _flag(day['is_start']),
            source: source,
          );
        }(),
    ]),
    cycles: List.unmodifiable([
      for (final item in cycles)
        () {
          final record = _map(item);
          return CycleRecord(
            startDate: _requiredDate(record['start_date']),
            lengthDays: _count(record['length_days'], min: 1, max: 100000),
            used: _flag(record['used']),
          );
        }(),
    ]),
  );
}

/// Reads the `import_cycle_days_v1` answer (1.x).
CycleImport parseCycleImport(Object? json) {
  final root = _map(json);
  final version = root['schema_version'];
  if (version is! String || !version.startsWith('1.')) throw _unreadable;
  final imported = _count(root['imported'], min: 0, max: 100000);
  final removed = _count(root['removed'], min: 0, max: 100000);
  if (imported == null || removed == null) throw _unreadable;
  return CycleImport(imported: imported, removed: removed);
}

/// The athlete's optional cycle tracking. Nothing here is kept on the phone:
/// every screen reads the answer from the server.
abstract interface class CycleRepository {
  Future<CycleAnswer> load();

  /// Turns tracking on or off and stores how her cycle works. Turning it on
  /// needs her agreement ([grantConsent]) first.
  Future<CycleAnswer> saveSettings({
    required bool trackingEnabled,
    required CycleStatus? status,
    required int? typicalCycleDays,
    required bool appleHealthEnabled,
  });

  /// Stores one day. A null [flow] says there was no bleeding that day.
  Future<CycleAnswer> logDay({
    required DateTime date,
    required PeriodFlow? flow,
    CycleCramps? cramps,
    bool isStart = false,
  });

  /// Replaces the Apple Health days in [from] to [to] with [days].
  Future<CycleImport> importDays({
    required DateTime from,
    required DateTime to,
    required List<CycleHealthDay> days,
  });

  /// Removes every logged day and answer, turns tracking off and withdraws the
  /// agreement.
  Future<CycleAnswer> deleteAll();

  /// Whether her newest record for cycle data is a grant.
  Future<bool> consentGranted();

  /// Records her agreement to [CycleConsent.noticeVersion].
  Future<void> grantConsent();
}

class SupabaseCycleRepository implements CycleRepository {
  SupabaseCycleRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Authentication required.');
    return user.id;
  }

  Future<CycleAnswer> _answer(
    String function, [
    Map<String, Object?>? params,
  ]) async {
    try {
      return parseCycleAnswer(
        await _client.rpc<dynamic>(function, params: params),
      );
    } on PostgrestException catch (error) {
      logNonCritical(error, 'cycle call failed');
      rethrow;
    }
  }

  @override
  Future<CycleAnswer> load() => _answer('get_my_cycle_v1');

  @override
  Future<CycleAnswer> saveSettings({
    required bool trackingEnabled,
    required CycleStatus? status,
    required int? typicalCycleDays,
    required bool appleHealthEnabled,
  }) => _answer('set_my_cycle_settings_v1', {
    'p_tracking_enabled': trackingEnabled,
    'p_status': status?.code,
    'p_typical_cycle_days': typicalCycleDays,
    'p_apple_health_enabled': appleHealthEnabled,
  });

  @override
  Future<CycleAnswer> logDay({
    required DateTime date,
    required PeriodFlow? flow,
    CycleCramps? cramps,
    bool isStart = false,
  }) => _answer('log_cycle_day_v1', {
    'p_local_date': cycleDateKey(date),
    'p_flow': flow?.code,
    'p_cramps': cramps?.code,
    'p_is_start': isStart,
  });

  @override
  Future<CycleImport> importDays({
    required DateTime from,
    required DateTime to,
    required List<CycleHealthDay> days,
  }) async {
    try {
      return parseCycleImport(
        await _client.rpc<dynamic>(
          'import_cycle_days_v1',
          params: {
            'p_from': cycleDateKey(from),
            'p_to': cycleDateKey(to),
            'p_days': [
              for (final day in days)
                {
                  'local_date': cycleDateKey(day.date),
                  'flow': day.flow.code,
                  'is_start': day.isStart,
                },
            ],
          },
        ),
      );
    } on PostgrestException catch (error) {
      logNonCritical(error, 'cycle import failed');
      rethrow;
    }
  }

  @override
  Future<CycleAnswer> deleteAll() => _answer('delete_my_cycle_data_v1');

  @override
  Future<bool> consentGranted() async {
    final rows = await _client
        .from('consent_records')
        .select('action')
        .eq('user_id', _userId)
        .eq('consent_type', CycleConsent.type)
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(1);
    return rows.isNotEmpty && rows.first['action'] == 'granted';
  }

  @override
  Future<void> grantConsent() async {
    await _client.from('consent_records').insert({
      'user_id': _userId,
      'consent_type': CycleConsent.type,
      'notice_version': CycleConsent.noticeVersion,
      'action': 'granted',
      'source': 'ios_app',
    });
  }
}

/// Builds without a backend: tracking is off and cannot be turned on.
class FixtureCycleRepository implements CycleRepository {
  const FixtureCycleRepository();

  @override
  Future<CycleAnswer> load() async => CycleAnswer.off;

  @override
  Future<CycleAnswer> saveSettings({
    required bool trackingEnabled,
    required CycleStatus? status,
    required int? typicalCycleDays,
    required bool appleHealthEnabled,
  }) => throw StateError('Configure Supabase.');

  @override
  Future<CycleAnswer> logDay({
    required DateTime date,
    required PeriodFlow? flow,
    CycleCramps? cramps,
    bool isStart = false,
  }) => throw StateError('Configure Supabase.');

  @override
  Future<CycleImport> importDays({
    required DateTime from,
    required DateTime to,
    required List<CycleHealthDay> days,
  }) => throw StateError('Configure Supabase.');

  @override
  Future<CycleAnswer> deleteAll() => throw StateError('Configure Supabase.');

  @override
  Future<bool> consentGranted() async => false;

  @override
  Future<void> grantConsent() => throw StateError('Configure Supabase.');
}
