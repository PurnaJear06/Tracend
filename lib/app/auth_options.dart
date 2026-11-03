import 'package:supabase_flutter/supabase_flutter.dart';

/// How the app's Supabase Auth client runs, with the session kept in
/// [localStorage].
///
/// A session starts only from the email and password sign-in, or from the
/// code in a password reset email typed into the app. A link never makes
/// one: `tracend://` links only switch tabs, so a link carrying another
/// account's tokens (a crafted page, a QR code) cannot sign this phone into
/// that account. The confirmation link in a sign-up email confirms the email
/// on the server; the athlete then signs in with the password.
FlutterAuthClientOptions tracendAuthOptions(LocalStorage localStorage) =>
    FlutterAuthClientOptions(
      localStorage: localStorage,
      detectSessionInUri: false,
    );
