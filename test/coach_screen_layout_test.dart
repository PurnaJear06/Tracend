import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/coach_screen.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';
import 'package:tracend/features/coach/widgets/coach_context_card.dart';
import 'package:tracend/features/coach/widgets/coach_message_bubble.dart';
import 'package:tracend/features/coach/widgets/coach_thinking_indicator.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

final _when = DateTime(2026, 10, 2, 8);

/// A conversation with every kind of turn: a model answer with evidence,
/// gaps, reasoning and follow-ups, then a data summary with a diagnostic.
final _conversation = [
  CoachMessage(
    id: 'u1',
    role: 'user',
    content: 'Should I train legs today after a short night of sleep?',
    createdAt: _when,
  ),
  CoachMessage(
    id: 'a1',
    role: 'assistant',
    content:
        '**Keep today’s session**, but drop the last set of squats.\n'
        '- Recovery is within your usual range\n'
        '- Sleep was short, so keep effort at RPE 7',
    createdAt: _when,
    modelProvider: 'deepseek',
    model: 'deepseek-flash',
    answerSource: 'model',
    evidence: const [
      {
        'code': 'RECOVERY_WITHIN_BASELINE',
        'label': 'Recovery is within your usual range',
        'source': 'feature_snapshot',
      },
    ],
    missingData: const ['recovery_check_in', 'resp_rate'],
    reasoningChain: const [
      {
        'step': 'recovery_status',
        'value': 'HRV is near your 28-day baseline.',
        'evidence_id': 'RECOVERY_WITHIN_BASELINE',
      },
      {
        'step': 'conclusion',
        'value': 'Train as planned with one set less.',
        'evidence_id': null,
      },
    ],
    suggestedFollowUps: const ['What should I eat before training?'],
  ),
  CoachMessage(
    id: 'u2',
    role: 'user',
    content: 'And my weight trend?',
    createdAt: _when,
  ),
  CoachMessage(
    id: 's1',
    role: 'assistant',
    content: 'Here is what your data shows.',
    createdAt: _when,
    modelProvider: 'deterministic',
    answerSource: 'data_summary',
    evidence: const [
      {
        'code': 'APPROVED_PLAN_ACTIVE',
        'label': 'Approved plan active',
        'source': 'coach_context',
      },
    ],
    diagnostic: const CoachChatDiagnostic(
      failureCode: 'provider_response_invalid',
      initialRule: 'evidence_code_not_permitted',
    ),
  ),
];

Widget _app(CoachRepository repository, {bool dark = true}) => MaterialApp(
  theme: dark ? TracendTheme.dark : TracendTheme.light,
  home: Scaffold(
    body: CoachScreen(repository: repository, threadMemory: _Memory()),
  ),
);

void _narrow(WidgetTester tester, double scale) {
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
}

/// Scrolls the conversation from top to bottom, failing on any layout
/// exception on the way.
Future<void> _scrollThrough(WidgetTester tester, String context) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 30; i++) {
    expect(tester.takeException(), isNull, reason: '$context, step $i');
    final position = tester.state<ScrollableState>(scrollable).position;
    if (position.pixels >= position.maxScrollExtent) break;
    await tester.drag(scrollable, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  expect(tester.takeException(), isNull, reason: context);
}

void main() {
  for (final dark in [true, false]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets('a full conversation lays out at 320pt × 2 text ($theme)', (
      tester,
    ) async {
      _narrow(tester, 2);
      await tester.pumpWidget(
        _app(_Repository(messages: _conversation), dark: dark),
      );
      await tester.pumpAndSettle();
      await _scrollThrough(tester, 'collapsed');

      // Open both disclosures, then walk the page again.
      for (final _ in [0, 1]) {
        final disclosure = find.text(CoachMessageBubble.evidenceTitle).last;
        await Scrollable.ensureVisible(
          tester.element(disclosure),
          alignment: 0.2,
        );
        await tester.pumpAndSettle();
        await tester.tap(disclosure);
        await tester.pumpAndSettle();
      }
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 6000));
      await tester.pumpAndSettle();
      await _scrollThrough(tester, 'expanded');
    });

    testWidgets('a new conversation, a failed turn and the thread sheet lay '
        'out at 320pt × 2 text ($theme)', (tester) async {
      _narrow(tester, 2);
      final repository = _Repository(
        reply: Exception(
          'FunctionException(status: 503, details: {code: provider_http_error})',
        ),
      );
      await tester.pumpWidget(_app(repository, dark: dark));
      await tester.pumpAndSettle();
      final card = find.text(CoachContextCard.title);
      await tester.scrollUntilVisible(
        card,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(tester.element(card), alignment: 0.2);
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pumpAndSettle();
      await _scrollThrough(tester, 'new conversation');

      await tester.enterText(find.byType(TextField), 'How was my week?');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(find.byType(CoachTurnError), findsOneWidget);
      await _scrollThrough(tester, 'failed turn');
      await tester.pumpAndSettle(TracendToast.visibleFor);

      await tester.tap(find.byTooltip('Saved conversations'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('New conversation'), findsOneWidget);
    });
  }

  testWidgets('the thinking dots move only at full motion', (tester) async {
    Future<void> pumpAt(TracendMotionLevel level) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: TracendMotionScope(
            level: level,
            child: const Scaffold(body: CoachThinkingIndicator()),
          ),
        ),
      );
    }

    await pumpAt(TracendMotionLevel.full);
    expect(tester.hasRunningAnimations, isTrue);
    expect(find.bySemanticsLabel('Coach is thinking'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await pumpAt(TracendMotionLevel.reduced);
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('Coach is thinking'), findsOneWidget);
  });

  testWidgets('the composer is a filled pill with a lime send button once '
      'there is something to send', (tester) async {
    _narrow(tester, 1);
    final repository = _Repository(reply: Completer<CoachMessage>());
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    final colors = TracendTheme.dark.extension<TracendColors>()!;
    Color sendFill() =>
        (tester
                    .widget<AnimatedContainer>(
                      find.ancestor(
                        of: find.byTooltip('Send message'),
                        matching: find.byType(AnimatedContainer),
                      ),
                    )
                    .decoration!
                as BoxDecoration)
            .color!;

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.border, isA<OutlineInputBorder>());
    expect(
      (field.decoration!.border! as OutlineInputBorder).borderRadius,
      const BorderRadius.all(Radius.circular(TracendRadii.pill)),
    );
    expect(sendFill(), colors.surfaceRaised);

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    expect(sendFill(), colors.accentSignal);
  });
}

class _Memory implements CoachThreadMemory {
  @override
  Future<String?> lastThreadId() async => null;

  @override
  Future<void> remember(String threadId) async {}
}

class _Repository
    implements CoachRepository, CoachChatRepository, CoachContextRepository {
  _Repository({this.messages = const [], this.reply});

  final List<CoachMessage> messages;
  final Object? reply;

  @override
  Future<List<CoachContextSource>> loadContextStatus() async => const [
    CoachContextSource(
      key: 'approved_plan',
      label: 'Approved training plan',
      available: true,
      records: 0,
    ),
    CoachContextSource(
      key: 'healthkit',
      label: 'Apple Health summaries',
      available: true,
      records: 38,
      latestDate: '2026-10-02',
    ),
    CoachContextSource(
      key: 'workouts',
      label: 'Completed Tracend workouts',
      available: false,
      records: 0,
    ),
  ];

  @override
  Future<List<CoachThread>> loadThreads() async => messages.isEmpty
      ? const []
      : [
          CoachThread(
            id: 't1',
            title: 'Should I train legs today after a short night of sleep?',
            updatedAt: _when,
          ),
        ];

  @override
  Future<String> createThread() async => 't2';

  @override
  Future<List<CoachMessage>> loadMessages(String threadId) async => messages;

  @override
  Future<CoachMessage> sendMessage(String threadId, String question) {
    final reply = this.reply;
    if (reply is Completer<CoachMessage>) return reply.future;
    if (reply is Exception) return Future.error(reply);
    return Future.error(StateError('no reply'));
  }

  @override
  Future<void> deleteThread(String threadId) async {}

  @override
  Future<CoachDecision?> loadLatest() async => null;

  @override
  Future<CoachDecision> generate() => throw StateError('not needed');

  @override
  Future<Map<String, dynamic>> loadUsage() async => const {};
}
