import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/readiness/choice_widgets.dart';
import 'package:tracend/features/readiness/day_adjustment.dart';
import 'package:tracend/features/readiness/pain_check.dart';
import 'package:tracend/features/readiness/pain_reporting.dart';
import 'package:tracend/features/readiness/safety_copy.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';

/// What the athlete does after the pain check on an exercise.
enum PainChipAction {
  /// Keep going, lightly (pain of 1 to 3).
  continueExercise,

  /// Leave the rest of this exercise out.
  skipExercise,

  /// Swap this exercise for the gentler one the check offered.
  useSwap,

  /// Stop the workout.
  endWorkout,
}

/// Asks the pain check for one exercise during a workout (UX_FLOWS.md §6):
/// where, how strong, and the two red-flag questions a person can answer
/// mid-set. The report goes to Tracend through [reporting] (or waits on the
/// phone). Resolves with what was sent or kept, or null when the sheet was
/// closed without answering.
///
/// [preselected] is the joint the exercise is known to load; the athlete can
/// change it. [localDate] is the server's today, `YYYY-MM-DD`.
Future<PainSubmission?> showPainCheckSheet(
  BuildContext context, {
  required PainReporting reporting,
  required String exerciseName,
  required String localDate,
  PainArea? preselected,
  String? exercisePerformanceId,
}) => showTracendSheet<PainSubmission>(
  context,
  title: chipTitle,
  subtitle: exerciseName,
  builder: (_) => _PainCheckForm(
    reporting: reporting,
    localDate: localDate,
    preselected: preselected,
    exercisePerformanceId: exercisePerformanceId,
  ),
);

class _PainCheckForm extends StatefulWidget {
  const _PainCheckForm({
    required this.reporting,
    required this.localDate,
    required this.preselected,
    required this.exercisePerformanceId,
  });

  final PainReporting reporting;
  final String localDate;
  final PainArea? preselected;
  final String? exercisePerformanceId;

  @override
  State<_PainCheckForm> createState() => _PainCheckFormState();
}

class _PainCheckFormState extends State<_PainCheckForm> {
  late PainArea? _area = widget.preselected;
  int? _severity;
  bool? _sharp;
  bool? _numb;
  bool _incomplete = false;
  bool _sending = false;

  bool get _complete =>
      _area != null && _severity != null && _sharp != null && _numb != null;

  Future<void> _submit() async {
    if (!_complete) {
      setState(() => _incomplete = true);
      return;
    }
    setState(() => _sending = true);
    final report = PainReport(
      localDate: widget.localDate,
      area: _area!,
      severity: _severity!,
      // The two questions are the red flags a person can answer mid-set.
      redFlags: [if (_sharp!) 'pop_or_sudden', if (_numb!) 'numb_weak_limb'],
      idempotencyKey: newIdempotencyKey(),
      exercisePerformanceId: widget.exercisePerformanceId,
    );
    final submission = await widget.reporting.submit(report);
    if (!mounted) return;
    Navigator.of(context).pop(submission);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    Widget yesNo(String title, bool? value, ValueChanged<bool> onChanged) =>
        ChoiceGroup(
          title: title,
          options: [
            (
              label: chipYes,
              selected: value == true,
              onTap: () => setState(() {
                onChanged(true);
                _incomplete = false;
              }),
            ),
            (
              label: chipNo,
              selected: value == false,
              onTap: () => setState(() {
                onChanged(false);
                _incomplete = false;
              }),
            ),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChoiceGroup(
          title: chipWhereTitle,
          options: [
            for (final area in PainArea.values)
              (
                label: areaChoice(area),
                selected: _area == area,
                onTap: () => setState(() {
                  _area = area;
                  _incomplete = false;
                }),
              ),
          ],
        ),
        const SizedBox(height: TracendSpacing.lg),
        Text(chipStrengthTitle, style: textTheme.titleMedium),
        const SizedBox(height: TracendSpacing.xxs),
        Text(
          '1 is barely noticeable, 10 is the worst you can imagine.',
          style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: TracendSpacing.sm),
        Wrap(
          spacing: TracendSpacing.xs,
          runSpacing: TracendSpacing.xs,
          children: [
            for (var level = 1; level <= 10; level++)
              SeverityChip(
                level: level,
                selected: _severity == level,
                onTap: () => setState(() {
                  _severity = level;
                  _incomplete = false;
                }),
              ),
          ],
        ),
        const SizedBox(height: TracendSpacing.lg),
        yesNo(chipSharpTitle, _sharp, (value) => _sharp = value),
        const SizedBox(height: TracendSpacing.lg),
        yesNo(chipNumbTitle, _numb, (value) => _numb = value),
        if (_incomplete) ...[
          const SizedBox(height: TracendSpacing.sm),
          Semantics(
            liveRegion: true,
            child: Text(
              chipRequired,
              style: textTheme.bodySmall?.copyWith(color: colors.stateDanger),
            ),
          ),
        ],
        const SizedBox(height: TracendSpacing.lg),
        FilledButton(
          onPressed: _sending ? null : _submit,
          child: Text(_sending ? 'Saving…' : chipSave),
        ),
        const SizedBox(height: TracendSpacing.sm),
      ],
    );
  }
}

/// What the check says to do, and the choices that follow. Pain of 4 to 6
/// offers [swap] (when the exercise has not been started and a gentler one is
/// known); pain of 7 or more, a red flag or any other route out stops the
/// exercise and shows the referral, and cannot be closed without choosing.
Future<PainChipAction?> showPainResultSheet(
  BuildContext context, {
  required PainSubmission submission,
  JointSwap? swap,
}) {
  final outcome = submission.outcome;
  final stops = outcome.routesOut;
  return showTracendSheet<PainChipAction>(
    context,
    title: switch (outcome) {
      PainOutcome.modify => chipSwapTitle,
      PainOutcome.watch || PainOutcome.clear => chipLightTitle,
      _ => chipStopTitle,
    },
    isDismissible: !stops,
    enableDrag: !stops,
    showCloseButton: !stops,
    builder: (sheetContext) => _PainResult(
      submission: submission,
      swap: swap,
      onPick: (action) => Navigator.of(sheetContext).pop(action),
    ),
  );
}

class _PainResult extends StatelessWidget {
  const _PainResult({
    required this.submission,
    required this.swap,
    required this.onPick,
  });

  final PainSubmission submission;
  final JointSwap? swap;
  final ValueChanged<PainChipAction> onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final outcome = submission.outcome;
    final route = outcome.route;
    final words = route == null ? null : safetyWords(route);
    final String body = switch (outcome) {
      PainOutcome.modify => chipSwapBody(swap?.name),
      PainOutcome.watch || PainOutcome.clear => chipLightBody,
      _ => chipStopBody,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(body, style: textTheme.bodyLarge),
        if (words != null) ...[
          const SizedBox(height: TracendSpacing.md),
          Text(words.title, style: textTheme.titleMedium),
          const SizedBox(height: TracendSpacing.xxs),
          Text(words.body, style: textTheme.bodyMedium),
        ],
        if (!submission.sent) ...[
          const SizedBox(height: TracendSpacing.sm),
          Text(
            submission.refused ? chipNotRecorded : chipQueued,
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
        const SizedBox(height: TracendSpacing.lg),
        ..._actions(),
        const SizedBox(height: TracendSpacing.sm),
      ],
    );
  }

  List<Widget> _actions() {
    Widget filled(String label, PainChipAction action) =>
        FilledButton(onPressed: () => onPick(action), child: Text(label));
    Widget outlined(String label, PainChipAction action) =>
        OutlinedButton(onPressed: () => onPick(action), child: Text(label));
    const gap = SizedBox(height: TracendSpacing.xs);
    return switch (submission.outcome) {
      PainOutcome.watch || PainOutcome.clear => [
        filled(chipContinue, PainChipAction.continueExercise),
      ],
      PainOutcome.modify => [
        if (swap != null) ...[
          filled(chipUseSwap(swap!.name), PainChipAction.useSwap),
          gap,
          outlined(chipSkipExercise, PainChipAction.skipExercise),
        ] else
          filled(chipSkipExercise, PainChipAction.skipExercise),
      ],
      _ => [
        filled(chipSkipExercise, PainChipAction.skipExercise),
        gap,
        outlined(chipEndWorkout, PainChipAction.endWorkout),
      ],
    };
  }
}
