import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/coach_screen.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';

const _threadId = '11111111-1111-4111-8111-111111111111';
final _now = DateTime.utc(2026, 10, 24, 9);

Map<String, dynamic> _row(String id, String role, String text, int minute) => {
  'id': id,
  'thread_id': _threadId,
  'role': role,
  'content': text,
  'created_at': '2026-10-24T08:0$minute:00Z',
};

/// A PostgREST stand-in that honours the `order` parameter the way the real
/// one does, rows without a direction included: descending by default is
/// postgrest-dart's, so the repository must ask for ascending itself.
class _Server {
  final rows = [
    _row('a1', 'assistant', 'Keep today’s session.', 1),
    _row('u1', 'user', 'Should I train legs today?', 0),
    _row('a2', 'assistant', 'Eat protein after.', 3),
    _row('u2', 'user', 'And what should I eat?', 2),
  ];

  late final client = SupabaseClient(
    'https://tracend-test.supabase.co',
    'publishable-test',
    httpClient: MockClient((request) async {
      http.Response json(Object value) => http.Response(
        jsonEncode(value),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
      switch (request.url.path) {
        case '/rest/v1/rpc/get_my_coach_threads':
          return json({
            'threads': [
              {
                'id': _threadId,
                'title': 'Should I train legs today?',
                'updated_at': '2026-10-24T08:03:00Z',
              },
            ],
          });
        case '/rest/v1/rpc/get_my_coach_context_status':
          return json({'sources': <Object>[]});
        case '/rest/v1/coach_messages':
          final sorted = [...rows];
          final order = request.url.queryParameters['order'] ?? '';
          // Only the first column matters here: created_at.
          final ascending = order.split(',').first.contains('.asc');
          sorted.sort(
            (a, b) => (a['created_at'] as String).compareTo(
              b['created_at'] as String,
            ),
          );
          return json(ascending ? sorted : sorted.reversed.toList());
      }
      return json(<Object>[]);
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
}

class _Memory implements CoachThreadMemory {
  @override
  Future<String?> lastThreadId() async => _threadId;

  @override
  Future<void> remember(String threadId) async {}
}

Future<void> _open(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.dark,
      home: Scaffold(
        body: CoachScreen(
          repository: SupabaseCoachRepository(
            _Server().client,
            now: () => _now,
          ),
          threadMemory: _Memory(),
          now: () => _now,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a restored conversation reads question then answer, newest '
      'last', (tester) async {
    await _open(tester, const Size(800, 2400));
    final tops = [
      for (final text in [
        'Should I train legs today?',
        'Keep today’s session.',
        'And what should I eat?',
        'Eat protein after.',
      ])
        tester.getTopLeft(find.text(text)).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(tops.toSet(), hasLength(4));
  });

  testWidgets('a restored conversation opens on its newest message', (
    tester,
  ) async {
    await _open(tester, const Size(320, 260));
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    expect(scroll.position.pixels, scroll.position.maxScrollExtent);
    expect(find.text('Eat protein after.'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text('Eat protein after.')).dy,
      lessThanOrEqualTo(260),
    );
    expect(find.text('Should I train legs today?'), findsNothing);
  });
}
