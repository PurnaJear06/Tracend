import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/account_screen.dart';
import 'package:tracend/features/coach/coach_screen.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';
import 'package:tracend/features/consent/ai_coaching_consent.dart';

class _Memory implements CoachThreadMemory {
  @override
  Future<String?> lastThreadId() async => null;

  @override
  Future<void> remember(String threadId) async {}
}

Widget _app(Widget home) => MaterialApp(theme: TracendTheme.dark, home: home);

Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('aiCoachingChoiceFrom', () {
    test('no record means the athlete has not answered', () {
      expect(aiCoachingChoiceFrom(null), AiCoachingChoice.undecided);
    });

    test('a grant of the current notice counts', () {
      expect(
        aiCoachingChoiceFrom({
          'action': 'granted',
          'notice_version': aiCoachingNoticeVersion,
        }),
        AiCoachingChoice.granted,
      );
    });

    test('a grant of an older notice asks again', () {
      expect(
        aiCoachingChoiceFrom({
          'action': 'granted',
          'notice_version': 'ai-coaching-v0',
        }),
        AiCoachingChoice.undecided,
      );
    });

    test('a withdrawal is a decline, whatever its version', () {
      expect(
        aiCoachingChoiceFrom({
          'action': 'withdrawn',
          'notice_version': 'ai-coaching-v0',
        }),
        AiCoachingChoice.declined,
      );
    });
  });

  test('the controller records the answer and notifies', () async {
    final repository = FixtureAiCoachingConsentRepository();
    final controller = AiCoachingConsentController(repository);
    var notified = 0;
    controller.addListener(() => notified++);

    await controller.load();
    expect(controller.choice, AiCoachingChoice.undecided);
    await controller.record(granted: true);
    expect(controller.granted, isTrue);
    await controller.record(granted: false);
    expect(controller.choice, AiCoachingChoice.declined);

    expect(repository.recorded, [true, false]);
    expect(notified, 3);
  });

  testWidgets('the full-screen question records Allow and moves on', (
    tester,
  ) async {
    await _tall(tester);
    final repository = FixtureAiCoachingConsentRepository();
    var decided = false;
    await tester.pumpWidget(
      _app(
        AiCoachingConsentScreen(
          controller: AiCoachingConsentController(repository),
          onDecided: () => decided = true,
        ),
      ),
    );

    expect(find.textContaining('Hangzhou DeepSeek'), findsOneWidget);
    await tester.tap(find.text('Allow AI coaching'));
    await tester.pumpAndSettle();

    expect(repository.recorded, [true]);
    expect(decided, isTrue);
  });

  testWidgets('Not now is recorded as a decline', (tester) async {
    await _tall(tester);
    final repository = FixtureAiCoachingConsentRepository();
    await tester.pumpWidget(
      _app(
        AiCoachingConsentScreen(
          controller: AiCoachingConsentController(repository),
          onDecided: () {},
        ),
      ),
    );

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(repository.recorded, [false]);
  });

  testWidgets('with AI coaching off, Coach explains and cannot send', (
    tester,
  ) async {
    await _tall(tester);
    final repository = FixtureAiCoachingConsentRepository(
      AiCoachingChoice.declined,
    );
    final consent = AiCoachingConsentController(
      repository,
      initial: AiCoachingChoice.declined,
    );
    await tester.pumpWidget(
      _app(CoachScreen(threadMemory: _Memory(), aiConsent: consent)),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI coaching is off'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

    await tester.tap(find.text('Review AI coaching'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow AI coaching'));
    await tester.pumpAndSettle();

    expect(repository.recorded, [true]);
    expect(find.text('AI coaching is off'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });

  testWidgets('Account shows the answer and can turn AI coaching off', (
    tester,
  ) async {
    await _tall(tester);
    final repository = FixtureAiCoachingConsentRepository(
      AiCoachingChoice.granted,
    );
    final consent = AiCoachingConsentController(
      repository,
      initial: AiCoachingChoice.granted,
    );
    await tester.pumpWidget(
      _app(
        AccountScreen(
          environment: const AppEnvironment(
            name: 'test',
            supabaseUrl: '',
            supabasePublishableKey: '',
          ),
          aiConsent: consent,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.text('On · DeepSeek writes Coach answers');
    await tester.scrollUntilVisible(
      row,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('Allow AI coaching'), findsNothing);
    await tester.tap(find.text('Turn off AI coaching'));
    await tester.pumpAndSettle();

    expect(repository.recorded, [false]);
    expect(find.text('Off'), findsOneWidget);
  });
}
