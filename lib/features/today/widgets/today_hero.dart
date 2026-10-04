import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/widgets/recovery_readout_card.dart';
import 'package:tracend/features/today/widgets/recovery_tick_ring.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// The top of Today: how recovered you are and why.
///
/// - **Verdict:** the recovery band in words ("Well recovered") and one line
///   naming any driver that pulls the score down ("Sleep less than usual.
///   Everything else is normal for you.").
/// - **Tick ring** ([RecoveryTickRing]): the lit ticks are split between the
///   drivers that counted today, lime when a driver is normal or better and
///   amber when it pulls the score down. Inside: the score counting up, the
///   band pill and the change from yesterday.
/// - **HRV and resting heart rate** under the ring, each against your normal.
/// - **Driver chips**: one per driver, grey with "no data" when it did not
///   count. Tapping a chip lights only that driver's ticks; tapping the ring
///   or a chip opens the drivers card ([RecoveryReadoutCard]) in place.
/// - **Checked in** chip once today's check-in is saved; tapping it reopens
///   the check-in to update it.
/// - The sync row, and what the last sync could not refresh.
///
/// Score states: a scored day draws the ring; computed but unscored draws an
/// empty track with "--" and how to get a score; no computed block (older or
/// fixture brief) shows the verdict and sync row only. Nothing is filled in.
class TodayHero extends StatefulWidget {
  const TodayHero({
    required this.brief,
    this.onSync,
    this.syncing = false,
    this.syncIssue,
    this.checkedIn = false,
    this.offerCheckIn = false,
    this.onCheckIn,
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

  /// Today's check-in is saved (or queued on this device).
  final bool checkedIn;

  /// Shows a "Check in" chip while today's check-in is missing (after "Not
  /// today", or when no gate bar is shown).
  final bool offerCheckIn;

  /// Opens the check-in; the chips are plain without it.
  final VoidCallback? onCheckIn;

  @override
  State<TodayHero> createState() => _TodayHeroState();
}

/// One driver as the hero shows it.
class _HeroDriver {
  const _HeroDriver({
    required this.short,
    required this.driver,
    required this.pullsDown,
    required this.downWord,
  });

  final String short;
  final RecoveryDriver driver;
  final bool pullsDown;
  final String downWord;

  String get key => driver.key;

  String get chipLabel {
    if (!driver.usable) return '$short no data';
    return pullsDown ? '$short $downWord' : short;
  }
}

class _TodayHeroState extends State<TodayHero> {
  int? _focus;
  bool _open = false;

  /// Chip name and the word for "pulling the score down", per component.
  static const _chipWords = {
    'hrv_sdnn': ('HRV', 'low'),
    'check_in': ('Check-in', 'low'),
    'resting_hr': ('Resting HR', 'high'),
    'sleep_minutes': ('Sleep', 'short'),
    'resp_rate': ('Breathing', 'high'),
    'prev_strain': ('Training', 'heavy'),
  };

  List<_HeroDriver> _drivers(ComputedMetrics computed) {
    final breakdown = computed.scores.recoveryBreakdown;
    if (breakdown == null) return const [];
    final drivers = recoveryDrivers(
      breakdown: breakdown,
      todayRaw: computed.todayRaw,
      sleepQualityProven: computed.scores.sleepQuality != null,
      mode: computed.scores.recoveryMode,
    );
    return [
      for (final driver in drivers)
        _HeroDriver(
          short: _chipWords[driver.key]!.$1,
          driver: driver,
          // Recent training counts against recovery (ALGORITHMS.md §1), so
          // more of it pulls the score down; the others pull it down when
          // they read a spread or more on the wrong side of normal.
          pullsDown:
              driver.usable &&
              (driver.key == 'prev_strain'
                  ? driver.zScore >= 1
                  : driver.zScore <= -1),
          downWord: _chipWords[driver.key]!.$2,
        ),
    ];
  }

  void _toggleFocus(int index) => setState(() {
    _focus = _focus == index ? null : index;
    _open = true;
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final brief = widget.brief;
    final computed = brief.computed;
    final score = computed?.scores.recovery;
    final drivers = computed == null
        ? const <_HeroDriver>[]
        : _drivers(computed);
    final usable = [
      for (var i = 0; i < drivers.length; i++)
        if (drivers[i].driver.usable) i,
    ];
    final ringColor = colors.accentSignalRing;
    final segments = [
      for (final i in usable)
        RingSegment(
          color: drivers[i].pullsDown ? colors.accentAmber : ringColor,
          weight: drivers[i].driver.weightPercent.toDouble(),
        ),
    ];
    final focusSegment = _focus == null ? null : usable.indexOf(_focus!);
    final issue = widget.syncIssue;

    final verdict = Text(
      _verdict(score, computed),
      style: textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        height: 1.08,
      ),
    );
    final reason = Text(
      _reason(score, computed, drivers),
      style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (MediaQuery.textScalerOf(context).scale(1) >= 1.3) ...[
          Semantics(header: true, child: verdict),
          if (widget.checkedIn || widget.offerCheckIn) ...[
            const SizedBox(height: TracendSpacing.xs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _CheckInChip(
                done: widget.checkedIn,
                onTap: widget.onCheckIn,
              ),
            ),
          ],
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Semantics(header: true, child: verdict)),
              if (widget.checkedIn || widget.offerCheckIn) ...[
                const SizedBox(width: TracendSpacing.xs),
                _CheckInChip(done: widget.checkedIn, onTap: widget.onCheckIn),
              ],
            ],
          ),
        const SizedBox(height: TracendSpacing.xxs),
        reason,
        if (computed != null) ...[
          const SizedBox(height: TracendSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final ringSize = math.min(260.0, constraints.maxWidth * 0.78);
              return Center(
                child: _RingGlow(
                  size: ringSize,
                  color: ringColor,
                  child: Pressable(
                    onTap: drivers.isEmpty
                        ? null
                        : () => setState(() => _open = !_open),
                    pressedScale: 0.985,
                    borderRadius: BorderRadius.circular(ringSize),
                    semanticLabel: _ringLabel(score, brief.recoveryPrevious),
                    child: RecoveryTickRing(
                      score: score,
                      segments: segments,
                      focus: focusSegment == -1 ? null : focusSegment,
                      size: ringSize,
                      center: (shown) => _center(colors, score, shown),
                    ),
                  ),
                ),
              );
            },
          ),
          _SideStats(computed: computed, drivers: drivers),
          if (drivers.isNotEmpty) ...[
            const SizedBox(height: TracendSpacing.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                // Training shows only when it weighs on the score; the
                // check-in only once it counts (the Check in chip offers it).
                for (var i = 0; i < drivers.length; i++)
                  if ((drivers[i].key != 'prev_strain' ||
                          drivers[i].pullsDown) &&
                      (drivers[i].key != 'check_in' ||
                          drivers[i].driver.usable))
                    _DriverChip(
                      label: drivers[i].chipLabel,
                      color: !drivers[i].driver.usable
                          ? colors.textTertiary
                          : drivers[i].pullsDown
                          ? colors.accentAmber
                          : ringColor,
                      selected: _focus == i,
                      onTap: drivers[i].driver.usable
                          ? () => _toggleFocus(i)
                          : null,
                    ),
              ],
            ),
          ],
          _Reveal(
            child: _open && computed.scores.recoveryBreakdown != null
                ? Padding(
                    padding: const EdgeInsets.only(top: TracendSpacing.sm),
                    child: RecoveryReadoutCard(computed: computed),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: TracendSpacing.xs),
          Text(
            scoreSource(score, computed),
            style: textTheme.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
        _SyncControl(
          label: _syncLabel(context),
          syncing: widget.syncing,
          onTap: widget.onSync,
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
  }

  Widget _center(TracendColors colors, int? score, int shown) {
    final band = score == null ? 'Not scored' : recoveryBand(score).$1;
    final good = score != null && score >= 65;
    final caution = score != null && score >= 50 && score < 65;
    final previous = widget.brief.recoveryPrevious;
    return RingCenter(
      shown: score == null ? null : shown,
      band: band,
      bandColor: score == null
          ? colors.surfaceRaised
          : good
          ? colors.accentSignal
          : caution
          ? colors.accentAmber.withValues(alpha: 0.22)
          : colors.stateAttention.withValues(alpha: 0.22),
      onBand: score == null
          ? colors.textSecondary
          : good
          ? colors.onAccentSignal
          : colors.textPrimary,
      delta: score == null || previous == null
          ? null
          : changeFromYesterday(score - previous),
    );
  }

  String? _syncLabel(BuildContext context) {
    final brief = widget.brief;

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

/// Where today's score comes from and how sure it is: "From last night ·
/// High confidence", or "Morning estimate, no night recorded · Medium
/// confidence · Settles at 12:00" until noon.
String scoreSource(int? score, ComputedMetrics computed) {
  if (score == null) {
    return 'Not enough data yet for a recovery score. Sync Apple Health and '
        'check in to build your baseline.';
  }
  final confidence = confidenceLabel(computed.dataConfidence);
  return switch (computed.scores.recoveryMode) {
    'night' => 'From last night · $confidence',
    'morning' =>
      'Morning estimate, no night recorded · $confidence'
          '${computed.scores.recoverySettled == false ? ' · Settles at 12:00' : ''}',
    _ => 'Recovery score · $confidence',
  };
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

/// The recovery band in words, for the verdict.
String _verdict(int? score, ComputedMetrics? computed) {
  if (computed == null) return 'Your day';
  if (score == null) return 'Recovery not scored yet';
  if (score >= 80) return 'Fully recovered';
  if (score >= 65) return 'Well recovered';
  if (score >= 50) return 'Partly recovered';
  if (score >= 35) return 'Under-recovered';
  return 'Very under-recovered';
}

/// One line naming what pulls the score down, from the drivers.
String _reason(
  int? score,
  ComputedMetrics? computed,
  List<_HeroDriver> drivers,
) {
  if (computed == null) {
    return 'Sync Apple Health to see how recovered you are.';
  }
  if (score == null || drivers.isEmpty) {
    return 'Your score appears once Tracend has enough nights to compare.';
  }
  final down = [
    for (final d in drivers)
      if (d.pullsDown) '${d.driver.label} ${d.driver.comparison}',
  ];
  if (down.isEmpty) {
    // No reading is a full swing off, but under 50 more of them sit a
    // little below normal than above it; saying "normal" would contradict
    // an under-recovered verdict.
    return score < 50
        ? 'Nothing is far off your normal, but more sits a little below it '
              'than above.'
        : 'Everything that counted today is normal for you.';
  }
  // "Sleep less than usual, resting heart rate higher than usual."
  final named = [
    down.first,
    for (final part in down.skip(1))
      '${part[0].toLowerCase()}${part.substring(1)}',
  ].join(', ');
  return '$named. Everything else is normal for you.';
}

/// "+6 from yesterday", "-4 from yesterday" or "Same as yesterday".
String changeFromYesterday(int change) {
  if (change == 0) return 'Same as yesterday';
  return '${change > 0 ? '+' : ''}$change from yesterday';
}

String _ringLabel(int? score, int? previous) {
  if (score == null) return 'Recovery not scored yet';
  final band = recoveryBand(score).$1;
  final delta = previous == null
      ? ''
      : '. ${changeFromYesterday(score - previous)}';
  return 'Recovery $score, $band$delta. Shows what built the score';
}

/// A soft light in the ring's colour behind it.
class _RingGlow extends StatelessWidget {
  const _RingGlow({
    required this.size,
    required this.color,
    required this.child,
  });

  final double size;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: dark ? 0.14 : 0.10),
            color.withValues(alpha: 0),
          ],
          stops: const [0.15, 0.72],
        ),
      ),
      child: child,
    );
  }
}

/// HRV on the left and resting heart rate on the right, each with how it
/// compares with your normal. A missing reading is left out.
class _SideStats extends StatelessWidget {
  const _SideStats({required this.computed, required this.drivers});

  final ComputedMetrics computed;
  final List<_HeroDriver> drivers;

  @override
  Widget build(BuildContext context) {
    final raw = computed.todayRaw;
    // The values the score used (scoring 2.3): the night's or the morning's
    // HRV and yesterday's resting heart rate.
    final scored = computed.scores.recoveryMode != null;
    final hrv = scored ? raw?.hrvScoredMs : raw?.hrvMs;
    final rhr = scored ? raw?.restingHrScoredBpm : raw?.restingHrBpm;
    if (hrv == null && rhr == null) return const SizedBox.shrink();
    String? word(String key) {
      final match = drivers.where((d) => d.key == key && d.driver.usable);
      if (match.isEmpty) return null;
      final comparison = match.first.driver.comparison!;
      return comparison == 'normal for you' ? 'normal' : comparison;
    }

    return Padding(
      padding: const EdgeInsets.only(top: TracendSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (hrv != null)
            Expanded(
              child: _Stat(
                value: '${hrv.round()}',
                unit: 'ms',
                label: word('hrv_sdnn') == null
                    ? 'HRV'
                    : 'HRV · ${word('hrv_sdnn')}',
                spoken: 'Heart rate variability ${hrv.round()} milliseconds',
              ),
            )
          else
            const Spacer(),
          if (rhr != null)
            Expanded(
              child: _Stat(
                value: '${rhr.round()}',
                unit: 'bpm',
                label: word('resting_hr') == null
                    ? 'Resting HR'
                    : 'Resting HR · ${word('resting_hr')}',
                spoken: 'Resting heart rate ${rhr.round()} beats a minute',
                end: true,
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.unit,
    required this.label,
    required this.spoken,
    this.end = false,
  });

  final String value;
  final String unit;
  final String label;
  final String spoken;
  final bool end;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: '$spoken. $label',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: end
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TracendTheme.numeric(colors, fontSize: 22),
                ),
                TextSpan(
                  text: ' $unit',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            label,
            textAlign: end ? TextAlign.end : TextAlign.start,
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// A driver chip: a dot in the driver's colour and its name.
class _DriverChip extends StatelessWidget {
  const _DriverChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final chip = AnimatedContainer(
      duration: TracendMotionScope.fade(context, TracendMotion.quick),
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TracendRadii.pill),
        border: Border.all(
          color: selected ? colors.accentSignalRing : colors.borderSubtle,
        ),
        color: selected ? colors.accentSignalTint : Colors.transparent,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return Semantics(label: label, excludeSemantics: true, child: chip);
    }
    return Pressable(
      onTap: onTap,
      semanticLabel: '$label. Highlights this driver',
      borderRadius: BorderRadius.circular(TracendRadii.pill),
      child: chip,
    );
  }
}

/// "Checked in" once today's check-in is saved, tapping to update it; or
/// "Check in", lime-edged, while it is missing.
class _CheckInChip extends StatelessWidget {
  const _CheckInChip({required this.done, required this.onTap});

  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final chip = Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TracendRadii.pill),
        border: Border.all(
          color: done ? colors.borderSubtle : colors.accentSignalRing,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? CupertinoIcons.checkmark_alt : CupertinoIcons.sun_max,
            size: 14,
            color: colors.accentSignalInk,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              done ? 'Checked in' : 'Check in',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return Pressable(
      onTap: onTap,
      semanticLabel: done
          ? 'Checked in. Update today\'s check-in'
          : 'Check in for today',
      borderRadius: BorderRadius.circular(TracendRadii.pill),
      child: chip,
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

/// Grows or shrinks to its child at full motion; snaps without motion, so
/// a zero-length size animation never re-lays itself out mid-layout.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = TracendMotionScope.movement(
      context,
      TracendMotion.standard,
    );
    if (duration == Duration.zero) return child;
    return AnimatedSize(
      duration: duration,
      curve: TracendMotion.curve,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}
