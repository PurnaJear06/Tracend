// Contract 7 contributor (A10 part 2): the facts the athlete confirmed, in the stable part of the
// Coach's file. They rank below Tracend's own calculations and above the Coach's notes, earlier
// messages and the library. Only the athlete writes them; this reads them.
import { renderConfirmedFacts } from "../../coach_memory/facts.ts";
import type { CoachContextContributor } from "../host.ts";
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
      return memory
        ? renderConfirmedFacts(memory.facts, input.localDate, confirmedFactsContributorBudgetChars)
        : null;
    },
  };
}

export const confirmedFactsContributor = createConfirmedFactsContributor(readCoachMemory);
