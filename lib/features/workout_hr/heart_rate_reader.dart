import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tracend/features/workout_hr/set_heart_rate_summary.dart';

/// The channel to `ios/Runner/Native/HeartRateReader.swift`. The app calls
/// `requestAccess` and `readSamples`; the samples stay on the phone.
const heartRateChannel = MethodChannel('tracend/heart_rate');

/// Heart-rate samples from Apple Health.
abstract interface class HeartRateReader {
  /// Asks for read access to heart rate. Apple Health shows its sheet only
  /// while the choice is undecided and never says whether access was given,
  /// so a read with no access returns no samples. Never throws.
  Future<void> requestAccess();

  /// The samples that overlap [from] to [to], oldest first. Throws when
  /// Apple Health cannot be read, so that "no samples" and "could not read"
  /// stay different.
  Future<List<HeartRateSample>> readSamples(DateTime from, DateTime to);
}

class MethodChannelHeartRateReader implements HeartRateReader {
  const MethodChannelHeartRateReader();

  @override
  Future<void> requestAccess() async {
    try {
      await heartRateChannel.invokeMethod<bool>('requestAccess');
    } on PlatformException catch (e) {
      debugPrint('Non-critical error: heart-rate access request failed: $e');
    } on MissingPluginException catch (e) {
      debugPrint('Non-critical error: heart-rate access request failed: $e');
    }
  }

  @override
  Future<List<HeartRateSample>> readSamples(DateTime from, DateTime to) async {
    final rows = await heartRateChannel
        .invokeListMethod<Object?>('readSamples', {
          'start_millis': from.millisecondsSinceEpoch,
          'end_millis': to.millisecondsSinceEpoch,
        });
    return [
      for (final row in rows ?? const <Object?>[])
        if (row is Map && row['at_millis'] is int && row['bpm'] is num)
          HeartRateSample(
            at: DateTime.fromMillisecondsSinceEpoch(row['at_millis'] as int),
            bpm: (row['bpm'] as num).toDouble(),
          ),
    ];
  }
}
