import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/coach_screen.dart';

void main() {
  testWidgets('Coach shows an evidence-grounded stored decision', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: const Scaffold(
          body: CoachScreen(repository: _DecisionRepository()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Keep today’s approved plan.'), findsOneWidget);
    expect(
      find.text('Recovery indicators are within the recent baseline'),
      findsOneWidget,
    );
    expect(find.text('Refresh decision'), findsOneWidget);
  });

  testWidgets('Coach failure explicitly preserves the approved plan', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: const Scaffold(
          body: CoachScreen(repository: _FailureRepository()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate today’s decision'));
    await tester.pumpAndSettle();
    expect(
      find.text('Coaching is unavailable. Your approved plan is unchanged.'),
      findsOneWidget,
    );
  });
}

final _decision = CoachDecision(
  id: 'decision-1',
  localDate: '2026-07-02',
  trainingAction: 'PROCEED_AS_PLANNED',
  trainingSummary: 'Complete the scheduled session.',
  nutritionAction: 'MAINTAIN_TARGETS',
  nutritionSummary: 'Keep approved nutrition targets.',
  finalDecision: 'Keep today’s approved plan.',
  reason: 'Current evidence supports maintaining the plan.',
  confidence: 'medium',
  evidence: [
    {
      'code': 'RECOVERY_WITHIN_BASELINE',
      'label': 'Recovery indicators are within the recent baseline',
      'source': 'feature_snapshot',
    },
  ],
  missingData: [],
  riskFlags: [],
  createdAt: DateTime.utc(2026, 7, 2),
);

class _DecisionRepository implements CoachRepository {
  const _DecisionRepository();
  @override
  Future<CoachDecision?> loadLatest() async => _decision;
  @override
  Future<CoachDecision> generate() async => _decision;
  @override
  Future<Map<String, dynamic>> loadUsage() async => const {};
}

class _FailureRepository implements CoachRepository {
  const _FailureRepository();
  @override
  Future<CoachDecision?> loadLatest() async => null;
  @override
  Future<CoachDecision> generate() => throw StateError('offline');
  @override
  Future<Map<String, dynamic>> loadUsage() async => const {};
}
