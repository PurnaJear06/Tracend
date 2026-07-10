import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/environment.dart';

void main() {
  group('AppEnvironment', () {
    test('requires both Supabase public values', () {
      const missingKey = AppEnvironment(
        name: 'test',
        supabaseUrl: 'https://example.supabase.co',
        supabasePublishableKey: '',
      );
      const configured = AppEnvironment(
        name: 'test',
        supabaseUrl: 'https://example.supabase.co',
        supabasePublishableKey: 'publishable-key',
      );

      expect(missingKey.hasSupabaseConfiguration, isFalse);
      expect(configured.hasSupabaseConfiguration, isTrue);
      expect(configured.usesOwnerEmailPassword, isTrue);
    });

    test('rejects unimplemented authentication modes', () {
      const environment = AppEnvironment(
        name: 'test',
        supabaseUrl: 'https://example.supabase.co',
        supabasePublishableKey: 'publishable-key',
        authMode: 'apple',
      );

      expect(environment.usesOwnerEmailPassword, isFalse);
    });
  });
}
