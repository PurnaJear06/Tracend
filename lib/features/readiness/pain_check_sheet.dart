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
/// mid-set. The report is handed to [reporting] and the sheet closes at once:
/// it resolves with the submission (the phone's own outcome now, the sending
/// settling in the background), or null when the sheet was closed without
/// answering.
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

  bool get _complete =>
      _area != null && _severity != null && _sharp != null && _numb != null;

  void _submit() {
    if (!_complete) {
      setState(() => _incomplete = true);
      return;
    }
    final report = PainReport(
      localDate: widget.localDate,
      area: _area!,
      severity: _severity!,
      // Only two of the ten questions are asked mid-set: "no" to both is not
      // "none of these", so nothing is claimed about the rest (null).
      redFlags: _sharp! || _numb!
          ? [if (_sharp!) 'pop_or_sudden', if (_numb!) 'numb_weak_limb']
          : null,
      idempotencyKey: newIdempotencyKey(),
      exercisePerformanceId: widget.exercisePerformanceId,
    );
    // The answer never waits on the network: the sheet closes with what the
    // phone works out, and the report goes on its way meanwhile.
    Navigator.of(context).pop(widget.reporting.submit(report));
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
        FilledButton(onPressed: _submit, child: const Text(chipSave)),
        const SizedBox(height: TracendSpacing.sm),
      ],
    );
  }
}

/// What the check says to do, and the choices that follow. Pain of 4 to 6
/// offers [swap] (when the exercise has not been started and a gentler one is
/// known). Pain of 7 or more, a red flag, any other route out, an area that is
/// held, or a day that already has a safety route stops the exercise and shows
/// the referral or the hold: no swap and no keep going, and the sheet cannot
/// be closed without choosing.
///
/// [dayRoute] is the safety route today already has, if any; [heldArea] the
/// area the report is about when it is held.
Future<PainChipAction?> showPainResultSheet(
  BuildContext context, {
  required PainSubmission submission,
  JointSwap? swap,
  String? dayRoute,
  bool heldArea = false,
}) {
  final outcome = submission.outcome;
  final route = stricterRoute(outcome.route, dayRoute);
  final stops = route != null || heldArea;
  return showTracendSheet<PainChipAction>(
    context,
    title: stops
        ? chipStopTitle
        : switch (outcome) {
            PainOutcome.modify => chipSwapTitle,
            _ => chipLightTitle,
          },
    isDismissible: !stops,
    enableDrag: !stops,
    showCloseButton: !stops,
    builder: (sheetContext) => _PainResult(
      submission: submission,
      swap: stops ? null : swap,
      route: route,
      heldArea: heldArea,
      onPick: (action) => Navigator.of(sheetContext).pop(action),
    ),
  );
}

class _PainResult extends StatelessWidget {
  const _PainResult({
    required this.submission,
    required this.swap,
    required this.route,
    required this.heldArea,
    required this.onPick,
  });

  final PainSubmission submission;
  final JointSwap? swap;
  final String? route;
  final bool heldArea;
  final ValueChanged<PainChipAction> onPick;

  bool get _stops => route != null || heldArea;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final words = route == null ? null : safetyWords(route!);
    final String body = _stops
        ? chipStopBody
        : switch (submission.outcome) {
            PainOutcome.modify => chipSwapBody(swap?.name),
            _ => chipLightBody,
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
        ] else if (heldArea) ...[
          const SizedBox(height: TracendSpacing.md),
          Text(
            heldAreaLine(submission.report.area),
            style: textTheme.bodyMedium,
          ),
        ],
        FutureBuilder<PainDelivery>(
          future: submission.delivery,
          builder: (context, snapshot) {
            final delivery = snapshot.data;
            if (delivery == null || delivery.sent) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: TracendSpacing.sm),
              child: Text(
                delivery.refused ? chipNotRecorded : chipQueued,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            );
          },
        ),
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
    if (_stops) {
      return [
        filled(chipSkipExercise, PainChipAction.skipExercise),
        gap,
        outlined(chipEndWorkout, PainChipAction.endWorkout),
      ];
    }
    return switch (submission.outcome) {
      PainOutcome.modify => [
        if (swap != null) ...[
          filled(chipUseSwap(swap!.name), PainChipAction.useSwap),
          gap,
          outlined(chipSkipExercise, PainChipAction.skipExercise),
        ] else
          filled(chipSkipExercise, PainChipAction.skipExercise),
      ],
      _ => [filled(chipContinue, PainChipAction.continueExercise)],
    };
  }
}
