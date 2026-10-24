import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/readiness/day_adjustment.dart';
import 'package:tracend/features/readiness/day_adjustment_controller.dart';
import 'package:tracend/features/readiness/day_adjustment_repository.dart';
import 'package:tracend/features/readiness/readiness_copy.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

/// What the card says today, from the adjustment the server named.
enum DayCardState {
  /// Nothing to say: the card is not shown.
  hidden,

  /// A day with a safety route: words only, no training choice.
  safety,

  /// The rules propose a kind and wait for the athlete.
  proposed,

  /// The athlete accepted; it can be undone until the workout starts.
  accepted,

  /// The athlete accepted and the workout started or is done: read only.
  begun,

  /// The athlete chose to train as planned.
  declined,

  /// No check-in yet.
  checkIn,

  /// The recovery score reads low and no kind is proposed: Tracend shows what
  /// it sees and the athlete decides.
  lowRecovery,

  /// The athlete said they cannot train today.
  notAvailable,

  /// Coach already adjusted today's session.
  coachAdjusted,

  /// Only words are due: mild pain, an earlier answer that no longer stands,
  /// or a kind this build cannot apply.
  note,
}

/// The state [adjustment] puts the card in. A safety route comes first: it
/// stands over every stored answer, so a day that routes out never offers
/// "train as planned" or an adjustment.
DayCardState dayCardState(DayAdjustment adjustment) {
  if (adjustment.hasSafetyRoute) return DayCardState.safety;
  if (adjustment.isAccepted && adjustment.kind != null) {
    return adjustment.sessionBegun ? DayCardState.begun : DayCardState.accepted;
  }
  if (!adjustment.available) {
    return adjustment.unavailableReason == 'coach_adjusted'
        ? DayCardState.coachAdjusted
        : DayCardState.hidden;
  }
  // A kind this build cannot apply: its explanation and band are said, and no
  // proposal or choice is offered for it.
  if (adjustment.unsupportedKind) return DayCardState.note;
  if (adjustment.status == DayAdjustmentStatus.declined) {
    return DayCardState.declined;
  }
  if (adjustment.kind != null) return DayCardState.proposed;
  if (adjustment.band == DayBand.unknown) {
    return adjustment.signals.recoveryLow
        ? DayCardState.lowRecovery
        : DayCardState.checkIn;
  }
  if (adjustment.triggers.contains('not_available')) {
    return DayCardState.notAvailable;
  }
  if (adjustment.signals.recoveryLow) return DayCardState.lowRecovery;
  if (adjustment.previousAnswer != null || painNote(adjustment) != null) {
    return DayCardState.note;
  }
  return DayCardState.hidden;
}

/// Today's same-day readiness card (UX_FLOWS.md §5, §7). It shows what Tracend
/// sees, proposes or offers one change for today only, and the athlete answers
/// with one tap; an accepted change can be undone until the workout starts.
/// Heart rate and HRV alone never apply or pre-select a change: with only a
/// low recovery score the card says what it sees, asks for a check-in and
/// offers a talk with Coach and the same choices.
class DayAdjustmentCard extends StatefulWidget {
  const DayAdjustmentCard({
    required this.controller,
    required this.onTalkToCoach,
    this.onCheckIn,
    this.computed,
    this.forDate,
    this.embedded = false,
    super.key,
  });

  /// The day the surrounding screen's data (the brief, the readiness numbers)
  /// was loaded for, `YYYY-MM-DD`. The card is shown only for the server's
  /// adjustment of that same day, so a phone date that differs from the
  /// server's never puts one day's card beside another day's numbers.
  final String? forDate;

  final DayAdjustmentController controller;

  /// Opens Coach with this question in the box, not sent.
  final ValueChanged<String> onTalkToCoach;

  /// Opens today's check-in; null where it cannot be opened from here.
  final VoidCallback? onCheckIn;

  /// The brief's numbers, for HRV and resting heart rate against the usual.
  final ComputedMetrics? computed;

  /// The card sits inside another card (Today's session): it takes the raised
  /// panel colour instead of the card colour.
  final bool embedded;

  @override
  State<DayAdjustmentCard> createState() => _DayAdjustmentCardState();
}

class _DayAdjustmentCardState extends State<DayAdjustmentCard> {
  bool _seenOpen = false;

  DayAdjustmentController get _controller => widget.controller;

  Future<void> _answer({
    required bool accept,
    DayAdjustmentKind? chosen,
    required String done,
  }) async {
    final taken = await _controller.respond(accept: accept, chosen: chosen);
    if (!taken || !mounted) return;
    unawaited(TracendHaptics.success());
    TracendToast.show(context, done);
  }

  Future<void> _openOptions(DayAdjustment adjustment) async {
    final choice = await showTracendSheet<_Choice>(
      context,
      title: optionsSheetTitle,
      subtitle: optionsSheetSubtitle,
      builder: (sheetContext) => _OptionsBody(
        adjustment: adjustment,
        pick: Navigator.of(sheetContext).pop,
      ),
    );
    if (choice == null || !mounted) return;
    final kind = choice.kind;
    if (kind == null) {
      await _answer(accept: false, done: declinedTitle);
    } else {
      await _answer(accept: true, chosen: kind, done: kindAppliedTitle(kind));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final adjustment = _controller.current;
      if (adjustment == null) {
        final failure = _controller.loadFailure;
        if (failure == null || _controller.loading) {
          return const SizedBox.shrink();
        }
        return _Panel(
          embedded: widget.embedded,
          child: _Line(
            failure == DayAdjustmentFailure.wrongDate
                ? failureLine(failure)
                : readFailureLine,
          ),
        );
      }
      final state = dayCardState(adjustment);
      if (state == DayCardState.hidden ||
          (widget.forDate != null && adjustment.localDate != widget.forDate)) {
        return const SizedBox.shrink();
      }
      return _Panel(
        embedded: widget.embedded,
        child: _content(context, adjustment, state),
      );
    },
  );

  Widget _content(
    BuildContext context,
    DayAdjustment adjustment,
    DayCardState state,
  ) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final busy = _controller.busy;
    final kind = adjustment.kind;
    final applied = adjustment.appliedKind;
    final previous = adjustment.previousAnswer;
    final String? title = switch (state) {
      DayCardState.safety => safetyWords(adjustment.safetyRoute!).title,
      DayCardState.proposed => kindTitle(kind!),
      DayCardState.accepted => kindAppliedTitle(applied!),
      DayCardState.begun => kindBegunTitle(applied!),
      DayCardState.declined => declinedTitle,
      DayCardState.lowRecovery => lowRecoveryTitle,
      DayCardState.coachAdjusted => coachAdjustedTitle,
      DayCardState.checkIn ||
      DayCardState.notAvailable ||
      DayCardState.note ||
      DayCardState.hidden => null,
    };
    final String body = switch (state) {
      DayCardState.safety => safetyWords(adjustment.safetyRoute!).body,
      DayCardState.accepted => appliedBody(adjustment),
      DayCardState.begun => begunBody(adjustment),
      DayCardState.declined => declinedBody,
      DayCardState.note
          when adjustment.kind == null && !adjustment.unsupportedKind =>
        painNote(adjustment) ?? adjustment.explanation,
      _ => adjustment.explanation,
    };
    final showSeen =
        state == DayCardState.proposed ||
        state == DayCardState.lowRecovery ||
        state == DayCardState.checkIn && adjustment.signals.recoveryLow;
    final seen = showSeen
        ? [
            ...seenLines(adjustment, widget.computed),
            ?basisLine(adjustment),
            ?confidenceLine(adjustment.confidence),
          ]
        : const <String>[];
    final seenAlwaysOpen =
        state == DayCardState.lowRecovery ||
        state == DayCardState.checkIn && adjustment.signals.recoveryLow;
    final chooseable = adjustment.options.isNotEmpty;
    final answered =
        state == DayCardState.accepted || state == DayCardState.declined;
    final failure = _controller.answerFailure;
    final stale = _controller.loadFailure != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              state == DayCardState.safety
                  ? CupertinoIcons.exclamationmark_triangle_fill
                  : CupertinoIcons.heart_circle,
              size: 17,
              color: state == DayCardState.safety
                  ? colors.stateDanger
                  : colors.accentSignalInk,
            ),
            const SizedBox(width: TracendSpacing.xs),
            Expanded(
              child: Text(
                state == DayCardState.safety
                    ? 'Your safety first'
                    : readinessKicker,
                style: textTheme.labelSmall?.copyWith(
                  color: state == DayCardState.safety
                      ? colors.stateDanger
                      : colors.accentSignalInk,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Semantics(
          header: true,
          child: Text(
            title ?? body,
            style: title == null
                ? textTheme.bodyMedium
                : textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (title != null) ...[
          const SizedBox(height: 4),
          Text(
            body,
            style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ],
        if (previous != null && state != DayCardState.safety) ...[
          const SizedBox(height: TracendSpacing.xs),
          _Line(previousAnswerLine(previous), color: colors.accentAmber),
        ],
        if (seen.isNotEmpty) ...[
          const SizedBox(height: TracendSpacing.xs),
          if (!seenAlwaysOpen)
            _SeenToggle(
              open: _seenOpen,
              onTap: () => setState(() => _seenOpen = !_seenOpen),
            ),
          if (seenAlwaysOpen || _seenOpen) ...[
            if (seenAlwaysOpen)
              Text(
                seesTitle,
                style: textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            for (final line in seen) _Line(line),
          ],
        ],
        if (stale) ...[
          const SizedBox(height: TracendSpacing.xs),
          const _Line(staleLine),
        ],
        if (failure != null) ...[
          const SizedBox(height: TracendSpacing.xs),
          _Line(failureLine(failure), color: colors.stateDanger),
        ],
        ..._actions(adjustment, state, busy, chooseable, answered),
        if (state != DayCardState.safety &&
            state != DayCardState.coachAdjusted &&
            state != DayCardState.notAvailable &&
            state != DayCardState.note) ...[
          const SizedBox(height: TracendSpacing.xs),
          const _Line(readinessProvenance),
          const _Line(readinessOnlyToday),
        ],
      ],
    );
  }

  List<Widget> _actions(
    DayAdjustment adjustment,
    DayCardState state,
    bool busy,
    bool chooseable,
    bool answered,
  ) {
    final kind = adjustment.kind;
    final talk = _TextAction(
      label: talkToCoach,
      onTap: () => widget.onTalkToCoach(coachQuestion(adjustment)),
    );
    switch (state) {
      case DayCardState.proposed:
        return [
          const SizedBox(height: TracendSpacing.sm),
          _Buttons(
            primary: kindAcceptLabel(kind!),
            onPrimary: busy
                ? null
                : () => _answer(accept: true, done: kindAppliedTitle(kind)),
            secondary: trainAsPlanned,
            onSecondary: busy
                ? null
                : () => _answer(accept: false, done: declinedTitle),
          ),
          Wrap(
            children: [
              if (adjustment.options.any((o) => o.kind != kind))
                _TextAction(
                  label: otherOptionsLabel,
                  onTap: busy ? null : () => _openOptions(adjustment),
                ),
              talk,
            ],
          ),
        ];
      case DayCardState.accepted:
        return [
          const SizedBox(height: TracendSpacing.sm),
          _Buttons(
            primary: undoLabel,
            onPrimary: busy
                ? null
                : () => _answer(accept: false, done: undoneToast),
            primaryFilled: false,
          ),
          Wrap(
            children: [
              if (chooseable)
                _TextAction(
                  label: changeLabel,
                  onTap: busy ? null : () => _openOptions(adjustment),
                ),
              talk,
            ],
          ),
        ];
      case DayCardState.declined:
        return [
          const SizedBox(height: TracendSpacing.sm),
          Wrap(
            children: [
              if (chooseable)
                _TextAction(
                  label: changeLabel,
                  onTap: busy ? null : () => _openOptions(adjustment),
                ),
              talk,
            ],
          ),
        ];
      case DayCardState.checkIn:
      case DayCardState.lowRecovery:
        final checkIn = adjustment.band == DayBand.unknown
            ? widget.onCheckIn
            : null;
        return [
          const SizedBox(height: TracendSpacing.sm),
          if (checkIn != null)
            _Buttons(primary: checkInLabel, onPrimary: checkIn),
          Wrap(
            children: [
              if (chooseable)
                _TextAction(
                  label: chooseYourselfLabel,
                  onTap: busy ? null : () => _openOptions(adjustment),
                ),
              if (adjustment.signals.recoveryLow) talk,
            ],
          ),
        ];
      case DayCardState.begun:
      case DayCardState.safety:
      case DayCardState.coachAdjusted:
      case DayCardState.notAvailable:
      case DayCardState.note:
      case DayCardState.hidden:
        return const [];
    }
  }
}

/// What the athlete picked in the options sheet: a kind, or the plan as written.
class _Choice {
  const _Choice(this.kind);
  final DayAdjustmentKind? kind;
}

class _OptionsBody extends StatelessWidget {
  const _OptionsBody({required this.adjustment, required this.pick});

  final DayAdjustment adjustment;
  final ValueChanged<_Choice> pick;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final current = adjustment.isAccepted ? adjustment.kind : null;
    final declined = adjustment.status == DayAdjustmentStatus.declined;
    Widget row({
      required String title,
      required String subtitle,
      required bool selected,
      required VoidCallback? onTap,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: TracendSpacing.xs),
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.99,
        semanticLabel: selected ? '$title, chosen' : title,
        borderRadius: BorderRadius.circular(TracendRadii.control + 4),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(TracendSpacing.sm),
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            borderRadius: BorderRadius.circular(TracendRadii.control + 4),
            border: selected
                ? Border.all(color: colors.accentSignalRing, width: 1.5)
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  CupertinoIcons.checkmark_alt,
                  size: 18,
                  color: colors.accentSignalInk,
                ),
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: TracendSpacing.xs),
        for (final option in adjustment.options)
          row(
            title: kindChoiceLabel(option.kind),
            subtitle: option.explanation,
            selected: option.kind == current,
            onTap: option.kind == current
                ? null
                : () => pick(_Choice(option.kind)),
          ),
        row(
          title: trainAsPlanned,
          subtitle: 'Do the session as your plan has it.',
          selected: declined,
          onTap: declined ? null : () => pick(const _Choice(null)),
        ),
        const SizedBox(height: TracendSpacing.sm),
      ],
    );
  }
}

/// The card's panel, with the gap that separates it from what follows. A card
/// that is not shown leaves no gap.
class _Panel extends StatelessWidget {
  const _Panel({required this.embedded, required this.child});

  final bool embedded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: TracendSpacing.sm),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(TracendSpacing.sm),
        decoration: BoxDecoration(
          color: embedded ? colors.surfaceRaised : colors.surface,
          borderRadius: BorderRadius.circular(TracendRadii.control + 4),
        ),
        child: child,
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: color ?? context.tracendColors.textSecondary,
      ),
    ),
  );
}

class _SeenToggle extends StatelessWidget {
  const _SeenToggle({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.99,
      semanticLabel: open ? 'Hide $seesTitle' : 'Show $seesTitle',
      borderRadius: BorderRadius.circular(TracendRadii.control),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Expanded(
              child: Text(
                seesTitle,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              open ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
              size: 14,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _Buttons extends StatelessWidget {
  const _Buttons({
    required this.primary,
    required this.onPrimary,
    this.secondary,
    this.onSecondary,
    this.primaryFilled = true,
  });

  final String primary;
  final VoidCallback? onPrimary;
  final String? secondary;
  final VoidCallback? onSecondary;
  final bool primaryFilled;

  @override
  Widget build(BuildContext context) {
    final main = primaryFilled
        ? FilledButton(onPressed: onPrimary, child: Text(primary))
        : OutlinedButton(onPressed: onPrimary, child: Text(primary));
    if (secondary == null) return main;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        main,
        const SizedBox(height: TracendSpacing.xs),
        OutlinedButton(onPressed: onSecondary, child: Text(secondary!)),
      ],
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
    child: Text(label),
  );
}

/// The referral for a day with a safety route, in a sheet that cannot be
/// missed. It has no training choice: "Got it" only closes it.
Future<void> showDaySafetySheet(BuildContext context, String route) {
  final words = safetyWords(route);
  return showTracendSheet<void>(
    context,
    title: words.title,
    builder: (sheetContext) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(words.body, style: Theme.of(sheetContext).textTheme.bodyLarge),
        const SizedBox(height: TracendSpacing.lg),
        FilledButton(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text(gotItLabel),
        ),
        const SizedBox(height: TracendSpacing.sm),
      ],
    ),
  );
}
