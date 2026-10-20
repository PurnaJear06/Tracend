// Contract 7 contributor (the Coach investigates first): watch-outs. Facts computed by code from
// several kinds of the athlete's records at once, so Coach does not have to notice them by
// reading lists side by side (a model with thinking off does not): back-to-back sessions that
// load the same muscles, a session due today or tomorrow on a bad recovery day, sessions behind
// the plan, the same session or exercise skipped again and again, a pain flag on an exercise that
// is planned again, resting heart rate or HRV off the athlete's own usual, a weigh-in or an Apple
// Health sync gone stale, and a plan that has outlived its block.
//
// Every line states what was found with its dates and the figures it was computed from, so the
// numbers check can ground a reply on it; none is a conclusion about what to do. Nothing is shown
// when nothing is found. A threshold is always one Tracend already uses somewhere else, and the
// table below says where; none is chosen here for this block.
//
// Inputs: the plan state (get_coach_plan_state_v1, shared with the training plan block), the facts
// of get_coach_watch_outs_v1 and the plan laid over the last four weeks (plan_history, filter
// schedule). Any one of them may fail; the lines that need it are then left out.
import { goalPhaseThresholds } from "../../training/goal_phase/thresholds.ts";
import { addDays, dayOf, overlapFactLine, stamp } from "../../training/schedule/week_ahead.ts";
import { readScheduleBody, type ScheduleBody } from "../../training/schedule/lookup_body.ts";
import { type CoachContextContributor, sharedRead } from "../host.ts";
import {
  coachServiceRpc,
  type ServiceRpc,
  type StateSource,
  stateSourceFromRpc,
} from "../service_source.ts";
import {
  parsePlanState,
  pickFocusSession,
  type PlanState,
  planStateReadKey,
  sessionsOn,
  weekAheadOf,
} from "./training_plan.ts";

export const watchOutsContributorId = "watch_outs";
export const watchOutsBudgetChars = 1_200;
/** At most this many lines, and at most this many characters of lines (`watchOutsLinesRoom` is what the introduction leaves of the budget). */
export const watchOutsMaxLines = 8;
export const watchOutsLinesMaxChars = 900;
/** How many days back the planned sessions are checked for repeated misses. */
export const missedLookbackDays = 28;

/**
 * Each threshold and where it comes from. Nothing here is new: a number that decides a watch-out
 * is one the product already uses to decide the same thing for the athlete.
 */
export const watchOutThresholds = Object.freeze({
  /** RECOVERY_BELOW_BASELINE: recovery score < 40 (daily_decision_provider.ts, evidenceCodeReference). */
  recoveryScoreBelow: 40,
  /** SLEEP_QUALITY_POOR: sleep quality score < 50 (the same table). */
  sleepQualityBelow: 50,
  /**
   * Resting heart rate or HRV one spread or more from the athlete's baseline reads "higher than
   * usual" or "lower than usual" in the app (driverComparison in recovery_readout_card.dart: inside
   * one spread is "normal for you", two or more is "much"). The z-scores are the recovery engine's own.
   */
  driftSpreads: 1,
  /**
   * A weigh-in older than 14 days is stale: the goal phase gives no rate then (ALGORITHMS.md, B7).
   * The goal phase counts days between the reading's date and today, and so does this: a weigh-in
   * has a date and no time. (The plan's age is also in whole days: no product rule measures it.)
   */
  weighInStaleDays: goalPhaseThresholds.staleReadingDays.value,
  /** Apple Health is stale after more than 2 days (deriveHealthConnectionState in health_models.dart). */
  healthSyncStaleDays: 2,
  /** The app's rule in milliseconds: elapsed time since the last successful sync is more than this (strictly), as `now.difference(last) > Duration(days: 2)`. */
  healthSyncStaleMs: 2 * 86_400_000,
  /** "Repeated" is twice running: the same exercise skipped in each of its last two sessions, the same session missed on its last two planned days. */
  repeatedTimes: 2,
});

type Json = Record<string, unknown>;
const rec = (value: unknown): Json =>
  value && typeof value === "object" && !Array.isArray(value) ? value as Json : {};
const list = (value: unknown): Json[] => Array.isArray(value) ? value.map(rec) : [];
const num = (value: unknown): number | null => {
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return typeof value === "number" && Number.isFinite(value) ? value : null;
};
const str = (value: unknown): string => typeof value === "string" ? value : "";
const day = (value: unknown): string | null => {
  const text = str(value).slice(0, 10);
  return /^\d{4}-\d{2}-\d{2}$/.test(text) ? text : null;
};

const instant = (value: unknown): number | null => {
  const time = typeof value === "string" ? Date.parse(value) : NaN;
  return Number.isFinite(time) ? time : null;
};
const syncOf = (row: Json): WatchFacts["healthSync"] => {
  const at = instant(row.at);
  const localDate = day(row.local_date);
  return at === null || localDate === null ? null : { at, localDate };
};

/** The facts of one get_coach_watch_outs_v1 payload. */
export type WatchFacts = Readonly<{
  localDate: string;
  sleep: Readonly<{ date: string; minutes: number }> | null;
  metrics:
    | Readonly<{
      date: string;
      recoveryScore: number | null;
      sleepQuality: number | null;
      hrvZ: number | null;
      rhrZ: number | null;
      missing: readonly string[];
    }>
    | null;
  checkIn: Readonly<{ date: string; pain: number | null }> | null;
  painFlags: readonly Readonly<{ date: string; name: string; slug: string | null }>[];
  skipped: readonly Readonly<{ name: string; sessions: number; lastDate: string }>[];
  weighIn: string | null;
  /** The last successful sync: its moment (milliseconds) and the athlete's local day. */
  healthSync: Readonly<{ at: number; localDate: string }> | null;
  /** The database's now when the facts were read, for elapsed-time rules. */
  asOf: number | null;
  plan:
    | Readonly<{
      version: number | null;
      startsOn: string;
      blockWeeks: number | null;
      temporary: boolean;
    }>
    | null;
}>;

export function parseWatchFacts(payload: unknown): WatchFacts | null {
  const body = rec(payload);
  if (!str(body.schema_version).startsWith("1.")) return null;
  const localDate = day(body.local_date);
  if (localDate === null) return null;
  const sleep = rec(body.sleep);
  const metrics = rec(body.metrics);
  const checkIn = rec(body.check_in);
  const plan = rec(body.plan);
  const sleepDate = day(sleep.local_date);
  const sleepMinutes = num(sleep.minutes);
  const metricsDate = day(metrics.local_date);
  const checkInDate = day(checkIn.local_date);
  const startsOn = day(plan.starts_on);
  return {
    localDate,
    sleep: sleepDate !== null && sleepMinutes !== null
      ? { date: sleepDate, minutes: sleepMinutes }
      : null,
    metrics: metricsDate === null ? null : {
      date: metricsDate,
      recoveryScore: num(metrics.recovery_score),
      sleepQuality: num(metrics.sleep_quality_score),
      hrvZ: num(metrics.hrv_z),
      rhrZ: num(metrics.rhr_z),
      missing: Array.isArray(metrics.missing_components)
        ? metrics.missing_components.filter((item): item is string => typeof item === "string")
        : [],
    },
    checkIn: checkInDate === null ? null : { date: checkInDate, pain: num(checkIn.pain_severity) },
    painFlags: list(body.pain_flags).flatMap((row) => {
      const date = day(row.local_date);
      return date === null || str(row.name) === ""
        ? []
        : [{ date, name: str(row.name), slug: str(row.slug) || null }];
    }),
    skipped: list(body.skipped).flatMap((row) => {
      const lastDate = day(row.last_date);
      const sessions = num(row.sessions);
      return lastDate === null || sessions === null || str(row.name) === ""
        ? []
        : [{ name: str(row.name), sessions, lastDate }];
    }),
    weighIn: day(rec(body.weigh_in).local_date),
    healthSync: syncOf(rec(body.health_sync)),
    asOf: instant(body.as_of),
    plan: startsOn === null ? null : {
      version: num(plan.version),
      startsOn,
      blockWeeks: num(plan.block_weeks),
      temporary: day(plan.ends_on) !== null,
    },
  };
}

/** What the watch-outs are computed from. Each part is null when its read failed. */
export type WatchOutInputs = Readonly<{
  plan: PlanState | null;
  facts: WatchFacts | null;
  schedule: ScheduleBody | null;
}>;

const oneDecimal = (value: number) => (Math.round(value * 10) / 10).toFixed(1);
const join = (items: readonly string[]) =>
  items.length <= 1 ? items.join("") : `${items.slice(0, -1).join(", ")} and ${items.at(-1)}`;

/** Sessions on the plan for today and tomorrow that are not done, by offset. */
function dueSessions(
  plan: PlanState,
): { offset: number; date: string; weekday: number; name: string }[] {
  const week = weekAheadOf(plan);
  return week.days.filter((item) => item.offset === 0 || item.offset === 1).flatMap((item) =>
    item.sessions.filter((session) => session.kind !== "done").map((session) => ({
      offset: item.offset,
      date: item.date,
      weekday: item.weekday,
      name: session.name,
    }))
  );
}

function loadCheck(plan: PlanState, facts: WatchFacts): string | null {
  const due = dueSessions(plan);
  if (due.length === 0) return null;
  const reasons: string[] = [];
  const m = facts.metrics;
  if (m?.recoveryScore != null && m.recoveryScore < watchOutThresholds.recoveryScoreBelow) {
    reasons.push(
      `recovery score ${m.recoveryScore} on ${m.date} (below ${watchOutThresholds.recoveryScoreBelow})`,
    );
  }
  if (m?.sleepQuality != null && m.sleepQuality < watchOutThresholds.sleepQualityBelow) {
    const slept = facts.sleep !== null && Math.abs(dayOf(facts.sleep.date) - dayOf(m.date)) <= 1
      ? `, ${facts.sleep.minutes} min asleep on ${facts.sleep.date}`
      : "";
    reasons.push(
      `sleep quality score ${m.sleepQuality} on ${m.date} (below ${watchOutThresholds.sleepQualityBelow}${slept})`,
    );
  }
  const pain = facts.checkIn;
  if (pain?.pain != null && pain.pain > 0) {
    reasons.push(`check-in pain ${pain.pain}/10 on ${pain.date}`);
  }
  if (reasons.length === 0) return null;
  const when = due.map((item) =>
    `${item.name} ${item.offset === 0 ? "today" : "tomorrow"} (${stamp(item)})`
  );
  return `Due ${join(when)}, with ${reasons.join("; ")}.`;
}

/** A pain-flagged exercise that a session in the next seven days holds again. */
function painPlannedAgain(plan: PlanState, facts: WatchFacts): string | null {
  const flagged = new Map<string, { name: string; date: string }>();
  for (const flag of facts.painFlags) {
    if (flag.slug !== null && !flagged.has(flag.slug)) {
      flagged.set(flag.slug, { name: flag.name, date: flag.date });
    }
  }
  if (flagged.size === 0) return null;
  const found: string[] = [];
  for (let offset = 0; offset < 7 && found.length < 2; offset += 1) {
    const date = addDays(plan.localDate, offset);
    const weekday = ((plan.weekday - 1 + offset) % 7) + 1;
    for (const session of sessionsOn(plan, offset).planned) {
      for (const exercise of session.exercises) {
        const flag = exercise.slug === null ? undefined : flagged.get(exercise.slug);
        if (flag) {
          flagged.delete(exercise.slug!);
          found.push(
            `${flag.name} (pain flagged on ${flag.date}) is planned again in ${session.name} on ${
              stamp({ weekday, date })
            }`,
          );
        }
      }
    }
  }
  return found.length === 0 ? null : `${found.join("; ")}.`;
}

function behindPlan(plan: PlanState): string | null {
  const { undone } = pickFocusSession(plan);
  if (undone.length === 0) return null;
  const names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
  const missed = undone.map((session) =>
    `${session.name} (${session.weekday === null ? "no set day" : names[session.weekday - 1]})`
  );
  const done = plan.completed.map((row) => row.localDate);
  return `Behind plan this week: ${join(missed)} not done, planned for days already past; ${
    done.length
      ? `${done.length} finished since Monday (${join(done)})`
      : "none finished since Monday"
  }.`;
}

/**
 * The same session missed on each of its last planned days. A session is the planned workout (its
 * id), not its name: two workouts can share a name (the plan supports it), and each has its own
 * streak. The name is only what the line says.
 */
function missedSessions(schedule: ScheduleBody): string | null {
  const byWorkout = new Map<string, { name: string; rows: { date: string; missed: boolean }[] }>();
  // Only days planned under the plan in force now: a session of an older plan is not one the
  // athlete is skipping today. Without a plan in force nothing is claimed.
  if (schedule.planId === null) return null;
  const note = (id: string, name: string, date: string, missed: boolean) => {
    const entry = byWorkout.get(id) ?? { name, rows: [] };
    entry.rows.push({ date, missed });
    byWorkout.set(id, entry);
  };
  for (const row of schedule.days) {
    if (row.versionId !== schedule.planId) continue;
    if (dayOf(row.date) >= dayOf(schedule.today)) continue;
    for (const item of row.planned) note(item.id, item.name, row.date, !item.logged);
    // A workout done on a day it was not planned for answers its own streak (it was made up).
    for (const item of row.done) {
      if (schedule.currentWorkoutIds.has(item.id) && !row.planned.some((p) => p.id === item.id)) {
        note(item.id, item.name, row.date, false);
      }
    }
  }
  const streaks = [...byWorkout.values()].flatMap(({ name, rows }) => {
    const newestFirst = [...rows].sort((a, b) => b.date.localeCompare(a.date));
    const lead = newestFirst.findIndex((row) => !row.missed);
    const missed = (lead === -1 ? newestFirst : newestFirst.slice(0, lead)).map((row) => row.date);
    return missed.length >= watchOutThresholds.repeatedTimes
      ? [{ name, dates: missed.slice(0, 3), last: missed[0] }]
      : [];
  }).sort((a, b) => b.last.localeCompare(a.last)).slice(0, 2);
  if (streaks.length === 0) return null;
  return `Planned but not logged on each of its last days: ${
    streaks.map((item) => `${item.name} (${join(item.dates.toReversed())})`).join("; ")
  }.`;
}

function skippedExercises(facts: WatchFacts): string | null {
  const rows = facts.skipped.filter((row) => row.sessions >= watchOutThresholds.repeatedTimes)
    .slice(0, 3);
  if (rows.length === 0) return null;
  return `Skipped in each of its last sessions: ${
    rows.map((row) => `${row.name} (${row.sessions} in a row, last ${row.lastDate})`).join("; ")
  }.`;
}

function drift(facts: WatchFacts): string | null {
  const m = facts.metrics;
  if (m === null) return null;
  const spreads = watchOutThresholds.driftSpreads;
  const parts: string[] = [];
  if (m.rhrZ !== null && !m.missing.includes("resting_hr") && m.rhrZ <= -spreads) {
    parts.push(`resting heart rate is ${oneDecimal(-m.rhrZ)} spreads above their usual`);
  }
  if (m.hrvZ !== null && !m.missing.includes("hrv_sdnn") && m.hrvZ <= -spreads) {
    parts.push(`HRV is ${oneDecimal(-m.hrvZ)} spreads below their usual`);
  }
  if (parts.length === 0) return null;
  return `On ${m.date}, ${
    parts.join(" and ")
  } (the recovery score's z-scores; the app calls one spread "than usual").`;
}

function staleWeighIn(facts: WatchFacts): string | null {
  if (facts.weighIn === null) return null;
  const days = dayOf(facts.localDate) - dayOf(facts.weighIn);
  if (days <= watchOutThresholds.weighInStaleDays) return null;
  return `Last weigh-in was ${facts.weighIn}, ${days} days ago (older than ${watchOutThresholds.weighInStaleDays} days, so no weight trend is current).`;
}

function staleSync(facts: WatchFacts): string | null {
  if (facts.healthSync === null || facts.asOf === null) return null;
  // Elapsed time, as the app measures it: a sync at 00:01 is stale at 00:02 two days later, not at
  // the end of that day.
  const elapsed = facts.asOf - facts.healthSync.at;
  if (elapsed <= watchOutThresholds.healthSyncStaleMs) return null;
  const days = Math.floor(elapsed / 86_400_000);
  return `Apple Health last synced on ${facts.healthSync.localDate}, ${days} days ago (the app calls more than ${watchOutThresholds.healthSyncStaleDays} days stale), so recent sleep and recovery rows may be missing.`;
}

function planAge(facts: WatchFacts): string | null {
  const plan = facts.plan;
  if (plan === null || plan.temporary || plan.blockWeeks === null) return null;
  const weeks = Math.floor((dayOf(facts.localDate) - dayOf(plan.startsOn)) / 7);
  if (weeks < plan.blockWeeks) return null;
  return `The current plan${
    plan.version === null ? "" : ` (v${plan.version})`
  } has run since ${plan.startsOn}, ${weeks} weeks; its block is ${plan.blockWeeks} weeks.`;
}

const introduction =
  "Watch-outs: facts Tracend calculated across the athlete's records. Each is verified from the dates and figures it states. Address each that bears on the question, or say why it does not matter. A change to the plan is a proposal the athlete approves.";

/**
 * Characters the lines may take: at most `watchOutsLinesMaxChars`, and what the contributor's
 * budget leaves after the introduction, so the host never has to cut a line.
 */
export const watchOutsLinesRoom = Math.min(
  watchOutsLinesMaxChars,
  watchOutsBudgetChars - introduction.length,
);

/** One watch-out: its line, and whether it bears on a training decision or only on the data. */
export type WatchOut = Readonly<{ line: string; kind: "decision" | "data" }>;

/**
 * The watch-outs, most important first: back-to-back muscles, a session due on a bad day, a pain
 * flag planned again, behind plan, repeated skips, drift (all training decisions), then stale
 * inputs and plan age (the data). At most `watchOutsMaxLines` lines and `watchOutsLinesMaxChars`
 * characters; a line that would pass either limit is left out, never cut.
 */
export function computeWatchOuts(inputs: WatchOutInputs): WatchOut[] {
  const { plan, facts, schedule } = inputs;
  const candidates: (readonly [string | null, WatchOut["kind"]])[] = [
    [plan === null ? null : overlapFactLine(weekAheadOf(plan).overlaps), "decision"],
    [plan === null || facts === null ? null : loadCheck(plan, facts), "decision"],
    [plan === null || facts === null ? null : painPlannedAgain(plan, facts), "decision"],
    [plan === null ? null : behindPlan(plan), "decision"],
    [schedule === null ? null : missedSessions(schedule), "decision"],
    [facts === null ? null : skippedExercises(facts), "decision"],
    [facts === null ? null : drift(facts), "decision"],
    [facts === null ? null : staleWeighIn(facts), "data"],
    [facts === null ? null : staleSync(facts), "data"],
    [facts === null ? null : planAge(facts), "data"],
  ];
  const found: WatchOut[] = [];
  let used = 0;
  for (const [text, kind] of candidates) {
    if (text === null) continue;
    const line = `- ${text}`;
    // Strict priority: when a line does not fit, nothing less important takes its place.
    if (found.length >= watchOutsMaxLines || used + line.length + 1 > watchOutsLinesRoom) break;
    found.push({ line, kind });
    used += line.length + 1;
  }
  return found;
}

/** The block's text, or null when there is nothing to watch. Exposed for tests. */
export function renderWatchOuts(inputs: WatchOutInputs): string | null {
  const found = computeWatchOuts(inputs);
  return found.length === 0 ? null : [introduction, ...found.map((item) => item.line)].join("\n");
}

/**
 * Whether pain is on record (today's or yesterday's check-in, or an exercise flagged in 14 days),
 * or null when the facts could not be read: the route treats an unknown as pain.
 */
export function painOnRecord(facts: WatchFacts | null): boolean | null {
  return facts === null ? null : (facts.checkIn?.pain ?? 0) > 0 || facts.painFlags.length > 0;
}

/** Where the contributor reads from; each is a service-role read. */
export type WatchOutSources = Readonly<{
  planState: StateSource;
  facts: StateSource;
  schedule: StateSource;
}>;

/**
 * How long the facts and the schedule may take: inside the host's limit, so the lines that need
 * only the plan (the back-to-back muscles) survive a slow second read.
 */
export const watchOutsSecondaryTimeoutMs = 2_500;

function within<T>(read: Promise<T>, ms: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  return Promise.race([
    read,
    new Promise<never>((_, reject) => {
      timer = setTimeout(() => reject(new Error("watch-outs read timed out")), ms);
    }),
  ]).finally(() => clearTimeout(timer));
}

export function createWatchOutsContributor(
  sources: WatchOutSources,
  secondaryTimeoutMs: number = watchOutsSecondaryTimeoutMs,
): CoachContextContributor {
  return {
    id: watchOutsContributorId,
    slot: "volatile",
    budgetChars: watchOutsBudgetChars,
    async render(input) {
      const [plan, facts, schedule] = await Promise.allSettled([
        sharedRead(input, planStateReadKey, () => sources.planState(input.userId, input.localDate)),
        within(sources.facts(input.userId, input.localDate), secondaryTimeoutMs),
        within(sources.schedule(input.userId, input.localDate), secondaryTimeoutMs),
      ]);
      const ok = <T>(result: PromiseSettledResult<unknown>, parse: (value: unknown) => T | null) =>
        result.status === "fulfilled" ? parse(result.value) : null;
      const inputs: WatchOutInputs = {
        plan: ok(plan, parsePlanState),
        facts: ok(facts, parseWatchFacts),
        schedule: ok(
          schedule,
          (value) => Object.keys(rec(value)).length === 0 ? null : readScheduleBody(value),
        ),
      };
      const found = computeWatchOuts(inputs);
      // The counts go to the route (coach_chat_provider_route.ts) whether or not there is text to
      // show: a turn with nothing to watch still says whether pain is on record. No text, no figure.
      return {
        text: found.length === 0
          ? ""
          : [introduction, ...found.map((item) => item.line)].join("\n"),
        shown: {},
        trace: {
          lines: found.length,
          decisions: found.filter((item) => item.kind === "decision").length,
          pain: painOnRecord(inputs.facts),
        },
      };
    },
  };
}

/** The plan laid over the last `missedLookbackDays` days before the coaching date. */
export function scheduleSourceFromRpc(rpc: ServiceRpc): StateSource {
  return async (userId, localDate) => {
    const { data, error } = await rpc("coach_lookup_plan_history_v1", {
      p_user_id: userId,
      p_from: addDays(localDate, -missedLookbackDays),
      p_to: addDays(localDate, -1),
      p_filter: "schedule",
    });
    if (error) throw new Error("coach_lookup_plan_history_v1 unavailable");
    return data;
  };
}

export const watchOutsContributor: CoachContextContributor = createWatchOutsContributor({
  planState: stateSourceFromRpc(coachServiceRpc, "get_coach_plan_state_v1"),
  facts: stateSourceFromRpc(coachServiceRpc, "get_coach_watch_outs_v1"),
  schedule: scheduleSourceFromRpc(coachServiceRpc),
});
