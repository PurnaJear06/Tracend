import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// Asks before the Coach remembers something the athlete said, such as a
/// food they avoid. Nothing is saved until Save is tapped (a durable user
/// fact needs explicit approval).
class PreferencePromptChip extends StatelessWidget {
  const PreferencePromptChip({
    required this.category,
    required this.prefKey,
    required this.value,
    required this.onConfirm,
    this.onDismiss,
    super.key,
  });

  final String category;
  final String prefKey;
  final String value;
  final VoidCallback onConfirm;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    return TracendCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  CupertinoIcons.bookmark,
                  size: 18,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: TracendSpacing.xs),
              Expanded(
                child: Text(
                  'Remember this $category preference?',
                  style: textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: TracendSpacing.xxs),
          Text(
            '“$value”',
            style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: TracendSpacing.sm),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: TracendSpacing.xs,
            runSpacing: TracendSpacing.xs,
            children: [
              if (onDismiss != null)
                TextButton(
                  onPressed: onDismiss,
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  child: const Text('Dismiss'),
                ),
              FilledButton(
                onPressed: onConfirm,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(88, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: TracendSpacing.md,
                  ),
                ),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
