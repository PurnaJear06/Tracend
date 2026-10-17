// The only thing the model hands to the proposal engine: an intent from a closed vocabulary. The
// parser is strict. A kind it does not know, a value outside its vocabulary, a stray key or a
// figure that is not a plain number makes the intent invalid, and the engine builds nothing.
import {
  blockSettings,
  type CoachProposalIntent,
  goalPhases,
  intensityLevels,
  nutritionDirections,
  proposalKinds,
  proposalReasons,
  sessionDirections,
  trainingFocuses,
} from "./types.ts";

export type IntentResult =
  | Readonly<{ ok: true; intent: CoachProposalIntent }>
  | Readonly<{ ok: false; problem: string }>;

const isoDate = /^\d{4}-\d{2}-\d{2}$/;
const slugPattern = /^[a-z0-9][a-z0-9-]{0,79}$/;

/** The longest free-text note kept with an intent (the athlete's own context, never a figure). */
export const maxNoteLength = 140;

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function oneOf<T extends string>(list: readonly T[], value: unknown): T | null {
  return typeof value === "string" ? list.find((item) => item === value) ?? null : null;
}

function wholeBetween(value: unknown, low: number, high: number): number | null {
  return typeof value === "number" && Number.isInteger(value) && value >= low && value <= high
    ? value
    : null;
}

function realBetween(value: unknown, low: number, high: number): number | null {
  return typeof value === "number" && Number.isFinite(value) && value >= low && value <= high
    ? value
    : null;
}

function realDate(value: unknown): string | null {
  if (typeof value !== "string" || !isoDate.test(value)) return null;
  const parsed = new Date(`${value}T00:00:00Z`);
  return Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value
    ? null
    : value;
}

/**
 * A note is kept only when it carries no digit: a figure in free text is a figure nobody checked,
 * so such a note is dropped, never edited. The athlete still sees the rules' own numbers.
 */
function cleanNote(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const note = value.replace(/\s+/g, " ").trim();
  if (note === "" || note.length > maxNoteLength || /\d/.test(note)) return undefined;
  return note;
}

const allowedKeys: Readonly<Record<string, readonly string[]>> = {
  temporary_block: ["kind", "reason", "note", "setting", "start_date", "end_date"],
  training_schedule: [
    "kind",
    "reason",
    "note",
    "days_per_week",
    "weekdays",
    "session_minutes",
    "weeks",
  ],
  exercise_swap: ["kind", "reason", "note", "from_slug", "to_slug"],
  intensity_or_phase: ["kind", "reason", "note", "level", "focus", "weeks"],
  goal_or_phase: ["kind", "reason", "note", "phase", "target_weight_kg", "target_date"],
  nutrition_targets: ["kind", "reason", "note", "direction", "requested_calories"],
  next_session_adjustment: ["kind", "reason", "note", "direction", "session"],
};

/** Reads the model's intent object. Anything outside the vocabulary is invalid. */
export function parseCoachProposalIntent(raw: unknown): IntentResult {
  const body = record(raw);
  if (!body) return { ok: false, problem: "intent is not an object" };
  const kind = oneOf(proposalKinds, body.kind);
  if (!kind) return { ok: false, problem: "unknown proposal kind" };
  const stray = Object.keys(body).find((key) => !allowedKeys[kind].includes(key));
  if (stray) return { ok: false, problem: `unexpected key ${stray}` };
  const reason = oneOf(proposalReasons, body.reason);
  if (!reason) return { ok: false, problem: "reason is not in the vocabulary" };
  const note = cleanNote(body.note);
  const common = { reason, ...(note === undefined ? {} : { note }) };
  const bad = (problem: string): IntentResult => ({ ok: false, problem });

  switch (kind) {
    case "temporary_block": {
      const setting = oneOf(blockSettings, body.setting);
      const startDate = realDate(body.start_date);
      const endDate = realDate(body.end_date);
      if (!setting) return bad("setting is not in the vocabulary");
      if (!startDate || !endDate) return bad("dates must be real YYYY-MM-DD dates");
      return { ok: true, intent: { kind, ...common, setting, startDate, endDate } };
    }
    case "training_schedule": {
      const weeks = wholeBetween(body.weeks, 1, 12);
      if (weeks === null) return bad("weeks must be a whole number from 1 to 12");
      const daysPerWeek = body.days_per_week === undefined
        ? undefined
        : wholeBetween(body.days_per_week, 1, 6);
      if (daysPerWeek === null) return bad("days_per_week must be a whole number from 1 to 6");
      let weekdays: number[] | undefined;
      if (body.weekdays !== undefined) {
        if (!Array.isArray(body.weekdays) || body.weekdays.length < 1 || body.weekdays.length > 6) {
          return bad("weekdays must list one to six ISO weekdays");
        }
        const days = body.weekdays.map((day) => wholeBetween(day, 1, 7));
        if (days.includes(null) || new Set(days).size !== days.length) {
          return bad("weekdays must be unique ISO weekdays from 1 to 7");
        }
        weekdays = (days as number[]).sort((a, b) => a - b);
      }
      const sessionMinutes = body.session_minutes === undefined
        ? undefined
        : wholeBetween(body.session_minutes, 30, 120);
      if (sessionMinutes === null) return bad("session_minutes must be from 30 to 120");
      if (daysPerWeek === undefined && weekdays === undefined && sessionMinutes === undefined) {
        return bad("a schedule change needs days, weekdays or a session length");
      }
      return {
        ok: true,
        intent: {
          kind,
          ...common,
          weeks,
          ...(daysPerWeek === undefined ? {} : { daysPerWeek }),
          ...(weekdays === undefined ? {} : { weekdays }),
          ...(sessionMinutes === undefined ? {} : { sessionMinutes }),
        },
      };
    }
    case "exercise_swap": {
      const fromSlug = typeof body.from_slug === "string" && slugPattern.test(body.from_slug)
        ? body.from_slug
        : null;
      if (!fromSlug) return bad("from_slug is not a catalog slug");
      if (body.to_slug !== undefined) {
        if (typeof body.to_slug !== "string" || !slugPattern.test(body.to_slug)) {
          return bad("to_slug is not a catalog slug");
        }
        return { ok: true, intent: { kind, ...common, fromSlug, toSlug: body.to_slug } };
      }
      return { ok: true, intent: { kind, ...common, fromSlug } };
    }
    case "intensity_or_phase": {
      const level = body.level === undefined ? undefined : oneOf(intensityLevels, body.level);
      const focus = body.focus === undefined ? undefined : oneOf(trainingFocuses, body.focus);
      const weeks = wholeBetween(body.weeks, 1, 8);
      if (level === null || focus === null) return bad("level or focus is not in the vocabulary");
      if ((level === undefined) === (focus === undefined)) {
        return bad("give exactly one of level or focus");
      }
      if (weeks === null) return bad("weeks must be a whole number from 1 to 8");
      return {
        ok: true,
        intent: {
          kind,
          ...common,
          weeks,
          ...(level === undefined ? {} : { level }),
          ...(focus === undefined ? {} : { focus }),
        },
      };
    }
    case "goal_or_phase": {
      const phase = oneOf(goalPhases, body.phase);
      if (!phase) return bad("phase is not in the vocabulary");
      const targetWeightKg = body.target_weight_kg === undefined
        ? undefined
        : realBetween(body.target_weight_kg, 30, 300);
      const targetDate = body.target_date === undefined ? undefined : realDate(body.target_date);
      if (targetWeightKg === null) return bad("target_weight_kg must be from 30 to 300");
      if (targetDate === null) return bad("target_date must be a real YYYY-MM-DD date");
      return {
        ok: true,
        intent: {
          kind,
          ...common,
          phase,
          ...(targetWeightKg === undefined ? {} : { targetWeightKg }),
          ...(targetDate === undefined ? {} : { targetDate }),
        },
      };
    }
    case "nutrition_targets": {
      const direction = oneOf(nutritionDirections, body.direction);
      if (!direction) return bad("direction is not in the vocabulary");
      const requestedCalories = body.requested_calories === undefined
        ? undefined
        : wholeBetween(body.requested_calories, 500, 8000);
      if (requestedCalories === null) return bad("requested_calories must be from 500 to 8000");
      return {
        ok: true,
        intent: {
          kind,
          ...common,
          direction,
          ...(requestedCalories === undefined ? {} : { requestedCalories }),
        },
      };
    }
    case "next_session_adjustment": {
      const direction = oneOf(sessionDirections, body.direction);
      const session = oneOf(["today", "next"] as const, body.session);
      if (!direction) return bad("direction is not in the vocabulary");
      if (!session) return bad("session must be today or next");
      return { ok: true, intent: { kind, ...common, direction, session } };
    }
  }
}
