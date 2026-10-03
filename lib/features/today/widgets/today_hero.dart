import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/micro_motion.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// The "Today" verdict card, built like a training app's readiness screen:
/// a recovery dial in the band's colour with the score counting up inside,
/// the band chip and the day's verdict beside it, today's vitals (sleep,
/// resting heart rate, heart rate variability) as big numbers, and the sync
/// control.
///
/// It is a decision surface only. The workout, the check-in and the evidence
/// sit below it on Today; nothing here is a disabled button.
///
/// Score states:
/// - score present: the dial filled to the score, the band chip
///   (Excellent/Good/Moderate/Low/Poor) and the confidence word
/// - computed present but score null: an empty dial with `--` and honest
///   next-step copy
/// - no computed block (older or fixture brief): no dial and no vitals
///
/// The vitals row shows only today's measured values; a missing reading is
/// left out, never filled in.
///
/// The sync row runs the sync-everything pipeline (Apple Health when
/// connected, the brief and today's decision). Its time is the last Apple
/// Health sync, written for people ("Today, 9:05 AM"), never an ISO date.
class TodayHero extends StatelessWidget {
  const TodayHero({
    required this.brief,
    this.onSync,
    this.syncing = false,
    this.syncIssue,
    super.key,
  });

  final DailyBrief brief;

  /// Sync-everything pipeline. Null renders the sync status as plain text.
  final VoidCallback? onSync;

  /// True while the sync pipeline runs.
  final bool syncing;

  /// What the last sync could not refresh, kept on screen until a sync
  /// succeeds, so the toast that reported it is never the only copy.
  final String? syncIssue;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final computed = brief.computed;
    final score = computed?.scores.recovery;
    final issue = syncIssue;
    final tone = score == null ? null : recoveryBand(score).$2;
    final toneColor = tone == null ? null : _toneColor(colors, tone);

    final header = SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: TracendSpacing.xs,
        runSpacing: TracendSpacing.xs,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Today',
              style: textTheme.titleSmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          if (score != null) _BandChip(score: score),
        ],
      ),
    );

    final verdict = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          brief.nextAction,
          style: textTheme.headlineSmall?.copyWith(height: 1.15),
        ),
        const SizedBox(height: TracendSpacing.xxs),
        Text(
          brief.reason,
          style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
      ],
    );

    final confidence = computed == null
        ? null
        : Text(
            score == null
                ? 'Not enough data yet for a recovery score. Sync Apple '
                      'Health and check in to build your baseline.'
                : 'Recovery score · '
                      '${confidenceLabel(computed.dataConfidence)}',
            style: textTheme.bodySmall?.copyWith(color: colors.textTertiary),
          );

    final vitals = _vitals(computed?.todayRaw);

    return ClipRRect(
      borderRadius: BorderRadius.circular(TracendRadii.card),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          // One quiet light source behind the dial, in the band's colour.
          gradient: toneColor == null
              ? null
              : RadialGradient(
                  center: const Alignment(-0.85, -0.75),
                  radius: 1.1,
                  colors: [
                    Color.alphaBlend(
                      toneColor.withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark
                            ? 0.16
                            : 0.09,
                      ),
                      colors.surface,
                    ),
                    colors.surface,
                  ],
                ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            TracendSpacing.gutter,
            TracendSpacing.gutter,
            TracendSpacing.gutter,
            TracendSpacing.xxs,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final sideBySide = constraints.maxWidth >= 300 && scale <= 1.3;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  if (computed != null) ...[
                    const SizedBox(height: TracendSpacing.sm),
                    if (sideBySide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _RecoveryDial(
                            score: score,
                            color: toneColor,
                            size: 132,
                          ),
                          if (vitals.isNotEmpty) ...[
                            const SizedBox(width: TracendSpacing.md),
                            Expanded(child: _VitalsList(vitals: vitals)),
                          ],
                        ],
                      )
                    else ...[
                      Center(
                        child: _RecoveryDial(
                          score: score,
                          color: toneColor,
                          size: 168,
                        ),
                      ),
                      if (vitals.isNotEmpty) ...[
                        const SizedBox(height: TracendSpacing.md),
                        _VitalsList(vitals: vitals),
                      ],
                    ],
                  ],
                  const SizedBox(height: TracendSpacing.md),
                  verdict,
                  if (confidence != null) ...[
                    const SizedBox(height: TracendSpacing.sm),
                    confidence,
                  ],
                  const SizedBox(height: TracendSpacing.sm),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: colors.borderHairline,
                  ),
                  _SyncControl(
                    label: _syncLabel(context),
                    syncing: syncing,
                    onTap: onSync,
                  ),
                  if (issue != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: TracendSpacing.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(
                              CupertinoIcons.exclamationmark_circle_fill,
                              size: 15,
                              color: colors.accentAmber,
                            ),
                          ),
                          const SizedBox(width: TracendSpacing.xs),
                          Expanded(
                            child: Text(
                              issue,
                              style: textTheme.bodySmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Today's measured vitals, in the order an athlete reads them.
  static List<_Vital> _vitals(TodayRaw? raw) {
    if (raw == null) return const [];
    final sleep = raw.sleepMinutes;
    final rhr = raw.restingHrBpm;
    final hrv = raw.hrvMs;
    return [
      if (sleep != null)
        _Vital(
          icon: CupertinoIcons.moon_fill,
          label: 'Sleep',
          value: '${sleep ~/ 60}h ${(sleep % 60).toString().padLeft(2, '0')}',
          unit: 'min',
          spoken: '${sleep ~/ 60} hours ${sleep % 60} minutes',
        ),
      if (rhr != null)
        _Vital(
          icon: CupertinoIcons.heart_fill,
          label: 'Resting HR',
          value: '${rhr.round()}',
          unit: 'bpm',
          spoken: '${rhr.round()} beats a minute',
        ),
      if (hrv != null)
        _Vital(
          icon: CupertinoIcons.waveform_path_ecg,
          label: 'HRV',
          value: '${hrv.round()}',
          unit: 'ms',
          spoken: '${hrv.round()} milliseconds',
        ),
    ];
  }

  /// The last Apple Health sync from the brief's health payload, as
  /// "Today, 9:05 AM". Falls back to the health summary's day ("Mon 24
  /// Aug"); the decision time is never used, because a stale decision would
  /// misreport the sync state.
  String? _syncLabel(BuildContext context) {
    final lastSynced = brief.health?['last_synced_at'] as String?;
    final parsed = lastSynced == null ? null : DateTime.tryParse(lastSynced);
    if (parsed != null) {
      final local = parsed.toLocal();
      final time = MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(local),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );
      return '${friendlyDate(local)}, $time';
    }
    final healthDate = brief.health?['local_date'] as String?;
    final day = healthDate == null ? null : DateTime.tryParse(healthDate);
    return day == null ? null : friendlyDate(day);
  }
}

/// "High confidence", "Medium confidence", "Low confidence", or "Building
/// baseline" for a cold start, from the brief's `data_confidence`.
String confidenceLabel(String? confidence) => switch (confidence) {
  'high' => 'High confidence',
  'medium' => 'Medium confidence',
  'low' => 'Low confidence',
  _ => 'Building baseline',
};

/// The recovery band word, its status tone and icon. Bands follow the
/// recovery score scale (DESIGN_SYSTEM.md §5.2).
(String, StatusTone, IconData) recoveryBand(int score) {
  if (score >= 80) {
    return ('Excellent', StatusTone.good, CupertinoIcons.checkmark_circle_fill);
  }
  if (score >= 65) {
    return ('Good', StatusTone.good, CupertinoIcons.checkmark_circle_fill);
  }
  if (score >= 50) {
    return ('Moderate', StatusTone.caution, CupertinoIcons.minus_circle_fill);
  }
  if (score >= 35) {
    return ('Low', StatusTone.low, CupertinoIcons.exclamationmark_circle_fill);
  }
  return ('Poor', StatusTone.low, CupertinoIcons.exclamationmark_circle_fill);
}

Color _toneColor(TracendColors colors, StatusTone tone) => switch (tone) {
  StatusTone.good => colors.stateStable,
  StatusTone.caution => colors.accentAmber,
  StatusTone.low => colors.stateAttention,
  _ => colors.textSecondary,
};

class _BandChip extends StatelessWidget {
  const _BandChip({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final (label, tone, icon) = recoveryBand(score);
    return Semantics(
      label: 'Recovery band: $label',
      excludeSemantics: true,
      child: StatusChip(label: label, icon: icon, tone: tone),
    );
  }
}

/// The recovery dial: a 270° arc filled to the score in the band's colour,
/// with the score counting up inside. The arc sweeps in once; under reduced
/// motion it is drawn at its value.
class _RecoveryDial extends StatelessWidget {
  const _RecoveryDial({
    required this.score,
    required this.color,
    required this.size,
  });

  final int? score;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final score = this.score;
    final animate = TracendMotionScope.of(context) == TracendMotionLevel.full;
    final fraction = score == null ? 0.0 : (score / 100).clamp(0.0, 1.0);
    final numberStyle = TextStyle(
      fontFamily: TracendFonts.displayFamily,
      fontWeight: FontWeight.w800,
      fontSize: size * 0.34,
      height: 1,
      letterSpacing: -1.2,
      color: colors.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      label: score == null
          ? 'Recovery score unavailable'
          : 'Recovery score $score out of 100',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: animate ? 0 : fraction, end: fraction),
          duration: animate
              ? const Duration(milliseconds: 1100)
              : Duration.zero,
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => CustomPaint(
            painter: _DialPainter(
              progress: value,
              track: colors.surfaceRaised,
              fill: color ?? colors.textTertiary,
              stroke: size * 0.085,
            ),
            child: child,
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(size * 0.16),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (score == null)
                      Text('--', style: numberStyle)
                    else
                      MicroMotionCountUp(
                        value: score,
                        builder: (context, value) =>
                            Text('$value', style: numberStyle),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      'Recovery',
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.progress,
    required this.track,
    required this.fill,
    required this.stroke,
  });

  final double progress;
  final Color track;
  final Color fill;
  final double stroke;

  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2 + 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(rect, _start, _sweep, false, base..color = track);
    if (progress <= 0) return;
    final sweep = _sweep * progress;
    canvas.drawArc(
      rect,
      _start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..color = fill.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawArc(rect, _start, sweep, false, base..color = fill);
    // A bright head where the arc ends, like a needle.
    final angle = _start + sweep;
    final radius = rect.width / 2;
    final head =
        rect.center + Offset(math.cos(angle), math.sin(angle)) * radius;
    canvas.drawCircle(
      head,
      stroke * 0.28,
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.progress != progress ||
      old.track != track ||
      old.fill != fill ||
      old.stroke != stroke;
}

@immutable
class _Vital {
  const _Vital({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.spoken,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final String spoken;
}

/// Today's vitals beside the dial, one per line: the icon and name, then
/// the value as a big number with its unit. Lines are separated by
/// hairlines, so the group reads as one instrument panel.
class _VitalsList extends StatelessWidget {
  const _VitalsList({required this.vitals});

  final List<_Vital> vitals;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    Widget line(_Vital vital) => Semantics(
      label: '${vital.label}: ${vital.spoken}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(vital.icon, size: 15, color: colors.textTertiary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                vital.label,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: vital.value,
                        style: TextStyle(
                          fontFamily: TracendFonts.numericFamily,
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          height: 1,
                          color: colors.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      TextSpan(
                        text: ' ${vital.unit}',
                        style: TextStyle(
                          fontFamily: TracendFonts.numericFamily,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < vitals.length; i++) ...[
          if (i > 0)
            Divider(height: 1, thickness: 1, color: colors.borderHairline),
          line(vitals[i]),
        ],
      ],
    );
  }
}

/// The sync row at the foot of the card. States:
/// - syncing: spinner + "Syncing"
/// - idle with a time: refresh icon + "Sync · Today, 9:05 AM"
/// - idle without a time: refresh icon + "Sync"
/// - [onTap] null: the same text, not tappable
class _SyncControl extends StatelessWidget {
  const _SyncControl({
    required this.label,
    required this.syncing,
    required this.onTap,
  });

  final String? label;
  final bool syncing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final text = syncing
        ? 'Syncing'
        : label == null
        ? 'Sync'
        : 'Sync · $label';
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 16,
            child: syncing
                ? CupertinoActivityIndicator(
                    radius: 7,
                    color: colors.textSecondary,
                  )
                : Icon(
                    CupertinoIcons.arrow_2_circlepath,
                    size: 16,
                    color: colors.textSecondary,
                  ),
          ),
          const SizedBox(width: TracendSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
    if (onTap == null || syncing) return row;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.98,
      semanticLabel:
          '$text. Syncs Apple Health, the daily brief and the coach decision',
      borderRadius: BorderRadius.circular(TracendRadii.control),
      child: row,
    );
  }
}
