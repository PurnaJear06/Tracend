import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';

/// What is being rated: the daily decision (`coach_decisions.id`) or a Coach
/// reply (`coach_messages.id`).
enum FeedbackSubject {
  dailyDecision('daily_decision'),
  coachReply('coach_reply');

  const FeedbackSubject(this.wire);

  /// The value `submit_feedback_rating_v1` and `feedback_ratings` use.
  final String wire;
}

/// The four one-tap answers (PRD §5.6). The name is the stored value.
enum FeedbackRating {
  useful('Useful'),
  unclear('Unclear'),
  incorrect('Incorrect'),
  unsafe('Unsafe');

  const FeedbackRating(this.label);

  final String label;
}

/// Reads and writes the athlete's rating of a decision or a reply. Only the
/// live repository has it; a screen shows the rating controls when its
/// repository is one.
abstract interface class FeedbackRatingRepository {
  /// The athlete's current rating of the subject, or null when none.
  Future<FeedbackRating?> loadRating(FeedbackSubject subject, String id);

  /// Rates the subject; a second rating replaces the first. Throws when the
  /// rating was not saved.
  Future<void> rate(FeedbackSubject subject, String id, FeedbackRating rating);
}

/// A small row of four one-tap choices under a daily decision or a Coach
/// reply: useful, unclear, incorrect or unsafe. The choice shows at once and
/// is taken back, with a message, if it could not be saved. Tapping another
/// choice replaces the rating.
class FeedbackRatingBar extends StatefulWidget {
  const FeedbackRatingBar({
    required this.repository,
    required this.subject,
    required this.subjectId,
    super.key,
  });

  final FeedbackRatingRepository repository;
  final FeedbackSubject subject;
  final String subjectId;

  @override
  State<FeedbackRatingBar> createState() => _FeedbackRatingBarState();
}

class _FeedbackRatingBarState extends State<FeedbackRatingBar> {
  FeedbackRating? _rating;
  bool _failed = false;

  /// Taps are answered in order: a rating that is still being saved is not
  /// overwritten by a late answer from the first read.
  var _taps = 0;

  String get _noun => switch (widget.subject) {
    FeedbackSubject.dailyDecision => 'daily decision',
    FeedbackSubject.coachReply => 'reply',
  };

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(FeedbackRatingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subjectId != widget.subjectId ||
        oldWidget.subject != widget.subject) {
      _rating = null;
      _failed = false;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final taps = _taps;
    try {
      final stored = await widget.repository.loadRating(
        widget.subject,
        widget.subjectId,
      );
      if (mounted && taps == _taps) setState(() => _rating = stored);
    } catch (e) {
      logNonCritical(e, 'rating not read');
    }
  }

  Future<void> _rate(FeedbackRating rating) async {
    final before = _rating;
    if (before == rating) return;
    final tap = ++_taps;
    unawaited(TracendHaptics.selection());
    setState(() {
      _rating = rating;
      _failed = false;
    });
    try {
      await widget.repository.rate(widget.subject, widget.subjectId, rating);
    } catch (e) {
      logNonCritical(e, 'rating not saved');
      if (mounted && tap == _taps) {
        setState(() {
          _rating = before;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    final textTheme = Theme.of(context).textTheme;
    final caption = _failed
        ? 'Could not save your rating. Check your connection and tap again.'
        : _rating == null
        ? 'How was this?'
        : 'Thanks. Tap another answer to change it.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: _failed,
          child: Text(
            caption,
            style: textTheme.labelSmall?.copyWith(
              color: _failed ? colors.stateDanger : colors.textSecondary,
            ),
          ),
        ),
        Wrap(
          spacing: TracendSpacing.xxs,
          children: [
            for (final rating in FeedbackRating.values)
              _RatingChip(
                label: rating.label,
                semanticLabel: 'Rate this $_noun ${rating.label.toLowerCase()}',
                selected: _rating == rating,
                onTap: () => _rate(rating),
              ),
          ],
        ),
      ],
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String semanticLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tracendColors;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Center(
            widthFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected ? colors.accentSignal : colors.surfaceRaised,
                borderRadius: BorderRadius.circular(TracendRadii.pill),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TracendSpacing.sm,
                  vertical: TracendSpacing.xxs,
                ),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected
                        ? colors.onAccentSignal
                        : colors.textPrimary,
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
