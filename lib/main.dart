import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/app.dart';
import 'package:tracend/app/environment.dart';

const _sensitiveKeys = {
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

void _redactSensitiveData(Map<String, dynamic> map) {
  for (final key in _sensitiveKeys) {
    if (map.containsKey(key)) {
      map[key] = '[redacted]';
    }
  }
}

SentryEvent? _sentryBeforeSend(SentryEvent event, Hint hint) {
  final requestData = event.request?.data;
  if (requestData is Map<String, dynamic>) {
    _redactSensitiveData(requestData);
  }
  final contexts = event.contexts;
  for (final key in contexts.keys) {
    final ctx = contexts[key];
    if (ctx is Map<String, dynamic>) {
      _redactSensitiveData(ctx);
    }
  }
  return event;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const environment = AppEnvironment.fromCompileTime();

  await runZonedGuarded(() async {
    await SentryFlutter.init(
      (options) {
        options.dsn = environment.sentryDsn;
        options.tracesSampleRate = 0.1;
        options.attachStacktrace = true;
        options.beforeSend = _sentryBeforeSend;
      },
      appRunner: () async {
        if (environment.hasSupabaseConfiguration) {
          await Supabase.initialize(
            url: environment.supabaseUrl,
            publishableKey: environment.supabasePublishableKey,
          );
        }

        runApp(const TracendApp(environment: environment));
      },
    );
  }, (exception, stackTrace) async {
    await Sentry.captureException(exception, stackTrace: stackTrace);
  });
}
