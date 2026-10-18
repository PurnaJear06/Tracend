// Fact suggestions: what Coach may put in front of the athlete as a confirm chip. A suggestion is
// never a fact. It is stored only when the athlete taps Confirm, and the confirm writes through
// save_coach_fact_v1 (or delete_coach_fact_v1 for a resolved fact) as the athlete's own action
// (Architecture 2 and 3). Two things produce suggestions: the deterministic reading of the
// athlete's message (statements.ts, contradictions.ts) and, optionally, the model's own
// `fact_suggestions`, which is checked against the closed vocabulary here.
import { type ClaimVerdict, judgeClaim, oppositeKind } from "./contradictions.ts";
import { type CoachFact, factsDueForReconfirm } from "./facts.ts";
import { type ClaimFact, claimToFact, extractClaims, type StatementClaim } from "./statements.ts";
import { flatten, normalizeText, sameSubject } from "./text.ts";
import {
  type FactKind,
  isFactKind,
  maxFactStatementChars,
  maxFactSubjectChars,
} from "./vocabulary.ts";

export const suggestionActions = ["add", "update", "resolve", "review", "reconfirm"] as const;
export type SuggestionAction = typeof suggestionActions[number];

/** What the model may ask for: it can add, update or close a fact, never "review" or "reconfirm". */
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

type Origin = FactSuggestion["origin"];

/**
 * The suggestion a claim's verdict calls for, or null when nothing needs the athlete's answer: a
 * new fact is an "add"; a contradiction an "update" (a "resolve" when an injury has healed, a
 * "review" when it cuts across an allergy); a fact already saved is not offered again, unless it
 * is one of those due to be asked about and the athlete has just spoken of it ("reconfirm").
 */
function suggestionForVerdict(
  claim: StatementClaim,
  wanted: ClaimFact,
  verdict: ClaimVerdict,
  origin: Origin,
  dueIds: ReadonlySet<string>,
): FactSuggestion | null {
  if (verdict.verdict === "known") {
    const { fact } = verdict;
    if (!fact || !dueIds.has(fact.id)) return null;
    return {
      action: "reconfirm",
      kind: fact.kind,
      subject: fact.subject,
      statement: fact.statement,
      factId: fact.id,
      previous: fact.statement,
      reason: `You confirmed “${
        flatten(fact.statement, 120)
      }” on ${fact.confirmedOn}. Is it still true?`,
      origin,
    };
  }
  if (verdict.verdict === "new") {
    return {
      action: "add",
      ...wanted,
      factId: null,
      previous: null,
      reason: origin === "coach"
        ? "Coach noticed this in your conversation."
        : "You said this in your message.",
      origin,
    };
  }
  const { fact } = verdict;
  const saved = `“${flatten(fact.statement, 120)}”`;
  if (verdict.resolves) {
    return {
      action: "resolve",
      kind: fact.kind,
      subject: fact.subject,
      statement: fact.statement,
      factId: fact.id,
      previous: fact.statement,
      reason: `You said this has healed. You confirmed ${saved} on ${fact.confirmedOn}.`,
      origin,
    };
  }
  if (verdict.review) {
    return {
      action: "review",
      kind: fact.kind,
      subject: fact.subject,
      statement: fact.statement,
      factId: fact.id,
      previous: fact.statement,
      reason: `This may not match ${saved}, which you confirmed on ${fact.confirmedOn}.`,
      origin,
    };
  }
  return {
    action: "update",
    ...wanted,
    // Saying the opposite of a saved like or dislike stays in that fact's own domain.
    kind: (claim.type === "like" || claim.type === "dislike") && oppositeKind[fact.kind]
      ? oppositeKind[fact.kind]!
      : wanted.kind,
    factId: fact.id,
    previous: fact.statement,
    reason: `This differs from ${saved}, which you confirmed on ${fact.confirmedOn}.`,
    origin,
  };
}

/**
 * Suggestions from an athlete's message (see suggestionForVerdict). `today` is the athlete's date:
 * a statement about a saved fact that is due to be asked about again offers "still true?".
 */
export function suggestFromStatement(
  message: string,
  facts: readonly CoachFact[],
  today: string,
): FactSuggestion[] {
  const dueIds = new Set(factsDueForReconfirm(facts, today).map((fact) => fact.id));
  const suggestions: FactSuggestion[] = [];
  for (const claim of extractClaims(message)) {
    const suggestion = suggestionForVerdict(
      claim,
      claimToFact(claim),
      judgeClaim(claim, facts),
      "athlete_statement",
      dueIds,
    );
    if (suggestion) suggestions.push(suggestion);
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

const noDueFacts: ReadonlySet<string> = new Set();

/** The claim a model's liking, dislike or allergy stands for, so it is judged like a statement. */
function claimOfModelFact(kind: FactKind, subject: string): StatementClaim | null {
  switch (kind) {
    case "food_like":
      return { type: "like", target: "food", subject };
    case "food_dislike":
      return { type: "dislike", target: "food", subject };
    case "exercise_like":
      return { type: "like", target: "exercise", subject };
    case "exercise_dislike":
      return { type: "dislike", target: "exercise", subject };
    case "allergy":
      return { type: "allergy", subject };
    default:
      return null;
  }
}

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
  // The model writes "" for no fact (its schema has no null).
  const factId = entry.fact_id === "" ? null : entry.fact_id;
  const target = typeof factId === "string" ? facts.find((fact) => fact.id === factId) : undefined;
  if (action === "add") {
    if (factId !== undefined && factId !== null) return null;
    const wanted = { kind: entry.kind, subject, statement };
    // A taste or an allergy is judged like the athlete's own statement: already saved is dropped,
    // the opposite of a saved taste becomes an update, and one that cuts across an allergy is a
    // review card, never an add.
    const claim = claimOfModelFact(entry.kind, subject);
    if (claim) {
      return suggestionForVerdict(claim, wanted, judgeClaim(claim, facts), "coach", noDueFacts);
    }
    const saved = facts.some((fact) =>
      fact.kind === entry.kind && sameSubject(fact.subject, subject)
    );
    if (saved) return null;
    return suggestionForVerdict(
      { type: "equipment_has", subject },
      wanted,
      { verdict: "new" },
      "coach",
      noDueFacts,
    );
  }
  if (!target) return null;
  if (action === "update" && normalizeText(statement) === normalizeText(target.statement)) {
    return null;
  }
  // An allergy is never changed or closed on the model's word: the athlete is asked to check it.
  if (target.kind === "allergy") {
    return {
      action: "review",
      kind: target.kind,
      subject: target.subject,
      statement: target.statement,
      factId: target.id,
      previous: target.statement,
      reason: `Coach asks you to check “${
        flatten(target.statement, 120)
      }”, which you confirmed on ${target.confirmedOn}.`,
      origin: "coach",
    };
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
