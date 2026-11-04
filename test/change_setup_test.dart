import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/account_screen.dart';
import 'package:tracend/features/consent/legal_consent.dart';
import 'package:tracend/features/onboarding/current_setup.dart';
import 'package:tracend/features/onboarding/onboarding_repository.dart';
import 'package:tracend/features/onboarding/onboarding_screening.dart';
import 'package:tracend/shared/plan_changes.dart';

const _offline = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

const _cleared = {
  'exercises_regularly': true,
  'known_disease': false,
  'symptoms': false,
  'cleared_by_professional': false,
};

/// The approved answers: three training days, 60 minutes, dumbbells.
const _approved = OnboardingDraft(
  path: 'beginner',
  currentSection: 'review',
  payload: {
    'goal': 'muscle_gain',
    'experience': 'beginner',
    'sex': 'female',
    'birth_year': 1992,
    'height_cm': 165,
    'weight_kg': 62.5,
    'daily_activity': 'some_standing',
    'training_weekdays': [1, 3, 5],
    'training_days': 3,
    'session_minutes': 60,
    'equipment_items': ['dumbbells'],
    'equipment': '',
    'nutrition_context': 'No dairy',
    'constraints': '',
    'avoid_patterns': <String>[],
    'screening': _cleared,
  },
);

void main() {
  testWidgets('Account opens the Review step with the approved answers', (
    tester,
  ) async {
    final harness = await _open(tester);

    expect(find.text('Review your setup.'), findsOneWidget);
    expect(find.textContaining('Your current plan stays active'), findsOne);
    expect(find.text('Mon, Wed, Fri · 60 min'), findsOneWidget);
    expect(find.text('Dumbbells'), findsOneWidget);
    expect(find.text('Muscle gain'), findsOneWidget);
    expect(find.textContaining('Step '), findsOneWidget);
    // Opening changes nothing on the server.
    expect(harness.repository.saveCalls, 0);
    expect(harness.repository.startCalls, 0);
    expect(harness.repository.responses, isEmpty);
  });

  testWidgets('leaving from Review changes nothing', (tester) async {
    final harness = await _open(tester);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Change my setup'), findsOneWidget);
    expect(harness.repository.saveCalls, 0);
    expect(harness.repository.startCalls, 0);
    expect(harness.repository.responses, isEmpty);
    // The plan screens refresh whenever the flow closes; nothing changed.
    expect(harness.announced, 1);
  });

  testWidgets('a changed schedule builds a new proposal, and approving it '
      'replaces the plan', (tester) async {
    final harness = await _open(tester);

    await tester.ensureVisible(find.byTooltip('Edit schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit schedule'));
    await tester.pumpAndSettle();
    expect(find.text('When do you train?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'Sat'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Save and return to review'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mon, Wed, Fri, Sat · 60 min'), findsOneWidget);
    // Editing a step keeps the answers in the form: nothing is saved until
    // the athlete asks for a plan.
    expect(harness.repository.startCalls, 0);

    await tester.tap(
      find.widgetWithText(FilledButton, 'Continue to your coach'),
    );
    await tester.pumpAndSettle();

    expect(harness.repository.startCalls, 1);
    expect(harness.repository.savedPayload?['training_weekdays'], [1, 3, 5, 6]);
    expect(harness.repository.savedPayload?['session_minutes'], 60);
    expect(find.text('Your new plan'), findsOneWidget);
    expect(find.textContaining('replaces your current plan'), findsOneWidget);
    // The proposal is only shown: the plan is not yet answered.
    expect(harness.repository.responses, isEmpty);
    expect(harness.announced, 0);

    final approve = find.widgetWithText(FilledButton, 'Approve plan');
    await tester.ensureVisible(approve);
    await tester.pumpAndSettle();
    await tester.tap(approve);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(harness.repository.responses, ['accept']);
    expect(harness.repository.respondedIds, ['proposal-new']);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Your new plan is active.'), findsOneWidget);
    expect(harness.announced, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('leaving the proposal without approving changes nothing', (
    tester,
  ) async {
    final harness = await _open(tester);

    await tester.tap(
      find.widgetWithText(FilledButton, 'Continue to your coach'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your new plan'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Account'), findsOneWidget);
    expect(harness.repository.responses, isEmpty);
    expect(harness.announced, 1);
    expect(find.text('Your new plan is active.'), findsNothing);
  });

  testWidgets('the flow cannot be left while the approval is saving', (
    tester,
  ) async {
    final repository = _Repository()..respondGate = Completer<void>();
    final harness = await _open(tester, repository: repository);

    await tester.tap(
      find.widgetWithText(FilledButton, 'Continue to your coach'),
    );
    await tester.pumpAndSettle();
    final approve = find.widgetWithText(FilledButton, 'Approve plan');
    await tester.ensureVisible(approve);
    await tester.pumpAndSettle();
    await tester.tap(approve);
    await tester.pump();

    expect(repository.responses, ['accept']);
    expect(find.byType(BackButton), findsNothing);
    expect(find.byType(CupertinoNavigationBarBackButton), findsNothing);
    expect(find.byTooltip('Back'), findsNothing);
    // The system back gesture is refused too.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Your new plan'), findsOneWidget);
    expect(find.text('Account'), findsNothing);

    repository.respondGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Your new plan is active.'), findsOneWidget);
    expect(harness.announced, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('the flow can be left again once the approval has failed', (
    tester,
  ) async {
    final repository = _Repository()
      ..respondGate = Completer<void>()
      ..failResponse = true;
    final harness = await _open(tester, repository: repository);

    await tester.tap(
      find.widgetWithText(FilledButton, 'Continue to your coach'),
    );
    await tester.pumpAndSettle();
    final approve = find.widgetWithText(FilledButton, 'Approve plan');
    await tester.ensureVisible(approve);
    await tester.pumpAndSettle();
    await tester.tap(approve);
    await tester.pump();
    repository.respondGate!.complete();
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Your new plan is active.'), findsNothing);
    expect(harness.announced, 1);
  });

  testWidgets('equipment the plan cannot work with opens the equipment step', (
    tester,
  ) async {
    final harness = await _open(
      tester,
      repository: _Repository()..infeasible = ['equipment_items'],
    );

    await tester.tap(
      find.widgetWithText(FilledButton, 'Continue to your coach'),
    );
    await tester.pumpAndSettle();

    expect(find.text('What can you train with?'), findsOneWidget);
    expect(
      find.textContaining('some training days would have no exercise'),
      findsOneWidget,
    );
    expect(harness.repository.responses, isEmpty);
  });

  testWidgets('the health check can still stop a plan', (tester) async {
    final harness = await _open(
      tester,
      repository: _Repository()..blockedByScreening = true,
    );

    await tester.tap(
      find.widgetWithText(FilledButton, 'Continue to your coach'),
    );
    await tester.pumpAndSettle();

    expect(find.text('A quick health check.'), findsOneWidget);
    expect(find.textContaining('health professional'), findsWidgets);
    expect(harness.repository.responses, isEmpty);
  });

  testWidgets('an athlete never screened is asked the health check first', (
    tester,
  ) async {
    await _open(
      tester,
      setup: OnboardingDraft(
        path: 'beginner',
        currentSection: 'review',
        payload: {..._approved.payload}..remove('screening'),
      ),
    );

    expect(find.text('A quick health check.'), findsOneWidget);
  });

  testWidgets('answers that do not load keep the athlete on Account', (
    tester,
  ) async {
    await _pumpAccount(
      tester,
      _Setup(fail: true),
      _Repository(),
      PlanChanges(),
    );
    await tester.tap(find.text('Change my setup'));
    await tester.pumpAndSettle();

    expect(find.text('Account'), findsOneWidget);
    expect(find.textContaining('did not load'), findsOneWidget);
    expect(find.text('Review your setup.'), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });
}

class _Harness {
  _Harness(this.repository, this.changes);

  final _Repository repository;
  final PlanChanges changes;
  int announced = 0;
}

Future<_Harness> _open(
  WidgetTester tester, {
  _Repository? repository,
  OnboardingDraft setup = _approved,
}) async {
  final repo = repository ?? _Repository();
  final changes = PlanChanges();
  final harness = _Harness(repo, changes);
  changes.addListener(() => harness.announced++);
  await _pumpAccount(tester, _Setup(setup: setup), repo, changes);
  await tester.tap(find.text('Change my setup'));
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _pumpAccount(
  WidgetTester tester,
  _Setup setup,
  _Repository repository,
  PlanChanges changes,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.light,
      home: AccountScreen(
        environment: _offline,
        onboarding: repository,
        currentSetup: setup,
        planChanges: changes,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Setup implements CurrentSetupSource {
  _Setup({this.setup = _approved, this.fail = false});

  final OnboardingDraft setup;
  final bool fail;

  @override
  Future<OnboardingDraft> load() async {
    if (fail) throw Exception('offline');
    return setup;
  }
}

class _Repository implements OnboardingRepository {
  List<String>? infeasible;
  bool blockedByScreening = false;
  int saveCalls = 0;
  int startCalls = 0;
  Map<String, dynamic>? savedPayload;
  final responses = <String>[];
  final respondedIds = <String>[];
  Completer<void>? respondGate;
  bool failResponse = false;

  @override
  Future<bool> isOnboardingComplete() async => true;

  @override
  Future<Set<LegalConsent>> loadOutdatedLegalConsents() async => {};

  @override
  Future<OnboardingDraft?> loadDraft() async => null;

  @override
  Future<void> saveDraft({
    required String? path,
    required String currentSection,
    required Map<String, dynamic> payload,
  }) async {
    saveCalls++;
    savedPayload = payload;
  }

  @override
  Future<void> recordEligibilityAndConsent({required bool eligible}) async {}

  @override
  Future<void> saveGoal(String goal) async {}

  @override
  Future<ScreeningRecord> recordScreening(ScreeningAnswers answers) async =>
      ScreeningRecord(
        outcome: ScreeningOutcome.cleared,
        screenedAt: DateTime.utc(2026),
      );

  @override
  Future<StoredScreening> loadScreening() async =>
      const StoredScreening(outcome: ScreeningOutcome.cleared, answers: null);

  @override
  Future<OnboardingQuestions> askQuestions() async {
    if (blockedByScreening) throw const OnboardingScreeningBlocked();
    if (infeasible != null) throw OnboardingPlanInfeasible(infeasible!);
    return const OnboardingQuestions(hash: 'hash', questions: []);
  }

  @override
  Future<OnboardingGeneration> startGeneration() async {
    startCalls++;
    return const OnboardingGeneration(
      id: 'generation-new',
      status: 'succeeded',
      proposalId: 'proposal-new',
      proposalStatus: 'pending',
    );
  }

  @override
  Future<OnboardingGeneration?> loadGeneration() async => null;

  @override
  Future<OnboardingProposal> loadProposal(String proposalId) async =>
      OnboardingProposal.fromRow({
        'id': proposalId,
        'proposed_training': {
          'title': 'Foundation block',
          'block_weeks': 6,
          'origin': 'rules',
          'prescription': {'progression': 'Add load at the top of the range.'},
          'weekly_structure': [
            {
              'preferred_weekday': 1,
              'name': 'Full body A',
              'objective': 'Squat and row',
              'estimated_minutes': 52,
              'exercises': [
                {
                  'name': 'Goblet squat',
                  'sets': 3,
                  'rep_min': 8,
                  'rep_max': 12,
                  'target_rpe': 7.5,
                  'rest_seconds': 120,
                  'notes': '',
                },
              ],
            },
          ],
        },
        'proposed_nutrition': {
          'calories': 2100,
          'protein_g': 140,
          'carbohydrate_g': 235,
          'fat_g': 65,
          'rationale': 'Middle of the range.',
        },
        'rationale': 'Built from your answers.',
        'expected_benefit': 'A measurable start.',
        'downside': 'Estimates need data.',
        'confidence': 'medium',
      });

  @override
  Future<void> respond(String proposalId, String action, {String? note}) async {
    responses.add(action);
    respondedIds.add(proposalId);
    await respondGate?.future;
    if (failResponse) throw Exception('offline');
  }
}
