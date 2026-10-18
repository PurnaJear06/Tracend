// Contract 7 contributor (A10 part 2): the Coach's own notes about earlier conversations and
// advice, capped and dated, labelled as untrusted. They rank below the confirmed facts and the
// athlete's recent statements.
import { renderCoachNotes } from "../../coach_memory/notes_render.ts";
import type { CoachContextContributor } from "../host.ts";
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
      return memory ? renderCoachNotes(memory.notes, coachNotesContributorBudgetChars) : null;
    },
  };
}

export const coachNotesContributor = createCoachNotesContributor(readCoachMemory);
