import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/widgets/fuel_rail_card.dart';
import 'package:tracend/features/today/widgets/sleep_architecture_card.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

/// Which tile is open.
enum TodayTile { sleep, load, fuel }

/// Sleep, training load and food at a glance, as a bento: Sleep tall on the
/// left, Load and Fuel stacked on the right (all three stacked from 1.3×
/// text). Tapping a tile opens its full card under the tiles, one at a
/// time: the sleep card, the week's load, or the fuel rail.
///
/// Every number is the brief's or Apple Health's own; a tile without data
/// says so instead of showing a figure.
class TodayTiles extends StatefulWidget {
  const TodayTiles({
    required this.computed,
    required this.week,
    required this.today,
    required this.consumed,
    required this.targets,
    required this.fuelDay,
    required this.sleepDay,
    required this.onLogMeal,
    super.key,
  });

  final ComputedMetrics? computed;
  final List<TodayWeekDay> week;
  final DateTime today;

  /// `brief.nutrition` (calories, protein_g, ...).
  final Map<String, dynamic>? consumed;
  final NutritionTargets? targets;

  /// The fuel rail's day; null while the meal plan loads.
  final FuelDay? fuelDay;

  /// Last night's Apple Health sleep, for the stage bar; null when missing.
  final HealthDay? sleepDay;
  final VoidCallback? onLogMeal;

  @override
  State<TodayTiles> createState() => _TodayTilesState();
}

class _TodayTilesState extends State<TodayTiles> {
  TodayTile? _open;

  void _toggle(TodayTile tile) =>
      setState(() => _open = _open == tile ? null : tile);

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final sleep = _SleepTile(
      computed: widget.computed,
      sleepDay: widget.sleepDay,
      selected: _open == TodayTile.sleep,
      onTap: () => _toggle(TodayTile.sleep),
    );
    final load = _LoadTile(
      acwr: widget.computed?.scores.acwr,
      week: widget.week,
      today: widget.today,
      selected: _open == TodayTile.load,
      onTap: () => _toggle(TodayTile.load),
    );
    final fuel = _FuelTile(
      consumed: widget.consumed,
      targets: widget.targets,
      selected: _open == TodayTile.fuel,
      onTap: () => _toggle(TodayTile.fuel),
    );
    final Widget grid = large
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sleep,
              const SizedBox(height: TracendSpacing.xs),
              load,
              const SizedBox(height: TracendSpacing.xs),
              fuel,
            ],
          )
        : IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 23, child: sleep),
                const SizedBox(width: TracendSpacing.xs),
                Expanded(
                  flex: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      load,
                      const SizedBox(height: TracendSpacing.xs),
                      fuel,
                    ],
                  ),
                ),
              ],
            ),
          );

    final computed = widget.computed;
    final Widget? detail = switch (_open) {
      TodayTile.sleep when computed != null => SleepArchitectureCard(
        computed: computed,
      ),
      TodayTile.load => _LoadDetail(
        acwr: computed?.scores.acwr,
        week: widget.week,
        today: widget.today,
      ),
      TodayTile.fuel => FuelRailCard(
        consumed: widget.consumed,
        targets: widget.targets,
        day: widget.fuelDay,
        onLog: widget.onLogMeal,
      ),
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        grid,
        _Reveal(
          child: detail == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: TracendSpacing.xs),
                  child: detail,
                ),
        ),
      ],
    );
  }
}

/// The shared tile frame: a surface with a label, pressed and selected
/// states, and a hint that it opens.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.onTap,
    required this.child,
    this.footer,
  });

  final String label;
  final String semanticLabel;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  /// Pinned to the bottom when the tile is taller than its content.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.97,
      semanticLabel:
          '$semanticLabel. ${selected ? 'Closes' : 'Opens'} the details',
      borderRadius: BorderRadius.circular(TracendRadii.card),
      child: AnimatedContainer(
        duration: TracendMotionScope.fade(context, TracendMotion.quick),
        padding: const EdgeInsets.all(TracendSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? colors.surfaceRaised : colors.surface,
          borderRadius: BorderRadius.circular(TracendRadii.card),
          border: Border.all(
            color: selected ? colors.accentSignalRing : colors.borderHairline,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: 2),
                child,
              ],
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.only(top: TracendSpacing.sm),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

class _SleepTile extends StatelessWidget {
  const _SleepTile({
    required this.computed,
    required this.sleepDay,
    required this.selected,
    required this.onTap,
  });

  final ComputedMetrics? computed;
  final HealthDay? sleepDay;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final minutes = computed?.todayRaw?.sleepMinutes;
    final debt = computed?.scores.sleepDebtMinutes;
    final quality = computed?.scores.sleepQuality;
    final value = minutes == null ? 'No data' : sleepDuration(minutes);
    final note = debt != null && debt > 0
        ? '${sleepDuration(debt)} sleep debt'
        : quality != null
        ? 'Quality $quality'
        : minutes == null
        ? 'Wear your watch tonight'
        : 'No debt this week';
    final day = sleepDay;
    return _Tile(
      label: 'Sleep',
      semanticLabel: 'Sleep $value, $note',
      selected: selected,
      onTap: onTap,
      footer: day != null && day.sleepMinutes != null && day.sleepMinutes! > 0
          ? _StageBar(day: day)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TracendTheme.numeric(
              colors,
              fontSize: minutes == null ? 18 : 24,
            ),
          ),
          Text(
            note,
            style: textTheme.bodySmall?.copyWith(
              color: debt != null && debt > 0
                  ? colors.accentAmber
                  : colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Last night as one bar: deep, REM and the rest, in proportion. Apple
/// Health gives totals per stage, not a timeline, so it is a share bar.
class _StageBar extends StatelessWidget {
  const _StageBar({required this.day});

  final HealthDay day;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final total = day.sleepMinutes!;
    final deep = (day.sleepDeepMinutes ?? 0).clamp(0, total);
    final rem = (day.sleepRemMinutes ?? 0).clamp(0, total - deep);
    final rest = total - deep - rem;
    Widget part(int minutes, Color color) => minutes <= 0
        ? const SizedBox.shrink()
        : Expanded(
            flex: minutes,
            child: Container(height: 10, color: color),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Row(
            children: [
              part(deep, colors.accentSignalRing),
              part(rem, colors.accentSignalRing.withValues(alpha: 0.5)),
              part(rest, colors.textSecondary.withValues(alpha: 0.35)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: TracendSpacing.xs,
          children: [
            for (final label in [
              'Deep ${sleepDuration(deep)}',
              'REM ${sleepDuration(rem)}',
            ])
              Text(
                label,
                style: textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _LoadTile extends StatelessWidget {
  const _LoadTile({
    required this.acwr,
    required this.week,
    required this.today,
    required this.selected,
    required this.onTap,
  });

  final double? acwr;
  final List<TodayWeekDay> week;
  final DateTime today;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final acwr = this.acwr;
    final words = acwr == null ? 'Building' : loadHeadline(acwr);
    return _Tile(
      label: 'Load',
      semanticLabel: acwr == null
          ? 'Training load still building'
          : 'Training load ${trainingLoadWords(acwr)}',
      selected: selected,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              words,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (week.isNotEmpty)
            SizedBox(
              width: 46,
              height: 22,
              child: _StrainBars(week: week, today: today, gap: 2),
            ),
        ],
      ),
    );
  }
}

class _FuelTile extends StatelessWidget {
  const _FuelTile({
    required this.consumed,
    required this.targets,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic>? consumed;
  final NutritionTargets? targets;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final protein = ((consumed?['protein_g'] as num?) ?? 0).toDouble();
    final calories = ((consumed?['calories'] as num?) ?? 0).toDouble();
    final targets = this.targets;
    final String value;
    final String note;
    final double? fraction;
    if (targets == null) {
      value = '${groupedThousands(calories.round())} kcal';
      note = 'eaten, no target set';
      fraction = null;
    } else if (targets.protein - protein <= 0) {
      value = '${protein.round()} g';
      note = 'protein target reached';
      fraction = 1;
    } else {
      value = '${(targets.protein - protein).round()} g';
      note = 'protein to go';
      fraction = targets.protein <= 0 ? 0 : protein / targets.protein;
    }
    return _Tile(
      label: 'Fuel',
      semanticLabel: 'Fuel, $value $note',
      selected: selected,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 4,
            children: [
              Text(value, style: TracendTheme.numeric(colors, fontSize: 18)),
              Text(
                note,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          if (fraction != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: fraction.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: colors.surfaceRaised,
                valueColor: AlwaysStoppedAnimation(colors.accentSignalRing),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The week's training strain, Monday to Sunday, one bar a day; today's bar
/// in the accent, later days left empty.
class _StrainBars extends StatelessWidget {
  const _StrainBars({required this.week, required this.today, this.gap = 4});

  final List<TodayWeekDay> week;
  final DateTime today;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final highest = week.fold<double>(
      0,
      (max, day) => (day.strain ?? 0) > max ? day.strain! : max,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < week.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(
            child: FractionallySizedBox(
              heightFactor: highest <= 0 || week[i].date.isAfter(today)
                  ? 0.08
                  : ((week[i].strain ?? 0) / highest).clamp(0.08, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _isSameDay(week[i].date, today)
                      ? colors.accentSignalRing
                      : colors.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The Load tile's detail: the week's strain by day, in words.
class _LoadDetail extends StatelessWidget {
  const _LoadDetail({
    required this.acwr,
    required this.week,
    required this.today,
  });

  final double? acwr;
  final List<TodayWeekDay> week;
  final DateTime today;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final acwr = this.acwr;
    return Container(
      padding: const EdgeInsets.all(TracendSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(TracendRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            acwr == null
                ? 'Training load is still building'
                : 'Training load ${trainingLoadWords(acwr)}',
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: 2),
          Text(
            acwr == null
                ? 'It needs 14 days of training to compare against.'
                : 'Last 7 days against your 4-week average · '
                      'ratio ${acwr.toStringAsFixed(2)}',
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          if (week.isNotEmpty) ...[
            const SizedBox(height: TracendSpacing.md),
            SizedBox(
              height: 64,
              child: _StrainBars(week: week, today: today),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (var i = 0; i < week.length && i < 7; i++)
                  Expanded(
                    child: Text(
                      _letters[i],
                      textAlign: TextAlign.center,
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// "Normal", "Lighter", "Heavier" or "Much heavier" for the Load tile.
String loadHeadline(double acwr) {
  if (acwr < 0.8) return 'Lighter';
  if (acwr <= 1.3) return 'Normal';
  if (acwr <= 1.5) return 'Heavier';
  return 'Much heavier';
}

/// Plain words for an ACWR value.
String trainingLoadWords(double acwr) {
  if (acwr < 0.8) return 'lighter than usual';
  if (acwr <= 1.3) return 'about normal';
  if (acwr <= 1.5) return 'heavier than usual';
  return 'much heavier than usual';
}

/// "6h 48m", "48m" or "7h".
String sleepDuration(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '${rest}m';
  return rest == 0
      ? '${hours}h'
      : '${hours}h ${rest.toString().padLeft(2, '0')}m';
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

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
