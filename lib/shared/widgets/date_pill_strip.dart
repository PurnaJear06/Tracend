import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';

/// Normalizes a [DateTime] to midnight so date sets compare by day only.
DateTime normalizedDate(DateTime date) =>
    DateTime(date.year, date.month, date.day);

/// Monday of the week containing [date].
DateTime mondayOf(DateTime date) {
  final normalized = normalizedDate(date);
  return normalized.subtract(Duration(days: normalized.weekday - 1));
}

/// Week strip: seven day boxes for the week containing [selectedDate], with
/// real chevron week navigation owned by the caller. The chevrons sit with
/// the week's date range above the days, so each day keeps a full-width
/// touch target.
///
/// The selected day sits on a `surface` box; today carries the lime ring,
/// the signal for "now". Changing the day plays the `selection` haptic.
///
/// Binding contract:
/// - [daysWithData] — normalized dates with completed data (check marker)
/// - [plannedDates] — normalized dates with a planned item (dot marker)
/// - [markedDate] — single highlighted date (e.g. reconciliation confirm)
/// - [isDateEnabled] — false disables the day (no no-op taps on future days)
/// - chevrons render only when their callback is provided: a missing chevron
///   is the honest "no further navigation" state
class DatePillStrip extends StatelessWidget {
  const DatePillStrip({
    required this.selectedDate,
    required this.onSelectedDate,
    this.daysWithData = const {},
    this.plannedDates = const {},
    this.isDateEnabled,
    this.onPreviousWeek,
    this.onNextWeek,
    this.markedDate,
    this.today,
    super.key,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelectedDate;
  final Set<DateTime> daysWithData;
  final Set<DateTime> plannedDates;
  final bool Function(DateTime date)? isDateEnabled;
  final VoidCallback? onPreviousWeek;
  final VoidCallback? onNextWeek;
  final DateTime? markedDate;

  /// The day that carries the lime "today" ring; the device date when null.
  final DateTime? today;

  /// Day boxes keep their text inside the box at large text sizes; the full
  /// date is always spoken.
  static const maxTextScale = 1.35;

  static const _letterLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  bool _matches(DateTime? candidate, DateTime date) =>
      candidate != null &&
      candidate.year == date.year &&
      candidate.month == date.month &&
      candidate.day == date.day;

  @override
  Widget build(BuildContext context) {
    final monday = mondayOf(selectedDate);
    final dates = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
    final now = today ?? DateTime.now();
    final hasChevrons = onPreviousWeek != null || onNextWeek != null;
    final days = Row(
      children: [
        for (var i = 0; i < dates.length; i++)
          Expanded(
            child: _DatePill(
              key: ValueKey('date-pill-${_iso(dates[i])}'),
              date: dates[i],
              letter: _letterLabels[i],
              weekdayName: _weekdayNames[i],
              selected: _matches(selectedDate, dates[i]),
              isToday: _matches(now, dates[i]),
              enabled: isDateEnabled?.call(dates[i]) ?? true,
              completed: daysWithData.any((d) => _matches(d, dates[i])),
              planned: plannedDates.any((d) => _matches(d, dates[i])),
              marked: _matches(markedDate, dates[i]),
              onTap: () => onSelectedDate(dates[i]),
            ),
          ),
      ],
    );
    // Pressable draws on a Material; the strip may sit straight on a page.
    if (!hasChevrons) {
      return Material(type: MaterialType.transparency, child: days);
    }
    final colors = context.tracendColors;
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Text(
                    '${shortDate(dates.first, now: now)} – '
                    '${shortDate(dates.last, now: now)}',
                    style: TracendTheme.dataUtility(colors),
                  ),
                ),
              ),
              if (onPreviousWeek != null)
                _WeekChevron(
                  key: const ValueKey('date-strip-previous'),
                  icon: CupertinoIcons.chevron_left,
                  tooltip: 'Previous week',
                  onPressed: onPreviousWeek!,
                ),
              if (onNextWeek != null)
                _WeekChevron(
                  key: const ValueKey('date-strip-next'),
                  icon: CupertinoIcons.chevron_right,
                  tooltip: 'Next week',
                  onPressed: onNextWeek!,
                ),
            ],
          ),
          days,
        ],
      ),
    );
  }

  static String _iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class _WeekChevron extends StatelessWidget {
  const _WeekChevron({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      icon: Icon(icon, size: 18, color: colors.textSecondary),
    );
  }
}

class _DatePill extends StatelessWidget {
  const _DatePill({
    required this.date,
    required this.letter,
    required this.weekdayName,
    required this.selected,
    required this.isToday,
    required this.enabled,
    required this.completed,
    required this.planned,
    required this.marked,
    required this.onTap,
    super.key,
  });

  final DateTime date;
  final String letter;
  final String weekdayName;
  final bool selected;
  final bool isToday;
  final bool enabled;
  final bool completed;
  final bool planned;
  final bool marked;
  final VoidCallback onTap;

  static const _radius = 16.0;

  void _select() {
    if (!selected) TracendHaptics.selection();
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final theme = Theme.of(context).textTheme;
    final numberColor = !enabled
        ? colors.textTertiary
        : selected || isToday
        ? colors.textPrimary
        : colors.textSecondary;
    final status = marked
        ? Icon(CupertinoIcons.link, size: 12, color: colors.textPrimary)
        : completed
        ? Icon(
            CupertinoIcons.checkmark_circle_fill,
            size: 13,
            color: colors.stateStable,
          )
        : planned
        ? Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isToday ? colors.accentSignalRing : colors.textTertiary,
            ),
          )
        : null;
    final label = [
      '$weekdayName ${date.day}',
      if (isToday) 'today',
      if (selected) 'selected',
      if (marked) 'highlighted',
      if (completed) 'completed' else if (planned) 'planned',
    ].join(', ');
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: DatePillStrip.maxTextScale,
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        label: label,
        onTap: enabled ? _select : null,
        excludeSemantics: true,
        child: Pressable(
          onTap: enabled ? _select : null,
          borderRadius: BorderRadius.circular(_radius),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(vertical: 6),
            foregroundDecoration: isToday
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(_radius),
                    border: Border.all(
                      color: colors.accentSignalRing,
                      width: 1.5,
                    ),
                  )
                : null,
            decoration: BoxDecoration(
              color: selected ? colors.surface : null,
              borderRadius: BorderRadius.circular(_radius),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  letter,
                  style: theme.labelSmall?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: enabled ? colors.textSecondary : colors.textTertiary,
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${date.day}',
                    style: TracendTheme.numeric(
                      colors,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: numberColor,
                    ).copyWith(height: 1),
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(height: 14, child: Center(child: status)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
