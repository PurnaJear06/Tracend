import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// Where she is in her cycle, as one quiet row under the plan: "Cycle day 18 ·
/// period expected 8–12 Dec". It explains; it never changes a number.
class CycleLine extends StatelessWidget {
  const CycleLine({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Semantics(
      key: const ValueKey('cycle-line'),
      label: text,
      excludeSemantics: true,
      child: Text(
        text,
        style: TracendTheme.numeric(
          colors,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}

/// After months with no period logged: a neutral card that suggests a doctor
/// if it is not expected, and offers to log a period or update her status. It
/// diagnoses nothing.
class CycleLongGapCard extends StatelessWidget {
  const CycleLongGapCard({
    required this.message,
    required this.onLogPeriod,
    required this.onUpdateStatus,
    super.key,
  });

  final String message;
  final VoidCallback onLogPeriod;
  final VoidCallback onUpdateStatus;

  @override
  Widget build(BuildContext context) => TracendCard(
    key: const ValueKey('cycle-long-gap'),
    raised: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: TracendSpacing.xs),
        Wrap(
          spacing: TracendSpacing.xs,
          children: [
            TextButton(
              key: const ValueKey('cycle-long-gap-log'),
              onPressed: onLogPeriod,
              child: const Text('Log a period'),
            ),
            TextButton(
              key: const ValueKey('cycle-long-gap-status'),
              onPressed: onUpdateStatus,
              child: const Text('Update my cycle status'),
            ),
          ],
        ),
      ],
    ),
  );
}
