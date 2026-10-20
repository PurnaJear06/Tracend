// Contract 7 contributor (the Coach investigates first): the Coverage Brief. For each kind of record
// the athlete has it says what the context above already shows (its window and grain), what a
// lookup adds and under which name, how much exists with its first and last date and how fresh it
// is, and the kinds that neighbour it. A question about one kind usually turns on its neighbours
// (a session question is also a sleep, recovery, soreness and schedule question), and the context
// summarises most kinds, so the brief is how Coach sees where the holes are before it answers.
//
// It replaces the data index. The neighbour table is static and the same for every athlete and
// every question: it is a map of the product's data, not a choice made for the question. The dates
// and counts come from get_coach_data_index_v1 (service role); when that read fails the brief is
// still shown without them. The rules for asking (data_requests) are in the Coach instructions.
import { dayOf } from "../../training/schedule/week_ahead.ts";
import type { CoachContextContributor } from "../host.ts";
import { coachServiceRpc, type StateSource, stateSourceFromRpc } from "../service_source.ts";

export const coverageBriefContributorId = "coverage_brief";
export const coverageBriefBudgetChars = 2_800;

/** One way to reach a kind of record: a lookup, and the filter that selects it, if any. */
export type BriefLookup = Readonly<{ lookup: string; filter?: string }>;

export type BriefDomain = Readonly<{
  /** The kind's name, as the brief and the eval bank call it. */
  id: string;
  /** What the context above already shows of it: window and grain. */
  shown: string;
  /** What a lookup adds, in words with the lookup names. */
  adds: string;
  /** The lookups that reach it. A request for any of them looks the kind up. */
  lookups: readonly BriefLookup[];
  /** The keys of get_coach_data_index_v1 `domains` that count it. */
  index: readonly string[];
  /** What one index record is. */
  unit: string;
  /** The kinds that neighbour it: check them too. The same for every question. */
  also: readonly string[];
}>;

// The windows below are the ones the athlete file and the contributors render: 28 days of training
// log and watch data, 14 days of check-ins, 8 weeks of weights (build_coach_athlete_context, and the
// training_plan, nutrition_state and proposals contributors). A change there changes a line here;
// coverage_brief_test.ts checks every name and neighbour.
export const coverageDomains: readonly BriefDomain[] = Object.freeze([
  {
    id: "training",
    shown: "28 d session totals (no sets, loads, notes)",
    adds: "workouts (every set with load, reps, notes, swaps), exercise_history (one lift)",
    lookups: [{ lookup: "workouts" }, { lookup: "exercise_history" }],
    index: ["workouts"],
    unit: "sessions",
    also: ["recovery", "check_ins", "plan_ahead", "nutrition"],
  },
  {
    id: "plan_ahead",
    shown: "this week, the next 7 days with muscles",
    adds: "plan_history filter schedule (any date, up to 90 d ahead)",
    lookups: [{ lookup: "plan_history", filter: "schedule" }],
    index: [],
    unit: "",
    also: ["training", "recovery", "check_ins", "proposals"],
  },
  {
    id: "plan_versions",
    shown: "the active plan",
    adds: "plan_history (past versions and targets, with why)",
    lookups: [{ lookup: "plan_history" }],
    index: ["plan_history"],
    unit: "plan versions",
    also: ["proposals", "training", "goals"],
  },
  {
    id: "recovery",
    shown: "28 d sleep, resting HR, HRV, steps",
    adds: "recovery (60 d; sleep stages, night/morning HRV, breathing, score)",
    lookups: [{ lookup: "recovery" }],
    index: ["recovery"],
    unit: "days",
    also: ["check_ins", "training", "watch_workouts"],
  },
  {
    id: "check_ins",
    shown: "14 d scores (sleep, energy, soreness, mood, pain), no notes",
    adds: "check_ins (60 d, with notes)",
    lookups: [{ lookup: "check_ins" }],
    index: ["check_ins"],
    unit: "check-ins",
    also: ["recovery", "training", "body"],
  },
  {
    id: "body",
    shown: "8 wk weights, waist, goal trend",
    adds: "body (90 weights, tape)",
    lookups: [{ lookup: "body" }],
    index: ["body"],
    unit: "weigh-in days",
    also: ["nutrition", "goals", "training"],
  },
  {
    id: "nutrition",
    shown: "this week by day, today's meals",
    adds: "meals (60 d, each meal's foods)",
    lookups: [{ lookup: "meals" }],
    index: ["meals"],
    unit: "days with meals",
    also: ["body", "training", "goals"],
  },
  {
    id: "goals",
    shown: "active goal, phase, health check",
    adds: "goals (every goal and health check)",
    lookups: [{ lookup: "goals" }],
    index: ["goals"],
    unit: "goals",
    also: ["body", "nutrition", "proposals"],
  },
  {
    id: "proposals",
    shown: "last 3, running block, what waits",
    adds: "plan_history filter proposals (all, why, the athlete's answers)",
    lookups: [{ lookup: "plan_history", filter: "proposals" }],
    index: ["proposals"],
    unit: "proposals",
    also: ["plan_ahead", "goals", "decisions", "conversation"],
  },
  {
    id: "decisions",
    shown: "-",
    adds: "weekly_reviews filter decisions (daily decisions, why)",
    lookups: [{ lookup: "weekly_reviews", filter: "decisions" }],
    index: ["daily_decisions"],
    unit: "decisions",
    also: ["recovery", "check_ins", "proposals"],
  },
  {
    id: "watch_workouts",
    shown: "14 d, type and minutes",
    adds: "health_history filter workouts (any age)",
    lookups: [{ lookup: "health_history", filter: "workouts" }],
    index: ["watch_workouts"],
    unit: "workouts",
    also: ["training", "recovery"],
  },
  {
    id: "reviews",
    shown: "-",
    adds: "weekly_reviews",
    lookups: [{ lookup: "weekly_reviews" }],
    index: ["weekly_reviews"],
    unit: "reviews",
    also: ["training", "nutrition", "goals"],
  },
  {
    id: "apple_health",
    shown: "-",
    adds: "health_history (monthly, from onboarding)",
    lookups: [{ lookup: "health_history" }],
    index: ["health_history"],
    unit: "months",
    also: ["body", "recovery", "training"],
  },
  {
    id: "conversation",
    shown: "latest messages, saved notes",
    adds: "past_messages (the athlete's words, Coach's earlier replies)",
    lookups: [{ lookup: "past_messages" }],
    index: ["past_messages"],
    unit: "messages",
    also: ["proposals", "training"],
  },
]);

type Json = Record<string, unknown>;
const rec = (value: unknown): Json =>
  value && typeof value === "object" && !Array.isArray(value) ? value as Json : {};

const weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

const iso = (value: unknown): string | null =>
  typeof value === "string" && /^\d{4}-\d{2}-\d{2}/.test(value) ? value.slice(0, 10) : null;

/** "today", "1 d ago" or "N d ago" for a date against the coaching date. */
export function ageText(date: string, localDate: string): string {
  const days = dayOf(localDate) - dayOf(date);
  return days <= 0 ? "today" : `${days} d ago`;
}

/** The records of a domain from the index: first, last, count; null when it holds none. */
function recordsOf(
  domains: Json,
  keys: readonly string[],
): Readonly<{ first: string; last: string; count: number }> | null {
  let first: string | null = null;
  let last: string | null = null;
  let count = 0;
  for (const key of keys) {
    const entry = rec(domains[key]);
    const f = iso(entry.first);
    const l = iso(entry.last);
    const c = typeof entry.count === "number" ? entry.count : 0;
    if (c === 0 || f === null || l === null) continue;
    count += c;
    if (first === null || f < first) first = f;
    if (last === null || l > last) last = l;
  }
  return first === null || last === null ? null : { first, last, count };
}

/** What the plan's schedule covers, for the plan_ahead line. */
function scheduleStat(schedule: Json): string | null {
  const days = Array.isArray(schedule.weekdays)
    ? schedule.weekdays.filter((day): day is number =>
      Number.isInteger(day) && day >= 1 && day <= 7
    )
    : [];
  const start = iso(schedule.starts_on);
  if (start === null || days.length === 0) return null;
  return `repeats ${days.map((day) => weekdayNames[day - 1]).join(" ")} since ${start}`;
}

function statOf(
  domain: BriefDomain,
  index: Json | null,
  localDate: string,
): string {
  if (index === null) return "counts unavailable";
  if (domain.id === "plan_ahead") {
    return scheduleStat(rec(index.schedule)) ?? "no active plan";
  }
  const records = recordsOf(rec(index.domains), domain.index);
  if (records === null) return "none yet";
  const span = records.first === records.last ? records.first : `${records.first}..${records.last}`;
  // A month-keyed kind has no day of its own to age.
  const age = domain.id === "apple_health" ? "" : `, last ${ageText(records.last, localDate)}`;
  return `${records.count} ${domain.unit} ${span}${age}`;
}

/** The brief for one index payload (null when the index could not be read). Exposed for tests. */
export function renderCoverageBrief(payload: unknown, localDate: string): string {
  const body = rec(payload);
  const index = typeof body.schema_version === "string" && body.schema_version.startsWith("1.")
    ? body
    : null;
  return [
    `What the athlete's records hold (today ${localDate}). Each line: kind | what the context above ` +
    "shows | what a lookup adds | what exists | kinds to check with it. A summary is not the detail behind it.",
    ...coverageDomains.map((domain) =>
      `- ${domain.id} | ${domain.shown} | ${domain.adds} | ${statOf(domain, index, localDate)} | ${
        domain.also.join(", ")
      }`
    ),
  ].join("\n");
}

export function createCoverageBriefContributor(source: StateSource): CoachContextContributor {
  return {
    id: coverageBriefContributorId,
    slot: "volatile",
    budgetChars: coverageBriefBudgetChars,
    async render(input) {
      let payload: unknown = null;
      try {
        payload = await source(input.userId, input.localDate);
      } catch {
        // The static map is still worth showing without the counts.
      }
      return renderCoverageBrief(payload, input.localDate);
    },
  };
}

export const coverageBriefContributor: CoachContextContributor = createCoverageBriefContributor(
  stateSourceFromRpc(coachServiceRpc, "get_coach_data_index_v1"),
);
