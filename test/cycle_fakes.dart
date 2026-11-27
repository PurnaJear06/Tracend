import 'dart:convert';
import 'dart:io';

import 'package:tracend/features/cycle/cycle_health.dart';
import 'package:tracend/features/cycle/cycle_repository.dart';

/// A cycle repository that keeps its answer in memory and records what the
/// app sent it.
class FakeCycle implements CycleRepository {
  FakeCycle({this.answer = CycleAnswer.off, this.consent = false});

  CycleAnswer answer;
  bool consent;
  bool failLoads = false;
  bool failWrites = false;
  Object? writeError;

  /// Saving the settings fails once this many have been saved.
  int? failSettingsFrom;

  int loads = 0;
  int consentGrants = 0;
  final settings =
      <({bool tracking, CycleStatus? status, int? typical, bool apple})>[];
  final days =
      <
        ({DateTime date, PeriodFlow? flow, CycleCramps? cramps, bool isStart})
      >[];
  final imports = <({DateTime from, DateTime to, List<CycleHealthDay> days})>[];
  int deletions = 0;

  void _maybeFail() {
    if (failWrites) throw writeError ?? Exception('offline');
  }

  @override
  Future<CycleAnswer> load() async {
    loads++;
    if (failLoads) throw Exception('offline');
    return answer;
  }

  @override
  Future<CycleAnswer> saveSettings({
    required bool trackingEnabled,
    required CycleStatus? status,
    required int? typicalCycleDays,
    required bool appleHealthEnabled,
  }) async {
    _maybeFail();
    if (failSettingsFrom != null && settings.length >= failSettingsFrom!) {
      throw Exception('offline');
    }
    settings.add((
      tracking: trackingEnabled,
      status: status,
      typical: typicalCycleDays,
      apple: appleHealthEnabled,
    ));
    return answer = CycleAnswer(
      trackingEnabled: trackingEnabled,
      status: status,
      typicalCycleDays: typicalCycleDays,
      appleHealthEnabled: appleHealthEnabled,
      state: answer.state,
      recentDays: answer.recentDays,
      cycles: answer.cycles,
    );
  }

  @override
  Future<CycleAnswer> logDay({
    required DateTime date,
    required PeriodFlow? flow,
    CycleCramps? cramps,
    bool isStart = false,
  }) async {
    _maybeFail();
    days.add((date: date, flow: flow, cramps: cramps, isStart: isStart));
    return answer = CycleAnswer(
      trackingEnabled: answer.trackingEnabled,
      status: answer.status,
      typicalCycleDays: answer.typicalCycleDays,
      appleHealthEnabled: answer.appleHealthEnabled,
      state: answer.state,
      recentDays: [
        for (final day in answer.recentDays)
          if (day.date != date) day,
        CycleDay(
          date: date,
          flow: flow,
          cramps: cramps,
          isStart: isStart,
          source: CycleSource.manual,
        ),
      ],
      cycles: answer.cycles,
    );
  }

  @override
  Future<CycleImport> importDays({
    required DateTime from,
    required DateTime to,
    required List<CycleHealthDay> days,
  }) async {
    _maybeFail();
    imports.add((from: from, to: to, days: days));
    return CycleImport(imported: days.length, removed: 0);
  }

  @override
  Future<CycleAnswer> deleteAll() async {
    _maybeFail();
    deletions++;
    consent = false;
    return answer = CycleAnswer.off;
  }

  @override
  Future<bool> consentGranted() async => consent;

  @override
  Future<void> grantConsent() async {
    _maybeFail();
    consentGrants++;
    consent = true;
  }
}

/// An Apple Health reader with days of its own.
class FakeCycleHealthReader implements CycleHealthReader {
  FakeCycleHealthReader({this.days = const [], this.canAsk = true});

  List<CycleHealthDay> days;
  bool canAsk;
  bool failReads = false;
  int requests = 0;
  final reads = <({DateTime from, DateTime to})>[];

  @override
  Future<bool> requestAccess() async {
    requests++;
    return canAsk;
  }

  @override
  Future<List<CycleHealthDay>> readDays(DateTime from, DateTime to) async {
    reads.add((from: from, to: to));
    if (failReads) throw Exception('unavailable');
    return days;
  }
}

/// A tracking answer with the fields a test cares about.
CycleAnswer trackingAnswer({
  CycleStatus status = CycleStatus.regular,
  int? typical = 28,
  bool apple = false,
  CycleState state = const CycleState(),
  List<CycleDay> recentDays = const [],
  List<CycleRecord> cycles = const [],
}) => CycleAnswer(
  trackingEnabled: true,
  status: status,
  typicalCycleDays: typical,
  appleHealthEnabled: apple,
  state: state,
  recentDays: recentDays,
  cycles: cycles,
);

/// A contract fixture of PR 1 read as the app reads the database's answer.
CycleAnswer fixtureAnswer(String name) => parseCycleAnswer(
  json.decode(File('test/contract/fixtures/$name').readAsStringSync()),
);
