import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/guidance/guidance_copy.dart';
import 'package:tracend/features/train/guidance/training_guidance.dart';
import 'package:tracend/features/train/widgets/train_parts.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';

/// Opens "Cardio this week": the minutes counted against the guideline, what
/// is open today, and where the numbers come from. Nothing is estimated: with
/// too little Apple Health data the sheet says so and shows no minutes.
Future<void> showCardioWeekSheet(
  BuildContext context, {
  required CardioWeek week,
}) => showTracendSheet<void>(
  context,
  title: cardioTitle,
  subtitle: cardioWindowLine(week),
  builder: (_) => CardioWeekSheetBody(week: week),
);

class CardioWeekSheetBody extends StatelessWidget {
  const CardioWeekSheetBody({required this.week, super.key});

  final CardioWeek week;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final done = week.doneMin;
    final stretch = cardioStretchLine(week);
    final easyGuide = cardioEasyGuideLine(week);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: TracendSpacing.xs),
        if (done == null) ...[
          Semantics(
            header: true,
            child: Text(cardioNoDataTitle, style: trainDisplay(context)),
          ),
          const SizedBox(height: 6),
          Text(cardioNoDataBody, style: textTheme.bodyMedium),
        ] else ...[
          Semantics(
            label: '$done of ${week.targetMin} minutes of cardio',
            excludeSemantics: true,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$done', style: trainDisplay(context)),
                  TextSpan(
                    text: ' of ${week.targetMin} min',
                    style: textTheme.titleMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: TracendSpacing.xs),
          _Progress(done: done, target: week.targetMin),
          const SizedBox(height: TracendSpacing.xs),
          Text(cardioStandingLine(week), style: textTheme.bodyMedium),
          if (!week.intensityKnown) ...[
            const SizedBox(height: 6),
            Text(
              cardioAllModerate,
              style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
        const SizedBox(height: 6),
        Text(
          cardioGuideline,
          style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
        if (stretch != null)
          Text(
            stretch,
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        const SizedBox(height: TracendSpacing.md),
        _Today(week: week, easyGuide: easyGuide),
        const SizedBox(height: TracendSpacing.md),
        const TrainNote(
          icon: CupertinoIcons.info,
          text: cardioPermissionNote,
          raised: true,
        ),
        const SizedBox(height: TracendSpacing.sm),
        Text(
          cardioProvenance,
          style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: TracendSpacing.lg),
      ],
    );
  }
}

/// What is open today: hard cardio when the rules allow it, else easy only
/// with the conditions that open it.
class _Today extends StatelessWidget {
  const _Today({required this.week, required this.easyGuide});

  final CardioWeek week;
  final String? easyGuide;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final open = week.vigorousAllowed;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              open ? cardioHardTitle : cardioEasyOnlyTitle,
              style: textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: 4),
          if (open)
            Text(cardioHardOpenLine(week), style: textTheme.bodyMedium)
          else ...[
            Text(cardioEasyOnlyIntro, style: textTheme.bodyMedium),
            const SizedBox(height: 4),
            for (final condition in cardioEasyOnlyConditions)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '• $condition',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 8),
          Text(cardioEasyTalk, style: textTheme.bodyMedium),
          if (easyGuide != null)
            Text(
              easyGuide!,
              style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.target});

  final int done;
  final int target;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final fraction = (done / target).clamp(0.0, 1.0);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          children: [
            Container(height: 8, color: colors.surfaceRaised),
            FractionallySizedBox(
              widthFactor: fraction,
              child: Container(height: 8, color: colors.stateStable),
            ),
          ],
        ),
      ),
    );
  }
}
