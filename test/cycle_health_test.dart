import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/cycle/cycle_health.dart';
import 'package:tracend/features/cycle/cycle_repository.dart';

import 'cycle_fakes.dart';

MenstrualFlowSample _sample(
  DateTime from, {
  PeriodFlow? flow = PeriodFlow.light,
  bool start = false,
  DateTime? to,
}) => MenstrualFlowSample(
  from: from,
  to: to ?? from.add(const Duration(hours: 1)),
  flow: flow,
  isStartOfCycle: start,
);

void main() {
  final from = DateTime(2026, 11, 1);
  final to = DateTime(2026, 11, 30);

  group('cycleHealthDays', () {
    test('one day per local day, oldest first, with the start flag', () {
      final days = cycleHealthDays(
        [
          _sample(DateTime(2026, 11, 11, 8), flow: PeriodFlow.medium),
          _sample(DateTime(2026, 11, 10, 8), start: true),
        ],
        from: from,
        to: to,
      );
      expect(days.map((d) => d.date), [
        DateTime(2026, 11, 10),
        DateTime(2026, 11, 11),
      ]);
      expect(days.first.isStart, isTrue);
      expect(days.first.flow, PeriodFlow.light);
      expect(days.last.flow, PeriodFlow.medium);
      expect(days.last.isStart, isFalse);
    });

    test('a "none" sample is dropped, so the day is not a bleed', () {
      expect(
        cycleHealthDays(
          [_sample(DateTime(2026, 11, 10, 8), flow: null)],
          from: from,
          to: to,
        ),
        isEmpty,
      );
    });

    test('the heaviest flow of a day wins and any start counts', () {
      final days = cycleHealthDays(
        [
          _sample(DateTime(2026, 11, 10, 8), flow: PeriodFlow.light),
          _sample(
            DateTime(2026, 11, 10, 20),
            flow: PeriodFlow.heavy,
            start: true,
          ),
          _sample(DateTime(2026, 11, 10, 22), flow: PeriodFlow.unspecified),
        ],
        from: from,
        to: to,
      );
      expect(days, hasLength(1));
      expect(days.single.flow, PeriodFlow.heavy);
      expect(days.single.isStart, isTrue);
    });

    test('days outside the window are left out', () {
      final days = cycleHealthDays(
        [
          _sample(DateTime(2026, 10, 31, 8)),
          _sample(DateTime(2026, 11, 1, 8)),
          _sample(DateTime(2026, 11, 30, 8)),
          _sample(DateTime(2026, 12, 1, 8)),
        ],
        from: from,
        to: to,
      );
      expect(days.map((d) => d.date), [
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 30),
      ]);
    });

    test('a sample over several days is one day each, a start only first', () {
      final days = cycleHealthDays(
        [
          _sample(
            DateTime(2026, 11, 10),
            to: DateTime(2026, 11, 13),
            start: true,
          ),
        ],
        from: from,
        to: to,
      );
      expect(days.map((d) => d.date.day), [10, 11, 12]);
      expect(days.map((d) => d.isStart), [true, false, false]);
    });

    test('a sample longer than ten days is not read as a period', () {
      expect(
        cycleHealthDays(
          [_sample(DateTime(2026, 11, 1), to: DateTime(2026, 11, 20))],
          from: from,
          to: to,
        ),
        isEmpty,
      );
    });

    test('spotting is never produced from Apple Health', () {
      final days = cycleHealthDays(
        [
          for (final flow in [
            PeriodFlow.unspecified,
            PeriodFlow.light,
            PeriodFlow.medium,
            PeriodFlow.heavy,
          ])
            _sample(DateTime(2026, 11, 3 + flow.index, 8), flow: flow),
        ],
        from: from,
        to: to,
      );
      expect(days.map((d) => d.flow), isNot(contains(PeriodFlow.spotting)));
    });
  });

  group('CycleHealthSync', () {
    final now = DateTime(2026, 11, 27, 9);

    test('backfill reads 180 days and replaces that window', () async {
      final repository = FakeCycle();
      final reader = FakeCycleHealthReader(
        days: [
          CycleHealthDay(
            date: DateTime(2026, 11, 10),
            flow: PeriodFlow.light,
            isStart: true,
          ),
        ],
      );
      final sync = CycleHealthSync(
        repository: repository,
        reader: reader,
        now: () => now,
      );
      expect(await sync.requestAccess(), isTrue);
      final result = await sync.backfill();
      expect(result.imported, 1);
      expect(reader.reads.single.to, DateTime(2026, 11, 27));
      expect(reader.reads.single.from, DateTime(2026, 11, 27 - 180));
      expect(repository.imports.single.days, hasLength(1));
    });

    test('a refused permission request means it cannot be turned on', () async {
      final sync = CycleHealthSync(
        repository: FakeCycle(),
        reader: FakeCycleHealthReader(canAsk: false),
      );
      expect(await sync.requestAccess(), isFalse);
    });

    test('sync reads 30 days, only when both switches are on', () async {
      final reader = FakeCycleHealthReader();
      final off = FakeCycle(answer: trackingAnswer());
      expect(
        await CycleHealthSync(
          repository: off,
          reader: reader,
          now: () => now,
        ).sync(),
        isNull,
      );
      expect(
        await CycleHealthSync(
          repository: FakeCycle(),
          reader: reader,
          now: () => now,
        ).sync(),
        isNull,
      );
      expect(reader.reads, isEmpty);

      final on = FakeCycle(answer: trackingAnswer(apple: true));
      final result = await CycleHealthSync(
        repository: on,
        reader: reader,
        now: () => now,
      ).sync();
      expect(result, isNotNull);
      expect(reader.reads.single.from, DateTime(2026, 11, 27 - 30));
      expect(on.imports, hasLength(1));
    });

    test('an Apple Health that cannot be read imports nothing', () async {
      final reader = FakeCycleHealthReader()..failReads = true;
      final repository = FakeCycle(answer: trackingAnswer(apple: true));
      await expectLater(
        CycleHealthSync(repository: repository, reader: reader).sync(),
        throwsException,
      );
      expect(repository.imports, isEmpty);
    });
  });
}
