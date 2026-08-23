import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

/// Normalizes a [DateTime] to midnight so date sets compare by day only.
DateTime normalizedDate(DateTime date) =>
    DateTime(date.year, date.month, date.day);

/// Monday of the week containing [date].
DateTime mondayOf(DateTime date) {
  final normalized = normalizedDate(date);
  return normalized.subtract(Duration(days: normalized.weekday - 1));
}

/// Week pill strip (plan §5.1/§5.2): seven day pills for the week containing
/// [selectedDate], with real chevron week navigation owned by the caller.
///
/// Binding contract:
/// - [daysWithData] — normalized dates with completed data (check marker)
/// - [plannedDates] — normalized dates with a planned item (dot marker)
/// - [markedDate] — single highlighted date (e.g. reconciliation confirm)
/// - [isDateEnabled] — false disables the pill (no no-op taps on future days)
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
    return Row(
      children: [
        if (onPreviousWeek != null)
          _WeekChevron(
            key: const ValueKey('date-strip-previous'),
            icon: CupertinoIcons.chevron_left,
            tooltip: 'Previous week',
            onPressed: onPreviousWeek!,
          ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < dates.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      left: i == 0 && onPreviousWeek != null
                          ? TracendSpacing.xxs
                          : 0,
                      right: i < dates.length - 1 ? TracendSpacing.xxs : 0,
                    ),
                    child: _DatePill(
                      key: ValueKey('date-pill-${_iso(dates[i])}'),
                      date: dates[i],
                      letter: _letterLabels[i],
                      weekdayName: _weekdayNames[i],
                      selected: _matches(selectedDate, dates[i]),
                      enabled: isDateEnabled?.call(dates[i]) ?? true,
                      completed: daysWithData.any((d) => _matches(d, dates[i])),
                      planned: plannedDates.any((d) => _matches(d, dates[i])),
                      marked: _matches(markedDate, dates[i]),
                      onTap: () => onSelectedDate(dates[i]),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (onNextWeek != null)
          _WeekChevron(
            key: const ValueKey('date-strip-next'),
            icon: CupertinoIcons.chevron_right,
            tooltip: 'Next week',
            onPressed: onNextWeek!,
          ),
      ],
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
  final bool enabled;
  final bool completed;
  final bool planned;
  final bool marked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final accent = selected ? colors.actionPrimary : colors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label:
          '$weekdayName ${date.day}'
          '${selected ? ', selected' : ''}'
          '${marked ? ', highlighted' : ''}'
          '${completed
              ? ', completed'
              : planned
              ? ', planned'
              : ''}',
      child: Material(
        color: selected
            ? colors.actionPrimary.withValues(alpha: 0.14)
            : colors.surface,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
            padding: const EdgeInsets.symmetric(
              horizontal: TracendSpacing.xs,
              vertical: TracendSpacing.xxs,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? colors.actionPrimary.withValues(alpha: 0.5)
                    : colors.borderHairline,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  letter,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontSize: 10,
                    letterSpacing: 0.8,
                    color: enabled ? accent : colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${date.day}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontFamily: TracendFonts.monoFamily,
                    fontSize: 14,
                    color: enabled
                        ? selected
                              ? colors.textPrimary
                              : colors.textSecondary
                        : colors.textSecondary.withValues(alpha: 0.5),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 10,
                  child: marked
                      ? Icon(
                          CupertinoIcons.link,
                          size: 10,
                          color: colors.actionPrimary,
                        )
                      : completed
                      ? Icon(
                          CupertinoIcons.check_mark_circled_solid,
                          size: 10,
                          color: colors.stateStable,
                        )
                      : planned
                      ? Container(
                          width: 4,
                          height: 4,
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.textSecondary,
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
