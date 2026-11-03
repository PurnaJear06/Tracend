import 'dart:async';

import 'package:tracend/features/feedback/feedback_rating.dart';

/// An in-memory [FeedbackRatingRepository]: ratings are kept as given, and
/// [failure] makes the next saves throw.
class FakeFeedbackRatings implements FeedbackRatingRepository {
  FakeFeedbackRatings({Map<String, FeedbackRating>? stored})
    : stored = {...?stored};

  final Map<String, FeedbackRating> stored;
  final saved = <(FeedbackSubject, String, FeedbackRating)>[];

  /// When set, the save waits for this before answering.
  Completer<void>? hold;

  /// Reading the rating of an id waits for its completer, when it has one.
  final loadHolds = <String, Completer<void>>{};

  /// When true, saving a rating throws.
  bool failure = false;

  @override
  Future<FeedbackRating?> loadRating(FeedbackSubject subject, String id) async {
    await loadHolds[id]?.future;
    return stored[id];
  }

  @override
  Future<void> rate(
    FeedbackSubject subject,
    String id,
    FeedbackRating rating,
  ) async {
    await hold?.future;
    if (failure) throw StateError('offline');
    saved.add((subject, id, rating));
    stored[id] = rating;
  }
}
