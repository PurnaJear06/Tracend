import 'dart:io';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/account_screen.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/coach_screen.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';
import 'package:tracend/features/consent/ai_coaching_consent.dart';
import 'package:tracend/features/today/check_in_queue.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';

class _Memory implements CoachThreadMemory {
  @override
  Future<String?> lastThreadId() async => null;

  @override
  Future<void> remember(String threadId) async {}
}

/// Coach backend whose thread creation and decision load wait for [gate],
/// so a test can change the AI coaching answer mid-request.
class _GatedCoach implements CoachRepository, CoachChatRepository {
  Completer<void>? gate;
  int sent = 0;
  int generated = 0;

  Future<void> _wait() async {
    final pending = gate;
    if (pending != null) await pending.future;
  }

  @override
  Future<List<CoachThread>> loadThreads() async => const [];

  @override
  Future<String> createThread() async {
    await _wait();
    return 'thread-1';
  }

  @override
  Future<List<CoachMessage>> loadMessages(String threadId) async => const [];

  @override
  Future<CoachMessage> sendMessage(
    String threadId,
    String question, {
    String? idempotencyKey,
  }) async {
    sent++;
    return CoachMessage(
      id: 'answer',
      role: 'assistant',
      content: 'Answer.',
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> deleteThread(String threadId) async {}

  @override
  Future<CoachDecision?> loadLatest() async {
    await _wait();
    return null;
  }

  @override
  Future<CoachDecision> generate() async {
    generated++;
    throw StateError('not needed');
  }

  @override
  Future<Map<String, dynamic>> loadUsage() async => const {};
}

class _EmptyBrief implements DailyBriefRepository {
  @override
  Future<DailyBrief> load(DateTime date) async =>
      DailyBrief(localDate: date.toIso8601String().substring(0, 10));
}

Widget _app(Widget home) => MaterialApp(theme: TracendTheme.dark, home: home);

Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// A notice as the server publishes it: it names the company once.
const _anthropicNotice = AiNotice(
  version: 'ai-coaching-v6',
  providerLabel: 'Anthropic',
  body:
      'Tracend sends Anthropic your coaching data.\n\n'
      'It keeps it 30 days.\n\n'
      'You can change this in Account.',
);

void main() {
  const current = 'ai-coaching-v6';

  group('aiCoachingChoiceFrom', () {
    test('no record means the athlete has not answered', () {
      expect(
        aiCoachingChoiceFrom(null, currentVersion: current),
        AiCoachingChoice.undecided,
      );
    });

    test('a grant of the current notice counts', () {
      expect(
        aiCoachingChoiceFrom({
          'action': 'granted',
          'notice_version': current,
        }, currentVersion: current),
        AiCoachingChoice.granted,
      );
    });

    test('a grant of an older notice asks again', () {
      expect(
        aiCoachingChoiceFrom({
          'action': 'granted',
          'notice_version': 'ai-coaching-v0',
        }, currentVersion: current),
        AiCoachingChoice.undecided,
      );
    });

    test('a grant counts only for the notice the server says is current', () {
      final latest = {'action': 'granted', 'notice_version': 'ai-coaching-v1'};
      expect(
        aiCoachingChoiceFrom(latest, currentVersion: 'ai-coaching-v1'),
        AiCoachingChoice.granted,
      );
      expect(
        aiCoachingChoiceFrom(latest, currentVersion: 'ai-coaching-v2'),
        AiCoachingChoice.undecided,
      );
    });

    test('a withdrawal is a decline, whatever its version', () {
      expect(
        aiCoachingChoiceFrom({
          'action': 'withdrawn',
          'notice_version': 'ai-coaching-v0',
        }, currentVersion: current),
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

    expect(find.textContaining('This is a test notice'), findsOneWidget);
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
      _anthropicNotice,
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
    // The company is named in the notice only (D11), not on this card.
    expect(find.textContaining('Anthropic'), findsNothing);

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

    final row = find.text('On · AI writes Coach answers');
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
    expect(find.text('Off · plans and logging still work'), findsOneWidget);
  });

  testWidgets('turning AI coaching off mid-send sends nothing to the Coach', (
    tester,
  ) async {
    await _tall(tester);
    final consent = AiCoachingConsentController(
      FixtureAiCoachingConsentRepository(AiCoachingChoice.granted),
      initial: AiCoachingChoice.granted,
    );
    final coach = _GatedCoach();
    await tester.pumpWidget(
      _app(
        CoachScreen(
          repository: coach,
          threadMemory: _Memory(),
          aiConsent: consent,
        ),
      ),
    );
    await tester.pumpAndSettle();

    coach.gate = Completer<void>();
    await tester.enterText(find.byType(TextField), 'How was my week?');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();
    await consent.record(granted: false);
    coach.gate!.complete();
    await tester.pumpAndSettle();

    expect(coach.sent, 0);
    expect(find.text('AI coaching is off'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'How was my week?',
    );
  });

  testWidgets('turning AI coaching off mid-load generates no decision', (
    tester,
  ) async {
    await _tall(tester);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final consent = AiCoachingConsentController(
      FixtureAiCoachingConsentRepository(),
    );
    final coach = _GatedCoach();
    await tester.pumpWidget(
      _app(
        TodayScreen(
          environment: const AppEnvironment(
            name: 'test',
            supabaseUrl: 'https://example.supabase.co',
            supabasePublishableKey: 'sb_publishable_test',
          ),
          coach: coach,
          brief: _EmptyBrief(),
          queueFactory: () => CheckInQueue(preferences),
          checkInSender: (localDate, timezone, key, payload) async => true,
          aiConsent: consent,
        ),
      ),
    );
    // Bounded pumps: the NOW-dot pulse never settles.
    await tester.pump(const Duration(seconds: 1));

    coach.gate = Completer<void>();
    await consent.record(granted: true);
    await tester.pump();
    await consent.record(granted: false);
    coach.gate!.complete();
    await tester.pump(const Duration(seconds: 1));
    expect(coach.generated, 0);

    // Control: with AI coaching left on, the same load does generate.
    await consent.record(granted: true);
    await tester.pump(const Duration(seconds: 1));
    expect(coach.generated, 1);
  });

  group('AiNotice', () {
    test('reads the server notice and splits its paragraphs', () {
      final notice = AiNotice.fromJson({
        'schema_version': '1.0',
        'version': 'ai-coaching-v2',
        'provider_label': 'DeepSeek',
        'body': 'One.\n\nTwo.\n \nThree.',
        'purposes': ['onboarding_plan'],
      });
      expect(notice?.version, 'ai-coaching-v2');
      expect(notice?.paragraphs, ['One.', 'Two.', 'Three.']);
    });

    test('anything that is not a notice falls back to none', () {
      expect(AiNotice.fromJson(null), isNull);
      expect(AiNotice.fromJson({'version': 'v'}), isNull);
      expect(
        AiNotice.fromJson({'version': '', 'provider_label': 'X', 'body': 'B'}),
        isNull,
      );
    });

    test('the notice drafts name one company and no model (D11)', () {
      final models = RegExp(
        r'deepseek|groq|qwen|gemini|claude|haiku|sonnet|opus|openai|china',
        caseSensitive: false,
      );
      for (final name in [
        'ai-coaching-v6',
        'meal-photo-ai-v2',
        'progress-photo-ai-v2',
      ]) {
        final draft = File('docs/notices/$name.md').readAsStringSync();
        final body = RegExp(
          r'\$notice\$(.*)\$notice\$',
          dotAll: true,
        ).firstMatch(draft)!.group(1)!;
        expect(
          RegExp('Anthropic').allMatches(body),
          hasLength(1),
          reason: name,
        );
        expect(models.hasMatch(body), isFalse, reason: name);
        expect(body.length, lessThanOrEqualTo(4000), reason: name);
      }
    });
  });

  group('a notice that cannot be loaded', () {
    test('the app has no text of its own: a failed call is unavailable', () {
      expect(
        loadCurrentAiNotice(() async => throw StateError('offline')),
        throwsA(isA<AiNoticeUnavailable>()),
      );
      expect(
        loadCurrentAiNotice(() async => null),
        throwsA(isA<AiNoticeUnavailable>()),
      );
      expect(
        loadCurrentAiNotice(() async => {'version': 'v'}),
        throwsA(isA<AiNoticeUnavailable>()),
      );
    });

    test('a server notice loads as given', () async {
      final notice = await loadCurrentAiNotice(
        () async => {
          'version': 'ai-coaching-v6',
          'provider_label': 'Anthropic',
          'body': 'One.',
        },
      );
      expect(notice.version, 'ai-coaching-v6');
    });

    test('loading and answering refuse without a notice', () async {
      final controller = AiCoachingConsentController(
        FixtureAiCoachingConsentRepository(AiCoachingChoice.undecided, null),
      );
      // Loading is not an error: AI coaching is unavailable, nothing assumed.
      await controller.load();
      expect(controller.notice, isNull);
      expect(controller.granted, isFalse);
      await expectLater(
        controller.record(granted: true),
        throwsA(isA<AiNoticeUnavailable>()),
      );
      expect(controller.choice, AiCoachingChoice.undecided);
    });

    test('the Supabase repository never records for a notice it lacks', () {
      final repository = SupabaseAiCoachingConsentRepository(
        SupabaseClient('http://localhost:54321', 'test-key'),
      );
      expect(repository.notice, isNull);
      expect(
        repository.record(granted: true),
        throwsA(isA<AiNoticeUnavailable>()),
      );
    });

    testWidgets('the question shows an error and a retry, no answer buttons', (
      tester,
    ) async {
      await _tall(tester);
      final repository = FixtureAiCoachingConsentRepository(
        AiCoachingChoice.undecided,
        null,
      );
      final controller = AiCoachingConsentController(repository);
      await tester.pumpWidget(
        _app(AiCoachingConsentScreen(controller: controller, onDecided: () {})),
      );

      expect(find.textContaining('could not be loaded'), findsOneWidget);
      expect(find.text('Allow AI coaching'), findsNothing);
      expect(find.text('Not now'), findsNothing);

      // The server answers on the next try: the notice and the buttons appear.
      repository.notice = _anthropicNotice;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tracend sends Anthropic'), findsOneWidget);
      await tester.tap(find.text('Allow AI coaching'));
      await tester.pumpAndSettle();
      expect(repository.recorded, [true]);
    });

    testWidgets('the Coach entry opens a sheet that retries, then asks', (
      tester,
    ) async {
      await _tall(tester);
      final repository = FixtureAiCoachingConsentRepository(
        AiCoachingChoice.undecided,
        null,
      );
      final consent = AiCoachingConsentController(repository);
      await tester.pumpWidget(
        _app(CoachScreen(threadMemory: _Memory(), aiConsent: consent)),
      );
      await tester.pumpAndSettle();
      expect(find.text('AI coaching is off'), findsOneWidget);

      await tester.tap(find.text('Review AI coaching'));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be loaded'), findsOneWidget);
      expect(find.text('Allow AI coaching'), findsNothing);
      expect(find.text('Not now'), findsNothing);

      // A failed retry keeps the error; a later one shows the notice.
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be loaded'), findsOneWidget);
      expect(repository.recorded, isEmpty);

      repository.notice = _anthropicNotice;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tracend sends Anthropic'), findsOneWidget);
      expect(find.text('Allow AI coaching'), findsOneWidget);
    });

    testWidgets('the Account entry retries the same way', (tester) async {
      await _tall(tester);
      final repository = FixtureAiCoachingConsentRepository(
        AiCoachingChoice.undecided,
        null,
      );
      final consent = AiCoachingConsentController(repository);
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showAiCoachingConsentSheet(context, consent),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be loaded'), findsOneWidget);
      expect(find.text('Allow AI coaching'), findsNothing);

      repository.notice = _anthropicNotice;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tracend sends Anthropic'), findsOneWidget);
    });
  });
}
