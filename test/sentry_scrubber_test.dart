import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tracend/app/sentry_scrubber.dart';

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

  group('what Sentry may carry of the pain check', () {
    test('an event keeps no pain key, area, severity or red flag', () {
      final event = SentryEvent(
        request: SentryRequest(
          url: 'https://example.supabase.co/rest/v1/rpc/save_daily_check_in',
          data: {
            'payload': {
              'pain_area': 'knee',
              'pain_severity': 8,
              'pain_red_flags': ['rapid_swelling'],
              'pain_followups': [
                {'area': 'back', 'severity': 5, 'cleared_by_clinician': false},
              ],
              'note': 'left in',
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

      final scrubbed = scrubSentryEvent(event, hint)!;
      final text = _everything(scrubbed);

      for (final secret in _secrets) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
      // The keys that carry an answer go whole, name and value.
      final data = scrubbed.request!.data as Map;
      expect(data.containsKey('red_flags'), isFalse);
      expect(data.containsKey('area'), isFalse);
      expect(data.containsKey('severity'), isFalse);
      final payload = data['payload'] as Map;
      expect(payload.keys, ['note']);
      // Everything else on the old list is redacted, and plain facts stay.
      expect(data['weight_kg'], redacted);
      expect(payload['note'], 'left in');
      // ignore: deprecated_member_use
      expect(scrubbed.extra!.keys, ['kept']);
      // ignore: deprecated_member_use
      expect(scrubbed.extra!['kept'], 'a plain fact');
      expect(scrubbed.tags, {'screen': 'today'});
      expect(scrubbed.exceptions!.single.type, 'PostgrestException');
      final crumb = scrubbed.breadcrumbs!.single;
      expect(crumb.data, {'outcome': 'ok'});
      expect(crumb.message, contains('record_pain_check_v1'));
    });

    test('a breadcrumb the SDK records is scrubbed before it is kept', () {
      final crumb = scrubSentryBreadcrumb(
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
      expect(crumb.message, contains('record_pain_check_v1'));
      expect(crumb.data.toString(), isNot(contains('numb_weak_limb')));
      expect(crumb.data!.containsKey('request_body'), isTrue);
      expect((crumb.data!['request_body'] as Map).isEmpty, isTrue);
      expect(crumb.data!['url'], contains('record_pain_check_v1'));
    });

    test('a row the database refused is not reported with its values', () {
      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'PostgrestException',
            value:
                'new row violates check constraint. Failing row contains '
                '(r1, u1, 2026-10-24, knee, 8, {numb}, clinician_today).',
          ),
        ],
      );
      final scrubbed = scrubSentryEvent(event, hint)!;
      final value = scrubbed.exceptions!.single.value!;
      expect(value, contains('new row violates check constraint'));
      expect(value, isNot(contains('knee')));
      expect(value, isNot(contains('2026-10-24')));
    });

    test('a missing breadcrumb stays missing', () {
      expect(scrubSentryBreadcrumb(null, hint), isNull);
    });

    test('words that name no answer are left alone', () {
      final event = SentryEvent(
        message: SentryMessage('Workout synced after a retry'),
        breadcrumbs: [Breadcrumb(message: 'Workout started')],
      );
      final scrubbed = scrubSentryEvent(event, hint)!;
      expect(scrubbed.message!.formatted, 'Workout synced after a retry');
      expect(scrubbed.breadcrumbs!.single.message, 'Workout started');
    });
  });
}
