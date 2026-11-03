import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/app.dart';
import 'package:tracend/app/auth_options.dart';
import 'package:tracend/app/keychain_session_storage.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/sentry_scrubber.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  LicenseRegistry.addLicense(() async* {
    final archivo = await rootBundle.loadString('assets/fonts/OFL-Archivo.txt');
    yield LicenseEntryWithLineBreaks(const ['Archivo'], archivo);
  });

  const environment = AppEnvironment.fromCompileTime();

  await runZonedGuarded(
    () async {
      await SentryFlutter.init(
        (options) {
          options.dsn = environment.sentryDsn;
          options.tracesSampleRate = 0.1;
          options.attachStacktrace = true;
          // The app's prints and the SDK's own HTTP bodies are free text: a
          // health value or a meal could ride in them. Only the named
          // breadcrumbs (AppBreadcrumbs) and scrubbed events leave the phone.
          options.enablePrintBreadcrumbs = false;
          options.beforeBreadcrumb = scrubBreadcrumb;
          options.beforeSend = scrubEvent;
        },
        appRunner: () async {
          if (environment.hasSupabaseConfiguration) {
            await Supabase.initialize(
              url: environment.supabaseUrl,
              publishableKey: environment.supabasePublishableKey,
              authOptions: tracendAuthOptions(
                KeychainSessionStorage(
                  persistSessionKey: KeychainSessionStorage.sessionKeyFor(
                    environment.supabaseUrl,
                  ),
                  onMigrationFailed: (error, stackTrace) =>
                      Sentry.captureException(
                        StateError('session_keychain_migration_failed'),
                        stackTrace: stackTrace,
                      ),
                ),
              ),
            );
          }

          runApp(const TracendApp(environment: environment));
        },
      );
    },
    (exception, stackTrace) async {
      await Sentry.captureException(exception, stackTrace: stackTrace);
    },
  );
}
