import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

/// One row of the day timeline: a logged meal, a draft awaiting review, or
/// a schedule slot that has not been logged yet.
class TimelineEntry {
  const TimelineEntry._({
    required this.minutes,
    required this.time,
    required this.title,
    this.meal,
    this.scheduled,
  });

  factory TimelineEntry.meal(MealEntry meal, {ScheduledMeal? slot}) {
    final at = meal.loggedAt;
    return TimelineEntry._(
      minutes: at == null ? 24 * 60 : at.hour * 60 + at.minute,
      time: at == null ? '' : _clock(at.hour, at.minute),
      title: slot?.label ?? mealTypeLabel(meal.type),
      meal: meal,
      scheduled: slot,
    );
  }

  factory TimelineEntry.planned(ScheduledMeal slot) => TimelineEntry._(
    minutes: _minutes(slot.time),
    time: slot.time,
    title: slot.label,
    scheduled: slot,
  );

  /// Minutes after midnight, for ordering.
  final int minutes;
  final String time;
  final String title;
  final MealEntry? meal;
  final ScheduledMeal? scheduled;

  bool get isPlanned => meal == null;
  bool get isDraft => meal?.status == 'draft';

  static int _minutes(String time) {
    final parts = time.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return hour * 60 + minute;
  }

  static String _clock(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// Merges the day's schedule and meals into one time-ordered list. A
/// confirmed meal logged from a slot replaces that slot's planned row.
List<TimelineEntry> buildNutritionTimeline(
  List<ScheduledMeal> schedule,
  List<MealEntry> meals,
) {
  final bySlot = <String, MealEntry>{};
  for (final meal in meals) {
    final slot = meal.scheduleItemId;
    if (slot != null && meal.status == 'confirmed') {
      bySlot.putIfAbsent(slot, () => meal);
    }
  }
  final used = <String>{};
  final entries = <TimelineEntry>[];
  for (final slot in schedule) {
    final meal = bySlot[slot.id];
    if (meal != null) {
      used.add(meal.id);
      entries.add(TimelineEntry.meal(meal, slot: slot));
    } else {
      entries.add(TimelineEntry.planned(slot));
    }
  }
  for (final meal in meals) {
    if (!used.contains(meal.id)) entries.add(TimelineEntry.meal(meal));
  }
  entries.sort((a, b) => a.minutes.compareTo(b.minutes));
  return entries;
}

/// The day as one vertical timeline in a single card. Every state carries a
/// word as well as a marker, so color is never the only signal.
class NutritionTimeline extends StatelessWidget {
  const NutritionTimeline({
    required this.entries,
    required this.onReview,
    required this.onDelete,
    required this.onLog,
    this.enabled = true,
    super.key,
  });

  final List<TimelineEntry> entries;
  final ValueChanged<MealEntry> onReview;
  final ValueChanged<MealEntry> onDelete;
  final ValueChanged<ScheduledMeal> onLog;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    if (entries.isEmpty) {
      return PremiumGradientCard(
        child: Row(
          children: [
            Icon(
              CupertinoIcons.square_list,
              color: context.tracendColors.textSecondary,
            ),
            const SizedBox(width: TracendSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nothing logged yet', style: theme.titleMedium),
                  Text(
                    'Snap a photo of your plate or enter it by hand.',
                    style: theme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return PremiumGradientCard(
      padding: const EdgeInsets.fromLTRB(
        TracendSpacing.md,
        TracendSpacing.xs,
        TracendSpacing.xxs,
        TracendSpacing.xs,
      ),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++)
            _TimelineRow(
              entry: entries[i],
              isFirst: i == 0,
              isLast: i == entries.length - 1,
              enabled: enabled,
              onReview: onReview,
              onDelete: onDelete,
              onLog: onLog,
            ),
        ],
      ),
    );
  }
}

enum _Marker { logged, draft, due, upcoming, optional, skipped }

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.entry,
    required this.isFirst,
    required this.isLast,
    required this.enabled,
    required this.onReview,
    required this.onDelete,
    required this.onLog,
  });

  final TimelineEntry entry;
  final bool isFirst;
  final bool isLast;
  final bool enabled;
  final ValueChanged<MealEntry> onReview;
  final ValueChanged<MealEntry> onDelete;
  final ValueChanged<ScheduledMeal> onLog;

  _Marker get _marker {
    if (entry.isDraft) return _Marker.draft;
    if (!entry.isPlanned) return _Marker.logged;
    return switch (entry.scheduled!.status) {
      'due' => _Marker.due,
      'optional' => _Marker.optional,
      'skipped' => _Marker.skipped,
      _ => _Marker.upcoming,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final theme = Theme.of(context).textTheme;
    final marker = _marker;
    final meal = entry.meal;
    final slot = entry.scheduled;
    final muted = marker == _Marker.skipped;
    final status = switch (marker) {
      _Marker.logged => null,
      _Marker.draft => 'Needs review',
      _Marker.due => 'Due now',
      _Marker.upcoming => 'Planned',
      _Marker.optional => 'Optional',
      _Marker.skipped => 'Not logged',
    };
    final statusColor = switch (marker) {
      _Marker.draft || _Marker.due => colors.accentAmber,
      _ => colors.textSecondary,
    };

    final details = <Widget>[
      if (meal != null && meal.items.isNotEmpty) ...[
        Text(
          meal.items.map((item) => item.name).join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.bodyMedium,
        ),
        Semantics(
          label:
              '${meal.calories.round()} kilocalories, protein '
              '${meal.protein.round()} grams, carbohydrate '
              '${meal.carbohydrate.round()} grams, fat ${meal.fat.round()} grams',
          excludeSemantics: true,
          child: Wrap(
            spacing: TracendSpacing.sm,
            children: [
              for (final part in [
                '${meal.calories.round()} kcal',
                'P ${meal.protein.round()}',
                'C ${meal.carbohydrate.round()}',
                'F ${meal.fat.round()}',
              ])
                Text(part, style: TracendTheme.dataUtility(colors)),
            ],
          ),
        ),
      ] else if (entry.isDraft)
        Text('Check the foods before they count.', style: theme.bodyMedium)
      else if (slot != null && meal == null)
        Text(
          slot.foods
              .map(
                (food) => [food['name'], food['quantity']]
                    .whereType<String>()
                    .where((part) => part.isNotEmpty)
                    .join(' '),
              )
              .join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.bodyMedium?.copyWith(
            color: muted ? colors.textSecondary : null,
          ),
        ),
    ];

    final action = switch (marker) {
      _Marker.logged => null,
      _Marker.draft => TextButton(
        key: ValueKey('review-meal-${meal!.id}'),
        onPressed: enabled ? () => onReview(meal) : null,
        child: const Text('Review'),
      ),
      _ => TextButton(
        key: ValueKey('log-scheduled-${slot!.id}'),
        onPressed: enabled ? () => onLog(slot) : null,
        child: const Text('Log'),
      ),
    };

    // Large text leaves no room for side columns: the time joins the title
    // line and the actions move under the details.
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 20;
    final timeText = Text(
      entry.time,
      style: TracendTheme.dataUtility(colors).copyWith(fontSize: 12),
    );
    final menu = meal == null
        ? null
        : _MealMenu(meal: meal, enabled: enabled, onDelete: onDelete);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!stacked)
            SizedBox(
              width: 46,
              child: Padding(
                padding: const EdgeInsets.only(top: TracendSpacing.sm + 2),
                child: timeText,
              ),
            ),
          _Rail(
            marker: marker,
            isFirst: isFirst,
            isLast: isLast,
            colors: colors,
          ),
          const SizedBox(width: TracendSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: TracendSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: TracendSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (stacked && entry.time.isNotEmpty) timeText,
                      Text(
                        entry.title,
                        style: theme.titleMedium?.copyWith(
                          color: muted ? colors.textSecondary : null,
                        ),
                      ),
                      if (status != null)
                        Text(
                          status.toUpperCase(),
                          style: TracendTheme.labelCaps(
                            context,
                            color: statusColor,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  ...details,
                  if (stacked && (action != null || menu != null))
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [?action, ?menu],
                    )
                  else if (entry.isDraft)
                    Align(alignment: Alignment.centerLeft, child: action),
                ],
              ),
            ),
          ),
          if (!stacked && action != null && !entry.isDraft)
            Align(alignment: Alignment.topCenter, child: action),
          if (!stacked && menu != null)
            Align(alignment: Alignment.topCenter, child: menu),
        ],
      ),
    );
  }
}

class _MealMenu extends StatelessWidget {
  const _MealMenu({
    required this.meal,
    required this.enabled,
    required this.onDelete,
  });

  final MealEntry meal;
  final bool enabled;
  final ValueChanged<MealEntry> onDelete;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    key: ValueKey('meal-menu-${meal.id}'),
    enabled: enabled,
    tooltip: 'Meal options',
    // onSelected runs after the menu closes, so the confirmation dialog it
    // opens is not popped along with the menu.
    onSelected: (_) => onDelete(meal),
    icon: Icon(
      CupertinoIcons.ellipsis,
      size: 18,
      color: context.tracendColors.textSecondary,
    ),
    itemBuilder: (context) => [
      PopupMenuItem<String>(
        key: ValueKey('delete-meal-${meal.id}'),
        value: 'delete',
        child: Row(
          children: [
            Icon(
              CupertinoIcons.delete,
              size: 18,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: TracendSpacing.sm),
            const Text('Delete meal'),
          ],
        ),
      ),
    ],
  );
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.marker,
    required this.isFirst,
    required this.isLast,
    required this.colors,
  });

  final _Marker marker;
  final bool isFirst;
  final bool isLast;
  final TracendColors colors;

  static const _dotSize = 18.0;

  @override
  Widget build(BuildContext context) {
    final line = colors.borderSubtle;
    return SizedBox(
      width: 22,
      child: Column(
        children: [
          Container(
            width: 2,
            height: TracendSpacing.sm + 2,
            color: isFirst ? Colors.transparent : line,
          ),
          _dot(),
          Expanded(
            child: Container(
              width: 2,
              color: isLast ? Colors.transparent : line,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot() => switch (marker) {
    _Marker.logged => _filled(colors.stateStable, CupertinoIcons.checkmark),
    _Marker.draft => _filled(colors.accentAmber, CupertinoIcons.sparkles),
    _Marker.due => _ring(colors.accentAmber, 2.5),
    _Marker.upcoming => _ring(colors.textSecondary, 2),
    _Marker.optional => _ring(colors.borderSubtle, 2),
    _Marker.skipped => SizedBox.square(
      dimension: _dotSize,
      child: Center(
        child: Container(width: 8, height: 2, color: colors.textSecondary),
      ),
    ),
  };

  Widget _filled(Color color, IconData icon) => Container(
    width: _dotSize,
    height: _dotSize,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: Icon(icon, size: 11, color: colors.canvas),
  );

  Widget _ring(Color color, double width) => Container(
    width: _dotSize,
    height: _dotSize,
    decoration: BoxDecoration(
      color: colors.surface,
      shape: BoxShape.circle,
      border: Border.all(color: color, width: width),
    ),
  );
}
