// A break from training (kind training_pause). The athlete says "I'm taking 15 days off" and Coach
// asks for it; these rules check the dates and build the card; the athlete approves it with one tap.
// Approval writes a row in training_pauses, an overlay like a day adjustment: no plan version changes,
// so the plan simply resumes after the break's last day. A break computes no number, so it needs no
// profile, no weight and no logged data, and the health check never holds one back.
import { addDays, daysBetween, reasonText, shortDate } from "./common.ts";
import { refusals, refuse } from "./refusals.ts";
import type { ScreeningOutcome } from "../training/screening/outcome.ts";
import { screeningOutcomes } from "../training/screening/outcome.ts";
import {
  type BuildResult,
  type CoachProposalIntent,
  type PauseReason,
  pauseReasons,
} from "./types.ts";

/** The longest break: the same six weeks as a temporary block. */
export const maxPauseDays = 42;
/** A break starts today, tomorrow or the day after. */
export const maxPauseStartLeadDays = 2;
/** Hours an unanswered break stays open: a break that starts within two days is answered soon. */
export const pauseExpiryHours = 24;

/** A break already running or ahead: its first and last day. */
export type PauseWindow = Readonly<{ startDate: string; lastDay: string }>;

/** What the rules read to build a break (get_training_pause_inputs_v1). */
export type PauseInputs = Readonly<{
  /** The athlete's own date. */
  today: string;
  screening: ScreeningOutcome;
  pauses: readonly PauseWindow[];
}>;

const isoDate = /^\d{4}-\d{2}-\d{2}$/;
type Json = Record<string, unknown>;
const rec = (value: unknown): Json | null =>
  typeof value === "object" && value !== null && !Array.isArray(value) ? value as Json : null;

/** The inputs payload, or null when it is not exactly that shape. */
export function parsePauseInputs(raw: unknown): PauseInputs | null {
  const row = rec(raw);
  if (!row || row.schema_version !== "1.0" || typeof row.local_date !== "string") return null;
  if (!isoDate.test(row.local_date) || !Array.isArray(row.pauses)) return null;
  const screening = screeningOutcomes.find((item) => item === row.screening);
  if (!screening) return null;
  const pauses: PauseWindow[] = [];
  for (const item of row.pauses) {
    const pause = rec(item);
    const start = pause?.start_date;
    const last = pause?.last_day;
    if (typeof start !== "string" || typeof last !== "string") return null;
    if (!isoDate.test(start) || !isoDate.test(last)) return null;
    pauses.push({ startDate: start, lastDay: last });
  }
  return { today: row.local_date, screening, pauses };
}

/** "1–15 Nov", or "28 Oct–3 Nov" across months, for a break's first and last day. */
export function pauseRange(startDate: string, endDate: string): string {
  const [start, end] = [shortDate(startDate), shortDate(endDate)];
  if (startDate === endDate) return start;
  const [startDay, startMonth] = start.split(" ");
  const [endDay, endMonth] = end.split(" ");
  return startMonth === endMonth ? `${startDay}–${endDay} ${endMonth}` : `${start}–${end}`;
}

const plural = (count: number, word: string) => `${count} ${word}${count === 1 ? "" : "s"}`;

export function buildTrainingPause(
  intent: Extract<CoachProposalIntent, { kind: "training_pause" }>,
  inputs: PauseInputs,
): BuildResult {
  const { startDate, endDate } = intent;
  if (!(pauseReasons as readonly string[]).includes(intent.reason)) {
    return refuse(
      "pause_reason_not_allowed",
      "I couldn't set up that break. Tell me why you're taking it (a rest, travel, being unwell or a busy spell) and I'll try again.",
    );
  }
  if (endDate < startDate) return refusals.datesInvalid();
  if (startDate < inputs.today) return refusals.pauseStartPast(inputs.today);
  if (daysBetween(inputs.today, startDate) > maxPauseStartLeadDays) {
    return refusals.pauseStartTooFar(addDays(startDate, -maxPauseStartLeadDays));
  }
  const days = daysBetween(startDate, endDate) + 1;
  if (days > maxPauseDays) return refusals.pauseTooLong(maxPauseDays);
  const clash = inputs.pauses.find((pause) =>
    pause.startDate <= endDate && pause.lastDay >= startDate
  );
  if (clash) return refusals.pauseOverlaps(clash.startDate, clash.lastDay);

  const range = pauseRange(startDate, endDate);
  const resumes = shortDate(addDays(endDate, 1));
  return {
    ok: true,
    proposal: {
      kind: "training_pause",
      title: `Break · ${range}`,
      rationale: `${reasonText(intent.reason, intent.note)} From ${shortDate(startDate)} to ${
        shortDate(endDate)
      } no session is due and nothing counts as missed. Your plan stays as it is and resumes on ${resumes}.`,
      benefit: "Rest without the plan nagging you, and come back to the same plan.",
      downside:
        "A long break can cost some fitness and strength, so the first sessions back may feel harder.",
      confidence: "high",
      evidence: [{
        code: "ATHLETE_REQUEST",
        label: "You asked for a break from training.",
        source: "athlete",
      }],
      expiresInHours: pauseExpiryHours,
      endsOn: endDate,
      before: { rows: [{ label: "Training", value: "Your plan as usual" }] },
      after: {
        rows: [
          { label: "Break", value: `${range} (${plural(days, "day")})` },
          { label: "Sessions", value: "None due during the break" },
          { label: "Plan resumes", value: resumes },
        ],
      },
      payload: {
        pause: {
          start_date: startDate,
          end_date: endDate,
          reason: intent.reason as PauseReason,
          ...(intent.note === undefined ? {} : { note: intent.note }),
        },
      },
      basis: {
        training_version_id: null,
        nutrition_version_id: null,
        goal_id: null,
        screening: inputs.screening,
        gates: [],
      },
    },
  };
}
