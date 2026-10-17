import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/shared/formatting.dart';

/// A Coach chat send that did not produce an answer: what to tell the
/// athlete, the raw beta diagnostic, and what the app may do next.
class CoachUnavailableException implements Exception {
  const CoachUnavailableException(
    this.message, {
    this.code,
    this.retryAfterSeconds,
    this.diagnostic,
    this.retryable = true,
    this.retrySameKey = false,
    this.needsConsent = false,
  });

  final String message;

  /// The server's stable failure code, when it sent one.
  final String? code;
  final int? retryAfterSeconds;

  /// The raw beta text (HTTP status, error, code, reason), shown under the
  /// message while the app is in private beta.
  final String? diagnostic;

  /// False when asking again cannot help, as at a usage limit.
  final bool retryable;

  /// True when no answer reached the app but the server may have one (a
  /// timeout, a lost connection, a turn still running): the retry reuses the
  /// request's idempotency key, so a finished turn is returned, not repeated
  /// and charged again. False when the server did answer, so a retry is a new
  /// turn.
  final bool retrySameKey;

  /// True when the server refused for want of the athlete's AI coaching
  /// consent: the card offers to review it.
  final bool needsConsent;

  /// The diagnostic line under the message, or null when there is nothing
  /// raw to show.
  String? get betaDiagnostic =>
      diagnostic ?? (code == null ? null : 'Beta diagnostic: $code');

  @override
  String toString() => message;
}

const _genericFailure =
    'Coach is unavailable right now. Your approved plan is unchanged.';

String coachChatFailureMessage(String? code) => switch (code) {
  'provider_response_empty' ||
  'provider_response_truncated' ||
  'provider_response_invalid' =>
    'Coach couldn’t complete that response. Please try again.',
  'provider_timeout' => 'Coach took too long to respond. Please try again.',
  _ => _genericFailure,
};

/// The instant a monthly limit resets: the first of next month, 00:00 UTC,
/// which is when the database starts a new month.
DateTime coachMonthlyReset(DateTime now) {
  final utc = now.toUtc();
  return DateTime.utc(utc.year, utc.month + 1);
}

/// The instant a daily limit resets: the next 00:00 UTC.
DateTime coachDailyReset(DateTime now) {
  final utc = now.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day + 1);
}

String _clock(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${time.hour < 12 ? 'am' : 'pm'}';
}

/// "5:30 am tomorrow" or "5:00 pm today", in the athlete's own clock.
String _dailyResetText(DateTime now) {
  final reset = coachDailyReset(now).toLocal();
  final local = now.toLocal();
  final sameDay =
      reset.year == local.year &&
      reset.month == local.month &&
      reset.day == local.day;
  return '${_clock(reset)} ${sameDay ? 'today' : 'tomorrow'}';
}

String _monthlyResetText(DateTime now) =>
    shortDate(coachMonthlyReset(now).toLocal(), now: now);

/// The note under a reply when the server says the athlete is nearing this
/// month's Coach allowance (`budget_warning`).
String coachBudgetWarningMessage(DateTime now) =>
    'Heads up: you’re approaching this month’s Coach limit. It resets on '
    '${_monthlyResetText(now)}.';

enum _Limit { monthly, daily, shared, unknown }

String _limitMessage(_Limit limit, DateTime now, int? dailyLimit) =>
    switch (limit) {
      _Limit.monthly =>
        'You’ve reached this month’s Coach limit. It resets on '
            '${_monthlyResetText(now)}.',
      _Limit.daily =>
        'You’ve used ${dailyLimit == null ? 'all' : 'all $dailyLimit'} of '
            'today’s Coach messages. The limit resets at '
            '${_dailyResetText(now)}.',
      _Limit.shared =>
        'Coach has reached its shared limit for this month. It resets on '
            '${_monthlyResetText(now)}.',
      _Limit.unknown =>
        'Coach has reached its usage limit for now. Please try again later.',
    };

/// Which limit a 429 means. The function names it in `reason` when it can;
/// otherwise the athlete's own budget state (`get_my_ai_budget_state`) says
/// whether the month or the day is used up.
_Limit _limitFor(String? reason, Map<String, dynamic>? budget) {
  switch (reason) {
    case 'monthly_cost_limit':
      return _Limit.monthly;
    case 'daily_rate_limit':
      return _Limit.daily;
    case 'global_monthly_cost_limit':
      return _Limit.shared;
  }
  if (budget == null) return _Limit.unknown;
  if (budget['blocked'] == true) return _Limit.monthly;
  final today = budget['today_requests'];
  final limit = budget['daily_limit'];
  if (today is num && limit is num && today >= limit) return _Limit.daily;
  return _Limit.unknown;
}

int? _retryAfter(Object? raw) => switch (raw) {
  final int seconds when seconds > 0 => seconds,
  final num seconds when seconds > 0 => seconds.ceil(),
  _ => null,
};

String _rawText(Object? details) {
  final text = details is String ? details.trim() : '$details';
  return text.length > 200 ? '${text.substring(0, 200)}…' : text;
}

/// What a failed coach-chat call means for the athlete. [error] is what the
/// call threw: a [FunctionException] (the function answered with an error, or
/// the request never got a response), a [TimeoutException] from the app's own
/// 45-second limit, or anything else. [budget] is the athlete's
/// `get_my_ai_budget_state`, read only after a 429 so the message can say
/// which limit was reached.
CoachUnavailableException coachChatFailure(
  Object error, {
  required DateTime now,
  Map<String, dynamic>? budget,
}) {
  if (error is CoachUnavailableException) return error;
  if (error is TimeoutException) {
    return CoachUnavailableException(
      'Coach took too long to answer. Retry will pick up the answer if it '
      'finished in the meantime.',
      code: 'client_timeout',
      diagnostic: 'Beta diagnostic: app timeout · $error',
      retrySameKey: true,
    );
  }
  if (error is FunctionsFetchException) {
    return CoachUnavailableException(
      'Tracend can’t reach Coach. Check your connection, then retry.',
      code: 'offline',
      diagnostic: 'Beta diagnostic: no response · ${_rawText(error.details)}',
      retrySameKey: true,
    );
  }
  if (error is! FunctionException) {
    return CoachUnavailableException(
      'Coach couldn’t answer. Your approved plan is unchanged.',
      diagnostic: _rawText(
        error
            .toString()
            .replaceFirst('Exception: ', '')
            .replaceFirst('StateError: ', '')
            .replaceFirst('Bad state: ', ''),
      ),
    );
  }

  final status = error.status;
  final details = error.details;
  final Map<String, dynamic> body = details is Map
      ? Map<String, dynamic>.from(details)
      : const {};
  final errorName = body['error'] as String?;
  final code = body['code'] as String?;
  final reason = body['reason'] as String?;
  final retryAfter = _retryAfter(body['retry_after_seconds']);
  final diagnostic = [
    'Beta diagnostic: HTTP $status',
    ?errorName,
    ?code,
    ?reason,
    if (body.isEmpty && details != null && '$details'.isNotEmpty)
      _rawText(details),
  ].join(' · ');

  CoachUnavailableException fail(
    String message, {
    bool retryable = true,
    bool retrySameKey = false,
    bool needsConsent = false,
  }) => CoachUnavailableException(
    message,
    code: code ?? errorName,
    retryAfterSeconds: retryAfter,
    diagnostic: diagnostic,
    retryable: retryable,
    retrySameKey: retrySameKey,
    needsConsent: needsConsent,
  );

  if (status == 429 || errorName == 'ai_usage_limit') {
    final dailyLimit = budget?['daily_limit'];
    return fail(
      _limitMessage(
        _limitFor(reason, budget),
        now,
        dailyLimit is num ? dailyLimit.toInt() : null,
      ),
      retryable: false,
    );
  }
  if (errorName == 'ai_consent_required') {
    return fail(
      'Coach needs your permission to use AI before it can answer. Review AI '
      'coaching, then ask again.',
      retryable: false,
      needsConsent: true,
    );
  }
  if (errorName == 'ai_consent_unavailable') {
    return fail(
      'Coach couldn’t check your AI coaching setting just now. Please try '
      'again in a moment.',
    );
  }
  if (status == 401 ||
      errorName == 'authentication_required' ||
      errorName == 'invalid_session') {
    return fail(
      'Your session has expired. Sign in again to keep talking to Coach.',
      retryable: false,
    );
  }
  if (errorName == 'chat_in_progress' || code == 'request_in_progress') {
    return fail(
      'Coach is still working on your last message. Give it a few seconds, '
      'then retry.',
      retrySameKey: true,
    );
  }
  if (code == 'context_preparation_failed') {
    return switch (reason) {
      'daily_rate_limit' => fail(
        _limitMessage(_Limit.daily, now, null),
        retryable: false,
      ),
      'monthly_cost_limit' => fail(
        _limitMessage(_Limit.monthly, now, null),
        retryable: false,
      ),
      'approved_plan_required' => fail(
        'Coach needs an approved plan to look at. Finish setting up your plan '
        'in Train, then ask again.',
        retryable: false,
      ),
      'thread_not_found' => fail(
        'That conversation is no longer available. Start a new one.',
        retryable: false,
      ),
      'invalid_chat_request' => fail(
        'Coach couldn’t read that message. Shorten it and send it again.',
        retryable: false,
      ),
      'account_not_found' => fail(
        'Coach couldn’t find your account. Sign out and back in, then try '
        'again.',
        retryable: false,
      ),
      'invalid_timezone' => fail(
        'Coach doesn’t recognise your time zone. Check it in Account, then '
        'try again.',
        retryable: false,
      ),
      'chat_context_too_large' => fail(
        'This conversation has grown too long for Coach to read. Start a new '
        'one.',
        retryable: false,
      ),
      _ => fail(
        'Coach couldn’t prepare your data just now. Please try again in a '
        'moment.',
      ),
    };
  }
  if (errorName == 'invalid_chat_request') {
    return fail(
      'Coach couldn’t read that message. Shorten it and send it again.',
      retryable: false,
    );
  }
  if (errorName == 'chat_rejected') {
    return fail('Coach’s answer couldn’t be saved. Please try again.');
  }
  if (code == 'provider_rate_limited') {
    return fail('Coach is busy right now. Please try again in a moment.');
  }
  if (code != null && code.startsWith('provider_')) {
    return fail(coachChatFailureMessage(code));
  }
  if (status == 502 || status == 504 || status == 546) {
    return fail(
      'Coach took too long to answer. Retry will pick up the answer if it '
      'finished in the meantime.',
      retrySameKey: true,
    );
  }
  return fail(_genericFailure);
}
