import 'package:tracend/features/readiness/day_adjustment.dart';

/// Every word of the pain check and its referrals, in one place so one test
/// can read all of it (UX_FLOWS.md §5, §6, §7). Fixed sentences written by
/// Tracend's rules; no model or company is named (D11), nothing here names a
/// condition or prescribes rehab, and heart rate has no part in it.

/// The sheet shown for a day with a safety route: no training choice.
typedef SafetyWords = ({String title, String body});

const SafetyWords _urgentWords = (
  title: 'Get medical help now',
  body:
      'What you described needs urgent care. Call your local emergency '
      'number or go to an emergency department now. Tracend will not '
      "suggest any training until you've been seen.",
);

/// A route this build does not know (a later server version) is read as the
/// strictest one, so a referral is never softened by an old build.
SafetyWords safetyWords(String route) => switch (route) {
  'pain_referral' => (
    title: "Don't train through this pain",
    body:
        'Pain of 7 or more is too high to train through. Rest the area and '
        'see a doctor or physio before you train it again. Get seen today if '
        "it's sharp, getting worse, or you can't move it.",
  ),
  'urgent' => _urgentWords,
  'clinician_today' => (
    title: 'Get this checked today',
    body:
        'Please see a doctor or physio today, before you train this area '
        'again. Tracend leaves training aside for today.',
  ),
  'clinician' => (
    title: 'See a doctor or physio',
    body:
        'Please book a doctor or physio before you train this area again. '
        'Tracend leaves training aside for today.',
  ),
  _ => _urgentWords,
};

/// The two routes that must be acknowledged before the athlete goes on: the
/// sheet for them cannot be swiped or tapped away. An unknown route counts,
/// because it reads as the strictest.
bool routeNeedsAcknowledgement(String route) =>
    route != 'pain_referral' && route != 'clinician';

/// How strict a route is; one this build does not know is the strictest.
int _routeRank(String route) => switch (route) {
  'urgent' => 4,
  'clinician_today' => 3,
  'pain_referral' => 2,
  'clinician' => 1,
  _ => 5,
};

/// The stricter of two routes, either of which may be absent.
String? stricterRoute(String? a, String? b) {
  if (a == null) return b;
  if (b == null) return a;
  return _routeRank(b) > _routeRank(a) ? b : a;
}

const gotItLabel = 'Got it';

// The areas ------------------------------------------------------------------

/// The area as a person says it: "knee", "lower back".
String areaWord(PainArea area) => switch (area) {
  PainArea.knee => 'knee',
  PainArea.back => 'lower back',
  PainArea.shoulder => 'shoulder',
  PainArea.other => 'pain you reported elsewhere',
};

/// "Your knee", "Your lower back"; the elsewhere area has no body part.
String areaYour(PainArea area) => switch (area) {
  PainArea.other => 'The pain you reported elsewhere',
  _ => 'Your ${areaWord(area)}',
};

/// The area as a choice in the pain check.
String areaChoice(PainArea area) => switch (area) {
  PainArea.knee => 'Knee',
  PainArea.back => 'Lower back',
  PainArea.shoulder => 'Shoulder',
  PainArea.other => 'Somewhere else',
};

// What a joint changes today -----------------------------------------------

/// "Your knee is resting until you have been seen."
String jointStateLine(JointState state) {
  final your = areaYour(state.area);
  return switch (state.state) {
    JointStateKind.held => '$your is resting until you have been seen.',
    JointStateKind.limited => '$your needs a lighter touch this week.',
    JointStateKind.watch => '$your is on watch.',
  };
}

/// The reminder for an area held on a "see a doctor or physio" outcome: said
/// on every day the area stays held, whether or not an exercise changes.
String holdReminderLine(JointState state) =>
    "${areaYour(state.area)} is on hold until you've had it checked.";

String persistentLine(JointState state) => switch (state.area) {
  PainArea.other =>
    'Your pain has lasted two weeks. Please see a physio or doctor.',
  _ =>
    'Your ${areaWord(state.area)} pain has lasted two weeks. Please see a '
        'physio or doctor.',
};

/// Said once under a swap: the new exercise carries no starting weight.
const swapLoadLine =
    'Choose a weight you can lift for the reps with 3 or more left.';

/// The pain-free range cue for [code] (`range_note_code`). A code this build
/// does not know gets the general cue, so a limit is never shown empty.
String rangeNoteText(String code) => switch (code) {
  'knee_squat_depth' =>
    'Squat only as deep as stays pain-free. A box or bench behind you marks '
        'the depth.',
  'knee_lunge_depth' =>
    'Take shorter steps and go only as low as stays pain-free.',
  'knee_extension_partial' =>
    'Use the part of the movement that stays pain-free.',
  'back_hinge_range' =>
    'Lower only as far as you can keep your back flat and pain-free, about '
        'knee height.',
  'back_squat_depth' => 'Stop above the depth where your back rounds or hurts.',
  'back_core_neutral' =>
    'Skip moves that bend or twist your spine if they hurt; hold still '
        'instead.',
  'back_press_seated' => 'Press seated with your back supported if you can.',
  'shoulder_press_height' =>
    'Press only as high as stays pain-free. Neutral-grip dumbbells can help.',
  'shoulder_press_depth' => 'Lower only as far as stays pain-free.',
  'shoulder_fly_stretch' => 'Keep the stretch short of where it hurts.',
  'shoulder_pull_range' =>
    'Pull in front of you, never behind the neck, and stop the hang short of '
        'pain.',
  'shoulder_raise_height' => 'Raise to just below shoulder height.',
  _ => genericRangeNote,
};

const genericRangeNote =
    'Use a range that stays pain-free and stop if the pain builds set to set.';

/// The range cues of an exercise, each said once.
List<String> rangeNoteLines(Iterable<String> codes) => [
  for (final text in {for (final code in codes) rangeNoteText(code)}) text,
];

const leftOutLine = 'Left out today';

/// What one joint change does, in words: "Barbell bench press: use Machine
/// chest press instead." Null for a change no joint touches.
String? jointChangeLine(DayAdjustmentChange change) =>
    switch (change.jointAction) {
      JointAction.swap => '${change.name}: use ${change.swapToName} instead.',
      JointAction.limit =>
        '${change.name}: ${rangeNoteLines(change.rangeNoteCodes).join(' ')}',
      JointAction.drop => '${change.name} is left out today.',
      null => null,
    };

/// The lines the day card gives for the joints, each said once: the
/// reminder for an area held on a "see a doctor or physio" outcome and the
/// two-week line. Anything the server's sentence already says is left out, so
/// a card that prints that sentence does not repeat it.
List<String> jointReminderLines(
  DayAdjustment adjustment, {
  bool explanationShown = false,
}) {
  final said = explanationShown ? adjustment.explanation : '';
  final lines = <String>[];
  for (final state in adjustment.jointStates) {
    if (state.isReminderHold && !said.contains(holdReminderLine(state))) {
      lines.add(holdReminderLine(state));
    }
  }
  if (!said.contains('lasted two weeks')) {
    for (final state in adjustment.jointStates) {
      if (state.persistent &&
          (state.state == JointStateKind.limited ||
              state.state == JointStateKind.held)) {
        lines.add(persistentLine(state));
      }
    }
  }
  return lines;
}

// The pain check in the check-in -----------------------------------------------

const painWhereTitle = 'Where is it?';
const painWhereRequired = 'Choose where the pain is to save.';
const painWhenTitle = 'When does it hurt?';
const painWhenMove = 'Only when I move or train it';
const painWhenRest = 'Even at rest';
const redFlagsTitle = 'Do any of these apply?';
const redFlagsNone = 'None of these';
const redFlagsRequired = 'Choose any that apply, or None of these.';
const painStrengthRequired = 'Choose how strong the pain is to save.';

const followUpGone = 'Gone';
const followUpStillThere = 'Still there';
const followUpYes = 'Yes';
const followUpNotYet = 'Not yet';
const followUpStrengthRequired = 'Choose how strong it is now to save.';

String followUpTitle(PainArea area) => switch (area) {
  PainArea.other => 'Last time you noted pain somewhere else. How is it today?',
  _ => 'Last time you noted ${areaWord(area)} pain. How is it today?',
};

String clearedTitle(PainArea area) => switch (area) {
  PainArea.other =>
    'Has a doctor or physio cleared you to train after the pain you '
        'reported elsewhere?',
  _ => 'Has a doctor or physio cleared you to train your ${areaWord(area)}?',
};

const followUpStrengthTitle = 'How strong is it now, from 0 to 10?';
const followUpStrengthHint = '0 is gone, 10 is the worst you can imagine.';

// Sending and waiting ------------------------------------------------------

const painQueuedToast =
    'Saved on this phone. Your pain report has not reached Tracend yet.';

const painWaitingTitle = 'Your pain report is waiting to be sent';
const painWaitingBody =
    'It is saved on this phone but has not reached Tracend. Open Tracend '
    'with a connection today or tomorrow: after that Tracend cannot record '
    'it.';

const painNotSentTitle = 'A pain report could not be recorded';
const painNotSentBody =
    'It was more than a day old, so Tracend did not record it. If the pain '
    'is still there, report it again in a check-in. If you answered yes to '
    'any of the questions about it, please see a doctor or physio.';
const painReportAgain = 'Report it again';
const painTryAgain = 'Try again';
const painDismissNotSent = 'I understand';

// The pain chip during a workout -----------------------------------------------

const chipTitle = 'Pain or discomfort';
const chipWhereTitle = 'Where?';
const chipStrengthTitle = 'How strong right now?';
const chipSharpTitle = 'Was it sharp or sudden, or did you feel a pop?';
const chipNumbTitle = 'Any numbness or tingling?';
const chipYes = 'Yes';
const chipNo = 'No';
const chipSave = 'Check this exercise';
const chipRequired = 'Answer each question to continue.';

const chipStopTitle = 'Stop this exercise';
const chipStopBody =
    "Don't train through it. See a doctor or physio before you train this "
    'area again.';
const chipSkipExercise = 'Skip this exercise';
const chipEndWorkout = 'End workout';

const chipSwapTitle = 'Stop this exercise for today';
String chipSwapBody(String? swap) => swap == null
    ? 'Skip it for today.'
    : 'Try $swap instead, in a range that stays pain-free.';
String chipUseSwap(String swap) => 'Use $swap';

const chipLightTitle = 'Keep it light';
const chipLightBody =
    "Keep going only if it stays at 3 or below and doesn't build from set to "
    'set.';
const chipContinue = 'Continue';

const chipQueued =
    'Saved on this phone. It will go to Tracend when you are online, and it '
    'must be sent today or tomorrow.';
const chipNotRecorded =
    'Tracend could not record this report. If the pain is still there, '
    'report it again in a check-in.';
const chipNoteLine = 'Pain noted';

// Red-flag questions -------------------------------------------------------

/// The plain question for a red-flag [code]. The closed list is the
/// database's; a code that is not on it has no question.
String? redFlagQuestion(String code) => _redFlagQuestions[code];

const _redFlagQuestions = {
  'bladder_bowel_saddle':
      'New trouble controlling your bladder or bowels, or numbness around '
      'your groin or inner thighs',
  'chest_or_breath':
      'The pain came with chest pain, pressure or shortness of breath',
  'numb_weak_limb': 'Numbness, tingling or weakness in an arm or leg',
  'pop_or_sudden': 'It started with a pop, a tear or a sudden sharp pain',
  'cannot_bear_or_move': "You can't put weight on it or can't move it normally",
  'rapid_swelling': 'It swelled up quickly',
  'dislocated_or_cannot_lift':
      "It felt like it slipped out of place, or you can't lift your arm",
  'locks_gives_way': 'The knee locks or gives way',
  'fever_unwell': 'You have a fever or feel unwell with it',
  'night_pain':
      "It wakes you at night and doesn't ease when you change position",
};
