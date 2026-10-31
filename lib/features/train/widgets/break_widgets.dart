import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/training_pause_repository.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/training_availability.dart';
import 'package:tracend/shared/widgets/tracend_confirm.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

/// A break on Today and Train: "On a break until Sat 15 Nov" while it runs,
/// "Break starts Mon 3 Nov" before. No session is due on its days; the plan
/// itself never changes and picks up again the day after its last day.
class BreakCard extends StatelessWidget {
  const BreakCard({
    required this.pause,
    required this.today,
    required this.onEnd,
    this.busy = false,
    this.justSet = false,
    super.key,
  });

  final TrainingPause pause;
  final DateTime today;

  /// Ends the break (or cancels one that has not started); null hides it.
  final VoidCallback? onEnd;
  final bool busy;

  /// The break was set a moment ago on this screen: the button reads Undo.
  final bool justSet;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final running = pause.running || !pause.startDate.isAfter(today);
    final title = running
        ? 'On a break until ${dayAndDate(pause.endDate, now: today)}'
        : 'Break starts ${dayAndDate(pause.startDate, now: today)}';
    final body = running
        ? 'No sessions are due. Your plan picks up again on '
              '${dayAndDate(pause.resumesOn, now: today)}.'
        : 'Until ${dayAndDate(pause.endDate, now: today)}. Your plan stays as '
              'it is until then.';
    final action = justSet
        ? 'Undo'
        : running
        ? 'End break early'
        : 'Cancel break';
    return Container(
      key: const ValueKey('break-card'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        TracendSpacing.md,
        TracendSpacing.md,
        TracendSpacing.md,
        TracendSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(TracendRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.pause_circle,
                size: 16,
                color: colors.accentSignalInk,
              ),
              const SizedBox(width: 6),
              Text(
                'Break',
                style: textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Semantics(
            header: true,
            child: Text(
              title,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(height: TracendSpacing.xs),
          Text(
            body,
            style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          if (pause.note != null) ...[
            const SizedBox(height: TracendSpacing.xxs),
            Text(
              '“${pause.note}”',
              style: textTheme.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
          if (onEnd != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const ValueKey('break-end'),
                onPressed: busy ? null : onEnd,
                child: Text(action),
              ),
            )
          else
            const SizedBox(height: TracendSpacing.sm),
        ],
      ),
    );
  }
}

/// A day of an older break on Train: nothing was due.
class BreakDayCard extends StatelessWidget {
  const BreakDayCard({required this.date, required this.today, super.key});

  final DateTime date;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final past = date.isBefore(today);
    return Container(
      key: const ValueKey('break-day'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(TracendRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.pause_circle,
                size: 15,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                dayAndDate(date, now: today),
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Semantics(
            header: true,
            child: Text(
              'Break day',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: TracendSpacing.sm),
          Text(
            past
                ? 'You were on a break. Nothing was due.'
                : 'You are on a break. Nothing is due.',
            style: textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// After two days of "can't train" check-ins: an offer the athlete taps.
/// Nothing is set until they choose dates and confirm.
class BreakOfferCard extends StatelessWidget {
  const BreakOfferCard({required this.onSetBreak, super.key});

  final VoidCallback onSetBreak;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      key: const ValueKey('break-offer'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        TracendSpacing.md,
        TracendSpacing.sm,
        TracendSpacing.xs,
        TracendSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.accentSignalTint,
        borderRadius: BorderRadius.circular(TracendRadii.card),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Taking a few days off?',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "You've said you can't train two days running. A break "
                  'keeps sessions from piling up as missed.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            key: const ValueKey('break-offer-set'),
            onPressed: onSetBreak,
            child: const Text('Set a break'),
          ),
        ],
      ),
    );
  }
}

/// The first days back from a break, until a session is logged.
class FirstDayBackNote extends StatelessWidget {
  const FirstDayBackNote({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      key: const ValueKey('first-day-back'),
      width: double.infinity,
      padding: const EdgeInsets.all(TracendSpacing.sm),
      decoration: BoxDecoration(
        color: colors.accentSignalTint,
        borderRadius: BorderRadius.circular(TracendRadii.control + 4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            CupertinoIcons.play_circle,
            size: 17,
            color: colors.accentSignalInk,
          ),
          const SizedBox(width: TracendSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'First day back',
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.accentSignalInk,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Your plan picks up again. Ease into the first session and '
                  'stop short of your limit.',
                  style: textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Taking a break": opens the break sheet.
class TakeBreakButton extends StatelessWidget {
  const TakeBreakButton({required this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: TextButton.icon(
      key: const ValueKey('take-break'),
      onPressed: onPressed,
      icon: const Icon(CupertinoIcons.pause_circle, size: 17),
      label: const Text('Taking a break'),
    ),
  );
}

/// Opens the break sheet. Completes with the break the server set, or null
/// when the athlete closed the sheet.
Future<PauseStartResult?> showTakeBreakSheet(
  BuildContext context, {
  required DateTime today,
  required TrainingPauseRepository repository,
}) => showTracendSheet<PauseStartResult>(
  context,
  title: 'Taking a break',
  subtitle: 'No sessions are due on these days. Your plan stays as it is.',
  builder: (_) => TakeBreakSheet(today: today, repository: repository),
);

/// The break sheet: the first day (today, tomorrow or the day after), the
/// last day and Confirm. The server checks every date again.
class TakeBreakSheet extends StatefulWidget {
  const TakeBreakSheet({
    required this.today,
    required this.repository,
    super.key,
  });

  final DateTime today;
  final TrainingPauseRepository repository;

  @override
  State<TakeBreakSheet> createState() => _TakeBreakSheetState();
}

class _TakeBreakSheetState extends State<TakeBreakSheet> {
  late DateTime _today;
  late DateTime _start;
  late DateTime _end;
  bool _saving = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    final t = widget.today;
    _today = DateTime(t.year, t.month, t.day);
    _start = _today;
    _end = _today.add(const Duration(days: 6));
  }

  DateTime get _lastAllowed =>
      _start.add(const Duration(days: maxBreakDays - 1));

  void _chooseStart(int offset) {
    final start = _today.add(Duration(days: offset));
    setState(() {
      _start = start;
      _problem = null;
      if (_end.isBefore(start)) _end = start;
      if (_end.isAfter(_lastAllowed)) _end = _lastAllowed;
    });
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _end,
      firstDate: _start,
      lastDate: _lastAllowed,
      helpText: 'Last day of your break',
    );
    if (picked != null && mounted) {
      setState(() {
        _end = DateTime(picked.year, picked.month, picked.day);
        _problem = null;
      });
    }
  }

  Future<void> _confirm() async {
    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      final result = await widget.repository.start(
        startDate: _start,
        endDate: _end,
      );
      if (!mounted) return;
      if (result.started) {
        Navigator.of(context).pop(result);
        return;
      }
      setState(() => _problem = pauseRefusalText(result.refusal!));
    } on TrainingPauseException catch (error) {
      if (mounted) setState(() => _problem = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _startLabel(int offset) => switch (offset) {
    0 => 'Today',
    1 => 'Tomorrow',
    _ => dayAndDate(_today.add(Duration(days: offset)), now: _today),
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final days = _end.difference(_start).inDays + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'First day',
          style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: TracendSpacing.xs),
        Wrap(
          spacing: TracendSpacing.xs,
          runSpacing: TracendSpacing.xs,
          children: [
            for (var offset = 0; offset <= maxBreakStartAhead; offset++)
              ChoiceChip(
                key: ValueKey('break-start-$offset'),
                label: Text(_startLabel(offset)),
                selected: _start == _today.add(Duration(days: offset)),
                onSelected: _saving ? null : (_) => _chooseStart(offset),
              ),
          ],
        ),
        const SizedBox(height: TracendSpacing.md),
        Text(
          'Last day',
          style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: TracendSpacing.xs),
        OutlinedButton.icon(
          key: const ValueKey('break-end-row'),
          onPressed: _saving ? null : _pickEnd,
          iconAlignment: IconAlignment.end,
          icon: const Icon(CupertinoIcons.calendar, size: 17),
          label: Text(dayAndDate(_end, now: _today)),
        ),
        const SizedBox(height: TracendSpacing.md),
        Semantics(
          liveRegion: true,
          child: Text(
            'Break · ${breakRangeLabel(_start, _end, now: _today)}',
            key: const ValueKey('break-summary'),
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$days ${days == 1 ? 'day' : 'days'}. Your plan picks up again on '
          '${dayAndDate(_end.add(const Duration(days: 1)), now: _today)}. '
          'You can end it early any time.',
          style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
        if (_problem != null) ...[
          const SizedBox(height: TracendSpacing.sm),
          Text(
            _problem!,
            key: const ValueKey('break-refusal'),
            style: textTheme.bodyMedium?.copyWith(color: colors.stateDanger),
          ),
        ],
        const SizedBox(height: TracendSpacing.md),
        FilledButton(
          key: const ValueKey('break-confirm'),
          onPressed: _saving ? null : _confirm,
          child: Text(_saving ? 'Setting your break…' : 'Confirm'),
        ),
        const SizedBox(height: TracendSpacing.md),
      ],
    );
  }
}

/// Opens the break sheet and, once the server set the break, says so. The
/// break's id, or null when nothing was set.
Future<String?> takeBreak(
  BuildContext context, {
  required DateTime today,
  required TrainingPauseRepository repository,
}) async {
  final result = await showTakeBreakSheet(
    context,
    today: today,
    repository: repository,
  );
  if (result == null || !result.started || !context.mounted) return null;
  TracendToast.show(
    context,
    'Break set · ${breakRangeLabel(result.startDate, result.endDate, now: today)}',
    icon: CupertinoIcons.pause_circle,
  );
  return result.pauseId;
}

/// Ends a running break today or cancels one that has not started, after the
/// athlete confirms (an Undo right after setting it asks nothing). True when
/// the server changed something.
Future<bool> endBreak(
  BuildContext context, {
  required TrainingPause pause,
  required DateTime today,
  required TrainingPauseRepository repository,
  bool justSet = false,
}) async {
  final running = pause.running || !pause.startDate.isAfter(today);
  if (!justSet) {
    final confirmed = await showTracendConfirm(
      context,
      title: running ? 'End your break now?' : 'Cancel this break?',
      message: running
          ? 'Today becomes a normal day and your plan picks up from today.'
          : 'Your plan stays as it is on those days.',
      confirmLabel: running ? 'End break' : 'Cancel break',
      cancelLabel: 'Keep it',
    );
    if (!confirmed || !context.mounted) return false;
  }
  try {
    final result = await repository.end(pause.id);
    if (!context.mounted) return result.status != 'not_running';
    TracendToast.show(context, switch (result.status) {
      'ended' => justSet ? 'Break undone.' : 'Break ended. Welcome back.',
      'cancelled' => justSet ? 'Break undone.' : 'Break cancelled.',
      _ => 'That break had already ended.',
    }, icon: CupertinoIcons.checkmark_alt);
    return true;
  } on TrainingPauseException catch (error) {
    if (context.mounted) {
      TracendToast.show(
        context,
        error.message,
        icon: CupertinoIcons.exclamationmark_triangle,
      );
    }
    return false;
  }
}
