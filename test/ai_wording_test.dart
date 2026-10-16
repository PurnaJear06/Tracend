import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/coach/coach_labels.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/widgets/coach_message_bubble.dart';
import 'package:tracend/features/onboarding/onboarding_proposal_view.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/features/progress/widgets/photo_widgets.dart';

/// D11: no model or company name in text the athlete reads outside an AI
/// consent notice. Old servers and old rows still carry provider ids and
/// labels; none of them reaches the screen.
final _names = RegExp(
  r'deepseek|groq|qwen|gemini|anthropic|claude|haiku|sonnet|opus|openai|'
  r'google|hangzhou|china|llama|mistral',
  caseSensitive: false,
);

String _allText(WidgetTester tester) => [
  ...tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data ?? text.textSpan?.toPlainText() ?? ''),
  ...tester
      .widgetList<RichText>(find.byType(RichText))
      .map((text) => text.text.toPlainText()),
].join('\n');

void _expectNoNames(WidgetTester tester) {
  final text = _allText(tester);
  expect(
    _names.allMatches(text).map((match) => match.group(0)).toList(),
    isEmpty,
    reason: text,
  );
}

Widget _app(Widget child) => MaterialApp(
  theme: TracendTheme.dark,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

CoachMessage _reply(String? provider, String? model) => CoachMessage(
  id: 'a1',
  role: 'assistant',
  content: 'Keep the plan and add a rest day.',
  createdAt: DateTime(2026, 10, 16),
  modelProvider: provider,
  model: model,
  answerSource: 'model',
);

void main() {
  group('Coach reply provenance', () {
    for (final (provider, model) in [
      ('deepseek', 'deepseek-flash'),
      ('groq', 'qwen/qwen3.8-27b'),
      ('gemini', 'gemini-3.5-flash'),
      ('anthropic', 'claude-haiku-5-5'),
      ('anthropic', 'claude-sonnet-5-5'),
    ]) {
      testWidgets('$provider / $model reads as an AI answer', (tester) async {
        await tester.pumpWidget(
          _app(CoachMessageBubble(message: _reply(provider, model))),
        );

        expect(find.text('AI answer · checked by Tracend'), findsOneWidget);
        _expectNoNames(tester);
      });
    }

    testWidgets('a reply with no stored provider shows no AI label', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(CoachMessageBubble(message: _reply(null, null))),
      );

      expect(find.textContaining('AI answer'), findsNothing);
      _expectNoNames(tester);
    });

    test('the label and the proposal line share one provenance phrase', () {
      expect(aiAnswerLabel(), endsWith(aiProvenanceLine));
      expect(
        OnboardingProposalView.provenanceLabel,
        endsWith(aiProvenanceLine),
      );
    });
  });

  group('progress photo card', () {
    final sets = [
      ProgressPhotoSet(
        id: 'set-1',
        date: DateTime(2026, 10, 10),
        status: 'complete',
        objectKeys: const ['a', 'b', 'c', 'd'],
      ),
    ];

    for (final available in [true, false]) {
      testWidgets('physique check available: $available', (tester) async {
        await tester.pumpWidget(
          _app(
            PhotoProgressCard(
              photoSets: sets,
              inProgress: false,
              onCapture: () {},
              onOpenSets: () {},
              physiqueCheckAvailable: available,
              onPhysiqueCheck: available ? () {} : null,
              now: DateTime(2026, 10, 16),
            ),
          ),
        );

        expect(
          find.text(
            available
                ? 'Only you can see these. Sent to AI only when you start a '
                      'physique check.'
                : 'Only you can see these. Never sent to AI.',
          ),
          findsOneWidget,
        );
        _expectNoNames(tester);
      });
    }
  });
}
