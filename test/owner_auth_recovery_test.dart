import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/auth/owner_auth_screen.dart';
import 'package:tracend/features/auth/password_reset_flow.dart';

const _email = 'athlete@example.com';

final _session = Session(
  accessToken: 'access-test',
  tokenType: 'bearer',
  user: User(
    id: '11111111-1111-4111-8111-111111111111',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-10-01T00:00:00Z',
  ),
);

const _rateLimited = AuthApiException(
  'For security purposes, you can only request this after 60 seconds.',
  statusCode: '429',
  code: 'over_email_send_rate_limit',
);

const _requestLimited = AuthApiException(
  'Request rate limit reached',
  statusCode: '429',
  code: 'over_request_rate_limit',
);

/// Auth as the sign-in screen uses it, recording each call.
class _FakeAuth extends Fake implements GoTrueClient {
  final calls = <String>[];
  Object? resetError;
  Object? verifyError;
  Object? updateError;
  Object? resendError;
  Object? signInError;

  @override
  Future<void> resetPasswordForEmail(
    String email, {
    String? redirectTo,
    String? captchaToken,
  }) async {
    calls.add('reset $email');
    if (resetError != null) throw resetError!;
  }

  @override
  Future<AuthResponse> verifyOTP({
    String? email,
    String? phone,
    String? token,
    required OtpType type,
    String? redirectTo,
    String? captchaToken,
    String? tokenHash,
  }) async {
    calls.add('verify ${type.name} $email $token');
    if (verifyError != null) throw verifyError!;
    return AuthResponse(session: _session);
  }

  @override
  Future<UserResponse> updateUser(
    UserAttributes attributes, {
    String? emailRedirectTo,
  }) async {
    calls.add('update ${attributes.password}');
    if (updateError != null) throw updateError!;
    return UserResponse.fromJson(_session.user.toJson());
  }

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.local}) async {
    calls.add('signOut ${scope.name}');
  }

  @override
  Future<AuthResponse> signUp({
    String? email,
    String? phone,
    required String password,
    String? emailRedirectTo,
    Map<String, dynamic>? data,
    String? captchaToken,
    OtpChannel channel = OtpChannel.sms,
  }) async {
    calls.add('signUp $email');
    return AuthResponse();
  }

  @override
  Future<AuthResponse> signInWithPassword({
    String? email,
    String? phone,
    required String password,
    String? captchaToken,
  }) async {
    calls.add('signIn $email');
    if (signInError != null) throw signInError!;
    return AuthResponse(session: _session);
  }

  @override
  Future<ResendResponse> resend({
    String? email,
    String? phone,
    required OtpType type,
    String? emailRedirectTo,
    String? captchaToken,
  }) async {
    calls.add('resend ${type.name} $email');
    if (resendError != null) throw resendError!;
    return ResendResponse();
  }
}

void main() {
  late _FakeAuth auth;
  late int authenticated;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    auth = _FakeAuth();
    authenticated = 0;
  });

  /// Whether this phone marks a reset whose code was accepted but whose
  /// password is not saved yet.
  Future<bool?> marked(WidgetTester tester) => tester.runAsync<bool?>(
    () => SharedPreferencesAsync().getBool(PasswordResetMarker.key),
  );

  Future<void> pump(WidgetTester tester, {Size size = const Size(390, 844)}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: OwnerAuthScreen(
          auth: auth,
          onAuthenticated: () => authenticated++,
        ),
      ),
    );
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  /// From sign-in to the code step, with the email typed on sign-in.
  Future<void> askForCode(WidgetTester tester) async {
    await pump(tester);
    await tester.enterText(field('Email'), _email);
    await tap(tester, 'Forgot password?');
    expect(find.text('Reset your password'), findsOneWidget);
    await tap(tester, 'Send code');
  }

  Future<void> enterCode(WidgetTester tester, String code) async {
    await tester.enterText(field('Code from the email'), code);
    await tester.enterText(field('New password'), 'new-password-1');
    await tap(tester, 'Set new password');
  }

  group('a forgotten password', () {
    testWidgets('a code and a new password reset it and sign in', (
      tester,
    ) async {
      await askForCode(tester);
      expect(auth.calls, ['reset $_email']);
      expect(find.text('Check your email'), findsOneWidget);

      await enterCode(tester, '123456');

      expect(auth.calls, [
        'reset $_email',
        'verify recovery $_email 123456',
        'update new-password-1',
      ]);
      expect(authenticated, 1);
      expect(await marked(tester), isNull);
    });

    testWidgets('asking for a code reads the same whether or not the email '
        'has an account', (tester) async {
      // An address with no account: Auth answers as if it sent one.
      await askForCode(tester);
      final unknown = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .toList();

      // An address with an account that asked a moment ago: Auth refuses.
      auth = _FakeAuth()..resetError = _rateLimited;
      await tester.pumpWidget(const SizedBox());
      await askForCode(tester);
      final known = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .toList();

      expect(known, unknown);
      expect(
        find.textContaining('If an account uses $_email, we sent it a code.'),
        findsOneWidget,
      );
    });

    for (final (name, refusal) in [
      (
        'a server failure',
        const AuthApiException(
          'Error sending recovery email',
          statusCode: '500',
          code: 'unexpected_failure',
        ),
      ),
      (
        'an address the sender refuses',
        const AuthApiException(
          'Email address not authorized',
          statusCode: '400',
          code: 'email_address_not_authorized',
        ),
      ),
    ]) {
      testWidgets('$name reads the same as a sent code', (tester) async {
        auth.resetError = refusal;
        await askForCode(tester);
        expect(find.text('Check your email'), findsOneWidget);
        expect(
          find.textContaining('If an account uses $_email, we sent it a code.'),
          findsOneWidget,
        );
      });
    }

    testWidgets('a wrong or expired code says so and saves nothing', (
      tester,
    ) async {
      auth.verifyError = const AuthApiException(
        'Token has expired or is invalid',
        statusCode: '403',
        code: 'otp_expired',
      );
      await askForCode(tester);
      await enterCode(tester, '000000');

      expect(
        find.text(
          'That code is wrong or has expired. Check it, or send a new code.',
        ),
        findsOneWidget,
      );
      expect(auth.calls.where((call) => call.startsWith('update')), isEmpty);
      expect(authenticated, 0);
      expect(await marked(tester), isNull);
    });

    testWidgets('too many code attempts say to wait', (tester) async {
      auth.verifyError = _requestLimited;
      await askForCode(tester);
      await enterCode(tester, '123456');

      expect(
        find.text('Too many attempts. Wait a few minutes, then try again.'),
        findsOneWidget,
      );
    });

    testWidgets('a refused password is chosen again without the used code', (
      tester,
    ) async {
      auth.updateError = AuthWeakPasswordException(
        message: 'Password is known to be weak',
        statusCode: '422',
        reasons: ['pwned'],
      );
      await askForCode(tester);
      await enterCode(tester, '123456');

      expect(
        find.text(
          'This password has appeared in a data breach. Choose a different '
          'one.',
        ),
        findsOneWidget,
      );
      expect(find.text('Code accepted. Choose your new password.'), findsOne);
      expect(field('Code from the email'), findsNothing);
      expect(authenticated, 0);

      auth.updateError = null;
      await tester.enterText(field('New password'), 'new-password-2');
      await tap(tester, 'Set new password');

      expect(
        auth.calls.where((call) => call.startsWith('verify')),
        hasLength(1),
      );
      expect(auth.calls.last, 'update new-password-2');
      expect(authenticated, 1);
    });

    testWidgets('leaving after the code was accepted signs this phone out', (
      tester,
    ) async {
      auth.updateError = const AuthApiException(
        'New password should be different from the old password.',
        statusCode: '422',
        code: 'same_password',
      );
      await askForCode(tester);
      await enterCode(tester, '123456');
      expect(
        find.text('Choose a password different from your old one.'),
        findsOneWidget,
      );
      // Closed now, the next launch would end this session (Phase2Gate).
      expect(await marked(tester), isTrue);

      await tap(tester, 'Back to sign in');
      await tester.pumpAndSettle();

      expect(auth.calls.last, 'signOut local');
      expect(await marked(tester), isNull);
      expect(find.text('Sign in to Tracend'), findsOneWidget);
      expect(authenticated, 0);
    });

    testWidgets('leaving before a code was accepted signs nothing out', (
      tester,
    ) async {
      await askForCode(tester);
      await tap(tester, 'Back to sign in');
      await tester.pumpAndSettle();

      expect(auth.calls, ['reset $_email']);
      expect(find.text('Sign in to Tracend'), findsOneWidget);
    });

    testWidgets('a new code can be sent once a minute', (tester) async {
      await askForCode(tester);
      final waiting = find.widgetWithText(TextButton, 'Send a new code in 60s');
      expect(waiting, findsOneWidget);
      expect(tester.widget<TextButton>(waiting).onPressed, isNull);

      const sent = 'If an account uses this email, a new code is on its way.';
      await tester.pump(const Duration(seconds: 60));
      await tap(tester, 'Send a new code');
      expect(auth.calls, ['reset $_email', 'reset $_email']);
      expect(find.text(sent), findsOneWidget);

      // An email limit only an address with an account can reach reads the
      // same as a sent code.
      auth.resetError = _rateLimited;
      await tester.pump(const Duration(seconds: 60));
      await tap(tester, 'Send a new code');
      expect(find.text(sent), findsOneWidget);

      // A limit on requests applies to everyone and is said as it is.
      auth.resetError = _requestLimited;
      await tester.pump(const Duration(seconds: 60));
      await tap(tester, 'Send a new code');
      expect(
        find.text('Too many requests. Wait a minute, then send a new code.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextButton, 'Send a new code in 60s'),
        findsOneWidget,
      );
    });

    testWidgets('a limit on requests is said before any code is sent', (
      tester,
    ) async {
      auth.resetError = _requestLimited;
      await askForCode(tester);
      expect(
        find.text('Too many requests. Wait a minute, then try again.'),
        findsOneWidget,
      );
      expect(find.text('Reset your password'), findsOneWidget);
    });

    testWidgets('lays out at 320pt × 2', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester, size: const Size(320, 844));
      await tester.enterText(field('Email'), _email);
      await tap(tester, 'Forgot password?');
      expect(tester.takeException(), isNull);
      await tap(tester, 'Send code');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('the confirmation email', () {
    Future<void> signUp(WidgetTester tester) async {
      await pump(tester);
      await tap(tester, 'Create account');
      await tester.enterText(field('Email'), _email);
      await tester.enterText(field('Password'), 'password-1');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
    }

    testWidgets('can be sent again a minute after sign-up', (tester) async {
      await signUp(tester);
      expect(
        find.text('Check your email to confirm your account.'),
        findsOneWidget,
      );
      final waiting = find.widgetWithText(TextButton, 'Resend email in 60s');
      expect(tester.widget<TextButton>(waiting).onPressed, isNull);

      await tester.pump(const Duration(seconds: 60));
      await tap(tester, 'Resend email');

      expect(auth.calls, ['signUp $_email', 'resend signup $_email']);
      expect(
        find.text('We sent the email again. Check your inbox and spam folder.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextButton, 'Resend email in 60s'),
        findsOneWidget,
      );
    });

    testWidgets('can be sent again from a sign-in before confirming', (
      tester,
    ) async {
      auth.signInError = const AuthApiException(
        'Email not confirmed',
        statusCode: '400',
        code: 'email_not_confirmed',
      );
      await pump(tester);
      await tester.enterText(field('Email'), _email);
      await tester.enterText(field('Password'), 'password-1');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();

      await tap(tester, 'Resend email');
      expect(auth.calls, ['signIn $_email', 'resend signup $_email']);
    });

    testWidgets('a refused resend says to wait', (tester) async {
      auth
        ..signInError = const AuthApiException(
          'Email not confirmed',
          statusCode: '400',
          code: 'email_not_confirmed',
        )
        ..resendError = _rateLimited;
      await pump(tester);
      await tester.enterText(field('Email'), _email);
      await tester.enterText(field('Password'), 'password-1');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();

      await tap(tester, 'Resend email');
      expect(
        find.text('Too many requests. Wait a minute, then try again.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextButton, 'Resend email in 60s'),
        findsOneWidget,
      );
    });

    testWidgets('is not offered after an ordinary sign-in failure', (
      tester,
    ) async {
      auth.signInError = const AuthApiException(
        'Invalid login credentials',
        statusCode: '400',
        code: 'invalid_credentials',
      );
      await pump(tester);
      await tester.enterText(field('Email'), _email);
      await tester.enterText(field('Password'), 'password-1');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();

      expect(find.text('The email or password is incorrect.'), findsOneWidget);
      expect(find.textContaining('Resend email'), findsNothing);
    });
  });
}
