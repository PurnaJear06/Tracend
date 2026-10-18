// Compares one claim from an athlete's message with the facts they have confirmed. The answer is
// one of three things: the fact is already saved ("known"), nothing like it is saved ("new"), or it
// contradicts a saved fact ("conflict"). A conflict never changes anything: it becomes an update
// suggestion the athlete answers (suggestions.ts). Matching is by closed vocabulary only: the same
// subject words, the opposite polarity, the other side of a number.
import type { CoachFact } from "./facts.ts";
import {
  daysPerWeekIn,
  minutesIn,
  type StatementClaim,
  styleOpposite,
  stylesOf,
  weekdaysIn,
} from "./statements.ts";
import { contentWords, normalizeText, sameSubject } from "./text.ts";
import type { FactKind } from "./vocabulary.ts";

export type ClaimVerdict =
  | Readonly<{ verdict: "new" }>
  | Readonly<{
    verdict: "known";
    /** The saved fact that already holds this (null when there is nothing to save). */
    fact: CoachFact | null;
  }>
  | Readonly<{
    verdict: "conflict";
    fact: CoachFact;
    /** The claim says the saved fact no longer applies (an injury has healed). */
    resolves: boolean;
    /** The claim cuts across a safety fact (an allergy): the athlete is asked, nothing replaces it. */
    review: boolean;
  }>;

/** "Known" through the saved fact that holds it; one with a re-confirm date is preferred. */
function knownVia(facts: readonly CoachFact[]): ClaimVerdict {
  if (facts.length === 0) return { verdict: "new" };
  return { verdict: "known", fact: facts.find((fact) => fact.reconfirmOn !== null) ?? facts[0] };
}

const conflict = (fact: CoachFact, resolves = false, review = false): ClaimVerdict => ({
  verdict: "conflict",
  fact,
  resolves,
  review,
});

const factText = (fact: CoachFact) => `${fact.subject} ${fact.statement}`;

const lacksWords =
  /\b(?:no|without|lack|lacks|lacking|don't have|do not have|dont have|not have|doesn't have|never)\b/;
const homeWords = ["home", "dumbbell", "band", "kettlebell", "bodyweight", "garage", "minimal"];

/** True when a saved equipment fact says the athlete has no such thing. */
function lacks(fact: CoachFact): boolean {
  return lacksWords.test(normalizeText(fact.statement));
}

/** Where a saved equipment fact says the athlete trains: a gym, home, or nothing it can tell. */
function settingOf(fact: CoachFact): "gym" | "home" | null {
  const words = contentWords(factText(fact));
  if (words.includes("gym")) return lacks(fact) ? "home" : "gym";
  return homeWords.some((word) => words.includes(word)) ? "home" : null;
}

function claimSetting(claim: StatementClaim): "gym" | "home" | null {
  if (claim.type === "equipment_has") {
    if (claim.subject === "gym") return "gym";
    if (claim.subject === "home gym") return "home";
    return null;
  }
  return claim.type === "equipment_lacks" && claim.subject === "gym" ? "home" : null;
}

/** The kind a like or dislike becomes when the athlete says the opposite about the same thing. */
export const oppositeKind: Readonly<Partial<Record<FactKind, FactKind>>> = {
  food_like: "food_dislike",
  food_dislike: "food_like",
  exercise_like: "exercise_dislike",
  exercise_dislike: "exercise_like",
};

const polarityOf = (kind: FactKind): "like" | "dislike" | null =>
  kind.endsWith("_dislike") ? "dislike" : kind.endsWith("_like") ? "like" : null;

const preferenceKinds: Readonly<Record<string, readonly FactKind[]>> = {
  food: ["food_like", "food_dislike", "allergy", "other_preference"],
  exercise: ["exercise_like", "exercise_dislike", "other_preference"],
  unknown: [
    "food_like",
    "food_dislike",
    "exercise_like",
    "exercise_dislike",
    "other_preference",
  ],
};

/** Whether a saved vague preference reads as a like or a dislike, from the words Tracend writes. */
function statedPolarity(fact: CoachFact): "like" | "dislike" | null {
  const text = normalizeText(fact.statement);
  if (/^(?:dislikes|hates|avoids|doesn't like|does not like)\b/.test(text)) return "dislike";
  if (/^(?:likes|loves|enjoys|prefers)\b/.test(text)) return "like";
  return null;
}

function judgePreference(
  claim: Extract<StatementClaim, { type: "like" | "dislike" }>,
  facts: readonly CoachFact[],
): ClaimVerdict {
  const known: CoachFact[] = [];
  for (const fact of facts) {
    if (!preferenceKinds[claim.target].includes(fact.kind)) continue;
    if (!sameSubject(fact.subject, claim.subject)) continue;
    if (fact.kind === "allergy") {
      if (claim.type === "like") return conflict(fact, false, true);
      known.push(fact);
    } else if (fact.kind === "other_preference") {
      // A migrated or typed preference has no like or dislike of its own: only one that says so
      // can be contradicted, and the same subject alone is not a contradiction.
      const stated = statedPolarity(fact);
      if (stated !== null && stated !== claim.type) return conflict(fact);
      known.push(fact);
    } else if (polarityOf(fact.kind) === claim.type) {
      known.push(fact);
    } else {
      return conflict(fact);
    }
  }
  return knownVia(known);
}

function judgeEquipment(
  claim: Extract<StatementClaim, { type: "equipment_has" | "equipment_lacks" }>,
  facts: readonly CoachFact[],
): ClaimVerdict {
  const setting = claimSetting(claim);
  const wantsHas = claim.type === "equipment_has";
  const known: CoachFact[] = [];
  for (const fact of facts.filter((candidate) => candidate.kind === "equipment")) {
    const factSetting = settingOf(fact);
    if (setting !== null && factSetting !== null && factSetting !== setting) return conflict(fact);
    if (sameSubject(fact.subject, claim.subject)) {
      if (lacks(fact) === wantsHas) return conflict(fact);
      known.push(fact);
    } else if (setting !== null && factSetting === setting) {
      known.push(fact);
    }
  }
  return knownVia(known);
}

const negativeSchedule =
  /\b(?:cannot|can't|cant|no|not|unavailable|busy|don't|do not|dont|never)\b/;

function judgeSchedule(
  claim: Extract<
    StatementClaim,
    { type: "schedule_days" | "schedule_minutes" | "schedule_unavailable" }
  >,
  facts: readonly CoachFact[],
): ClaimVerdict {
  const known: CoachFact[] = [];
  for (const fact of facts.filter((candidate) => candidate.kind === "schedule_constraint")) {
    const text = factText(fact);
    if (claim.type === "schedule_days") {
      const days = daysPerWeekIn(text);
      if (days === null) continue;
      if (days !== claim.days) return conflict(fact);
      known.push(fact);
    } else if (claim.type === "schedule_minutes") {
      const minutes = minutesIn(text);
      if (minutes === null) continue;
      if (minutes !== claim.minutes) return conflict(fact);
      known.push(fact);
    } else {
      const named = weekdaysIn(text);
      const overlap = claim.weekdays.filter((day) => named.includes(day));
      if (overlap.length === 0) continue;
      if (!negativeSchedule.test(normalizeText(text))) return conflict(fact);
      if (overlap.length === claim.weekdays.length) known.push(fact);
    }
  }
  return knownVia(known);
}

function judgeStyle(
  claim: Extract<StatementClaim, { type: "style" }>,
  facts: readonly CoachFact[],
): ClaimVerdict {
  const known: CoachFact[] = [];
  for (const fact of facts.filter((candidate) => candidate.kind === "coaching_style")) {
    const styles = stylesOf(factText(fact));
    if (styles.includes(styleOpposite[claim.style])) return conflict(fact);
    if (styles.includes(claim.style)) known.push(fact);
  }
  return knownVia(known);
}

/** What one claim means against the facts the athlete has confirmed. */
export function judgeClaim(claim: StatementClaim, facts: readonly CoachFact[]): ClaimVerdict {
  switch (claim.type) {
    case "like":
    case "dislike":
      return judgePreference(claim, facts);
    case "allergy": {
      const known: CoachFact[] = [];
      for (const fact of facts) {
        if (!sameSubject(fact.subject, claim.subject)) continue;
        if (fact.kind === "allergy") known.push(fact);
        else if (fact.kind === "food_like") return conflict(fact);
      }
      return knownVia(known);
    }
    case "injury": {
      return knownVia(
        facts.filter((fact) =>
          fact.kind === "injury_limitation" && sameSubject(fact.subject, claim.subject)
        ),
      );
    }
    case "injury_resolved": {
      const saved = facts.find((fact) =>
        fact.kind === "injury_limitation" && sameSubject(fact.subject, claim.subject)
      );
      return saved ? conflict(saved, true) : { verdict: "known", fact: null };
    }
    case "equipment_has":
    case "equipment_lacks":
      return judgeEquipment(claim, facts);
    case "schedule_days":
    case "schedule_minutes":
    case "schedule_unavailable":
      return judgeSchedule(claim, facts);
    case "style":
      return judgeStyle(claim, facts);
  }
}
