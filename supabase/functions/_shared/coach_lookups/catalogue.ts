// The catalogue of data lookups Coach may ask for while answering (A10). A lookup is a read-only,
// bounded query over one kind of the athlete's own records, served by a service-role RPC
// (migration 20261018100020_coach_data_lookups.sql). Coach names a lookup, a date range and a
// filter; this module validates the request, and nothing else reaches the database. The athlete's
// id is never part of a request: the Edge Function binds it from the authenticated call.
//
// This is not an agent. A request is a field of the JSON answer (`data_requests`), the server
// runs it, and the model is called again with the rows. At most `maxLookupRounds` rounds happen
// in one turn, at most `maxRequestsPerRound` lookups in a round, and nothing is ever written.
//
// The names are the closed enum of the structured-output schema (`dataRequestsJsonSchema`), whose
// bytes are fixed (coach_chat_schema_test.ts): a new kind of record is reached through a filter on
// an existing lookup, never a new name, so the schema is the same bytes as before.

export const maxLookupRounds = 2;
export const maxRequestsPerRound = 8;
/**
 * Most characters of rows one round adds to the prompt. A round of up to four lookups gets
 * `lookupResultMaxChars` each (render.ts); more are scaled down to share this total.
 */
export const maxRoundResultChars = 24_000;
export const maxLookupRangeDays = 400;
export const maxLookupFilterChars = 60;
/** How far past the coaching date a lookup that reads the plan's schedule may reach. */
export const maxScheduleAheadDays = 90;

export type CoachLookupSpec = Readonly<{
  name: string;
  /** The RPC the lookup calls: (p_user_id, p_from, p_to, p_filter). */
  rpc: string;
  /** What it returns, for the model. */
  summary: string;
  filter: "none" | "optional" | "required";
  /** What the filter means, for the model. Empty when the lookup takes none. */
  filterMeaning: string;
  /**
   * The filters that select a different set of records (a mode) and nothing else: the filter of a
   * lookup that has modes is empty or one of these, and a near miss ("proposal") is refused so the
   * model corrects it instead of silently getting the default records.
   */
  filterModes?: readonly string[];
  /**
   * Set on the one lookup that can see forward: with this filter the range may end up to
   * `maxScheduleAheadDays` after the coaching date. Every other request is cut at the coaching date.
   */
  reachesAheadWith?: string;
}>;

export const coachLookupCatalogue = [
  {
    name: "workouts",
    rpc: "coach_lookup_workouts_v1",
    summary:
      "completed sessions in the range (newest 15) with every exercise: planned sets and reps against the sets logged (reps, load, reps in reserve, effort, watch heart rate), pain flags, skipped exercises, substitutions, and the athlete's own session and exercise notes and swap reasons (the notes only where the athlete's accepted AI notice names them)",
    filter: "optional",
    filterMeaning: "an exercise name: only sessions and exercises that match",
  },
  {
    name: "exercise_history",
    rpc: "coach_lookup_exercise_history_v1",
    summary:
      "one exercise across the range: per session the heaviest set, estimated one-rep max, sets done and fewest reps in reserve; the plan's prescription and the next target",
    filter: "required",
    filterMeaning: "the exercise: its catalog slug or part of its name",
  },
  {
    name: "meals",
    rpc: "coach_lookup_meals_v1",
    summary:
      "nutrition by day (newest 60 days) marked complete or partial, and the meals with their foods (newest 30)",
    filter: "optional",
    filterMeaning: "a meal type (breakfast, lunch, dinner, snack) or part of a food name",
  },
  {
    name: "body",
    rpc: "coach_lookup_body_v1",
    summary: "body weight readings (newest 90) and tape measurements (newest 30)",
    filter: "none",
    filterMeaning: "",
  },
  {
    name: "check_ins",
    rpc: "coach_lookup_check_ins_v1",
    summary:
      "daily check-ins (newest 60): sleep, energy, soreness, hunger, mood, pain and the athlete's own note",
    filter: "none",
    filterMeaning: "",
  },
  {
    name: "recovery",
    rpc: "coach_lookup_recovery_v1",
    summary:
      "watch and recovery data by day (newest 60): sleep and its stages, resting heart rate, HRV (all day, night, morning), breathing rate (only where the athlete's accepted AI notice names it), steps, active energy, workout minutes, recovery score",
    filter: "none",
    filterMeaning: "",
  },
  {
    name: "plan_history",
    rpc: "coach_lookup_plan_history_v1",
    summary:
      "training plan versions (what was planned, when and why, newest 6) and nutrition target versions (newest 12); with the filter schedule, instead, the plan laid over the range day by day: the sessions planned for each date with their muscles, what was logged, and any muscle trained on consecutive days (the range may be in the past or up to " +
      maxScheduleAheadDays +
      " days ahead); with the filter proposals, instead, the changes Coach proposed in the range (newest 12) with why, and how the athlete answered",
    filter: "optional",
    filterMeaning:
      "schedule for the day-by-day schedule of the dates (use it for what is coming up, next week or any past week); proposals for the Coach proposals and the athlete's answers; empty for the plan versions and nutrition targets",
    filterModes: ["schedule", "proposals"],
    reachesAheadWith: "schedule",
  },
  {
    name: "goals",
    rpc: "coach_lookup_goals_v1",
    summary: "goals and their targets, and the health-check outcomes, in the range",
    filter: "none",
    filterMeaning: "",
  },
  {
    name: "weekly_reviews",
    rpc: "coach_lookup_weekly_reviews_v1",
    summary:
      "weekly reviews for weeks starting in the range (newest 12); with the filter decisions, instead, the daily coaching decisions of the days in the range (newest 30): the training action, the decision and its flags",
    filter: "optional",
    filterMeaning: "decisions for the past daily decisions; empty for the weekly reviews",
    filterModes: ["decisions"],
  },
  {
    name: "health_history",
    rpc: "coach_lookup_health_history_v1",
    summary:
      "the monthly Apple Health summary imported at onboarding: workouts, sleep, weight (newest 12 months); with the filter workouts, instead, the individual workouts the watch recorded in the range (newest 40, any age) with their length and whether a logged session matches them",
    filter: "optional",
    filterMeaning: "workouts for the watch workouts; empty for the monthly summary",
    filterModes: ["workouts"],
  },
  {
    name: "past_messages",
    rpc: "coach_lookup_past_messages_v1",
    summary:
      "the athlete's own earlier questions in conversations they let Coach remember, found by their words (12 at most), and Coach's own earlier replies on the same words (4 at most; what Coach said then, not a record, so check a claim in one against the records); use it when the notes are not enough to recall what was said",
    filter: "required",
    filterMeaning: 'the words to find, such as "knee pain"; any of them matches',
  },
] as const satisfies readonly CoachLookupSpec[];

export type CoachLookupName = typeof coachLookupCatalogue[number]["name"];

export const coachLookupNames: readonly CoachLookupName[] = coachLookupCatalogue.map((spec) =>
  spec.name
);

export function lookupSpec(name: string): CoachLookupSpec | undefined {
  return coachLookupCatalogue.find((spec) => spec.name === name);
}

export type DataRequest = Readonly<{
  lookup: CoachLookupName;
  /** First day of the range (YYYY-MM-DD). */
  from: string;
  /** Last day of the range (YYYY-MM-DD), never after the coaching date. */
  to: string;
  filter: string | null;
}>;

/**
 * The `data_requests` key of the gateway answer, for structured output. The key is always
 * present: an empty list means no request. Every field is required (Claude compiles a grammar
 * for each optional field), so `filter` is "" when the lookup takes none; validateDataRequests
 * reads "" as no filter. The range limits, the lookup's own needs and the date checks are the
 * validator's, not the schema's.
 */
export const dataRequestsJsonSchema = {
  type: "array",
  items: {
    type: "object",
    additionalProperties: false,
    properties: {
      lookup: { type: "string", enum: [...coachLookupNames] },
      from: { type: "string" },
      to: { type: "string" },
      filter: { type: "string" },
    },
    required: ["lookup", "from", "to", "filter"],
  },
} as const;

export type DataRequestsCheck =
  | Readonly<{ ok: true; requests: readonly DataRequest[] }>
  | Readonly<{ ok: false; reason: string }>;

const isoDate = /^\d{4}-\d{2}-\d{2}$/;
const filterText = /^[\p{L}\p{N}][\p{L}\p{N} '\-]*$/u;

/** Days since 1970-01-01 for a real calendar date in YYYY-MM-DD form, else null. */
export function dayNumber(value: unknown): number | null {
  if (typeof value !== "string" || !isoDate.test(value)) return null;
  const time = Date.parse(`${value}T00:00:00Z`);
  if (!Number.isFinite(time)) return null;
  const date = new Date(time);
  return date.toISOString().slice(0, 10) === value ? time / 86_400_000 : null;
}

/**
 * The requests in a model answer's `data_requests`, or the reason they are refused: an unknown
 * lookup or key, a malformed or oversized range, a range wholly in the future, a missing or
 * malformed filter, too many requests. A range that ends after the coaching date is cut to it (no
 * record can be newer), except the plan's schedule, which may reach `maxScheduleAheadDays` ahead.
 * A filter on a lookup that takes none is dropped. Repeats are merged.
 */
export function validateDataRequests(raw: unknown, localDate: string): DataRequestsCheck {
  const today = dayNumber(localDate);
  if (today === null) return { ok: false, reason: "coaching date unreadable" };
  if (!Array.isArray(raw) || raw.length === 0) {
    return { ok: false, reason: "data_requests must be a non-empty list" };
  }
  if (raw.length > maxRequestsPerRound) {
    return { ok: false, reason: `at most ${maxRequestsPerRound} requests per round` };
  }
  const requests: DataRequest[] = [];
  for (const item of raw) {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      return { ok: false, reason: "each request must be an object" };
    }
    const entry = item as Record<string, unknown>;
    if (Object.keys(entry).some((key) => !["lookup", "from", "to", "filter"].includes(key))) {
      return { ok: false, reason: "a request has a key other than lookup, from, to, filter" };
    }
    const spec = typeof entry.lookup === "string" ? lookupSpec(entry.lookup) : undefined;
    if (!spec) {
      return { ok: false, reason: `unknown lookup; use one of ${coachLookupNames.join(", ")}` };
    }
    const from = dayNumber(entry.from);
    const to = dayNumber(entry.to);
    if (from === null || to === null) {
      return { ok: false, reason: `${spec.name}: from and to must be dates as YYYY-MM-DD` };
    }
    if (from > to) return { ok: false, reason: `${spec.name}: from is after to` };
    if (to - from + 1 > maxLookupRangeDays) {
      return { ok: false, reason: `${spec.name}: a range is at most ${maxLookupRangeDays} days` };
    }
    let filter: string | null = null;
    if (spec.filter !== "none" && typeof entry.filter === "string" && entry.filter.trim() !== "") {
      const text = entry.filter.trim();
      if (text.length > maxLookupFilterChars || !filterText.test(text)) {
        return { ok: false, reason: `${spec.name}: the filter must be plain words` };
      }
      filter = text;
    }
    if (filter !== null && spec.filterModes) {
      const mode = filter.toLowerCase();
      if (!spec.filterModes.includes(mode)) {
        return {
          ok: false,
          reason: `${spec.name}: the filter must be ${
            spec.filterModes.join(" or ")
          }, or empty (${spec.filterMeaning})`,
        };
      }
      filter = mode;
    }
    if (spec.filter === "required" && filter === null) {
      return { ok: false, reason: `${spec.name}: a filter is required (${spec.filterMeaning})` };
    }
    const reachesAhead = spec.reachesAheadWith !== undefined &&
      filter?.toLowerCase() === spec.reachesAheadWith;
    const last = today + (reachesAhead ? maxScheduleAheadDays : 0);
    if (from > last) return { ok: false, reason: `${spec.name}: the range is in the future` };
    const clipped = new Date(Math.min(to, last) * 86_400_000).toISOString().slice(0, 10);
    const request: DataRequest = {
      lookup: spec.name as CoachLookupName,
      from: entry.from as string,
      to: clipped,
      filter,
    };
    if (!requests.some((seen) => JSON.stringify(seen) === JSON.stringify(request))) {
      requests.push(request);
    }
  }
  return { ok: true, requests };
}

/** The catalogue as the model reads it (the instructions and the data index). */
export function describeLookupCatalogue(): string {
  return coachLookupCatalogue.map((spec) => {
    const filter = spec.filter === "none" ? "" : ` Filter (${spec.filter}): ${spec.filterMeaning}.`;
    return `- ${spec.name}: ${spec.summary}.${filter}`;
  }).join("\n");
}
