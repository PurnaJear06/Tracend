import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/memory/fact_suggestion.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// A fact Coach suggests remembering, with the words that would be saved.
/// Nothing is saved until Confirm is tapped; Dismiss leaves memory as it is.
/// A suggestion to review (the message may cut across a saved allergy) offers
/// no change at all, only OK.
class FactSuggestionChip extends StatelessWidget {
  const FactSuggestionChip({
    required this.suggestion,
    required this.onConfirm,
    required this.onDismiss,
    this.busy = false,
    super.key,
  });

  final CoachFactSuggestion suggestion;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  /// A confirm is being saved.
  final bool busy;

  String get _title => switch (suggestion.action) {
    CoachFactSuggestionAction.add => 'Remember this?',
    CoachFactSuggestionAction.update => 'Update what Coach remembers?',
    CoachFactSuggestionAction.resolve => 'Forget this?',
    CoachFactSuggestionAction.review => 'Check what Coach remembers',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final review = suggestion.action == CoachFactSuggestionAction.review;
    final previous = suggestion.previous;
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
              Expanded(child: Text(_title, style: textTheme.titleSmall)),
            ],
          ),
          const SizedBox(height: TracendSpacing.xxs),
          if (previous != null &&
              suggestion.action == CoachFactSuggestionAction.update)
            Text(
              'Saved: “$previous”',
              style: textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          Text(
            review || suggestion.action == CoachFactSuggestionAction.resolve
                ? '“${previous ?? suggestion.statement}”'
                : '“${suggestion.statement}”',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: TracendSpacing.xxs),
          Text(
            suggestion.reason,
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: TracendSpacing.sm),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: TracendSpacing.xs,
            runSpacing: TracendSpacing.xs,
            children: [
              TextButton(
                onPressed: busy ? null : onDismiss,
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                child: Text(review ? 'OK' : 'Dismiss'),
              ),
              if (!review)
                FilledButton(
                  onPressed: busy ? null : onConfirm,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(88, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: TracendSpacing.md,
                    ),
                  ),
                  child: const Text('Confirm'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
