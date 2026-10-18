import 'package:tracend/features/coach/memory/coach_memory.dart';

/// What a Coach suggestion asks of the athlete.
enum CoachFactSuggestionAction {
  /// Something new to remember.
  add,

  /// Replace a saved fact with what the athlete said now.
  update,

  /// The saved fact no longer applies (an injury has healed): delete it.
  resolve,

  /// The message may not match a saved fact (an allergy). Nothing is offered
  /// to save; the athlete is told so and can change the fact in Account.
  review,

  /// A saved fact that is due to be asked about again and that the athlete
  /// has just spoken of: "is it still true?".
  reconfirm;

  static CoachFactSuggestionAction? fromWire(Object? wire) {
    for (final action in values) {
      if (action.name == wire) return action;
    }
    return null;
  }
}

/// A fact Coach suggests, shown under its reply as a card. Nothing is saved
/// until the athlete taps Confirm (Architecture 2 and 3).
class CoachFactSuggestion {
  const CoachFactSuggestion({
    required this.action,
    required this.kind,
    required this.subject,
    required this.statement,
    required this.reason,
    this.factId,
    this.previous,
  });

  /// One entry of the `fact_suggestions` the coach-chat response carries.
  /// Returns null for an entry this build cannot read.
  static CoachFactSuggestion? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final action = CoachFactSuggestionAction.fromWire(json['action']);
    final kind = CoachFactKind.fromWire(json['kind']);
    final subject = json['subject'];
    final statement = json['statement'];
    final reason = json['reason'];
    if (action == null ||
        kind == null ||
        subject is! String ||
        statement is! String ||
        reason is! String) {
      return null;
    }
    final factId = json['fact_id'];
    if (action != CoachFactSuggestionAction.add && factId is! String) {
      return null;
    }
    return CoachFactSuggestion(
      action: action,
      kind: kind,
      subject: subject,
      statement: statement,
      reason: reason,
      factId: factId is String ? factId : null,
      previous: json['previous'] is String ? json['previous'] as String : null,
    );
  }

  /// The suggestions in a coach-chat response body, skipping unreadable ones.
  static List<CoachFactSuggestion> listFromResponse(
    Map<String, dynamic>? body,
  ) {
    final raw = body?['fact_suggestions'];
    if (raw is! List) return const [];
    return [for (final item in raw) ?tryFromJson(item)];
  }

  final CoachFactSuggestionAction action;
  final CoachFactKind kind;
  final String subject;
  final String statement;
  final String reason;

  /// The saved fact an update replaces, a resolve deletes or a review is about.
  final String? factId;

  /// That fact's words, to show before and after.
  final String? previous;
}
