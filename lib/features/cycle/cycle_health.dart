import 'dart:io';

import 'package:health/health.dart';
import 'package:tracend/features/cycle/cycle_repository.dart';
import 'package:tracend/shared/diagnostics.dart';

/// One menstrual flow sample as Apple Health holds it, before it becomes days.
class MenstrualFlowSample {
  const MenstrualFlowSample({
    required this.from,
    required this.to,
    required this.flow,
    required this.isStartOfCycle,
  });

  final DateTime from;
  final DateTime to;

  /// Null when Apple Health records no bleeding ("none") or a value this
  /// build does not know.
  final PeriodFlow? flow;
  final bool isStartOfCycle;
}

/// The key Apple Health stores the start of a cycle under
/// (`HKMetadataKeyMenstrualCycleStart`).
const _cycleStartKey = 'HKMenstrualCycleStart';

/// Whether a sample's metadata says it began a cycle. Apple Health keeps the
/// flag as a boolean, which arrives here as `true`; the health plugin's own
/// `isStartOfCycle` compares it with `1.0`, which a `true` never equals, so
/// the raw value is read as well (a number 1 counts too).
bool isCycleStartMetadata(Map<String, dynamic>? metadata) {
  final raw = metadata?[_cycleStartKey];
  return raw == true || raw == 1 || raw == 1.0;
}

/// The longest run of days one sample may cover. Apple Health writes one
/// sample a day; a longer one is not read as a period.
const _maxSampleDays = 10;

/// The period days in [samples], one per local day, inside [from] to [to].
///
/// A "none" sample is dropped, so a day Apple Health says had no bleeding is
/// absent rather than a bleed. Spotting is never read from Apple Health: it
/// is logged by hand only. Where a day has several samples the heaviest flow
/// wins and the day is a start if any of them is.
List<CycleHealthDay> cycleHealthDays(
  List<MenstrualFlowSample> samples, {
  required DateTime from,
  required DateTime to,
}) {
  final first = DateTime(from.year, from.month, from.day);
  final last = DateTime(to.year, to.month, to.day);
  final byDay = <DateTime, CycleHealthDay>{};
  for (final sample in samples) {
    final flow = sample.flow;
    if (flow == null) continue;
    final startDay = DateTime(
      sample.from.year,
      sample.from.month,
      sample.from.day,
    );
    // A sample ending at midnight does not include the day it ends on.
    final end = sample.to.isAfter(sample.from)
        ? sample.to.subtract(const Duration(microseconds: 1))
        : sample.from;
    final endDay = DateTime(end.year, end.month, end.day);
    final span = endDay.difference(startDay).inDays + 1;
    if (span > _maxSampleDays) continue;
    for (var offset = 0; offset < span; offset++) {
      final day = DateTime(
        startDay.year,
        startDay.month,
        startDay.day + offset,
      );
      if (day.isBefore(first) || day.isAfter(last)) continue;
      final isStart = sample.isStartOfCycle && offset == 0;
      final earlier = byDay[day];
      byDay[day] = earlier == null
          ? CycleHealthDay(date: day, flow: flow, isStart: isStart)
          : CycleHealthDay(
              date: day,
              flow: _heavier(earlier.flow, flow),
              isStart: earlier.isStart || isStart,
            );
    }
  }
  return [for (final key in byDay.keys.toList()..sort()) byDay[key]!];
}

PeriodFlow _heavier(PeriodFlow a, PeriodFlow b) {
  int weight(PeriodFlow flow) => switch (flow) {
    PeriodFlow.heavy => 3,
    PeriodFlow.medium => 2,
    PeriodFlow.light => 1,
    PeriodFlow.spotting || PeriodFlow.unspecified => 0,
  };
  return weight(b) > weight(a) ? b : a;
}

/// Period days from Apple Health. It is separate from the main health sync:
/// menstrual flow is asked for only when she turns "Read periods from Apple
/// Health" on, never with the other types.
abstract interface class CycleHealthReader {
  /// Shows Apple's sheet for menstrual flow (only while the choice is still
  /// undecided; Apple never says whether read access was given). False when
  /// Apple Health cannot be asked at all. Never throws.
  Future<bool> requestAccess();

  /// The period days from [from] to [to], oldest first. Throws when Apple
  /// Health cannot be read, so that "no periods" and "could not read" stay
  /// different.
  Future<List<CycleHealthDay>> readDays(DateTime from, DateTime to);
}

class HealthKitCycleReader implements CycleHealthReader {
  HealthKitCycleReader({Health? health}) : _health = health ?? Health();

  final Health _health;
  bool _configured = false;

  static const _types = [HealthDataType.MENSTRUATION_FLOW];

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<bool> requestAccess() async {
    if (!Platform.isIOS) return false;
    try {
      await _configure();
      await _health.requestAuthorization(
        _types,
        permissions: const [HealthDataAccess.READ],
      );
      return true;
    } catch (error) {
      logNonCritical(error, 'menstrual flow access not requested');
      return false;
    }
  }

  @override
  Future<List<CycleHealthDay>> readDays(DateTime from, DateTime to) async {
    if (!Platform.isIOS) {
      throw UnsupportedError('Apple Health is not on this platform.');
    }
    await _configure();
    final points = await _health.getHealthDataFromTypes(
      types: _types,
      // Whole days: the first day's sample starts at its midnight.
      startTime: DateTime(from.year, from.month, from.day),
      endTime: DateTime(to.year, to.month, to.day + 1),
    );
    return cycleHealthDays(
      [
        for (final point in points)
          if (point.value case final MenstruationFlowHealthValue value)
            MenstrualFlowSample(
              from: point.dateFrom,
              to: point.dateTo,
              flow: switch (value.flow) {
                MenstrualFlow.unspecified => PeriodFlow.unspecified,
                MenstrualFlow.light => PeriodFlow.light,
                MenstrualFlow.medium => PeriodFlow.medium,
                MenstrualFlow.heavy => PeriodFlow.heavy,
                _ => null,
              },
              isStartOfCycle:
                  (value.isStartOfCycle ?? false) ||
                  isCycleStartMetadata(point.metadata),
            ),
      ],
      from: from,
      to: to,
    );
  }
}

/// Apple Health cannot be read now: the agreements are unknown or outdated.
class CycleHealthGateClosed implements Exception {
  const CycleHealthGateClosed();
}

/// Reads Apple Health's period days into the database. 180 days when she turns
/// the switch on, 30 days on each sync after. Every window replaces what Apple
/// Health gave before inside it and never touches a day she logged by hand.
class CycleHealthSync {
  CycleHealthSync({
    required this.repository,
    required this.reader,
    bool Function()? allowed,
    DateTime Function()? now,
  }) : _allowed = allowed ?? (() => true),
       _now = now ?? DateTime.now;

  final CycleRepository repository;
  final CycleHealthReader reader;

  /// Whether Apple Health may be read and sent now: the same gate as the main
  /// health sync, closed while the agreements are unknown or outdated.
  final bool Function() _allowed;
  final DateTime Function() _now;

  static const enableWindowDays = 180;
  static const syncWindowDays = 30;

  /// Shows Apple's sheet for menstrual flow; false when Apple Health cannot be
  /// asked, and then nothing is turned on.
  Future<bool> requestAccess() => reader.requestAccess();

  /// The first 180 days, read after the switch is on at the database (which
  /// refuses an import before).
  ///
  /// Throws [CycleHealthGateClosed] without reading while the agreements gate
  /// is closed, like [sync].
  Future<CycleImport> backfill() async {
    if (!_allowed()) throw const CycleHealthGateClosed();
    return _import(enableWindowDays);
  }

  /// Whether Apple Health may be read and sent now (the agreements gate).
  bool get allowed => _allowed();

  /// The 30-day refresh. Does nothing, and returns null, unless the agreements
  /// gate is open and tracking and "Read periods from Apple Health" are both
  /// on. [answer] is the cycle answer the caller just read; without it the
  /// answer is read first.
  Future<CycleImport?> sync({CycleAnswer? answer}) async {
    if (!_allowed()) return null;
    final current = answer ?? await repository.load();
    if (!current.trackingEnabled || !current.appleHealthEnabled) return null;
    // The agreements may have changed while the answer was read.
    if (!_allowed()) return null;
    return _import(syncWindowDays);
  }

  Future<CycleImport> _import(int days) async {
    final today = _now();
    final to = DateTime(today.year, today.month, today.day);
    final from = DateTime(to.year, to.month, to.day - days);
    return repository.importDays(
      from: from,
      to: to,
      days: await reader.readDays(from, to),
    );
  }
}
