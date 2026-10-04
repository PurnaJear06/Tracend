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
    this.trainingAdjustments = const [],
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
      trainingAdjustments: List<String>.from(
        training['today_adjustments'] as List? ?? const [],
      ),
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

  /// What the coach suggests changing today, in plain sentences; advice
  /// only, never applied to the plan.
  final List<String> trainingAdjustments;
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

  factory CoachThread.fromJson(Map<String, dynamic> json) => CoachThread(
    id: json['id'] as String,
    title: json['title'] as String,
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

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

class CoachUnavailableException implements Exception {
  const CoachUnavailableException(
    this.message, {
    this.code,
    this.retryAfterSeconds,
  });
  final String message;
  final String? code;
  final int? retryAfterSeconds;

  @override
  String toString() => message;
}

String coachChatFailureMessage(String? code) => switch (code) {
  'provider_response_empty' ||
  'provider_response_truncated' ||
  'provider_response_invalid' =>
    'Coach couldn’t complete that response. Please try again.',
  'provider_timeout' => 'Coach took too long to respond. Please try again.',
  _ => 'Coach is unavailable right now. Your approved plan is unchanged.',
};

abstract interface class CoachContextRepository {
  Future<List<CoachContextSource>> loadContextStatus();
}

/// Request schema 1.1 asks coach-chat for response 1.2: `answer_source` on
/// every message, and a labeled data summary (HTTP 200) instead of a 503 when
/// the model cannot produce a valid answer.
const coachChatRequestSchemaVersion = '1.1';

/// Every call gets a new idempotency key, so a retry is a new turn. Reusing a
/// key would only return the first attempt's outcome.
Map<String, String> coachChatRequestBody({
  required String threadId,
  required String question,
  required String timezone,
  required String idempotencyKey,
}) => {
  'schema_version': coachChatRequestSchemaVersion,
  'thread_id': threadId,
  'question': question.trim(),
  'timezone': timezone,
  'idempotency_key': idempotencyKey,
};

/// Why the model did not answer, sent with a live data summary for the beta.
/// Stored summaries do not keep it.
class CoachChatDiagnostic {
  const CoachChatDiagnostic({
    required this.failureCode,
    this.initialRule,
    this.repairRule,
  });

  factory CoachChatDiagnostic.fromJson(Map<String, dynamic> json) =>
      CoachChatDiagnostic(
        failureCode: json['failure_code'] as String,
        initialRule: json['initial_rule'] as String?,
        repairRule: json['repair_rule'] as String?,
      );

  final String failureCode;
  final String? initialRule;
  final String? repairRule;
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
    this.answerSource,
    this.diagnostic,
  });

  /// Parses a stored `coach_messages` row or a coach-chat response message.
  factory CoachMessage.fromJson(
    Map<String, dynamic> row, {
    required String fallbackId,
    required DateTime fallbackCreatedAt,
  }) {
    final diagnostic = row['diagnostic'];
    return CoachMessage(
      id: row['id'] as String? ?? fallbackId,
      role: row['role'] as String,
      content: row['content'] as String? ?? row['answer'] as String,
      createdAt: row['created_at'] is String
          ? DateTime.parse(row['created_at'] as String)
          : fallbackCreatedAt,
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
      answerSource: row['answer_source'] as String?,
      diagnostic: diagnostic is Map
          ? CoachChatDiagnostic.fromJson(Map<String, dynamic>.from(diagnostic))
          : null,
    );
  }

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

  /// `model` or `data_summary`. Null for user messages and for model answers,
  /// which the server stores without a source; only data summaries carry one.
  final String? answerSource;
  final CoachChatDiagnostic? diagnostic;

  /// A labeled deterministic reply from the athlete's data, served when the
  /// model could not answer. Never the Coach AI's own answer.
  bool get isDataSummary => answerSource == 'data_summary';

  /// A data summary for a message that may concern a health risk: a safety
  /// referral that carries no numbers from the athlete's data.
  bool get isSafetyReferral => isDataSummary && safetyState == 'limited';
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

  /// Active threads that contain at least one message, newest first. Empty
  /// threads from earlier builds are never listed.
  @override
  Future<List<CoachThread>> loadThreads() async {
    final value = Map<String, dynamic>.from(
      await _client.rpc('get_my_coach_threads') as Map,
    );
    return (value['threads'] as List? ?? const [])
        .map(
          (thread) =>
              CoachThread.fromJson(Map<String, dynamic>.from(thread as Map)),
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
    final response = await _client.functions
        .invoke(
          'coach-chat',
          body: coachChatRequestBody(
            threadId: threadId,
            question: question,
            timezone: account['timezone'] as String? ?? 'UTC',
            idempotencyKey: _uuid.v4(),
          ),
        )
        .timeout(const Duration(seconds: 45));
    if (response.status != 200 || response.data is! Map) {
      String? code;
      int? retryAfter;
      if (response.data is Map) {
        final d = Map<String, dynamic>.from(response.data as Map);
        code = d['code'] as String?;
        final rawRetry = d['retry_after_seconds'];
        if (rawRetry is int) {
          retryAfter = rawRetry;
        } else if (rawRetry is num) {
          retryAfter = rawRetry.ceil();
        }
      }
      throw CoachUnavailableException(
        coachChatFailureMessage(code),
        code: code,
        retryAfterSeconds: retryAfter,
      );
    }
    final body = Map<String, dynamic>.from(response.data as Map);
    _lastResponse = body;
    final message = body['message'];
    if (message is! Map) {
      throw const FormatException('Coach response has no message body.');
    }
    return _messageFromJson(Map<String, dynamic>.from(message));
  }

  Future<void> confirmPreference({
    required String category,
    required String key,
    required String value,
    required String provenance,
  }) async {
    await _client.rpc(
      'persist_coach_preference',
      params: {
        'target_user_id': _client.auth.currentUser?.id,
        'category': category,
        'pref_key': key,
        'pref_value': value,
        'provenance': provenance,
      },
    );
  }

  Future<Map<String, dynamic>?> loadLastRawResponse() async => _lastResponse;

  CoachMessage _messageFromJson(Map<String, dynamic> row) =>
      CoachMessage.fromJson(
        row,
        fallbackId: _uuid.v4(),
        fallbackCreatedAt: _now().toUtc(),
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
