// The numbers behind the pain check, the red flags and the joint rules (B5-1, rules versions pain-v1
// and joint-v1). The rules run in SQL (migration 20261024060025_pain_checks.sql: private.pain_rules,
// private.pain_outcome, private.joint_states, private.joint_rules, private.joint_swap,
// private.joint_changes) because the reports, the plan and the session live in the database; this
// module holds each number with its sources and a basis in our own words, and a test keeps it equal
// to the migration. Nothing here diagnoses a condition or prescribes rehab: the rules route the
// athlete to a doctor or physio, ease the session around a sore joint, and say nothing else.
import { sourced } from "../standard/sources.ts";

export const painRulesVersion = sourced(
  "pain-v1" as const,
  ["tracend_in_house"],
  "Names this rule set in the code that stores a report's outcome, so a later change of numbers " +
    "can be told apart from today's. In-house, like the bands below.",
);

export const jointRulesVersion = sourced(
  "joint-v1" as const,
  ["tracend_in_house"],
  "Names the rule set that changes a session around a joint. In-house.",
);

/** Severity 0 to 10: from this on a report is clinician_today, modify and watch respectively. */
export const painBands = sourced(
  Object.freeze({ clinicianTodayFrom: 7, modifyFrom: 4, watchFrom: 1 }),
  ["tracend_in_house"],
  "In-house bands (owner decision O8). Seven or more already sends the athlete to a doctor or " +
    "physio in the daily decision and the Coach safety screen, so the pain check matches them; " +
    "4 to 6 limits the joint's exercises without stopping the athlete, 1 to 3 is only watched. " +
    "Some pain during exercise is not always harmful (Smith 2017, in people who already have " +
    "long-lasting pain), but that is context for the watch band, not a basis for the numbers. " +
    "Needs a coach's review before an external beta.",
);

/** A clearance counts only at this severity or lower. */
export const painClearanceMaxSeverity = sourced(
  3,
  ["tracend_in_house"],
  "In-house. Someone cleared by a doctor or physio who still reports pain above the watch band " +
    "has a new symptom, and a new symptom always holds the area again. Self-attested (owner " +
    "decision O9): the athlete says a clinician cleared them.",
);

/** An area's state lapses this many days after its newest report. */
export const painLapseDays = sourced(
  7,
  ["tracend_in_house"],
  "In-house (owner decision O8). A week without a new report ends a limit or a watch: pain that " +
    "is not reported again is not assumed to persist forever. A held area never lapses; it ends " +
    "only by clearance.",
);

/** An area limited or held this many days is flagged as lasting. */
export const painPersistentDays = sourced(
  14,
  ["keogh_2017", "tracend_in_house"],
  "Shoulder, low back and knee are where lifters are most often hurt, and pain that does not " +
    "settle is a reason to see a professional (Keogh 2017). Two weeks is an in-house line " +
    "(owner decision O8); the athlete is told, in plain words, to see a physio or doctor.",
);

/** Reports of at least this severity count towards a pain that lasts. */
export const painPersistentMinSeverity = sourced(
  4,
  ["tracend_in_house"],
  "In-house: the lower edge of the modify band, so mild pain on and off is not read as lasting.",
);

/** A guard against a stuck client, not a rule about the athlete. */
export const painReportsPerDay = sourced(
  40,
  ["tracend_in_house"],
  "A limit on stored reports a day so a stuck client cannot fill the table; ordinary use is a " +
    "few. In-house.",
);

/**
 * What each red flag does to a report: urgent (emergency care), clinician_today (see a doctor or
 * physio today) or clinician (book one). Every one of them holds the joint and routes out of
 * training advice. The questions the athlete answers are in red_flags.ts.
 */
export const redFlagOutcomes = Object.freeze({
  bladder_bowel_saddle: sourced(
    "urgent" as const,
    ["finucane_2020"],
    "New trouble controlling the bladder or bowels, or numbness around the groin or inner " +
      "thighs, with back pain is the red flag of serious spinal problems that the international " +
      "framework (Finucane 2020) and NICE NG59 (nice.org.uk/guidance/ng59) send to urgent care.",
  ),
  chest_or_breath: sourced(
    "urgent" as const,
    ["tracend_in_house"],
    "In-house, matching the Coach's chest-symptom screen: pain that comes with chest pain, " +
      "pressure or shortness of breath is urgent whatever the joint. No open source for the " +
      "wording; the safe default is emergency care.",
  ),
  numb_weak_limb: sourced(
    "clinician_today" as const,
    ["finucane_2020"],
    "Numbness, tingling or weakness in an arm or leg is a nerve-related red flag in the " +
      "framework (Finucane 2020) and in the Coach's numbness screen.",
  ),
  pop_or_sudden: sourced(
    "clinician_today" as const,
    ["tracend_in_house"],
    "In-house, matching the Coach's injury-pain screen: a pop, a tear or a sudden sharp pain at " +
      "the start of the pain is an injury, not soreness.",
  ),
  cannot_bear_or_move: sourced(
    "clinician_today" as const,
    ["stiell_1997"],
    "Being unable to bear weight after a knee injury is the rule's trigger to be examined and " +
      "imaged (Stiell 1997); the question is asked for every joint, as the safe default.",
  ),
  rapid_swelling: sourced(
    "clinician_today" as const,
    ["tracend_in_house"],
    "In-house, from the Coach's injury-pain wording: a joint that swells up quickly after " +
      "training needs to be looked at the same day.",
  ),
  dislocated_or_cannot_lift: sourced(
    "clinician_today" as const,
    ["tracend_in_house"],
    "In-house: a shoulder that felt out of place, or an arm that cannot be lifted, is not a " +
      "range to train around.",
  ),
  locks_gives_way: sourced(
    "clinician" as const,
    ["tracend_in_house"],
    "In-house: a knee that locks or gives way is a reason to see a doctor or physio before " +
      "loading it again, though not the same day.",
  ),
  fever_unwell: sourced(
    "clinician" as const,
    ["finucane_2020"],
    "Fever or feeling unwell with pain is a red flag in the framework (Finucane 2020), and " +
      "Tracend never advises training through a fever.",
  ),
  night_pain: sourced(
    "clinician" as const,
    ["finucane_2020"],
    "Pain that wakes the athlete at night and does not ease when they change position is a red " +
      "flag in the framework (Finucane 2020).",
  ),
});

/**
 * The action per joint state and the stress of the exercise on that joint. An exercise at a
 * stress with no entry (low stress; moderate on a joint only on watch) is left as planned.
 */
export const jointActions = sourced(
  Object.freeze({
    held: Object.freeze({ high: "swap", moderate: "swap" }),
    limited: Object.freeze({ high: "swap", moderate: "limit" }),
    watch: Object.freeze({ high: "limit" }),
  }),
  ["haugen_2023", "schoenfeld_2020_rom", "tracend_in_house"],
  "Machines and free weights build size and strength alike (Haugen 2023), so swapping a " +
    "demanding exercise for a gentler one keeps most of the stimulus; a shorter pain-free range " +
    "is a reasonable adjustment when a joint calls for it (Schoenfeld 2020). Which state gets " +
    "which action is in-house: a held joint trains nothing demanding, a limited one swaps the " +
    "highest-stress lifts and shortens the range of the moderate ones, a joint on watch only " +
    "shortens the highest-stress lifts.",
);

/** The highest stress a swap may have on the joint, by state; the athlete's own state decides. */
export const jointSwapMaxStress = sourced(
  Object.freeze({ held: "low", limited: "moderate" }),
  ["tracend_in_house"],
  "In-house: a held joint gets only low-stress exercises; a limited one may get a moderate " +
    "exercise because the swap already lowers the demand.",
);

/** The highest stress a swapped-in exercise may have on the athlete's other sore joints. */
export const jointOtherJointCap = sourced(
  Object.freeze({ held: "low", limited: "low", watch: "moderate" }),
  ["tracend_in_house"],
  "In-house: a swap must not trade one sore joint for another, so another held or limited " +
    "joint allows only low stress and one on watch allows moderate.",
);

/** The stress an in-workout swap option may have on the joint (the chip stops the exercise). */
export const jointOptionsMaxStress = sourced(
  "low" as const,
  ["tracend_in_house"],
  "In-house: when pain stops an exercise mid-workout the offered swap is low stress on the sore " +
    "joint, or none and the exercise is skipped.",
);

/** A limited exercise's effort is at most this (RPE). */
export const jointLimitRpeMax = sourced(
  7,
  ["lopez_2021", "tracend_in_house"],
  "Lighter, easier work still builds muscle when it is taken near failure (Lopez 2021), so " +
    "capping the effort on a sore joint's exercises costs little; seven leaves three repetitions " +
    "in reserve. The number is in-house.",
);

/** An exercise with no catalog entry is treated as this stress on every joint. */
export const jointUnratedStress = sourced(
  "moderate" as const,
  ["tracend_in_house"],
  "In-house: missing data lowers what is allowed and never raises it, so an unrated exercise " +
    "is treated as moderate on every joint.",
);

export type RangeNote = Readonly<{
  code: string;
  joint: "knee" | "back" | "shoulder" | null;
  pattern: string | null;
  cue: string;
}>;

/**
 * The range-limit cue for a joint and a movement pattern. Coaching cues in our own words, not
 * rehab. A pair not listed gets the generic cue.
 */
export const rangeNotes = sourced(
  Object.freeze(
    [
      {
        code: "knee_squat_depth",
        joint: "knee",
        pattern: "squat",
        cue: "Squat only as deep as stays pain-free. A box or bench behind you marks the depth.",
      },
      {
        code: "knee_lunge_depth",
        joint: "knee",
        pattern: "lunge",
        cue: "Take shorter steps and go only as low as stays pain-free.",
      },
      {
        code: "knee_extension_partial",
        joint: "knee",
        pattern: "quads_isolation",
        cue: "Use the part of the movement that stays pain-free.",
      },
      {
        code: "back_hinge_range",
        joint: "back",
        pattern: "hinge",
        cue: "Lower only as far as you can keep your back flat and pain-free, about knee height.",
      },
      {
        code: "back_squat_depth",
        joint: "back",
        pattern: "squat",
        cue: "Stop above the depth where your back rounds or hurts.",
      },
      {
        code: "back_core_neutral",
        joint: "back",
        pattern: "core",
        cue: "Skip moves that bend or twist your spine if they hurt; hold still instead.",
      },
      {
        code: "back_press_seated",
        joint: "back",
        pattern: "vertical_push",
        cue: "Press seated with your back supported if you can.",
      },
      {
        code: "shoulder_press_height",
        joint: "shoulder",
        pattern: "vertical_push",
        cue: "Press only as high as stays pain-free. Neutral-grip dumbbells can help.",
      },
      {
        code: "shoulder_press_depth",
        joint: "shoulder",
        pattern: "horizontal_push",
        cue: "Lower only as far as stays pain-free.",
      },
      {
        code: "shoulder_fly_stretch",
        joint: "shoulder",
        pattern: "chest_fly",
        cue: "Keep the stretch short of where it hurts.",
      },
      {
        code: "shoulder_pull_range",
        joint: "shoulder",
        pattern: "vertical_pull",
        cue: "Pull in front of you, never behind the neck, and stop the hang short of pain.",
      },
      {
        code: "shoulder_raise_height",
        joint: "shoulder",
        pattern: "lateral_raise",
        cue: "Raise to just below shoulder height.",
      },
      {
        code: "generic_pain_free",
        joint: null,
        pattern: null,
        cue: "Use a range that stays pain-free and stop if the pain builds set to set.",
      },
    ] as const satisfies readonly RangeNote[],
  ),
  ["schoenfeld_2020_rom", "tracend_in_house"],
  "A shorter pain-free range is a reasonable adjustment when a joint calls for it (Schoenfeld " +
    "2020), and full range is only trivially better than a partial one for muscle growth " +
    "(Wolf 2023, doi 10.47206/ijsc.v3i1.182, a study without a PubMed entry). Which cue goes with " +
    "which joint and movement, and every word of them, are in-house coaching cues, not rehab.",
);

/** The rules as private.pain_rules() returns them. */
export function painRulesJson(): Readonly<Record<string, unknown>> {
  return {
    version: painRulesVersion.value,
    clinician_today_from: painBands.value.clinicianTodayFrom,
    modify_from: painBands.value.modifyFrom,
    watch_from: painBands.value.watchFrom,
    clearance_max_severity: painClearanceMaxSeverity.value,
    lapse_days: painLapseDays.value,
    persistent_days: painPersistentDays.value,
    persistent_min_severity: painPersistentMinSeverity.value,
    reports_per_day: painReportsPerDay.value,
    red_flags: Object.fromEntries(
      Object.entries(redFlagOutcomes).map(([code, rule]) => [code, rule.value]),
    ),
  };
}

/** The rules as private.joint_rules() returns them. */
export function jointRulesJson(): Readonly<Record<string, unknown>> {
  return {
    version: jointRulesVersion.value,
    actions: jointActions.value,
    swap_max_stress: jointSwapMaxStress.value,
    other_joint_cap: jointOtherJointCap.value,
    options_max_stress: jointOptionsMaxStress.value,
    limit_rpe_max: jointLimitRpeMax.value,
    unrated_stress: jointUnratedStress.value,
  };
}
