import 'package:sentry_flutter/sentry_flutter.dart';

/// What replaces a value the athlete entered or the phone measured.
const redactedValue = '[redacted]';

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
final _failingRowPattern = RegExp(r'Failing row contains \([^)]*\)');
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
final _sensitivePairPattern = RegExp(
  '(["\']?\\b\\w*(?:${_sensitiveKeyParts.map(RegExp.escape).join('|')})\\w*["\']?)'
  r'''\s*(?::|=>|=)\s*("[^"]*"|'[^']*'|[^\s,;)}\]]+)''',
  caseSensitive: false,
);

/// [text] without the values it carries: a Postgres row's details, ids,
/// emails, query strings, the value of a named measurement, and a number with
/// a body or heart unit. Long text is cut.
String scrubText(String text) {
  var out = text
      .replaceAll(_detailsPattern, 'details: $redactedValue')
      .replaceAll(_failingRowPattern, 'Failing row contains ($redactedValue)')
      .replaceAll(_keyPairPattern, 'Key ($redactedValue)=($redactedValue)')
      .replaceAllMapped(_urlPattern, (match) => _stripQuery(match[0]!))
      .replaceAll(_uuidPattern, '[id]')
      .replaceAll(_emailPattern, '[email]')
      .replaceAllMapped(
        _sensitivePairPattern,
        (match) => '${match[1]}: $redactedValue',
      )
      .replaceAll(_measurePattern, '[value]');
  if (out.length > _maxTextLength) out = '${out.substring(0, _maxTextLength)}…';
  return out;
}

String _stripQuery(String url) {
  final cut = url.indexOf(RegExp(r'[?#]'));
  return cut < 0 ? url : url.substring(0, cut);
}

/// [value] with every sensitive key's value replaced and every text scrubbed,
/// at any depth.
Object? scrubValue(Object? value, {String? key}) {
  if (key != null && _isSensitiveKey(key)) return redactedValue;
  return switch (value) {
    final String text => scrubText(text),
    final Map<dynamic, dynamic> map => {
      for (final entry in map.entries)
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

/// The event Sentry may send, scrubbed in place: the request body and query,
/// contexts, `extra`, the message, every exception value and every
/// breadcrumb. An event that cannot be scrubbed is dropped, never sent as it
/// was.
SentryEvent? scrubEvent(SentryEvent event, Hint hint) {
  try {
    final request = event.request;
    if (request != null) {
      // Cookies, headers, the query and the fragment never travel.
      event.request = SentryRequest(
        url: request.url == null ? null : _stripQuery(request.url!),
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
    final message = event.message;
    if (message != null) {
      event.message = SentryMessage(scrubText(message.formatted));
    }
    for (final exception in event.exceptions ?? const <SentryException>[]) {
      final value = exception.value;
      if (value != null) exception.value = scrubText(value);
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
