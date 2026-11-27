// Contract 7 contributor: the athlete's menstrual cycle (cycle support v1, 2026-11-27). The cycle
// day, phase, expected range, confidence and flags are Tracend's calculation
// (`private.cycle_state`, read through `coach_cycle_state_v1`); the status is the athlete's own
// answer and the days are what they logged or allowed from Apple Health. A model never works any
// of it out.
//
// It reaches the AI only under an accepted notice that names cycle data (`cycle_data`,
// ai_notice_coverage.ts): without the scope the contributor reads nothing and renders nothing, so
// an athlete on an earlier notice gets exactly the turn they got before, with no line saying data
// was held back. With the scope and tracking off it renders nothing either.
//
// The cycle explains, it never applies: the block's fixed rules say the evidence does not support
// changing training or food by phase, what shifts are expected (resting heart rate, HRV, water
// weight), when a doctor is worth seeing, and what Coach never says (fertile days, ovulation, the
// chance of pregnancy, contraception advice, a condition the athlete did not name). The reply guard
// (coach_safety/reply_guard.ts) reads the long-gap line from the rendered block
// (`cycleLongGapIn`), as it reads the screening outcome, so the model and the guard work from one
// value. The watch-outs read the same state once per turn (`cycleReadKey`).
import {
  blockOf,
  type CoachContextContributor,
  type CoachContextInput,
  type CoachContributions,
  noticeOpens,
  type RenderedBlock,
  sharedRead,
} from "../host.ts";
import { plain, record } from "../../recorded_text.ts";
import { readWithin } from "../read_within.ts";
import { addDays } from "../../training/schedule/week_ahead.ts";
import { coachServiceRpc, type StateSource, stateSourceFromRpc } from "../service_source.ts";

export const cycleContributorId = "cycle";
export const cycleBudgetChars = 2_800;
/** The key of the turn's one read of the cycle state, shared with the watch-outs. */
export const cycleReadKey = "cycle_state";
/** How long the read may take before the block is left out. */
export const cycleDeadlineMs = 1_500;
/** At most this many logged days are listed (the RPC returns the last 14). */
export const cycleDaysListed = 14;

export const cycleStatuses = [
  "regular",
  "irregular",
  "hormonal_contraception",
  "no_periods",
] as const;
export type CycleStatus = typeof cycleStatuses[number];
const flows = ["spotting", "light", "medium", "heavy", "unspecified"] as const;
const crampLevels = ["none", "mild", "strong"] as const;
const phases = ["period", "first_half", "second_half"] as const;
const confidences = ["low", "medium", "high"] as const;
const sources = ["manual", "apple_health"] as const;

export type CycleDay = Readonly<{
  date: string;
  flow: typeof flows[number] | null;
  cramps: typeof crampLevels[number] | null;
  isStart: boolean;
  source: typeof sources[number];
}>;

export type CycleStart = Readonly<{ startDate: string; lengthDays: number | null; used: boolean }>;

/** One coach_cycle_state_v1 answer, read. */
export type CycleState = Readonly<{
  trackingEnabled: boolean;
  status: CycleStatus | null;
  typicalDays: number | null;
  cycleDay: number | null;
  periodDay: number | null;
  phase: typeof phases[number] | null;
  confidence: typeof confidences[number] | null;
  expectedFrom: string | null;
  expectedTo: string | null;
  lateDays: number | null;
  noPeriodLong: boolean;
  weightWaterWindow: boolean;
  recentDays: readonly CycleDay[];
  cycles: readonly CycleStart[];
}>;

type Json = Record<string, unknown>;
const rec = (value: unknown): Json =>
  value && typeof value === "object" && !Array.isArray(value) ? value as Json : {};

/** Thrown inside the parser for a value this code does not know: the answer is unreadable. */
class Unreadable extends Error {}

const oneOf = <T extends string>(allowed: readonly T[], value: unknown): T | null => {
  if (value === null || value === undefined) return null;
  const found = allowed.find((item) => item === value);
  if (found === undefined) throw new Unreadable();
  return found;
};
const whole = (value: unknown): number | null => {
  if (value === null || value === undefined) return null;
  if (typeof value !== "number" || !Number.isInteger(value)) throw new Unreadable();
  return value;
};
const date = (value: unknown): string | null => {
  if (value === null || value === undefined) return null;
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Unreadable();
  return value;
};
const flag = (value: unknown): boolean => {
  if (typeof value !== "boolean") throw new Unreadable();
  return value;
};

/**
 * The answer, or null when it is not one this code can read (another schema, a value it does not
 * know, a missing key): an unreadable answer is never read as "tracking off".
 */
export function parseCycleState(payload: unknown): CycleState | null {
  const body = rec(payload);
  if (typeof body.schema_version !== "string" || !body.schema_version.startsWith("1.")) {
    return null;
  }
  try {
    const state = rec(body.state);
    if (!Array.isArray(body.recent_days) || !Array.isArray(body.cycles)) return null;
    const parsed: CycleState = {
      trackingEnabled: flag(body.tracking_enabled),
      status: oneOf(cycleStatuses, body.status),
      typicalDays: whole(body.typical_cycle_days),
      cycleDay: whole(state.cycle_day),
      periodDay: whole(state.period_day),
      phase: oneOf(phases, state.phase),
      confidence: oneOf(confidences, state.confidence),
      expectedFrom: date(state.expected_from),
      expectedTo: date(state.expected_to),
      lateDays: whole(state.late_days),
      noPeriodLong: flag(state.no_period_long),
      weightWaterWindow: flag(state.weight_water_window),
      recentDays: body.recent_days.map((item) => {
        const row = rec(item);
        const day = date(row.local_date);
        if (day === null) throw new Unreadable();
        return {
          date: day,
          flow: oneOf(flows, row.flow),
          cramps: oneOf(crampLevels, row.cramps),
          isStart: flag(row.is_start),
          source: oneOf(sources, row.source) ?? "manual",
        };
      }),
      cycles: body.cycles.map((item) => {
        const row = rec(item);
        const start = date(row.start_date);
        if (start === null) throw new Unreadable();
        return { startDate: start, lengthDays: whole(row.length_days), used: flag(row.used) };
      }),
    };
    // Tracking on means a status: the table's check says so, and a block without one would guess.
    if (parsed.trackingEnabled && parsed.status === null) return null;
    return parsed;
  } catch (error) {
    if (error instanceof Unreadable) return null;
    throw error;
  }
}

/** Whether tracking is on: the only state that renders a block. */
export const cycleTracked = (state: CycleState | null): state is CycleState & {
  status: CycleStatus;
} => state !== null && state.trackingEnabled && state.status !== null;

/**
 * Whether the athlete is in the second half of a natural cycle that Tracend is sure enough of
 * (medium or high confidence): when the watch-outs read a mild resting heart rate or HRV drift as
 * what that part of the cycle brings.
 */
export const cycleExplainsDrift = (state: CycleState | null): boolean =>
  cycleTracked(state) && state.status === "regular" && state.phase === "second_half" &&
  (state.confidence === "medium" || state.confidence === "high");

const statusWords: Readonly<Record<CycleStatus, string>> = {
  regular: "regular periods",
  irregular: "irregular or changing periods",
  hormonal_contraception:
    "hormonal contraception (pill, implant, hormonal IUD, injection, ring or patch)",
  no_periods: "no periods at the moment",
};

const flowWords: Readonly<Record<NonNullable<CycleDay["flow"]>, string>> = {
  spotting: "spotting",
  light: "light flow",
  medium: "medium flow",
  heavy: "heavy flow",
  unspecified: "bleeding",
};

/** The line the reply guard reads; always present in a rendered block. */
const longGapPrefix = "Long gap without a period: ";

const neverSay =
  "Never estimate fertile days, ovulation or the chance of pregnancy, never advise on contraception, and never name a condition (such as PCOS, endometriosis or a hormonal imbalance) unless the athlete named it first. Never say why a cycle changed.";
const noPhaseChanges =
  "The evidence does not support changing training or food by cycle phase: never propose or advise a change because of the cycle. Follow how the athlete feels and performs; they decide.";
const naturalShifts =
  "In the second half of a natural cycle resting heart rate often runs a little higher and HRV a little lower: expected, not poor recovery by itself. Weight often runs higher around a period (water): compare with the same point of the last cycle, not with last week.";
const doctorWhen =
  "Period cramps are not an injury. Period pain that is severe, unusual or stops normal life, very heavy bleeding, or a missed period that is not expected is worth seeing a doctor about.";

function todayLines(state: CycleState, localDate: string): string[] {
  const lines: string[] = [];
  const confidence = state.confidence === null ? "" : ` (confidence ${state.confidence})`;
  if (state.cycleDay === null) {
    lines.push(`Today (${record(localDate)}): cycle day unknown (no period start logged).`);
  } else {
    const where = state.phase === "period" && state.periodDay !== null
      ? `, period day ${record(state.periodDay)}`
      : state.phase === "second_half"
      ? ", second half of the cycle"
      : state.phase === "first_half"
      ? ", first half of the cycle"
      : state.lateDays !== null
      ? `; the period is ${
        record(state.lateDays)
      } days later than the expected range, so Tracend gives no phase`
      : state.status === "irregular"
      ? "; Tracend gives no phase for irregular or changing cycles"
      : "; no phase (not enough data)";
    lines.push(
      `Today (${record(localDate)}): cycle day ${record(state.cycleDay)}${where}${confidence}.`,
    );
  }
  lines.push(
    state.expectedFrom === null || state.expectedTo === null
      ? "No expected date for the next period (not enough data)."
      : state.lateDays !== null
      ? `The expected range was ${record(state.expectedFrom)} to ${record(state.expectedTo)}.`
      : `Next period expected ${record(state.expectedFrom)} to ${record(state.expectedTo)}.`,
  );
  const used = state.cycles.filter((cycle) => cycle.used && cycle.lengthDays !== null);
  const left = state.cycles.filter((cycle) => !cycle.used && cycle.lengthDays !== null).length;
  if (state.typicalDays !== null) {
    lines.push(
      `Typical cycle length: ${record(state.typicalDays)} days (${
        used.length >= 2 ? "from the logged cycles" : "the athlete's own answer"
      }).`,
    );
  }
  if (used.length > 0) {
    lines.push(
      `Recent cycle lengths, oldest first: ${
        used.map((cycle) => `${record(cycle.lengthDays!)} days`).join(", ")
      }${left > 0 ? `; ${record(left)} left out as a likely missed log` : ""}.`,
    );
  }
  if (state.confidence === "low" && state.phase !== null) {
    lines.push("Confidence is low: if you mention the phase, say it is a rough estimate.");
  }
  return lines;
}

function dayLine(day: CycleDay): string {
  const parts = [
    day.flow === null ? "no bleeding (logged)" : flowWords[day.flow],
    ...(day.cramps === null || day.cramps === "none" ? [] : [`${day.cramps} cramps`]),
    ...(day.isStart ? ["start"] : []),
  ];
  return `${record(day.date)} ${parts.join(", ")}`;
}

/** The block's text with its values marked (`../../recorded_text.ts`), for a tracked cycle. */
export function cycleMarked(
  state: CycleState & { status: CycleStatus },
  localDate: string,
): string {
  const lines = [
    "Menstrual cycle (the athlete turned on cycle tracking): the status is their answer, the days are what they logged or allowed from Apple Health, and Tracend calculated the rest. Estimates, not certainties.",
    `Status: ${statusWords[state.status]}.`,
    `${longGapPrefix}${state.noPeriodLong ? "yes" : "no"}`,
  ];
  if (state.noPeriodLong) {
    lines.push(
      `Rule: no period logged for ${
        state.status === "irregular" ? "6" : "3"
      } months or more. Never suggest eating less, a calorie deficit, a cut or faster weight loss while this stands: keep calories at maintenance or above. Say it is worth talking to a doctor if this is not expected for them.`,
    );
  }
  if (state.status === "regular" || state.status === "irregular") {
    lines.push(...todayLines(state, localDate));
  } else if (state.status === "hormonal_contraception") {
    lines.push(
      "Tracend shows no cycle day, phase or prediction on hormonal contraception: do not explain recovery or weight by cycle phase.",
    );
    if (state.periodDay !== null) {
      lines.push(`Today (${record(localDate)}): bleed day ${record(state.periodDay)}.`);
    }
  } else {
    lines.push("Nothing is tracked: do not ask about periods or suggest a reason.");
  }
  // Tracend sets it around an expected period and on the first days of any logged bleed.
  if (state.weightWaterWindow) {
    lines.push(
      "Weight-water window: yes. Weight often runs higher around a period (water); a rise these days is not fat gain.",
    );
  }
  lines.push("Rules:", `- ${noPhaseChanges}`);
  if (state.status === "regular" || state.status === "irregular") lines.push(`- ${naturalShifts}`);
  if (state.status !== "no_periods") lines.push(`- ${doctorWhen}`);
  lines.push(`- ${neverSay}`);
  // Only the days in the window the line names, whatever the answer holds.
  const from = addDays(localDate, -(cycleDaysListed - 1));
  const days = state.recentDays.filter((day) => day.date >= from && day.date <= localDate);
  if (days.length > 0) {
    lines.push(
      `Logged days in the last ${cycleDaysListed}, oldest first: ${days.map(dayLine).join("; ")}.`,
    );
  }
  return lines.join("\n");
}

/** The block's text for a tracked cycle, or null when there is nothing to show. Exposed for tests. */
export function renderCycle(state: CycleState | null, localDate: string): string | null {
  return cycleTracked(state) ? plain(cycleMarked(state, localDate)) : null;
}

const longGapLine = new RegExp(`^${longGapPrefix}yes$`, "m");

/**
 * Whether the turn's cycle block says no period has come for a long time: the reply guard then
 * refuses advice to eat less. False without the block (no scope, tracking off, a failed read).
 */
export function cycleLongGapIn(contributions: CoachContributions | null): boolean {
  return longGapLine.test(contributions?.texts?.[cycleContributorId] ?? "");
}

/**
 * The turn's cycle state, read once for every contributor that needs it, within `deadlineMs`. Never
 * read without the `cycle_data` scope: the caller checks it first.
 */
export async function readCycleState(
  input: CoachContextInput,
  source: StateSource,
  deadlineMs: number = cycleDeadlineMs,
) {
  const read = await readWithin(
    () => sharedRead(input, cycleReadKey, () => source(input.userId, input.localDate)),
    deadlineMs,
  );
  if (read.value === null) return { state: null, status: read.status };
  const state = parseCycleState(read.value);
  return { state, status: state === null ? "unavailable" as const : read.status };
}

export function createCycleContributor(
  source: StateSource,
  deadlineMs: number = cycleDeadlineMs,
): CoachContextContributor {
  return Object.freeze({
    id: cycleContributorId,
    slot: "volatile",
    budgetChars: cycleBudgetChars,
    async render(input): Promise<RenderedBlock | null> {
      if (!noticeOpens(input, "cycle_data")) return null;
      const { state, status } = await readCycleState(input, source, deadlineMs);
      // The trace says whether the read answered, never whether tracking is on: the log carries
      // nothing about the athlete's cycle.
      const trace = { cycle: status };
      return cycleTracked(state)
        ? blockOf(cycleMarked(state, input.localDate), { trace })
        : blockOf("", { trace });
    },
  });
}

/** The cycle state for a user and coaching date, from the service-role RPC. */
export const cycleStateFromService: StateSource = stateSourceFromRpc(
  coachServiceRpc,
  "coach_cycle_state_v1",
);

export const cycleContributor: CoachContextContributor = createCycleContributor(
  cycleStateFromService,
);
