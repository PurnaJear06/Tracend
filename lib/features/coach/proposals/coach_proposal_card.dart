import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/coach/proposals/coach_proposal.dart';
import 'package:tracend/features/coach/proposals/coach_proposal_repository.dart';
import 'package:tracend/features/coach/proposals/proposal_notices.dart';
import 'package:tracend/shared/ai_provider_names.dart';
import 'package:tracend/shared/widgets/evidence_accordion.dart';
import 'package:tracend/shared/widgets/tracend_confirm.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';

/// A change Coach proposed, with the before and after the rules computed, the
/// reason, the downside and when it expires. Nothing is applied until the
/// athlete taps Approve. After approval an Undo stays for the undo window.
///
/// The card renders from a proposal the caller already has ([proposal]) or
/// loads one by id ([CoachProposalLoader]). The chat connects it to a message;
/// the card knows nothing about chat.
class CoachProposalCard extends StatefulWidget {
  const CoachProposalCard({
    required this.proposal,
    required this.repository,
    this.onPlanChanged,
    this.onChangeIt,
    this.origin,
    this.allowChange = true,
    super.key,
  });

  final CoachProposal proposal;
  final CoachProposalRepository repository;

  /// Who started the proposal; it sets the card's first line. Left out, the
  /// proposal says it itself: one that carries the rules' evidence is
  /// Tracend's, any other is Coach's.
  final CoachProposalOrigin? origin;

  /// Whether "Change it" is offered. It sends a follow-up message in the Coach
  /// chat, so a card shown outside the chat turns it off.
  final bool allowChange;

  /// A plan, nutrition target or goal version was written or restored, so the
  /// screens that show them should reload.
  final VoidCallback? onPlanChanged;

  /// The athlete tapped "Change it". The card has recorded the answer; the
  /// caller sends the follow-up message (see
  /// [CoachProposal.changeRequestMessage]).
  final ValueChanged<CoachProposal>? onChangeIt;

  @override
  State<CoachProposalCard> createState() => _CoachProposalCardState();
}

class _CoachProposalCardState extends State<CoachProposalCard> {
  late CoachProposal _proposal = widget.proposal;
  bool _busy = false;
  String? _error;
  String? _notice;

  CoachProposalOrigin get _origin =>
      widget.origin ??
      (_proposal.suggestedByRules
          ? CoachProposalOrigin.tracend
          : CoachProposalOrigin.coach);

  @override
  void didUpdateWidget(CoachProposalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.proposal.id != widget.proposal.id) {
      _proposal = widget.proposal;
      _error = null;
      _notice = null;
    }
  }

  Future<void> _approve() async {
    final confirmed = await showTracendActionSheet<bool>(
      context,
      title: 'Apply this change?',
      message: '${_proposal.title}. You can undo it for 7 days.',
      actions: const [
        TracendSheetAction(label: 'Approve', value: true, isDefault: true),
      ],
    );
    if (confirmed != true || !mounted) return;
    await _answer(CoachProposalAction.approve);
  }

  Future<void> _answer(CoachProposalAction action) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final answer = await widget.repository.respond(_proposal.id, action);
      if (!mounted) return;
      final status = switch (answer.status) {
        'accepted' => CoachProposalStatus.accepted,
        'declined' => CoachProposalStatus.declined,
        'changed' => CoachProposalStatus.changed,
        _ => CoachProposalStatus.expired,
      };
      if (status == CoachProposalStatus.expired &&
          action == CoachProposalAction.approve) {
        _notice = proposalStaleNotice(answer.reason, _origin);
      }
      await _refresh(status, answer);
      if (!mounted) return;
      if (answer.changedPlan) {
        unawaited(TracendHaptics.success());
        widget.onPlanChanged?.call();
      }
      if (status == CoachProposalStatus.changed) {
        widget.onChangeIt?.call(_proposal);
      }
    } on CoachProposalException catch (error) {
      if (!await _settledByServer(action) && mounted) {
        setState(() => _error = proposalErrorNotice(error, _origin));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo() async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final answer = await widget.repository.undo(_proposal.id);
      if (!mounted) return;
      if (answer.status == 'undone') {
        await _refresh(CoachProposalStatus.undone, answer);
        if (!mounted) return;
        unawaited(TracendHaptics.success());
        widget.onPlanChanged?.call();
      } else {
        // Later changes replaced it, or the window ended: nothing was restored.
        await _refresh(_proposal.status, answer);
        if (mounted) {
          setState(() {
            _notice = answer.status == 'superseded'
                ? 'A later change replaced this one, so it can no longer be undone from here.'
                : 'The undo window for this change has ended.';
          });
        }
      }
    } on CoachProposalException catch (error) {
      if (!await _settledByServer(null) && mounted) {
        setState(() => _error = proposalErrorNotice(error, _origin));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// After an error the answer may still have been written (the reply was
  /// lost, or a retry met a proposal that is already answered). Reads the
  /// proposal again: if it moved on, the card shows what the server holds,
  /// and the plan screens reload when it was applied or restored. True when
  /// there is nothing left to report as an error.
  Future<bool> _settledByServer(CoachProposalAction? action) async {
    final before = _proposal.status;
    final CoachProposal? fresh;
    try {
      final loaded = await widget.repository.load(id: _proposal.id);
      fresh = loaded.isEmpty ? null : loaded.first;
    } on CoachProposalException {
      return false;
    }
    if (fresh == null || !mounted) return false;
    setState(() => _proposal = fresh!);
    if (fresh.status == before) return false;
    switch (fresh.status) {
      case CoachProposalStatus.accepted || CoachProposalStatus.undone:
        unawaited(TracendHaptics.success());
        widget.onPlanChanged?.call();
        return true;
      case CoachProposalStatus.declined:
        return true;
      case CoachProposalStatus.changed:
        if (action == CoachProposalAction.change) {
          widget.onChangeIt?.call(fresh);
        }
        return true;
      case CoachProposalStatus.pending || CoachProposalStatus.expired:
        return false;
    }
  }

  /// Reads the proposal again so the card shows what the server now says (the
  /// undo window, whether undo is still possible); on a failed read the
  /// answer's own status stands.
  Future<void> _refresh(
    CoachProposalStatus fallback,
    CoachProposalAnswer answer,
  ) async {
    CoachProposal? fresh;
    try {
      final loaded = await widget.repository.load(id: _proposal.id);
      fresh = loaded.isEmpty ? null : loaded.first;
    } on CoachProposalException {
      fresh = null;
    }
    if (!mounted) return;
    setState(() {
      _proposal = fresh ?? _proposal.withStatus(fallback, answer.undoUntil);
    });
  }

  @override
  Widget build(BuildContext context) {
    final proposal = _proposal;
    final text = Theme.of(context).textTheme;
    final colors = context.tracendColors;
    final pending = proposal.status == CoachProposalStatus.pending;
    final showChange =
        pending || proposal.status == CoachProposalStatus.accepted;
    return TracendCard(
      raised: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: TracendSpacing.xs,
            runSpacing: TracendSpacing.xs,
            children: [
              StatusChip(
                label: switch (_origin) {
                  CoachProposalOrigin.coach =>
                    'Proposed by Coach · $aiProvenanceLine',
                  CoachProposalOrigin.tracend => 'Suggested by Tracend',
                },
                icon: CupertinoIcons.checkmark_shield,
              ),
              StatusChip(
                label: _statusLabel(proposal.status),
                icon: _statusIcon(proposal.status),
                tone: _statusTone(proposal.status),
              ),
            ],
          ),
          const SizedBox(height: TracendSpacing.sm),
          Semantics(
            header: true,
            child: Text(proposal.title, style: text.titleLarge),
          ),
          if (proposal.endsLine != null) ...[
            const SizedBox(height: TracendSpacing.xxs),
            Text(
              '${proposal.endsLine!}. Your regular plan comes back after.',
              style: text.bodySmall,
            ),
          ],
          const SizedBox(height: TracendSpacing.sm),
          Text(proposal.rationale, style: text.bodyMedium),
          if (showChange) ...[
            const SizedBox(height: TracendSpacing.md),
            _BeforeAfter(proposal: proposal),
          ],
          if (showChange) ...[
            const SizedBox(height: TracendSpacing.md),
            Text('Downside', style: text.labelLarge),
            const SizedBox(height: TracendSpacing.xxs),
            Text(proposal.downside, style: text.bodyMedium),
          ],
          if (proposal.evidence.isNotEmpty && pending) ...[
            const SizedBox(height: TracendSpacing.xs),
            EvidenceAccordion(
              title: 'What this is based on',
              compact: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in proposal.evidence)
                    Padding(
                      padding: const EdgeInsets.only(bottom: TracendSpacing.xs),
                      child: Text('• ${item.label}', style: text.bodySmall),
                    ),
                ],
              ),
            ),
          ],
          if (proposal.expiryLine != null) ...[
            const SizedBox(height: TracendSpacing.sm),
            Text(proposal.expiryLine!, style: text.bodySmall),
          ],
          if (proposal.status == CoachProposalStatus.accepted &&
              proposal.undoLine != null) ...[
            const SizedBox(height: TracendSpacing.sm),
            Text(proposal.undoLine!, style: text.bodySmall),
          ],
          if (_notice != null) ...[
            const SizedBox(height: TracendSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(_notice!, style: text.bodyMedium),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: TracendSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: text.bodyMedium?.copyWith(color: colors.stateDanger),
              ),
            ),
          ],
          if (pending) ...[
            const SizedBox(height: TracendSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _approve,
                child: const Text('Approve'),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _answer(CoachProposalAction.decline),
                    child: const Text('Not now'),
                  ),
                ),
                if (widget.allowChange) ...[
                  const SizedBox(width: TracendSpacing.xs),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _answer(CoachProposalAction.change),
                      child: const Text('Change it'),
                    ),
                  ),
                ],
              ],
            ),
          ] else if (proposal.canUndo) ...[
            const SizedBox(height: TracendSpacing.md),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _busy ? null : _undo,
                child: const Text('Undo'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _statusLabel(CoachProposalStatus status) => switch (status) {
    CoachProposalStatus.pending => 'Waiting for you',
    CoachProposalStatus.accepted => 'Applied',
    CoachProposalStatus.declined => 'Not now',
    CoachProposalStatus.changed => 'Change requested',
    CoachProposalStatus.expired => 'Expired',
    CoachProposalStatus.undone => 'Undone',
  };

  static IconData _statusIcon(CoachProposalStatus status) => switch (status) {
    CoachProposalStatus.pending => CupertinoIcons.hourglass,
    CoachProposalStatus.accepted => CupertinoIcons.checkmark_circle,
    CoachProposalStatus.undone => CupertinoIcons.arrow_uturn_left,
    _ => CupertinoIcons.xmark_circle,
  };

  static StatusTone _statusTone(CoachProposalStatus status) => switch (status) {
    CoachProposalStatus.pending => StatusTone.caution,
    CoachProposalStatus.accepted => StatusTone.good,
    _ => StatusTone.neutral,
  };
}

/// Before and after side by side: one line per value, then the sessions.
class _BeforeAfter extends StatelessWidget {
  const _BeforeAfter({required this.proposal});

  final CoachProposal proposal;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.tracendColors;
    final before = {for (final row in proposal.before.rows) row.label: row};
    final labels = [
      for (final row in proposal.after.rows) row.label,
      for (final row in proposal.before.rows)
        if (!proposal.after.rows.any((after) => after.label == row.label))
          row.label,
    ];
    final after = {for (final row in proposal.after.rows) row.label: row};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(flex: 3, child: Text('', style: text.labelMedium)),
            Expanded(flex: 4, child: Text('Now', style: text.labelMedium)),
            Expanded(flex: 4, child: Text('After', style: text.labelMedium)),
          ],
        ),
        for (final label in labels)
          Padding(
            padding: const EdgeInsets.only(top: TracendSpacing.xs),
            child: Semantics(
              container: true,
              label:
                  '$label: ${before[label]?.value ?? 'none'} now, '
                  '${after[label]?.value ?? 'none'} after',
              child: ExcludeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(label, style: text.bodySmall),
                    ),
                    Expanded(
                      flex: 4,
                      child: Text(
                        before[label]?.value ?? '—',
                        style: text.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Text(
                        after[label]?.value ?? '—',
                        style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (proposal.after.sessions.isNotEmpty) ...[
          const SizedBox(height: TracendSpacing.md),
          _Sessions(
            title: 'Your sessions now',
            sessions: proposal.before.sessions,
          ),
          const SizedBox(height: TracendSpacing.sm),
          _Sessions(
            title: 'Your sessions after',
            sessions: proposal.after.sessions,
          ),
        ],
      ],
    );
  }
}

class _Sessions extends StatelessWidget {
  const _Sessions({required this.title, required this.sessions});

  final String title;
  final List<ProposalSession> sessions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: text.labelLarge),
        for (final session in sessions)
          Padding(
            padding: const EdgeInsets.only(top: TracendSpacing.xxs),
            child: Text(session.line, style: text.bodySmall),
          ),
      ],
    );
  }
}

/// Loads a proposal by id and shows its card, for a caller that has only the
/// id (a chat message that carries one).
class CoachProposalLoader extends StatefulWidget {
  const CoachProposalLoader({
    required this.proposalId,
    required this.repository,
    this.onPlanChanged,
    this.onChangeIt,
    this.origin,
    this.allowChange = true,
    super.key,
  });

  final String proposalId;
  final CoachProposalRepository repository;
  final VoidCallback? onPlanChanged;
  final ValueChanged<CoachProposal>? onChangeIt;
  final CoachProposalOrigin? origin;
  final bool allowChange;

  @override
  State<CoachProposalLoader> createState() => _CoachProposalLoaderState();
}

class _CoachProposalLoaderState extends State<CoachProposalLoader> {
  late Future<CoachProposal?> _proposal = _load();

  Future<CoachProposal?> _load() async {
    final loaded = await widget.repository.load(id: widget.proposalId);
    return loaded.isEmpty ? null : loaded.first;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CoachProposal?>(
    future: _proposal,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const TracendCard(
          child: SizedBox(
            height: 48,
            child: Center(child: CupertinoActivityIndicator()),
          ),
        );
      }
      final proposal = snapshot.data;
      if (snapshot.hasError || proposal == null) {
        return TracendCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This proposal could not be loaded.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _proposal = _load();
                  });
                },
                child: const Text('Try again'),
              ),
            ],
          ),
        );
      }
      return CoachProposalCard(
        proposal: proposal,
        repository: widget.repository,
        onPlanChanged: widget.onPlanChanged,
        onChangeIt: widget.onChangeIt,
        origin: widget.origin,
        allowChange: widget.allowChange,
      );
    },
  );
}
