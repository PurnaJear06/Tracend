import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/coach/memory/coach_memory.dart';

/// Reads and changes what Coach remembers. Every change is the athlete's own
/// action (a typed fact, a confirmed suggestion, a delete); Coach has no way to
/// call any of these.
abstract interface class CoachMemoryRepository {
  Future<CoachMemory> load();

  /// Saves a fact. With [supersedes] it replaces that fact as a new version;
  /// without it, a fact with the same kind and subject is replaced the same way.
  Future<CoachFact> saveFact({
    required CoachFactKind kind,
    required String subject,
    required String statement,
    CoachFactSource source = CoachFactSource.athleteTyped,
    String? supersedes,
  });

  /// "Still true": the same fact with a fresh confirmation date.
  Future<CoachFact> reconfirmFact(String factId);

  /// Deletes every version of a fact.
  Future<void> deleteFact(String factId);
  Future<void> deleteNote(String noteId);

  /// Deletes every fact and note. Conversations stay.
  Future<void> forgetAll();
}

/// Postgres code for "too many saved facts" (54000).
bool isFactLimitError(Object error) =>
    error is PostgrestException && error.code == '54000';

class SupabaseCoachMemoryRepository implements CoachMemoryRepository {
  const SupabaseCoachMemoryRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<CoachMemory> load() async => CoachMemory.fromJson(
    Map<String, dynamic>.from(
      await _client.rpc('get_my_coach_memory_v1') as Map,
    ),
  );

  @override
  Future<CoachFact> saveFact({
    required CoachFactKind kind,
    required String subject,
    required String statement,
    CoachFactSource source = CoachFactSource.athleteTyped,
    String? supersedes,
  }) async => _fact(
    await _client.rpc(
      'save_coach_fact_v1',
      params: {
        'p_kind': kind.wire,
        'p_subject': subject,
        'p_statement': statement,
        'p_source': source.wire,
        'p_supersedes': supersedes,
      },
    ),
  );

  @override
  Future<CoachFact> reconfirmFact(String factId) async => _fact(
    await _client.rpc('reconfirm_coach_fact_v1', params: {'p_fact_id': factId}),
  );

  @override
  Future<void> deleteFact(String factId) async {
    await _client.rpc('delete_coach_fact_v1', params: {'p_fact_id': factId});
  }

  @override
  Future<void> deleteNote(String noteId) async {
    await _client.rpc('delete_coach_note_v1', params: {'p_note_id': noteId});
  }

  @override
  Future<void> forgetAll() async {
    await _client.rpc('forget_coach_memory_v1');
  }

  CoachFact _fact(Object? answer) => CoachFact.fromJson(
    Map<String, dynamic>.from(
      (Map<String, dynamic>.from(answer as Map))['fact'] as Map,
    ),
  );
}

/// Without a backend there is nothing to remember.
class FixtureCoachMemoryRepository implements CoachMemoryRepository {
  const FixtureCoachMemoryRepository();

  @override
  Future<CoachMemory> load() async => const CoachMemory();

  @override
  Future<CoachFact> saveFact({
    required CoachFactKind kind,
    required String subject,
    required String statement,
    CoachFactSource source = CoachFactSource.athleteTyped,
    String? supersedes,
  }) => throw StateError('Configure Supabase to save what Coach remembers.');

  @override
  Future<CoachFact> reconfirmFact(String factId) =>
      throw StateError('Configure Supabase to save what Coach remembers.');

  @override
  Future<void> deleteFact(String factId) async {}

  @override
  Future<void> deleteNote(String noteId) async {}

  @override
  Future<void> forgetAll() async {}
}
