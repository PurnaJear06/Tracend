// The plain text Coach reads for one lookup result: compact, dated rows. Every figure in a row is
// copied from the record, never computed here, so the numbers check can ground a reply on it.
// Text the athlete wrote (check-in notes) is quoted, flattened to one line and labelled.
import { describeTarget, parseProgressionSummary } from "../training/progression/targets.ts";
import { clipToBudget } from "../coach_context/host.ts";
import type { DayExercise } from "../training/schedule/muscles.ts";
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

function workouts(body: Json): Parts {
  const sessions = list(body.sessions);
  const units = sessions.map((session) => {
    const head = `- ${val(session.local_date)} ${val(session.workout)}, ${
      withUnit(session.minutes, "min")
    }, effort ${val(session.effort)}`;
    const exercises = list(session.exercises).map((exercise) => {
      const planned = rec(exercise.planned);
      const plan = has(planned.sets)
        ? ` (planned ${planned.sets} x ${planned.rep_min}-${planned.rep_max})`
        : " (not in the plan)";
      const sets = list(exercise.sets).map(setText).join("; ");
      const status = exercise.status === "skipped" ? " skipped" : "";
      const pain = exercise.pain ? " pain flagged;" : "";
      return `    ${val(exercise.name)}${plan}${status}:${pain} ${sets || "no sets logged"}`;
    });
    return [head, ...exercises];
  });
  return { preface: [], units, trailer: [] };
}

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

function recovery(body: Json): Parts {
  const days = list(body.days);
  const lines = days.map((day) =>
    `- ${val(day.local_date)}: sleep ${withUnit(day.sleep_minutes, "min")}, resting heart rate ${
      withUnit(day.resting_heart_rate_bpm, "bpm")
    }, HRV ${withUnit(day.hrv_ms, "ms")}, steps ${val(day.steps)}, recovery score ${
      val(day.recovery_score)
    }, sleep quality ${val(day.sleep_quality)}, load ratio ${val(day.acwr)}`
  );
  return singles(lines);
}

/** Most overlaps one schedule result lists; the rest are counted, never dropped silently. */
const maxListedOverlaps = 8;

/** The plan laid over a range of dates: one line per day with a session, and the overlaps. */
function planSchedule(body: Json): Parts {
  const plan = rec(body.plan);
  // Planned workouts are keyed by id: names are not unique.
  const sessions = new Map(
    list(body.sessions).map((session) => [
      String(session.id),
      list(session.exercises).map((exercise): DayExercise => ({
        slug: typeof exercise.slug === "string" ? exercise.slug : null,
        sets: Number(exercise.sets) || 0,
      })),
    ]),
  );
  const to = String(body.to ?? "");
  const today = String(has(body.today) ? body.today : to);
  const scheduleDays: ScheduleDay[] = [];
  const lines: string[] = [];
  for (const row of list(body.days)) {
    const date = String(row.date);
    const weekday = Number(row.weekday);
    const offset = dayOf(date) - dayOf(today);
    const done = list(row.done).map((item) => ({
      kind: "done" as SessionKind,
      id: String(item.planned_workout_id),
      name: String(item.name),
      exercises: list(item.exercises).map((exercise): DayExercise => ({
        slug: typeof exercise.slug === "string" ? exercise.slug : null,
        sets: Number(exercise.sets) || 0,
      })),
    }));
    const doneNames = done.map((item) => item.name);
    // A finished session answers the planned one with its id; one finished under an earlier plan
    // version (an id the active plan does not hold) is matched by its name.
    const isDone = (id: string, name: string) =>
      done.some((item) => item.id === id || (!sessions.has(item.id) && item.name === name));
    const planned = list(row.planned).map((item) => ({
      id: String(item.id),
      name: String(item.name),
    })).filter((item) => !isDone(item.id, item.name));
    // A planned session that was not logged on a day before today did not happen.
    const upcoming = offset >= 0 ? planned : [];
    const day = scheduleDay(date, weekday, offset, [
      ...done,
      ...upcoming.map((item) => ({
        kind: "planned" as SessionKind,
        name: item.name,
        exercises: sessions.get(item.id) ?? [],
      })),
    ]);
    scheduleDays.push(day);
    const parts = [
      done.length ? `done ${doneNames.join(" + ")}` : null,
      upcoming.length ? `planned ${upcoming.map((item) => item.name).join(" + ")}` : null,
      offset < 0 && planned.length
        ? `planned ${planned.map((item) => item.name).join(" + ")}, not logged`
        : null,
    ].filter(Boolean).join("; ");
    const muscles = day.muscles.length ? ` (${day.muscles.join(", ")})` : "";
    const block = row.block === true;
    const version = has(row.version) && (block || row.version !== plan.version)
      ? ` [version ${row.version}${block ? ", temporary block" : ""}]`
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

function planHistory(body: Json): Parts {
  if (body.filter === "schedule") return planSchedule(body);
  const training = list(body.training);
  const nutrition = list(body.nutrition);
  const units = [
    ...training.map((version) => [
      `- Plan v${val(version.version)} (${val(version.status)}), created ${
        val(version.created_on)
      }, effective ${val(version.effective_date)}: ${val(version.title)}, ${
        val(version.sessions_per_week)
      } sessions a week, ${val(version.block_weeks)}-week block. Why: ${val(version.rationale)}`,
      ...list(version.sessions).map((session) =>
        `    day ${val(session.weekday)} ${val(session.name)}: ${
          list(session.exercises).map((exercise) =>
            `${val(exercise.name)} ${exercise.sets} x ${exercise.rep_min}-${exercise.rep_max}`
          ).join(", ")
        }`
      ),
    ]),
    ...nutrition.map((target) => [
      `- Nutrition target v${val(target.version)} (${val(target.status)}), created ${
        val(target.created_on)
      }, effective ${val(target.effective_date)}: ${val(target.calories)} kcal, protein ${
        val(target.protein_g)
      } g, carbs ${val(target.carbohydrate_g)} g, fat ${val(target.fat_g)} g. Why: ${
        val(target.rationale)
      }`,
    ]),
  ];
  return { preface: [], units, trailer: [] };
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

function weeklyReviews(body: Json): Parts {
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

function healthHistory(body: Json): Parts {
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
  const lines = list(body.messages).map((message) =>
    `- ${val(message.local_date)}, the athlete wrote: ${quoted(message.content)}`
  );
  return singles(lines);
}

/** One line per row. */
const singles = (lines: string[]): Parts => ({
  preface: [],
  units: lines.map((line) => [line]),
  trailer: [],
});

const renderers: Readonly<Record<string, (body: Json) => Parts>> = {
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
export function renderLookup(request: DataRequest, payload: unknown): RenderedLookup {
  const body = rec(payload);
  const render = renderers[request.lookup];
  if (
    !render || !lookupSpec(request.lookup) || typeof body.schema_version !== "string" ||
    !body.schema_version.startsWith("1.")
  ) {
    return unreadable(request);
  }
  const parts = render(body);
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
    if (used + size > lookupResultMaxChars) break;
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
      ...lines,
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
