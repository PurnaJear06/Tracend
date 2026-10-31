import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:tracend/shared/home_widgets/today_widget_publisher.dart';

/// Whether the signed-in athlete allows numbers on the Lock Screen (Account ›
/// Widgets, SECURITY_PRIVACY.md §10). The workout's Live Activity shows the
/// set's kg and reps only while this is on. Off when no one is signed in, when
/// the choice was never made, or when it cannot be read: the card then shows
/// the exercise and the set's position and nothing else.
Future<bool> readLockScreenNumbers() async {
  try {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    return await SharedPreferencesAsync().getBool(
          TodayWidgetPublisher.lockScreenNumbersKeyFor(userId),
        ) ??
        false;
  } catch (e) {
    debugPrint('Non-critical error: lock screen choice not read: $e');
    return false;
  }
}
