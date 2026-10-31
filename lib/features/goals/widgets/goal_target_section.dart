import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/goals/goal_target.dart';
import 'package:tracend/features/goals/goal_target_repository.dart';
import 'package:tracend/features/goals/widgets/goal_target_sheet.dart';
import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';
import 'package:tracend/shared/widgets/grouped_list.dart';

/// The goal's end point on Progress: "Set your target" while none exists, the
/// chosen target with an Edit action afterwards. Shows nothing without an
/// active goal or when the target cannot be read, so a failed read never
/// blocks the screen.
class GoalTargetSection extends StatefulWidget {
  const GoalTargetSection({required this.repository, super.key});

  final GoalTargetRepository repository;

  @override
  State<GoalTargetSection> createState() => _GoalTargetSectionState();
}

class _GoalTargetSectionState extends State<GoalTargetSection> {
  GoalTargetState? _state;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await widget.repository.load();
      if (mounted) setState(() => _state = state);
    } catch (e) {
      logNonCritical(e);
    }
  }

  Future<void> _open(GoalTargetState state) async {
    final saved = await showTracendSheet<GoalTargetState>(
      context,
      title: state.hasTarget ? 'Your target' : 'Set your target',
      scrollable: false,
      builder: (_) => GoalTargetSheet(
        initial: state.target,
        minWeightKg: state.minTargetWeightKg,
        onSave: widget.repository.save,
      ),
    );
    if (saved == null || !mounted) return;
    setState(() => _state = saved);
    unawaited(TracendHaptics.success());
    TracendToast.show(context, 'Target saved');
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null || !state.hasGoal) return const SizedBox.shrink();
    final theme = Theme.of(context).textTheme;
    final hasTarget = state.hasTarget;
    return Padding(
      padding: const EdgeInsets.only(top: TracendSpacing.md),
      child: PremiumGradientCard(
        key: const ValueKey('goal-target-card'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TracendRowIcon(icon: CupertinoIcons.flag_fill),
            const SizedBox(height: TracendSpacing.sm),
            Text(
              hasTarget ? 'Your target' : 'Set your target',
              style: theme.titleMedium,
            ),
            const SizedBox(height: TracendSpacing.xxs),
            Text(
              hasTarget
                  ? state.target.summary
                  : 'Your goal has no end point yet. Choose a weight, a '
                        'body-fat range or a look to aim for. Only you set '
                        'it, and you can change it any time.',
              style: theme.bodyMedium,
            ),
            const SizedBox(height: TracendSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: hasTarget
                  ? OutlinedButton(
                      key: const ValueKey('goal-target-edit'),
                      onPressed: () => _open(state),
                      child: const Text('Change target'),
                    )
                  : FilledButton(
                      key: const ValueKey('goal-target-set'),
                      onPressed: () => _open(state),
                      child: const Text('Set target'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
