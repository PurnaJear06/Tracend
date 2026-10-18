import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import type { CoachChatAnswerBreak } from "../contracts/coach_chat_v1.ts";
import type { ScreeningState } from "../coach_context/contributors/screening.ts";
import { weightClaimCheckFor } from "../training/goal_phase/guard.ts";
import { numberGroundOf } from "./numbers_check.ts";
import { coachReplyCheck, cutReply } from "./reply_guard.ts";
import { ownerContext, ownerGoalPhasePayload } from "./fixtures.ts";
import { safeRangesOf } from "./safe_ranges.ts";
import { renderCoachContextParts } from "../providers/coach_chat_provider.ts";
import { renderGoalPhasePayload } from "../coach_context/contributors/goal_phase.ts";

const context = ownerContext();
const file = renderCoachContextParts(context, 96_000).file;
const goalPhase = renderGoalPhasePayload(ownerGoalPhasePayload, "2026-10-14")!;

function check(
  answer: string,
  options: {
    screening?: ScreeningState;
    question?: string;
    painEscalated?: boolean;
    /** The text shown for each library source, by id. */
    library?: Readonly<Record<string, string>>;
    /** The library sources the reply's evidence cites. */
    cited?: readonly string[];
    /** The coaching principles digest, which grounds general figures but not the athlete's own. */
    digest?: string;
  } = {},
) {
  const question = options.question ?? "What should I do?";
  const result = coachReplyCheck({
    ranges: { ...safeRangesOf(context), painEscalated: options.painEscalated ?? false },
    screening: options.screening ?? "cleared",
    ground: numberGroundOf([
      file,
      goalPhase,
      question,
      ...(options.digest ? [options.digest] : []),
    ]),
    athleteGround: numberGroundOf([file, goalPhase, question]),
    librarySources: options.library,
    weightClaim: weightClaimCheckFor(context, question),
  })(answer, options.cited);
  return result as CoachChatAnswerBreak | null;
}

const broken = (answer: string, options?: Parameters<typeof check>[1]) =>
  check(answer, options)?.rules ?? [];

Deno.test("an honest reply from the data passes every rule", () => {
  assertEquals(
    check(
      "You've lost 11.8 kg since 2026-07-04, and your pace is -0.62 kg/week. **Keep your calories near 2000 kcal** and log your meals. Want to set a target on Progress?",
    ),
    null,
  );
});

Deno.test("calories_below_floor: advising a daily intake under the floor", () => {
  // The floor for this athlete is 1719 kcal (his resting energy; the sex minimum is 1500).
  assertEquals(safeRangesOf(context).calorieFloorKcal, 1719);
  for (
    const reply of [
      "Drop to 1,400 calories a day and you'll lose faster.",
      "I'd eat 1,200 kcal a day for the next month.",
      "Aim for 1,300-1,500 kcal daily.",
      "You should go down to 1500 kcal.",
      "Try keeping it at 1,600 calories each day.",
    ]
  ) {
    assert(broken(reply).includes("calories_below_floor"), reply);
  }
  for (
    const reply of [
      "Never go below 1,719 kcal a day.",
      "Eating 1,200 kcal a day is too low for you.",
      "Your target is 2000 kcal.",
      "Cut 300 kcal from your day if the scale stalls.",
      "A 400 kcal snack before training is fine.",
      "You burn about 600 kcal in a session.",
      "Keep dinner near 700 calories.",
      "Aim for 1,800 kcal a day.",
      "The floor is 1,719 kcal, so don't drop to 1,500 calories a day.",
    ]
  ) {
    assert(!broken(reply).includes("calories_below_floor"), reply);
  }
});

Deno.test("loss_rate_above_ceiling: advising a loss faster than 1% of body weight a week", () => {
  // 1% of 74.4 kg is 0.744 kg.
  for (
    const reply of [
      "Aim to lose 1 kg a week.",
      "You could try for 1.5% a week.",
      "Push for 2 lb per week.",
      "You should lose 6 kg in 4 weeks.",
      "Target 0.9-1.2 kg per week.",
    ]
  ) {
    assert(broken(reply).includes("loss_rate_above_ceiling"), reply);
  }
  for (
    const reply of [
      "Aim for about 0.5 kg a week.",
      "Aim for 0.7 kg per week, the ceiling is 0.74 kg.",
      "Losing more than 1 kg a week is too fast.",
      "You've been losing 0.9 kg a week, so slow down.",
      "Your pace over the last 4 weeks is 1.2 kg/week.",
      "Aim for 1% of body weight a week at most.",
    ]
  ) {
    assert(!broken(reply).includes("loss_rate_above_ceiling"), reply);
  }
});

Deno.test("effort_above_screening_cap: no vigorous effort until the health check clears", () => {
  for (const screening of ["moderate_until_cleared", "see_professional"] as const) {
    for (
      const reply of [
        "Finish with a few sprints.",
        "Go to failure on the last set.",
        "Try a heavy single at RPE 9.",
        "Add HIIT intervals twice a week.",
        "Push harder today, you have this.",
      ]
    ) {
      assert(broken(reply, { screening }).includes("effort_above_screening_cap"), reply);
    }
  }
  for (
    const reply of [
      "Keep the effort moderate: no sets to failure.",
      "Avoid sprints until a doctor clears you.",
      "Stay at a moderate pace and keep 3 reps in reserve.",
      "I won't suggest intervals until you have clearance.",
    ]
  ) {
    assert(
      !broken(reply, { screening: "moderate_until_cleared" }).includes(
        "effort_above_screening_cap",
      ),
      reply,
    );
  }
  assertEquals(broken("Finish with a few sprints.", { screening: "cleared" }), []);
});

Deno.test("claimed_action: Coach has no tools and says so", () => {
  for (
    const reply of [
      "I've updated your plan for next week.",
      "I lowered your calories to match.",
      "Done. Your target is now saved.",
      "Your plan has been updated.",
      "I'll set a reminder for you.",
      "Let me adjust that for you.",
      "I can change your calories for you.",
      "I will log that meal now.",
      "I have scheduled a deload.",
      "It's done!",
    ]
  ) {
    assert(broken(reply).includes("claimed_action"), reply);
  }
  for (
    const reply of [
      "You can change this in Progress, Set your target.",
      "I'd suggest lowering your calories only if the scale stalls.",
      "Want me to explain how to update your plan?",
      "I can explain why the trend moved.",
      "The plan is set for 6 sessions a week.",
      "I noted your sleep was short, so keep today easy.",
      "If you set a target, I can compare your pace with it.",
    ]
  ) {
    assert(!broken(reply).includes("claimed_action"), reply);
  }
});

Deno.test("numbers_not_grounded carries the figures for the repair and a safe count for the log", () => {
  const result = check("That is roughly 71.5 kg in 4 weeks and 66.5 kg in 12 weeks.", {
    question: "What now?",
  })!;
  assertEquals(result.rule, "projection_without_target");
  assert(result.rules!.includes("numbers_not_grounded"));
  assertEquals(result.detail, "71.5, 66.5, 12");
  const onlyNumbers = check("You might walk 45 minutes a day.")!;
  assertEquals(onlyNumbers.rule, "numbers_not_grounded");
  assertEquals(onlyNumbers.count, 1);
  assertEquals(onlyNumbers.detail, "45");
});

Deno.test("every broken rule is reported together, the goal phase rule first", () => {
  const result = check(
    "I've updated your plan: drop to 1,200 kcal a day and lose 1.5 kg a week, ending at 66.5 kg in 12 weeks.",
  )!;
  assertEquals(result.rule, "projection_without_target");
  assertEquals(result.rules, [
    "projection_without_target",
    "calories_below_floor",
    "loss_rate_above_ceiling",
    "claimed_action",
    "numbers_not_grounded",
  ]);
});

Deno.test("calories_below_floor: only a real warning is exempt, parsed for direction", () => {
  const flagged = [
    "Set your minimum to 900 kcal a day.",
    "Your floor can be 1,000 calories a day, so drop to it.",
    "Skip dinner and drop to 900 calories.",
    "Reduce dinner to 400 kcal and eat 1,000 kcal a day.",
    "Don't skip meals; drop to 1,200 calories a day.",
    "A good minimum is to eat 1,100 kcal a day.",
    "Never mind the scale, eat 1,300 kcal a day for a month.",
    "The floor is a guide, so go down to 1,000 kcal.",
    "Breakfast is optional; try 1,200 kcal a day total.",
  ];
  for (const reply of flagged) {
    assert(broken(reply).includes("calories_below_floor"), reply);
  }
  const warnings = [
    "Don't go below 1,500 kcal a day.",
    "Never under 1,200 calories.",
    "You should not eat less than 1,000 kcal a day.",
    "1,200 kcal a day is too low for you.",
    "Eating 1,200 kcal a day isn't safe.",
    "A 400 kcal snack is fine.",
    "Reduce dinner to 400 kcal.",
    "You burn 600 kcal in a session.",
    "Please avoid dropping under 1,400 calories a day.",
  ];
  for (const reply of warnings) {
    assert(!broken(reply).includes("calories_below_floor"), reply);
  }
});

Deno.test("effort_above_screening_cap: moderate-until-cleared keeps HIIT, sprints and intervals out", () => {
  for (
    const reply of [
      "Keep HIIT moderate.",
      "Do HIIT intervals at a moderate pace.",
      "Add a few moderate sprints.",
      "Use a limited number of intervals.",
    ]
  ) {
    assert(
      broken(reply, { screening: "moderate_until_cleared" }).includes("effort_above_screening_cap"),
      reply,
    );
  }
  for (
    const reply of [
      "No HIIT until a doctor clears you.",
      "Avoid sprints and intervals for now.",
      "Keep the effort moderate and finish every set with 3 reps in reserve.",
      "Skip HIIT for now.",
    ]
  ) {
    assert(
      !broken(reply, { screening: "moderate_until_cleared" }).includes(
        "effort_above_screening_cap",
      ),
      reply,
    );
  }
  assertEquals(broken("Do 3 sets of 8 reps.", { screening: "moderate_until_cleared" }), []);
});

Deno.test("effort_above_screening_cap: see_professional blocks every training prescription", () => {
  for (
    const reply of [
      "Do 3 sets of 8 reps.",
      "Try 3x10 squats.",
      "Squat 60 kg for 5 reps.",
      "Walk 30 minutes a day.",
      "Follow this 3-day split.",
      "Add a full-body workout twice a week.",
      "Aim for 8,000 steps a day.",
      "Start with 20 minutes of easy cardio.",
      "Keep HIIT moderate.",
      "Do some RPE 6 work.",
      "Try a push, pull, legs routine.",
      "Train three times a week.",
      "Finish with planks and lunges.",
    ]
  ) {
    assert(
      broken(reply, { screening: "see_professional" }).includes("effort_above_screening_cap"),
      reply,
    );
  }
  for (
    const reply of [
      "I can't give you sets or reps until a professional clears you.",
      "Please see a doctor before any training.",
      "Tracend builds a plan once your health check allows it.",
      "You can ask me about sleep and food.",
      "No workouts or cardio targets until you are cleared.",
      "Don't train until a doctor clears you.",
      "A doctor can tell you how much exercise is safe.",
    ]
  ) {
    assert(
      !broken(reply, { screening: "see_professional" }).includes("effort_above_screening_cap"),
      reply,
    );
  }
});

Deno.test("an unknown screening is treated as moderate_until_cleared, never as cleared", () => {
  assert(
    broken("Finish with sprints.", { screening: "unknown" }).includes("effort_above_screening_cap"),
  );
  assert(
    broken("Keep HIIT moderate.", { screening: "unknown" }).includes("effort_above_screening_cap"),
  );
  assertEquals(broken("Do 3 sets of 8 reps.", { screening: "unknown" }), []);
});

Deno.test("training_advice_on_pain_day: no training prescription on a day of check-in pain of 7 or more", () => {
  for (
    const reply of [
      "Do 3 sets of 8 reps today.",
      "Try an easy 20 minutes of cardio.",
      "Keep HIIT moderate.",
      "Go for a 30 minute walk.",
    ]
  ) {
    assert(broken(reply, { painEscalated: true }).includes("training_advice_on_pain_day"), reply);
    assert(!broken(reply).includes("training_advice_on_pain_day"), reply);
  }
  for (
    const reply of [
      "Please don't train today; rest and see a doctor or physio.",
      "Eat around 2000 kcal and sleep well.",
    ]
  ) {
    assert(!broken(reply, { painEscalated: true }).includes("training_advice_on_pain_day"), reply);
  }
});

Deno.test("citation_not_retrieved: a source id in the text that Coach was not shown", () => {
  const library = { schoenfeld_2017_weekly_volume: "Weekly sets." };
  assertEquals(
    broken("Ten sets a week is a sound target [made_up_2019_claim].", { library }),
    ["citation_not_retrieved"],
  );
  // With nothing retrieved, any printed id is a citation of nothing.
  assertEquals(broken("Ten sets a week is a sound target [schoenfeld_2017_weekly_volume]."), [
    "citation_not_retrieved",
  ]);
  assertEquals(
    broken("Ten sets a week is a sound target [schoenfeld_2017_weekly_volume].", { library }),
    [],
  );
  assertEquals(broken("Ten sets a week is a sound target.", { library }), []);
});

const guideline = {
  jager_2017_protein: "People who train need 1.4 to 2.0 grams of protein per kilogram.",
};

Deno.test("a figure only a library source holds is accepted when the reply cites that source", () => {
  const reply = "The position stand puts it at about 1.4 to 2.0 g of protein per kg a day.";
  assertEquals(broken(reply, { library: guideline, cited: ["jager_2017_protein"] }), []);
  // Not cited, or cited another source that does not hold it: the figure is ungrounded.
  assertEquals(broken(reply, { library: guideline }), ["numbers_not_grounded"]);
  assertEquals(
    broken(reply, {
      library: { ...guideline, other_2020_source: "Sleep for 7 hours." },
      cited: ["other_2020_source"],
    }),
    ["numbers_not_grounded"],
  );
  assertEquals(broken(reply), ["numbers_not_grounded"]);
});

Deno.test("a library figure never becomes the athlete's own target", () => {
  const cited = ["jager_2017_protein"];
  for (
    const reply of [
      "Your protein target is 1.4 to 2.0 g per kg a day.",
      "You should eat 1.4 to 2.0 g of protein per kg a day.",
      "Aim for 2.0 g of protein per kg.",
      "Cut 1.4 g of protein per kg a day.",
    ]
  ) {
    assertEquals(broken(reply, { library: guideline, cited }), ["numbers_not_grounded"], reply);
  }
  // The same figure as the source's guidance, next to a target that comes from the athlete's data.
  assertEquals(
    broken(
      "The position stand puts it at 1.4 to 2.0 g of protein per kg a day. Your calorie target stays at 2000 kcal.",
      { library: guideline, cited },
    ),
    [],
  );
});

Deno.test("the principles digest grounds general guidance but not a sentence about the athlete's target", () => {
  const digest = "Most people who train do well on 1.6 g of protein per kg a day.";
  assertEquals(
    broken("Guidance for people who train is about 1.6 g of protein per kg a day.", { digest }),
    [],
  );
  assertEquals(
    broken("Your protein target is 1.6 g per kg a day.", { digest }),
    ["numbers_not_grounded"],
  );
  assertEquals(broken("You should eat 1.6 g of protein per kg a day.", { digest }), [
    "numbers_not_grounded",
  ]);
  // A figure from the athlete's data is fine in a target sentence.
  assertEquals(broken("Your calorie target is 2000 kcal.", { digest }), []);
});

// ---- citations by name, repeats and cuts ------------------------------------------------------

const kreiderLibrary = {
  maughan_2018_ioc_supplements:
    "[source: maughan_2018_ioc_supplements] Creatine at 3 to 5 g a day is well studied. Athletes who train hard may use it.",
};

function inputsFor(extra: Partial<Parameters<typeof coachReplyCheck>[0]> = {}) {
  const question = "What should I do?";
  return {
    ranges: { ...safeRangesOf(context), painEscalated: false },
    screening: "cleared" as ScreeningState,
    ground: numberGroundOf([file, goalPhase, question]),
    athleteGround: numberGroundOf([file, goalPhase, question]),
    weightClaim: weightClaimCheckFor(context, question),
    librarySources: kreiderLibrary,
    libraryLabels: { maughan_2018_ioc_supplements: "IOC consensus statement (2018)" },
    ...extra,
  };
}

Deno.test("citation_not_retrieved: a study named by authors and year that was not shown", () => {
  const run = (answer: string, extra = {}) =>
    ((coachReplyCheck(inputsFor(extra))(answer, [], answer)) as CoachChatAnswerBreak | null)
      ?.rules ?? [];
  assertEquals(run("Kreider 2017 found creatine helps."), ["citation_not_retrieved"]);
  assertEquals(run("The WHO guidelines say to move more."), ["citation_not_retrieved"]);
  assertEquals(run("Creatine is well studied."), []);
  // Shown, or named by the athlete, or a date and not a study.
  assertEquals(run("Maughan 2018 found creatine helps."), []);
  assertEquals(
    run("Kreider 2017 found creatine helps.", { athleteText: ["What does Kreider say?"] }),
    [],
  );
  assertEquals(run("Since 2018 you have trained a lot."), []);
});

Deno.test("repeats_previous_turn: the closing question of the previous reply, asked again", () => {
  const repetition = {
    previousReply: "Sleep was fine. Want me to suggest two easy ways to close the protein gap?",
    referralNeeded: false,
  };
  const run = (answer: string) =>
    ((coachReplyCheck(inputsFor({ repetition }))(answer, [], answer)) as
      | CoachChatAnswerBreak
      | null)?.rules ?? [];
  assertEquals(
    run("Training is on track. Should I suggest two simple ways to close your protein gap?"),
    ["repeats_previous_turn"],
  );
  assertEquals(run("Training is on track. Do you want to move leg day to Friday?"), []);
  assertEquals(
    coachReplyCheck(inputsFor())(
      "Training is on track. Should I suggest two simple ways to close your protein gap?",
    ),
    null,
  );
});

Deno.test("a cut removes the sentences at fault and nothing else", () => {
  const cut = (answer: string, rules: Parameters<typeof cutReply>[2]) =>
    cutReply(inputsFor(), {
      answer,
      evidence: [],
      missing_data: [],
      safety_state: "allowed",
      suggested_follow_ups: ["Walk 37 minutes?", "Show my week"],
      reasoning_chain: [],
    }, rules);
  const plan =
    "Here is your plan:\n1. Walk 20 min after dinner.\n2. Squat 61.5 kg x 8 today.\n3. Sleep early.\nThat keeps the week simple and realistic for travel.";
  const result = cut(plan, ["numbers_not_grounded"])!;
  assertEquals(
    result.answer.answer,
    "Here is your plan:\n1. Walk 20 min after dinner.\n3. Sleep early.\nThat keeps the week simple and realistic for travel.",
  );
  assertEquals(result.answer.suggested_follow_ups, ["Show my week"]);
  assertEquals(result.answer.missing_data, [
    "Left out lines with figures that are not in your data.",
  ]);
  assertEquals(result.cuts, ["numbers_stripped"]);
  // A lead-in left with nothing under it goes too, and a reply with too little left is not cut.
  assertEquals(
    cut("Here is your plan:\n1. Squat 61.5 kg x 8 today.", ["numbers_not_grounded"]),
    null,
  );
  // A rule that is not about particular sentences is never cut.
  assertEquals(cut(plan, ["numbers_not_grounded", "claimed_action"]), null);
  assertEquals(cut(plan, ["calories_below_floor"]), null);
});

Deno.test("a cut keeps the missing-data notes within the contract and rebuilds library labels", () => {
  const base = {
    evidence: [],
    missing_data: Array.from({ length: 12 }, (_, index) => `Note ${"abcdefghijkl"[index]}`),
    safety_state: "allowed",
    suggested_follow_ups: [],
    reasoning_chain: [],
  };
  const plan =
    "Here is your plan:\n1. Walk for 20 min after dinner.\n2. Squat 61.5 kg x 8 today.\n3. Sleep early.\nThat keeps the week simple and realistic for travel.";
  const crowded = cutReply(inputsFor(), { ...base, answer: plan }, ["numbers_not_grounded"])!;
  const notes = crowded.answer.missing_data as string[];
  assertEquals(notes.length, 12);
  assertEquals(notes.at(-1), "Left out lines with figures that are not in your data.");
  assertEquals(notes[0], "Note a");

  // The model's wording of a library label (a figure, an unshown study) is replaced by the title
  // and year of the retrieved source, and the citation stays.
  const labelled = cutReply(inputsFor(), {
    ...base,
    missing_data: [],
    answer: plan,
    evidence: [{
      code: "maughan_2018_ioc_supplements",
      label: "Kreider 2017 says 61.5 kg",
      source: "library",
    }],
  }, ["numbers_not_grounded"])!;
  assertEquals(labelled.answer.evidence, [{
    code: "maughan_2018_ioc_supplements",
    label: "IOC consensus statement (2018)",
    source: "library",
  }]);
  // A fault only in a label is mended, and says so.
  const onlyLabel = cutReply(inputsFor(), {
    ...base,
    missing_data: [],
    answer: "Creatine is well studied and safe for most healthy adults who train.",
    evidence: [{ code: "maughan_2018_ioc_supplements", label: "Kreider 2017", source: "library" }],
  }, ["citation_not_retrieved"])!;
  assertEquals(onlyLabel.cuts, ["label_rebuilt"]);
});

Deno.test("a cut never turns a rule, a limit or a caveat into a plain recommendation", () => {
  const base = {
    evidence: [],
    missing_data: [],
    safety_state: "allowed",
    suggested_follow_ups: [],
    reasoning_chain: [],
  };
  const cut = (answer: string) =>
    cutReply(inputsFor(), { ...base, answer }, ["numbers_not_grounded"]);
  const tail = " That keeps the week simple and realistic for your recovery.";
  // The reviewer's cases: a "skip these" list whose lead-in holds the ungrounded figure.
  assertEquals(
    cut(
      "Your knee needs a rest this week, so keep it easy.\nFor the next 13 days, skip all of these:\n- Heavy back squats\n- Jumping lunges and box jumps\n- Downhill running",
    ),
    null,
  );
  assertEquals(
    cut(
      "Your knee needs a rest this week, so keep it easy.\nStop these until 17 days pass with no pain:\n- Heavy back squats\n- Jumping lunges\n- Downhill running",
    ),
    null,
  );
  // Prohibitions, limits, conditions and caveats on a figure that is not in the data.
  for (
    const faulty of [
      "Do not squat for 13 days.",
      "Don't run on that knee for 13 days.",
      "Never load the knee in the next 13 days.",
      "Avoid jumping for 13 days.",
      "Keep squats light until 13 days have passed.",
      "Add weight only if the knee feels fine after 13 days.",
      "But stop at once if the knee hurts in the next 13 days.",
      "Unless the knee swells, you can add 13 min of cycling.",
      "However, wait 13 days before you test the knee.",
      "Limit squats to 13 reps a day.",
      "Skip jumps for the next 13 days.",
    ]
  ) {
    assertEquals(
      cut(`Do 3 sets of leg presses today, and keep the weight comfortable. ${faulty}${tail}`),
      null,
      faulty,
    );
  }
  // A lead-in with no rule of its own takes its whole list with it.
  const listed = cut(
    "Your knee is doing well so far this week and the plan can stay simple.\nSleep and protein are on track.\nWarm up for a few minutes first.\nHere are the exercises for the next 13 days:\n- Leg press\n- Hamstring curls\nThat keeps the week simple and realistic for your recovery.",
  )!;
  assertEquals(
    listed.answer.answer,
    "Your knee is doing well so far this week and the plan can stay simple.\nSleep and protein are on track.\nWarm up for a few minutes first.\nThat keeps the week simple and realistic for your recovery.",
  );
  // A repeated closing question may carry a caution word; it sets no rule, so it is still cut.
  const repetition = {
    previousReply: "Sleep was fine. Want me to adjust the plan if the knee still hurts again?",
    referralNeeded: false,
  };
  const repeated = cutReply(
    inputsFor({ repetition }),
    {
      ...base,
      answer:
        "Your sleep looks steady this week and your recovery is in range, so keep the same routine. Should I adjust the plan if the knee still hurts again?",
    },
    ["repeats_previous_turn"],
  );
  assertEquals(repeated?.cuts, ["closing_question_stripped"]);
});

Deno.test("repeats_previous_turn: a pain stop rule is never a repeat, on any turn", () => {
  const rule = "If the knee pinches or swells, stop the set and rest it for the day.";
  const repetition = { previousReply: `${rule} Want me to plan around it?`, referralNeeded: false };
  const reply = `Your sleep looks steady this week. ${rule}`;
  assertEquals(coachReplyCheck(inputsFor({ repetition }))(reply, [], reply), null);
});

Deno.test("a cut gives up rather than drop a limit on effort or time", () => {
  const base = {
    evidence: [],
    missing_data: [],
    safety_state: "allowed",
    suggested_follow_ups: [],
    reasoning_chain: [],
  };
  const lead = "Do 3 sets of leg presses today and keep the weight comfortable throughout. ";
  const tail = " That keeps the week simple and realistic for your recovery.";
  // The control: the same figure in a sentence with no limit is cut.
  assertEquals(
    cutReply(inputsFor(), { ...base, answer: `${lead}Spend 37 minutes on the warm-up.${tail}` }, [
      "numbers_not_grounded",
    ])?.cuts,
    ["numbers_stripped"],
  );
  for (
    const limit of [
      "Keep your heart rate below 163 bpm the whole time.",
      "Keep every set at RPE 7.3 or lower today.",
      "Cap it at 37 minutes in total.",
      "Stay under 37 minutes in total.",
      "Hold the load at or beneath 163 bpm effort.",
      "Do 37 minutes or less.",
      "Stay within 163 bpm.",
      "Ease off if the knee aches after 37 minutes.",
      "Back off at 163 bpm.",
      "Set a ceiling of 163 bpm.",
      "If the knee flares up, stop at minute 37.",
    ]
  ) {
    assertEquals(
      cutReply(inputsFor(), { ...base, answer: `${lead}${limit}${tail}` }, [
        "numbers_not_grounded",
      ]),
      null,
      limit,
    );
  }
});
