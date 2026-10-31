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

/// A PostgREST stand-in that honours every column of the `order` parameter
/// the way the real one does: descending by default is postgrest-dart's, so
/// the repository must ask for ascending itself.
class _Server {
  _Server([List<Map<String, dynamic>>? rows])
    : rows =
          rows ??
          [
            _row('a1', 'assistant', 'Keep today’s session.', 1),
            _row('u1', 'user', 'Should I train legs today?', 0),
            _row('a2', 'assistant', 'Eat protein after.', 3),
            _row('u2', 'user', 'And what should I eat?', 2),
          ];

  final List<Map<String, dynamic>> rows;

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
          final keys = [
            for (final part
                in (request.url.queryParameters['order'] ?? '')
                    .split(',')
                    .where((part) => part.isNotEmpty))
              (part.split('.').first, part.contains('.asc')),
          ];
          final sorted = [...rows]
            ..sort((a, b) {
              for (final (column, ascending) in keys) {
                final compared = '${a[column]}'.compareTo('${b[column]}');
                if (compared != 0) return ascending ? compared : -compared;
              }
              return 0;
            });
          final limit = int.tryParse(
            request.url.queryParameters['limit'] ?? '',
          );
          return json(limit == null ? sorted : sorted.take(limit).toList());
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

Future<void> _open(
  WidgetTester tester,
  Size size, {
  List<Map<String, dynamic>>? rows,
}) async {
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
            _Server(rows).client,
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

Map<String, dynamic> _at(String id, String role, int second) => {
  'id': id,
  'thread_id': _threadId,
  'role': role,
  'content': id,
  'created_at': DateTime.utc(
    2026,
    10,
    24,
    8,
  ).add(Duration(seconds: second)).toIso8601String(),
};

void main() {
  test('a long conversation loads its newest messages, in reading order, '
      'whichever way ties fall', () async {
    // 100 question and answer pairs (each pair shares an instant) and one
    // newer lone message: the newest 200 cut the oldest pair in two.
    final rows = [
      for (var i = 0; i < 100; i++) ...[
        _at('a${i.toString().padLeft(3, '0')}', 'assistant', i),
        _at('u${i.toString().padLeft(3, '0')}', 'user', i),
      ],
      _at('z', 'assistant', 500),
    ];
    final loaded = await SupabaseCoachRepository(
      _Server(rows).client,
      now: () => _now,
    ).loadMessages(_threadId);

    // The cut left the oldest pair's answer without its question: dropped.
    expect(loaded, hasLength(coachMessageWindow - 1));
    expect(
      [for (final message in loaded) message.id],
      [
        for (var i = 1; i < 100; i++) ...[
          'u${i.toString().padLeft(3, '0')}',
          'a${i.toString().padLeft(3, '0')}',
        ],
        'z',
      ],
    );
  });

  test('a conversation under the window loads whole', () async {
    final loaded = await SupabaseCoachRepository(
      _Server().client,
      now: () => _now,
    ).loadMessages(_threadId);
    expect(
      [for (final message in loaded) message.id],
      ['u1', 'a1', 'u2', 'a2'],
    );
  });

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

  testWidgets('a question and its answer stored in the same instant read '
      'question first, whatever their ids', (tester) async {
    // One transaction stores both rows, so they share created_at; these ids
    // would put the answer first if the id settled the tie.
    await _open(
      tester,
      const Size(800, 2400),
      rows: [
        _row('b-question', 'user', 'Should I train legs today?', 0),
        _row('a-answer', 'assistant', 'Keep today’s session.', 0),
      ],
    );
    expect(
      tester.getTopLeft(find.text('Should I train legs today?')).dy,
      lessThan(tester.getTopLeft(find.text('Keep today’s session.')).dy),
    );
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
