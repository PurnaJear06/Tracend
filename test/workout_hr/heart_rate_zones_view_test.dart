import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/workout_hr/heart_rate_profile.dart';
import 'package:tracend/features/workout_hr/heart_rate_zones_view.dart';

HeartRateProfile _case(String name) {
  final cases =
      jsonDecode(
            File(
              'supabase/functions/_shared/training/heart_rate/profile_cases.json',
            ).readAsStringSync(),
          )
          as List;
  final found =
      cases.firstWhere((item) => (item as Map)['name'] == name) as Map;
  return buildHeartRateProfile(HeartRateInputs.tryParse(found['inputs'])!);
}

Future<void> _show(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: TracendTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: KeyedSubtree(key: UniqueKey(), child: child),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows the five zones with resting and the estimated maximum', (
    tester,
  ) async {
    await _show(
      tester,
      HeartRateZonesBody(
        profile: _case('formula from age with resting and zones'),
      ),
    );
    expect(find.text('Heart-rate zones'), findsOneWidget);
    expect(
      find.text('Resting 59 bpm · Max 183 bpm, estimated from your age'),
      findsOneWidget,
    );
    expect(find.text('Z1'), findsOneWidget);
    expect(find.text('121-132 bpm'), findsOneWidget);
    expect(find.text('Maximum'), findsOneWidget);
    expect(find.text('171-183 bpm'), findsOneWidget);
    expect(
      find.text('Recovery after sets: not enough tracked sets yet.'),
      findsOneWidget,
    );
    expect(
      find.text('For information only. Heart rate never changes your loads.'),
      findsOneWidget,
    );
  });

  testWidgets('an observed maximum and a recovery trend are named', (
    tester,
  ) async {
    await _show(
      tester,
      HeartRateZonesBody(
        profile: _case('a trusted higher peak replaces the formula'),
      ),
    );
    expect(
      find.text('Resting 59 bpm · Max 190 bpm, from your workouts'),
      findsOneWidget,
    );
    await _show(tester, HeartRateZonesBody(profile: _case('recovery slower')));
    expect(
      find.text(
        'Recovery after sets: heart rate falls 18 bpm in the first minute, '
        'slower (-7 bpm against the 4 weeks before).',
      ),
      findsOneWidget,
    );
  });

  testWidgets('missing data reads as missing, with no zones', (tester) async {
    await _show(
      tester,
      HeartRateZonesBody(
        profile: _case('fewer than three resting days leaves zones missing'),
      ),
    );
    expect(find.text('Z1'), findsNothing);
    expect(
      find.text(
        'Zones need a resting heart rate. Apple Health has fewer than 3 recent days of it.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Resting heart rate not found yet · Max 183 bpm, estimated from your age',
      ),
      findsOneWidget,
    );
    await _show(
      tester,
      HeartRateZonesBody(
        profile: _case('no birth year and no peaks leaves the maximum missing'),
      ),
    );
    expect(find.textContaining('Max unknown'), findsOneWidget);
    expect(find.textContaining('Add your birth year'), findsOneWidget);
  });

  testWidgets(
    'the loader fills the view, and a failure or no profile hides it',
    (tester) async {
      final profile = _case('formula from age with resting and zones');
      await _show(tester, HeartRateZonesView(load: () async => profile));
      await tester.pumpAndSettle();
      expect(find.text('Heart-rate zones'), findsOneWidget);
      await _show(
        tester,
        HeartRateZonesView(load: () async => throw StateError('offline')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Heart-rate zones'), findsNothing);
      await _show(tester, HeartRateZonesView(load: () async => null));
      await tester.pumpAndSettle();
      expect(find.text('Heart-rate zones'), findsNothing);
    },
  );
}
