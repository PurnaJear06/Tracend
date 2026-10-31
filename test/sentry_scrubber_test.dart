import 'dart:io';

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
    test('templates a request URL to its origin and route', () {
      const uid = '3f2b8c1e-5a47-4d0e-9b61-7c2a4e8f1d90';
      final out = scrubEvent(
        SentryEvent(
          request: SentryRequest(
            url:
                'https://x.supabase.co/storage/v1/object/authenticated/progress/$uid/9/IMG_1234.JPG?t=1#f',
          ),
        ),
        hint,
      )!;
      expect(out.request!.url, 'https://x.supabase.co/storage/v1/object/:path');
      expect(out.request!.url, isNot(contains(uid)));
      expect(
        templateUrl('https://x.co:8443/rest/v1/meals/$uid/12/a.png?q=1'),
        'https://x.co:8443/rest/v1/meals/:id/:id/:id',
      );
      expect(
        templateUrl('https://x.co/rest/v1/rpc/get_my_training_hub'),
        'https://x.co/rest/v1/rpc/get_my_training_hub',
      );
      expect(templateUrl('not a url'), '[url]');
    });

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

    SentryEvent thrownEvent(Object error, String value) => SentryEvent(
      throwable: error,
      exceptions: [SentryException(type: '${error.runtimeType}', value: value)],
    );

    test('keeps only the type and code of an exception, never its text', () {
      final cases = <(Object, String, String)>[
        (
          const FileSystemException(
            'Cannot open IMG_1234.JPG',
            '/p/IMG_1234.JPG',
          ),
          'Cannot open IMG_1234.JPG',
          'FileSystemException',
        ),
        (
          PostgrestException(message: 'Failing row (82 kg)', code: '23514'),
          'PostgrestException: Failing row (82 kg)',
          'PostgrestException 23514',
        ),
        (
          const SocketException('Failed host lookup: x.supabase.co'),
          'SocketException: Failed host lookup: x.supabase.co',
          'SocketException network',
        ),
        (
          StateError('You ate oats and eggs, so protein is low.'),
          'Bad state: You ate oats and eggs, so protein is low.',
          'StateError',
        ),
      ];
      for (final (error, text, expected) in cases) {
        final out = scrubEvent(thrownEvent(error, text), hint)!;
        expect(out.exceptions!.single.value, expected);
        expect(out.exceptions!.single.type, '${error.runtimeType}');
      }
    });

    test('an exception with no thrown object keeps its type and no text', () {
      final out = scrubEvent(
        SentryEvent(
          exceptions: [SentryException(type: 'NativeCrash', value: 'ate oats')],
        ),
        hint,
      )!;
      expect(out.exceptions!.single.type, 'NativeCrash');
      expect(out.exceptions!.single.value, isNull);
    });

    test('a reported failure keeps its fixed wording', () {
      final failure = NonCriticalFailure(
        'Account state not loaded',
        'SocketException network',
      );
      final out = scrubEvent(thrownEvent(failure, '$failure'), hint)!;
      expect(
        out.exceptions!.single.value,
        'NonCriticalFailure: Account state not loaded (SocketException network)',
      );
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

    test('keeps no athlete path in a Storage URL', () {
      const uid = '3f2b8c1e-5a47-4d0e-9b61-7c2a4e8f1d90';
      const setId = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
      final crumb = scrubBreadcrumb(
        Breadcrumb(
          type: 'http',
          category: 'http',
          data: {
            'url':
                'https://x.supabase.co/storage/v1/object/sign/progress/$uid/$setId/front.jpg?token=abc',
            'method': 'POST',
          },
        ),
        hint,
      )!;
      expect(
        crumb.data!['url'],
        'https://x.supabase.co/storage/v1/object/:path',
      );
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
