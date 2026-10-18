import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/memory/coach_memory.dart';

Map<String, dynamic> _fixture(String name) => Map<String, dynamic>.from(
  json.decode(File('test/contract/fixtures/$name').readAsStringSync()) as Map,
);

List<String> _keys(Object? value) =>
    (Map<String, dynamic>.from(value as Map).keys.toList()..sort());

void main() {
  // The key lists are the contract: add keys, never remove or rename them. The
  // same lists are asserted against the database in
  // supabase/tests/database/coach_memory_test.sql.
  group('Coach memory contract 1.0', () {
    test('get_my_coach_memory_v1 carries exactly its keys', () {
      final memory = _fixture('coach_memory_v1_0.json');
      expect(memory['schema_version'], '1.0');
      expect(_keys(memory), ['facts', 'limits', 'notes', 'schema_version']);
      for (final fact in memory['facts'] as List) {
        expect(_keys(fact), [
          'confirmed_at',
          'id',
          'kind',
          'lineage_id',
          'reconfirm_at',
          'reconfirm_due',
          'source',
          'statement',
          'subject',
          'version',
        ]);
      }
      for (final note in memory['notes'] as List) {
        expect(_keys(note), [
          'advice',
          'commitments',
          'concerns',
          'created_at',
          'entry_kind',
          'expires_at',
          'follow_through',
          'id',
          'message_ids',
          'note_date',
          'proposal_id',
          'summary',
          'thread_id',
          'topics',
        ]);
      }
      expect(_keys(memory['limits']), ['max_facts', 'max_notes', 'note_days']);
    });

    test('the app reads the facts, the notes and the limits', () {
      final memory = CoachMemory.fromJson(_fixture('coach_memory_v1_0.json'));
      expect(memory.facts.map((fact) => fact.kind), [
        CoachFactKind.injuryLimitation,
        CoachFactKind.foodDislike,
      ]);
      expect(
        memory.facts.first.source,
        CoachFactSource.coachSuggestionConfirmed,
      );
      expect(memory.facts.first.reconfirmAt, isNotNull);
      expect(memory.facts.last.version, 2);
      expect(
        memory.notes.single.summary,
        'Asked about training. Mentioned pain.',
      );
      expect(memory.limits.maxFacts, 60);
      expect(memory.factsFull, isFalse);
    });

    test('every kind and source the app names is one the database accepts', () {
      final sql = File(
        'supabase/migrations/20261018150020_coach_memory.sql',
      ).readAsStringSync();
      final kinds = RegExp(
        r"kind in \(\s*([^)]*)\)",
      ).firstMatch(sql)!.group(1)!;
      expect(
        RegExp(
          r"'([a-z_]+)'",
        ).allMatches(kinds).map((m) => m.group(1)).toList(),
        CoachFactKind.values.map((kind) => kind.wire).toList(),
      );
      final sources = RegExp(
        r"source in \(([^)]*)\)",
      ).firstMatch(sql)!.group(1)!;
      expect(
        RegExp(
          r"'([a-z_]+)'",
        ).allMatches(sources).map((m) => m.group(1)).toList(),
        CoachFactSource.values.map((source) => source.wire).toList(),
      );
    });

    test('saving a fact answers with the fact', () {
      final saved = _fixture('coach_fact_saved_v1_0.json');
      expect(_keys(saved), ['fact', 'schema_version']);
      expect(
        CoachFact.fromJson(Map<String, dynamic>.from(saved['fact'] as Map)).id,
        '6a1f3c52-7d0e-4b8a-9c21-5e4d3b2a1f00',
      );
    });

    test('opening a conversation and forgetting answer exactly their keys', () {
      expect(_keys(_fixture('coach_thread_created_v1_0.json')), [
        'remember',
        'schema_version',
        'thread_id',
      ]);
      expect(_keys(_fixture('coach_memory_forgotten_v1_0.json')), [
        'facts_deleted',
        'notes_deleted',
        'schema_version',
      ]);
    });

    test('the thread list says which conversations are not remembered', () {
      final threads = (_fixture('coach_threads_v1_0.json')['threads'] as List)
          .map(
            (thread) =>
                CoachThread.fromJson(Map<String, dynamic>.from(thread as Map)),
          )
          .toList();
      expect(threads.map((thread) => thread.remember), [true, false]);
      for (final thread
          in _fixture('coach_threads_v1_0.json')['threads'] as List) {
        expect(_keys(thread), [
          'id',
          'last_message_at',
          'remember',
          'title',
          'updated_at',
        ]);
      }
    });
  });
}
