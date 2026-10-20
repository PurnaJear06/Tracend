// Contract 7 contributor (A10 part 2): the Coach's own notes about earlier conversations and
// advice, capped and dated, labelled as untrusted. They rank below the confirmed facts and the
// athlete's recent statements.
import { renderCoachNotesMarked } from "../../coach_memory/notes_render.ts";
import { blockOf, type CoachContextContributor } from "../host.ts";
import { readCoachMemory } from "./memory_source.ts";

export const coachNotesContributorId = "coach_notes";
export const coachNotesContributorBudgetChars = 3_600;

export function createCoachNotesContributor(
  read: typeof readCoachMemory,
): CoachContextContributor {
  return {
    id: coachNotesContributorId,
    slot: "volatile",
    budgetChars: coachNotesContributorBudgetChars,
    async render(input) {
      const memory = await read(input);
      const marked = memory
        ? renderCoachNotesMarked(memory.notes, coachNotesContributorBudgetChars)
        : null;
      return marked === null ? null : blockOf(marked);
    },
  };
}

export const coachNotesContributor = createCoachNotesContributor(readCoachMemory);
