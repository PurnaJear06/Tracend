import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tracend/shared/diagnostics.dart';

// Keeps what is private out of the error reports Tracend sends.
//
// Health values, meal content, photo links and prompts never leave the phone,
// and neither does anything from the pain check: the area, the strength, the
// red-flag answers and the referral they led to are among the most private
// things the app holds. A report says that something failed, never what the
// athlete answered.

/// What replaces a value the athlete entered or the phone measured.
const redactedValue = '[redacted]';

/// The pain check's own keys (B5): answers, areas, severities and the
/// referral. They go entirely, name and value, because even that a pain
/// answer was present is nobody else's to know.
const _droppedKeys = {
  'area',
  'area_state',
  'cleared_by_clinician',
  'followups',
  'hold_outcome',
  'range_note_code',
  'range_note_codes',
  'red_flags',
  'safety_route',
  'severity',
  'swap_to_name',
  'swap_to_slug',
};

/// Keys that start with these are the pain check's too: `pain_area`,
/// `pain_severity`, `pain_red_flags`, `joint_states`, `joint_action`.
const _droppedPrefixes = ['pain_', 'joint_', 'red_flag'];

bool _dropKey(String key) {
  final lower = key.toLowerCase();
  return _droppedKeys.contains(lower) || _droppedPrefixes.any(lower.startsWith);
}

/// A key that names something the athlete entered or the phone measured.
/// Matched as a part of the key, lower-cased, so `resting_heart_rate_bpm` and
/// `weightKg` both count.
const _sensitiveKeyParts = <String>[
  'answer',
  'authorization',
  'blood',
  'body_fat',
  'bodyfat',
  'calorie',
  'carb',
  'cookie',
  'detail',
  'email',
  'fat_',
  'food',
  'heart',
  'hint',
  'hrv',
  'image',
  'ingredient',
  'kcal',
  'meal',
  'note',
  'object_key',
  'password',
  'payload',
  'photo',
  'prompt',
  'protein',
  'question',
  'secret',
  'signed',
  'sleep',
  'step',
  'token',
  'weight',
];

/// Keys an HTTP breadcrumb may keep. Bodies and query values never travel.
const _httpCrumbKeys = {
  'url',
  'method',
  'status_code',
  'reason',
  'duration',
  'request_body_size',
  'response_body_size',
};

/// Breadcrumb categories that carry free text from the app's own prints.
const _printCategories = {'console', 'print'};

const _maxTextLength = 300;

bool _isSensitiveKey(String key) {
  final lower = key.toLowerCase();
  for (final part in _sensitiveKeyParts) {
    if (lower.contains(part)) return true;
  }
  return false;
}

final _detailsPattern = RegExp(
  r'details:\s*.*?(?=,\s*hint:|\)\s*$|$)',
  dotAll: true,
);

/// What the database says of a row it refused: the values are the athlete's
/// answers, so everything from there to the end of the line goes, even when
/// the message was cut short before its closing bracket.
final _refusedRowPattern = RegExp(r'Failing row contains \(.*');
final _keyPairPattern = RegExp(r'Key \([^)]*\)=\([^)]*\)');
final _urlPattern = RegExp(r'''https?://[^\s"')]+''');
final _uuidPattern = RegExp(
  r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
);
final _emailPattern = RegExp(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)+');
final _measurePattern = RegExp(
  r'\b\d+(?:[.,]\d+)?\s?(?:kg|lbs?|kcal|bpm)\b',
  caseSensitive: false,
);

/// The value after a key in free text. A list, or a string in either kind of
/// quote (an escaped quote does not end it), goes whole. Anything else, which
/// may be several words, goes to the end of the line, and so does a string
/// whose closing quote was cut off.
const _valuePattern =
    r'''(?:\[[^\]]*\]|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|.*)''';

/// A pain key with its value, in any text: `pain_area=back`,
/// `pain_severity: 8`, `"red_flags":["night_pain"]`, `area = 'knee'`. The whole
/// expression goes, so the answer does not stay behind the key.
final _painPairPattern = RegExp(
  r'''["']?\b(?:pain_[a-z_]+|joint_[a-z_]+|red_flags?|area|area_state|severity|'''
  r'''cleared_by_clinician|followups|hold_outcome|safety_route|'''
  r'''range_note_codes?|swap_to_(?:name|slug))["']?[ \t]*[:=][ \t]*'''
  '$_valuePattern',
);

/// A key that names something the athlete entered or the phone measured, with
/// its value, in any text. The key stays so a report still shows what kind of
/// thing it was about.
final _sensitivePairPattern = RegExp(
  '(["\']?\\b\\w*(?:${_sensitiveKeyParts.map(RegExp.escape).join('|')})\\w*["\']?)'
  '[ \\t]*(?::|=>|=)[ \\t]*$_valuePattern',
  caseSensitive: false,
);

/// The words that carry a pain answer or a referral when they appear inside
/// text: the codes of the red-flag list, the routes and outcomes that name a
/// referral, the pain check's own `pain_` and `joint_` tokens, and the names
/// of its table and function (`pain_reports`, `record_pain_check`). Names of
/// other functions and screens are not among them.
final _painWordPattern = RegExp(
  r'(pain_(?:area|severity|pattern|red_flags|followups|cleared_by_clinician|'
  r'referral|flag|mild|moderate|severe|reports)|record_pain_check[a-z0-9_]*|'
  r'red_flag[a-z_:]*|joint_[a-z_]+|'
  r'bladder_bowel_saddle|chest_or_breath|numb_weak_limb|pop_or_sudden|'
  r'cannot_bear_or_move|rapid_swelling|dislocated_or_cannot_lift|'
  r'locks_gives_way|fever_unwell|night_pain|clinician_today|clinician)',
);

/// [text] without the values it carries: a Postgres row's details, ids,
/// emails, query strings, the value of a named measurement, and a number with
/// a body or heart unit. Long text is cut.
String scrubText(String text) {
  var out = text
      .replaceAll(_detailsPattern, 'details: $redactedValue')
      .replaceAll(_refusedRowPattern, 'Failing row contains ($redactedValue)')
      .replaceAll(_keyPairPattern, 'Key ($redactedValue)=($redactedValue)')
      .replaceAllMapped(_urlPattern, (match) => templateUrl(match[0]!))
      .replaceAll(_uuidPattern, '[id]')
      .replaceAll(_emailPattern, '[email]')
      .replaceAll(_painPairPattern, redactedValue)
      .replaceAllMapped(
        _sensitivePairPattern,
        (match) => '${match[1]}: $redactedValue',
      )
      .replaceAll(_painWordPattern, redactedValue)
      .replaceAll(_measurePattern, '[value]');
  if (out.length > _maxTextLength) out = '${out.substring(0, _maxTextLength)}…';
  return out;
}

final _digitsPattern = RegExp(r'^\d+$');

/// A path segment that names one record or file rather than a route: an id,
/// a number, a filename, or a long token that mixes letters and digits.
bool _isRecordSegment(String segment) =>
    _uuidPattern.hasMatch(segment) ||
    _digitsPattern.hasMatch(segment) ||
    segment.contains('.') ||
    (segment.length >= 16 && segment.contains(RegExp(r'\d')));

/// [url] reduced to its origin and a route template: no query, no fragment, no
/// credentials, every segment that names a record or a file (a UUID, a number,
/// `IMG_1234.JPG`, a token) replaced by `:id`, and everything after
/// `/object/` (a Storage bucket, owner and photo path) replaced by `:path`.
/// A Storage URL keeps no athlete id, set id or pose.
String templateUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '[url]';
  final segments = <String>[];
  var afterObject = false;
  for (final segment in uri.pathSegments) {
    if (segment.isEmpty) continue;
    if (afterObject) {
      if (segments.last != ':path') segments.add(':path');
      continue;
    }
    if (segment == 'object') {
      afterObject = true;
      segments.add(segment);
      continue;
    }
    segments.add(_isRecordSegment(segment) ? ':id' : segment);
  }
  final port = uri.hasPort ? ':${uri.port}' : '';
  final path = segments.isEmpty ? '' : '/${segments.join('/')}';
  return '${uri.scheme}://${uri.host}$port$path';
}

/// What an exception is, with no free text: its type and code (see
/// [describeFailure]); a lost connection is `network`. A failure the app
/// reported keeps its own fixed wording. Null for an exception whose type is
/// not the event's thrown one (a chained cause), which keeps its type only.
String? _failureLabel(Object? thrown) {
  if (thrown == null) return null;
  if (thrown is NonCriticalFailure) return thrown.toString();
  if (thrown is SocketException ||
      thrown is HandshakeException ||
      thrown is TimeoutException ||
      thrown is http.ClientException) {
    return '${thrown.runtimeType} network';
  }
  return describeFailure(thrown);
}

/// [value] with every sensitive key's value replaced, every pain-check key
/// removed, and every text scrubbed, at any depth.
Object? scrubValue(Object? value, {String? key}) {
  if (key != null && _isSensitiveKey(key)) return redactedValue;
  return switch (value) {
    final String text => scrubText(text),
    final Map<dynamic, dynamic> map => {
      for (final entry in map.entries)
        if (!_dropKey('${entry.key}'))
          '${entry.key}': scrubValue(entry.value, key: '${entry.key}'),
    },
    final List<dynamic> list => [for (final item in list) scrubValue(item)],
    _ => value,
  };
}

Map<String, dynamic> _scrubMap(Map<String, dynamic> map) =>
    scrubValue(map)! as Map<String, dynamic>;

/// The breadcrumb Sentry may keep: none for the app's prints, an HTTP crumb
/// reduced to its method, status and address without a query, and every other
/// crumb with its text and data scrubbed.
Breadcrumb? scrubBreadcrumb(Breadcrumb? crumb, Hint hint) {
  if (crumb == null) return null;
  final category = crumb.category;
  if (category != null && _printCategories.contains(category)) return null;
  final data = crumb.data;
  final isHttp =
      crumb.type == 'http' || category == 'http' || category == 'xhr';
  if (isHttp && data != null) {
    crumb.data = _scrubMap({
      for (final entry in data.entries)
        if (_httpCrumbKeys.contains(entry.key)) entry.key: entry.value,
    });
  } else if (data != null) {
    crumb.data = _scrubMap(data);
  }
  final message = crumb.message;
  if (message != null) crumb.message = scrubText(message);
  return crumb;
}

/// The event Sentry may send, scrubbed in place: the request (reduced to its
/// method, route template and scrubbed body), contexts, `extra`, tags, the
/// message (its template and parameters are dropped), every exception value
/// (reduced to its type and code) and every breadcrumb. An event that cannot
/// be scrubbed is dropped, never sent as it was.
SentryEvent? scrubEvent(SentryEvent event, Hint hint) {
  try {
    final request = event.request;
    if (request != null) {
      // Cookies, headers, the query and the fragment never travel.
      event.request = SentryRequest(
        url: request.url == null ? null : scrubText(templateUrl(request.url!)),
        method: request.method,
        data: scrubValue(request.data),
      );
    }
    final contexts = event.contexts;
    for (final key in contexts.keys.toList()) {
      final context = contexts[key];
      if (context is Map<String, dynamic>) {
        contexts[key] = _scrubMap(context);
      }
    }
    // ignore: deprecated_member_use
    final extra = event.extra;
    if (extra != null) {
      // ignore: deprecated_member_use
      event.extra = _scrubMap(extra);
    }
    final tags = event.tags;
    if (tags != null) {
      event.tags = {
        for (final entry in tags.entries)
          if (!_dropKey(entry.key))
            entry.key: '${scrubValue(entry.value, key: entry.key)}',
      };
    }
    final message = event.message;
    if (message != null) {
      event.message = SentryMessage(scrubText(message.formatted));
    }
    // An exception's text can hold a row, a filename or model prose, however
    // it is pattern-scrubbed, so only its type and code travel.
    final thrown = event.throwable;
    for (final exception in event.exceptions ?? const <SentryException>[]) {
      exception.value =
          thrown != null && exception.type == '${thrown.runtimeType}'
          ? _failureLabel(thrown)
          : null;
    }
    final breadcrumbs = event.breadcrumbs;
    if (breadcrumbs != null) {
      event.breadcrumbs = [
        for (final crumb in breadcrumbs) ?scrubBreadcrumb(crumb, hint),
      ];
    }
    return event;
  } on Object {
    return null;
  }
}
