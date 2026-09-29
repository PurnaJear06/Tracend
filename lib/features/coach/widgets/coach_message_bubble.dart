import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/widgets/reasoning_chain_card.dart';
import 'package:tracend/shared/widgets/evidence_accordion.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// Chat bubble for one Coach message (plan §6.2).
///
/// Binding contract:
/// - evidence rows = `CoachMessage.evidence` (label + source, display-only)
/// - missing data = `CoachMessage.missingData`
/// - suggested prompts ONLY from `CoachMessage.suggestedFollowUps`
/// - provider label from `CoachMessage.modelProvider`
/// - reasoning from `CoachMessage.reasoningChain` (structured data only —
///   never hidden model chain-of-thought)
/// - a data summary (`CoachMessage.isDataSummary`) is labeled as not an AI
///   answer, never carries the provider label, and shows the beta diagnostic
///   when the live response included one. A safety referral
///   (`CoachMessage.isSafetyReferral`) is labeled as a safety note without the
///   data-summary styling.
class CoachMessageBubble extends StatelessWidget {
  const CoachMessageBubble({
    required this.message,
    this.onSendFollowUp,
    this.onRetry,
    super.key,
  });

  final CoachMessage message;
  final void Function(String prompt)? onSendFollowUp;

  /// Asks the question again. Offered on a data summary that ends the
  /// conversation.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final user = message.role == 'user';
    final summary = !user && message.isDataSummary;
    final referral = summary && message.isSafetyReferral;
    final diagnostic = summary ? message.diagnostic : null;
    final colors = context.tracendColors;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Semantics(
        label: user
            ? 'You said'
            : referral
            ? 'Safety note'
            : summary
            ? 'Data summary'
            : 'Coach said',
        child: Container(
          constraints: const BoxConstraints(maxWidth: 620),
          padding: const EdgeInsets.all(TracendSpacing.md),
          decoration: BoxDecoration(
            color: user ? colors.actionPrimary : colors.surface,
            border: user
                ? null
                : Border.all(
                    color: summary && !referral
                        ? colors.stateAttention
                        : colors.borderSubtle,
                  ),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(user ? 18 : 4),
              bottomRight: Radius.circular(user ? 4 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (summary) ...[
                TracendPill(
                  label: referral
                      ? 'Safety note · not an AI answer'
                      : 'Data summary · not an AI answer',
                  icon: referral
                      ? CupertinoIcons.heart
                      : CupertinoIcons.doc_text,
                  color: colors.stateAttention,
                ),
                const SizedBox(height: TracendSpacing.sm),
              ],
              SelectableText(
                message.content,
                style: TextStyle(
                  color: user ? colors.actionOnPrimary : colors.textPrimary,
                  height: 1.45,
                ),
              ),
              if (!user && message.reasoningChain.isNotEmpty) ...[
                const SizedBox(height: TracendSpacing.sm),
                ReasoningChainCard(chain: message.reasoningChain),
              ],
              if (!user && !summary && message.modelProvider != null) ...[
                const SizedBox(height: TracendSpacing.xs),
                TracendPill(
                  label: message.modelProvider == 'groq'
                      ? 'Qwen AI response'
                      : '${message.modelProvider} AI response',
                  icon: CupertinoIcons.check_mark_circled,
                ),
              ],
              if (!user &&
                  (message.evidence.isNotEmpty ||
                      message.missingData.isNotEmpty)) ...[
                const SizedBox(height: TracendSpacing.xs),
                EvidenceAccordion(
                  title: 'Evidence used and data gaps',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in message.evidence)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: TracendSpacing.xs,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['label'] as String,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Text(
                                item['source'] as String,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      if (message.missingData.isNotEmpty)
                        Text(
                          'Missing: ${message.missingData.join(', ')}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                    ],
                  ),
                ),
              ],
              if (!user && message.suggestedFollowUps.isNotEmpty) ...[
                const SizedBox(height: TracendSpacing.sm),
                Text(
                  'Suggested next actions',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: TracendSpacing.xxs),
                Wrap(
                  spacing: TracendSpacing.xs,
                  runSpacing: TracendSpacing.xs,
                  children: [
                    for (final prompt in message.suggestedFollowUps)
                      ActionChip(
                        label: Text(prompt),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        onPressed: () => onSendFollowUp?.call(prompt),
                      ),
                  ],
                ),
              ],
              if (diagnostic != null) ...[
                const SizedBox(height: TracendSpacing.sm),
                SelectableText(
                  [
                    'Beta diagnostic: ${diagnostic.failureCode}',
                    if (diagnostic.initialRule != null)
                      'first attempt: ${diagnostic.initialRule}',
                    if (diagnostic.repairRule != null)
                      'repair: ${diagnostic.repairRule}',
                  ].join(' · '),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: TracendSpacing.xs),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(CupertinoIcons.arrow_clockwise),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
