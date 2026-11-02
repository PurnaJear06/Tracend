import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/onboarding/current_setup.dart';
import 'package:tracend/features/onboarding/onboarding_screening.dart';

const _userId = '11111111-1111-4111-8111-111111111111';

const _cleared = ScreeningAnswers(
  exercisesRegularly: true,
  knownCondition: false,
  symptoms: false,
  clearedByProfessional: false,
);

void main() {
  group('currentSetupDraft', () {
    final profile = <String, dynamic>{
      'experience_level': 'intermediate',
      'height_cm': 178,
      'training_days': [1, 3, 5],
      'session_minutes': 60,
      'sex': 'male',
      'birth_year': 1990,
      'daily_activity': 'mostly_sitting',
      'equipment': ['dumbbells', 'bench'],
      'equipment_note': 'Hotel gym on trips',
      'avoid_patterns': ['squat'],
      'limitations_note': 'Sore left knee',
      'nutrition_note': 'No dairy',
      'training_years': '3_5',
      'priority_muscles': ['chest'],
      'strong_muscles': ['legs'],
    };

    test(
      'what was approved wins over a draft the athlete walked away from',
      () {
        final draft = currentSetupDraft(
          draftPath: 'experienced',
          draftPayload: {
            'goal': 'strength',
            'training_weekdays': [2, 4],
            'session_minutes': 30,
            'equipment_items': ['bands'],
            'weight_kg': 70,
            'target_weight_kg': 65,
            'current_plan': 'Upper/lower',
            'health_import': 'skipped',
            'follow_ups_hash': 'old',
            'follow_ups': [
              {'category': 'recovery', 'question': 'Sleep?', 'answer': 'Fine'},
            ],
            'revision_note': 'Fewer squats',
          },
          profile: profile,
          goal: {
            'goal_type': 'muscle_gain',
            'details': {'target_weight_kg': 84},
          },
          weightKg: 81.5,
          screening: _cleared,
        );

        expect(draft.currentSection, 'review');
        expect(draft.path, 'experienced');
        final payload = draft.payload;
        expect(payload['goal'], 'muscle_gain');
        expect(payload['target_weight_kg'], 84);
        expect(payload['weight_kg'], 81.5);
        expect(payload['experience'], 'intermediate');
        expect(payload['training_weekdays'], [1, 3, 5]);
        expect(payload['training_days'], 3);
        expect(payload['session_minutes'], 60);
        expect(payload['equipment_items'], ['dumbbells', 'bench']);
        expect(payload['equipment'], 'Hotel gym on trips');
        expect(payload['avoid_patterns'], ['squat']);
        expect(payload['constraints'], 'Sore left knee');
        expect(payload['nutrition_context'], 'No dairy');
        expect(payload['training_years'], '3_5');
        expect(payload['priority_muscles'], ['chest']);
        expect(payload['strong_muscles'], ['legs']);
        expect(payload['screening'], _cleared.toJson());
        // Not kept by approval, so the draft supplies them.
        expect(payload['current_plan'], 'Upper/lower');
        expect(payload['health_import'], 'skipped');
        // Belong to an earlier build of the plan.
        expect(payload.containsKey('follow_ups'), isFalse);
        expect(payload.containsKey('follow_ups_hash'), isFalse);
        expect(payload.containsKey('revision_note'), isFalse);
      },
    );

    test('a goal with no target clears a target left in the draft', () {
      final draft = currentSetupDraft(
        draftPath: 'beginner',
        draftPayload: {'target_weight_kg': 65},
        profile: profile,
        goal: {'goal_type': 'fat_loss', 'details': <String, dynamic>{}},
        weightKg: null,
        screening: null,
      );
      expect(draft.payload['target_weight_kg'], isNull);
      expect(draft.payload.containsKey('screening'), isFalse);
    });

    test('empty approved notes read as none, not as the draft', () {
      final draft = currentSetupDraft(
        draftPath: 'beginner',
        draftPayload: {'constraints': 'Old note', 'equipment': 'Old'},
        profile: {...profile, 'limitations_note': null, 'equipment_note': ''},
        goal: null,
        weightKg: null,
        screening: null,
      );
      expect(draft.payload['constraints'], '');
      expect(draft.payload['equipment'], '');
    });

    test('with no saved draft the path follows the training years', () {
      final experienced = currentSetupDraft(
        draftPath: null,
        draftPayload: const {},
        profile: profile,
        goal: null,
        weightKg: null,
        screening: null,
      );
      expect(experienced.path, 'experienced');

      final beginner = currentSetupDraft(
        draftPath: null,
        draftPayload: const {},
        profile: {...profile, 'training_years': null},
        goal: null,
        weightKg: null,
        screening: null,
      );
      expect(beginner.path, 'beginner');
    });

    test('an answer approval did not keep falls back to the draft', () {
      final draft = currentSetupDraft(
        draftPath: 'beginner',
        draftPayload: {'nutrition_context': 'Vegetarian', 'weight_kg': 70},
        profile: {...profile, 'nutrition_note': null},
        goal: null,
        weightKg: null,
        screening: null,
      );
      expect(draft.payload['nutrition_context'], 'Vegetarian');
      expect(draft.payload['weight_kg'], 70);
    });
  });

  group('SupabaseCurrentSetup', () {
    test('reads the approved answers and writes nothing', () async {
      final requests = <String>[];
      final client = SupabaseClient(
        'https://tracend-test.supabase.co',
        'publishable-test',
        httpClient: MockClient((request) async {
          final query = request.url.query.isEmpty
              ? ''
              : '?${Uri.decodeQueryComponent(request.url.query)}';
          requests.add('${request.method} ${request.url.path}$query');
          Object body = <Object>[];
          switch (request.url.path) {
            case '/rest/v1/onboarding_drafts':
              body = {
                'path': 'beginner',
                'payload': {
                  'goal': 'strength',
                  'training_weekdays': [2],
                },
              };
            case '/rest/v1/user_profiles':
              body = {
                'training_days': [1, 4],
                'session_minutes': 45,
                'equipment': ['kettlebells'],
              };
            case '/rest/v1/user_goals':
              body = {
                'goal_type': 'recomposition',
                'details': {'phase': 'cut'},
              };
            case '/rest/v1/body_measurements':
              body = {'weight_kg': 79.5};
            case '/rest/v1/rpc/get_my_screening_v1':
              body = {
                'schema_version': '1.0',
                'screened': true,
                'outcome': 'cleared',
                ..._cleared.toJson(),
              };
          }
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await _signIn(client);

      final draft = await SupabaseCurrentSetup(client).load();

      expect(draft.currentSection, 'review');
      expect(draft.payload['goal'], 'recomposition');
      expect(draft.payload['training_weekdays'], [1, 4]);
      expect(draft.payload['session_minutes'], 45);
      expect(draft.payload['equipment_items'], ['kettlebells']);
      expect(draft.payload['weight_kg'], 79.5);
      expect(draft.payload['screening'], _cleared.toJson());
      expect(
        requests.where(
          (request) =>
              !request.startsWith('GET ') &&
              !request.startsWith('POST /rest/v1/rpc/get_my_screening_v1'),
        ),
        isEmpty,
      );
      // The newest weight, not the oldest.
      final weights = requests.singleWhere(
        (request) => request.contains('/body_measurements'),
      );
      expect(weights, contains('order=measured_on.desc'));
      expect(weights, contains('limit=1'));
    });
  });
}

Future<void> _signIn(SupabaseClient client) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1));
  final token = [
    part({'alg': 'HS256', 'typ': 'JWT'}),
    part({'sub': _userId, 'exp': exp.millisecondsSinceEpoch ~/ 1000}),
    'test-signature',
  ].join('.');
  return client.auth.setInitialSession(
    jsonEncode({
      'access_token': token,
      'expires_in': 3600,
      'refresh_token': 'refresh-test',
      'token_type': 'bearer',
      'user': {
        'id': _userId,
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'athlete@tracend.test',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-10-01T00:00:00Z',
      },
    }),
  );
}
