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
}
