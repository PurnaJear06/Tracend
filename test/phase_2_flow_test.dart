import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/auth/owner_auth_screen.dart';
import 'package:tracend/features/consent/ai_coaching_consent.dart';
import 'package:tracend/features/onboarding/onboarding_flow.dart';
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
    expect(find.text('Review before building.'), findsOneWidget);
    expect(find.text('Mon, Wed, Thu, Fri · 60 min'), findsOneWidget);
    expect(find.text('Squats, Overhead pressing'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Build my plan'));
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

    final approve = find.widgetWithText(FilledButton, 'Approve plan');
    await tester.ensureVisible(approve);
    await tester.pumpAndSettle();
    await tester.tap(approve);
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

    expect(find.textContaining('Section 5 of 10'), findsOneWidget);
    expect(find.text('About you.'), findsOneWidget);
    expect(find.text('Current weight: 82 kg'), findsOneWidget);
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
    await tester.enterText(find.byType(TextField).last, 'No deadlifts');
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
    await tester.tap(find.widgetWithText(FilledButton, 'Build my plan'));
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
      await tester.tap(find.widgetWithText(FilledButton, 'Build my plan'));
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
    await tester.tap(find.widgetWithText(FilledButton, 'Build my plan'));
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
}

const _running = OnboardingGeneration(id: 'gen-1', status: 'running');
const _succeeded = OnboardingGeneration(
  id: 'gen-1',
  status: 'succeeded',
  proposalId: 'p-1',
  proposalStatus: 'pending',
);

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
}) async {
  tester.view.physicalSize = const Size(390, 844);
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
  }) : _generations = [...generations];

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

  @override
  Future<OnboardingDraft?> loadDraft() async => draft;

  @override
  Future<void> saveDraft({
    required String? path,
    required String currentSection,
    required Map<String, dynamic> payload,
  }) async {
    savedPayload = payload;
  }

  @override
  Future<void> recordEligibilityAndConsent({
    required bool eligible,
    required String experience,
    required int trainingDays,
    required int sessionMinutes,
  }) async {}

  @override
  Future<void> saveGoal(String goal) async {}

  @override
  Future<OnboardingGeneration> startGeneration() async {
    startCalls++;
    if (missing != null) throw OnboardingAnswersIncomplete(missing!);
    if (infeasible != null) throw OnboardingPlanInfeasible(infeasible!);
    return _next() ?? _running;
  }

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
