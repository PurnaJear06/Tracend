class AppEnvironment {
  const AppEnvironment({
    required this.name,
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    this.sentryDsn = '',
    this.authMode = 'owner_email_password',
  });

  const AppEnvironment.fromCompileTime()
    : name = const String.fromEnvironment('TRACEND_ENV', defaultValue: 'local'),
      supabaseUrl = const String.fromEnvironment('SUPABASE_URL'),
      supabasePublishableKey = const String.fromEnvironment(
        'SUPABASE_PUBLISHABLE_KEY',
      ),
      sentryDsn = const String.fromEnvironment('SENTRY_DSN'),
      authMode = const String.fromEnvironment(
        'TRACEND_AUTH_MODE',
        defaultValue: 'owner_email_password',
      );

  final String name;
  final String supabaseUrl;
  final String supabasePublishableKey;
  final String sentryDsn;
  final String authMode;

  bool get hasSupabaseConfiguration =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  bool get hasSentryConfiguration => sentryDsn.isNotEmpty;

  bool get usesOwnerEmailPassword => authMode == 'owner_email_password';
}
