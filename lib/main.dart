import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/app.dart';
import 'package:tracend/app/environment.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const environment = AppEnvironment.fromCompileTime();
  if (environment.hasSupabaseConfiguration) {
    await Supabase.initialize(
      url: environment.supabaseUrl,
      publishableKey: environment.supabasePublishableKey,
    );
  }

  runApp(const TracendApp(environment: environment));
}
