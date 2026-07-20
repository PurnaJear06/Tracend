import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

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
    return TracendCard(
      padding: const EdgeInsets.all(TracendSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.bookmark, size: 16, color: colors.stateStable),
              const SizedBox(width: TracendSpacing.xs),
              Expanded(
                child: Text(
                  'Remember this $category preference?',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: TracendSpacing.xxs),
          Text(
            '"$value"',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: TracendSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (onDismiss != null)
                TextButton(
                  onPressed: onDismiss,
                  child: const Text('Dismiss'),
                ),
              const SizedBox(width: TracendSpacing.xs),
              FilledButton.tonalIcon(
                onPressed: onConfirm,
                icon: const Icon(CupertinoIcons.check_mark, size: 16),
                label: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
