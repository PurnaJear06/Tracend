import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/sentry_scrubber.dart';
import 'package:tracend/shared/diagnostics.dart';

void main() {
  final hint = Hint();

  group('scrubText', () {
    test('removes the failing row a Postgres error carries', () {
      final error = PostgrestException(
        message: 'new row violates check constraint "weight_range"',
        code: '23514',
        details:
            'Failing row contains (3f2b8c1e-aaaa-4bbb-8ccc-1234567890ab, 400, 2026-10-31).',
        hint: 'check the value',
      );
      final text = scrubText(error.toString());
      expect(text, contains('23514'));
      expect(text, isNot(contains('3f2b8c1e')));
      expect(text, isNot(contains('400')));
      expect(text, isNot(contains('check the value')));
    });

    test('removes ids, emails, query strings and unit values', () {
      final text = scrubText(
        'user a@b.com 3f2b8c1e-aaaa-4bbb-8ccc-1234567890ab weighed 82.5 kg '
        'at https://x.supabase.co/rest/v1/m?weight_kg=eq.82&user=1 and 61 bpm',
      );
      expect(text, isNot(contains('a@b.com')));
      expect(text, isNot(contains('3f2b8c1e')));
      expect(text, isNot(contains('82.5')));
      expect(text, isNot(contains('61 bpm')));
      expect(text, contains('https://x.supabase.co/rest/v1/m'));
      expect(text, isNot(contains('weight_kg=eq')));
    });

    test('removes the value of a named measurement', () {
      expect(scrubText('{"weight_kg": 400, "ok": 1}'), isNot(contains('400')));
      expect(scrubText('meal_description: oats'), isNot(contains('oats')));
    });

    test('keeps a plain failure readable and cuts long text', () {
      expect(scrubText('Connection closed'), 'Connection closed');
      expect(scrubText('x' * 1000).length, lessThan(400));
    });
  });

  group('scrubEvent', () {
    test('scrubs exception values, extra, message and request data', () {
      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'PostgrestException',
            value: 'details: Failing row contains (a, 400)',
          ),
        ],
        // ignore: deprecated_member_use
        extra: {'weight_kg': 400, 'note': 'ate a lot', 'screen': 'progress'},
        message: SentryMessage('meal_content: oats and eggs'),
        request: SentryRequest(
          url: 'https://x.co/p?weight=1',
          data: {'prompt': 'hello', 'safe': 'value'},
        ),
      );
      final out = scrubEvent(event, hint)!;
      expect(out.exceptions!.single.value, isNot(contains('400')));
      // ignore: deprecated_member_use
      final extra = out.extra!;
      expect(extra['weight_kg'], redactedValue);
      expect(extra['note'], redactedValue);
      expect(extra['screen'], 'progress');
      expect(out.message!.formatted, isNot(contains('oats')));
      expect((out.request!.data as Map)['prompt'], redactedValue);
      expect((out.request!.data as Map)['safe'], 'value');
      expect(out.request!.url, 'https://x.co/p');
    });

    test('scrubs the breadcrumbs it carries and drops prints', () {
      final event = SentryEvent(
        breadcrumbs: [
          Breadcrumb(category: 'console', message: 'weight 400'),
          Breadcrumb(category: 'workout', message: 'started'),
          Breadcrumb(
            category: 'ui',
            message: 'food: rice',
            data: {'sleep_minutes': 400},
          ),
        ],
      );
      final out = scrubEvent(event, hint)!;
      expect(out.breadcrumbs!.map((c) => c.category), ['workout', 'ui']);
      expect(out.breadcrumbs!.last.message, isNot(contains('rice')));
      expect(out.breadcrumbs!.last.data!['sleep_minutes'], redactedValue);
    });

    test('scrubs contexts', () {
      final event = SentryEvent();
      event.contexts['custom'] = {'step_count': 9000, 'screen': 'today'};
      final out = scrubEvent(event, hint)!;
      final custom = out.contexts['custom'] as Map<String, dynamic>;
      expect(custom['step_count'], redactedValue);
      expect(custom['screen'], 'today');
    });
  });

  group('scrubBreadcrumb', () {
    test('drops console and print crumbs', () {
      expect(scrubBreadcrumb(Breadcrumb(category: 'console'), hint), isNull);
      expect(scrubBreadcrumb(Breadcrumb(category: 'print'), hint), isNull);
      expect(scrubBreadcrumb(null, hint), isNull);
    });

    test('reduces an HTTP crumb to method, status and address', () {
      final crumb = scrubBreadcrumb(
        Breadcrumb(
          type: 'http',
          category: 'http',
          data: {
            'url': 'https://x.co/rest/v1/m?weight_kg=eq.82',
            'method': 'POST',
            'status_code': 400,
            'request_body': '{"weight_kg":400}',
            'response_body': 'Failing row contains (400)',
          },
        ),
        hint,
      )!;
      expect(crumb.data!.keys.toSet(), {'url', 'method', 'status_code'});
      expect(crumb.data!['url'], 'https://x.co/rest/v1/m');
    });

    test('keeps the app\'s own workout crumb', () {
      final crumb = scrubBreadcrumb(
        Breadcrumb(
          category: 'workout',
          message: 'finish queued',
          data: {'replayed': true},
        ),
        hint,
      )!;
      expect(crumb.message, 'finish queued');
      expect(crumb.data, {'replayed': true});
    });
  });

  group('diagnostics', () {
    test('describes a failure by type and code, never its text', () {
      final error = PostgrestException(
        message: 'Failing row contains (400)',
        code: '23514',
        details: 'weight 400',
      );
      final described = describeFailure(error);
      expect(described, 'PostgrestException 23514');
      expect(described, isNot(contains('400')));
      expect(describeFailure(StateError('secret 400')), 'StateError');
    });

    test('a reported failure reaches the sink without the exception text', () {
      final seen = <NonCriticalFailure>[];
      final previous = failureSink;
      failureSink = (failure, _) => seen.add(failure);
      addTearDown(() => failureSink = previous);
      reportNonCritical(
        PostgrestException(message: 'row (400)', code: '23514'),
        null,
        'Weigh-in not saved',
      );
      expect(seen.single.toString(), isNot(contains('400')));
      expect(seen.single.what, 'Weigh-in not saved');
      expect(seen.single.detail, 'PostgrestException 23514');
    });
  });
}
