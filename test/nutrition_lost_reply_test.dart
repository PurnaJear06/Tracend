import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/nutrition/nutrition_screen.dart';

const _userId = '11111111-1111-4111-8111-111111111111';
const _mealId = '22222222-2222-4222-8222-222222222222';

class _Repository implements NutritionRepository {
  _Repository({this.draft = false, this.draftAge = const Duration(hours: 1)});

  final bool draft;

  /// How long ago the draft was created.
  final Duration draftAge;

  /// A failing save was written by the server before its reply was lost.
  bool writtenBeforeFailing = false;
  final writtenKeys = <String>{};

  /// Asking whether a meal was saved fails (offline).
  bool lookupFails = false;

  /// How many saves fail before one succeeds.
  int failingSaves = 0;
  final saves = <({String key, String name})>[];
  int summaryLoads = 0;
  final deleted = <String>[];
  bool failDelete = false;

  @override
  Future<NutritionTargets?> loadTargets() async => null;

  @override
  Future<NutritionSummary> loadSummary(DateTime date) async {
    summaryLoads++;
    return const NutritionSummary(
      calories: 0,
      protein: 0,
      carbohydrate: 0,
      fat: 0,
      confirmedMeals: 0,
    );
  }

  @override
  Future<List<MealEntry>> loadMeals(DateTime date) async => [
    if (draft)
      MealEntry(
        id: 'draft-1',
        type: 'lunch',
        status: 'draft',
        source: 'photo_analysis',
        loggedAt: DateTime.now().subtract(draftAge),
      ),
  ];

  @override
  Future<void> saveManualMeal({
    required DateTime date,
    required String mealType,
    required ManualFoodInput food,
    required String idempotencyKey,
  }) async {
    saves.add((key: idempotencyKey, name: food.name));
    if (failingSaves > 0) {
      failingSaves--;
      if (writtenBeforeFailing) writtenKeys.add(idempotencyKey);
      throw Exception('offline');
    }
    writtenKeys.add(idempotencyKey);
  }

  @override
  Future<bool> isMealSaved(String idempotencyKey) async {
    if (lookupFails) throw Exception('offline');
    return writtenKeys.contains(idempotencyKey);
  }

  @override
  Future<String> createFixtureMeal({
    required DateTime date,
    required String mealType,
  }) => throw UnimplementedError();

  @override
  Future<List<MealCandidate>> loadCandidates(String mealId) async => const [];

  @override
  Future<void> confirmCandidates(
    String mealId,
    List<MealCandidate> candidates,
  ) => throw UnimplementedError();

  @override
  Future<void> deleteMeal(String mealId) async {
    if (failDelete) throw Exception('offline');
    deleted.add(mealId);
  }
}

Future<void> _show(WidgetTester tester, NutritionRepository repository) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.light,
      home: Scaffold(body: NutritionScreen(repository: repository)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openManual(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('log-a-meal'));
  await tester.scrollUntilVisible(
    button,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Enter manually'));
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester, {String name = 'Oats'}) async {
  for (final (label, value) in [
    ('Food name', name),
    ('Serving', '1 bowl'),
    ('Calories', '380'),
    ('Protein (g)', '15'),
    ('Carbohydrate (g)', '58'),
    ('Fat (g)', '9'),
  ]) {
    await tester.enterText(find.widgetWithText(TextFormField, label), value);
  }
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Confirm meal'));
  await tester.tap(find.text('Confirm meal'));
  await tester.pumpAndSettle();
}

void main() {
  group('a manual meal whose save fails', () {
    testWidgets('keeps the sheet and what was typed, and says so', (
      tester,
    ) async {
      final repository = _Repository()..failingSaves = 1;
      await _show(tester, repository);
      await _openManual(tester);
      await _fill(tester);
      await _confirm(tester);

      expect(find.textContaining('The meal was not saved'), findsOneWidget);
      expect(find.text('Oats'), findsOneWidget);
      expect(find.text('380'), findsOneWidget);
      expect(find.text('Confirm meal'), findsOneWidget);
      expect(find.text('Meal logged'), findsNothing);
    });

    testWidgets('closes as saved when the server did write the meal', (
      tester,
    ) async {
      final repository = _Repository()
        ..failingSaves = 1
        ..writtenBeforeFailing = true;
      await _show(tester, repository);
      await _openManual(tester);
      await _fill(tester);
      await _confirm(tester);

      expect(find.text('Meal logged'), findsOneWidget);
      expect(find.text('Confirm meal'), findsNothing);
      expect(repository.saves, hasLength(1));
    });

    testWidgets('says it may not have been saved when that cannot be found '
        'out', (tester) async {
      final repository = _Repository()
        ..failingSaves = 1
        ..lookupFails = true;
      await _show(tester, repository);
      await _openManual(tester);
      await _fill(tester);
      await _confirm(tester);

      expect(find.textContaining('may not have been saved'), findsOneWidget);
      expect(find.textContaining('The meal was not saved'), findsNothing);
      expect(find.text('Oats'), findsOneWidget);
    });

    testWidgets('reloads the day, since the save may have been written', (
      tester,
    ) async {
      final repository = _Repository()..failingSaves = 1;
      await _show(tester, repository);
      final before = repository.summaryLoads;
      await _openManual(tester);
      await _fill(tester);
      await _confirm(tester);

      expect(repository.summaryLoads, greaterThan(before));
    });

    testWidgets('repeats the same key when retried unchanged, once', (
      tester,
    ) async {
      final repository = _Repository()..failingSaves = 2;
      await _show(tester, repository);
      await _openManual(tester);
      await _fill(tester);
      await _confirm(tester);
      await _confirm(tester);
      await _confirm(tester);

      expect(repository.saves, hasLength(3));
      expect(repository.saves.map((save) => save.key).toSet(), hasLength(1));
      expect(find.text('Meal logged'), findsOneWidget);
      expect(find.text('Confirm meal'), findsNothing);
    });

    testWidgets('uses a new key when the meal was changed before retrying', (
      tester,
    ) async {
      final repository = _Repository()..failingSaves = 1;
      await _show(tester, repository);
      await _openManual(tester);
      await _fill(tester);
      await _confirm(tester);
      await _fill(tester, name: 'Porridge');
      await _confirm(tester);

      expect(repository.saves.map((save) => save.name), ['Oats', 'Porridge']);
      expect(repository.saves.map((save) => save.key).toSet(), hasLength(2));
    });

    testWidgets('two separate meals get two keys', (tester) async {
      final repository = _Repository();
      await _show(tester, repository);
      await _openManual(tester);
      await _fill(tester);
      await _confirm(tester);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await _openManual(tester);
      await _fill(tester);
      await _confirm(tester);

      expect(repository.saves.map((save) => save.key).toSet(), hasLength(2));
    });
  });

  group('a draft with nothing to review', () {
    Future<void> openDraft(WidgetTester tester) async {
      final review = find.byKey(const ValueKey('review-meal-draft-1'));
      await tester.scrollUntilVisible(
        review,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(review);
      await tester.pumpAndSettle();
      await tester.tap(review);
      await tester.pumpAndSettle();
    }

    testWidgets('says so and offers Delete draft instead of a Confirm that '
        'never enables', (tester) async {
      final repository = _Repository(draft: true);
      await _show(tester, repository);
      await openDraft(tester);

      expect(find.textContaining('Nothing to review'), findsOneWidget);
      expect(find.text('Confirm selected foods'), findsNothing);

      await tester.tap(find.text('Delete draft'));
      await tester.pumpAndSettle();

      expect(repository.deleted, ['draft-1']);
      expect(find.textContaining('Nothing to review'), findsNothing);
      expect(find.text('Draft deleted'), findsOneWidget);
    });

    testWidgets('a draft that may still be analyzing is not offered for '
        'deletion', (tester) async {
      final repository = _Repository(
        draft: true,
        draftAge: const Duration(minutes: 1),
      );
      await _show(tester, repository);
      await openDraft(tester);

      expect(find.textContaining('Nothing to review yet'), findsOneWidget);
      expect(find.text('Delete draft'), findsNothing);
      expect(repository.deleted, isEmpty);
    });

    testWidgets('a failed delete says so and can be repeated', (tester) async {
      final repository = _Repository(draft: true)..failDelete = true;
      await _show(tester, repository);
      await openDraft(tester);

      await tester.tap(find.text('Delete draft'));
      await tester.pumpAndSettle();
      expect(find.textContaining('was not deleted'), findsOneWidget);

      repository.failDelete = false;
      await tester.tap(find.text('Delete draft'));
      await tester.pumpAndSettle();
      expect(repository.deleted, ['draft-1']);
    });
  });

  group('a meal photo that fails', () {
    late List<String> calls;

    /// The request key the draft was created with, and what the server was
    /// asked to delete.
    String? requestKey;
    late List<String> deleteTargets;
    late List<Map<String, String>> mealQueries;

    Future<SupabaseNutritionRepository> signedIn({
      required int analysisStatus,
      bool draftReplyLost = false,
      bool deleteFails = false,
    }) async {
      calls = [];
      requestKey = null;
      deleteTargets = [];
      mealQueries = [];
      final client = SupabaseClient(
        'https://tracend-test.supabase.co',
        'publishable-test',
        httpClient: MockClient((request) async {
          final path = request.url.path;
          calls.add('${request.method} $path');
          http.Response json(int status, Object? body) => http.Response(
            jsonEncode(body),
            status,
            headers: {'content-type': 'application/json'},
            request: request,
          );
          if (path.startsWith('/storage/v1/object/meal-images') &&
              request.method == 'POST') {
            return json(200, {'Key': 'meal-images/x.jpg'});
          }
          if (path == '/storage/v1/object/meal-images' &&
              request.method == 'DELETE') {
            return json(200, <Object>[]);
          }
          switch (path) {
            case '/rest/v1/user_accounts':
              return http.Response(
                jsonEncode({'timezone': 'UTC'}),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            case '/rest/v1/rpc/create_meal_photo_draft':
              requestKey =
                  (jsonDecode(request.body)
                          as Map<String, dynamic>)['request_idempotency_key']
                      as String;
              if (draftReplyLost) throw http.ClientException('offline');
              return json(200, {'meal_id': _mealId});
            case '/functions/v1/meal-analyze':
              return json(analysisStatus, {'error': 'meal_analysis_failed'});
            case '/rest/v1/meals':
              // Honours the filters the way PostgREST does: a row carrying
              // the request's key, and a draft when a status is asked for.
              mealQueries.add(request.url.queryParameters);
              final query = request.url.queryParameters;
              final found =
                  query['idempotency_key'] == 'eq.$requestKey' &&
                  (query['status'] == null || query['status'] == 'eq.draft');
              return json(200, [
                if (found) {'id': _mealId},
              ]);
            case '/rest/v1/rpc/delete_my_meal':
              if (deleteFails) throw http.ClientException('offline');
              deleteTargets.add(
                (jsonDecode(request.body)
                        as Map<String, dynamic>)['target_meal_id']
                    as String,
              );
              return json(200, true);
          }
          return json(404, {'message': 'unexpected $path'});
        }),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await client.auth.setInitialSession(jsonEncode(_session()));
      return SupabaseNutritionRepository(client);
    }

    for (final status in [503, 429, 422]) {
      test('$status deletes the draft', () async {
        final repository = await signedIn(analysisStatus: status);
        await expectLater(
          repository.analyzeMealPhoto(
            date: DateTime(2026, 10, 24),
            mealType: 'lunch',
            bytes: Uint8List.fromList(const [1, 2, 3]),
          ),
          throwsA(isA<MealPhotoFailure>()),
        );
        expect(deleteTargets, [_mealId]);
        expect(mealQueries, isEmpty, reason: 'the draft id was known');
      });
    }

    test('a draft whose creation reply was lost is found by its key and '
        'deleted', () async {
      final repository = await signedIn(
        analysisStatus: 503,
        draftReplyLost: true,
      );
      await expectLater(
        repository.analyzeMealPhoto(
          date: DateTime(2026, 10, 24),
          mealType: 'lunch',
          bytes: Uint8List.fromList(const [1, 2, 3]),
        ),
        throwsA(isA<MealPhotoFailure>()),
      );
      expect(mealQueries.single, containsPair('status', 'eq.draft'));
      expect(
        mealQueries.single,
        containsPair('idempotency_key', 'eq.$requestKey'),
      );
      expect(deleteTargets, [_mealId]);
    });

    test('asking whether a meal was saved filters by its key', () async {
      final repository = await signedIn(analysisStatus: 503);
      requestKey = 'key-1';
      expect(await repository.isMealSaved('key-1'), isTrue);
      expect(await repository.isMealSaved('key-2'), isFalse);
      expect(mealQueries.map((query) => query['idempotency_key']), [
        'eq.key-1',
        'eq.key-2',
      ]);
    });

    test('a delete that fails does not hide why the photo failed', () async {
      final repository = await signedIn(analysisStatus: 503, deleteFails: true);
      await expectLater(
        repository.analyzeMealPhoto(
          date: DateTime(2026, 10, 24),
          mealType: 'lunch',
          bytes: Uint8List.fromList(const [1, 2, 3]),
        ),
        throwsA(
          isA<MealPhotoFailure>().having((e) => e.step, 'step', 'analysis'),
        ),
      );
    });
  });
}

Map<String, dynamic> _session() => {
  'access_token': _accessToken(),
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
};

String _accessToken() {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1));
  return [
    part({'alg': 'HS256', 'typ': 'JWT'}),
    part({'sub': _userId, 'exp': exp.millisecondsSinceEpoch ~/ 1000}),
    'signature',
  ].join('.');
}
