import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/cycle/cycle_labels.dart';
import 'package:tracend/features/cycle/cycle_repository.dart';
import 'package:tracend/features/readiness/choice_widgets.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';

/// The cycle lengths the stepper offers; the database takes 15 to 60.
const cycleLengthMin = 21;
const cycleLengthMax = 45;
const cycleLengthDefault = 28;

/// A cycle length in days, nudged one day at a time.
class CycleLengthStepper extends StatelessWidget {
  const CycleLengthStepper({
    required this.days,
    required this.onChanged,
    super.key,
  });

  final int days;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Shorter cycle',
          onPressed: days <= cycleLengthMin ? null : () => onChanged(days - 1),
          icon: const Icon(CupertinoIcons.minus_circle),
        ),
        Semantics(
          liveRegion: true,
          label: '$days days',
          excludeSemantics: true,
          child: SizedBox(
            width: 120,
            child: Text(
              '$days days',
              textAlign: TextAlign.center,
              style: TracendTheme.numeric(
                colors,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Longer cycle',
          onPressed: days >= cycleLengthMax ? null : () => onChanged(days + 1),
          icon: const Icon(CupertinoIcons.plus_circle),
        ),
      ],
    );
  }
}

/// The four ways her cycle works, as a titled list of choices.
class CycleStatusChoices extends StatelessWidget {
  const CycleStatusChoices({
    required this.selected,
    required this.onChosen,
    super.key,
  });

  final CycleStatus? selected;
  final ValueChanged<CycleStatus> onChosen;

  @override
  Widget build(BuildContext context) => ChoiceGroup(
    title: 'Which fits you best?',
    options: [
      for (final status in CycleStatus.values)
        (
          label: cycleStatusLabel(status),
          selected: status == selected,
          onTap: () => onChosen(status),
        ),
    ],
  );
}

/// Asks how her cycle works. Completes with the choice, or null when she
/// leaves.
Future<CycleStatus?> showCycleStatusSheet(
  BuildContext context, {
  CycleStatus? selected,
}) => showTracendSheet<CycleStatus>(
  context,
  title: 'Your cycle',
  builder: (sheetContext) => Padding(
    padding: const EdgeInsets.only(bottom: TracendSpacing.md),
    child: CycleStatusChoices(
      selected: selected,
      onChosen: (status) => Navigator.of(sheetContext).pop(status),
    ),
  ),
);

/// What the length sheet returns: a length, or null for "Not sure". A sheet
/// that is dismissed returns no pick at all.
class CycleLengthPick {
  const CycleLengthPick(this.days);

  final int? days;
}

/// Asks how long her cycle usually is, from the first day of one period to the
/// first day of the next.
Future<CycleLengthPick?> showCycleLengthSheet(
  BuildContext context, {
  int? current,
}) => showTracendSheet<CycleLengthPick>(
  context,
  title: 'How long is your cycle usually?',
  subtitle: 'From the first day of one period to the first day of the next.',
  builder: (_) => _LengthSheet(initial: current),
);

class _LengthSheet extends StatefulWidget {
  const _LengthSheet({required this.initial});

  final int? initial;

  @override
  State<_LengthSheet> createState() => _LengthSheetState();
}

class _LengthSheetState extends State<_LengthSheet> {
  late int _days = (widget.initial ?? cycleLengthDefault).clamp(
    cycleLengthMin,
    cycleLengthMax,
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: TracendSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CycleLengthStepper(
          days: _days,
          onChanged: (days) => setState(() => _days = days),
        ),
        const SizedBox(height: TracendSpacing.md),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(CycleLengthPick(_days)),
          child: const Text('Save'),
        ),
        const SizedBox(height: TracendSpacing.xs),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const CycleLengthPick(null)),
          child: const Text('Not sure'),
        ),
      ],
    ),
  );
}
