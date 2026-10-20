// The plain text Coach reads for one lookup result: compact, dated rows. Every figure in a row is
// copied from the record, never computed here, so the numbers check can ground a reply on it.
// Text the athlete wrote (check-in notes) is quoted, flattened to one line and labelled.
import { describeTarget, parseProgressionSummary } from "../training/progression/targets.ts";
import { clipToBudget } from "../coach_context/host.ts";
import { readScheduleBody } from "../training/schedule/lookup_body.ts";
import {
  consecutiveOverlaps,
  dayOf,
  renderOverlapFact,
  type ScheduleDay,
  scheduleDay,
  type SessionKind,
  stamp,
  unknownNote,
} from "../training/schedule/week_ahead.ts";
import type { NoticeScope } from "../ai_notice_coverage.ts";
import { type DataRequest, lookupSpec } from "./catalogue.ts";

/** Most characters of one lookup's text. */
export const lookupResultMaxChars = 5_000;

export type RenderedLookup = Readonly<{
  /** What the model reads: a heading, then the rows. */
  text: string;
  /** Rows the model was shown. */
  rows: number;
  /**
   * The lines the server produced from the records, for the numbers check: the rows shown, the
   * counts and the period. Never the model's own filter text.
   */
  grounds: readonly string[];
}>;

/** A lookup's rows as units (a row with its detail lines), ahead of fitting them to the budget. */
type Parts = Readonly<{
  preface: string[];
  units: string[][];
  trailer: string[];
  /** Units run oldest to newest, so the newest are the last ones. */
  newestLast?: boolean;
  /** Units run in date order and the earliest are the ones to keep (a schedule from today). */
  keepFirst?: boolean;
  /**
   * Lines that carry text a model wrote (a decision's summary, the reason given for a plan or a
   * proposal, Coach's own earlier reply), by the line as shown, with the part of it that is still a
   * record (its date, its codes, its counts), which is all that may ground a figure in a reply. A
   * model's words are not evidence that a figure is true, and a decision or reason written on an
   * earlier day states figures that were true on that day. An empty string grounds nothing.
   */
  ungrounded?: ReadonlyMap<string, string>;
}>;

type Json = Record<string, unknown>;

const rec = (value: unknown): Json =>
  value && typeof value === "object" && !Array.isArray(value) ? value as Json : {};
const list = (value: unknown): Json[] => Array.isArray(value) ? value.map(rec) : [];
const has = (value: unknown) => value !== null && value !== undefined && value !== "";
const val = (value: unknown) => has(value) ? String(value) : "—";
const withUnit = (value: unknown, unit: string) => has(value) ? `${value} ${unit}` : "—";

/** One line of the athlete's own words: quoted, flattened, without angle brackets. */
function quoted(value: unknown, max = 300): string {
  const flat = String(value ?? "").replace(/[<>]/g, "").replace(/\s+/g, " ").trim();
  return `"${clipToBudget(flat, max)}"`;
}

function setText(set: Json): string {
  const load = has(set.load_kg) ? `${set.load_kg} kg x ` : "";
  let text = `${load}${val(set.reps)}`;
  if (has(set.rir)) text += ` (${set.rir} reps in reserve)`;
  else if (has(set.rpe)) text += ` (RPE ${set.rpe})`;
  if (set.done === false) text += " (not ticked)";
  if (has(set.peak_bpm)) {
    text += ` [peak ${set.peak_bpm} bpm${
      has(set.drop_60s_bpm) ? `, ${set.drop_60s_bpm} bpm lower after 60 s` : ""
    }]`;
  }
  return text;
}

function workouts(body: Json, allowed: ReadonlySet<NoticeScope>): Parts {
  const sessions = list(body.sessions);
  const notes = allowed.has("workout_notes");
  let withheld = false;
  const units = sessions.map((session) => {
    withheld ||= !notes && has(session.note);
    const note = notes && has(session.note)
      ? `; session note (the athlete's words): ${quoted(session.note)}`
      : "";
    const head = `- ${val(session.local_date)} ${val(session.workout)}, ${
      withUnit(session.minutes, "min")
    }, effort ${val(session.effort)}${note}`;
    const exercises = list(session.exercises).map((exercise) => {
      const planned = rec(exercise.planned);
      const plan = has(planned.sets)
        ? ` (planned ${planned.sets} x ${planned.rep_min}-${planned.rep_max})`
        : " (not in the plan)";
      const sets = list(exercise.sets).map(setText).join("; ");
      const status = exercise.status === "skipped" ? " skipped" : "";
      const pain = exercise.pain ? " pain flagged;" : "";
      withheld ||= !notes && (has(exercise.note) || has(exercise.substitution_reason));
      const swap = exercise.kind === "substituted"
        ? ` [substitute for ${val(exercise.planned_name)}${
          notes && has(exercise.substitution_reason)
            ? `, reason (the athlete's words): ${quoted(exercise.substitution_reason)}`
            : ""
        }]`
        : "";
      const note = notes && has(exercise.note)
        ? ` note (the athlete's words): ${quoted(exercise.note)};`
        : "";
      return `    ${val(exercise.name)}${plan}${swap}${status}:${pain}${note} ${
        sets || "no sets logged"
      }`;
    });
    return [head, ...exercises];
  });
  return {
    preface: withheld ? [withheldNote("the athlete's free-text notes and swap reasons")] : [],
    units,
    trailer: [],
  };
}

/** Said when a field exists but the accepted AI notice does not name it, so Coach never reads "none". */
const withheldNote = (what: string) =>
  `Withheld: ${what} exist but are not shown, because the athlete's accepted AI notice does not name them. Do not say there are none.`;

function exerciseHistory(body: Json): Parts {
  const sessions = list(body.sessions);
  const units = sessions.map((session) => {
    if (session.assisted === true) {
      // Machine help is the load: the top set is the least help, and there is no one-rep max.
      const help = Number(session.top_load_kg) === 0
        ? "unassisted"
        : `${val(session.top_load_kg)} kg help`;
      return [
        `- ${val(session.local_date)} ${val(session.name)} (assisted): least help ${help} x ${
          val(session.top_reps)
        }, ${val(session.sets)} sets, fewest reps in reserve ${val(session.min_rir)}`,
      ];
    }
    return [
      `- ${val(session.local_date)} ${val(session.name)}: heaviest set ${
        has(session.top_load_kg) ? `${session.top_load_kg} kg x ` : ""
      }${val(session.top_reps)}, ${val(session.sets)} sets, estimated one-rep max ${
        withUnit(session.e1rm_kg, "kg")
      }, fewest reps in reserve ${val(session.min_rir)}`,
    ];
  });
  const planned = list(body.planned).map((item) =>
    `Plan now: ${val(item.name)} ${item.sets} x ${item.rep_min}-${item.rep_max}, rest ${
      val(item.rest_seconds)
    } s`
  );
  const targets = parseProgressionSummary({ schema_version: "1.0", targets: body.next_targets })
    .map((target) => `Next target (Tracend): ${describeTarget(target)}`);
  return { preface: [], units, trailer: [...planned, ...targets], newestLast: true };
}

function meals(body: Json): Parts {
  const days = list(body.days);
  const rules = rec(body.rules);
  const header =
    `Target ${withUnit(body.target_kcal, "kcal")} a day. A day is complete with ${
      val(rules.min_meals)
    } or more meals or ${
      Math.round(Number(rules.min_target_share) * 100)
    }% of the target; otherwise ` +
    "it is partial and says nothing about the day's intake.";
  const dayLines = days.map((day) =>
    `- ${val(day.local_date)}: ${val(day.meals)} meals, ${val(day.calories)} kcal, protein ${
      val(day.protein_g)
    } g, carbs ${val(day.carbohydrate_g)} g, fat ${val(day.fat_g)} g (${
      day.complete ? "complete" : "partial"
    })`
  );
  const how = (meal: Json) =>
    meal.source === "photo_analysis"
      ? "photo estimate"
      : meal.from_schedule
      ? "from the schedule"
      : "typed in";
  const mealLines = list(body.meals).map((meal) =>
    `  ${val(meal.local_date)} ${val(meal.meal_type)} (${how(meal)}): ${
      list(meal.foods).map((food) => `${val(food.name)} ${val(food.calories)} kcal`).join(", ")
    }`
  );
  return {
    preface: [header],
    units: [...dayLines, ...mealLines].map((line) => [line]),
    trailer: [],
  };
}

function bodyLookup(body: Json): Parts {
  const weights = list(body.weights);
  const tape = list(body.measurements);
  const lines = [
    ...weights.map((row) => `- ${val(row.date)}: ${val(row.kg)} kg (${val(row.source)})`),
    ...tape.map((row) =>
      `- ${val(row.date)} tape: waist ${val(row.waist_cm)}, chest ${val(row.chest_cm)}, hip ${
        val(row.hip_cm)
      }, arm ${val(row.arm_cm)}, thigh ${val(row.thigh_cm)} (cm)`
    ),
  ];
  return singles(lines);
}

function checkIns(body: Json): Parts {
  const rows = list(body.check_ins);
  const lines = rows.map((row) => {
    const note = String(row.note ?? "").trim() === ""
      ? ""
      : `; note (the athlete's words): ${quoted(row.note)}`;
    return `- ${val(row.local_date)}: sleep ${val(row.sleep_quality)}, energy ${
      val(row.energy)
    }, soreness ${val(row.soreness)}, hunger ${val(row.hunger)}, mood ${
      val(row.mood)
    } (1-5), pain ${val(row.pain_severity)}/10, ${
      row.available_to_train === false ? "not available to train" : "available to train"
    }${note}`;
  });
  return singles(lines);
}

function recovery(body: Json, allowed: ReadonlySet<NoticeScope>): Parts {
  const days = list(body.days);
  const breathing = allowed.has("breathing_rate");
  const withheld = !breathing && days.some((day) => has(day.respiratory_rate_bpm));
  const lines = days.map((day) => {
    const stages = [
      has(day.sleep_deep_minutes) ? `deep ${day.sleep_deep_minutes}` : null,
      has(day.sleep_rem_minutes) ? `REM ${day.sleep_rem_minutes}` : null,
      has(day.sleep_light_minutes) ? `light ${day.sleep_light_minutes}` : null,
      has(day.sleep_awake_minutes) ? `awake ${day.sleep_awake_minutes}` : null,
    ].filter(Boolean);
    const hrvParts = [
      has(day.hrv_sleep_ms) ? `night ${day.hrv_sleep_ms}` : null,
      has(day.hrv_morning_ms) ? `morning ${day.hrv_morning_ms}` : null,
    ].filter(Boolean);
    return `- ${val(day.local_date)}: sleep ${withUnit(day.sleep_minutes, "min")}${
      stages.length ? ` (${stages.join(", ")} min)` : ""
    }, resting heart rate ${withUnit(day.resting_heart_rate_bpm, "bpm")}, HRV ${
      withUnit(day.hrv_ms, "ms")
    }${hrvParts.length ? ` (${hrvParts.join(", ")} ms)` : ""}, ${
      breathing ? `breathing rate ${withUnit(day.respiratory_rate_bpm, "breaths/min")}, ` : ""
    }steps ${val(day.steps)}, active energy ${withUnit(day.active_energy_kcal, "kcal")}, ${
      withUnit(day.workout_minutes, "min")
    } of workouts, recovery score ${val(day.recovery_score)}, sleep quality ${
      val(day.sleep_quality)
    }, load ratio ${val(day.acwr)}`;
  });
  return { ...singles(lines), preface: withheld ? [withheldNote("breathing rates")] : [] };
}

/** Most overlaps one schedule result lists; the rest are counted, never dropped silently. */
const maxListedOverlaps = 8;

/** The plan laid over a range of dates: one line per day with a session, and the overlaps. */
function planSchedule(body: Json): Parts {
  const plan = rec(body.plan);
  const schedule = readScheduleBody(body);
  const scheduleDays: ScheduleDay[] = [];
  const lines: string[] = [];
  for (const row of schedule.days) {
    const offset = dayOf(row.date) - dayOf(schedule.today);
    const done = row.done.map((item) => ({ kind: "done" as SessionKind, ...item }));
    const planned = row.unlogged;
    // A planned session that was not logged on a day before today did not happen.
    const upcoming = offset >= 0 ? planned : [];
    const day = scheduleDay(row.date, row.weekday, offset, [
      ...done,
      ...upcoming.map((item) => ({
        kind: "planned" as SessionKind,
        name: item.name,
        exercises: schedule.exercisesByWorkout.get(item.id) ?? [],
      })),
    ]);
    scheduleDays.push(day);
    const parts = [
      done.length ? `done ${done.map((item) => item.name).join(" + ")}` : null,
      upcoming.length ? `planned ${upcoming.map((item) => item.name).join(" + ")}` : null,
      offset < 0 && planned.length
        ? `planned ${planned.map((item) => item.name).join(" + ")}, not logged`
        : null,
    ].filter(Boolean).join("; ");
    const muscles = day.muscles.length ? ` (${day.muscles.join(", ")})` : "";
    // Version numbers repeat across plans (a block is a new plan at version 1), so versions are
    // compared by id and the number is only shown.
    const version = has(row.version) && (row.block || row.versionId !== schedule.planId)
      ? ` [version ${row.version}${row.block ? ", temporary block" : ""}]`
      : "";
    lines.push(
      `- ${stamp(day)}${offset === 0 ? " (today)" : ""}: ${parts}${muscles}${
        unknownNote(day)
      }${version}`,
    );
  }
  const found = consecutiveOverlaps(scheduleDays);
  const overlaps = renderOverlapFact(found.slice(0, maxListedOverlaps));
  const omitted = found.length - maxListedOverlaps;
  return {
    preface: [
      has(plan.version)
        ? `The plan is version ${plan.version} now. Each date uses the plan version in force on it ` +
          "(a version that differs from the current one, and a temporary block, is marked), and " +
          "the plan repeats every week; a date before the first plan shows only what was " +
          "logged. Days not listed have no session planned or logged."
        : "There is no active training plan: only logged sessions are shown.",
    ],
    units: lines.map((line) => [line]),
    trailer: [
      ...(overlaps === null ? [] : [overlaps]),
      ...(omitted > 0
        ? [`${omitted} more overlaps in this range are not listed; ask for a narrower range.`]
        : []),
    ],
    keepFirst: true,
  };
}

function proposalsHistory(body: Json): Parts {
  // The reason, the gain and the cost are text built around a model's reason and note: shown, not evidence.
  const ungrounded = new Map<string, string>();
  const lines = list(body.proposals).map((proposal) => {
    const head = `- ${val(proposal.created_on)} ${val(proposal.kind).replaceAll("_", " ")}: ${
      val(proposal.title)
    } (${val(proposal.status)}, confidence ${val(proposal.confidence)}).`;
    const tail = `${has(proposal.ends_on) ? ` Ends ${proposal.ends_on}.` : ""}${
      has(proposal.applied_on) ? ` Applied ${proposal.applied_on}.` : ""
    }`;
    const line = `${head} Why: ${val(proposal.rationale)} Gain: ${val(proposal.benefit)} Cost: ${
      val(proposal.downside)
    }${tail}`;
    ungrounded.set(line, `${head}${tail}`);
    return line;
  });
  return { ...singles(lines), ungrounded };
}

function planHistory(body: Json): Parts {
  if (body.filter === "schedule") return planSchedule(body);
  if (body.filter === "proposals") return proposalsHistory(body);
  const training = list(body.training);
  const nutrition = list(body.nutrition);
  // A version's reason and a target's reason were written with a model's help (the plan or the
  // proposal that made them): shown, not evidence. The plan's own sessions, sets and targets are
  // what the athlete approved, and ground.
  const ungrounded = new Map<string, string>();
  const reasoned = (head: string, why: unknown) => {
    const line = `${head}. Why: ${val(why)}`;
    ungrounded.set(line, `${head}.`);
    return line;
  };
  const units = [
    ...training.map((version) => [
      reasoned(
        `- Plan v${val(version.version)} (${val(version.status)}), created ${
          val(version.created_on)
        }, effective ${val(version.effective_date)}: ${val(version.title)}, ${
          val(version.sessions_per_week)
        } sessions a week, ${val(version.block_weeks)}-week block`,
        version.rationale,
      ),
      ...list(version.sessions).map((session) =>
        `    day ${val(session.weekday)} ${val(session.name)}: ${
          list(session.exercises).map((exercise) =>
            `${val(exercise.name)} ${exercise.sets} x ${exercise.rep_min}-${exercise.rep_max}`
          ).join(", ")
        }`
      ),
    ]),
    ...nutrition.map((target) => [
      reasoned(
        `- Nutrition target v${val(target.version)} (${val(target.status)}), created ${
          val(target.created_on)
        }, effective ${val(target.effective_date)}: ${val(target.calories)} kcal, protein ${
          val(target.protein_g)
        } g, carbs ${val(target.carbohydrate_g)} g, fat ${val(target.fat_g)} g`,
        target.rationale,
      ),
    ]),
  ];
  return { preface: [], units, trailer: [], ungrounded };
}

function goals(body: Json): Parts {
  const goalRows = list(body.goals);
  const screenings = list(body.screenings);
  const lines = [
    ...goalRows.map((goal) => {
      const target = rec(goal.target);
      const parts = [
        has(target.weight_kg) ? `target weight ${target.weight_kg} kg` : null,
        has(target.body_fat_pct_min)
          ? `target body fat ${target.body_fat_pct_min}-${target.body_fat_pct_max}%`
          : null,
        has(target.physique) ? `target physique ${val(target.physique)}` : null,
        has(target.date) ? `target date ${target.date}` : null,
        has(target.set_at) ? `target set ${String(target.set_at).slice(0, 10)}` : null,
      ].filter(Boolean);
      return `- Goal ${val(goal.goal_type)} (${val(goal.status)}), created ${
        val(goal.created_on)
      }: ${parts.length ? parts.join(", ") : "no target set"}`;
    }),
    ...screenings.map((row) =>
      `- Health check ${val(row.screened_on)}: ${val(row.outcome).replaceAll("_", " ")}`
    ),
  ];
  return singles(lines);
}

function dailyDecisions(body: Json): Parts {
  // The summary and the decision are a model's words about that day: shown, not evidence. The
  // action codes, the confidence, the flags and the date are Tracend's record of it.
  const ungrounded = new Map<string, string>();
  const lines = list(body.decisions).map((decision) => {
    const tail = ` Confidence ${val(decision.confidence)}${
      Array.isArray(decision.risk_flags) && decision.risk_flags.length
        ? `; flags ${decision.risk_flags.join(", ")}`
        : ""
    }`;
    const training = val(decision.training_action).replaceAll("_", " ");
    const nutrition = val(decision.nutrition_action).replaceAll("_", " ");
    const line = `- ${val(decision.local_date)}: ${training}${
      has(decision.training_summary) ? ` (${decision.training_summary})` : ""
    }; nutrition ${nutrition}; decision: ${val(decision.decision)}${tail}`;
    ungrounded.set(
      line,
      `- ${val(decision.local_date)}: ${training}; nutrition ${nutrition};${tail}`,
    );
    return line;
  });
  return { ...singles(lines), ungrounded };
}

function weeklyReviews(body: Json): Parts {
  if (body.filter === "decisions") return dailyDecisions(body);
  const reviews = list(body.reviews);
  const lines = reviews.map((review) => {
    const training = rec(review.training);
    const recoveryPart = rec(review.recovery);
    return `- Week of ${val(review.review_week)}: ${
      val(review.outcome_code).replaceAll("_", " ")
    }; ${val(training.completed_workouts)} of ${val(training.planned_sessions)} planned workouts (${
      val(training.adherence_percent)
    }% done), ${val(training.completed_sets)} sets; ${
      val(recoveryPart.check_in_days)
    } check-in days; ${val(rec(review.nutrition).confirmed_days)} days with meals; next focus ${
      val(review.next_focus_code).replaceAll("_", " ")
    }`;
  });
  return singles(lines);
}

/** How a watch workout stands against the sessions the athlete logged. */
const reconciliationText: Readonly<Record<string, string>> = {
  confirmed: "matched to a logged session (confirmed)",
  suggested: "possibly the same as a logged session (suggested, not confirmed)",
  conflict: "overlaps a logged session but conflicts with it",
  rejected: "the athlete rejected a match with a logged session",
};

function watchWorkouts(body: Json): Parts {
  const lines = list(body.workouts).map((workout) =>
    `- ${val(workout.local_date)} ${val(workout.activity_type)} recorded by the watch, ${
      withUnit(workout.minutes, "min")
    }, ${withUnit(workout.energy_kcal, "kcal")}; ${
      has(workout.reconciliation)
        ? reconciliationText[String(workout.reconciliation)] ?? "not matched to a logged session"
        : "no logged session was matched to it"
    }`
  );
  return singles(lines);
}

function healthHistory(body: Json): Parts {
  if (body.filter === "workouts") return watchWorkouts(body);
  const months = list(body.months);
  const lines = months.map((month) =>
    `- ${String(month.month ?? "").slice(0, 7)} (imported from Apple Health): ${
      val(month.workouts)
    } workouts (${val(month.strength_workouts)} strength, ${
      val(month.workout_minutes)
    } min), sleep ${withUnit(month.sleep_minutes_avg, "min")} over ${
      val(month.sleep_nights)
    } nights, weight ${withUnit(month.weight_kg_avg, "kg")} over ${val(month.weight_days)} days`
  );
  return singles(lines);
}

function pastMessages(body: Json): Parts {
  // Coach's own words are not records: labelled so a claim in one is checked, never repeated as
  // fact, and kept out of the lines that ground the numbers check.
  const replies = list(body.coach_replies).map((message) =>
    `- ${
      val(message.local_date)
    }, Coach replied (an earlier reply, not a record; it may have been wrong, so check any claim in it against the records): ${
      quoted(message.content)
    }`
  );
  const lines = [
    ...list(body.messages).map((message) =>
      `- ${val(message.local_date)}, the athlete wrote: ${quoted(message.content)}`
    ),
    ...replies,
  ];
  return {
    ...singles(lines),
    ungrounded: new Map(
      replies.map((line) => [line, line.slice(0, line.indexOf(" (an earlier reply"))]),
    ),
  };
}

/** One line per row. */
const singles = (lines: string[]): Parts => ({
  preface: [],
  units: lines.map((line) => [line]),
  trailer: [],
});

const renderers: Readonly<
  Record<string, (body: Json, allowed: ReadonlySet<NoticeScope>) => Parts>
> = {
  workouts,
  exercise_history: exerciseHistory,
  meals,
  body: bodyLookup,
  check_ins: checkIns,
  recovery,
  plan_history: planHistory,
  goals,
  weekly_reviews: weeklyReviews,
  health_history: healthHistory,
  past_messages: pastMessages,
};

/** The lookups that have a renderer, for the grounding table's completeness check. */
export const lookupRendererNames: readonly string[] = Object.keys(renderers);

/**
 * Which fields of each lookup's payload ground a figure in a reply (`grounds`) and which are text a
 * model wrote (`modelText`): shown to Coach, never evidence. Only values that are deterministic
 * (Tracend calculated them) or recorded by the athlete may ground; a decision's summary, the reason
 * on a plan version, a nutrition target or a proposal, and Coach's own earlier reply may not. Keyed
 * by lookup, then by mode (the filter that selects different records, or "default"). Every
 * renderer and every mode must be declared here, with a fixture, or render_grounding_test.ts
 * fails: a new renderer states what it grounds before it can ship. Paths are in the lookup's
 * payload (`a[].b` is the field `b` of each element of the list `a`); the test puts a marker in
 * each and reads it back from `text` and `grounds`.
 */
export type FieldGrounding = Readonly<{
  grounds: readonly string[];
  modelText: readonly string[];
}>;

export const lookupGrounding: Readonly<Record<string, Readonly<Record<string, FieldGrounding>>>> = {
  workouts: {
    default: {
      grounds: [
        "sessions[].local_date",
        "sessions[].workout",
        "sessions[].note",
        "sessions[].exercises[].name",
        "sessions[].exercises[].note",
        "sessions[].exercises[].planned_name",
        "sessions[].exercises[].substitution_reason",
      ],
      modelText: [],
    },
  },
  exercise_history: {
    default: {
      grounds: ["sessions[].local_date", "sessions[].name", "planned[].name"],
      modelText: [],
    },
  },
  meals: {
    default: {
      grounds: [
        "days[].local_date",
        "meals[].local_date",
        "meals[].meal_type",
        "meals[].foods[].name",
      ],
      modelText: [],
    },
  },
  body: {
    default: {
      grounds: ["weights[].date", "weights[].source", "measurements[].date"],
      modelText: [],
    },
  },
  check_ins: {
    default: { grounds: ["check_ins[].local_date", "check_ins[].note"], modelText: [] },
  },
  recovery: { default: { grounds: ["days[].local_date"], modelText: [] } },
  plan_history: {
    default: {
      grounds: [
        "training[].status",
        "training[].title",
        "training[].sessions[].name",
        "training[].sessions[].exercises[].name",
        "nutrition[].status",
      ],
      modelText: ["training[].rationale", "nutrition[].rationale"],
    },
    schedule: { grounds: ["days[].planned[].name", "days[].done[].name"], modelText: [] },
    proposals: {
      grounds: [
        "proposals[].created_on",
        "proposals[].kind",
        "proposals[].title",
        "proposals[].status",
        "proposals[].confidence",
      ],
      modelText: ["proposals[].rationale", "proposals[].benefit", "proposals[].downside"],
    },
  },
  goals: {
    default: {
      grounds: ["goals[].goal_type", "goals[].status", "screenings[].outcome"],
      modelText: [],
    },
  },
  weekly_reviews: {
    default: {
      grounds: ["reviews[].review_week", "reviews[].outcome_code", "reviews[].next_focus_code"],
      modelText: [],
    },
    decisions: {
      grounds: [
        "decisions[].local_date",
        "decisions[].training_action",
        "decisions[].nutrition_action",
        "decisions[].confidence",
      ],
      modelText: ["decisions[].training_summary", "decisions[].decision"],
    },
  },
  health_history: {
    default: { grounds: ["months[].workouts"], modelText: [] },
    workouts: { grounds: ["workouts[].local_date", "workouts[].activity_type"], modelText: [] },
  },
  past_messages: {
    default: {
      grounds: ["messages[].local_date", "messages[].content", "coach_replies[].local_date"],
      modelText: ["coach_replies[].content"],
    },
  },
};

/** The heading of a result: what was asked, the period, how many rows are shown and why not all. */
function heading(
  request: DataRequest,
  shown: number,
  total: number,
  sqlCut: boolean,
  keepFirst = false,
) {
  const range = `${request.from} to ${request.to}`;
  const filter = request.filter ? `, filter "${request.filter.replace(/"/g, "")}"` : "";
  const count = shown < total
    ? `showing the ${
      keepFirst ? "first" : "newest"
    } ${shown} of ${total} rows (the rest were cut for size)`
    : `${total} ${total === 1 ? "row" : "rows"}`;
  const more = sqlCut
    ? "; more rows exist than the lookup returns (the newest are shown): ask for a narrower range for the rest"
    : "";
  return `### ${request.lookup} ${range}${filter}: ${count}${more}`;
}

/**
 * The text of a lookup's RPC payload. Whole rows are shown, newest first, until the character
 * budget runs out; the heading then says how many of how many, so the model never believes it saw
 * more than it did. An unreadable payload becomes a notice that Coach could not check.
 */
export function renderLookup(
  request: DataRequest,
  payload: unknown,
  maxChars: number = lookupResultMaxChars,
  allowed: ReadonlySet<NoticeScope> = new Set(),
): RenderedLookup {
  const body = rec(payload);
  const render = renderers[request.lookup];
  if (
    !render || !lookupSpec(request.lookup) || typeof body.schema_version !== "string" ||
    !body.schema_version.startsWith("1.")
  ) {
    return unreadable(request);
  }
  const parts = render(body, allowed);
  const total = parts.units.length;
  const sqlCut = body.truncated === true;
  const fixed = [...parts.preface, ...parts.trailer].join("\n").length;
  // Room for the widest heading, then rows: newest first (the last ones when the rows run
  // oldest to newest).
  let used = fixed + heading(request, total, total + 1, sqlCut, parts.keepFirst).length + 40;
  const kept: string[][] = [];
  const order = parts.newestLast ? [...parts.units].reverse() : parts.units;
  for (const unit of order) {
    const size = unit.join("\n").length + 1;
    if (used + size > maxChars) break;
    kept.push(unit);
    used += size;
  }
  const shown = parts.newestLast ? kept.reverse() : kept;
  const headed = heading(request, shown.length, total, sqlCut, parts.keepFirst);
  const lines = [...parts.preface, ...shown.flat(), ...parts.trailer];
  const empty = total === 0 ? ["No records in this range."] : [];
  return {
    text: [headed, ...empty, ...lines].join("\n"),
    rows: shown.length,
    grounds: [
      `Period looked at: ${request.from} to ${request.to}. Rows shown: ${shown.length} of ${total}.`,
      ...lines.map((line) => parts.ungrounded?.get(line) ?? line).filter((line) => line !== ""),
    ],
  };
}

/** Shown in place of a result the server could not read: Coach must say it could not check. */
export function unreadable(request: DataRequest): RenderedLookup {
  return {
    text: `### ${request.lookup} ${request.from} to ${request.to}: could not be read just now. ` +
      "Say you could not check it; do not guess.",
    rows: 0,
    grounds: [],
  };
}
