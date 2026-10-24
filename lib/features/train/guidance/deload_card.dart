import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/proposals/coach_proposal_card.dart';
import 'package:tracend/features/coach/proposals/coach_proposal_repository.dart';
import 'package:tracend/features/train/guidance/guidance_copy.dart';
import 'package:tracend/features/train/guidance/training_guidance.dart';
import 'package:tracend/features/train/guidance/training_guidance_controller.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';

/// "A lighter week could help" (owner decision O7). Tracend's rules suggest a
/// lighter week from the athlete's own data; the card says why, and one tap
/// shows what would change. The athlete then approves or declines through the
/// same proposal card as Coach's proposals, with Undo for seven days. Nothing
/// is applied by the card, by opening it, or by the rules.
///
/// The card is shown for a `suggested` or `pending` lighter week and, so Undo
/// stays within reach, for a `running` one. On a day with a safety route, for
/// a status this build cannot read, and in every other state it is not there.
class DeloadCard extends StatefulWidget {
  const DeloadCard({
    required this.controller,
    required this.proposals,
    this.onPlanChanged,
    super.key,
  });

  final TrainingGuidanceController controller;

  /// Reads and answers the lighter week's proposal.
  final CoachProposalRepository proposals;

  /// A plan version was written or restored, so the screens that show the plan
  /// should reload.
  final VoidCallback? onPlanChanged;

  @override
  State<DeloadCard> createState() => _DeloadCardState();
}

class _DeloadCardState extends State<DeloadCard> {
  TrainingGuidanceController get _controller => widget.controller;

  Future<void> _open(DeloadCardState state, DeloadGuidance deload) async {
    // A suggestion has no proposal yet: preparing one stores it for the
    // athlete to answer. An open or running one is read as it is.
    final id = state == DeloadCardState.suggested
        ? await _controller.prepareDeload()
        : deload.proposalId;
    if (id == null || !mounted) return;
    await showTracendSheet<void>(
      context,
      title: deloadSheetTitle,
      builder: (_) => Padding(
        padding: const EdgeInsets.only(bottom: TracendSpacing.lg),
        child: CoachProposalLoader(
          proposalId: id,
          repository: widget.proposals,
          origin: CoachProposalOrigin.tracend,
          allowChange: false,
          onPlanChanged: widget.onPlanChanged,
        ),
      ),
    );
    // The answer may have moved the lighter week on; show what is true.
    if (mounted) unawaited(_controller.load());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final guidance = _controller.current;
      final state = deloadCardState(guidance);
      if (state == DeloadCardState.hidden) return const SizedBox.shrink();
      return _Panel(child: _content(context, guidance!, state));
    },
  );

  Widget _content(
    BuildContext context,
    TrainingGuidance guidance,
    DeloadCardState state,
  ) {
    final deload = guidance.deload!;
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final running = state == DeloadCardState.running;
    final preparing = _controller.preparing;
    final failure = _controller.prepareFailure;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: StatusChip(
            label: deloadSuggestedBy,
            icon: CupertinoIcons.checkmark_shield,
            tone: running ? StatusTone.good : StatusTone.neutral,
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          header: true,
          child: Text(
            running ? deloadRunningTitle : deloadTitle,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 4),
        if (running)
          Text(
            deloadRunningBody,
            style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          )
        else ...[
          for (final reason in deload.reasons)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• ${deloadReasonLine(reason)}',
                style: textTheme.bodyMedium,
              ),
            ),
          if (state == DeloadCardState.pending)
            Padding(
              padding: EdgeInsets.only(top: deload.reasons.isEmpty ? 0 : 6),
              child: Text(
                deloadPendingBody,
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            )
          else ...[
            const SizedBox(height: 6),
            Text(
              deloadWhat,
              style: textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: TracendSpacing.xs),
          _Line(deloadProvenance),
          _Line(deloadNothingChanges),
        ],
        if (failure != null) ...[
          const SizedBox(height: TracendSpacing.xs),
          Semantics(
            liveRegion: true,
            child: _Line(
              deloadFailureLine(failure, reason: _controller.prepareReason),
              color: colors.stateDanger,
            ),
          ),
        ],
        const SizedBox(height: TracendSpacing.sm),
        if (running)
          OutlinedButton(
            onPressed: () => _open(state, deload),
            child: const Text(deloadRunningAction),
          )
        else
          FilledButton(
            onPressed: preparing ? null : () => _open(state, deload),
            child: preparing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CupertinoActivityIndicator(),
                  )
                : const Text(deloadSeeChanges),
          ),
      ],
    );
  }
}

/// The card's panel, with the gap that separates it from what follows.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: TracendSpacing.sm),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(TracendSpacing.sm),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(TracendRadii.control + 4),
        ),
        child: child,
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: color ?? context.tracendColors.textSecondary,
      ),
    ),
  );
}
