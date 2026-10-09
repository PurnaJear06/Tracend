import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/consent/photo_ai_notice.dart';

/// The notice shown before a photo goes to an AI provider, with the choice.
/// The physique check and meal photo analysis both use it; the server refuses
/// either until the current notice is granted.
class AiNoticePanel extends StatelessWidget {
  const AiNoticePanel({
    required this.title,
    required this.notice,
    required this.agreeLabel,
    required this.onAgree,
    required this.onDecline,
    this.busy = false,
    this.error,
    super.key,
  });

  final String title;
  final PhotoAiNotice? notice;
  final String agreeLabel;
  final VoidCallback onAgree;
  final VoidCallback onDecline;
  final bool busy;

  /// Shown above the buttons, for example when the choice was not saved.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final paragraphs = notice?.paragraphs ?? const <String>[];
    final message = error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.headlineSmall),
        const SizedBox(height: TracendSpacing.md),
        for (var i = 0; i < paragraphs.length; i++) ...[
          if (i > 0) const SizedBox(height: TracendSpacing.sm),
          Text(paragraphs[i], style: theme.bodyLarge),
        ],
        const SizedBox(height: TracendSpacing.lg),
        if (message != null) ...[
          Text(
            message,
            style: TextStyle(color: context.tracendColors.stateDanger),
          ),
          const SizedBox(height: TracendSpacing.sm),
        ],
        FilledButton.icon(
          onPressed: busy ? null : onAgree,
          icon: const Icon(CupertinoIcons.sparkles),
          label: Text(agreeLabel),
        ),
        const SizedBox(height: TracendSpacing.xs),
        TextButton(
          onPressed: busy ? null : onDecline,
          child: const Text('Not now'),
        ),
      ],
    );
  }
}
