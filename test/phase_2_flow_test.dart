import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/auth/owner_auth_screen.dart';
import 'package:tracend/features/consent/ai_coaching_consent.dart';
import 'package:tracend/features/health/health_baseline.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/onboarding/onboarding_flow.dart';
import 'package:tracend/features/onboarding/onboarding_proposal_view.dart';
import 'package:tracend/features/onboarding/onboarding_repository.dart';

void main() {
  testWidgets('owner auth validates fields before contacting Supabase', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: OwnerAuthScreen(onAuthenticated: () {}),
      ),
    );

    expect(find.text('Owner development access'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(
      find.text('Password must contain at least 8 characters.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Create account'));
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'Create account'), findsOneWidget);
  });

  testWidgets('a beginner answers every step and approves the exact plan', (
    tester,
  ) async {
    final repository = _FakeOnboardingRepository(
      generations: [_running, _succeeded],
    );
    final consent = FixtureAiCoachingConsentRepository();
    var completed = false;
    await _pump(
      tester,
      repository,
      onCompleted: () => completed = true,
      consent: AiCoachingConsentController(consent),
    );

    await _tapText(tester, 'I am 18 or older');
    await _tapText(tester, 'I accept the private-beta terms');
    await _tapText(tester, 'I have read the privacy notice');
    await _continue(tester);

    expect(find.text('Allow AI coaching?'), findsOneWidget);
    await _continue(tester);
    expect(find.text('Choose whether to allow AI coaching.'), findsOneWidget);
    await _tapText(tester, 'Allow AI coaching');
    await _continue(tester);
    expect(consent.recorded, [true]);

    await _tapText(tester, 'Guide me');
    await _continue(tester);
    await _tapText(tester, 'Fat loss');
    await _continue(tester);

    expect(find.text('Connect Apple Health?'), findsOneWidget);
    await _continue(tester);
    expect(
      find.text('Connect Apple Health, or choose Skip for now.'),
      findsOneWidget,
    );
    await _tapText(tester, 'Skip for now');

    expect(find.text('About you.'), findsOneWidget);
    await _continue(tester);
    expect(find.text('Choose an option for sex.'), findsOneWidget);
    await _tapText(tester, 'Female');
    await tester.enterText(find.byKey(const ValueKey('birth-year')), '1992');
    await tester.pumpAndSettle();
    await _tapText(tester, 'On my feet some of the day');
    await _continue(tester);

    expect(find.text('When do you train?'), findsOneWidget);
    await _tapText(tester, 'Thu');
    await _continue(tester);

    expect(find.text('What can you train with?'), findsOneWidget);
    await _tapText(tester, 'Dumbbells');
    await _continue(tester);

    expect(find.text('Food and limits.'), findsOneWidget);
    await _tapText(tester, 'Squats');
    await _tapText(tester, 'Overhead pressing');
    await _continue(tester);

    // A beginner skips the training and top-set steps.
    expect(find.text('Where should the plan focus?'), findsOneWidget);
    expect(find.textContaining('Step 10 of 13'), findsOneWidget);
    // The first row is "Bring up"; the second, "Already strong".
    await tester.tap(find.widgetWithText(FilterChip, 'Chest').first);
    await tester.pumpAndSettle();
    await _continue(tester);
    expect(find.text('Review before building.'), findsOneWidget);
    expect(find.text('Mon, Wed, Thu, Fri · 60 min'), findsOneWidget);
    expect(find.text('Squats, Overhead pressing'), findsOneWidget);
    expect(find.text('Bring up chest'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(FilledButton, 'Continue to your coach'),
    );
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Your starting plan'), findsOneWidget);
    expect(
      find.textContaining('Proposed by AI (deepseek-flash)'),
      findsOneWidget,
    );
    expect(find.text('Mon · Full body A'), findsOneWidget);
    expect(find.text('Goblet squat'), findsOneWidget);
    expect(find.text('2100 kcal a day'), findsOneWidget);
    expect(find.textContaining('How this was calculated'), findsOneWidget);

    final payload = repository.savedPayload!;
    expect(payload['training_weekdays'], [1, 3, 4, 5]);
    expect(payload['training_days'], 4);
    expect(payload['equipment_items'], ['dumbbells']);
    expect(payload['sex'], 'female');
    expect(payload['birth_year'], 1992);
    expect(payload['daily_activity'], 'some_standing');
    expect(payload['goal'], 'fat_loss');
    expect(payload['avoid_patterns'], ['squat', 'vertical_push']);
    expect(payload['health_import'], 'skipped');
    expect(payload['priority_muscles'], ['chest']);
    expect(payload.containsKey('training_years'), isFalse);
    // No questions came back: the plan was built straight away.
    expect(repository.askCalls, 1);

    final approve = find.widgetWithText(FilledButton, 'Approve plan');
    await tester.ensureVisible(approve);
    await tester.pumpAndSettle();
    await tester.tap(approve);
    await tester.pumpAndSettle();
    // Approval shows "You're set" once; the app opens from its button.
    expect(completed, isFalse);
    expect(find.text("You're set."), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Go to Today'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(repository.responses, ['accept']);
  });

  testWidgets('passing the AI step again records only a changed answer', (
    tester,
  ) async {
    final consent = FixtureAiCoachingConsentRepository();
    await _pump(
      tester,
      _FakeOnboardingRepository(),
      consent: AiCoachingConsentController(consent),
    );
    await _tapText(tester, 'I am 18 or older');
    await _tapText(tester, 'I accept the private-beta terms');
    await _tapText(tester, 'I have read the privacy notice');
    await _continue(tester);

    await _tapText(tester, 'Allow AI coaching');
    await _continue(tester);
    await tester.tap(find.byTooltip('Previous section'));
    await tester.pumpAndSettle();
    await _continue(tester);
    expect(consent.recorded, [true]);

    await tester.tap(find.byTooltip('Previous section'));
    await tester.pumpAndSettle();
    await _tapText(tester, 'Not now');
    await _continue(tester);
    expect(consent.recorded, [true, false]);
  });

  testWidgets('the AI step shows the server notice', (tester) async {
    const notice = AiNotice(
      version: 'ai-coaching-v2',
      providerLabel: 'DeepSeek',
      body: 'First paragraph from the server.\n\nSecond paragraph.',
    );
    final controller = AiCoachingConsentController(
      FixtureAiCoachingConsentRepository(AiCoachingChoice.undecided, notice),
    );
    await _pump(
      tester,
      _FakeOnboardingRepository(draft: _draft('ai')),
      consent: controller,
    );
    expect(find.text('First paragraph from the server.'), findsOneWidget);
    expect(find.text('Second paragraph.'), findsOneWidget);
  });

  testWidgets('an older draft continues where the new answers start', (
    tester,
  ) async {
    final repository = _FakeOnboardingRepository(
      draft: const OnboardingDraft(
        path: 'experienced',
        currentSection: 'context',
        payload: {
          'goal': 'strength',
          'experience': 'intermediate',
          'training_days': 4,
          'session_minutes': 60,
          'weight_kg': 82,
          'equipment': 'Full gym',
          'nutrition_context': 'No restrictions',
          'current_plan': 'Upper/lower split',
        },
      ),
    );
    await _pump(tester, repository);

    expect(find.textContaining('Step 6 of 15'), findsOneWidget);
    expect(find.text('About you.'), findsOneWidget);
    expect(find.text('Current weight: 82 kg'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous section'));
    await tester.pumpAndSettle();
    // The Apple Health step is new and optional; an older draft passes it.
    expect(find.text('Connect Apple Health?'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous section'));
    await tester.pumpAndSettle();
    expect(find.text('Strength'), findsOneWidget);
  });

  testWidgets('an older draft saved at review still asks the new questions', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeOnboardingRepository(
        draft: const OnboardingDraft(
          path: 'beginner',
          currentSection: 'review',
          payload: {'goal': 'recomposition', 'training_days': 3},
        ),
      ),
    );
    expect(find.text('About you.'), findsOneWidget);
  });

  testWidgets('reopening while the plan builds waits, then shows it', (
    tester,
  ) async {
    final repository = _FakeOnboardingRepository(
      draft: _draft('proposal'),
      generations: [_running, _running, _succeeded],
    );
    await _pump(tester, repository);
    expect(find.text('Building your plan'), findsOneWidget);
    expect(find.byTooltip('Previous section'), findsOneWidget);

    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Your starting plan'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Approve plan'), findsOneWidget);
  });

  testWidgets('reopening after the plan was answered returns to review', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeOnboardingRepository(
        draft: _draft('proposal'),
        generations: [
          const OnboardingGeneration(
            id: 'gen-1',
            status: 'succeeded',
            proposalId: 'p-1',
            proposalStatus: 'rejected',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Review before building.'), findsOneWidget);
  });

  testWidgets('a failed generation offers a retry instead of spinning', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeOnboardingRepository(
        draft: _draft('proposal'),
        generations: [
          const OnboardingGeneration(
            id: 'gen-1',
            status: 'failed',
            errorCode: 'lease_expired',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your plan was not built.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
  });

  testWidgets('requesting changes sends the note and returns to review', (
    tester,
  ) async {
    final repository = _FakeOnboardingRepository(
      draft: _draft('proposal'),
      generations: [_succeeded],
    );
    await _pump(tester, repository);
    await tester.pumpAndSettle();

    final revise = find.widgetWithText(OutlinedButton, 'Request changes');
    await tester.ensureVisible(revise);
    await tester.pumpAndSettle();
    await tester.tap(revise);
    await tester.pumpAndSettle();
    // An empty request cannot be sent.
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Request changes'),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField).last, 'No deadlifts');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Request changes'));
    await tester.pumpAndSettle();

    expect(repository.responses, ['request_revision']);
    expect(repository.notes, ['No deadlifts']);
    expect(find.text('Review before building.'), findsOneWidget);
    expect(repository.savedPayload!['revision_note'], 'No deadlifts');
  });

  testWidgets('missing answers reported by the server open their step', (
    tester,
  ) async {
    final repository = _FakeOnboardingRepository(
      draft: _draft('review'),
      missing: const ['equipment_items'],
    );
    await _pump(tester, repository);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Continue to your coach'),
    );
    await tester.pumpAndSettle();
    expect(find.text('What can you train with?'), findsOneWidget);
    expect(find.text('Add your equipment to build your plan.'), findsOneWidget);
  });

  testWidgets(
    'a draft that never answered movements to avoid does not invent an answer',
    (tester) async {
      final repository = _FakeOnboardingRepository(
        draft: _draft('review'),
        missing: const ['avoid_patterns'],
      );
      await _pump(tester, repository);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Continue to your coach'),
      );
      await tester.pumpAndSettle();
      expect(repository.savedPayload!.containsKey('avoid_patterns'), isFalse);
      expect(find.text('Food and limits.'), findsOneWidget);
      expect(
        find.textContaining('Choose the movements your plan should leave out'),
        findsOneWidget,
      );
      await _continue(tester);
      expect(repository.savedPayload!['avoid_patterns'], isEmpty);
    },
  );

  testWidgets('answers no plan can meet open the step to change', (
    tester,
  ) async {
    final repository = _FakeOnboardingRepository(
      draft: _draft('review'),
      infeasible: const ['avoid_patterns', 'equipment_items'],
    );
    await _pump(tester, repository);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Continue to your coach'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Food and limits.'), findsOneWidget);
    expect(
      find.textContaining('Avoid fewer movements or add equipment'),
      findsOneWidget,
    );
    expect(repository.startCalls, 1);
  });

  testWidgets('reopening an expired proposal offers a rebuild that works', (
    tester,
  ) async {
    var completed = false;
    final repository = _FakeOnboardingRepository(
      draft: _draft('proposal'),
      generations: [
        const OnboardingGeneration(
          id: 'gen-1',
          status: 'succeeded',
          proposalId: 'p-1',
          proposalStatus: 'expired',
        ),
        const OnboardingGeneration(id: 'gen-2', status: 'running'),
        const OnboardingGeneration(
          id: 'gen-2',
          status: 'succeeded',
          proposalId: 'p-2',
          proposalStatus: 'pending',
        ),
      ],
    );
    await _pump(tester, repository, onCompleted: () => completed = true);
    await tester.pumpAndSettle();

    expect(find.text('This plan proposal expired.'), findsOneWidget);
    expect(find.text('Approve plan'), findsNothing);
    expect(find.byTooltip('Previous section'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Build a new plan'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(repository.startCalls, 1);
    expect(find.text('Your starting plan'), findsOneWidget);

    final approve = find.widgetWithText(FilledButton, 'Approve plan');
    await tester.ensureVisible(approve);
    await tester.pumpAndSettle();
    await tester.tap(approve);
    await tester.pumpAndSettle();
    expect(repository.respondedIds, ['p-2']);
    // Approval shows "You're set" once; the app opens from its button.
    expect(completed, isFalse);
    expect(find.text("You're set."), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Go to Today'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
  });

  testWidgets('a proposal that expires before approval offers a rebuild', (
    tester,
  ) async {
    var completed = false;
    final repository = _FakeOnboardingRepository(
      draft: _draft('proposal'),
      generations: [_succeeded],
      staleResponses: 1,
    );
    await _pump(tester, repository, onCompleted: () => completed = true);
    await tester.pumpAndSettle();

    final approve = find.widgetWithText(FilledButton, 'Approve plan');
    await tester.ensureVisible(approve);
    await tester.pumpAndSettle();
    await tester.tap(approve);
    await tester.pumpAndSettle();
    expect(completed, isFalse);
    expect(find.text('This plan proposal expired.'), findsOneWidget);
    expect(find.byTooltip('Previous section'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Build a new plan'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Your starting plan'), findsOneWidget);
    final again = find.widgetWithText(FilledButton, 'Approve plan');
    await tester.ensureVisible(again);
    await tester.pumpAndSettle();
    await tester.tap(again);
    await tester.pumpAndSettle();
    // Approval shows "You're set" once; the app opens from its button.
    expect(completed, isFalse);
    expect(find.text("You're set."), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Go to Today'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
  });

  test('generation status reads an expired proposal as not reviewable', () {
    final expired = OnboardingGeneration.fromJson({
      'generation_id': 'gen-1',
      'status': 'succeeded',
      'proposal_id': 'p-1',
      'proposal_status': 'expired',
      'proposal_expires_at': '2026-09-25T10:00:00Z',
    })!;
    expect(expired.proposalExpired, isTrue);
    expect(expired.readyForReview, isFalse);
    // An older server still says pending; the expiry time decides.
    final lapsed = OnboardingGeneration.fromJson({
      'generation_id': 'gen-1',
      'status': 'succeeded',
      'proposal_id': 'p-1',
      'proposal_status': 'pending',
      'proposal_expires_at': '2026-09-25T10:00:00Z',
    })!;
    expect(lapsed.readyForReview, isFalse);
    final fresh = OnboardingGeneration.fromJson({
      'generation_id': 'gen-1',
      'status': 'succeeded',
      'proposal_id': 'p-1',
      'proposal_status': 'pending',
      'proposal_expires_at': DateTime.now()
          .add(const Duration(days: 3))
          .toUtc()
          .toIso8601String(),
    })!;
    expect(fresh.readyForReview, isTrue);
  });

  testWidgets('under-18 birth years are refused', (tester) async {
    await _pump(
      tester,
      _FakeOnboardingRepository(draft: _draft('about')),
      currentYear: 2026,
    );
    await tester.enterText(find.byKey(const ValueKey('birth-year')), '2010');
    await tester.pumpAndSettle();
    expect(find.text('Tracend is for adults 18 and over.'), findsOneWidget);
    await _continue(tester);
    expect(find.text('About you.'), findsOneWidget);
  });

  testWidgets('sign out is always available during onboarding', (tester) async {
    var signedOut = false;
    await _pump(
      tester,
      _FakeOnboardingRepository(
        draft: _draft('proposal'),
        generations: [_running],
      ),
      onSignOut: () async => signedOut = true,
    );
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(signedOut, isTrue);
  });

  group('recovery and controls', () {
    testWidgets('answers that fail to load are never overwritten', (
      tester,
    ) async {
      final repository = _FakeOnboardingRepository(draft: _draft('schedule'))
        ..failingLoads = 1;
      await _pump(tester, repository, onSignOut: () async {});
      await tester.pumpAndSettle();
      expect(find.text('Your answers did not load.'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
      expect(find.text('Sign out'), findsOneWidget);
      expect(repository.saveCalls, 0);
      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pumpAndSettle();
      expect(find.text('When do you train?'), findsOneWidget);
    });

    testWidgets('no goal is chosen for the athlete', (tester) async {
      await _pump(
        tester,
        _FakeOnboardingRepository(
          draft: const OnboardingDraft(
            path: 'beginner',
            currentSection: 'goal',
            payload: {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Lose fat and build muscle at about the same weight.'),
        findsOneWidget,
      );
      await _continue(tester);
      expect(
        find.text('Choose what your first block should prioritize.'),
        findsOneWidget,
      );
    });

    testWidgets('editing one answer from Review returns to Review', (
      tester,
    ) async {
      final repository = _FakeOnboardingRepository(draft: _draft('review'));
      await _pump(tester, repository);
      await tester.pumpAndSettle();
      expect(find.text('No dairy'), findsOneWidget);
      final edit = find.byTooltip('Edit equipment');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(find.text('What can you train with?'), findsOneWidget);
      await _tapText(tester, 'Kettlebells');
      await tester.tap(
        find.widgetWithText(FilledButton, 'Save and return to review'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Review before building.'), findsOneWidget);
      expect(find.text('Dumbbells, Kettlebells'), findsOneWidget);
      expect(repository.savedPayload!['equipment_items'], [
        'dumbbells',
        'kettlebells',
      ]);
    });

    testWidgets('exact values with − and +, spoken with their unit', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _FakeOnboardingRepository(draft: _draft('about')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Increase current weight'));
      await tester.pumpAndSettle();
      expect(find.text('Current weight: 68.5 kg'), findsOneWidget);
      await tester.tap(find.byTooltip('Decrease height'));
      await tester.pumpAndSettle();
      expect(find.text('Height: 164 cm'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('68.5 kg')), findsWidgets);
      handle.dispose();
    });

    testWidgets('rejecting asks first; one tap approves once', (tester) async {
      final repository = _FakeOnboardingRepository(
        draft: _draft('proposal'),
        generations: [_succeeded],
      );
      await _pump(tester, repository);
      await tester.pumpAndSettle();
      final reject = find.widgetWithText(TextButton, 'Reject proposal');
      await tester.ensureVisible(reject);
      await tester.tap(reject);
      await tester.pumpAndSettle();
      expect(find.text('Reject this plan?'), findsOneWidget);
      await tester.tap(find.text('Keep reviewing'));
      await tester.pumpAndSettle();
      expect(repository.responses, isEmpty);

      final approve = find.widgetWithText(FilledButton, 'Approve plan');
      await tester.ensureVisible(approve);
      await tester.tap(approve);
      await tester.tap(approve, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(repository.responses, ['accept']);
      expect(find.textContaining('Next session:'), findsOneWidget);
      expect(find.text('Each day: 2100 kcal · 140 g protein'), findsOneWidget);
    });

    testWidgets('an unavailable plan builder says so', (tester) async {
      final repository = _FakeOnboardingRepository(draft: _draft('review'))
        ..unavailable = true;
      await _pump(tester, repository);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Continue to your coach'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('The plan builder is unavailable. Try again in a minute.'),
        findsOneWidget,
      );
    });

    test('effort reads as reps left', () {
      expect(
        OnboardingProposalView.effortText(7.5),
        'RPE 7.5 (about 2–3 reps left)',
      );
      expect(OnboardingProposalView.effortText(8), 'RPE 8 (about 2 reps left)');
      expect(OnboardingProposalView.effortText(9), 'RPE 9 (about 1 rep left)');
    });
  });

  group('2x text', () {
    Future<void> large(
      WidgetTester tester,
      _FakeOnboardingRepository repo,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(tester, repo, onSignOut: () async {}, width: 320);
      await tester.pumpAndSettle();
    }

    for (final section in [
      'eligibility',
      'ai',
      'path',
      'goal',
      'health',
      'about',
      'schedule',
      'equipment',
      'food',
      'training',
      'lifts',
      'focus',
      'review',
    ]) {
      testWidgets('$section lays out at 2x text', (tester) async {
        await large(
          tester,
          _FakeOnboardingRepository(
            draft: _experiencedDraft(section, {
              'current_lifts': [
                {
                  'slug': 'barbell-bench-press',
                  'load_kg': 100,
                  'reps': 5,
                  'reps_left': 1,
                },
              ],
              'priority_muscles': ['chest'],
            }),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the proposal and "You\'re set" lay out at 2x text', (
      tester,
    ) async {
      await large(
        tester,
        _FakeOnboardingRepository(
          draft: _draft('proposal'),
          generations: [_succeeded],
        ),
      );
      expect(tester.takeException(), isNull);
      final approve = find.widgetWithText(FilledButton, 'Approve plan');
      await tester.ensureVisible(approve);
      await tester.tap(approve);
      await tester.pumpAndSettle();
      expect(find.text("You're set."), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Coach intake', () {
    testWidgets(
      'an experienced athlete reports training, a top set and a focus',
      (tester) async {
        final repository = _FakeOnboardingRepository(
          draft: _experiencedDraft('food', {'training_years': null}),
        );
        await _pump(tester, repository);
        await _continue(tester);

        expect(find.text('Your training so far.'), findsOneWidget);
        expect(find.textContaining('Step 10 of 15'), findsOneWidget);
        await _continue(tester);
        expect(find.text('Choose how long you have trained.'), findsOneWidget);
        await _tapText(tester, 'Over 5 years');
        await tester.enterText(
          find.widgetWithText(
            TextField,
            'What has worked, and what has stalled',
          ),
          'Bench stuck at 80 kg',
        );
        await _continue(tester);

        expect(find.text('Recent top sets.'), findsOneWidget);
        await tester.tap(find.widgetWithText(SwitchListTile, 'Bench press'));
        await tester.pumpAndSettle();
        final heavier = find.byTooltip('Increase bench press weight');
        await tester.ensureVisible(heavier);
        await tester.tap(heavier);
        await tester.pumpAndSettle();
        await tester.tap(heavier);
        await tester.pumpAndSettle();
        await _tapText(tester, 'None');
        await _continue(tester);

        expect(find.text('Where should the plan focus?'), findsOneWidget);
        final bringUp = find.widgetWithText(FilterChip, 'Back').first;
        await tester.tap(bringUp);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilterChip, 'Chest').first);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilterChip, 'Calves').first);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Focusing on everything is focusing on nothing'),
          findsWidgets,
        );
        // A strong muscle cannot also be a focus.
        await tester.tap(find.widgetWithText(FilterChip, 'Back').last);
        await tester.pumpAndSettle();
        await _continue(tester);

        expect(find.text('Review before building.'), findsOneWidget);
        expect(find.text('Bench press 65 kg × 5 to failure'), findsOneWidget);
        expect(find.text('Bring up chest · strong back'), findsOneWidget);
        final payload = repository.savedPayload!;
        expect(payload['training_years'], 'over_5');
        expect(payload['training_history'], 'Bench stuck at 80 kg');
        expect(payload['current_lifts'], [
          {
            'slug': 'barbell-bench-press',
            'load_kg': 65.0,
            'reps': 5,
            'reps_left': 0,
          },
        ]);
        expect(payload['priority_muscles'], ['chest']);
        expect(payload['strong_muscles'], ['back']);
      },
    );

    testWidgets('the coach asks, and the answers go with the plan', (
      tester,
    ) async {
      final repository =
          _FakeOnboardingRepository(
              draft: _experiencedDraft('review'),
              generations: [_succeeded],
            )
            ..questions = const [
              FollowUpQuestion(
                category: 'stalled_lift',
                question: 'How often do you bench now?',
                choices: ['Once a week', 'Twice a week'],
              ),
              FollowUpQuestion(
                category: 'recovery_between_sessions',
                question: 'How do you feel the day after legs?',
                choices: [],
              ),
            ];
      await _pump(tester, repository);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Continue to your coach'),
      );
      await tester.pumpAndSettle();

      expect(find.text('A few questions from your coach.'), findsOneWidget);
      expect(repository.startCalls, 0);
      await _tapText(tester, 'Twice a week');
      await tester.enterText(
        find.widgetWithText(TextField, 'Your answer'),
        'Sore for two days',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Build my plan'));
      await tester.pumpAndSettle();

      expect(find.text('Your starting plan'), findsOneWidget);
      final payload = repository.savedPayload!;
      expect(payload['follow_ups_hash'], 'a' * 64);
      expect(payload['follow_ups'], [
        {
          'category': 'stalled_lift',
          'question': 'How often do you bench now?',
          'answer': 'Twice a week',
        },
        {
          'category': 'recovery_between_sessions',
          'question': 'How do you feel the day after legs?',
          'answer': 'Sore for two days',
        },
      ]);
    });

    testWidgets('skip builds the plan while the coach is still reading', (
      tester,
    ) async {
      final repository = _FakeOnboardingRepository(
        draft: _experiencedDraft('review'),
        generations: [_succeeded],
      )..questionsDelay = Completer<void>();
      await _pump(tester, repository);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Continue to your coach'),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Your coach is reading your answers'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Skip and build my plan'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your starting plan'), findsOneWidget);
      expect(repository.startCalls, 1);
      expect(repository.savedPayload!.containsKey('follow_ups'), isFalse);
      // The late answer changes nothing.
      repository.questionsDelay!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Your starting plan'), findsOneWidget);
    });

    testWidgets(
      'an edited answer drops the follow-up answers it no longer fits',
      (tester) async {
        final repository = _FakeOnboardingRepository(
          draft: _experiencedDraft('review', {
            'follow_ups_hash': 'b' * 64,
            'follow_ups': [
              {
                'category': 'stalled_lift',
                'question': 'How often do you bench now?',
                'answer': 'Once a week',
              },
            ],
          }),
        );
        await _pump(tester, repository);
        final edit = find.byTooltip('Edit focus');
        await tester.ensureVisible(edit);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilterChip, 'Chest').first);
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(FilledButton, 'Save and return to review'),
        );
        await tester.pumpAndSettle();
        expect(
          repository.savedPayload!.containsKey('follow_ups_hash'),
          isFalse,
        );
        expect(repository.savedPayload!['priority_muscles'], ['chest']);
      },
    );

    testWidgets('Apple Health shows the usual months next to the last weeks', (
      tester,
    ) async {
      final repository = _FakeOnboardingRepository(draft: _draft('health'));
      final baseline = _FakeBaseline(
        const HealthBaseline(
          months: 11,
          usualStrengthPerWeek: 3.4,
          recentStrengthPerWeek: 1,
          usualSleepMinutes: 410,
        ),
      );
      await _pump(
        tester,
        repository,
        health: _FakeHealth(
          connectStatus: _connected,
          history: HealthHistory([
            for (var back = 20; back >= 1; back--)
              HealthDay(
                date: DateTime.now().subtract(Duration(days: back)),
                presentMetrics: const {HealthMetric.steps},
                steps: 8000,
              ),
          ]),
        ),
        healthBaseline: baseline,
      );
      await _tapText(tester, 'Connect Apple Health');
      expect(baseline.loads, 1);
      expect(
        find.text('Strength: 3.4× a week usually · 1× a week lately'),
        findsOneWidget,
      );
      expect(find.text('Sleep: 6 h 50 min usually'), findsOneWidget);
    });

    testWidgets('a short history says the plan uses the last weeks', (
      tester,
    ) async {
      final repository = _FakeOnboardingRepository(draft: _draft('health'));
      await _pump(
        tester,
        repository,
        health: _FakeHealth(
          connectStatus: _connected,
          history: HealthHistory([
            HealthDay(
              date: DateTime.now().subtract(const Duration(days: 2)),
              presentMetrics: const {HealthMetric.steps},
              steps: 8000,
            ),
          ]),
        ),
        healthBaseline: _FakeBaseline(const HealthBaseline(months: 2)),
      );
      await _tapText(tester, 'Connect Apple Health');
      expect(
        find.textContaining('Fewer than 3 earlier months of data'),
        findsOneWidget,
      );
    });

    testWidgets('the proposal shows starting loads, the focus and usual months', (
      tester,
    ) async {
      final repository = _FakeOnboardingRepository(
        draft: _draft('proposal'),
        generations: [_succeeded],
      )..intakeProposal = true;
      await _pump(tester, repository);
      await tester.pumpAndSettle();
      expect(find.text('Start at 82.5 kg'), findsOneWidget);
      expect(find.text('Focus: chest 10+ sets a week.'), findsOneWidget);
      expect(
        find.textContaining(
          'Your usual months (11): strength 3.4 times a week · sleep 7 h 5 min.',
        ),
        findsOneWidget,
      );
    });
  });

  group('Apple Health step', () {
    final today = DateTime.now();
    HealthDay day(int back, {int? steps, double? weightKg}) => HealthDay(
      date: DateTime(today.year, today.month, today.day - back),
      presentMetrics: {
        if (steps != null) HealthMetric.steps,
        if (weightKg != null) HealthMetric.weight,
      },
      steps: steps,
      weightKg: weightKg,
    );
    final history = HealthHistory([
      for (var back = 20; back >= 1; back--) day(back, steps: 9100),
      day(3, weightKg: 81.5),
    ]);

    testWidgets(
      'connecting fills weight and shows steps; the athlete confirms',
      (tester) async {
        final repository = _FakeOnboardingRepository(draft: _draft('health'));
        final health = _FakeHealth(connectStatus: _connected, history: history);
        await _pump(tester, repository, health: health);

        expect(find.text('Connect Apple Health?'), findsOneWidget);
        await _tapText(tester, 'Connect Apple Health');
        expect(health.connectCalls, 1);
        expect(find.text('Apple Health connected'), findsOneWidget);
        expect(
          find.textContaining('21 of 28 days · steps, weight'),
          findsOneWidget,
        );
        await _continue(tester);

        expect(find.text('About you.'), findsOneWidget);
        expect(find.text('Current weight: 81.5 kg'), findsOneWidget);
        expect(find.textContaining('From Apple Health,'), findsOneWidget);
        expect(
          find.text(
            'Apple Health: about 9,100 steps a day over the last 4 weeks.',
          ),
          findsOneWidget,
        );
        // 9,100 steps matches "on my feet most of the day", nothing else.
        expect(find.text('Matches your steps'), findsOneWidget);
        expect(repository.savedPayload!['health_import'], 'connected');
      },
    );

    testWidgets(
      'steps without workouts or weight still connect; no data explains access',
      (tester) async {
        final repository = _FakeOnboardingRepository(draft: _draft('health'));
        final health = _FakeHealth(
          connectStatus: const HealthSyncStatus(
            state: HealthConnectionState.partial,
            availableMetrics: {},
          ),
          history: const HealthHistory([]),
        );
        await _pump(tester, repository, health: health);
        await _tapText(tester, 'Connect Apple Health');
        expect(find.text('No Apple Health data came back'), findsOneWidget);
        expect(find.textContaining('Data Access & Devices'), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);
        await _continue(tester);
        expect(find.text('About you.'), findsOneWidget);
        expect(repository.savedPayload!['health_import'], 'empty');
        // Nothing came back, so the weight stays the athlete's own answer.
        expect(find.text('Current weight: 68 kg'), findsOneWidget);
      },
    );

    testWidgets('a failed or refused connection can be retried or skipped', (
      tester,
    ) async {
      final repository = _FakeOnboardingRepository(draft: _draft('health'));
      final health = _FakeHealth(connectThrows: true);
      await _pump(tester, repository, health: health);
      await _tapText(tester, 'Connect Apple Health');
      expect(find.textContaining('could not be read'), findsOneWidget);
      health
        ..connectThrows = false
        ..connectStatus = const HealthSyncStatus(
          state: HealthConnectionState.manualOnly,
          accessError: HealthAccessError.authorizationDenied,
        );
      await _tapText(tester, 'Connect Apple Health');
      expect(health.connectCalls, 2);
      await _tapText(tester, 'Skip for now');
      expect(find.text('About you.'), findsOneWidget);
      expect(repository.savedPayload!['health_import'], 'skipped');
    });

    testWidgets(
      'reopened after the app closed mid-sync, a finished sync counts',
      (tester) async {
        // The sync finished, but the app closed before Continue was saved.
        final health = _FakeHealth(status: _connected, history: history);
        await _pump(
          tester,
          _FakeOnboardingRepository(draft: _draft('health')),
          health: health,
        );
        await tester.pumpAndSettle();
        expect(find.text('Apple Health connected'), findsOneWidget);
        expect(health.connectCalls, 0);
      },
    );

    testWidgets('an answered weight is never replaced by Apple Health', (
      tester,
    ) async {
      final health = _FakeHealth(status: _connected, history: history);
      await _pump(
        tester,
        _FakeOnboardingRepository(draft: _draft('schedule')),
        health: health,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Previous section'));
      await tester.pumpAndSettle();
      expect(find.text('Current weight: 68 kg'), findsOneWidget);
      expect(find.textContaining('From Apple Health,'), findsNothing);
    });

    testWidgets('the proposal shows the Apple Health the plan used', (
      tester,
    ) async {
      final repository = _FakeOnboardingRepository(
        draft: _draft('review'),
        generations: [_succeeded],
        calculationHealth: const {
          'window_days': 28,
          'days_with_data': 26,
          'steps_per_day': 9132,
          'workouts_per_week': 3,
          'sleep_minutes_per_night': 410,
          'weight_trend_kg_per_week': -0.3,
        },
      );
      await _pump(tester, repository);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Continue to your coach'),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Apple Health, last 28 days: about 9,100 steps a day · 3 workouts a week · sleep 6 h 50 min · weight down 0.3 kg a week.',
        ),
        findsOneWidget,
      );
    });
  });
}

const _connected = HealthSyncStatus(
  state: HealthConnectionState.connected,
  availableMetrics: {HealthMetric.steps, HealthMetric.weight},
);

class _FakeHealth implements HealthRepository {
  _FakeHealth({
    this.status = const HealthSyncStatus(
      state: HealthConnectionState.manualOnly,
    ),
    this.connectStatus = const HealthSyncStatus(
      state: HealthConnectionState.manualOnly,
    ),
    this.history = const HealthHistory([]),
    this.connectThrows = false,
  });

  HealthSyncStatus status;
  HealthSyncStatus connectStatus;
  HealthHistory history;
  bool connectThrows;
  int connectCalls = 0;

  @override
  Future<HealthSyncStatus> loadStatus() async => status;

  @override
  Future<HealthHistory> loadHistory() async => history;

  @override
  Future<HealthSyncStatus> connectAndSync() async {
    connectCalls++;
    if (connectThrows) throw Exception('sync failed');
    return status = connectStatus;
  }

  @override
  Future<HealthSyncStatus> sync() async => status;
}

const _running = OnboardingGeneration(id: 'gen-1', status: 'running');
const _succeeded = OnboardingGeneration(
  id: 'gen-1',
  status: 'succeeded',
  proposalId: 'p-1',
  proposalStatus: 'pending',
);

OnboardingDraft _experiencedDraft(
  String section, [
  Map<String, Object?> extra = const {},
]) => OnboardingDraft(
  path: 'experienced',
  currentSection: section,
  payload: {
    ..._draft(section).payload,
    'experience': 'intermediate',
    'current_plan': 'Upper/lower, four days',
    'training_years': 'over_5',
    ...extra,
  },
);

class _FakeBaseline implements HealthBaselineSource {
  _FakeBaseline(this.baseline);

  final HealthBaseline? baseline;
  int loads = 0;

  @override
  Future<HealthBaseline?> load() async {
    loads++;
    return baseline;
  }

  @override
  Future<void> refreshIfDue() async {}
}

OnboardingDraft _draft(String section) => OnboardingDraft(
  path: 'beginner',
  currentSection: section,
  payload: const {
    'goal': 'fat_loss',
    'experience': 'beginner',
    'sex': 'female',
    'birth_year': 1992,
    'height_cm': 165,
    'weight_kg': 68,
    'daily_activity': 'some_standing',
    'training_weekdays': [1, 3, 5],
    'session_minutes': 60,
    'equipment_items': ['dumbbells'],
    'equipment': '',
    'nutrition_context': 'No dairy',
    'constraints': '',
  },
);

Future<void> _pump(
  WidgetTester tester,
  _FakeOnboardingRepository repository, {
  VoidCallback? onCompleted,
  AiCoachingConsentController? consent,
  Future<void> Function()? onSignOut,
  int? currentYear,
  HealthRepository? health,
  HealthBaselineSource? healthBaseline,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.light,
      home: OnboardingFlow(
        repository: repository,
        onCompleted: onCompleted ?? () {},
        aiConsent: consent,
        health: health,
        healthBaseline: healthBaseline,
        onSignOut: onSignOut,
        pollInterval: Duration.zero,
        currentYear: currentYear,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _continue(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
  await tester.pumpAndSettle();
}

class _FakeOnboardingRepository implements OnboardingRepository {
  _FakeOnboardingRepository({
    this.draft,
    List<OnboardingGeneration> generations = const [],
    this.missing,
    this.infeasible,
    this.staleResponses = 0,
    this.calculationHealth,
  }) : _generations = [...generations];

  /// The Apple Health summary the fake proposal's calculation carries.
  final Map<String, Object?>? calculationHealth;

  final OnboardingDraft? draft;
  final List<OnboardingGeneration> _generations;
  final List<String>? missing;
  final List<String>? infeasible;

  /// How many responses fail as stale before they succeed.
  int staleResponses;
  Map<String, dynamic>? savedPayload;
  int startCalls = 0;
  final responses = <String>[];
  final respondedIds = <String>[];
  final notes = <String?>[];

  OnboardingGeneration? _next() => _generations.isEmpty
      ? null
      : _generations.length == 1
      ? _generations.first
      : _generations.removeAt(0);

  @override
  Future<bool> isOnboardingComplete() async => false;

  /// How many draft loads fail before one succeeds.
  int failingLoads = 0;
  bool unavailable = false;
  int saveCalls = 0;

  @override
  Future<OnboardingDraft?> loadDraft() async {
    if (failingLoads > 0) {
      failingLoads--;
      throw Exception('offline');
    }
    return draft;
  }

  @override
  Future<void> saveDraft({
    required String? path,
    required String currentSection,
    required Map<String, dynamic> payload,
  }) async {
    saveCalls++;
    savedPayload = payload;
  }

  int eligibilityCalls = 0;

  @override
  Future<void> recordEligibilityAndConsent({required bool eligible}) async {
    eligibilityCalls++;
  }

  @override
  Future<void> saveGoal(String goal) async {}

  @override
  Future<OnboardingGeneration> startGeneration() async {
    startCalls++;
    if (missing != null) throw OnboardingAnswersIncomplete(missing!);
    if (infeasible != null) throw OnboardingPlanInfeasible(infeasible!);
    if (unavailable) throw const OnboardingPlanUnavailable();
    return _next() ?? _running;
  }

  /// The coach's questions; none by default, so Review goes straight to the
  /// plan.
  List<FollowUpQuestion> questions = const [];
  String questionsHash = 'a' * 64;
  int askCalls = 0;

  /// When set, the questions wait for it (the coach still reading).
  Completer<void>? questionsDelay;

  @override
  Future<OnboardingQuestions> askQuestions() async {
    askCalls++;
    await questionsDelay?.future;
    return OnboardingQuestions(hash: questionsHash, questions: questions);
  }

  /// The proposal carries the coach intake: a starting load, the focus and
  /// the usual months.
  bool intakeProposal = false;

  @override
  Future<OnboardingGeneration?> loadGeneration() async => _next();

  @override
  Future<OnboardingProposal> loadProposal(String proposalId) async =>
      OnboardingProposal.fromRow({
        'id': proposalId,
        'proposed_training': {
          'title': 'Foundation block',
          'block_weeks': 6,
          'origin': 'ai',
          'model': 'deepseek-flash',
          'assessment': 'A balanced start for fat loss.',
          'assumptions': ['Weigh-ins will confirm calories.'],
          'missing_information': [],
          'prescription': {'progression': 'Add load at the top of the range.'},
          'calculation': {
            'bmr_kcal': [1400, 1400],
            'activity_factor': 1.375,
            'tdee_kcal': [2100, 2100],
            'calorie_range_kcal': [1580, 1890],
            'floor_applied': false,
            'health': ?calculationHealth,
            if (intakeProposal) ...{
              'priority_minimums': [
                {'muscle': 'chest', 'sets': 10},
              ],
              'health_history': {
                'months': 11,
                'first_month': '2025-11-01',
                'last_month': '2026-09-01',
                'usual_strength_per_week': 3.4,
                'usual_sleep_minutes': 425,
              },
            },
          },
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
                if (intakeProposal)
                  {
                    'name': 'Barbell bench press',
                    'sets': 4,
                    'rep_min': 5,
                    'rep_max': 8,
                    'target_rpe': 8,
                    'rest_seconds': 150,
                    'notes': '',
                    'start_load_kg': 82.5,
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
    if (staleResponses > 0) {
      staleResponses--;
      throw const OnboardingProposalStale();
    }
    responses.add(action);
    respondedIds.add(proposalId);
    notes.add(note);
  }
}
