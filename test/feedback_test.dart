import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/account_screen.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/widgets/coach_message_bubble.dart';
import 'package:tracend/features/feedback/feedback_mail.dart';
import 'package:tracend/features/feedback/feedback_rating.dart';
import 'package:tracend/shared/beta_diagnostic.dart';

import 'feedback_fakes.dart';

const _offline = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

Widget _app(Widget child) => MaterialApp(
  theme: TracendTheme.dark,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

CoachMessage _reply({String id = 'm1'}) => CoachMessage(
  id: id,
  role: 'assistant',
  content: 'Keep the plan and add a rest day.',
  createdAt: DateTime(2026, 11, 2),
  answerSource: 'model',
);

void main() {
  setUp(() => LatestBetaDiagnostic.code = null);

  group('the feedback email', () {
    test('goes to the support address with a subject and the app details', () {
      final uri = feedbackMailUri(
        version: (version: '1.1.0', build: '920'),
        diagnosticCode: 'HTTP 502',
      );

      expect(uri.scheme, 'mailto');
      expect(uri.path, supportEmail);
      expect(uri.queryParameters['subject'], 'Tracend beta feedback');
      final body = uri.queryParameters['body']!;
      expect(body, contains('Tracend 1.1.0 (920)'));
      expect(body, contains('Last problem code: HTTP 502'));
      expect(body.split('\n').first, isEmpty, reason: 'room to write first');
    });

    test('holds no email address and no account id', () {
      final body = feedbackMailUri(
        version: (version: '1.1.0', build: '920'),
        diagnosticCode: 'provider_response_invalid',
      ).queryParameters['body']!;

      expect(body.contains('@'), isFalse);
      expect(
        RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}-').hasMatch(body),
        isFalse,
        reason: 'no uuid',
      );
    });

    test('encodes spaces as %20, which mail apps show as written', () {
      final uri = feedbackMailUri(version: (version: '1.1.0', build: '920'));

      expect(uri.toString(), isNot(contains('+')));
      expect(uri.toString(), contains('Tracend%20beta%20feedback'));
    });

    test('leaves out what is not known', () {
      final body = feedbackMailUri().queryParameters['body']!;

      expect(body, isNot(contains('Tracend 1')));
      expect(body, isNot(contains('Last problem code')));
    });

    testWidgets('opens the mail composer and shows nothing else', (
      tester,
    ) async {
      LatestBetaDiagnostic.code = 'HTTP 502';
      Uri? opened;
      late BuildContext context;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );

      await sendFeedback(
        context,
        launch: (uri) async {
          opened = uri;
          return true;
        },
        readVersion: () async => (version: '1.1.0', build: '920'),
      );
      await tester.pumpAndSettle();

      expect(opened!.queryParameters['body'], contains('HTTP 502'));
      expect(find.text('Send feedback'), findsNothing);
    });

    testWidgets('without a mail app it shows the address to copy', (
      tester,
    ) async {
      LatestBetaDiagnostic.code = 'HTTP 502';
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      late BuildContext context;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );

      unawaited(
        sendFeedback(
          context,
          launch: (_) async => false,
          readVersion: () async => (version: '1.1.0', build: '920'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Send feedback'), findsOneWidget);
      expect(find.byType(SelectableText), findsWidgets);
      expect(find.text(supportEmail), findsOneWidget);
      expect(find.textContaining('Tracend 1.1.0 (920)'), findsOneWidget);
      expect(
        find.textContaining('Last problem code: HTTP 502'),
        findsOneWidget,
      );
      await tester.tap(find.text('Copy address'));
      await tester.pumpAndSettle();
      expect(copied, supportEmail);
    });

    testWidgets('Account has a Send feedback row that opens it', (
      tester,
    ) async {
      LatestBetaDiagnostic.code = 'HTTP 502';
      Uri? opened;
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: AccountScreen(
            environment: _offline,
            mailLauncher: (uri) async {
              opened = uri;
              return true;
            },
            versionReader: () async => (version: '1.1.0', build: '920'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Send feedback'), 200);
      await tester.tap(find.text('Send feedback'));
      await tester.pumpAndSettle();

      expect(opened, isNotNull);
      expect(opened!.path, supportEmail);
      expect(opened!.queryParameters['body'], contains('HTTP 502'));
    });
  });

  group('the latest beta diagnostic code', () {
    test('is the code in front of the detail', () {
      expect(betaDiagnosticCode('Beta diagnostic: HTTP 502'), 'HTTP 502');
      expect(
        betaDiagnosticCode(
          'Beta diagnostic: provider_response_invalid · first attempt: rule_a · repair: rule_b',
        ),
        'provider_response_invalid',
      );
      expect(
        betaDiagnosticCode('Beta diagnostic · analyze: vision_failed'),
        'analyze: vision_failed',
      );
      expect(betaDiagnosticCode('Beta diagnostic: '), isNull);
    });

    test('is set when a failure produces a diagnostic', () {
      LatestBetaDiagnostic.note('Beta diagnostic: HTTP 429 · busy');
      expect(LatestBetaDiagnostic.code, 'HTTP 429');

      LatestBetaDiagnostic.note(null);
      LatestBetaDiagnostic.note('Beta diagnostic: ');
      expect(LatestBetaDiagnostic.code, 'HTTP 429', reason: 'nothing to note');
    });

    testWidgets('a line drawn again never replaces a newer failure', (
      tester,
    ) async {
      LatestBetaDiagnostic.note('Beta diagnostic: HTTP 502');

      await tester.pumpWidget(
        _app(const CoachDiagnosticLine('Beta diagnostic: HTTP 429 · busy')),
      );

      expect(find.text('Beta diagnostic: HTTP 429 · busy'), findsOneWidget);
      expect(LatestBetaDiagnostic.code, 'HTTP 502');
    });

    testWidgets('a load error is remembered when its line first appears', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const BetaDiagnosticMark(code: 'StateError', child: Text('x'))),
      );

      expect(LatestBetaDiagnostic.code, 'StateError');
    });
  });

  group('the rating row', () {
    Future<FakeFeedbackRatings> open(
      WidgetTester tester, {
      Map<String, FeedbackRating> stored = const {},
    }) async {
      final ratings = FakeFeedbackRatings(stored: stored);
      await tester.pumpWidget(
        _app(
          FeedbackRatingBar(
            repository: ratings,
            subject: FeedbackSubject.coachReply,
            subjectId: 'm1',
          ),
        ),
      );
      await tester.pumpAndSettle();
      return ratings;
    }

    testWidgets('offers the four answers, each a 44pt target', (tester) async {
      await open(tester);

      for (final label in ['Useful', 'Unclear', 'Incorrect', 'Unsafe']) {
        expect(find.text(label), findsOneWidget);
        final size = tester.getSize(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(ConstrainedBox),
              )
              .first,
        );
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
        expect(size.width, greaterThanOrEqualTo(44), reason: label);
      }
    });

    testWidgets('each answer has a screen reader label and a selected state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester, stored: {'m1': FeedbackRating.unclear});

      expect(find.bySemanticsLabel('Rate this reply useful'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Rate this reply unclear')),
        matchesSemantics(
          label: 'Rate this reply unclear',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
          hasEnabledState: false,
        ),
      );
      handle.dispose();
    });

    testWidgets('shows the rating given before and saves a tap', (
      tester,
    ) async {
      final ratings = await open(tester);

      await tester.tap(find.text('Incorrect'));
      await tester.pumpAndSettle();

      expect(ratings.saved, [
        (FeedbackSubject.coachReply, 'm1', FeedbackRating.incorrect),
      ]);
      expect(find.textContaining('Thanks'), findsOneWidget);
    });

    testWidgets('a second tap replaces the rating', (tester) async {
      final ratings = await open(tester, stored: {'m1': FeedbackRating.useful});
      expect(find.textContaining('Thanks'), findsOneWidget);

      await tester.tap(find.text('Unsafe'));
      await tester.pumpAndSettle();

      expect(ratings.stored['m1'], FeedbackRating.unsafe);
    });

    testWidgets('shows the choice at once, before the save finishes', (
      tester,
    ) async {
      final ratings = FakeFeedbackRatings()..hold = Completer<void>();
      await tester.pumpWidget(
        _app(
          FeedbackRatingBar(
            repository: ratings,
            subject: FeedbackSubject.dailyDecision,
            subjectId: 'd1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Unclear'));
      await tester.pump();

      expect(find.textContaining('Thanks'), findsOneWidget);
      ratings.hold!.complete();
      await tester.pumpAndSettle();
      expect(ratings.stored['d1'], FeedbackRating.unclear);
    });

    testWidgets('ignores taps while a rating is being saved', (tester) async {
      final ratings = FakeFeedbackRatings()..hold = Completer<void>();
      await tester.pumpWidget(
        _app(
          FeedbackRatingBar(
            repository: ratings,
            subject: FeedbackSubject.coachReply,
            subjectId: 'm1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Unclear'));
      await tester.pump();
      await tester.tap(find.text('Unsafe'));
      await tester.pump();
      ratings.hold!.complete();
      await tester.pumpAndSettle();

      expect(ratings.saved, [
        (FeedbackSubject.coachReply, 'm1', FeedbackRating.unclear),
      ]);
      expect(ratings.stored['m1'], FeedbackRating.unclear);

      await tester.tap(find.text('Unsafe'));
      await tester.pumpAndSettle();
      expect(ratings.stored['m1'], FeedbackRating.unsafe);
    });

    testWidgets('takes the choice back and says so when it did not save', (
      tester,
    ) async {
      final ratings = await open(tester);
      ratings.failure = true;

      await tester.tap(find.text('Useful'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Could not save your rating. Check your connection and tap again.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Thanks'), findsNothing);
      expect(ratings.stored, isEmpty);

      ratings.failure = false;
      await tester.tap(find.text('Useful'));
      await tester.pumpAndSettle();
      expect(ratings.stored['m1'], FeedbackRating.useful);
      expect(find.textContaining('Could not save'), findsNothing);
    });
  });

  group('under a Coach reply', () {
    testWidgets('the rating row shows when ratings can be saved', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          CoachMessageBubble(
            message: _reply(),
            feedback: FakeFeedbackRatings(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Useful'), findsOneWidget);
    });

    testWidgets('there is no rating row without a backend', (tester) async {
      await tester.pumpWidget(_app(CoachMessageBubble(message: _reply())));

      expect(find.text('Useful'), findsNothing);
    });

    testWidgets('a message the app named itself is not rated', (tester) async {
      await tester.pumpWidget(
        _app(
          CoachMessageBubble(
            message: CoachMessage.fromJson(
              {
                'role': 'assistant',
                'answer': 'Keep the plan.',
                'created_at': '2026-11-02T08:00:00Z',
              },
              fallbackId: 'local-id',
              fallbackCreatedAt: DateTime(2026, 11, 2),
            ),
            feedback: FakeFeedbackRatings(),
          ),
        ),
      );

      expect(find.text('Keep the plan.'), findsOneWidget);
      expect(find.text('Useful'), findsNothing);
    });

    testWidgets('your own message is not rated', (tester) async {
      await tester.pumpWidget(
        _app(
          CoachMessageBubble(
            message: CoachMessage(
              id: 'u1',
              role: 'user',
              content: 'Should I rest?',
              createdAt: DateTime(2026, 11, 2),
            ),
            feedback: FakeFeedbackRatings(),
          ),
        ),
      );

      expect(find.text('Useful'), findsNothing);
    });
  });
}
