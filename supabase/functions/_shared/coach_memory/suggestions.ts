// Fact suggestions: what Coach may put in front of the athlete as a confirm chip. A suggestion is
// never a fact. It is stored only when the athlete taps Confirm, and the confirm writes through
// save_coach_fact_v1 (or delete_coach_fact_v1 for a resolved fact) as the athlete's own action
// (Architecture 2 and 3). Two things produce suggestions: the deterministic reading of the
// athlete's message (statements.ts, contradictions.ts) and, optionally, the model's own
// `fact_suggestions`, which is checked against the closed vocabulary here.
import { judgeClaim, oppositeKind } from "./contradictions.ts";
import type { CoachFact } from "./facts.ts";
import { claimToFact, extractClaims } from "./statements.ts";
import { flatten, normalizeText, sameSubject } from "./text.ts";
import {
  type FactKind,
  isFactKind,
  maxFactStatementChars,
  maxFactSubjectChars,
} from "./vocabulary.ts";

export const suggestionActions = ["add", "update", "resolve", "review"] as const;
export type SuggestionAction = typeof suggestionActions[number];

/** What the model may ask for: it can add, update or close a fact, never "review" one. */
const modelActions: readonly SuggestionAction[] = ["add", "update", "resolve"];

export type FactSuggestion = Readonly<{
  action: SuggestionAction;
  kind: FactKind;
  subject: string;
  statement: string;
  /** The saved fact this updates, closes or asks about (its current version id). */
  factId: string | null;
  /** That fact's statement, so the chip can show before and after. */
  previous: string | null;
  /** One plain sentence on why this is offered. */
  reason: string;
  origin: "athlete_statement" | "coach";
}>;

/** At most this many chips follow one reply. */
export const maxSuggestionsPerTurn = 2;
export const maxModelSuggestions = 3;

/**
 * Suggestions from an athlete's message. A new fact is offered as "add"; a statement that
 * contradicts a confirmed fact is offered as "update" (or "resolve" when it says an injury has
 * healed, or "review" when it cuts across an allergy). A fact already saved is never offered again.
 */
export function suggestFromStatement(
  message: string,
  facts: readonly CoachFact[],
): FactSuggestion[] {
  const suggestions: FactSuggestion[] = [];
  for (const claim of extractClaims(message)) {
    const verdict = judgeClaim(claim, facts);
    if (verdict.verdict === "known") continue;
    const wanted = claimToFact(claim);
    if (verdict.verdict === "new") {
      suggestions.push({
        action: "add",
        ...wanted,
        factId: null,
        previous: null,
        reason: "You said this in your message.",
        origin: "athlete_statement",
      });
      continue;
    }
    const { fact } = verdict;
    const saved = `“${flatten(fact.statement, 120)}”`;
    if (verdict.resolves) {
      suggestions.push({
        action: "resolve",
        kind: fact.kind,
        subject: fact.subject,
        statement: fact.statement,
        factId: fact.id,
        previous: fact.statement,
        reason: `You said this has healed. You confirmed ${saved} on ${fact.confirmedOn}.`,
        origin: "athlete_statement",
      });
    } else if (verdict.review) {
      suggestions.push({
        action: "review",
        kind: fact.kind,
        subject: fact.subject,
        statement: fact.statement,
        factId: fact.id,
        previous: fact.statement,
        reason: `This may not match ${saved}, which you confirmed on ${fact.confirmedOn}.`,
        origin: "athlete_statement",
      });
    } else {
      suggestions.push({
        action: "update",
        ...wanted,
        // Saying the opposite of a saved like or dislike stays in that fact's own domain.
        kind: (claim.type === "like" || claim.type === "dislike") && oppositeKind[fact.kind]
          ? oppositeKind[fact.kind]!
          : wanted.kind,
        factId: fact.id,
        previous: fact.statement,
        reason: `This differs from ${saved}, which you confirmed on ${fact.confirmedOn}.`,
        origin: "athlete_statement",
      });
    }
  }
  return dedupe(suggestions).slice(0, maxSuggestionsPerTurn);
}

function dedupe(suggestions: readonly FactSuggestion[]): FactSuggestion[] {
  const kept: FactSuggestion[] = [];
  for (const suggestion of suggestions) {
    const same = kept.some((other) =>
      suggestion.factId !== null
        ? other.factId === suggestion.factId
        : other.factId === null && other.kind === suggestion.kind &&
          sameSubject(other.subject, suggestion.subject)
    );
    if (!same) kept.push(suggestion);
  }
  return kept;
}

/** The deterministic suggestions first, then the model's, without repeats, at most two. */
export function mergeSuggestions(
  fromStatement: readonly FactSuggestion[],
  fromModel: readonly FactSuggestion[],
): FactSuggestion[] {
  return dedupe([...fromStatement, ...fromModel]).slice(0, maxSuggestionsPerTurn);
}

// The model's suggestions -----------------------------------------------------------------------

export type ModelSuggestionsCheck = Readonly<{
  suggestions: FactSuggestion[];
  /** How many entries were refused, for the turn's log. */
  dropped: number;
}>;

const modelKeys = ["action", "kind", "subject", "statement", "fact_id"];
const subjectText = /^[\p{L}\p{N}][\p{L}\p{N} '\-]*$/u;

/**
 * Keeps the entries of a model answer's `fact_suggestions` that fit the closed vocabulary and
 * drops the rest (a bad suggestion never fails a reply). An update or resolve must name a fact the
 * athlete has saved, an add must not; nothing a model sends is trusted as a fact. A suggestion for
 * something already saved is dropped as a repeat.
 */
export function sanitizeModelSuggestions(
  raw: unknown,
  facts: readonly CoachFact[],
): ModelSuggestionsCheck {
  if (raw === undefined || raw === null) return { suggestions: [], dropped: 0 };
  if (!Array.isArray(raw)) return { suggestions: [], dropped: 1 };
  const suggestions: FactSuggestion[] = [];
  let dropped = Math.max(0, raw.length - maxModelSuggestions);
  for (const item of raw.slice(0, maxModelSuggestions)) {
    const checked = checkModelSuggestion(item, facts);
    if (checked) suggestions.push(checked);
    else dropped++;
  }
  return { suggestions, dropped };
}

function checkModelSuggestion(item: unknown, facts: readonly CoachFact[]): FactSuggestion | null {
  if (!item || typeof item !== "object" || Array.isArray(item)) return null;
  const entry = item as Record<string, unknown>;
  if (Object.keys(entry).some((key) => !modelKeys.includes(key))) return null;
  const action = entry.action as SuggestionAction;
  if (!modelActions.includes(action) || !isFactKind(entry.kind)) return null;
  if (typeof entry.subject !== "string" || typeof entry.statement !== "string") return null;
  const subject = normalizeText(entry.subject);
  const statement = entry.statement.replace(/\s+/g, " ").trim();
  if (
    subject.length < 1 || subject.length > maxFactSubjectChars || !subjectText.test(subject) ||
    statement.length < 1 || statement.length > maxFactStatementChars || /[<>]/.test(statement)
  ) return null;
  const target = typeof entry.fact_id === "string"
    ? facts.find((fact) => fact.id === entry.fact_id)
    : undefined;
  if (action === "add") {
    if (entry.fact_id !== undefined && entry.fact_id !== null) return null;
    const saved = facts.some((fact) =>
      fact.kind === entry.kind && sameSubject(fact.subject, subject)
    );
    if (saved) return null;
    return {
      action,
      kind: entry.kind,
      subject,
      statement,
      factId: null,
      previous: null,
      reason: "Coach noticed this in your conversation.",
      origin: "coach",
    };
  }
  if (!target) return null;
  if (action === "update" && normalizeText(statement) === normalizeText(target.statement)) {
    return null;
  }
  return {
    action,
    kind: action === "resolve" ? target.kind : entry.kind,
    subject: action === "resolve" ? target.subject : subject,
    statement: action === "resolve" ? target.statement : statement,
    factId: target.id,
    previous: target.statement,
    reason: action === "resolve"
      ? `Coach thinks “${flatten(target.statement, 120)}” may no longer apply.`
      : `Coach suggests updating “${
        flatten(target.statement, 120)
      }”, which you confirmed on ${target.confirmedOn}.`,
    origin: "coach",
  };
}

/** A suggestion as the app receives it. */
export function suggestionToWire(suggestion: FactSuggestion): Record<string, unknown> {
  return {
    action: suggestion.action,
    kind: suggestion.kind,
    subject: suggestion.subject,
    statement: suggestion.statement,
    fact_id: suggestion.factId,
    previous: suggestion.previous,
    reason: suggestion.reason,
    origin: suggestion.origin,
  };
}
