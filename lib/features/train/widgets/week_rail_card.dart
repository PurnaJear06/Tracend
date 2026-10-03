import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/date_pill_strip.dart'
    show normalizedDate;
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';

export 'package:tracend/shared/widgets/date_pill_strip.dart'
    show mondayOf, normalizedDate;

/// What one day of the strip shows under its number.
enum DayBoxStatus {
  /// A completed session: a check.
  done,

  /// A planned workout not yet done: a dot.
  planned,

  /// Nothing planned: the number dims.
  rest,
}

/// The Train day strip (owner pick: day boxes): seven boxes for the week
/// starting [weekStart]. A done day shows a check, a planned day a dot,
/// today a lime ring and the selected day a raised fill. A tap selects the
/// day with the selection haptic; a horizontal swipe pages the week when
/// [onPreviousWeek] or [onNextWeek] is given.
class DayBoxesStrip extends StatelessWidget {
  const DayBoxesStrip({
    required this.weekStart,
    required this.selectedDate,
    required this.today,
    required this.statusFor,
    required this.onSelected,
    this.workoutNameFor,
    this.onPreviousWeek,
    this.onNextWeek,
    super.key,
  });

  final DateTime weekStart;
  final DateTime selectedDate;
  final DateTime today;
  final DayBoxStatus Function(DateTime date) statusFor;
  final ValueChanged<DateTime> onSelected;

  /// The planned workout's name, for VoiceOver; null on a rest day.
  final String? Function(DateTime date)? workoutNameFor;
  final VoidCallback? onPreviousWeek;
  final VoidCallback? onNextWeek;

  /// The boxes are a compact control, like the tab bar: their text stops
  /// growing at this scale and VoiceOver carries the full words.
  static const maxTextScale = 1.3;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _label(DateTime date, DayBoxStatus status) {
    final name = workoutNameFor?.call(date);
    final state = switch (status) {
      DayBoxStatus.done => name == null ? 'done' : '$name, done',
      DayBoxStatus.planned => name == null ? 'planned' : '$name, planned',
      DayBoxStatus.rest => 'rest day',
    };
    final day =
        '${_weekdays[date.weekday - 1]} ${date.day} ${_months[date.month - 1]}';
    return '$day, $state${_same(date, today) ? ', today' : ''}';
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity > 300) {
      onPreviousWeek?.call();
    } else if (velocity < -300) {
      onNextWeek?.call();
    }
  }

  static String iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final start = normalizedDate(weekStart);
    final days = [for (var i = 0; i < 7; i++) start.add(Duration(days: i))];
    final strip = MediaQuery.withClampedTextScaling(
      maxScaleFactor: maxTextScale,
      child: Row(
        children: [
          for (var i = 0; i < 7; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: _DayBox(
                key: ValueKey('day-box-${iso(days[i])}'),
                letter: _letters[i],
                date: days[i],
                status: statusFor(days[i]),
                isToday: _same(days[i], today),
                selected: _same(days[i], selectedDate),
                semanticLabel: _label(days[i], statusFor(days[i])),
                onTap: () {
                  if (_same(days[i], selectedDate)) return;
                  TracendHaptics.selection();
                  onSelected(days[i]);
                },
              ),
            ),
          ],
        ],
      ),
    );
    if (onPreviousWeek == null && onNextWeek == null) return strip;
    return Semantics(
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Previous week'): ?onPreviousWeek,
        const CustomSemanticsAction(label: 'Next week'): ?onNextWeek,
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: _onDragEnd,
        child: strip,
      ),
    );
  }
}

class _DayBox extends StatelessWidget {
  const _DayBox({
    required this.letter,
    required this.date,
    required this.status,
    required this.isToday,
    required this.selected,
    required this.semanticLabel,
    required this.onTap,
    super.key,
  });

  final String letter;
  final DateTime date;
  final DayBoxStatus status;
  final bool isToday;
  final bool selected;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final marker = switch (status) {
      DayBoxStatus.done => Icon(
        CupertinoIcons.checkmark_alt,
        size: 14,
        color: colors.stateStable,
      ),
      DayBoxStatus.planned => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isToday ? colors.accentSignalRing : colors.textTertiary,
        ),
        child: const SizedBox.square(dimension: 5),
      ),
      DayBoxStatus.rest => const SizedBox.shrink(),
    };
    return Semantics(
      selected: selected,
      child: Pressable(
        onTap: onTap,
        semanticLabel: semanticLabel,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: TracendMotion.quick,
          curve: TracendMotion.curve,
          constraints: const BoxConstraints(minHeight: 66),
          decoration: BoxDecoration(
            color: selected ? colors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          foregroundDecoration: isToday
              ? BoxDecoration(
                  border: Border.all(
                    color: colors.accentSignalRing,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(16),
                )
              : null,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                letter,
                style: textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${date.day}',
                style: TextStyle(
                  fontFamily: TracendFonts.displayFamily,
                  fontSize: 18,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: status == DayBoxStatus.rest
                      ? colors.textTertiary
                      : colors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              SizedBox(height: 14, child: Center(child: marker)),
            ],
          ),
        ),
      ),
    );
  }
}
