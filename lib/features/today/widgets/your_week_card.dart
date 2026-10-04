import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

/// The week so far, Monday to Sunday, in the ring's language: each day is a
/// stack of ten ticks lit to its recovery score (lime from 50, amber below),
/// with a mark under it: a filled dot when a session was completed, a ring
/// when one is planned and still ahead, a hollow grey ring when a planned
/// session was not done, and a dash on rest days. A day without a score
/// says "no data"; later days stay empty. Tapping a day names it below.
///
/// The headline counts sessions against the plan's week and the average of
/// the days that were scored. Nothing is interpolated.
class YourWeekCard extends StatefulWidget {
  const YourWeekCard({required this.week, required this.today, super.key});

  final List<TodayWeekDay> week;
  final DateTime today;

  @override
  State<YourWeekCard> createState() => _YourWeekCardState();
}

class _YourWeekCardState extends State<YourWeekCard> {
  int? _selected;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  int get _todayIndex {
    for (var i = 0; i < widget.week.length; i++) {
      if (_sameDay(widget.week[i].date, widget.today)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final week = widget.week;
    final todayIndex = _todayIndex;
    final selected = _selected ?? todayIndex;
    final trained = week.where((d) => d.trained).length;
    final planned = week.where((d) => d.planned).length;
    final scored = [
      for (var i = 0; i <= todayIndex && i < week.length; i++)
        if (week[i].recovery != null) week[i].recovery!,
    ];
    final headline = planned == 0
        ? '$trained ${trained == 1 ? 'session' : 'sessions'} this week'
        : '$trained of $planned sessions done';
    final average = scored.isEmpty
        ? 'Recovery not scored yet this week'
        : 'Recovery averaged '
              '${(scored.reduce((a, b) => a + b) / scored.length).round()} '
              'this week';

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
            'Your week',
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            headline,
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          Text(
            average,
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: TracendSpacing.md),
          Row(
            children: [
              for (var i = 0; i < week.length && i < 7; i++)
                Expanded(
                  child: _DayColumn(
                    letter: _letters[i],
                    day: week[i],
                    today: i == todayIndex,
                    future: i > todayIndex,
                    selected: i == selected,
                    semanticLabel: _dayLine(i),
                    onTap: () => setState(() => _selected = i),
                  ),
                ),
            ],
          ),
          const SizedBox(height: TracendSpacing.sm),
          AnimatedSwitcher(
            duration: TracendMotionScope.fade(context, TracendMotion.quick),
            child: Container(
              key: ValueKey(selected),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: TracendSpacing.sm,
                vertical: TracendSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceRaised,
                borderRadius: BorderRadius.circular(TracendRadii.control),
              ),
              child: Text(_dayLine(selected), style: textTheme.bodySmall),
            ),
          ),
        ],
      ),
    );
  }

  /// "Monday · recovery 64 · trained".
  String _dayLine(int index) {
    final day = widget.week[index];
    final todayIndex = _todayIndex;
    final name = index == todayIndex ? 'Today' : _names[index];
    if (index > todayIndex) {
      return '$name · ${day.planned ? 'session planned' : 'rest day'}';
    }
    final recovery = day.recovery == null
        ? 'recovery not scored'
        : 'recovery ${day.recovery}';
    final session = day.trained
        ? 'trained'
        : day.planned
        ? (index == todayIndex ? 'session planned' : 'planned, not logged')
        : 'rest day';
    return '$name · $recovery · $session';
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.letter,
    required this.day,
    required this.today,
    required this.future,
    required this.selected,
    required this.semanticLabel,
    required this.onTap,
  });

  final String letter;
  final TodayWeekDay day;
  final bool today;
  final bool future;
  final bool selected;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final recovery = day.recovery;
    final lit = recovery == null ? 0 : (recovery / 10).round().clamp(0, 10);
    final tickColor = recovery != null && recovery < 50
        ? colors.accentAmber
        : colors.accentSignalRing;

    final Widget stack;
    if (future) {
      stack = const SizedBox(height: 52);
    } else if (recovery == null) {
      stack = SizedBox(
        height: 52,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'no\ndata',
              textAlign: TextAlign.center,
              style: textTheme.labelSmall?.copyWith(
                color: colors.textTertiary,
                height: 1.1,
              ),
            ),
          ),
        ),
      );
    } else {
      stack = SizedBox(
        height: 52,
        width: 18,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (var k = 9; k >= 0; k--) ...[
              Container(
                height: 3,
                decoration: BoxDecoration(
                  color: k < lit
                      ? tickColor.withValues(alpha: 0.4 + 0.06 * k)
                      : colors.textSecondary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (k > 0) const SizedBox(height: 2),
            ],
          ],
        ),
      );
    }

    final Widget mark;
    if (day.trained) {
      mark = _Mark(fill: colors.accentSignalRing);
    } else if (day.planned && (future || today)) {
      mark = _Mark(ring: colors.accentSignalRing);
    } else if (day.planned) {
      mark = _Mark(ring: colors.textTertiary);
    } else {
      mark = Container(
        width: 8,
        height: 2,
        decoration: BoxDecoration(
          color: colors.textSecondary.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(1),
        ),
      );
    }

    return Pressable(
      onTap: onTap,
      pressedScale: 0.95,
      semanticLabel: semanticLabel,
      borderRadius: BorderRadius.circular(TracendRadii.control),
      child: AnimatedContainer(
        duration: TracendMotionScope.fade(context, TracendMotion.quick),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: TracendSpacing.xs),
        decoration: BoxDecoration(
          color: selected ? colors.surfaceRaised : Colors.transparent,
          borderRadius: BorderRadius.circular(TracendRadii.control),
        ),
        child: Column(
          children: [
            stack,
            const SizedBox(height: 6),
            SizedBox(height: 8, child: Center(child: mark)),
            const SizedBox(height: 6),
            Text(
              letter,
              style: textTheme.labelMedium?.copyWith(
                color: today ? colors.accentSignalInk : colors.textSecondary,
                fontWeight: today ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({this.fill, this.ring});

  final Color? fill;
  final Color? ring;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: fill,
      border: ring == null ? null : Border.all(color: ring!, width: 1.5),
    ),
  );
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
