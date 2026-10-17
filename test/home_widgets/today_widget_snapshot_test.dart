import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/shared/home_widgets/today_widget_snapshot.dart';

final _now = DateTime.utc(2026, 10, 18, 7, 30);

const _targets = NutritionTargets(
  calories: 2400,
  protein: 160,
  carbohydrate: 280,
  fat: 70,
);

Map<String, dynamic> _exercise(
  int order,
  String name, {
  int sets = 3,
  int repMin = 8,
  int repMax = 10,
  num? load,
}) => {
  'order': order,
  'name': name,
  'set_count': sets,
  'rep_min': repMin,
  'rep_max': repMax,
  'target_load_kg': load,
};

DailyBrief _brief({
  Map<String, dynamic>? workout,
  TodaySession? session,
  int? recovery = 72,
  Map<String, dynamic>? nutrition,
}) => DailyBrief(
  localDate: '2026-10-18',
  workout: workout,
  todaySession: session,
  nutrition: nutrition ?? const {'calories': 1240.4, 'protein_g': 79.6},
  computed: ComputedMetrics.fromJson({
    'scores': {'recovery': ?recovery},
  }),
);

Map<String, dynamic> _push() => {
  'name': 'Push day',
  'exercises': [
    _exercise(1, 'Bench press', sets: 4, repMin: 6, repMax: 8, load: 82.5),
    _exercise(2, 'Overhead press', load: 45),
    _exercise(3, 'Incline dumbbell press', repMin: 10, repMax: 12, load: 24),
    _exercise(4, 'Lateral raise', sets: 2, repMin: 15, repMax: 15),
  ],
};

TodayWidgetSnapshot _build(
  DailyBrief brief, {
  NutritionTargets? targets = _targets,
  bool checkedIn = true,
  bool lockScreenNumbers = false,
}) => TodayWidgetSnapshot.build(
  brief: brief,
  targets: targets,
  checkedIn: checkedIn,
  lockScreenNumbers: lockScreenNumbers,
  now: _now,
);

Map<String, dynamic> _json(TodayWidgetSnapshot snapshot) =>
    jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>;

void main() {
  group('Today session', () {
    test('a planned workout lists its first three exercises with targets', () {
      final json = _json(_build(_brief(workout: _push())));
      final session = json['session'] as Map<String, dynamic>;

      expect(session['state'], 'planned');
      expect(session['name'], 'Push day');
      expect(session['sets_logged'], 0);
      expect(session['sets_total'], 12);
      expect(session['exercises'], [
        {'name': 'Bench press', 'target': '4 × 6–8 · 82.5 kg'},
        {'name': 'Overhead press', 'target': '3 × 8–10 · 45 kg'},
        {'name': 'Incline dumbbell press', 'target': '3 × 10–12 · 24 kg'},
      ]);
    });

    test('totals count every exercise, not only the three shown', () {
      final json = _json(_build(_brief(workout: _push())));
      expect((json['session'] as Map)['sets_total'], 4 + 3 + 3 + 2);
    });

    test('an exercise with equal reps and no load reads plainly', () {
      final json = _json(
        _build(
          _brief(
            workout: {
              'name': 'Arms',
              'exercises': [
                _exercise(1, 'Lateral raise', sets: 2, repMin: 15, repMax: 15),
              ],
            },
          ),
        ),
      );
      expect(((json['session'] as Map)['exercises'] as List).single, {
        'name': 'Lateral raise',
        'target': '2 × 15',
      });
    });

    test('a session under way counts logged sets, capped at the plan', () {
      final json = _json(
        _build(
          _brief(
            workout: _push(),
            session: const TodaySession(
              state: 'in_progress',
              completedSets: {1: 4, 2: 9, 9: 3},
            ),
          ),
        ),
      );
      final session = json['session'] as Map<String, dynamic>;
      expect(session['state'], 'in_progress');
      expect(session['sets_logged'], 4 + 3);
    });

    test('a finished session says completed', () {
      final json = _json(
        _build(
          _brief(
            workout: _push(),
            session: const TodaySession(
              state: 'completed',
              completedSets: {1: 4, 2: 3, 3: 3, 4: 2},
            ),
          ),
        ),
      );
      final session = json['session'] as Map<String, dynamic>;
      expect(session['state'], 'completed');
      expect(session['sets_logged'], 12);
    });

    test('no workout is a rest day with no name', () {
      final json = _json(_build(_brief()));
      expect(json['session'], {
        'state': 'rest',
        'name': null,
        'sets_logged': 0,
        'sets_total': 0,
        'exercises': <Object>[],
      });
    });

    test('plan names are trimmed and a long one is shortened', () {
      final json = _json(
        _build(
          _brief(
            workout: {
              'name': '  ${'A' * 60}  ',
              'exercises': [_exercise(1, '   ')],
            },
          ),
        ),
      );
      final session = json['session'] as Map<String, dynamic>;
      expect((session['name'] as String).length, 40);
      expect((session['name'] as String).endsWith('…'), isTrue);
      expect(
        ((session['exercises'] as List).single as Map)['name'],
        'Exercise',
      );
    });
  });

  group('Recovery, fuel and check-in', () {
    test('carries the brief numbers and the plan targets', () {
      final json = _json(_build(_brief(workout: _push())));

      expect(json['recovery'], 72);
      expect(json['nutrition'], {
        'calories': 1240,
        'calories_target': 2400,
        'protein_g': 80,
        'protein_target_g': 160,
      });
      expect(json['check_in_done'], isTrue);
    });

    test('an unscored day has no recovery number', () {
      expect(_json(_build(_brief(recovery: null)))['recovery'], isNull);
    });

    test('targets that did not load leave only what was eaten', () {
      final json = _json(_build(_brief(), targets: null, checkedIn: false));
      expect(json['nutrition'], {
        'calories': 1240,
        'calories_target': null,
        'protein_g': 80,
        'protein_target_g': null,
      });
      expect(json['check_in_done'], isFalse);
    });

    test('nothing eaten yet reads zero, not missing', () {
      final json = _json(_build(_brief(nutrition: const {})));
      expect((json['nutrition'] as Map)['calories'], 0);
      expect((json['nutrition'] as Map)['protein_g'], 0);
    });
  });

  group('Lock Screen privacy', () {
    test('numbers are left out unless the athlete chose them', () {
      final snapshot = _build(_brief(workout: _push()));
      expect(_json(snapshot)['lock'], isNull);
    });

    test('a chosen Lock Screen carries only the three readings', () {
      final json = _json(
        _build(_brief(workout: _push()), lockScreenNumbers: true),
      );
      expect(json['lock'], {
        'session': 'Push day',
        'session_state': 'planned',
        'recovery': 72,
        'protein_g': 80,
        'protein_target_g': 160,
      });
    });

    test('a rest day reads "Rest day" on the Lock Screen', () {
      final json = _json(_build(_brief(), lockScreenNumbers: true));
      expect((json['lock'] as Map)['session'], 'Rest day');
      expect((json['lock'] as Map)['session_state'], 'rest');
    });

    test('the choice changes the content key, so it is written again', () {
      final hidden = _build(_brief(workout: _push()));
      final shown = _build(_brief(workout: _push()), lockScreenNumbers: true);
      expect(hidden.contentKey, isNot(shown.contentKey));
    });
  });

  group('Staleness', () {
    test('the snapshot carries its time and its stale limit', () {
      final json = _json(_build(_brief()));
      expect(json['generated_at_millis'], _now.millisecondsSinceEpoch);
      expect(json['stale_after_seconds'], 12 * 60 * 60);
      expect(TodayWidgetSnapshot.staleAfter, const Duration(hours: 12));
    });

    test('the content key ignores the time, so an unchanged day matches', () {
      final first = _build(_brief(workout: _push()));
      final later = TodayWidgetSnapshot.build(
        brief: _brief(workout: _push()),
        targets: _targets,
        checkedIn: true,
        lockScreenNumbers: false,
        now: _now.add(const Duration(hours: 3)),
      );
      expect(later.contentKey, first.contentKey);
      expect(
        _json(later)['generated_at_millis'],
        isNot(_json(first)['generated_at_millis']),
      );
    });

    test('a changed number changes the content key', () {
      final before = _build(_brief(workout: _push()));
      final after = _build(
        _brief(
          workout: _push(),
          nutrition: const {'calories': 1500, 'protein_g': 95},
        ),
      );
      expect(after.contentKey, isNot(before.contentKey));
    });
  });

  test('no free text travels: only plan names, counts and scores', () {
    final text = jsonEncode(
      _build(
        DailyBrief(
          localDate: '2026-10-18',
          workout: _push(),
          checkIn: const {'notes': 'my knee hurts, private note'},
          nextMeal: const {'name': 'Grilled chicken bowl'},
          decision: const {'final_decision': 'Take it easy today.'},
          nutrition: const {'calories': 1000, 'protein_g': 50},
        ),
        lockScreenNumbers: true,
      ).toJson(),
    );
    expect(text, isNot(contains('knee')));
    expect(text, isNot(contains('chicken')));
    expect(text, isNot(contains('easy')));
  });
}
