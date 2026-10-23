// Contract 7 contributor (A10 part 2): the facts the athlete confirmed, in the stable part of the
// Coach's file. They rank below Tracend's own calculations and above the Coach's notes, earlier
// messages and the library. Only the athlete writes them; this reads them.
import { renderConfirmedFactsMarked } from "../../coach_memory/facts.ts";
import { blockOf, type CoachContextContributor } from "../host.ts";
import { readCoachMemory } from "./memory_source.ts";

export const confirmedFactsContributorId = "confirmed_facts";
export const confirmedFactsContributorBudgetChars = 4_200;

export function createConfirmedFactsContributor(
  read: typeof readCoachMemory,
): CoachContextContributor {
  return {
    id: confirmedFactsContributorId,
    slot: "stable",
    budgetChars: confirmedFactsContributorBudgetChars,
    async render(input) {
      const memory = await read(input);
      const marked = memory
        ? renderConfirmedFactsMarked(
          memory.facts,
          input.localDate,
          confirmedFactsContributorBudgetChars,
        )
        : null;
      return marked === null ? null : blockOf(marked);
    },
  };
}

export const confirmedFactsContributor = createConfirmedFactsContributor(readCoachMemory);
