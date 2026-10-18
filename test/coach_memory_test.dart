import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/account_screen.dart';
import 'package:tracend/features/coach/memory/coach_memory.dart';
import 'package:tracend/features/coach/memory/coach_memory_repository.dart';
import 'package:tracend/features/coach/memory/coach_memory_screen.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

final _confirmed = DateTime.utc(2026, 9, 2, 9);

CoachFact _fact(
  String id,
  CoachFactKind kind,
  String statement, {
  CoachFactSource source = CoachFactSource.athleteTyped,
  DateTime? reconfirmAt,
  bool due = false,
}) => CoachFact(
  id: id,
  lineageId: id,
  version: 1,
  kind: kind,
  subject: coachFactSubjectFor(statement),
  statement: statement,
  source: source,
  confirmedAt: _confirmed,
  reconfirmAt: reconfirmAt,
  reconfirmDue: due,
);

CoachNote _note(
  String id,
  String summary, {
  bool advice = false,
  CoachNoteFollowThrough? through,
}) => CoachNote(
  id: id,
  entryKind: advice ? 'advice' : 'conversation',
  noteDate: DateTime.utc(2026, 10, 12),
  summary: summary,
  followThrough: through,
);

/// An in-memory stand-in for the database that records what the athlete did.
class _Memory implements CoachMemoryRepository {
  _Memory(this.memory);

  CoachMemory memory;
  final calls = <String>[];
  int loads = 0;
  int loadFailures = 0;
  Object? writeFailure;

  @override
  Future<CoachMemory> load() async {
    loads++;
    if (loadFailures > 0) {
      loadFailures--;
      throw Exception('offline');
    }
    return memory;
  }

  @override
  Future<CoachFact> saveFact({
    required CoachFactKind kind,
    required String subject,
    required String statement,
    CoachFactSource source = CoachFactSource.athleteTyped,
    String? supersedes,
  }) async {
    calls.add(
      'save ${kind.wire} | $subject | $statement | ${supersedes ?? '-'}',
    );
    if (writeFailure != null) throw writeFailure!;
    final saved = _fact('new-${calls.length}', kind, statement);
    memory = CoachMemory(
      facts: [
        for (final fact in memory.facts)
          if (fact.id != supersedes) fact,
        saved,
      ],
      notes: memory.notes,
    );
    return saved;
  }

  @override
  Future<CoachFact> reconfirmFact(String factId) async {
    calls.add('reconfirm $factId');
    if (writeFailure != null) throw writeFailure!;
    final fact = memory.facts.firstWhere((fact) => fact.id == factId);
    memory = CoachMemory(
      facts: [
        for (final item in memory.facts)
          if (item.id != factId) item,
        _fact(
          factId,
          fact.kind,
          fact.statement,
          reconfirmAt: DateTime.utc(2026, 12),
        ),
      ],
      notes: memory.notes,
    );
    return fact;
  }

  @override
  Future<void> deleteFact(String factId) async {
    calls.add('delete fact $factId');
    if (writeFailure != null) throw writeFailure!;
    memory = CoachMemory(
      facts: [
        for (final fact in memory.facts)
          if (fact.id != factId) fact,
      ],
      notes: memory.notes,
    );
  }

  @override
  Future<void> deleteNote(String noteId) async {
    calls.add('delete note $noteId');
    if (writeFailure != null) throw writeFailure!;
    memory = CoachMemory(
      facts: memory.facts,
      notes: [
        for (final note in memory.notes)
          if (note.id != noteId) note,
      ],
    );
  }

  @override
  Future<void> forgetAll() async {
    calls.add('forget all');
    if (writeFailure != null) throw writeFailure!;
    memory = const CoachMemory();
  }
}

Future<void> _open(WidgetTester tester, _Memory repository) async {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.dark,
      home: CoachMemoryScreen(repository: repository),
    ),
  );
  await tester.pumpAndSettle();
}

/// Lets a toast finish so no timer is left running.
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pumpAndSettle(TracendToast.visibleFor);
}

Finder _button(String label) => find.widgetWithText(FilledButton, label);

_Memory _filled() => _Memory(
  CoachMemory(
    facts: [
      _fact(
        'f1',
        CoachFactKind.injuryLimitation,
        'Left knee hurts on deep squats',
        source: CoachFactSource.coachSuggestionConfirmed,
        reconfirmAt: DateTime.utc(2026, 9, 30),
        due: true,
      ),
      _fact('f2', CoachFactKind.foodDislike, 'Dislikes mushrooms'),
      _fact(
        'f3',
        CoachFactKind.scheduleConstraint,
        'Can train 3 days a week',
        reconfirmAt: DateTime.utc(2026, 12, 1),
      ),
    ],
    notes: [
      _note('n1', 'Asked about training. Mentioned pain.'),
      _note(
        'n2',
        'Coach proposed “Train 4 days a week”; you approved it on 2026-10-05.',
        advice: true,
        through: const CoachNoteFollowThrough(
          status: 'partly',
          detail: '2 of 4 sessions from 2026-10-06 to 2026-10-12',
        ),
      ),
    ],
  ),
);

void main() {
  group('the models', () {
    test('a fact reads its wire shape and an unknown kind becomes other', () {
      final fact = CoachFact.fromJson({
        'id': 'f1',
        'lineage_id': 'f1',
        'version': 2,
        'kind': 'injury_limitation',
        'subject': 'left knee',
        'statement': 'Left knee hurts',
        'source': 'coach_suggestion_confirmed',
        'confirmed_at': '2026-09-02T09:00:00+00:00',
        'reconfirm_at': '2026-09-30T09:00:00+00:00',
        'reconfirm_due': true,
      });
      expect(fact.kind, CoachFactKind.injuryLimitation);
      expect(fact.source, CoachFactSource.coachSuggestionConfirmed);
      expect(fact.version, 2);
      expect(fact.reconfirmDue, isTrue);
      expect(fact.reconfirmAt, DateTime.utc(2026, 9, 30, 9));
      final unknown = CoachFact.fromJson({
        'id': 'f2',
        'lineage_id': 'f2',
        'version': 1,
        'kind': 'something_new',
        'subject': 'x',
        'statement': 'X',
        'source': 'a_new_source',
        'confirmed_at': '2026-09-02T09:00:00+00:00',
        'reconfirm_at': null,
        'reconfirm_due': false,
      });
      expect(unknown.kind, CoachFactKind.otherPreference);
      expect(unknown.source, CoachFactSource.athleteTyped);
      expect(unknown.reconfirmAt, isNull);
    });

    test('a fact or note this build cannot read is left out of the memory', () {
      final memory = CoachMemory.fromJson({
        'facts': [
          {
            'id': 'f1',
            'lineage_id': 'f1',
            'version': 1,
            'kind': 'equipment',
            'subject': 'bands',
            'statement': 'Has bands',
            'source': 'athlete_typed',
            'confirmed_at': '2026-09-02T09:00:00+00:00',
          },
          {'id': 'broken'},
          'text',
        ],
        'notes': [
          {
            'id': 'n1',
            'entry_kind': 'conversation',
            'note_date': '2026-10-12',
            'summary': 'Asked about training.',
          },
          {'id': 'broken'},
        ],
        'limits': {'max_facts': 60, 'max_notes': 20, 'note_days': 60},
      });
      expect(memory.facts.map((fact) => fact.id), ['f1']);
      expect(memory.notes.map((note) => note.id), ['n1']);
      expect(memory.limits.maxFacts, 60);
      expect(CoachMemory.fromJson(const {}).isEmpty, isTrue);
    });

    test('a fact label is one lower-case line of at most 60 characters', () {
      expect(coachFactSubjectFor('  Left KNEE hurts.  '), 'left knee hurts');
      expect(coachFactSubjectFor('A\n\nB   C!'), 'a b c');
      final long = coachFactSubjectFor('word ' * 30);
      expect(long.length, lessThanOrEqualTo(60));
      expect(long.endsWith(' '), isFalse);
      expect(coachFactSubjectFor('x' * 80).length, 60);
    });

    test('a note says how its advice turned out', () {
      expect(
        const CoachNoteFollowThrough(status: 'followed', detail: '').label,
        'You followed it',
      );
      expect(
        const CoachNoteFollowThrough(status: 'partly', detail: '').label,
        'You followed it in part',
      );
      expect(
        const CoachNoteFollowThrough(status: 'not_followed', detail: '').label,
        'Not followed',
      );
    });
  });

  group('What Coach remembers', () {
    testWidgets('lists facts by kind with where they came from and when', (
      tester,
    ) async {
      await _open(tester, _filled());
      expect(find.text('What Coach remembers'), findsOneWidget);
      expect(find.text('Injuries and limitations'), findsOneWidget);
      expect(find.text('Foods you dislike'), findsOneWidget);
      expect(find.text('Schedule and life'), findsOneWidget);
      expect(find.text('Left knee hurts on deep squats'), findsOneWidget);
      expect(
        find.textContaining('Confirmed 2 Sep 2026 · Coach suggested it'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Confirmed 2 Sep 2026 · You typed it'),
        findsNWidgets(2),
      );
      expect(
        find.textContaining('Check that this still applies'),
        findsOneWidget,
      );
    });

    testWidgets('lists Coach\'s notes with their dates and follow-through', (
      tester,
    ) async {
      await _open(tester, _filled());
      expect(find.text('Coach’s notes'), findsOneWidget);
      expect(
        find.text('Asked about training. Mentioned pain.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('12 Oct 2026 · You followed it in part (2 of 4'),
        findsOneWidget,
      );
      expect(find.byTooltip('Delete note'), findsNWidgets(2));
    });

    testWidgets(
      'says plainly when nothing is saved and offers nothing to forget',
      (tester) async {
        await _open(tester, _Memory(const CoachMemory()));
        expect(find.textContaining('Nothing is saved yet'), findsOneWidget);
        expect(find.textContaining('No notes yet'), findsOneWidget);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Forget everything'),
              )
              .onPressed,
          isNull,
        );
      },
    );

    testWidgets('a memory that cannot load says so and tries again', (
      tester,
    ) async {
      final repository = _filled()..loadFailures = 1;
      await _open(tester, repository);
      expect(find.text('Coach’s memory could not load'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Dislikes mushrooms'), findsOneWidget);
      expect(repository.loads, 2);
    });

    testWidgets('adding a fact saves the kind chosen and the words typed', (
      tester,
    ) async {
      final repository = _Memory(const CoachMemory());
      await _open(tester, repository);
      await tester.tap(find.text('Add something Coach should know'));
      await tester.pumpAndSettle();
      expect(find.text('Add a fact'), findsOneWidget);
      expect(_saveEnabled(tester), isFalse);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Equipment'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Has a barbell at home.');
      await tester.pump();
      expect(_saveEnabled(tester), isTrue);
      await tester.tap(_button('Save'));
      await _settle(tester);
      expect(repository.calls, [
        'save equipment | has a barbell at home | Has a barbell at home. | -',
      ]);
      expect(find.text('Has a barbell at home.'), findsOneWidget);
      expect(find.text('Equipment'), findsOneWidget);
    });

    testWidgets(
      'editing replaces the fact it opened and keeps its words to start',
      (tester) async {
        final repository = _filled();
        await _open(tester, repository);
        await tester.tap(find.text('Dislikes mushrooms'));
        await tester.pumpAndSettle();
        expect(
          find.text('You typed it. Confirmed 2 Sep 2026.'),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
        await tester.pumpAndSettle();
        expect(find.text('Edit this fact'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Dislikes mushrooms',
        );
        expect(_saveEnabled(tester), isFalse);
        await tester.enterText(
          find.byType(TextField),
          'Dislikes mushrooms and olives',
        );
        await tester.pump();
        await tester.tap(_button('Save'));
        await _settle(tester);
        expect(repository.calls, [
          'save food_dislike | dislikes mushrooms and olives | Dislikes mushrooms and olives | f2',
        ]);
        expect(find.text('Dislikes mushrooms and olives'), findsOneWidget);
        expect(find.text('Dislikes mushrooms'), findsNothing);
      },
    );

    testWidgets('changing only the kind is a change too', (tester) async {
      final repository = _filled();
      await _open(tester, repository);
      await tester.tap(find.text('Dislikes mushrooms'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(ChoiceChip, 'Allergies and intolerances'),
      );
      await tester.pump();
      expect(_saveEnabled(tester), isTrue);
      await tester.tap(_button('Save'));
      await _settle(tester);
      expect(
        repository.calls.single,
        startsWith('save allergy | dislikes mushrooms'),
      );
    });

    testWidgets('a failed save keeps what was typed and says why', (
      tester,
    ) async {
      final repository = _Memory(const CoachMemory())
        ..writeFailure = Exception('offline');
      await _open(tester, repository);
      await tester.tap(find.text('Add something Coach should know'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Has a bench');
      await tester.pump();
      await tester.tap(_button('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('It could not be saved'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Has a bench',
      );
      repository.writeFailure = null;
      await tester.tap(_button('Save'));
      await _settle(tester);
      expect(find.text('Has a bench'), findsOneWidget);
    });

    testWidgets('the limit of saved facts is explained, not hidden', (
      tester,
    ) async {
      final repository = _Memory(const CoachMemory())
        ..writeFailure = const PostgrestException(
          message: 'too many saved facts',
          code: '54000',
        );
      await _open(tester, repository);
      await tester.tap(find.text('Add something Coach should know'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'One more');
      await tester.pump();
      await tester.tap(_button('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('saved the most Coach keeps'), findsOneWidget);
    });

    testWidgets(
      'with the most facts saved, adding is switched off with the reason',
      (tester) async {
        final repository = _Memory(
          CoachMemory(
            facts: [
              for (var i = 0; i < 60; i++)
                _fact('f$i', CoachFactKind.otherPreference, 'Preference $i'),
            ],
          ),
        );
        await _open(tester, repository);
        await tester.scrollUntilVisible(
          find.textContaining('Delete one to add another'),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.textContaining('Delete one to add another'),
          findsOneWidget,
        );
        await tester.tap(find.text('Add something Coach should know'));
        await tester.pumpAndSettle();
        expect(find.text('Add a fact'), findsNothing);
      },
    );

    testWidgets('"Still true" confirms an old fact again', (tester) async {
      final repository = _filled();
      await _open(tester, repository);
      await tester.tap(find.text('Left knee hurts on deep squats'));
      await tester.pumpAndSettle();
      expect(
        find.text('Coach would like to check that this still applies.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Still true'));
      await _settle(tester);
      expect(repository.calls, ['reconfirm f1']);
      expect(
        find.textContaining('Check that this still applies'),
        findsNothing,
      );
    });

    testWidgets('a fact that never lapses has no "Still true"', (tester) async {
      await _open(tester, _filled());
      await tester.tap(find.text('Dislikes mushrooms'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Still true'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Edit'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Delete'), findsOneWidget);
    });

    testWidgets('deleting a fact asks first and then removes it', (
      tester,
    ) async {
      final repository = _filled();
      await _open(tester, repository);
      await tester.tap(find.text('Dislikes mushrooms'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this fact?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.calls, isEmpty);
      expect(find.text('Dislikes mushrooms'), findsOneWidget);

      await tester.tap(find.text('Dislikes mushrooms'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete fact'));
      await _settle(tester);
      expect(repository.calls, ['delete fact f2']);
      expect(find.text('Dislikes mushrooms'), findsNothing);
    });

    testWidgets('a delete that fails changes nothing and says so', (
      tester,
    ) async {
      final repository = _filled()..writeFailure = Exception('offline');
      await _open(tester, repository);
      await tester.tap(find.text('Dislikes mushrooms'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete fact'));
      await tester.pumpAndSettle();
      expect(
        find.text('The fact could not be deleted. Nothing was changed.'),
        findsOneWidget,
      );
      expect(find.text('Dislikes mushrooms'), findsOneWidget);
      await _settle(tester);
    });

    testWidgets('deleting a note asks first and then removes it', (
      tester,
    ) async {
      final repository = _filled();
      await _open(tester, repository);
      await tester.tap(find.byTooltip('Delete note').first);
      await tester.pumpAndSettle();
      expect(find.text('Delete this note?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.calls, isEmpty);
      await tester.tap(find.byTooltip('Delete note').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete note').last);
      await _settle(tester);
      expect(repository.calls, ['delete note n1']);
      expect(find.text('Asked about training. Mentioned pain.'), findsNothing);
      expect(find.byTooltip('Delete note'), findsOneWidget);
    });

    testWidgets(
      '"Forget everything" asks first, counts what goes, and clears it',
      (tester) async {
        final repository = _filled();
        await _open(tester, repository);
        await tester.ensureVisible(find.text('Forget everything'));
        await tester.tap(find.text('Forget everything'));
        await tester.pumpAndSettle();
        expect(find.text('Forget everything?'), findsOneWidget);
        expect(
          find.textContaining('all 3 saved facts and 2 notes'),
          findsOneWidget,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(repository.calls, isEmpty);

        await tester.tap(find.text('Forget everything'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Forget everything').last);
        await _settle(tester);
        expect(repository.calls, ['forget all']);
        expect(find.textContaining('Nothing is saved yet'), findsOneWidget);
        expect(find.text('Dislikes mushrooms'), findsNothing);
      },
    );
  });

  group('Account', () {
    const configured = AppEnvironment(
      name: 'test',
      supabaseUrl: 'https://example.supabase.co',
      supabasePublishableKey: 'test-key',
    );

    testWidgets('lists "What Coach remembers" and opens it', (tester) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _filled();
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: AccountScreen(environment: configured, memory: repository),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('What Coach remembers'), 200);
      await tester.tap(find.text('What Coach remembers'));
      await tester.pumpAndSettle();
      expect(find.text('Dislikes mushrooms'), findsOneWidget);
      expect(repository.loads, 1);
    });

    testWidgets('has no memory row without a backend', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: const AccountScreen(
            environment: AppEnvironment(
              name: 'test',
              supabaseUrl: '',
              supabasePublishableKey: '',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('What Coach remembers'), findsNothing);
    });
  });
}

bool _saveEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_button('Save')).onPressed != null;
