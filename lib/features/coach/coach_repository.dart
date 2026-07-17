import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class CoachDecision {
  const CoachDecision({
    required this.id,
    required this.localDate,
    required this.trainingAction,
    required this.trainingSummary,
    required this.nutritionAction,
    required this.nutritionSummary,
    required this.finalDecision,
    required this.reason,
    required this.confidence,
    required this.evidence,
    required this.missingData,
    required this.riskFlags,
    required this.createdAt,
  });

  factory CoachDecision.fromJson(Map<String, dynamic> json) {
    final training = Map<String, dynamic>.from(json['training'] as Map);
    final nutrition = Map<String, dynamic>.from(json['nutrition'] as Map);
    final head = Map<String, dynamic>.from(json['head_coach'] as Map);
    return CoachDecision(
      id: json['id'] as String,
      localDate: json['local_date'] as String,
      trainingAction: training['action'] as String,
      trainingSummary: training['summary'] as String,
      nutritionAction: nutrition['action'] as String,
      nutritionSummary: nutrition['summary'] as String,
      finalDecision: head['final_decision'] as String,
      reason: head['reason'] as String,
      confidence: json['confidence'] as String,
      evidence: (json['evidence'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
      missingData: List<String>.from(json['missing_data'] as List? ?? const []),
      riskFlags: List<String>.from(json['risk_flags'] as List? ?? const []),
      createdAt: DateTime.parse(
        json['created_at'] as String? ??
            DateTime.now().toUtc().toIso8601String(),
      ),
    );
  }

  final String id;
  final String localDate;
  final String trainingAction;
  final String trainingSummary;
  final String nutritionAction;
  final String nutritionSummary;
  final String finalDecision;
  final String reason;
  final String confidence;
  final List<Map<String, dynamic>> evidence;
  final List<String> missingData;
  final List<String> riskFlags;
  final DateTime createdAt;
}

class CoachThread {
  const CoachThread({
    required this.id,
    required this.title,
    required this.updatedAt,
  });
  final String id;
  final String title;
  final DateTime updatedAt;
}

class CoachContextSource {
  const CoachContextSource({
    required this.key,
    required this.label,
    required this.available,
    required this.records,
    this.latestDate,
  });

  factory CoachContextSource.fromJson(Map<String, dynamic> json) =>
      CoachContextSource(
        key: json['key'] as String,
        label: json['label'] as String,
        available: json['available'] as bool? ?? false,
        records: (json['records'] as num?)?.toInt() ?? 0,
        latestDate: json['latest_date'] as String?,
      );

  final String key;
  final String label;
  final bool available;
  final int records;
  final String? latestDate;
}

abstract interface class CoachContextRepository {
  Future<List<CoachContextSource>> loadContextStatus();
}

class CoachMessage {
  const CoachMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.evidence = const [],
    this.missingData = const [],
    this.safetyState = 'allowed',
    this.suggestedFollowUps = const [],
    this.modelProvider,
    this.model,
    this.reasoningChain = const [],
  });
  final String id;
  final String role;
  final String content;
  final DateTime createdAt;
  final List<Map<String, dynamic>> evidence;
  final List<String> missingData;
  final String safetyState;
  final List<String> suggestedFollowUps;
  final String? modelProvider;
  final String? model;
  final List<Map<String, dynamic>> reasoningChain;
}

abstract interface class CoachChatRepository {
  Future<List<CoachThread>> loadThreads();
  Future<String> createThread();
  Future<List<CoachMessage>> loadMessages(String threadId);
  Future<CoachMessage> sendMessage(String threadId, String question);
  Future<void> deleteThread(String threadId);
}

abstract interface class CoachRepository {
  Future<CoachDecision?> loadLatest();
  Future<CoachDecision> generate();
  Future<Map<String, dynamic>> loadUsage();
}

class SupabaseCoachRepository
    implements CoachRepository, CoachChatRepository, CoachContextRepository {
  SupabaseCoachRepository(this._client, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const _uuid = Uuid();
  final SupabaseClient _client;
  final DateTime Function() _now;
  Map<String, dynamic>? _lastResponse;

  @override
  Future<List<CoachContextSource>> loadContextStatus() async {
    final value = Map<String, dynamic>.from(
      await _client.rpc('get_my_coach_context_status') as Map,
    );
    return (value['sources'] as List? ?? const [])
        .map(
          (source) => CoachContextSource.fromJson(
            Map<String, dynamic>.from(source as Map),
          ),
        )
        .toList();
  }

  @override
  Future<List<CoachThread>> loadThreads() async {
    final rows = await _client
        .from('coach_threads')
        .select('id,title,updated_at')
        .eq('status', 'active')
        .order('last_message_at', ascending: false);
    return rows
        .map(
          (row) => CoachThread(
            id: row['id'] as String,
            title: row['title'] as String,
            updatedAt: DateTime.parse(row['updated_at'] as String),
          ),
        )
        .toList();
  }

  @override
  Future<String> createThread() async =>
      await _client.rpc(
            'create_coach_thread',
            params: {'thread_title': 'New conversation'},
          )
          as String;

  @override
  Future<List<CoachMessage>> loadMessages(String threadId) async {
    final rows = await _client
        .from('coach_messages')
        .select()
        .eq('thread_id', threadId)
        .order('created_at');
    return rows.map(_messageFromJson).toList();
  }

  @override
  Future<CoachMessage> sendMessage(String threadId, String question) async {
    final account = await _client
        .from('user_accounts')
        .select('timezone')
        .single();
    final response = await _client.functions.invoke(
      'coach-chat',
      body: {
        'schema_version': '1.0',
        'thread_id': threadId,
        'question': question.trim(),
        'timezone': account['timezone'] as String? ?? 'UTC',
        'idempotency_key': _uuid.v4(),
      },
    );
    if (response.status != 200 || response.data is! Map) {
      throw StateError('Coach chat is unavailable.');
    }
    final body = Map<String, dynamic>.from(response.data as Map);
    _lastResponse = body;
    if (body['message'] is Map) {
      return _messageFromJson(
        Map<String, dynamic>.from(body['message'] as Map),
      );
    }
    final messages = await loadMessages(threadId);
    if (messages.isEmpty) throw const FormatException('Coach message missing.');
    return messages.last;
  }

  Future<void> confirmPreference({
    required String category,
    required String key,
    required String value,
    required String provenance,
  }) async {
    await _client.rpc('persist_coach_preference', params: {
      'target_user_id': _client.auth.currentUser?.id,
      'category': category,
      'pref_key': key,
      'pref_value': value,
      'provenance': provenance,
    });
  }

  Future<Map<String, dynamic>?> loadLastRawResponse() async => _lastResponse;

  CoachMessage _messageFromJson(Map<String, dynamic> row) => CoachMessage(
    id: row['id'] as String? ?? _uuid.v4(),
    role: row['role'] as String,
    content: row['content'] as String? ?? row['answer'] as String,
    createdAt: DateTime.parse(
      row['created_at'] as String? ?? _now().toUtc().toIso8601String(),
    ),
    evidence: (row['evidence'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(),
    missingData: List<String>.from(row['missing_data'] as List? ?? const []),
    safetyState: row['safety_state'] as String? ?? 'allowed',
    suggestedFollowUps: List<String>.from(
      row['suggested_follow_ups'] as List? ?? const [],
    ),
    modelProvider: row['model_provider'] as String?,
    model: row['model'] as String?,
    reasoningChain: (row['reasoning_chain'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(),
  );

  @override
  Future<void> deleteThread(String threadId) async {
    await _client.rpc(
      'delete_coach_thread',
      params: {'target_thread_id': threadId},
    );
  }

  @override
  Future<CoachDecision?> loadLatest() async {
    final rows = await _client
        .from('coach_decisions')
        .select()
        .order('created_at', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : CoachDecision.fromJson(rows.first);
  }

  @override
  Future<CoachDecision> generate() async {
    final now = _now();
    final account = await _client
        .from('user_accounts')
        .select('timezone')
        .single();
    final timezone = account['timezone'] as String? ?? 'UTC';
    final response = await _client.functions.invoke(
      'coach-decide',
      body: {
        'schema_version': '1.0',
        'local_date': _dateKey(now),
        'timezone': timezone,
        'idempotency_key': _uuid.v4(),
      },
    );
    if (response.status != 200 || response.data is! Map) {
      throw StateError('Coaching is temporarily unavailable.');
    }
    final body = Map<String, dynamic>.from(response.data as Map);
    final decision = body['decision'];
    if (decision is! Map) throw const FormatException('Decision missing.');
    final mapped = Map<String, dynamic>.from(decision);
    mapped['created_at'] ??= now.toUtc().toIso8601String();
    return CoachDecision.fromJson(mapped);
  }

  @override
  Future<Map<String, dynamic>> loadUsage() async {
    final values = await Future.wait([
      _client.rpc('get_my_ai_usage'),
      _client.rpc('get_my_ai_budget_state'),
    ]);
    return {
      ...Map<String, dynamic>.from(values[0] as Map),
      ...Map<String, dynamic>.from(values[1] as Map),
    };
  }

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class FixtureCoachRepository implements CoachRepository, CoachChatRepository {
  const FixtureCoachRepository();
  @override
  Future<List<CoachThread>> loadThreads() async => const [];
  @override
  Future<String> createThread() async => 'fixture-thread';
  @override
  Future<List<CoachMessage>> loadMessages(String threadId) async => const [];
  @override
  Future<CoachMessage> sendMessage(
    String threadId,
    String question,
  ) async => CoachMessage(
    id: 'fixture-message',
    role: 'assistant',
    content:
        'Configure the secure backend to use persistent Coach chat. Your approved plan remains available.',
    createdAt: DateTime.now(),
    safetyState: 'unavailable',
  );
  @override
  Future<void> deleteThread(String threadId) async {}
  @override
  Future<CoachDecision?> loadLatest() async => null;
  @override
  Future<CoachDecision> generate() =>
      throw StateError('Configure Supabase to generate coaching.');
  @override
  Future<Map<String, dynamic>> loadUsage() async => const {
    'period': 'current_month',
    'successful_runs': 0,
    'failed_runs': 0,
    'estimated_cost_usd': 0,
  };
}
