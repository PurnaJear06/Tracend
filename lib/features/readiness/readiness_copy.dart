import 'package:tracend/features/readiness/day_adjustment.dart';
import 'package:tracend/features/readiness/day_adjustment_repository.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/today/widgets/recovery_readout_card.dart';

/// Every word of the same-day adjustment card, in one place so one test can
/// read all of it (UX_FLOWS.md §5, §7). Tracend's rules write the reasons; no
/// model or company is named (D11), and nothing here names a condition.

const readinessProvenance =
    'Calculated by Tracend from your check-in and Apple Health. No AI.';
const readinessOnlyToday = 'Only today changes. Your plan stays the same.';

const readinessKicker = "Today's readiness";
const trainAsPlanned = 'Train as planned';
const talkToCoach = 'Talk to Coach';
const checkInLabel = 'Check in';
const undoLabel = 'Undo';
const changeLabel = 'Change';
const otherOptionsLabel = 'Other options';
const chooseYourselfLabel = 'Or choose for yourself';
const seesTitle = 'What Tracend sees';
const optionsSheetTitle = "Change today's session";
const optionsSheetSubtitle = 'Only today changes. Your plan stays the same.';

String kindTitle(DayAdjustmentKind kind) => switch (kind) {
  DayAdjustmentKind.holdLoad => 'Hold your weights today',
  DayAdjustmentKind.reduceSets => 'One set fewer today',
  DayAdjustmentKind.swapToEasyCardio => 'Easy cardio instead today',
  DayAdjustmentKind.jointAdjust => 'Easier on your joints today',
};

/// The primary button when the rules propose [kind].
String kindAcceptLabel(DayAdjustmentKind kind) => switch (kind) {
  DayAdjustmentKind.holdLoad => 'Hold weights',
  DayAdjustmentKind.reduceSets => 'Use lighter session',
  DayAdjustmentKind.swapToEasyCardio => 'Swap to easy cardio',
  DayAdjustmentKind.jointAdjust => 'Use these changes',
};

/// A choice in a list the athlete picks from.
String kindChoiceLabel(DayAdjustmentKind kind) => switch (kind) {
  DayAdjustmentKind.holdLoad => 'Hold your weights',
  DayAdjustmentKind.reduceSets => 'One set fewer',
  DayAdjustmentKind.swapToEasyCardio => 'Easy cardio instead',
  DayAdjustmentKind.jointAdjust => 'Changes for your joints',
};

/// "holding your weights": [kind] inside a sentence.
String kindPhrase(DayAdjustmentKind kind) => switch (kind) {
  DayAdjustmentKind.holdLoad => 'holding your weights',
  DayAdjustmentKind.reduceSets => 'a lighter session',
  DayAdjustmentKind.swapToEasyCardio => 'easy cardio',
  DayAdjustmentKind.jointAdjust => 'changes for my joints',
};

/// "fewer sets": [kind] in brackets, for an earlier answer said in words only.
String kindShort(DayAdjustmentKind kind) => switch (kind) {
  DayAdjustmentKind.holdLoad => 'weights held',
  DayAdjustmentKind.reduceSets => 'fewer sets',
  DayAdjustmentKind.swapToEasyCardio => 'easy cardio',
  DayAdjustmentKind.jointAdjust => 'joint changes',
};

/// The title once [kind] is accepted and can still be changed.
String kindAppliedTitle(DayAdjustmentKind kind) => switch (kind) {
  DayAdjustmentKind.holdLoad => 'Weights held for today.',
  DayAdjustmentKind.reduceSets => 'Lighter session set for today.',
  DayAdjustmentKind.swapToEasyCardio => 'Easy cardio set for today.',
  DayAdjustmentKind.jointAdjust => 'Joint changes set for today.',
};

/// The title of an accepted answer once the session started: read only.
String kindBegunTitle(DayAdjustmentKind kind) => switch (kind) {
  DayAdjustmentKind.holdLoad => 'Weights held today',
  DayAdjustmentKind.reduceSets => 'Lighter session today',
  DayAdjustmentKind.swapToEasyCardio => 'Easy cardio chosen today',
  DayAdjustmentKind.jointAdjust => 'Joint changes today',
};

const declinedTitle = 'Training as planned today.';
const declinedBody =
    'You chose to train as planned. You can change that until you start.';

String begunBody(DayAdjustment adjustment) =>
    adjustment.unavailableReason == 'session_done'
    ? 'You trained with this change. It stays as it was.'
    : 'Your session started with this change, so it cannot be changed now.';

String appliedBody(DayAdjustment adjustment) {
  final cut =
      adjustment.kind == DayAdjustmentKind.reduceSets &&
          adjustment.setsTotalTo < adjustment.setsTotalFrom
      ? ' ${adjustment.setsTotalFrom} sets become ${adjustment.setsTotalTo}.'
      : '';
  return '${adjustment.explanation}$cut You can undo this until you start.';
}

const lowRecoveryTitle = 'Your recovery reads low';
const coachAdjustedTitle = 'Coach adjusted today';
const undoneToast = 'Back to your plan.';

/// Said under the card when the last read failed and what shows is older.
const staleLine = 'Could not refresh. This is what loaded earlier.';

String? painNote(DayAdjustment adjustment) =>
    adjustment.triggers.contains('pain_mild')
    ? 'Keep any pain at 3 or below, and stop if it builds from set to set.'
    : null;

/// How sure Tracend is of today's call. Null when it rated nothing, as on a
/// day without a check-in.
String? confidenceLine(String? confidence) => switch (confidence) {
  'high' => 'Confidence: high.',
  'medium' => 'Confidence: medium.',
  'low' => 'Confidence: low.',
  _ => null,
};

/// What the earlier answer was, when it no longer stands today. The server
/// keeps an accepted answer in force until the athlete answers again, so the
/// line says so.
String previousAnswerLine(PreviousDayAnswer previous) {
  final why = switch (previous.reason) {
    'check_in' => 'Your check-in changed',
    'new_data' => 'New sleep or recovery data came in',
    _ => 'Things changed since you answered',
  };
  final kind = previous.kind;
  if (previous.status == DayAdjustmentStatus.accepted && kind != null) {
    return '$why. Your earlier choice (${kindShort(kind)}) still applies until '
        'you choose again.';
  }
  if (previous.status == DayAdjustmentStatus.declined) {
    return '$why, so Tracend looked again. You had chosen to train as '
        'planned.';
  }
  return '$why, so Tracend looked again.';
}

/// Why an answer or a read did not go through, in words for the card.
String failureLine(DayAdjustmentFailure failure) => switch (failure) {
  DayAdjustmentFailure.wrongDate =>
    "Your phone's date and your Tracend day do not match, so today's check is "
        'not shown. Pull down to try again.',
  DayAdjustmentFailure.refused =>
    'That change is not available now. The card shows what is true today.',
  DayAdjustmentFailure.unavailable =>
    "Today's session has started or is done, so it cannot be changed now.",
  DayAdjustmentFailure.tooMany =>
    'You have changed this many times today. Try again tomorrow.',
  DayAdjustmentFailure.unreadable =>
    'Tracend sent a check this version cannot read. Update the app to see it.',
  DayAdjustmentFailure.network =>
    'Could not reach Tracend. Check your connection and try again.',
};

const readFailureLine =
    "Today's readiness check could not load. Pull down to try again.";

/// "5 h 40 min" for a night of sleep.
String sleepText(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest min';
  return rest == 0 ? '$hours h' : '$hours h $rest min';
}

String _confidenceWord(String? value) => switch (value) {
  'high' => 'high confidence',
  'medium' => 'medium confidence',
  'low' => 'low confidence',
  _ => 'confidence not rated',
};

/// What Tracend sees, as plain lines: the recovery score with its confidence,
/// HRV and resting heart rate against the athlete's usual (from [computed]
/// when the brief carries them), and last night's sleep. Whatever is missing
/// is said to be missing; nothing is filled in.
List<String> seenLines(DayAdjustment adjustment, ComputedMetrics? computed) {
  final signals = adjustment.signals;
  final lines = <String>[];
  final score = signals.recoveryScore;
  if (score == null) {
    lines.add('Recovery score: not available yet');
  } else {
    final mode = signals.recoveryMode == 'morning'
        ? ', an estimate from this morning'
        : '';
    lines.add(
      'Recovery score: $score of 100, '
      '${_confidenceWord(signals.recoveryConfidence)}$mode',
    );
  }
  final breakdown = computed?.scores.recoveryBreakdown;
  if (breakdown != null) {
    final drivers = recoveryDrivers(
      breakdown: breakdown,
      todayRaw: computed?.todayRaw,
      sleepQualityProven: computed?.scores.sleepQuality != null,
      mode: computed?.scores.recoveryMode,
    );
    for (final driver in drivers) {
      if ((driver.key == 'hrv_sdnn' || driver.key == 'resting_hr') &&
          driver.usable) {
        lines.add('${driver.label}: ${driver.detail}');
      }
    }
  }
  final sleep = signals.sleepMinutes;
  if (sleep != null && sleep > 0 && sleep <= 960) {
    lines.add('Sleep: ${sleepText(sleep)}');
  } else {
    lines.add('Sleep: not in from Apple Health yet');
  }
  return lines;
}

/// Said plainly under a proposal that rests on less than the whole picture.
String? basisLine(DayAdjustment adjustment) {
  final missing = adjustment.missing;
  final both = missing.contains('sleep') && missing.contains('recovery');
  if (both) {
    return 'Apple Health sleep and recovery are not in yet, so this rests on '
        'your check-in alone.';
  }
  if (missing.contains('sleep')) {
    return "Last night's sleep is not in from Apple Health yet, so this "
        'leaves it out.';
  }
  if (missing.contains('recovery')) {
    return "Today's recovery score is not available yet, so this leaves it "
        'out.';
  }
  return null;
}

/// The question Talk to Coach puts in the box. The athlete sends it, or
/// changes it first; nothing is sent for them.
String coachQuestion(DayAdjustment adjustment) {
  final kind = adjustment.kind;
  if (kind == DayAdjustmentKind.jointAdjust &&
      (adjustment.status == DayAdjustmentStatus.proposed ||
          adjustment.isAccepted)) {
    return "Tracend changed today's session for my sore joints. Can we talk "
        'about whether that makes sense?';
  }
  if (adjustment.status == DayAdjustmentStatus.proposed && kind != null) {
    return 'Tracend suggests ${kindPhrase(kind)} for today because of how I '
        'feel and sleep. Can we talk it through before I decide?';
  }
  if (adjustment.isAccepted && kind != null) {
    return "I chose ${kindPhrase(kind)} for today's session. Does that make "
        'sense for how I am doing?';
  }
  if (adjustment.signals.recoveryLow) {
    return 'My recovery reads low today. Should I change my session, and what '
        'would you change?';
  }
  return "Can we talk about whether to change today's session?";
}
