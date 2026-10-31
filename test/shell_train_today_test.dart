import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/shell/app_shell.dart';
import 'package:tracend/features/train/widgets/week_rail_card.dart';
import 'package:tracend/features/train/workout_repository.dart';

const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

void main() {
  testWidgets('Today\'s session card opens Train on today, not on the day '
      'last viewed', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: AppShell(
          environment: _environment,
          repositories: AppShellRepositories(
            workouts: FixtureWorkoutRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('tab-train')));
    await tester.pumpAndSettle();
    DayBoxesStrip strip() =>
        tester.widget<DayBoxesStrip>(find.byType(DayBoxesStrip));
    final today = strip().today;
    final pick = [
      for (var i = 0; i < 7; i++) strip().weekStart.add(Duration(days: i)),
    ].firstWhere((day) => day != today);
    await tester.tap(
      find.byKey(ValueKey('day-box-${DayBoxesStrip.iso(pick)}')),
    );
    await tester.pumpAndSettle();
    expect(strip().selectedDate, pick);

    await tester.tap(find.byKey(const ValueKey('tab-today')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open in Train'));
    await tester.pumpAndSettle();

    expect(strip().selectedDate, today);
  });
}
