import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/train/widgets/rpe_picker.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';

/// Asks how hard the whole workout was before it is finished. Completes with
/// the athlete's 1–10 session effort, or null when they keep logging.
///
/// The answer is required and nothing is preselected: it sets the training
/// load, and it is never derived from the sets' own efforts.
Future<int?> showWorkoutFinishSheet(
  BuildContext context, {
  required String workoutName,
  required int unloggedSets,
}) => showTracendSheet<int>(
  context,
  title: 'Finish workout',
  subtitle: workoutName,
  builder: (sheetContext) => WorkoutFinishForm(
    unloggedSets: unloggedSets,
    onFinish: (effort) => Navigator.of(sheetContext).pop(effort),
    onKeepLogging: () => Navigator.of(sheetContext).pop(),
  ),
);

/// The body of the finish sheet.
class WorkoutFinishForm extends StatefulWidget {
  const WorkoutFinishForm({
    required this.unloggedSets,
    required this.onFinish,
    required this.onKeepLogging,
    super.key,
  });

  final int unloggedSets;
  final ValueChanged<int> onFinish;
  final VoidCallback onKeepLogging;

  @override
  State<WorkoutFinishForm> createState() => _WorkoutFinishFormState();
}

class _WorkoutFinishFormState extends State<WorkoutFinishForm>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake;
  int? _effort;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _finish() {
    final effort = _effort;
    if (effort == null) {
      TracendHaptics.warning();
      setState(() => _missing = true);
      if (TracendMotionScope.of(context) == TracendMotionLevel.full) {
        _shake.forward(from: 0);
      }
      return;
    }
    widget.onFinish(effort);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final text = Theme.of(context).textTheme;
    final effort = _effort;
    final unlogged = widget.unloggedSets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: TracendSpacing.xs),
        Semantics(
          header: true,
          child: Text(
            'How hard was this workout overall?',
            style: text.titleMedium,
          ),
        ),
        const SizedBox(height: TracendSpacing.sm),
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) => Transform.translate(
            offset: Offset(
              math.sin(_shake.value * math.pi * 4) * 6 * (1 - _shake.value),
              0,
            ),
            child: child,
          ),
          child: EffortScale(
            value: effort,
            height: 54,
            fontSize: 22,
            describe: sessionEffortAnchor,
            onSelected: (value) => setState(() {
              _effort = value;
              _missing = false;
            }),
          ),
        ),
        const SizedBox(height: TracendSpacing.xs),
        Wrap(
          spacing: TracendSpacing.sm,
          runSpacing: 2,
          children: [
            for (final anchor in const [
              '1–2 very easy',
              '3–4 easy',
              '5–6 moderate',
              '7–8 hard',
              '9 very hard',
              '10 max',
            ])
              Text(
                anchor,
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
          ],
        ),
        const SizedBox(height: TracendSpacing.sm),
        Semantics(
          liveRegion: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 26),
            child: _missing
                ? Text(
                    'Pick a number from 1 to 10 first.',
                    style: text.bodyMedium?.copyWith(
                      color: colors.accentAmber,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : effort == null
                ? const SizedBox.shrink()
                : Text(
                    '$effort, ${sessionEffortAnchor(effort)}',
                    style: text.titleMedium,
                  ),
          ),
        ),
        if (unlogged > 0) ...[
          const SizedBox(height: TracendSpacing.xs),
          Text(
            unlogged == 1
                ? '1 set is not logged. It stays unlogged, not skipped.'
                : '$unlogged sets are not logged. They stay unlogged, not '
                      'skipped.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ],
        const SizedBox(height: TracendSpacing.xs),
        Text(
          'This number sets your training load. It is separate from the '
          'effort on each set.',
          style: text.bodySmall?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: TracendSpacing.lg),
        FilledButton(onPressed: _finish, child: const Text('Finish workout')),
        const SizedBox(height: TracendSpacing.xs),
        TextButton(
          onPressed: widget.onKeepLogging,
          child: const Text('Keep logging'),
        ),
      ],
    );
  }
}
