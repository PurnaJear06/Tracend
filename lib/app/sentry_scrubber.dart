import 'package:sentry_flutter/sentry_flutter.dart';

/// Keeps what is private out of the error reports Tracend sends.
///
/// Health values, meal content, photo links and prompts never leave the
/// phone, and neither does anything from the pain check: the area, the
/// strength, the red-flag answers and the referral they led to are among the
/// most private things the app holds. They are removed from an event and from
/// every breadcrumb, by key (the whole entry goes) and by what a string says,
/// before anything is sent. A report says that something failed, never what
/// the athlete answered.

const redacted = '[redacted]';

/// Values replaced by [redacted]; the key stays so a report still shows what
/// kind of thing it was about.
const _redactedKeys = {
  'answer_payload',
  'answer_text',
  'blood_pressure',
  'food_items',
  'heart_rate',
  'image_url',
  'ingredients',
  'meal_content',
  'meal_description',
  'object_key',
  'photo_url',
  'prompt',
  'prompt_text',
  'question',
  'resting_heart_rate_bpm',
  'signed_url',
  'sleep_minutes',
  'step_count',
  'weight_kg',
};

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

bool _dropKey(Object? key) =>
    key is String &&
    (_droppedKeys.contains(key) || _droppedPrefixes.any(key.startsWith));

/// The words that carry a pain answer or a referral when they appear inside
/// text: the codes of the red-flag list, the routes and outcomes that name a
/// referral, and the pain check's own `pain_` and `joint_` tokens. Names of
/// functions and screens are not among them.
final _sensitiveText = RegExp(
  r'(pain_(?:area|severity|pattern|red_flags|followups|cleared_by_clinician|'
  r'referral|flag|mild|moderate|severe)|red_flag[a-z_:]*|joint_[a-z_]+|'
  r'bladder_bowel_saddle|chest_or_breath|numb_weak_limb|pop_or_sudden|'
  r'cannot_bear_or_move|rapid_swelling|dislocated_or_cannot_lift|'
  r'locks_gives_way|fever_unwell|night_pain|clinician_today|clinician)',
);

String _scrubText(String text) => text.replaceAll(_sensitiveText, redacted);

Object? _scrub(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (!_dropKey(entry.key))
          entry.key: _redactedKeys.contains(entry.key)
              ? redacted
              : _scrub(entry.value),
    };
  }
  if (value is List) return [for (final item in value) _scrub(item)];
  if (value is String) return _scrubText(value);
  return value;
}

Map<String, dynamic>? _scrubMap(Map<String, dynamic>? map) =>
    map == null ? null : Map<String, dynamic>.from(_scrub(map)! as Map);

/// A breadcrumb with its message and data scrubbed. Breadcrumbs that Tracend
/// writes itself carry plain facts only; this also covers the ones the SDK
/// records on its own (navigation, network, console).
Breadcrumb? scrubSentryBreadcrumb(Breadcrumb? crumb, Hint hint) {
  if (crumb == null) return null;
  final message = crumb.message;
  if (message != null) crumb.message = _scrubText(message);
  crumb.data = _scrubMap(crumb.data);
  return crumb;
}

/// An event with the request, extra data, tags, message, exception messages
/// and breadcrumbs scrubbed.
SentryEvent? scrubSentryEvent(SentryEvent event, Hint hint) {
  final request = event.request;
  if (request != null) {
    event.request = SentryRequest(
      url: request.url == null ? null : _scrubText(request.url!),
      method: request.method,
      queryString: request.queryString == null
          ? null
          : _scrubText(request.queryString!),
      fragment: request.fragment == null ? null : _scrubText(request.fragment!),
      apiTarget: request.apiTarget,
      data: _scrub(request.data),
      headers: request.headers,
      env: request.env,
    );
  }
  final context = event.contexts;
  for (final key in context.keys.toList()) {
    final value = context[key];
    if (value is Map<String, dynamic>) context[key] = _scrubMap(value);
  }
  // ignore: deprecated_member_use
  event.extra = _scrubMap(event.extra);
  final tags = event.tags;
  if (tags != null) {
    event.tags = {
      for (final entry in tags.entries)
        if (!_dropKey(entry.key))
          entry.key: _redactedKeys.contains(entry.key)
              ? redacted
              : _scrubText(entry.value),
    };
  }
  final message = event.message;
  if (message != null) {
    final template = message.template;
    final params = message.params;
    event.message = SentryMessage(
      _scrubText(message.formatted),
      template: template == null ? null : _scrubText(template),
      params: params == null ? null : _scrub(params)! as List,
    );
  }
  for (final exception in event.exceptions ?? const <SentryException>[]) {
    final value = exception.value;
    if (value != null) exception.value = _scrubText(value);
  }
  for (final crumb in event.breadcrumbs ?? const <Breadcrumb>[]) {
    scrubSentryBreadcrumb(crumb, Hint());
  }
  return event;
}
