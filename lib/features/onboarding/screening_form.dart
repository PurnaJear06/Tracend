import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/onboarding/choice_widgets.dart';
import 'package:tracend/features/onboarding/onboarding_screening.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// The health check's questions and what the server answered, shared by
/// onboarding and the Account screen that reopens the check. The widget holds
/// no state: the caller keeps the answers and records them.
class ScreeningForm extends StatelessWidget {
  const ScreeningForm({
    required this.exercisesRegularly,
    required this.knownCondition,
    required this.symptoms,
    required this.clearedByProfessional,
    required this.outcome,
    required this.locked,
    required this.onExercisesRegularly,
    required this.onKnownCondition,
    required this.onSymptoms,
    required this.onClearedByProfessional,
    super.key,
  });

  final bool? exercisesRegularly;
  final bool? knownCondition;
  final bool? symptoms;
  final bool? clearedByProfessional;

  /// What the server answered for the answers on screen; null until recorded.
  final ScreeningOutcome? outcome;

  /// Locked while the answers are being recorded, so the response always
  /// belongs to the answers on screen.
  final bool locked;
  final ValueChanged<bool> onExercisesRegularly;
  final ValueChanged<bool> onKnownCondition;
  final ValueChanged<bool> onSymptoms;
  final ValueChanged<bool> onClearedByProfessional;

  Widget _question(
    BuildContext context, {
    required String label,
    required String hint,
    required bool? value,
    required ValueChanged<bool> onChanged,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(
          top: TracendSpacing.md,
          bottom: TracendSpacing.xs,
        ),
        child: Text(label, style: Theme.of(context).textTheme.titleMedium),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: TracendSpacing.xs),
        child: Text(hint, style: Theme.of(context).textTheme.bodySmall),
      ),
      IgnorePointer(
        ignoring: locked,
        child: SingleChoice<bool>(
          label: label,
          options: const [(true, 'Yes'), (false, 'No')],
          selected: value,
          onChanged: onChanged,
        ),
      ),
    ],
  );

  Widget _card(BuildContext context, String title, String body) => Padding(
    padding: const EdgeInsets.only(top: TracendSpacing.lg),
    child: Semantics(
      liveRegion: true,
      child: TracendCard(
        raised: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: TracendSpacing.xs),
            Text(body, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _question(
        context,
        label: 'Do you exercise regularly now?',
        hint:
            'Planned exercise of about 30 minutes or more, on at least 3 days a week, for the last 3 months.',
        value: exercisesRegularly,
        onChanged: onExercisesRegularly,
      ),
      _question(
        context,
        label:
            'Do you know you have a heart, diabetes or other metabolic, or kidney condition?',
        hint:
            'One that a doctor or another health professional has told you about.',
        value: knownCondition,
        onChanged: onKnownCondition,
      ),
      _question(
        context,
        label: 'Do you notice any of these right now?',
        hint:
            'Chest pain or pressure, breathlessness at rest or with light effort, dizziness or fainting, swollen ankles, a racing or skipping heartbeat, or cramping leg pain when you walk.',
        value: symptoms,
        onChanged: onSymptoms,
      ),
      if (ScreeningAnswers.asksClearance(
        knownCondition: knownCondition,
        symptoms: symptoms,
      ))
        _question(
          context,
          label: 'Has a health professional said you are fine to exercise?',
          hint: 'A doctor, nurse or other qualified professional.',
          value: clearedByProfessional,
          onChanged: onClearedByProfessional,
        ),
      if (outcome == ScreeningOutcome.seeProfessional)
        _card(
          context,
          'Please see a health professional first.',
          'From your answers, it is best to check with a doctor or another health professional before you start exercising. Tracend cannot build a plan until then. Come back and answer again once you have been cleared. If you have chest pain, severe breathlessness or fainting now, get medical help straight away.',
        ),
      if (outcome == ScreeningOutcome.moderateUntilCleared)
        _card(
          context,
          'Your plan will stay at moderate effort.',
          'Until a health professional has said you are fine to exercise, Tracend keeps every session at a comfortable effort, with no all-out sets. Talk to your doctor when you can, then update this answer.',
        ),
    ],
  );
}
