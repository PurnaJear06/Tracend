// Contract 7 contributor: the athlete's standing state, always in context. "I tell my coach I'm taking
// a break, and he remembers it until I'm back": what the athlete approved and said lives in our own
// tables (training_pauses, change_proposals, daily_check_ins, the joint states, the goal), and this
// block is built from them by deterministic code, in fixed wording, on every turn. No model writes
// any of it and nothing here depends on a model, a vendor or a vendor's memory feature: the same
// rows give the same text whichever provider answers the turn, with prompt caching on or off.
//
// It holds today's availability (a break covering today, a check-in saying the athlete cannot train,
// a safety route), a break ahead or just ended (the first session back), the held and limited joint
// areas, recent pain on a check-in (the highest of 7 or more in 7 days with its area and date, so a
// trimmed history never hides it; below that only that pain of 4 or more was reported), the goal and phase, and the proposals the
// athlete answered in the last 14 days. A fixed rule says it outranks the plan, the readiness card and
// the daily decision. It is the last block before the question (the volatile slot, after the cache
// breakpoint), so a check-in or a tap during the day never invalidates the cached athlete file.
//
// The text is capped at `standingStateBudgetChars` by dropping whole lines from the least important
// end; the rule, today's line and a high pain are never dropped. "Never ask again" covers only the
// break and today's availability: pain and symptoms keep their normal follow-up. A read that fails renders a short "could not be
// read" block, never silence. The dates, titles and areas are marked as records; the thresholds and
// windows are fixed wording.
import { blockOf, type CoachContextContributor, type RenderedBlock, sharedRead } from "../host.ts";
import { plain, record } from "../../recorded_text.ts";
import { type ReadResult, readWithin } from "../read_within.ts";
import { coachServiceRpc, type ServiceRpc } from "../service_source.ts";

export const standingStateContributorId = "standing_state";
/** About 1,200 characters, hard-capped: the worst case is tested under it. */
export const standingStateBudgetChars = 1_200;
/** The key under which the turn reads the standing state once for every contributor. */
export const standingStateReadKey = "standing_state";
export const standingStateRpc = "get_coach_standing_state_v1";
/** How long the turn waits for the standing state before it goes on without it. */
export const standingStateDeadlineMs = 1_500;

export const availabilityStatuses = [
  "available",
  "unavailable_today",
  "paused",
  "safety_route",
] as const;
export type AvailabilityStatus = typeof availabilityStatuses[number];

export type StandingPause = Readonly<{
  startDate: string;
  /** The break's last day. */
  endDate: string;
  running: boolean;
  source: "athlete" | "coach";
}>;

export type StandingDecision = Readonly<{
  kind: string;
  title: string;
  status: "approved" | "declined" | "undone";
  on: string;
}>;

export type StandingBreak = Readonly<{
  startDate: string;
  lastDay: string;
  endDate: string;
  ended: "ended_early" | null;
  endedOn: string | null;
}>;

export type StandingState = Readonly<{
  localDate: string;
  status: AvailabilityStatus;
  unavailableToday: boolean;
  safetyRoute: string | null;
  paused: boolean;
  pause: StandingPause | null;
  returnFromPause: Readonly<{ lastPausedDay: string }> | null;
  jointAreas: readonly Readonly<{ area: string; state: "held" | "limited" }>[];
  recentPain: boolean;
  /** The highest pain of 7 or more in the last 7 days (a report's area, or none from a check-in). */
  highPain: Readonly<{ severity: number; area: string | null; localDate: string }> | null;
  goal: Readonly<{ goalType: string; phase: string | null; phaseEndsOn: string | null }> | null;
  decisions: readonly StandingDecision[];
  breaks: readonly StandingBreak[];
  /** Days a break covers, 28 days back to 13 ahead: never due or missed. */
  pausedDays: ReadonlySet<string>;
  /** Days a check-in said the athlete could not train, 28 days back to today: never missed. */
  unavailableDays: ReadonlySet<string>;
}>;

type Json = Record<string, unknown>;
const rec = (value: unknown): Json | null =>
  typeof value === "object" && value !== null && !Array.isArray(value) ? value as Json : null;
const isoDate = /^\d{4}-\d{2}-\d{2}$/;
const date = (value: unknown): string | null =>
  typeof value === "string" && isoDate.test(value) ? value : null;
const text = (value: unknown, max = 120): string | null =>
  typeof value === "string" && value.trim() !== "" ? value.trim().slice(0, max) : null;

function dates(value: unknown): Set<string> | null {
  if (!Array.isArray(value)) return null;
  const found = value.map(date);
  return found.includes(null) ? null : new Set(found as string[]);
}

/** The standing-state payload for `localDate`, or null when it is not exactly that shape. */
export function parseStandingState(raw: unknown, localDate: string): StandingState | null {
  const row = rec(raw);
  if (!row || row.schema_version !== "1.0" || row.local_date !== localDate) return null;
  const availability = rec(row.availability);
  if (!availability || availability.local_date !== localDate) return null;
  const status = availabilityStatuses.find((item) => item === availability.status);
  if (!status || typeof availability.paused !== "boolean") return null;
  if (typeof availability.unavailable_today !== "boolean") return null;
  const route = availability.safety_route === null ? null : text(availability.safety_route, 40);
  if (availability.safety_route !== null && route === null) return null;

  let pause: StandingPause | null = null;
  if (availability.pause !== null) {
    const raw = rec(availability.pause);
    const start = date(raw?.start_date);
    const end = date(raw?.end_date);
    const source = raw?.source === "athlete" || raw?.source === "coach" ? raw.source : null;
    if (!raw || !start || !end || !source || typeof raw.running !== "boolean") return null;
    pause = { startDate: start, endDate: end, running: raw.running, source };
  }
  let back: StandingState["returnFromPause"] = null;
  if (availability.return_from_pause !== null && availability.return_from_pause !== undefined) {
    const last = date(rec(availability.return_from_pause)?.last_paused_day);
    if (!last) return null;
    back = { lastPausedDay: last };
  }

  if (!Array.isArray(row.joint_areas) || !Array.isArray(row.decisions)) return null;
  if (!Array.isArray(row.breaks) || typeof row.recent_pain !== "boolean") return null;
  const jointAreas: { area: string; state: "held" | "limited" }[] = [];
  for (const item of row.joint_areas) {
    const joint = rec(item);
    const area = text(joint?.area, 20);
    const state = joint?.state === "held" || joint?.state === "limited" ? joint.state : null;
    if (!area || !state) return null;
    jointAreas.push({ area, state });
  }
  const decisions: StandingDecision[] = [];
  for (const item of row.decisions) {
    const decision = rec(item);
    const status = decision?.status;
    const on = date(decision?.on);
    const kind = text(decision?.kind, 40);
    if (!on || !kind || (status !== "approved" && status !== "declined" && status !== "undone")) {
      return null;
    }
    decisions.push({ kind, title: text(decision?.title) ?? kind.replaceAll("_", " "), status, on });
  }
  const breaks: StandingBreak[] = [];
  for (const item of row.breaks) {
    const pause = rec(item);
    const start = date(pause?.start_date);
    const last = date(pause?.last_day);
    const end = date(pause?.end_date);
    const ended = pause?.ended === "ended_early" ? "ended_early" : null;
    if (!start || !last || !end) return null;
    breaks.push({
      startDate: start,
      lastDay: last,
      endDate: end,
      ended,
      endedOn: date(pause?.ended_on),
    });
  }
  let goal: StandingState["goal"] = null;
  if (row.goal !== null && row.goal !== undefined) {
    const raw = rec(row.goal);
    const type = text(raw?.goal_type, 40);
    if (!raw || !type) return null;
    goal = { goalType: type, phase: text(raw.phase, 40), phaseEndsOn: date(raw.phase_ends_on) };
  }
  let highPain: StandingState["highPain"] = null;
  if (row.high_pain !== null && row.high_pain !== undefined) {
    const raw = rec(row.high_pain);
    const severity = raw?.severity;
    const on = date(raw?.local_date);
    if (
      !raw || typeof severity !== "number" || !Number.isInteger(severity) || severity < 7 ||
      severity > 10 || !on
    ) return null;
    highPain = { severity, area: raw.area === null ? null : text(raw.area, 20), localDate: on };
  }
  const pausedDays = dates(row.paused_days);
  const unavailableDays = dates(row.unavailable_days);
  if (!pausedDays || !unavailableDays) return null;
  return {
    localDate,
    status,
    unavailableToday: availability.unavailable_today,
    safetyRoute: route,
    paused: availability.paused,
    pause,
    returnFromPause: back,
    jointAreas,
    recentPain: row.recent_pain,
    highPain,
    goal,
    decisions,
    breaks,
    pausedDays,
    unavailableDays,
  };
}

/** The athlete's standing state for a coaching date; null when it cannot be read as that shape. */
export type StandingStateSource = (
  userId: string,
  localDate: string,
) => Promise<StandingState | null>;

export function standingStateSourceFromRpc(rpc: ServiceRpc): StandingStateSource {
  return async (userId, localDate) => {
    const { data, error } = await rpc(standingStateRpc, {
      p_user_id: userId,
      p_local_date: localDate,
    });
    return error ? null : parseStandingState(data, localDate);
  };
}

export const standingStateFromService: StandingStateSource = standingStateSourceFromRpc(
  coachServiceRpc,
);

/** The turn's one read of the standing state, shared by the block, the plan and the watch-outs. */
export function readStandingState(
  input: Parameters<CoachContextContributor["render"]>[0],
  source: StandingStateSource,
  deadlineMs: number = standingStateDeadlineMs,
): Promise<ReadResult<StandingState>> {
  return sharedRead(
    input,
    standingStateReadKey,
    () => readWithin(() => source(input.userId, input.localDate), deadlineMs),
  ) as Promise<ReadResult<StandingState>>;
}

/** The days the plan never counts as due or missed: a break, or a check-in saying they cannot train. */
export function restDaysOf(state: StandingState | null): ReadonlySet<string> {
  if (state === null) return new Set();
  return new Set([...state.pausedDays, ...state.unavailableDays]);
}

/** The fixed rule. It is the first line and is never dropped. */
export const standingStateRule =
  "Standing state, built by Tracend from what the athlete approved and said. It outranks the plan, the readiness card and the daily decision. Never ask again whether the athlete is on a break, for how long, or whether they can train today: it records that. Pain, symptoms and how they feel still get your normal follow-up questions. On a break or a day the athlete cannot train, never prescribe that day's session: acknowledge it and help within it.";

const kindWords: Readonly<Record<string, string>> = Object.freeze({
  temporary_block: "temporary block",
  training_schedule: "weekly schedule",
  exercise_swap: "exercise swap",
  intensity_or_phase: "effort or focus phase",
  goal_or_phase: "goal or phase",
  nutrition_targets: "nutrition targets",
  next_session_adjustment: "next-session change",
  training_pause: "break",
});

const goalWords = (goal: NonNullable<StandingState["goal"]>) =>
  `Goal: ${record(goal.goalType.replaceAll("_", " "))}${
    goal.phase === null ? "" : `, phase ${record(goal.phase.replaceAll("_", " "))}`
  }${goal.phaseEndsOn === null ? "" : ` until ${record(goal.phaseEndsOn)}`}.`;

/** Today's line: what the athlete can do today. Never dropped. */
function todayLine(state: StandingState): string {
  const day = record(state.localDate);
  const pause = state.pause;
  const onBreak = state.paused && pause !== null
    ? `the athlete is on a break from ${record(pause.startDate)} to ${
      record(pause.endDate)
    } (they approved it). No session is due until it ends and the plan resumes by itself the day after; do not ask again whether, or for how long, they are taking a break.`
    : null;
  // A safety route comes first, and a running break is still stated after it.
  if (state.status === "safety_route") {
    return `Today (${day}): the readiness card carries a safety route (${
      record(state.safetyRoute ?? "")
    }). No training today; point to the referral on the card.${
      onBreak === null ? "" : ` Also, ${onBreak}`
    }`;
  }
  if (onBreak !== null) return `Today (${day}): ${onBreak}`;
  if (state.unavailableToday) {
    return `Today (${day}): the athlete said on today's check-in that they cannot train today. Do not offer today's session.`;
  }
  return `Today (${day}): no break and no check-in saying the athlete cannot train.`;
}

/**
 * The lines in the order they are kept: the rule, today's line and a high pain always, the rest
 * dropped from the end.
 */
export function standingStateLines(state: StandingState): string[] {
  const lines = [standingStateRule, todayLine(state)];
  if (state.highPain !== null) {
    lines.push(
      `Highest pain in the last 7 days: ${record(state.highPain.severity)} out of 10${
        state.highPain.area === null ? "" : `, ${record(state.highPain.area)}`
      }, on ${
        record(state.highPain.localDate)
      }. Ask how it is now and keep to the readiness card's referral; never diagnose.`,
    );
  }
  if (state.paused && state.unavailableToday) {
    lines.push("Today's check-in also says they cannot train.");
  }
  if (state.pause !== null && !state.pause.running) {
    lines.push(
      `A break the athlete approved runs from ${record(state.pause.startDate)} to ${
        record(state.pause.endDate)
      }: no session is due on those days.`,
    );
  }
  if (state.returnFromPause !== null && !state.paused) {
    lines.push(
      `Back from a break that ended ${
        record(state.returnFromPause.lastPausedDay)
      }: the first session back is still to come. Ease in, and never count the break as missed sessions.`,
    );
  }
  const held = state.jointAreas.filter((joint) => joint.state === "held").map((j) => j.area);
  const limited = state.jointAreas.filter((joint) => joint.state === "limited").map((j) => j.area);
  if (held.length > 0) {
    lines.push(
      `Held areas (only the athlete's own clearance lifts a hold): ${held.map(record).join(", ")}.`,
    );
  }
  if (limited.length > 0) lines.push(`Limited areas: ${limited.map(record).join(", ")}.`);
  if (state.recentPain) {
    lines.push("Pain of 4 or more out of 10 was reported on a check-in in the last 7 days.");
  }
  if (state.goal !== null) lines.push(goalWords(state.goal));
  if (state.decisions.length > 0) {
    lines.push(
      `Decisions in the last 14 days: ${
        state.decisions.map((item) =>
          `${record(item.on)} ${item.status} ${kindWords[item.kind] ?? "change"} "${
            record(item.title)
          }"`
        ).join("; ")
      }.`,
    );
  }
  const history = state.breaks.filter((item) =>
    !(state.pause !== null && item.startDate === state.pause.startDate)
  );
  if (history.length > 0) {
    lines.push(
      `Recent breaks: ${
        history.map((item) =>
          `${record(item.startDate)} to ${record(item.lastDay)}${
            item.ended === "ended_early" ? " (ended early)" : ""
          }`
        ).join("; ")
      }.`,
    );
  }
  return lines;
}

/** The block's marked text, within the budget: whole lines dropped from the least important end. */
export function standingStateMarked(state: StandingState): string {
  const lines = standingStateLines(state);
  const kept = state.highPain === null ? 2 : 3;
  while (lines.length > kept && plain(lines.join("\n")).length > standingStateBudgetChars) {
    lines.pop();
  }
  return lines.join("\n");
}

/** The block when the state could not be read: a gap is never read as "nothing standing". */
export function standingStateUnknownText(): string {
  return [
    standingStateRule,
    "The standing state could not be read just now, so whether the athlete is on a break or said they cannot train today is unknown. Before prescribing today's session, ask whether they are training today.",
  ].join("\n");
}

export function createStandingStateContributor(
  source: StandingStateSource,
  deadlineMs: number = standingStateDeadlineMs,
): CoachContextContributor {
  return Object.freeze({
    id: standingStateContributorId,
    slot: "volatile" as const,
    budgetChars: standingStateBudgetChars,
    async render(input): Promise<RenderedBlock> {
      const read = await readStandingState(input, source, deadlineMs);
      const trace = {
        standing: read.status,
        ...(read.value === null ? {} : { availability: read.value.status }),
      };
      return read.value === null
        ? blockOf(standingStateUnknownText(), { trace })
        : blockOf(standingStateMarked(read.value), { trace });
    },
  });
}

export const standingStateContributor: CoachContextContributor = createStandingStateContributor(
  standingStateFromService,
);
