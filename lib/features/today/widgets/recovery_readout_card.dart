import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

/// What is behind today's recovery score (the score itself sits in the
/// Today hero). Each driver is a plain row, such as "Heart rate variability:
/// normal for you, 58 ms". The z-scores, the weights and the rules are kept
/// behind the ⓘ "How this is calculated" disclosure (UX_FLOWS.md §5).
///
/// Row states:
/// - usable: the comparison word from the z-score (see [driverComparison])
///   plus today's measured value when the brief carries it (brief ≥ 1.4)
/// - missing component: "not enough data yet" — never an at-baseline
///   reading
/// - sleep missing but proven valid (non-null sleep quality, the backend's
///   1–960-minute gate): the measurement with "baseline still building"
///
/// Renders nothing when the brief has no recovery breakdown.
class RecoveryReadoutCard extends StatelessWidget {
  const RecoveryReadoutCard({required this.computed, super.key});

  final ComputedMetrics computed;

  @override
  Widget build(BuildContext context) {
    final breakdown = computed.scores.recoveryBreakdown;
    if (breakdown == null) return const SizedBox.shrink();
    final colors = context.tracendColors;
    final drivers = recoveryDrivers(
      breakdown: breakdown,
      todayRaw: computed.todayRaw,
      sleepQualityProven: computed.scores.sleepQuality != null,
      mode: computed.scores.recoveryMode,
    );
    return PremiumGradientCard(
      padding: const EdgeInsets.fromLTRB(
        TracendSpacing.md,
        TracendSpacing.xs,
        TracendSpacing.md,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < drivers.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 42),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: colors.borderHairline,
                ),
              ),
            _DriverRow(driver: drivers[i]),
          ],
          Divider(height: 1, thickness: 1, color: colors.borderHairline),
          _HowCalculated(
            drivers: drivers,
            morning: computed.scores.recoveryMode == 'morning',
          ),
        ],
      ),
    );
  }
}

/// One recovery driver ready to render.
@immutable
class RecoveryDriver {
  const RecoveryDriver({
    required this.key,
    required this.label,
    required this.icon,
    required this.zScore,
    required this.usable,
    required this.weightPercent,
    this.comparison,
    this.rawValue,
    this.buildingBaseline = false,
  });

  /// The component key ('hrv_sdnn', 'resting_hr', 'sleep_minutes',
  /// 'resp_rate', 'prev_strain', 'check_in').
  final String key;
  final String label;
  final IconData icon;

  /// The true z-score from the brief; meaningful only when [usable].
  final double zScore;

  /// False when the component did not count towards today's score.
  final bool usable;
  final int weightPercent;

  /// "normal for you", "higher than usual", …; null when not [usable].
  final String? comparison;

  /// Today's measurement with its unit ("58 ms"), when the brief has it.
  final String? rawValue;

  /// A valid sleep reading whose baseline is still too young to compare.
  final bool buildingBaseline;

  /// The plain sentence after the label: "normal for you, 58 ms".
  String get detail {
    if (!usable) {
      return buildingBaseline && rawValue != null
          ? '$rawValue, baseline still building'
          : 'not enough data yet';
    }
    return rawValue == null ? comparison! : '$comparison, $rawValue';
  }

  /// "+0.5", "-1.2", or "Not used today".
  String get zText => usable
      ? '${zScore >= 0 ? '+' : ''}${zScore.toStringAsFixed(1)}'
      : 'Not used today';
}

/// The comparison word for a driver's z-score. [inverted] is true for
/// resting heart rate and breathing rate, whose z-scores are negated in the
/// recovery composite (ALGORITHMS.md §1), so a positive z there means a
/// lower reading. Within one spread of the baseline reads "normal for you";
/// two spreads or more reads "much".
String driverComparison(
  double z, {
  required bool inverted,
  String more = 'higher',
  String less = 'lower',
}) {
  final magnitude = z.abs();
  if (magnitude < 1) return 'normal for you';
  final up = inverted ? z < 0 : z > 0;
  final word = up ? more : less;
  return magnitude >= 2 ? 'much $word than usual' : '$word than usual';
}

/// The weights of a night score, for payloads that predate published
/// weights (scoring < 2.3).
const _nightWeights = {
  'hrv_sdnn': 55,
  'resting_hr': 20,
  'sleep_minutes': 15,
  'resp_rate': 5,
  'prev_strain': 5,
};

/// Builds the driver rows in the composite's weight order. A night score
/// has HRV, resting heart rate, sleep, breathing and recent training; a
/// morning estimate ([mode] 'morning') has no breathing rate (the watch
/// records it only asleep) and adds the morning check-in.
List<RecoveryDriver> recoveryDrivers({
  required RecoveryBreakdown breakdown,
  required TodayRaw? todayRaw,
  required bool sleepQualityProven,
  String? mode,
}) {
  final missing = breakdown.missingComponents.toSet();
  final morning = mode == 'morning';
  final weights = breakdown.weights.isEmpty ? _nightWeights : breakdown.weights;
  RecoveryDriver driver({
    required String key,
    required String label,
    required IconData icon,
    required double z,
    required bool inverted,
    String more = 'higher',
    String less = 'lower',
  }) {
    final usable = !missing.contains(key);
    final raw = _rawLabel(key, todayRaw, scored: mode != null);
    return RecoveryDriver(
      key: key,
      label: label,
      icon: icon,
      zScore: z,
      usable: usable,
      weightPercent: weights[key] ?? 0,
      comparison: !usable
          ? null
          : key == 'check_in'
          ? checkInComparison(z)
          : driverComparison(z, inverted: inverted, more: more, less: less),
      // A raw value only accompanies a usable reading, or the one gated
      // sleep exception below; a missing component never shows a number.
      rawValue: usable || key == 'sleep_minutes' ? raw : null,
      buildingBaseline:
          key == 'sleep_minutes' &&
          !usable &&
          raw != null &&
          sleepQualityProven,
    );
  }

  final drivers = [
    driver(
      key: 'hrv_sdnn',
      label: morning
          ? 'Morning HRV'
          : mode == 'night'
          ? 'Overnight HRV'
          : 'Heart rate variability',
      icon: CupertinoIcons.waveform_path_ecg,
      z: breakdown.hrvZ,
      inverted: false,
    ),
    if (morning)
      driver(
        key: 'check_in',
        label: 'Morning check-in',
        icon: CupertinoIcons.person_crop_circle,
        z: breakdown.checkInZ,
        inverted: false,
      ),
    driver(
      key: 'resting_hr',
      label: 'Resting heart rate',
      icon: CupertinoIcons.heart_fill,
      z: breakdown.rhrZ,
      inverted: true,
    ),
    driver(
      key: 'sleep_minutes',
      label: 'Sleep',
      icon: CupertinoIcons.moon_fill,
      z: breakdown.sleepZ,
      inverted: false,
      more: 'more',
      less: 'less',
    ),
    if (!morning)
      driver(
        key: 'resp_rate',
        label: 'Breathing rate',
        icon: CupertinoIcons.wind,
        z: breakdown.respRateZ,
        inverted: true,
      ),
    driver(
      key: 'prev_strain',
      label: 'Recent training',
      icon: CupertinoIcons.flame_fill,
      z: breakdown.prevStrainZ,
      inverted: false,
      more: 'more',
      less: 'less',
    ),
  ];
  return drivers;
}

/// The check-in in words: it compares with "OK", not with your usual.
String checkInComparison(double z) {
  if (z >= 1) return 'feeling good';
  if (z <= -1) return 'feeling rough';
  return 'feeling about OK';
}

/// Today's measured value with its unit, or null when the brief predates
/// `today_raw` or the component was not measured today.
///
/// With [scored] (scoring ≥ 2.3) HRV and resting heart rate are the values
/// the score used: the night's or the morning's HRV, and yesterday's
/// resting heart rate.
String? _rawLabel(String key, TodayRaw? raw, {required bool scored}) {
  if (raw == null) return null;
  final hrv = scored ? raw.hrvScoredMs : raw.hrvMs;
  final rhr = scored ? raw.restingHrScoredBpm : raw.restingHrBpm;
  return switch (key) {
    'hrv_sdnn' => hrv == null ? null : '${hrv.round()} ms',
    'resting_hr' =>
      rhr == null ? null : '${rhr.round()} bpm${scored ? ' yesterday' : ''}',
    'sleep_minutes' =>
      raw.sleepMinutes == null ? null : _formatMinutes(raw.sleepMinutes!),
    'resp_rate' =>
      raw.respRateBpm == null
          ? null
          : '${raw.respRateBpm!.round()} breaths a minute',
    'prev_strain' =>
      raw.dailyStrain == null
          ? null
          : 'strain ${raw.dailyStrain!.toStringAsFixed(1)} today',
    _ => null,
  };
}

String _formatMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest min';
  return rest == 0 ? '$hours h' : '$hours h $rest min';
}

class _DriverRow extends StatelessWidget {
  const _DriverRow({required this.driver});

  final RecoveryDriver driver;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: '${driver.label}: ${driver.detail}',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: TracendSpacing.xs),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.surfaceRaised,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  driver.icon,
                  size: 15,
                  color: driver.usable || driver.buildingBaseline
                      ? colors.textSecondary
                      : colors.textTertiary,
                ),
              ),
              const SizedBox(width: TracendSpacing.sm),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: driver.label, style: textTheme.titleSmall),
                      TextSpan(
                        text: ': ${driver.detail}',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The ⓘ "How this is calculated" disclosure: the method in plain words,
/// then each driver's true z-score and weight. Closed by default.
class _HowCalculated extends StatefulWidget {
  const _HowCalculated({required this.drivers, required this.morning});

  final List<RecoveryDriver> drivers;
  final bool morning;

  @override
  State<_HowCalculated> createState() => _HowCalculatedState();
}

class _HowCalculatedState extends State<_HowCalculated> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    // Full motion grows the panel open; Reduce Motion and static show it at
    // once (an AnimatedSize with a zero duration cannot lay out).
    final duration = TracendMotionScope.movement(
      context,
      TracendMotion.standard,
    );
    final panel = _open
        ? Padding(
            padding: const EdgeInsets.only(bottom: TracendSpacing.md),
            child: _Method(drivers: widget.drivers, morning: widget.morning),
          )
        : const SizedBox(width: double.infinity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: 'How this is calculated',
          excludeSemantics: true,
          onTap: _toggle,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.info_circle,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: TracendSpacing.xs),
                  Expanded(
                    child: Text(
                      'How this is calculated',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: duration,
                    curve: TracendMotion.curve,
                    child: Icon(
                      CupertinoIcons.chevron_down,
                      size: 15,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (duration == Duration.zero)
          panel
        else
          AnimatedSize(
            duration: duration,
            curve: TracendMotion.curve,
            alignment: Alignment.topCenter,
            child: panel,
          ),
      ],
    );
  }

  void _toggle() => setState(() => _open = !_open);
}

class _Method extends StatelessWidget {
  const _Method({required this.drivers, required this.morning});

  final List<RecoveryDriver> drivers;
  final bool morning;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final body = textTheme.bodySmall?.copyWith(color: colors.textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Each reading is compared with your own baseline, a running '
          'average of your recent days. The number below is how far today '
          'sits from it, in typical day-to-day swings (a z-score). Within one '
          'swing reads "normal for you". The score weighs the readings as '
          'shown, and leaves out any reading without enough history.',
          style: body,
        ),
        const SizedBox(height: TracendSpacing.xs),
        Text(
          morning
              ? 'No night with your watch was recorded, so this is a morning '
                    'estimate: the HRV your watch took between 4:00 and 12:00, '
                    'compared only with your other mornings, plus your '
                    'check-in. Readings after 12:00 never count, so it '
                    'settles at noon. Wear your watch to bed for a full score.'
              : 'Scored from last night: the HRV your watch took while you '
                    'slept, compared only with your other nights. Readings '
                    'taken while you are awake never count.',
          style: body,
        ),
        const SizedBox(height: TracendSpacing.sm),
        for (final driver in drivers)
          Semantics(
            label: driver.usable
                ? '${driver.label}, z-score ${driver.zText}, '
                      'weight ${driver.weightPercent} percent'
                : '${driver.label}, not used today',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      '${driver.label} · ${driver.weightPercent}%',
                      style: body,
                    ),
                  ),
                  const SizedBox(width: TracendSpacing.sm),
                  Flexible(
                    flex: 2,
                    child: Text(
                      driver.zText,
                      textAlign: TextAlign.end,
                      style: TracendTheme.numeric(
                        colors,
                        fontSize: 13,
                        color: driver.usable
                            ? colors.textPrimary
                            : colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: TracendSpacing.sm),
        Text(
          'Calculated from your Apple Health data and logged workouts. '
          'No AI.',
          style: body,
        ),
      ],
    );
  }
}
