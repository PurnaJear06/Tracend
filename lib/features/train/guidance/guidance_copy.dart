import 'package:tracend/features/train/guidance/training_guidance.dart';
import 'package:tracend/features/train/guidance/training_guidance_repository.dart';
import 'package:tracend/shared/formatting.dart';

/// Every word of the lighter-week card and the cardio row, in one place so one
/// test can read all of it (UX_FLOWS.md §7). Tracend's rules write the reasons;
/// no model or company is named (D11), nothing names a condition, and heart
/// rate never decides anything here.

// -- Lighter week -------------------------------------------------------------

const deloadSuggestedBy = 'Suggested by Tracend';
const deloadTitle = 'A lighter week could help';
const deloadSeeChanges = 'See what changes';
const deloadProvenance =
    'Calculated by Tracend from your logged sessions and check-ins. No AI.';
const deloadNothingChanges = 'Nothing changes until you approve it.';

/// What a lighter week is, in one sentence.
const deloadWhat =
    'The same sessions on the same days with half the sets, your weights held '
    'and effort at 7 or lower. Your regular plan comes back after the week.';

/// One reason, in the athlete's own terms.
String deloadReasonLine(DeloadReason reason) => switch (reason) {
  DeloadReason.performanceDrop =>
    'Two or more of your lifts have stalled or slipped.',
  DeloadReason.runDown =>
    'Your readiness has read low on four or more of the days you checked in '
        'this past week.',
  DeloadReason.blockDone => "You've trained most of a full block of training.",
};

const deloadPendingBody =
    'Tracend prepared a lighter week for you to look at. It waits for your '
    'answer.';

/// A lighter week the athlete asked Coach for, waiting for an answer. The rules
/// did not suggest it, so the card claims none of their reasons.
const deloadCoachTitle = 'A lighter week from Coach';
const deloadCoachPendingBody =
    'Coach prepared a lighter week for you to look at. It waits for your '
    'answer.';

const deloadRunningTitle = 'A lighter week is on';
const deloadRunningBody =
    'Half the sets, your weights held, effort at 7 or lower. Your regular plan '
    'comes back by itself after the week.';

/// "A lighter week is on until Fri 31 Oct", or without the day when the server
/// did not name it.
String deloadRunningTitleFor(DateTime? endsOn) => endsOn == null
    ? deloadRunningTitle
    : '$deloadRunningTitle until ${dayAndDate(endsOn)}';
const deloadRunningAction = 'Details and undo';

const deloadSheetTitle = 'A lighter week';

/// Why the server turned a lighter week down, in Tracend's own words: the
/// server's are Coach's, in the first person.
String deloadRefusalLine(String? code) => switch (code) {
  'screening_see_professional' =>
    'Your health check says a health professional should clear you before '
        'Tracend changes your plan.',
  'no_active_plan' => 'There is no active plan to lighten yet.',
  'block_already_active' =>
    'Another change is already running, so a lighter week cannot start now.',
  'no_change' => 'Your plan is already at that effort.',
  'profile_incomplete' =>
    'Tracend needs your profile finished before it can prepare a lighter '
        'week.',
  'plan_changed' || 'screening_changed' || 'evidence_changed' =>
    'Your plan or health check changed just now. Pull down to refresh and '
        'look again.',
  _ => 'A lighter week cannot be prepared right now.',
};

const deloadOtherProposalLine =
    'You have a change waiting in Coach. Answer it first.';

String deloadFailureLine(
  TrainingGuidanceFailure failure, {
  String? code,
}) => switch (failure) {
  TrainingGuidanceFailure.wrongDate =>
    'Your day changed while this was open. Pull down to refresh.',
  TrainingGuidanceFailure.notSuggested =>
    'A lighter week is not suggested right now. Nothing was changed.',
  TrainingGuidanceFailure.otherProposalPending => deloadOtherProposalLine,
  TrainingGuidanceFailure.refused => deloadRefusalLine(code),
  TrainingGuidanceFailure.unreadable =>
    'Tracend sent something this version cannot read. Update the app and try '
        'again.',
  TrainingGuidanceFailure.network =>
    'Could not reach Tracend. Check your connection and try again.',
};

// -- Cardio this week ---------------------------------------------------------

const cardioTitle = 'Cardio this week';
const cardioNoDataValue = 'Not enough Apple Health data';
const cardioNoDataTitle = 'Not enough data yet';
const cardioNoDataBody =
    'Tracend counts your cardio from Apple Health once at least 5 of the last '
    '7 days have data. Connect Apple Health and wear your watch, and the '
    'minutes show here. Until then nothing is counted, and no number is '
    'guessed.';
const cardioPermissionNote =
    'If Apple Health workout access is off for Tracend, your cardio can read '
    'as 0 minutes even when you did some. You can change it in Settings, '
    'Health, Data Access.';
const cardioAllModerate =
    'Every minute counts as moderate, because a workout record does not say '
    'how hard it was.';
const cardioProvenance =
    'Calculated by Tracend from your Apple Health workouts. No AI.';
const cardioEasyTalk = 'Easy means you can talk in full sentences.';
const cardioHardTitle = 'Hard cardio today';
const cardioEasyOnlyTitle = 'Easy cardio only today';
const cardioEasyOnlyIntro = 'Hard cardio opens when all of these are true:';
const cardioEasyOnlyConditions = [
  'Your health check allows it.',
  "Today's readiness reads green, which needs today's check-in.",
  'You can train today.',
  'No joint is held or limited.',
];
const cardioGuideline =
    'The health guideline is 150 minutes of moderate cardio a week.';

/// The row on Train's "This week" card.
String cardioRowValue(CardioWeek week) {
  final done = week.doneMin;
  if (done == null) return cardioNoDataValue;
  return '$done of ${week.targetMin} min';
}

/// The state of the week against the guideline, in a sentence.
String cardioStandingLine(CardioWeek week) {
  final done = week.doneMin;
  if (done == null) return cardioNoDataTitle;
  if (done >= week.targetMin) return 'You have reached the weekly guideline.';
  return '${week.targetMin - done} min to go to reach the weekly guideline.';
}

/// "Last 7 days, to Sat 24 Oct", when the server named the window.
String? cardioWindowLine(CardioWeek week) {
  final to = week.windowTo;
  return to == null ? null : 'Last 7 days, to ${dayAndDate(to)}';
}

/// What the stretch figure means, for the goals that carry one.
String? cardioStretchLine(CardioWeek week) {
  final stretch = week.stretchMax;
  if (stretch == null) return null;
  return 'For fat loss or recomposition you can build toward $stretch minutes.';
}

/// Hard cardio, when it is open today.
String cardioHardOpenLine(CardioWeek week) {
  final sessions = week.vigorousSessionsMax;
  return 'Up to $sessions hard '
      '${sessions == 1 ? 'session' : 'sessions'} a week. Each hard minute '
      'counts as ${week.vigorousCountsAs}. Leave about '
      '${week.liftSeparationHours} hours between hard cardio and lifting.';
}

/// The easy ceiling as a guide, never a rule.
String? cardioEasyGuideLine(CardioWeek week) {
  final reserve = week.easyHrReserveMax;
  return reserve == null
      ? null
      : 'As a guide, easy stays below about $reserve% of your heart rate '
            'reserve.';
}
