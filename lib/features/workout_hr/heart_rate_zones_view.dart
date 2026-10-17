import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/workout_hr/heart_rate_profile.dart';
import 'package:tracend/shared/widgets/tracend_loading_indicator.dart';

/// The athlete's heart-rate zones, resting and maximum heart rate and recovery
/// after sets, in the Apple Health sheet. Missing data reads as missing: no
/// zones without a resting heart rate and a maximum, no recovery trend without
/// enough tracked sets. It informs only; it never changes a load.
class HeartRateZonesView extends StatefulWidget {
  const HeartRateZonesView({required this.load, super.key});

  final Future<HeartRateProfile?> Function() load;

  @override
  State<HeartRateZonesView> createState() => _HeartRateZonesViewState();
}

class _HeartRateZonesViewState extends State<HeartRateZonesView> {
  late final Future<HeartRateProfile?> _profile = _read();

  Future<HeartRateProfile?> _read() async {
    try {
      return await widget.load();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<HeartRateProfile?>(
    future: _profile,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: TracendSpacing.sm),
          child: Center(child: TracendLoadingIndicator(size: 16)),
        );
      }
      final profile = snapshot.data;
      if (profile == null) return const SizedBox.shrink();
      return HeartRateZonesBody(profile: profile);
    },
  );
}

/// The zones section for an already-loaded [profile].
class HeartRateZonesBody extends StatelessWidget {
  const HeartRateZonesBody({required this.profile, super.key});

  final HeartRateProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final colors = context.tracendColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Heart-rate zones', style: theme.titleSmall),
        const SizedBox(height: TracendSpacing.xs),
        Text(heartRateBasisLine(profile), style: theme.bodySmall),
        const SizedBox(height: TracendSpacing.xs),
        if (profile.zones.isEmpty)
          Text(
            heartRateZonesMissingLine(profile),
            style: theme.bodyMedium?.copyWith(color: colors.textSecondary),
          )
        else
          for (final zone in profile.zones)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: Text('Z${zone.zone}', style: theme.labelMedium),
                  ),
                  Expanded(child: Text(zone.label, style: theme.bodyMedium)),
                  Text(
                    '${zone.lowBpm}-${zone.highBpm} bpm',
                    style: theme.bodyMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
        const SizedBox(height: TracendSpacing.xs),
        Text(heartRateRecoveryLine(profile), style: theme.bodySmall),
        const SizedBox(height: 2),
        Text(
          'For information only. Heart rate never changes your loads.',
          style: theme.bodySmall?.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}

/// "Resting 59 bpm · Max 183 bpm, estimated from age", or what is missing.
String heartRateBasisLine(HeartRateProfile profile) {
  final resting = profile.restingBpm == null
      ? 'Resting heart rate not found yet'
      : 'Resting ${profile.restingBpm} bpm';
  final max = switch (profile.maxBasis) {
    MaxHeartRateBasis.observed =>
      'Max ${profile.maxBpm} bpm, from your workouts',
    MaxHeartRateBasis.ageFormula =>
      'Max ${profile.maxBpm} bpm, estimated from your age',
    MaxHeartRateBasis.missing => 'Max unknown',
  };
  return '$resting · $max';
}

String heartRateZonesMissingLine(
  HeartRateProfile profile,
) => switch (profile.zonesMissing) {
  ZonesMissing.noResting =>
    'Zones need a resting heart rate. Apple Health has fewer than 3 recent days of it.',
  ZonesMissing.noMax =>
    'Zones need a maximum heart rate. Add your birth year in your profile, or track a hard workout with your Watch.',
  ZonesMissing.narrowReserve =>
    'Your resting and maximum heart rates are too close to set zones.',
  null => '',
};

String heartRateRecoveryLine(HeartRateProfile profile) {
  final recent = profile.recentDrop60sBpm;
  if (recent == null) {
    return 'Recovery after sets: not enough tracked sets yet.';
  }
  final drop = _beats(recent);
  final change = profile.recoveryChangeBpm;
  if (change == null) {
    return 'Recovery after sets: heart rate falls $drop bpm in the first minute. '
        'The 4 weeks before are too thin to compare.';
  }
  final sign = change >= 0 ? '+' : '-';
  final trend = switch (profile.recoveryState) {
    RecoveryState.improving => 'improving',
    RecoveryState.slower => 'slower',
    _ => 'steady',
  };
  return 'Recovery after sets: heart rate falls $drop bpm in the first minute, '
      '$trend ($sign${_beats(change.abs())} bpm against the 4 weeks before).';
}

String _beats(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : '$value';
