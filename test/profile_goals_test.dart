import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/widgets/profile_goals_screen.dart';

void main() {
  test('the profile shows the onboarding answers approval kept', () {
    final rows = onboardingAnswerRows({
      'sex': 'female',
      'birth_year': 1992,
      'daily_activity': 'some_standing',
      'equipment': ['dumbbells', 'pull_up_bar'],
      'equipment_note': 'Dumbbells up to 20 kg',
      'avoid_patterns': ['squat', 'vertical_push'],
      'limitations_note': 'Left knee',
      'nutrition_note': '',
    });
    expect(rows['Sex'], 'Female');
    expect(rows['Daily activity'], 'On my feet some of the day');
    expect(rows['Equipment'], 'Dumbbells, Pull Up Bar');
    expect(rows['Equipment note'], 'Dumbbells up to 20 kg');
    expect(rows['Movements to avoid'], 'Squats, Overhead pressing');
    expect(rows['Diet'], 'None');
    final bare = onboardingAnswerRows({'sex': 'male'});
    expect(bare['Equipment'], 'Bodyweight only');
    expect(bare['Movements to avoid'], 'None');
    expect(bare.containsKey('Equipment note'), isFalse);
  });

  testWidgets('older profiles without the answers show no empty section', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: ProfileGoalsScreen(
          data: Future.value(const {
            'profile': {'experience_level': 'beginner'},
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ONBOARDING ANSWERS'), findsNothing);
    expect(find.text('TRAINING PROFILE'), findsOneWidget);
  });
}
