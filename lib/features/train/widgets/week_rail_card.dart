import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/date_pill_strip.dart'
    show mondayOf, normalizedDate;
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

export 'package:tracend/shared/widgets/date_pill_strip.dart'
    show mondayOf, normalizedDate;

/// One calendar day of the visible training week.
@immutable
class WeekLoadDay {
  const WeekLoadDay({
    required this.date,
    required this.hasSession,
    this.minutes,
  });

  final DateTime date;

  /// A completed session exists on this day (a real `recent_sessions` row).
  final bool hasSession;

  /// Total training minutes that day from `duration_seconds`; null when the
  /// session exists but carried no duration (present, never invented).
  final int? minutes;
}

/// Days of the 7-day window starting at [windowStart]: one slot per calendar
/// day, minutes summed per `local_date` from real hub sessions. Days without
/// a session are simply absent — never interpolated or invented.
List<WeekLoadDay> weekLoadDays(
  List<TrainingSessionSummary> sessions, {
  required DateTime windowStart,
}) {
  final end = windowStart.add(const Duration(days: 6));
  final byDay = <DateTime, int?>{};
  for (final session in sessions) {
    final date = normalizedDate(session.date);
    if (date.isBefore(windowStart) || date.isAfter(end)) continue;
    final minutes = session.durationSeconds == null
        ? null
        : (session.durationSeconds! / 60).round();
    if (byDay.containsKey(date)) {
      // Any session without a duration leaves the day's total unknown —
      // the day stays present on the chart, its magnitude never invented.
      byDay[date] = byDay[date] == null || minutes == null
          ? null
          : byDay[date]! + minutes;
    } else {
      byDay[date] = minutes;
    }
  }
  return [
    for (var i = 0; i < 7; i++)
      WeekLoadDay(
        date: windowStart.add(Duration(days: i)),
        hasSession: byDay.containsKey(windowStart.add(Duration(days: i))),
        minutes: byDay[windowStart.add(Duration(days: i))],
      ),
  ];
}

/// Unified app-wide ACWR band (owner-approved 2026-09-04): Low load < 0.8 ·
/// Optimal 0.8–1.3 · High load > 1.3. High load above 1.5 escalates the
/// headline copy, never the label.
class LoadBand {
  const LoadBand._(this.label, this.color);
  final String label;
  final Color color;

  static LoadBand forAcwr(double? acwr, TracendColors colors) {
    if (acwr == null) {
      return LoadBand._('Building baseline', colors.accentAmber);
    }
    if (acwr >= 0.8 && acwr <= 1.3) {
      return LoadBand._('Optimal', colors.stateStable);
    }
    if (acwr < 0.8) {
      return LoadBand._('Low load', colors.accentAmber);
    }
    return LoadBand._('High load', colors.stateAttention);
  }
}

/// Week rail (2026-09-04 redesign): the date strip and the training-load
/// readout fused into one instrument. Day slots select the day; the chart
/// below speaks Today's `TrajectoryTrend` grammar — indigo 9pt day columns
/// sized by real training minutes, the lime terminal column plus halo on the
/// latest session day, hairline rails at the series' max and the baseline,
/// dim sockets for session-less days, month-rollover day ticks, and the
/// calibration strip (range · count · as-of). The verdict is one plain
/// sentence with a band chip; the ratio and day load live in one small mono
/// strip; the mix advice translates monotony. Honesty gates: fewer than four
/// sessions in the 28-day payload renders the Building-baseline state and
/// never a ratio verdict (thin-history ACWR is noise, per
/// docs/reviews/2026-09-02-post-deploy-verification-and-findings.md #6).
class WeekRailCard extends StatefulWidget {
  const WeekRailCard({
    required this.selectedDate,
    required this.onSelectedDate,
    required this.sessions,
    this.computed,
    this.completedDays = const {},
    this.plannedDates = const {},
    this.markedDate,
    this.onPreviousWeek,
    this.onNextWeek,
    super.key,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelectedDate;

  /// Real hub `recent_sessions` (28-day window).
  final List<TrainingSessionSummary> sessions;

  /// Computed metrics for the selected day; null while the brief loads —
  /// the verdict block stays hidden rather than flashing a false state.
  final ComputedMetrics? computed;

  final Set<DateTime> completedDays;
  final Set<DateTime> plannedDates;
  final DateTime? markedDate;
  final VoidCallback? onPreviousWeek;
  final VoidCallback? onNextWeek;

  @override
  State<WeekRailCard> createState() => _WeekRailCardState();
}

class _WeekRailCardState extends State<WeekRailCard>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  static const _drawDuration = Duration(milliseconds: 1500);

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion || _controller != null || _windowDays.isEmpty) {
      return;
    }
    _startDraw();
  }

  @override
  void didUpdateWidget(WeekRailCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller == null &&
        !_reduceMotion &&
        _windowDays.any((day) => day.hasSession)) {
      _startDraw();
    }
  }

  void _startDraw() {
    _controller = AnimationController(vsync: this, duration: _drawDuration)
      ..forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  List<WeekLoadDay> get _windowDays =>
      weekLoadDays(widget.sessions, windowStart: mondayOf(widget.selectedDate));

  /// Four or more sessions in the 28-day payload: the honest floor beneath a
  /// ratio verdict. Fewer renders the baseline state.
  bool get _hasLoadHistory => widget.sessions.length >= 4;

  bool _matches(DateTime? candidate, DateTime date) =>
      candidate != null &&
      candidate.year == date.year &&
      candidate.month == date.month &&
      candidate.day == date.day;

  String get _verdict {
    // The ratio is only honest with real history (finding #6: thin-window
    // ACWR is noise), so the verdict reads the gated value.
    final acwr = _showRatioVerdict ? widget.computed?.scores.acwr : null;
    if (acwr == null) {
      return _hasLoadHistory
          ? 'Your load reading will appear as training is logged.'
          : 'Follow the plan as written — your load reading builds as you '
                'train.';
    }
    if (acwr < 0.8) {
      return 'This week is running lighter than your normal training.';
    }
    if (acwr <= 1.3) {
      return 'This week’s training matches your normal.';
    }
    if (acwr <= 1.5) {
      return 'This week is running heavier than your normal — still in a '
          'workable range.';
    }
    return 'This week is running much heavier than your normal — scale back '
        'to protect progress.';
  }

  bool get _showRatioVerdict =>
      widget.computed?.scores.acwr != null && _hasLoadHistory;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final days = _windowDays;
    final sessionDays = days.where((day) => day.hasSession).toList();
    final terminal = sessionDays.isEmpty ? null : sessionDays.last;
    final band = LoadBand.forAcwr(
      _showRatioVerdict ? widget.computed!.scores.acwr : null,
      colors,
    );

    return PremiumGradientCard(
      glow: true,
      glowColor: colors.stateStable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _RailTag(),
          if (widget.computed != null) ...[
            const SizedBox(height: TracendSpacing.sm),
            Text(
              _verdict,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 20,
                height: 1.3,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: TracendSpacing.xs),
            _BandChip(band: band),
          ],
          const SizedBox(height: TracendSpacing.md),
          _SlotRow(
            selectedDate: widget.selectedDate,
            onSelectedDate: widget.onSelectedDate,
            completedDays: widget.completedDays,
            plannedDates: widget.plannedDates,
            markedDate: widget.markedDate,
            onPreviousWeek: widget.onPreviousWeek,
            onNextWeek: widget.onNextWeek,
            matches: _matches,
          ),
          const SizedBox(height: TracendSpacing.xs),
          _LoadPlot(
            days: days,
            terminal: terminal,
            plannedDates: widget.plannedDates,
            controller: _controller,
          ),
          _DayTicks(days: days),
          const SizedBox(height: TracendSpacing.xxs),
          _CalibrationStrip(days: days, terminal: terminal),
          const SizedBox(height: TracendSpacing.sm),
          _LoadStrip(
            computed: widget.computed,
            showRatio: _showRatioVerdict,
            hasMixHistory: _hasLoadHistory,
          ),
          const SizedBox(height: TracendSpacing.xxs),
          Text(
            _showRatioVerdict
                ? 'The ratio compares this week’s training load with your '
                      'typical week. 1.0 means unchanged.'
                : 'The load ratio fills in as more weeks of training are '
                      'logged.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
              fontSize: 11.5,
              height: 15 / 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _RailTag extends StatelessWidget {
  const _RailTag();

  @override
  Widget build(BuildContext context) {
    final color = context.tracendColors.stateStable;
    // MetricStrip idiom: stack the tag and its unit when Dynamic Type
    // scales past the inline width (no horizontal overflow at any scale).
    final stacked = MediaQuery.textScalerOf(context).scale(13) > 17;
    final label = Text(
      'THIS WEEK',
      style: TracendTheme.labelCaps(context, color: color),
    );
    final unit = Text(
      'training minutes',
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        fontFamily: TracendFonts.monoFamily,
        fontSize: 11,
        color: context.tracendColors.textSecondary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.bolt_fill, size: 13, color: color),
              const SizedBox(width: TracendSpacing.xxs),
              label,
            ],
          ),
          const SizedBox(height: TracendSpacing.xxs),
          unit,
        ],
      );
    }
    return Row(
      children: [
        Icon(CupertinoIcons.bolt_fill, size: 13, color: color),
        const SizedBox(width: TracendSpacing.xxs),
        Expanded(child: label),
        unit,
      ],
    );
  }
}

class _BandChip extends StatelessWidget {
  const _BandChip({required this.band});
  final LoadBand band;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: band.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        band.label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: band.color),
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.selectedDate,
    required this.onSelectedDate,
    required this.completedDays,
    required this.plannedDates,
    required this.markedDate,
    required this.onPreviousWeek,
    required this.onNextWeek,
    required this.matches,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelectedDate;
  final Set<DateTime> completedDays;
  final Set<DateTime> plannedDates;
  final DateTime? markedDate;
  final VoidCallback? onPreviousWeek;
  final VoidCallback? onNextWeek;
  final bool Function(DateTime?, DateTime) matches;

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

  static String _iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

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
                    child: _DaySlot(
                      key: ValueKey('date-pill-${_iso(dates[i])}'),
                      date: dates[i],
                      letter: _letterLabels[i],
                      weekdayName: _weekdayNames[i],
                      selected: matches(selectedDate, dates[i]),
                      completed: completedDays.any((d) => matches(d, dates[i])),
                      planned: plannedDates.any((d) => matches(d, dates[i])),
                      marked: matches(markedDate, dates[i]),
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

class _DaySlot extends StatelessWidget {
  const _DaySlot({
    required this.date,
    required this.letter,
    required this.weekdayName,
    required this.selected,
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
            : colors.surface.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minWidth: 38, minHeight: 44),
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
                // The letter and day glyphs are visual only — the Semantics
                // label above is the VoiceOver contract, so the raw glyphs
                // are excluded from the merged node (otherwise the reader
                // speaks "Monday 17, highlighted, M, 17").
                ExcludeSemantics(
                  child: Text(
                    letter,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontSize: 10,
                      letterSpacing: 0.8,
                      color: accent,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                ExcludeSemantics(
                  child: Text(
                    '${date.day}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontFamily: TracendFonts.monoFamily,
                      fontSize: 14,
                      color: selected
                          ? colors.textPrimary
                          : colors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
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

/// Day-column plot in the `TrajectoryTrend` grammar: 9pt pill columns at
/// 0.85 indigo (terminal lime at 0.9), the NOW halo on the latest session
/// day (still on Train — Today keeps the single pulsing loop), hairline
/// rails at the series' padded max and the baseline, 1.5pt sockets for
/// session-less days, and a small amber marker for missed planned days.
class _LoadPlot extends StatelessWidget {
  const _LoadPlot({
    required this.days,
    required this.terminal,
    required this.plannedDates,
    required this.controller,
  });

  final List<WeekLoadDay> days;
  final WeekLoadDay? terminal;
  final Set<DateTime> plannedDates;
  final AnimationController? controller;

  static const _plotHeight = 74.0;
  static const _xInset = 16.0;
  static const _topInset = 12.0;

  int get _maxMinutes =>
      days.map((day) => day.minutes).whereType<int>().fold(1, math.max);

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final controller = this.controller;
    Widget plot(double progress) => SizedBox(
      height: _plotHeight,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, _plotHeight);
          final terminalDay = terminal == null
              ? null
              : days.indexWhere((day) => day.date == terminal!.date);
          // Halo rides the terminal column's final top edge (same fixed
          // final position as TrajectoryTrend's NOW dot; a still halo —
          // Today keeps the single pulsing loop). No halo when the
          // terminal session carries no duration — there is no column
          // top to ride.
          final haloOffset =
              terminal == null ||
                  terminalDay == null ||
                  terminal!.minutes == null
              ? null
              : () {
                  final normalized = _maxMinutes == 0
                      ? 0.5
                      : terminal!.minutes! / _maxMinutes;
                  final topY =
                      size.height - normalized * (size.height - _topInset);
                  return Offset(
                    _xInset +
                        (terminalDay / 6) * (size.width - 2 * _xInset) -
                        5,
                    topY - 5,
                  );
                }();
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  key: const ValueKey('week-rail-plot'),
                  painter: _LoadPainter(
                    days: days,
                    terminal: terminal,
                    plannedDates: plannedDates,
                    column: colors.actionPrimary,
                    terminalColor: colors.accentNow,
                    rail: colors.borderSubtle,
                    socket: colors.borderSubtle,
                    miss: colors.accentAmber,
                    progress: progress,
                  ),
                ),
              ),
              // The NOW halo rides the terminal column's top edge (drawn at
              // the fixed topInset from the plot's top, matching the column
              // cap; a still halo, no pulse on Train).
              if (haloOffset != null)
                Positioned(
                  left: haloOffset.dx,
                  top: haloOffset.dy,
                  child: Container(
                    key: const ValueKey('week-rail-now-halo'),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.accentNow,
                      border: Border.all(color: colors.canvas, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: colors.accentNow.withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );

    if (controller == null) return plot(1);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) =>
          plot(Curves.easeOutCubic.transform(controller.value)),
    );
  }
}

class _LoadPainter extends CustomPainter {
  _LoadPainter({
    required this.days,
    required this.terminal,
    required this.plannedDates,
    required this.column,
    required this.terminalColor,
    required this.rail,
    required this.socket,
    required this.miss,
    required this.progress,
  });

  final List<WeekLoadDay> days;
  final WeekLoadDay? terminal;
  final Set<DateTime> plannedDates;
  final Color column;
  final Color terminalColor;
  final Color rail;
  final Color socket;
  final Color miss;
  final double progress;

  static const _xInset = 16.0;
  static const _columnWidth = 9.0;
  static const _minColumnHeight = 4.0;

  int get _maxMinutes =>
      days.map((day) => day.minutes).whereType<int>().fold(1, math.max);

  bool _isPlanned(DateTime date) => plannedDates.any(
    (planned) =>
        planned.year == date.year &&
        planned.month == date.month &&
        planned.day == date.day,
  );

  double _xFor(int index, Size size) =>
      _xInset + (index / 6) * (size.width - 2 * _xInset);

  double _yFor(int minutes, Size size) {
    const topInset = 12.0;
    final normalized = minutes / _maxMinutes;
    return size.height - normalized * (size.height - topInset);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || days.isEmpty) return;
    final hasRealMinutes = days.any((day) => day.minutes != null);
    final maxMinutes = hasRealMinutes ? _maxMinutes : 1;

    final railPaint = Paint()
      ..color = rail.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;
    // Top rail sits at the tallest column's height; baseline bounds the plot.
    final topRailY = _yFor(maxMinutes, size);
    canvas.drawLine(
      Offset(_xInset, topRailY),
      Offset(size.width - _xInset, topRailY),
      railPaint,
    );
    canvas.drawLine(
      Offset(_xInset, size.height),
      Offset(size.width - _xInset, size.height),
      railPaint,
    );

    final socketPaint = Paint()..color = socket.withValues(alpha: 0.55);
    final missPaint = Paint()..color = miss.withValues(alpha: 0.9);
    for (var i = 0; i < 7; i++) {
      if (days[i].hasSession) continue;
      final x = _xFor(i, size);
      if (_isPlanned(days[i].date)) {
        // Missed planned day: amber dot lifted off the baseline.
        canvas.drawCircle(Offset(x, size.height - 3.5), 3.5, missPaint);
      } else {
        canvas.drawCircle(Offset(x, size.height), 1.5, socketPaint);
      }
    }

    for (var i = 0; i < 7; i++) {
      final day = days[i];
      if (!day.hasSession) continue;
      final x = _xFor(i, size);
      final minutes = day.minutes;
      if (minutes == null) {
        // Session present but duration unknown: a larger socket on the
        // baseline — present, never inventing magnitude.
        canvas.drawCircle(Offset(x, size.height), 3, socketPaint);
        continue;
      }
      final fullHeight = size.height - _yFor(minutes, size);
      final height = math.max(
        _minColumnHeight,
        fullHeight *
            Curves.easeOutCubic.transform(
              ((progress - 0.1 * i) / 0.4).clamp(0.0, 1.0),
            ),
      );
      final isTerminal = terminal != null && terminal!.date == day.date;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x - _columnWidth / 2,
            size.height - height,
            _columnWidth,
            height,
          ),
          const Radius.circular(_columnWidth / 2),
        ),
        Paint()
          ..color = isTerminal
              ? terminalColor.withValues(alpha: 0.9 * progress)
              : column.withValues(alpha: 0.85 * progress),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LoadPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.days != days ||
      oldDelegate.terminal != terminal ||
      oldDelegate.plannedDates != plannedDates ||
      oldDelegate.column != column ||
      oldDelegate.terminalColor != terminalColor ||
      oldDelegate.rail != rail ||
      oldDelegate.socket != socket;
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _dayLabel(DateTime date) => '${date.day} ${_months[date.month - 1]}';

/// One tick per calendar day; first/last and month-rollover days carry the
/// month; session-less days render dim (the `TrajectoryTrend` idiom).
class _DayTicks extends StatelessWidget {
  const _DayTicks({required this.days});

  final List<WeekLoadDay> days;

  @override
  Widget build(BuildContext context) {
    final color = context.tracendColors.textSecondary;
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      fontFamily: TracendFonts.monoFamily,
      fontSize: 9,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        const inset = 16.0;
        final width = constraints.maxWidth;
        return SizedBox(
          height: 14,
          width: double.infinity,
          child: Stack(
            children: [
              for (var i = 0; i < 7; i++)
                Positioned(
                  left: inset + (i / 6) * (width - 2 * inset),
                  top: 4,
                  child: Transform.translate(
                    offset: Offset(
                      i == 0
                          ? 0
                          : i == 6
                          ? -30
                          : -10,
                      0,
                    ),
                    child: Text(
                      _tickText(i),
                      style: style?.copyWith(
                        color: days[i].hasSession
                            ? color
                            : color.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _tickText(int i) {
    final date = days[i].date;
    final rollover = i == 0 || i == 6 || (i != 0 && date.day == 1);
    return rollover ? _dayLabel(date) : '${date.day}';
  }
}

/// " min–max min · N of 7 days" left, "as of latest session day ·
/// Tracend sessions" right — the trust readout that dates the week.
class _CalibrationStrip extends StatelessWidget {
  const _CalibrationStrip({required this.days, required this.terminal});

  final List<WeekLoadDay> days;
  final WeekLoadDay? terminal;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      fontFamily: TracendFonts.monoFamily,
      fontSize: 9,
      color: context.tracendColors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final real = days
        .map((day) => day.minutes)
        .whereType<int>()
        .toList(growable: false);
    final sessionCount = days.where((day) => day.hasSession).length;
    final left = real.isEmpty
        ? '$sessionCount of 7 days'
        : '${real.reduce(math.min)}–${real.reduce(math.max)} min · '
              '$sessionCount of 7 days';
    final right = terminal == null
        ? 'no sessions logged'
        : 'as of ${_dayLabel(terminal!.date)} · Tracend sessions';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            left,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        const SizedBox(width: TracendSpacing.xs),
        Flexible(
          child: Text(
            right,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}

/// The single jargon site: the plain mix advice (was "Monotony") and the raw
/// numbers (was "Strain"), one quiet mono line above the footnote.
class _LoadStrip extends StatelessWidget {
  const _LoadStrip({
    required this.computed,
    required this.showRatio,
    required this.hasMixHistory,
  });

  final ComputedMetrics? computed;
  final bool showRatio;
  final bool hasMixHistory;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final monotony = computed?.scores.trainingMonotony;
    final strain = computed?.scores.dailyStrain;
    final showMix = monotony != null && hasMixHistory;
    final acwr = computed?.scores.acwr;
    if (!showMix && strain == null && (!showRatio || acwr == null)) {
      return const SizedBox.shrink();
    }

    final stats = [
      if (showRatio && acwr != null) 'Ratio ${acwr.toStringAsFixed(2)}',
      if (strain != null) 'Day load ${strain.toStringAsFixed(1)}',
    ].join(' · ');

    // Always stacked (owner QA 2026-09-04: the one-row variant bled off the
    // card at phone widths — advice + stats side by side only fit wide
    // surfaces, and depending on copy length to fit reintroduces the bleed).
    // Advice line above, quiet mono stats below; both wrap, never overflow.
    return Container(
      padding: const EdgeInsets.only(top: TracendSpacing.sm),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.borderHairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showMix) _MixAdvice(monotony: monotony),
          if (showMix && stats.isNotEmpty)
            const SizedBox(height: TracendSpacing.xxs),
          if (stats.isNotEmpty) _StatsLine(stats: stats),
        ],
      ),
    );
  }
}

class _MixAdvice extends StatelessWidget {
  const _MixAdvice({required this.monotony});
  final double monotony;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final warning = monotony > 2.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          warning
              ? CupertinoIcons.exclamationmark_triangle_fill
              : CupertinoIcons.check_mark_circled_solid,
          size: 14,
          color: warning ? colors.accentAmber : colors.stateStable,
        ),
        const SizedBox(width: TracendSpacing.xs),
        Flexible(
          child: Text(
            warning
                ? 'Days are too similar — vary intensity'
                : 'Good mix of hard and easy days',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textPrimary),
          ),
        ),
      ],
    );
  }
}

class _StatsLine extends StatelessWidget {
  const _StatsLine({required this.stats});
  final String stats;

  @override
  Widget build(BuildContext context) => Text(
    stats,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      fontFamily: TracendFonts.monoFamily,
      fontSize: 10.5,
      color: context.tracendColors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}
