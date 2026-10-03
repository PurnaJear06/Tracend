import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/coach_labels.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/widgets/coach_reply_text.dart';
import 'package:tracend/features/coach/widgets/reasoning_chain_card.dart';
import 'package:tracend/shared/widgets/evidence_accordion.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// One Coach message (plan §6.2).
///
/// The athlete's own message is a filled `surfaceRaised` bubble on the right,
/// shown exactly as typed. A Coach reply is borderless text on the canvas.
///
/// Binding contract:
/// - a Coach reply renders its Markdown subset through [CoachReplyText]
/// - evidence rows = `CoachMessage.evidence` (label + source, display-only)
/// - data gaps = `CoachMessage.missingData`, in words ([coachGapLabel])
/// - suggested prompts ONLY from `CoachMessage.suggestedFollowUps`
/// - the provider label comes from `CoachMessage.modelProvider` through the
///   display-name map ([aiAnswerLabel]), never a raw id
/// - reasoning from `CoachMessage.reasoningChain` (structured data only,
///   never hidden model chain-of-thought), without its evidence ids
/// - a data summary (`CoachMessage.isDataSummary`) is labeled as not an AI
///   answer, never carries the provider label, and shows the beta diagnostic
///   when the live response included one. A safety referral
///   (`CoachMessage.isSafetyReferral`) is labeled as a safety note.
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

  /// The disclosure under a reply that cites evidence, reports data gaps or
  /// returns reasoning steps.
  static const evidenceTitle = 'Evidence used and data gaps';

  @override
  Widget build(BuildContext context) => message.role == 'user'
      ? _UserBubble(text: message.content)
      : _CoachReply(
          message: message,
          onSendFollowUp: onSendFollowUp,
          onRetry: onRetry,
        );
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.centerRight,
        child: Semantics(
          label: 'You said',
          child: ConstrainedBox(
            constraints: BoxConstraints(
              // Large text gets more of the line, so a question does not
              // break into one word per line.
              maxWidth:
                  (constraints.maxWidth *
                          (MediaQuery.textScalerOf(context).scale(10) > 15
                              ? 0.94
                              : 0.85))
                      .clamp(0, 560),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceRaised,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: SelectableText(
                  text,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colors.textPrimary,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CoachReply extends StatelessWidget {
  const _CoachReply({
    required this.message,
    required this.onSendFollowUp,
    required this.onRetry,
  });

  final CoachMessage message;
  final void Function(String prompt)? onSendFollowUp;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final summary = message.isDataSummary;
    final referral = message.isSafetyReferral;
    final diagnostic = summary ? message.diagnostic : null;
    final diagnosticLine = diagnostic == null
        ? null
        : CoachDiagnosticLine(betaDiagnosticText(diagnostic));
    final reasoning = ReasoningSteps.visible(message.reasoningChain);
    final hasDisclosure =
        message.evidence.isNotEmpty ||
        message.missingData.isNotEmpty ||
        reasoning.isNotEmpty;
    final provider = !summary ? message.modelProvider : null;
    return Semantics(
      container: true,
      label: referral
          ? 'Safety note'
          : summary
          ? 'Data summary'
          : 'Coach said',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (summary) ...[
            StatusChip(
              label: referral
                  ? 'Safety note · not an AI answer'
                  : 'Data summary · not an AI answer',
              icon: referral ? CupertinoIcons.heart : CupertinoIcons.doc_text,
              tone: referral ? StatusTone.neutral : StatusTone.caution,
            ),
            const SizedBox(height: TracendSpacing.sm),
          ],
          CoachReplyText(
            message.content,
            style: textTheme.bodyLarge!.copyWith(
              color: colors.textPrimary,
              height: 1.45,
            ),
          ),
          if (provider != null) ...[
            const SizedBox(height: TracendSpacing.xs),
            Text(
              aiAnswerLabel(provider),
              style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
          if (hasDisclosure) ...[
            const SizedBox(height: TracendSpacing.xxs),
            EvidenceAccordion(
              title: CoachMessageBubble.evidenceTitle,
              compact: true,
              child: _EvidenceBody(
                message: message,
                reasoning: reasoning,
                diagnostic: diagnosticLine,
              ),
            ),
          ] else if (diagnosticLine != null) ...[
            const SizedBox(height: TracendSpacing.xs),
            diagnosticLine,
          ],
          if (message.suggestedFollowUps.isNotEmpty) ...[
            const SizedBox(height: TracendSpacing.sm),
            Semantics(
              header: true,
              child: Text(
                'Suggested next actions',
                style: textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: TracendSpacing.xxs),
            // Padded chips already keep 8pt between rows.
            Wrap(
              spacing: TracendSpacing.xs,
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
          if (onRetry != null) ...[
            const SizedBox(height: TracendSpacing.xs),
            CoachRetryButton(onPressed: onRetry),
          ],
        ],
      ),
    );
  }
}

/// The evidence disclosure's content: cited evidence, data gaps in words,
/// the reasoning steps, then the beta diagnostic when the reply has one.
class _EvidenceBody extends StatelessWidget {
  const _EvidenceBody({
    required this.message,
    required this.reasoning,
    required this.diagnostic,
  });

  final CoachMessage message;
  final List<Map<String, dynamic>> reasoning;
  final Widget? diagnostic;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final sections = <Widget>[
      if (message.evidence.isNotEmpty)
        _Section(
          title: 'Evidence',
          children: [
            for (final item in message.evidence)
              MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['label'] as String? ?? '',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (item['source'] is String)
                      Text(
                        coachEvidenceSourceLabel(item['source'] as String),
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      if (message.missingData.isNotEmpty)
        _Section(
          title: 'Data gaps',
          children: [
            for (final gap in message.missingData)
              MergeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        CupertinoIcons.minus_circle,
                        size: 16,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: TracendSpacing.sm),
                    Expanded(
                      child: Text(
                        coachGapLabel(gap),
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      if (reasoning.isNotEmpty)
        _Section(
          title: 'How the Coach reasoned',
          children: [ReasoningSteps(chain: reasoning)],
        ),
      ?diagnostic,
    ];
    return Padding(
      padding: const EdgeInsets.only(
        top: TracendSpacing.xxs,
        bottom: TracendSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, section) in sections.indexed) ...[
            if (index > 0) const SizedBox(height: TracendSpacing.md),
            section,
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (final child in children) ...[
          const SizedBox(height: TracendSpacing.xs),
          child,
        ],
      ],
    );
  }
}

/// "Beta diagnostic: provider_response_invalid · first attempt: … · repair:
/// …": why the model did not answer, kept visible for the private beta.
String betaDiagnosticText(CoachChatDiagnostic diagnostic) => [
  'Beta diagnostic: ${diagnostic.failureCode}',
  if (diagnostic.initialRule != null)
    'first attempt: ${diagnostic.initialRule}',
  if (diagnostic.repairRule != null) 'repair: ${diagnostic.repairRule}',
].join(' · ');

/// A raw beta diagnostic as one small, selectable secondary line (owner
/// rule: the raw text stays visible during the private beta).
class CoachDiagnosticLine extends StatelessWidget {
  const CoachDiagnosticLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => SelectableText(
    text,
    style: Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: context.tracendColors.textSecondary),
  );
}

/// The quiet Retry action under a reply or a failed turn.
class CoachRetryButton extends StatelessWidget {
  const CoachRetryButton({required this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: TracendSpacing.sm),
    ),
    icon: const Icon(CupertinoIcons.arrow_clockwise, size: 18),
    label: const Text('Retry'),
  );
}

/// A turn that failed, shown in place of the Coach's reply under the
/// question it answers: what happened in plain words, then the raw beta
/// diagnostic as a small second line, and Retry when it can be asked again.
class CoachTurnError extends StatelessWidget {
  const CoachTurnError({
    required this.message,
    this.diagnostic,
    this.onRetry,
    super.key,
  });

  final String message;
  final String? diagnostic;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MergeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  CupertinoIcons.exclamationmark_circle,
                  size: 18,
                  color: colors.stateAttention,
                ),
              ),
              const SizedBox(width: TracendSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    if (diagnostic != null) ...[
                      const SizedBox(height: 2),
                      CoachDiagnosticLine(diagnostic!),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: TracendSpacing.xxs),
          CoachRetryButton(onPressed: onRetry),
        ],
      ],
    );
  }
}
