import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/tracend_confirm.dart';

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

/// The day's meals in one card, in time order. Each row reads as
/// "Lunch · 691 kcal" with its foods and a protein / carbs / fat split bar,
/// and states its status in words, so color is never the only signal.
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: context.tracendColors.borderHairline,
              ),
            _MealRow(
              entry: entries[i],
              enabled: enabled,
              onReview: onReview,
              onDelete: onDelete,
              onLog: onLog,
            ),
          ],
        ],
      ),
    );
  }
}

enum _Marker { logged, draft, due, upcoming, optional, skipped }

class _MealRow extends StatelessWidget {
  const _MealRow({
    required this.entry,
    required this.enabled,
    required this.onReview,
    required this.onDelete,
    required this.onLog,
  });

  final TimelineEntry entry;
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
      _Marker.logged => 'Logged',
      _Marker.draft => 'Needs review',
      _Marker.due => 'Due now',
      _Marker.upcoming => 'Planned',
      _Marker.optional => 'Optional',
      _Marker.skipped => 'Not logged',
    };
    final statusColor = switch (marker) {
      _Marker.logged => colors.stateStable,
      _Marker.draft || _Marker.due => colors.accentAmber,
      _ => colors.textSecondary,
    };
    final logged = meal != null && meal.items.isNotEmpty;
    final title = logged
        ? '${entry.title} · ${meal.calories.round()} kcal'
        : entry.title;

    final foods = logged
        ? meal.items.map((item) => item.name).join(' · ')
        : entry.isDraft
        ? 'Check the foods before they count.'
        : slot != null && meal == null
        ? slot.foods
              .map(
                (food) => [food['name'], food['quantity']]
                    .whereType<String>()
                    .where((part) => part.isNotEmpty)
                    .join(' '),
              )
              .join(' · ')
        : null;

    final action = switch (marker) {
      _Marker.logged => null,
      _Marker.draft => TextButton(
        key: ValueKey('review-meal-${meal!.id}'),
        onPressed: enabled ? () => onReview(meal) : null,
        // Sits under the text, so it aligns with it instead of padding in.
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          alignment: Alignment.centerLeft,
        ),
        child: const Text('Review foods'),
      ),
      _ => TextButton(
        key: ValueKey('log-scheduled-${slot!.id}'),
        onPressed: enabled ? () => onLog(slot) : null,
        child: const Text('Log'),
      ),
    };
    final menu = meal == null
        ? null
        : _MealMenu(
            meal: meal,
            title: title,
            enabled: enabled,
            onDelete: onDelete,
          );

    // Large text leaves no room for a time column or trailing actions: the
    // time joins the title line and the actions move under the row.
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 20;
    final timeText = Text(
      entry.time,
      style: TracendTheme.dataUtility(colors).copyWith(fontSize: 12),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TracendSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!stacked)
            SizedBox(
              width: 44,
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: timeText,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _StatusGlyph(marker: marker, colors: colors),
          ),
          const SizedBox(width: TracendSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: TracendSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (stacked && entry.time.isNotEmpty) timeText,
                    Text(
                      title,
                      style: theme.titleMedium?.copyWith(
                        color: muted ? colors.textSecondary : null,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // The status word always opens the second line, so every row
                // reads the same way: "Logged · Banana · Black coffee".
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: status,
                        style: theme.labelMedium?.copyWith(color: statusColor),
                      ),
                      if (foods != null && foods.isNotEmpty)
                        TextSpan(text: '  ·  $foods'),
                    ],
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                if (logged) ...[
                  const SizedBox(height: TracendSpacing.xs),
                  MacroSplitBar(meal: meal),
                ],
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
          if (!stacked && action != null && !entry.isDraft) action,
          if (!stacked && menu != null) menu,
        ],
      ),
    );
  }
}

/// A meal's energy split into protein, carbs, and fat (4, 4, and 9 kcal per
/// gram), in the totals card's colors. Screen readers hear the grams.
class MacroSplitBar extends StatelessWidget {
  const MacroSplitBar({required this.meal, super.key});

  final MealEntry meal;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    // Only macros the meal has get a segment, so gaps fall between visible
    // segments and the bar never ends on an empty gap.
    final parts = [
      (meal.protein * 4, colors.actionPrimary),
      (meal.carbohydrate * 4, colors.stateStable),
      (meal.fat * 9, colors.accentAmber),
    ].where((part) => part.$1 > 0).toList();
    final total = parts.fold<double>(0, (sum, part) => sum + part.$1);
    return Semantics(
      label:
          'Protein ${meal.protein.round()} grams, carbohydrate '
          '${meal.carbohydrate.round()} grams, fat ${meal.fat.round()} grams',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 4,
          child: total <= 0
              ? Container(color: colors.borderSubtle)
              : Row(
                  children: [
                    for (var i = 0; i < parts.length; i++)
                      Expanded(
                        flex: (parts[i].$1 / total * 1000).round().clamp(
                          1,
                          1000,
                        ),
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: i < parts.length - 1 ? 2 : 0,
                          ),
                          child: Container(color: parts[i].$2),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The **⋯** control on a logged meal: an action sheet with **Delete
/// meal**. The screen then asks for a destructive confirmation.
class _MealMenu extends StatelessWidget {
  const _MealMenu({
    required this.meal,
    required this.title,
    required this.enabled,
    required this.onDelete,
  });

  final MealEntry meal;
  final String title;
  final bool enabled;
  final ValueChanged<MealEntry> onDelete;

  Future<void> _open(BuildContext context) async {
    final choice = await showTracendActionSheet<String>(
      context,
      title: title,
      actions: const [
        TracendSheetAction(
          label: 'Delete meal',
          value: 'delete',
          destructive: true,
        ),
      ],
    );
    if (choice == 'delete') onDelete(meal);
  }

  @override
  Widget build(BuildContext context) => IconButton(
    key: ValueKey('meal-menu-${meal.id}'),
    onPressed: enabled ? () => _open(context) : null,
    tooltip: 'Meal options',
    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    icon: Icon(
      CupertinoIcons.ellipsis,
      size: 18,
      color: context.tracendColors.textSecondary,
    ),
  );
}

class _StatusGlyph extends StatelessWidget {
  const _StatusGlyph({required this.marker, required this.colors});

  final _Marker marker;
  final TracendColors colors;

  static const _size = 18.0;

  @override
  Widget build(BuildContext context) => switch (marker) {
    _Marker.logged => Icon(
      CupertinoIcons.checkmark_circle_fill,
      size: _size,
      color: colors.stateStable,
    ),
    _Marker.draft => Icon(
      CupertinoIcons.sparkles,
      size: _size,
      color: colors.accentAmber,
    ),
    _Marker.due => _ring(colors.accentAmber, 2.5),
    _Marker.upcoming => _ring(colors.textSecondary, 1.75),
    _Marker.optional => _ring(colors.borderSubtle, 1.75),
    _Marker.skipped => SizedBox.square(
      dimension: _size,
      child: Center(
        child: Container(width: 8, height: 2, color: colors.textSecondary),
      ),
    ),
  };

  Widget _ring(Color color, double width) => Container(
    width: _size,
    height: _size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: color, width: width),
    ),
  );
}
