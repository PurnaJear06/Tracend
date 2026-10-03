import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/train/muscle_groups.dart';
import 'package:tracend/features/train/train_view_models.dart';
import 'package:tracend/features/train/workout_repository.dart';

TrainingHubData _hub16() => TrainingHubData.fromHubJson(
  json.decode(
        File(
          'test/contract/fixtures/training_hub_v1_6.json',
        ).readAsStringSync(),
      )
      as Map<String, dynamic>,
);

/// 28 days ending 2026-10-02; [trained] maps a day offset from the end
/// (0 = today) to its strain, all athlete-rated unless listed in [defaults].
List<DailyLoadDay> _load(
  Map<int, double> trained, {
  Set<int> defaults = const {},
  DayLoadLevel level = DayLoadLevel.moderate,
}) {
  final today = DateTime(2026, 10, 2);
  return [
    for (var back = 27; back >= 0; back--)
      DailyLoadDay(
        date: today.subtract(Duration(days: back)),
        recorded: trained.containsKey(back),
        strain: trained[back] ?? 0,
        minutes: trained.containsKey(back) ? 45 : 0,
        sessions: trained.containsKey(back) ? 1 : 0,
        effortReported: trained.containsKey(back) && !defaults.contains(back),
        level: !trained.containsKey(back)
            ? DayLoadLevel.rest
            : defaults.contains(back)
            ? null
            : level,
      ),
  ];
}

final _sixDays = {0: 30.0, 2: 30.0, 5: 30.0, 9: 30.0, 12: 30.0, 16: 30.0};

PlannedExercise _exercise(
  String name,
  int sets,
  List<MuscleGroup> muscles, {
  bool linked = true,
}) => PlannedExercise(
  order: 1,
  name: name,
  setCount: sets,
  repMin: 8,
  repMax: 10,
  targetRpe: 8,
  exerciseSlug: linked ? name.toLowerCase().replaceAll(' ', '-') : null,
  primaryMuscles: muscles,
);

void main() {
  group('PlanWeek', () {
    test('counts weeks from the effective date: day 16 is week 3 of 6', () {
      final week = PlanWeek.from(
        effectiveDate: DateTime(2026, 9, 16),
        localToday: DateTime(2026, 10, 2),
        blockWeeks: 6,
      );
      expect(week!.label, 'Week 3 of 6');
    });

    test('the effective day is week 1 and day 7 starts week 2', () {
      final start = DateTime(2026, 9, 16);
      expect(
        PlanWeek.from(
          effectiveDate: start,
          localToday: start,
          blockWeeks: 6,
        )!.label,
        'Week 1 of 6',
      );
      expect(
        PlanWeek.from(
          effectiveDate: start,
          localToday: DateTime(2026, 9, 23),
          blockWeeks: 6,
        )!.label,
        'Week 2 of 6',
      );
    });

    test('after the block ends it reads "Week N" alone', () {
      final start = DateTime(2026, 8, 1);
      expect(
        PlanWeek.from(
          effectiveDate: start,
          localToday: DateTime(2026, 9, 11),
          blockWeeks: 6,
        )!.label,
        'Week 6 of 6',
      );
      expect(
        PlanWeek.from(
          effectiveDate: start,
          localToday: DateTime(2026, 10, 2),
          blockWeeks: 6,
        )!.label,
        'Week 9',
      );
    });

    test('a 1.5 hub without dates, or a plan not started, has no pill', () {
      expect(
        PlanWeek.from(
          effectiveDate: null,
          localToday: DateTime(2026, 10, 2),
          blockWeeks: 6,
        ),
        isNull,
      );
      expect(
        PlanWeek.from(
          effectiveDate: DateTime(2026, 10, 5),
          localToday: DateTime(2026, 10, 2),
          blockWeeks: 6,
        ),
        isNull,
      );
    });

    test('the fixture hub reads Week 3 of 6', () {
      final hub = _hub16();
      expect(
        PlanWeek.from(
          effectiveDate: hub.plan!.effectiveDate,
          localToday: hub.localToday,
          blockWeeks: hub.plan!.blockWeeks,
        )!.label,
        'Week 3 of 6',
      );
    });
  });

  group('ReadinessLine', () {
    String line(int? score) =>
        ReadinessLine.from(healthConnected: true, recoveryScore: score).text;

    test('maps the five ALGORITHMS bands at their cut-offs', () {
      expect(line(100), 'Recovery is excellent.');
      expect(line(80), 'Recovery is excellent.');
      expect(line(79), 'Recovered. Good to train.');
      expect(line(65), 'Recovered. Good to train.');
      expect(line(64), 'Recovery is moderate.');
      expect(line(50), 'Recovery is moderate.');
      expect(line(49), 'Recovery is low today.');
      expect(line(35), 'Recovery is low today.');
      expect(line(34), 'Recovery is poor today.');
      expect(line(0), 'Recovery is poor today.');
    });

    test('no score reads as a baseline in progress', () {
      final readiness = ReadinessLine.from(
        healthConnected: true,
        recoveryScore: null,
      );
      expect(readiness.text, 'Building your baseline.');
      expect(readiness.band, isNull);
      expect(readiness.needsHealth, isFalse);
    });

    test('without Apple Health it asks to connect, whatever the score', () {
      final readiness = ReadinessLine.from(
        healthConnected: false,
        recoveryScore: 90,
      );
      expect(readiness.text, 'Connect Apple Health to see recovery');
      expect(readiness.needsHealth, isTrue);
    });

    test('connection states map to connected or not', () {
      expect(
        ReadinessLine.isHealthConnected(HealthConnectionState.connected),
        isTrue,
      );
      expect(
        ReadinessLine.isHealthConnected(HealthConnectionState.stale),
        isTrue,
      );
      expect(
        ReadinessLine.isHealthConnected(HealthConnectionState.manualOnly),
        isFalse,
      );
      expect(
        ReadinessLine.isHealthConnected(HealthConnectionState.unavailable),
        isFalse,
      );
    });
  });

  group('TrainingLoadSheetModel', () {
    test('the fixture hub: about normal, calibrating, last 7 days', () {
      final hub = _hub16();
      final model = TrainingLoadSheetModel.from(
        dailyLoad: hub.dailyLoad,
        acwr: hub.load!.acwr,
        monotony: hub.load!.trainingMonotony,
        localToday: hub.localToday,
      );
      expect(model.hasReading, isTrue);
      expect(model.calibrating, isTrue);
      expect(model.verdict, 'About normal for you');
      expect(model.rowLabel, 'About normal, calibrating');
      expect(model.subtitle, 'Last 7 days compared with your usual 4 weeks');
      expect(model.zone, LoadZone.normal);
      expect(model.scalePosition, closeTo((1.07 - 0.5) / 1.3, 1e-9));
      expect(model.days.map((d) => d.kind), [
        LoadBarKind.rest,
        LoadBarKind.calibrating,
        LoadBarKind.calibrating,
        LoadBarKind.rest,
        LoadBarKind.hard,
        LoadBarKind.rest,
        LoadBarKind.moderate,
      ]);
      expect(model.days.last.isToday, isTrue);
      expect(model.days.last.shortLabel, 'Today');
      expect(model.days.first.shortLabel, 'S');
      expect(model.showCalibratingLegend, isTrue);
      expect(model.initialSelectedIndex, 6);
      expect(model.days[4].detail, 'Wednesday 30: 52 min, hard');
      expect(
        model.days[1].detail,
        'Sunday 27: 48 min, effort not reported, calibrating',
      );
      expect(model.days[3].detail, 'Tuesday 29: rest day');
      expect(model.days[4].heightFraction, closeTo(41.6 / 50, 1e-9));
      expect(model.days[0].heightFraction, 0);
      expect(model.advice, 'Your hard and easy days are well mixed.');
      expect(model.explanation.ratioText, contains('is 1.07'));
      expect(model.explanation.ratioText, contains('From 0.8 to 1.3'));
      expect(model.explanation.monotonyText, contains('well mixed'));
      expect(model.explanation.paragraphs, hasLength(4));
    });

    test('the scale zones sit at 0.8 and 1.3', () {
      expect(
        TrainingLoadSheetModel.normalStartFraction,
        closeTo(0.3 / 1.3, 1e-9),
      );
      expect(
        TrainingLoadSheetModel.normalEndFraction,
        closeTo(0.8 / 1.3, 1e-9),
      );
    });

    TrainingLoadSheetModel at(double acwr, {double? monotony}) =>
        TrainingLoadSheetModel.from(
          dailyLoad: _load(_sixDays),
          acwr: acwr,
          monotony: monotony,
        );

    test('the verdict follows the existing ACWR thresholds', () {
      expect(at(0.79).verdict, 'Lighter than normal for you');
      expect(at(0.79).zone, LoadZone.low);
      expect(at(0.8).verdict, 'About normal for you');
      expect(at(1.3).verdict, 'About normal for you');
      expect(at(1.31).verdict, 'Heavier than normal for you');
      expect(at(1.31).zone, LoadZone.high);
      expect(at(1.5).verdict, 'Heavier than normal for you');
      expect(at(1.51).verdict, 'Much heavier than normal for you');
      expect(at(1.51).zone, LoadZone.high);
      expect(at(3).scalePosition, 1);
      expect(at(0.2).scalePosition, 0);
    });

    test('one advice line, from the ACWR band and monotony only', () {
      expect(
        at(1.6, monotony: 1.2).advice,
        'Much heavier than your normal. Scale back to protect progress.',
      );
      expect(
        at(1.0, monotony: 2.1).advice,
        'Your days are too similar. Vary how hard they are.',
      );
      expect(
        at(1.4, monotony: 1.2).advice,
        'Heavier than your normal, still in a workable range.',
      );
      expect(
        at(1.0, monotony: 1.2).advice,
        'Your hard and easy days are well mixed.',
      );
      expect(at(1.0).advice, 'This matches your normal training.');
      expect(at(0.6).advice, 'Lighter than your normal training.');
      expect(
        at(1.0, monotony: 2.1).explanation.monotonyText,
        contains('alike'),
      );
      expect(at(1.0).explanation.monotonyText, isNull);
    });

    test('athlete-rated days only: no calibrating label or legend', () {
      final model = at(1.0);
      expect(model.calibrating, isFalse);
      expect(model.rowLabel, 'About normal for you');
      expect(model.showCalibratingLegend, isFalse);
    });

    test('a default-effort day in the window keeps calibrating on', () {
      final model = TrainingLoadSheetModel.from(
        dailyLoad: _load(_sixDays, defaults: {16}),
        acwr: 1.0,
        monotony: null,
      );
      expect(model.calibrating, isTrue);
      expect(model.rowLabel, 'About normal, calibrating');
      // Day 16 is outside the 7 days shown, so the legend stays quiet.
      expect(model.showCalibratingLegend, isFalse);
    });

    test('a new user without ACWR sees the reading build', () {
      final model = TrainingLoadSheetModel.from(
        dailyLoad: _load({0: 20, 2: 25}),
        acwr: null,
        monotony: 1.5,
      );
      expect(model.hasReading, isFalse);
      expect(model.verdict, 'Your load reading builds as you train');
      expect(model.rowLabel, 'Builds as you train');
      expect(model.scalePosition, isNull);
      expect(model.zone, isNull);
      expect(model.advice, 'Follow the plan as written.');
      expect(model.explanation.ratioText, contains('about two weeks'));
      expect(model.explanation.monotonyText, isNull);
      expect(model.days, hasLength(7));
    });

    test('fewer than four sessions never shows a ratio verdict', () {
      final model = TrainingLoadSheetModel.from(
        dailyLoad: _load({0: 20, 2: 25, 4: 30}),
        acwr: 1.1,
        monotony: null,
      );
      expect(model.hasReading, isFalse);
    });

    test('personal reference changes the day explanation', () {
      final fixed = at(1.0).explanation.dayText;
      expect(fixed, contains('under 20 is easy'));
      final personal = TrainingLoadSheetModel.from(
        dailyLoad: [
          for (final day in _load(_sixDays))
            DailyLoadDay(
              date: day.date,
              recorded: day.recorded,
              strain: day.strain,
              minutes: day.minutes,
              sessions: day.sessions,
              effortReported: day.effortReported,
              level: day.level,
              personalReference: day.recorded,
            ),
        ],
        acwr: 1.0,
        monotony: null,
      ).explanation.dayText;
      expect(personal, contains('your own last 4 weeks'));
    });

    test('today without a session reads "not trained yet"', () {
      final model = TrainingLoadSheetModel.from(
        dailyLoad: _load({2: 30}),
        acwr: null,
        monotony: null,
      );
      expect(model.days.last.detail, 'Today: not trained yet');
      expect(model.days.last.semanticsLabel, 'Today: not trained yet');
      expect(model.initialSelectedIndex, 4);
    });

    test('an empty window has no bars', () {
      final model = TrainingLoadSheetModel.from(
        dailyLoad: const [],
        acwr: null,
        monotony: null,
      );
      expect(model.days, isEmpty);
      expect(model.calibrating, isFalse);
    });
  });

  group('muscleSetsFor', () {
    test('sums each exercise’s sets into every primary muscle', () {
      final sets = muscleSetsFor(_hub16().workouts.single.exercises);
      expect(sets, const [
        MuscleSets(group: MuscleGroup.chest, sets: 3, tone: MuscleTone.main),
        MuscleSets(group: MuscleGroup.back, sets: 3, tone: MuscleTone.main),
        MuscleSets(group: MuscleGroup.biceps, sets: 3, tone: MuscleTone.main),
        MuscleSets(group: MuscleGroup.triceps, sets: 3, tone: MuscleTone.main),
      ]);
    });

    test('main is at least 60% of the top group, else also', () {
      final sets = muscleSetsFor([
        _exercise('Bench press', 4, [MuscleGroup.chest, MuscleGroup.triceps]),
        _exercise('Incline press', 6, [MuscleGroup.chest]),
        _exercise('Pressdown', 2, [MuscleGroup.triceps]),
        _exercise('Lateral raise', 5, [MuscleGroup.shoulders]),
      ]);
      expect(sets, const [
        MuscleSets(group: MuscleGroup.chest, sets: 10, tone: MuscleTone.main),
        MuscleSets(group: MuscleGroup.triceps, sets: 6, tone: MuscleTone.main),
        MuscleSets(
          group: MuscleGroup.shoulders,
          sets: 5,
          tone: MuscleTone.also,
        ),
      ]);
      expect(muscleTones(sets), {
        MuscleGroup.chest: MuscleTone.main,
        MuscleGroup.triceps: MuscleTone.main,
        MuscleGroup.shoulders: MuscleTone.also,
      });
    });

    test('unlinked exercises add nothing and nothing is guessed', () {
      expect(
        muscleSetsFor([
          _exercise('Cable fly', 3, const []),
          _exercise('Squat', 4, [MuscleGroup.quads], linked: false),
        ]),
        isEmpty,
      );
    });
  });
}
