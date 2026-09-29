import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/widgets/coach_message_bubble.dart';
import 'package:tracend/features/coach/widgets/coach_reply_text.dart';

void main() {
  group('parseCoachInline', () {
    test('bold, italic and code lose their markers', () {
      expect(parseCoachInline('Hit **150 g** of protein, *not* `less`.'), [
        const CoachReplySpan('Hit '),
        const CoachReplySpan('150 g', bold: true),
        const CoachReplySpan(' of protein, '),
        const CoachReplySpan('not', italic: true),
        const CoachReplySpan(' '),
        const CoachReplySpan('less', code: true),
        const CoachReplySpan('.'),
      ]);
    });

    test('underscore emphasis works but snake_case stays literal', () {
      expect(parseCoachInline('__Rest__ today, _easy_ tomorrow'), [
        const CoachReplySpan('Rest', bold: true),
        const CoachReplySpan(' today, '),
        const CoachReplySpan('easy', italic: true),
        const CoachReplySpan(' tomorrow'),
      ]);
      expect(parseCoachInline('recovery_check_in is missing'), [
        const CoachReplySpan('recovery_check_in is missing'),
      ]);
    });

    test('arithmetic and unmatched markers stay as typed', () {
      expect(parseCoachInline('3 * 4 sets, then 2*5 reps'), [
        const CoachReplySpan('3 * 4 sets, then 2*5 reps'),
      ]);
      expect(parseCoachInline('**Protein first'), [
        const CoachReplySpan('**Protein first'),
      ]);
    });

    test('italic inside bold keeps both styles', () {
      expect(parseCoachInline('**Keep *every* set**'), [
        const CoachReplySpan('Keep ', bold: true),
        const CoachReplySpan('every', bold: true, italic: true),
        const CoachReplySpan(' set', bold: true),
      ]);
    });

    test('a link keeps its destination after the label', () {
      expect(parseCoachInline('See [your plan](https://example.com) today'), [
        const CoachReplySpan('See '),
        const CoachReplySpan('your plan'),
        const CoachReplySpan(' (https://example.com)'),
        const CoachReplySpan(' today'),
      ]);
    });

    test('a link labelled with its own address shows it once', () {
      expect(parseCoachInline('[https://example.com](https://example.com)'), [
        const CoachReplySpan('https://example.com'),
      ]);
    });
  });

  group('parseCoachReply', () {
    test('reads headings, paragraphs and nested lists', () {
      final blocks = parseCoachReply(
        '### Plan\n'
        'Today is **Legs A**.\n'
        '\n'
        '- Squat 4×6\n'
        '* Rest\n'
        '  - 90 s between sets\n'
        '1. Warm up\n'
        '2) Lift\n'
        '\n'
        '---\n'
        'Done.',
      );
      expect(blocks.map((block) => block.kind), [
        CoachReplyBlockKind.heading,
        CoachReplyBlockKind.paragraph,
        CoachReplyBlockKind.bullet,
        CoachReplyBlockKind.bullet,
        CoachReplyBlockKind.bullet,
        CoachReplyBlockKind.numbered,
        CoachReplyBlockKind.numbered,
        CoachReplyBlockKind.paragraph,
      ]);
      expect(blocks[0].spans, [const CoachReplySpan('Plan', bold: true)]);
      expect(blocks[2].marker, '•');
      expect(blocks[4].depth, 1);
      expect(blocks[6].marker, '2.');
      expect(blocks[7].spans, [const CoachReplySpan('Done.')]);
    });

    test('a line that opens with emphasis is not a list item', () {
      final blocks = parseCoachReply('*Note:* sleep was not measured');
      expect(blocks.single.kind, CoachReplyBlockKind.paragraph);
      expect(
        blocks.single.spans.first,
        const CoachReplySpan('Note:', italic: true),
      );
    });

    test('single line breaks stay inside one paragraph', () {
      final blocks = parseCoachReply('First line\nsecond line');
      expect(blocks.single.spans, [
        const CoachReplySpan('First line\nsecond line'),
      ]);
    });
  });

  Widget bubble(CoachMessage message) => MaterialApp(
    theme: TracendTheme.dark,
    home: Scaffold(
      body: SingleChildScrollView(child: CoachMessageBubble(message: message)),
    ),
  );

  testWidgets('a Coach reply shows formatting instead of Markdown markers', (
    tester,
  ) async {
    await tester.pumpWidget(
      bubble(
        CoachMessage(
          id: 'reply',
          role: 'assistant',
          content: '**Deload** this week:\n- Cut sets by *half*',
          createdAt: DateTime(2026, 9, 29),
        ),
      ),
    );

    expect(find.textContaining('*'), findsNothing);
    expect(find.text('•'), findsOneWidget);
    final heading = tester.widget<Text>(find.textContaining('Deload'));
    final bold = (heading.textSpan! as TextSpan).children!.first as TextSpan;
    expect(bold.text, 'Deload');
    expect(bold.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('the athlete\'s own message keeps its asterisks', (tester) async {
    await tester.pumpWidget(
      bubble(
        CoachMessage(
          id: 'question',
          role: 'user',
          content: 'Is **5 sets** too much?',
          createdAt: DateTime(2026, 9, 29),
        ),
      ),
    );

    expect(find.text('Is **5 sets** too much?'), findsOneWidget);
  });
}
