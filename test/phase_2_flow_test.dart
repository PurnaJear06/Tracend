import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/auth/owner_auth_screen.dart';
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

  testWidgets('beginner completes proposal approval flow', (tester) async {
    final repository = _FakeOnboardingRepository();
    var completed = false;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: OnboardingFlow(
          repository: repository,
          onCompleted: () => completed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapText(tester, 'I am 18 or older');
    await _tapText(tester, 'I accept the private-beta terms');
    await _tapText(tester, 'I have read the privacy notice');
    await _continue(tester);

    await _tapText(tester, 'Guide me');
    await _continue(tester);
    expect(find.text('What should the plan prioritize?'), findsOneWidget);
    await _continue(tester);
    expect(find.text('Make the proposal practical.'), findsOneWidget);
    await _continue(tester);
    expect(find.text('Review before generation.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Build proposal'));
    await tester.pumpAndSettle();
    expect(find.text('Your proposed starting plan.'), findsOneWidget);
    expect(find.textContaining('Nothing becomes active'), findsNothing);

    final approve = find.widgetWithText(FilledButton, 'Approve plan');
    await tester.ensureVisible(approve);
    await tester.pumpAndSettle();
    await tester.tap(approve);
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(repository.lastResponse, 'accept');
    expect(repository.savedPath, 'beginner');
  });

  testWidgets('experienced draft restores the preserve path', (tester) async {
    final repository = _FakeOnboardingRepository(
      draft: const OnboardingDraft(
        path: 'experienced',
        currentSection: 'goal',
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

    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: OnboardingFlow(repository: repository, onCompleted: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Section 3 of 6'), findsOneWidget);
    expect(find.text('Strength'), findsOneWidget);
    await _continue(tester);
    expect(find.text('Current plan and what works *'), findsOneWidget);
  });
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
  _FakeOnboardingRepository({this.draft});

  final OnboardingDraft? draft;
  String? savedPath;
  String? lastResponse;

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
    savedPath = path;
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
  Future<OnboardingProposal> generateProposal() async =>
      const OnboardingProposal(
        id: 'proposal-1',
        training: {
          'title': 'Foundation Block',
          'block_weeks': 6,
          'weekly_structure': ['Full body A', 'Full body B', 'Full body C'],
        },
        nutrition: {
          'calories': 2250,
          'protein_g': 150,
          'carbohydrate_g': 255,
          'fat_g': 70,
        },
        rationale: 'Create a measurable baseline.',
        benefit: 'Repeatable execution.',
        downside: 'Initial estimates require review.',
        confidence: 'medium',
      );

  @override
  Future<OnboardingProposal> loadProposal(String proposalId) async =>
      generateProposal();

  @override
  Future<void> respond(String proposalId, String action) async {
    lastResponse = action;
  }
}
