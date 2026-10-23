import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// One finished workout, as `get_my_watch_workout_status_v1` lists it: the
/// sets the athlete finished and how many of them have Apple Watch heart rate
/// from a Watch workout.
class WatchWorkoutSession {
  const WatchWorkoutSession({
    required this.completedSets,
    required this.watchSets,
  });

  final int completedSets;
  final int watchSets;
}

/// The last three finished workouts and whether the Watch tracked them.
class WatchWorkoutStatus {
  const WatchWorkoutStatus(this.recentSessions);

  factory WatchWorkoutStatus.fromJson(Object? json) {
    final rows = json is Map ? json['recent_sessions'] : null;
    return WatchWorkoutStatus([
      for (final row in rows is List ? rows : const [])
        if (row is Map && row['completed_sets'] is num)
          WatchWorkoutSession(
            completedSets: (row['completed_sets'] as num).toInt(),
            watchSets: (row['watch_sets'] as num?)?.toInt() ?? 0,
          ),
    ]);
  }

  final List<WatchWorkoutSession> recentSessions;

  /// None of the last three finished workouts had Watch heart rate, or there
  /// is no finished workout yet: a Watch workout started with this one would
  /// give the first heart-rate readings. A single tracked workout among the
  /// last three is enough to stay quiet.
  bool get suggestsWatchWorkout =>
      recentSessions.every((session) => session.watchSets == 0);
}

/// Decides whether to suggest starting a Watch workout, and remembers the
/// athlete's answer on this phone.
abstract interface class WatchWorkoutPromptSource {
  /// True when the suggestion should show before the first set. False when the
  /// athlete muted it, snoozed it or the Watch already tracks their workouts,
  /// and when the server cannot be read. Never throws.
  Future<bool> shouldSuggest();

  /// "Not now": stay quiet for [snoozeFor].
  Future<void> snooze();

  /// "I don't use a Watch": never suggest again on this phone.
  Future<void> mute();
}

class SupabaseWatchWorkoutPromptSource implements WatchWorkoutPromptSource {
  SupabaseWatchWorkoutPromptSource(
    this._client, {
    SharedPreferencesAsync? preferences,
    DateTime Function() now = DateTime.now,
  }) : _preferences = preferences ?? SharedPreferencesAsync(),
       _now = now;

  /// How long "Not now" keeps the suggestion away.
  static const snoozeFor = Duration(days: 7);

  static const mutedKey = 'tracend.watch_prompt.muted';
  static const snoozedUntilKey = 'tracend.watch_prompt.snoozed_until';

  final SupabaseClient _client;
  final SharedPreferencesAsync _preferences;
  final DateTime Function() _now;

  @override
  Future<bool> shouldSuggest() async {
    try {
      if (await _preferences.getBool(mutedKey) ?? false) return false;
      final until = DateTime.tryParse(
        await _preferences.getString(snoozedUntilKey) ?? '',
      );
      if (until != null && _now().isBefore(until)) return false;
      final today = _now();
      final value = await _client.rpc(
        'get_my_watch_workout_status_v1',
        params: {
          'local_date':
              '${today.year.toString().padLeft(4, '0')}-'
              '${today.month.toString().padLeft(2, '0')}-'
              '${today.day.toString().padLeft(2, '0')}',
        },
      );
      return WatchWorkoutStatus.fromJson(value).suggestsWatchWorkout;
    } catch (e) {
      debugPrint('Non-critical error: Watch workout status not read: $e');
      return false;
    }
  }

  @override
  Future<void> snooze() => _store(
    () => _preferences.setString(
      snoozedUntilKey,
      _now().add(snoozeFor).toIso8601String(),
    ),
  );

  @override
  Future<void> mute() => _store(() => _preferences.setBool(mutedKey, true));

  Future<void> _store(Future<void> Function() write) async {
    try {
      await write();
    } catch (e) {
      debugPrint('Non-critical error: Watch workout answer not stored: $e');
    }
  }
}

/// The card on the workout screen before the first set. Heart rate informs
/// rest and recovery only; it never changes a weight or the plan.
class WatchWorkoutPromptCard extends StatelessWidget {
  const WatchWorkoutPromptCard({
    required this.onNotNow,
    required this.onNoWatch,
    super.key,
  });

  final VoidCallback onNotNow;
  final VoidCallback onNoWatch;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TracendSpacing.gutter,
        TracendSpacing.xs,
        TracendSpacing.gutter,
        0,
      ),
      child: TracendCard(
        raised: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const StatusChip(
              label: 'Track your heart rate',
              icon: CupertinoIcons.heart,
            ),
            const SizedBox(height: TracendSpacing.xs),
            Text(
              'Start a Strength workout on your Apple Watch, then log your '
              'sets here. Afterwards Tracend reads your heart rate to learn '
              'how you recover between sets. It informs rest and recovery and '
              'never changes your weights.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: TracendSpacing.xs),
            Wrap(
              spacing: TracendSpacing.xs,
              children: [
                TextButton(onPressed: onNotNow, child: const Text('Not now')),
                TextButton(
                  onPressed: onNoWatch,
                  child: const Text("I don't use a Watch"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
