// The red-flag questions of the pain check (B5-1): the closed list of codes the database accepts, the
// joints each question is asked about, and the plain question the athlete reads. The outcome each
// code leads to is a rule value and lives, with its sources, in rules.ts; the database keeps its own
// copy (private.pain_rules) and a test keeps the two equal. The app shows the questions for the
// chosen joint and the general ones; the server accepts any code in this list for any joint, because a
// flag that is stored is never wrong to act on.
import { redFlagOutcomes } from "./rules.ts";

export const painAreas = ["knee", "back", "shoulder", "other"] as const;
export type PainArea = typeof painAreas[number];

export const painPatterns = ["movement", "rest"] as const;
export type PainPattern = typeof painPatterns[number];

export const painOutcomes = [
  "urgent",
  "clinician_today",
  "clinician",
  "modify",
  "watch",
  "clear",
] as const;
export type PainOutcome = typeof painOutcomes[number];

export type RedFlagCode = keyof typeof redFlagOutcomes;

export type RedFlagQuestion = Readonly<{
  /** The joints the app asks this about; "all" means every one. */
  areas: readonly PainArea[];
  question: string;
}>;

const everyArea = painAreas;

export const redFlagQuestions: Readonly<Record<RedFlagCode, RedFlagQuestion>> = Object.freeze({
  bladder_bowel_saddle: {
    areas: ["back"],
    question:
      "New trouble controlling your bladder or bowels, or numbness around your groin or inner thighs",
  },
  chest_or_breath: {
    areas: ["shoulder", "other"],
    question: "The pain came with chest pain, pressure or shortness of breath",
  },
  numb_weak_limb: {
    areas: everyArea,
    question: "Numbness, tingling or weakness in an arm or leg",
  },
  pop_or_sudden: {
    areas: everyArea,
    question: "It started with a pop, a tear or a sudden sharp pain",
  },
  cannot_bear_or_move: {
    areas: everyArea,
    question: "You can't put weight on it or can't move it normally",
  },
  rapid_swelling: {
    areas: ["knee", "other"],
    question: "It swelled up quickly",
  },
  dislocated_or_cannot_lift: {
    areas: ["shoulder"],
    question: "It felt like it slipped out of place, or you can't lift your arm",
  },
  locks_gives_way: {
    areas: ["knee"],
    question: "The knee locks or gives way",
  },
  fever_unwell: {
    areas: everyArea,
    question: "You have a fever or feel unwell with it",
  },
  night_pain: {
    areas: everyArea,
    question: "It wakes you at night and doesn't ease when you change position",
  },
});

export const redFlagCodes = Object.freeze(
  (Object.keys(redFlagOutcomes) as RedFlagCode[]).sort(),
);

export function isRedFlagCode(value: unknown): value is RedFlagCode {
  return typeof value === "string" && (redFlagCodes as readonly string[]).includes(value);
}

/** The questions the app asks about one joint: its own and the general ones, in list order. */
export function questionsFor(area: PainArea): readonly RedFlagCode[] {
  return redFlagCodes.filter((code) => redFlagQuestions[code].areas.includes(area));
}
