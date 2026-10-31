import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/auth/owner_auth_screen.dart';

void main() {
  test('a refused sign-up explains the invite list', () {
    expect(
      authErrorMessage(
        const AuthException(
          'Database error saving new user',
          statusCode: '500',
          code: 'unexpected_failure',
        ),
        createAccount: true,
      ),
      "This email isn't on the invite list yet.",
    );
  });

  test('a sign-in failure never mentions the invite list', () {
    expect(
      authErrorMessage(
        const AuthException('Server error', statusCode: '500'),
        createAccount: false,
      ),
      'Authentication is unavailable right now. Try again.',
    );
    expect(
      authErrorMessage(
        const AuthException('Invalid login credentials', statusCode: '400'),
        createAccount: false,
      ),
      'The email or password is incorrect.',
    );
  });

  test('an invalid sign-up keeps its own message', () {
    expect(
      authErrorMessage(
        const AuthException('Password too short', statusCode: '400'),
        createAccount: true,
      ),
      'This account could not be created. Check the email and password.',
    );
  });

  test(
    'an unconfirmed email is told to confirm it, not that the password is wrong',
    () {
      expect(
        authErrorMessage(
          const AuthException(
            'Email not confirmed',
            statusCode: '400',
            code: 'email_not_confirmed',
          ),
          createAccount: false,
        ),
        'Confirm your email first: open the message Tracend sent you, then sign in.',
      );
    },
  );

  test('a 422 says why the account was refused', () {
    expect(
      authErrorMessage(
        const AuthException(
          'Signups not allowed',
          statusCode: '422',
          code: 'signup_disabled',
        ),
        createAccount: true,
      ),
      'New accounts are closed during the private beta.',
    );
    expect(
      authErrorMessage(
        const AuthException(
          'User already registered',
          statusCode: '422',
          code: 'email_exists',
        ),
        createAccount: true,
      ),
      'An account with this email already exists. Sign in instead.',
    );
    expect(
      authErrorMessage(
        const AuthException(
          'Password is too weak',
          statusCode: '422',
          code: 'weak_password',
        ),
        createAccount: true,
      ),
      'Choose a stronger password of at least 8 characters.',
    );
    expect(
      authErrorMessage(
        const AuthException('Unprocessable', statusCode: '422'),
        createAccount: true,
      ),
      'This account could not be created. Check the email and password.',
    );
  });

  test('too many attempts is not called a wrong password', () {
    expect(
      authErrorMessage(
        const AuthException(
          'Rate limit',
          statusCode: '429',
          code: 'over_request_rate_limit',
        ),
        createAccount: false,
      ),
      'Too many attempts. Wait a minute, then try again.',
    );
    expect(
      authErrorMessage(
        const AuthException('Slow down', statusCode: '429'),
        createAccount: false,
      ),
      'Too many attempts. Wait a minute, then try again.',
    );
  });
}
