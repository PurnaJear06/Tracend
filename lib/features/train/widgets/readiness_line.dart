import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/train/train_view_models.dart';
import 'package:tracend/features/train/widgets/train_parts.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';

/// One measure in the readiness sheet, in plain words.
@immutable
class ReadinessMeasure {
  const ReadinessMeasure({
    required this.label,
    required this.icon,
    required this.note,
    this.value,
  });

  final String label;
  final IconData icon;

  /// The measured value with its unit; null when there is none today.
  final String? value;

  /// How it compares with the athlete's usual, never a z-score.
  final String note;
}

/// Plain-word comparisons of today's sleep, HRV and resting heart rate with
/// the athlete's own baselines. A difference of one usual spread or more
/// counts as above or below usual. The HRV baseline is stored as ln(ms), so
/// its usual value is `exp(ewma)`.
///
/// HRV and resting heart rate are the readings recovery scored (scoring
/// 2.3): last night's HRV against your nights, or this morning's against
/// your mornings, and yesterday's resting heart rate.
List<ReadinessMeasure> readinessMeasures(ComputedMetrics? computed) {
  final raw = computed?.todayRaw;
  final baselines = computed?.baselines;
  const missing = 'Not enough data yet';

  String compare({
    required double value,
    required BaselineMetric? baseline,
    required double Function(double) transform,
    required String higher,
    required String lower,
    String? usual,
  }) {
    if (baseline == null || baseline.nObs < 3 || baseline.spread <= 0) {
      return 'Building your baseline';
    }
    final z = (transform(value) - baseline.ewma) / baseline.spread;
    final word = z >= 1
        ? higher
        : z <= -1
        ? lower
        : 'Normal for you';
    return usual == null ? word : '$word, usually $usual';
  }

  final sleep = raw?.sleepMinutes;
  final mode = computed?.scores.recoveryMode;
  final hrv = mode == null ? raw?.hrvMs : raw?.hrvScoredMs;
  final rhr = mode == null ? raw?.restingHrBpm : raw?.restingHrScoredBpm;
  final hrvBaseline = switch (mode) {
    'night' => baselines?.hrvSleep,
    'morning' => baselines?.hrvMorning,
    _ => baselines?.hrv,
  };
  return [
    ReadinessMeasure(
      label: 'Sleep',
      icon: CupertinoIcons.moon,
      value: sleep == null || sleep <= 0
          ? null
          : '${sleep ~/ 60} h ${sleep % 60} min',
      note: sleep == null || sleep <= 0
          ? missing
          : compare(
              value: sleep.toDouble(),
              baseline: baselines?.sleepMinutes,
              transform: (v) => v,
              higher: 'More than usual',
              lower: 'Less than usual',
            ),
    ),
    ReadinessMeasure(
      label: switch (mode) {
        'night' => 'Overnight HRV',
        'morning' => 'Morning HRV',
        _ => 'Heart rate variability',
      },
      icon: CupertinoIcons.waveform_path,
      value: hrv == null || hrv <= 0 ? null : '${hrv.round()} ms',
      note: hrv == null || hrv <= 0
          ? missing
          : compare(
              value: hrv,
              baseline: hrvBaseline,
              transform: math.log,
              higher: 'Higher than usual',
              lower: 'Lower than usual',
              usual: hrvBaseline == null
                  ? null
                  : '${math.exp(hrvBaseline.ewma).round()} ms',
            ),
    ),
    ReadinessMeasure(
      label: mode == null
          ? 'Resting heart rate'
          : 'Resting heart rate, yesterday',
      icon: CupertinoIcons.heart,
      value: rhr == null || rhr <= 0 ? null : '${rhr.round()} bpm',
      note: rhr == null || rhr <= 0
          ? missing
          : compare(
              value: rhr,
              baseline: baselines?.restingHr,
              transform: (v) => v,
              higher: 'Higher than usual',
              lower: 'Lower than usual',
            ),
    ),
  ];
}

/// The readiness row above the workout: one sentence about recovery state
/// and, when Today has a decision for today, its verdict below it.
class ReadinessLineRow extends StatelessWidget {
  const ReadinessLineRow({
    required this.line,
    required this.onTap,
    this.verdict,
    super.key,
  });

  final ReadinessLine line;
  final String? verdict;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final tone = switch (line.band) {
      RecoveryBand.excellent || RecoveryBand.good => colors.stateStable,
      RecoveryBand.moderate => colors.accentAmber,
      RecoveryBand.low || RecoveryBand.poor => colors.stateAttention,
      null => colors.textSecondary,
    };
    final icon = line.needsHealth
        ? CupertinoIcons.heart
        : CupertinoIcons.heart_fill;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 18, color: tone),
            ),
            const SizedBox(width: TracendSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.text, style: textTheme.titleSmall),
                  if (verdict != null) ...[
                    const SizedBox(height: 1),
                    Text('Today: $verdict', style: textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            const SizedBox(width: TracendSpacing.xs),
            Icon(
              CupertinoIcons.chevron_forward,
              size: 16,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the readiness sheet. Without Apple Health it explains where to
/// connect; [onOpenAccount] adds a button when the host can open Account.
Future<void> showReadinessSheet(
  BuildContext context, {
  required ReadinessLine line,
  required ComputedMetrics? computed,
  required TrainingLoadSheetModel load,
  VoidCallback? onOpenAccount,
}) {
  if (line.needsHealth) {
    return showTracendSheet<void>(
      context,
      title: 'Apple Health',
      subtitle: 'Recovery needs your health data',
      builder: (sheetContext) => _ConnectHealthBody(
        onOpenAccount: onOpenAccount == null
            ? null
            : () {
                Navigator.of(sheetContext).pop();
                onOpenAccount();
              },
      ),
    );
  }
  return showTracendSheet<void>(
    context,
    title: 'Recovery today',
    subtitle: line.text,
    builder: (_) => _ReadinessBody(computed: computed, load: load),
  );
}

class _ReadinessBody extends StatelessWidget {
  const _ReadinessBody({required this.computed, required this.load});

  final ComputedMetrics? computed;
  final TrainingLoadSheetModel load;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final measures = readinessMeasures(computed);
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final valueStyle = TextStyle(
      fontFamily: TracendFonts.numericFamily,
      fontSize: 16,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: colors.textPrimary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: TracendSpacing.xs),
        TracendGroupedList(
          children: [
            for (final measure in measures)
              TracendListRow(
                leading: TracendRowIcon(icon: measure.icon),
                title: measure.label,
                // Large text moves the value under the label so neither is
                // squeezed off the row.
                subtitle: largeText && measure.value != null
                    ? '${measure.value}. ${measure.note}'
                    : measure.note,
                trailing: largeText || measure.value == null
                    ? null
                    : Text(measure.value!, style: valueStyle),
              ),
            TracendListRow(
              leading: const TracendRowIcon(icon: CupertinoIcons.gauge),
              title: 'Training load',
              subtitle: load.rowLabel,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Calculated from your Apple Health data and logged workouts. '
          'No AI estimates.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ConnectHealthBody extends StatelessWidget {
  const _ConnectHealthBody({this.onOpenAccount});

  final VoidCallback? onOpenAccount;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: TracendSpacing.xs),
      const TrainNote(
        icon: CupertinoIcons.heart,
        text:
            'Connect Apple Health to see your sleep, heart rate variability '
            'and resting heart rate here. Open Account from the Today tab, '
            'then choose Apple Health.',
      ),
      if (onOpenAccount != null) ...[
        const SizedBox(height: TracendSpacing.md),
        OutlinedButton(
          onPressed: onOpenAccount,
          child: const Text('Open Account'),
        ),
      ],
    ],
  );
}
