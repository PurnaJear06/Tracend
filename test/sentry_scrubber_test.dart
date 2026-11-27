import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/sentry_scrubber.dart';
import 'package:tracend/shared/diagnostics.dart';

const _secrets = [
  'rapid_swelling',
  'bladder_bowel_saddle',
  'red_flag',
  'night_pain',
  'locks_gives_way',
  'pain_referral',
  'pain_area',
  'pain_severity',
  'clinician_today',
  'numb_weak_limb',
];

String _everything(SentryEvent event) => event.toJson().toString();

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

    test('keeps the account id alone as the user', () {
      const uid = '3f2b8c1e-5a47-4d0e-9b61-7c2a4e8f1d90';
      final out = scrubEvent(
        SentryEvent(
          user: SentryUser(
            id: uid,
            email: 'athlete@example.com',
            name: 'Athlete',
            ipAddress: '203.0.113.7',
          ),
        ),
        hint,
      )!;
      expect(out.user!.id, uid);
      expect(out.user!.email, isNull);
      expect(out.user!.name, isNull);
      expect(out.user!.ipAddress, isNull);

      final anonymous = scrubEvent(
        SentryEvent(user: SentryUser(email: 'athlete@example.com')),
        hint,
      )!;
      expect(anonymous.user, isNull);
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

  group('what Sentry may carry of the pain check', () {
    test('an event keeps no pain key, area, severity or red flag', () {
      final event = SentryEvent(
        request: SentryRequest(
          url: 'https://example.supabase.co/rest/v1/rpc/save_daily_check_in',
          data: {
            'body': {
              'pain_area': 'knee',
              'pain_severity': 8,
              'pain_red_flags': ['rapid_swelling'],
              'pain_followups': [
                {'area': 'back', 'severity': 5, 'cleared_by_clinician': false},
              ],
              'plain': 'left in',
            },
            'red_flags': ['night_pain'],
            'area': 'knee',
            'severity': 9,
            'weight_kg': 80,
          },
        ),
        // ignore: deprecated_member_use
        extra: {
          'joint_states': [
            {'area': 'knee', 'state': 'held'},
          ],
          'safety_route': 'clinician_today',
          'hold_outcome': 'clinician_today',
          'swap_to_name': 'Leg press',
          'kept': 'a plain fact',
        },
        tags: {'pain_area': 'knee', 'screen': 'today'},
        message: SentryMessage(
          'red_flag:rapid_swelling for a pain_referral on the knee',
          template: 'red_flag:%s',
          params: ['night_pain'],
        ),
        exceptions: [
          SentryException(
            type: 'PostgrestException',
            value:
                'clinician_today refused pain_red_flags: bladder_bowel_saddle',
          ),
        ],
        breadcrumbs: [
          Breadcrumb(
            message: 'record_pain_check_v1 sent red_flag:locks_gives_way',
            data: {'pain_severity': 8, 'outcome': 'ok', 'area': 'knee'},
          ),
        ],
      );

      final scrubbed = scrubEvent(event, hint)!;
      final text = _everything(scrubbed);

      for (final secret in _secrets) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
      // The keys that carry an answer go whole, name and value.
      final data = scrubbed.request!.data as Map;
      expect(data.containsKey('red_flags'), isFalse);
      expect(data.containsKey('area'), isFalse);
      expect(data.containsKey('severity'), isFalse);
      final body = data['body'] as Map;
      expect(body.keys, ['plain']);
      // Everything else on the sensitive list is redacted, plain facts stay.
      expect(data['weight_kg'], redactedValue);
      expect(body['plain'], 'left in');
      // ignore: deprecated_member_use
      expect(scrubbed.extra!.keys, ['kept']);
      // ignore: deprecated_member_use
      expect(scrubbed.extra!['kept'], 'a plain fact');
      expect(scrubbed.tags, {'screen': 'today'});
      expect(scrubbed.exceptions!.single.type, 'PostgrestException');
      expect(scrubbed.exceptions!.single.value, isNull);
      expect(scrubbed.message!.template, isNull);
      expect(scrubbed.message!.params, isNull);
      final crumb = scrubbed.breadcrumbs!.single;
      expect(crumb.data, {'outcome': 'ok'});
      expect(crumb.message, isNot(contains('record_pain_check')));
    });

    test('a breadcrumb the SDK records is scrubbed before it is kept', () {
      final crumb = scrubBreadcrumb(
        Breadcrumb(
          category: 'http',
          message: 'POST /rpc/record_pain_check_v1 pain_area=back',
          data: {
            'url': 'https://example.supabase.co/rpc/record_pain_check_v1',
            'request_body': {
              'red_flags': ['numb_weak_limb'],
              'severity': 6,
            },
          },
        ),
        hint,
      )!;
      expect(crumb.message, isNot(contains('pain_area')));
      expect(crumb.message, isNot(contains('back')), reason: 'the value too');
      expect(crumb.message, isNot(contains('record_pain_check')));
      expect(crumb.data.toString(), isNot(contains('numb_weak_limb')));
      expect(crumb.data!.containsKey('request_body'), isFalse);
      expect(crumb.data!['url'], isNot(contains('record_pain_check')));
    });

    test('a row the database refused is not reported with its values', () {
      final event = SentryEvent(
        message: SentryMessage(
          'new row violates check constraint. Failing row contains '
          '(r1, u1, 2026-10-24, knee, 8, {numb}, clinician_today).',
        ),
      );
      final scrubbed = scrubEvent(event, hint)!;
      final value = scrubbed.message!.formatted;
      expect(value, contains('new row violates check constraint'));
      expect(value, isNot(contains('knee')));
      expect(value, isNot(contains('2026-10-24')));
    });

    test(
      'a row cut short before its bracket is gone to the end of the line',
      () {
        final event = SentryEvent(
          message: SentryMessage(
            'new row violates check constraint\nFailing row contains '
            '(r1, u1, 2026-10-24, shoulder, 8, {numb_weak_limb}, clin',
          ),
        );
        final value = scrubEvent(event, hint)!.message!.formatted;
        expect(value, contains('new row violates check constraint'));
        for (final left in ['shoulder', '2026-10-24', 'r1, u1', 'clin']) {
          expect(value, isNot(contains(left)));
        }
      },
    );

    test('a pain key and its value go together, in any text', () {
      final texts = {
        'pain_area=back': 'back',
        'saved pain_severity: 8 for the visit': '8 for',
        'body {"pain_area":"lower back","pain_severity":7}': 'lower back',
        "args(pain_red_flags: ['night_pain', 'fever_unwell'])": 'fever',
        'GET /rest/v1/x?area=knee&limit=1': 'knee',
        "payload {'area': 'shoulder'}": 'shoulder',
        'red_flags = [numb_weak_limb] failed': 'numb',
        'cleared_by_clinician=true': 'true',
      };
      for (final entry in texts.entries) {
        final scrubbed = scrubEvent(
          SentryEvent(message: SentryMessage(entry.key)),
          hint,
        )!.message!.formatted;
        expect(scrubbed, isNot(contains(entry.value)), reason: scrubbed);
      }
      final kept = scrubEvent(
        SentryEvent(message: SentryMessage('limit=1 failed for the workout')),
        hint,
      )!.message!.formatted;
      expect(kept, 'limit=1 failed for the workout');
    });

    test('a multi-word or escaped value goes whole, not its first word', () {
      final texts = {
        'note: ate oats and eggs': ['oats', 'eggs'],
        'meal_description = two eggs, toast and jam': ['toast', 'jam'],
        'pain_area: lower back, left side': ['back', 'left'],
        r'{"note": "she said \"no oats\" then left", "ok": 1}': [
          'oats',
          'then left',
        ],
        "{'meal': 'it\\'s oats and eggs', 'ok': 1}": ['oats', 'eggs'],
        'note: "ate oats and eggs and then the cut-off': ['oats', 'eggs'],
      };
      for (final entry in texts.entries) {
        final scrubbed = scrubText(entry.key);
        for (final left in entry.value) {
          expect(scrubbed, isNot(contains(left)), reason: scrubbed);
        }
      }
      // A closed quoted value leaves the rest of the structure readable.
      expect(scrubText('{"note": "ate oats", "ok": 1}'), contains('"ok": 1'));
    });

    test('the table and the function of the pain check are not named', () {
      final scrubbed = scrubEvent(
        SentryEvent(
          message: SentryMessage(
            'insert into pain_reports failed in record_pain_check_v1',
          ),
        ),
        hint,
      )!.message!.formatted;
      expect(scrubbed, isNot(contains('pain_reports')));
      expect(scrubbed, isNot(contains('record_pain_check')));
      expect(scrubbed, contains('failed in'));
    });

    test('a missing breadcrumb stays missing', () {
      expect(scrubBreadcrumb(null, hint), isNull);
    });

    test('words that name no answer are left alone', () {
      final event = SentryEvent(
        message: SentryMessage('Workout synced after a retry'),
        breadcrumbs: [Breadcrumb(message: 'Workout started')],
      );
      final scrubbed = scrubEvent(event, hint)!;
      expect(scrubbed.message!.formatted, 'Workout synced after a retry');
      expect(scrubbed.breadcrumbs!.single.message, 'Workout started');
    });
  });

  group('what Sentry may carry of the cycle', () {
    Map<String, dynamic> fixture(String name) => Map<String, dynamic>.from(
      json.decode(File('test/contract/fixtures/$name').readAsStringSync())
          as Map,
    );

    // What the app sends the cycle RPCs, by their real parameter names.
    final rpcParams = <String, Map<String, Object?>>{
      'log_cycle_day_v1': {
        'p_local_date': '2026-11-10',
        'p_flow': 'heavy',
        'p_cramps': 'strong',
        'p_is_start': true,
      },
      'set_my_cycle_settings_v1': {
        'p_tracking_enabled': true,
        'p_status': 'hormonal_contraception',
        'p_typical_cycle_days': 31,
        'p_apple_health_enabled': false,
      },
      'import_cycle_days_v1': {
        'p_from': '2026-05-01',
        'p_to': '2026-11-27',
        'p_days': [
          {'local_date': '2026-11-10', 'flow': 'medium', 'is_start': true},
        ],
      },
    };

    test('an answer from the database keeps nothing of the cycle', () {
      for (final name in const [
        'my_cycle_v1_0_regular.json',
        'my_cycle_v1_0_contraception.json',
        'my_cycle_v1_0_off.json',
      ]) {
        final answer = fixture(name);
        final scrubbed = scrubEvent(
          SentryEvent(
            request: SentryRequest(
              url: 'https://example.supabase.co/rest/v1/rpc/get_my_cycle_v1',
              data: {'response': answer, 'screen': 'today'},
            ),
            // ignore: deprecated_member_use
            extra: {...answer, 'kept': 'a plain fact'},
          ),
          hint,
        )!;
        final data = scrubbed.request!.data as Map;
        final response = data['response'] as Map;
        for (final key in ['typical_cycle_days', 'recent_days', 'cycles']) {
          expect(response.containsKey(key), isFalse, reason: '$name $key');
        }
        // `state` is too common a key to drop; what is inside it goes.
        final state = response['state'] as Map;
        for (final key in [
          'cycle_day',
          'period_day',
          'expected_from',
          'expected_to',
          'late_days',
          'no_period_long',
          'weight_water_window',
        ]) {
          expect(state.containsKey(key), isFalse, reason: '$name $key');
        }
        // ignore: deprecated_member_use
        final extra = scrubbed.extra!;
        for (final key in ['typical_cycle_days', 'recent_days', 'cycles']) {
          expect(extra.containsKey(key), isFalse, reason: '$name $key');
        }
        expect(extra['kept'], 'a plain fact');
        expect(data['screen'], 'today');
        // The event's own timestamp is not the answer's.
        // ignore: deprecated_member_use
        final text = '${scrubbed.request!.data} ${scrubbed.extra}';
        // Every date, flow and phase the answer holds, whatever the fixture.
        final answerState = answer['state'] as Map;
        final secrets = <String>[
          'hormonal_contraception',
          'second_half',
          ?answerState['expected_from'] as String?,
          ?answerState['expected_to'] as String?,
          for (final day in answer['recent_days'] as List) ...[
            (day as Map)['local_date'] as String,
          ],
          for (final cycle in answer['cycles'] as List)
            (cycle as Map)['start_date'] as String,
        ];
        for (final secret in secrets) {
          expect(text, isNot(contains(secret)), reason: '$name $secret');
        }
      }
    });

    test('the state keys go whole at any depth', () {
      final state =
          fixture('my_cycle_v1_0_regular.json')['state']!
              as Map<String, dynamic>;
      final scrubbed =
          scrubValue({
                'deep': {'state': state, 'keep': 1},
              })!
              as Map;
      expect(scrubbed, {
        'deep': {
          'state': <String, Object?>{
            // `phase` and `confidence` are too common to drop as keys; the
            // values that say where she is in her cycle go instead.
            'phase': redactedValue,
            'confidence': 'medium',
          },
          'keep': 1,
        },
      });
    });

    test('the RPC parameters go whole', () {
      for (final entry in rpcParams.entries) {
        final scrubbed = scrubValue({entry.key: entry.value})! as Map;
        final params = scrubbed.values.single as Map;
        for (final key in [
          'p_flow',
          'p_cramps',
          'p_status',
          'p_days',
          'p_is_start',
          'p_typical_cycle_days',
        ]) {
          expect(params.containsKey(key), isFalse, reason: '${entry.key} $key');
        }
        final text = scrubbed.toString();
        for (final secret in ['heavy', 'strong', 'hormonal_contraception']) {
          expect(text, isNot(contains(secret)), reason: entry.key);
        }
      }
    });

    test('the values that say how her cycle works go, whatever the key', () {
      final scrubbed =
          scrubValue({
                'status': 'hormonal_contraception',
                'cycle': 'no_periods',
                'phase': 'second_half',
                'where': ' First_Half ',
                'tags': ['second_half', 'ok'],
              })!
              as Map;
      expect(scrubbed['status'], redactedValue);
      expect(scrubbed['cycle'], redactedValue);
      expect(scrubbed['phase'], redactedValue);
      expect(scrubbed['where'], redactedValue);
      expect(scrubbed['tags'], [redactedValue, 'ok']);
    });

    test('plain status and phase keys are not dropped', () {
      final scrubbed =
          scrubValue({
                'status': 'running',
                'phase': 'upload',
                'confidence': 'high',
              })!
              as Map;
      expect(scrubbed, {
        'status': 'running',
        'phase': 'upload',
        'confidence': 'high',
      });
    });

    test('the cycle RPC names that write answers go from free text', () {
      for (final name in rpcParams.keys.followedBy([
        'delete_my_cycle_data_v1',
      ])) {
        final text = scrubText('failed in $name after a retry');
        expect(text, isNot(contains(name)), reason: name);
        expect(text, contains('after a retry'));
      }
      expect(
        scrubText('https://x.co/rest/v1/rpc/get_my_cycle_v1'),
        contains('get_my_cycle_v1'),
      );
    });

    test('an event keeps no cycle key, flow, period or cramps', () {
      final event = SentryEvent(
        request: SentryRequest(
          url: 'https://example.supabase.co/rest/v1/rpc/log_cycle_day_v1',
          data: {
            'body': {
              'cycle_status': 'regular',
              'menstrual_flow': 'heavy',
              'flow': 'heavy',
              'period': '2026-11-10',
              'cramps': 'strong',
              'plain': 'left in',
            },
          },
        ),
        // ignore: deprecated_member_use
        extra: {
          'cycle_state': {'phase': 'second_half'},
          'flow': 'light',
          'period': 'yes',
          'kept': 'a plain fact',
        },
        tags: {'cycle_status': 'regular', 'screen': 'today'},
        breadcrumbs: [
          Breadcrumb(
            message: 'log_cycle_day_v1 sent',
            data: {'cramps': 'mild', 'menstruation_logged': true, 'ok': 1},
          ),
        ],
      );

      final scrubbed = scrubEvent(event, hint)!;
      final body = (scrubbed.request!.data as Map)['body'] as Map;
      expect(body.keys, ['plain']);
      expect(scrubbed.request!.url, isNot(contains('log_cycle_day')));
      // ignore: deprecated_member_use
      expect(scrubbed.extra!.keys, ['kept']);
      expect(scrubbed.tags, {'screen': 'today'});
      expect(scrubbed.breadcrumbs!.single.data, {'ok': 1});
      final text = _everything(scrubbed);
      for (final secret in ['heavy', 'strong', 'regular', '2026-11-10']) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
    });

    test('keys that only contain the words are not touched', () {
      final scrubbed =
          scrubValue({
                'workflow': 'checkout',
                'lifecycle': 'resumed',
                'periodDays': 28,
                'flowers': 'tulips',
                'recycle_bin': 'empty',
              })!
              as Map;
      expect(scrubbed, {
        'workflow': 'checkout',
        'lifecycle': 'resumed',
        'periodDays': 28,
        'flowers': 'tulips',
        'recycle_bin': 'empty',
      });
    });

    test(
      'a training pause keeps its start_date and the cycle list is gone',
      () {
        final scrubbed =
            scrubValue({
                  'pause': {
                    'start_date': '2026-12-01',
                    'end_date': '2026-12-05',
                    'length_days': 5,
                  },
                  'cycles': [
                    {
                      'start_date': '2026-10-13',
                      'length_days': 28,
                      'used': true,
                    },
                  ],
                })!
                as Map;
        expect(scrubbed.containsKey('cycles'), isFalse);
        expect(scrubbed['pause'], {
          'start_date': '2026-12-01',
          'end_date': '2026-12-05',
          'length_days': 5,
        });
      },
    );

    test('the exact keys flow and period are dropped at any depth', () {
      final scrubbed =
          scrubValue({
                'a': [
                  {'flow': 'light', 'period': 3, 'workflow': 'x'},
                ],
              })!
              as Map;
      expect(scrubbed, {
        'a': [
          {'workflow': 'x'},
        ],
      });
    });

    test('a cycle key with its value in free text goes whole', () {
      final text = scrubText(
        'refused cycle_status=hormonal_contraception and cramps: strong',
      );
      expect(text, isNot(contains('hormonal_contraception')));
      expect(text, isNot(contains('strong')));
      expect(text, contains('refused'));
    });

    test('names of other functions and ordinary words are left alone', () {
      expect(
        scrubText('get_my_cycle_v1 failed after a lifecycle workflow'),
        'get_my_cycle_v1 failed after a lifecycle workflow',
      );
      expect(scrubText('period of 3 weeks'), 'period of 3 weeks');
    });
  });
}
