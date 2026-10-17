// Contract 7 contributor (A10): an index of what the athlete's records hold, so Coach knows what
// it can look up and how far back each kind goes. It reads get_coach_data_index_v1 (service role):
// per kind of record the first and last date and a count, nothing else. The rules for asking
// (data_requests) are in the Coach instructions; the lookup names here are the catalogue's.
import { coachLookupNames } from "../../coach_lookups/catalogue.ts";
import type { CoachContextContributor } from "../host.ts";
import { coachServiceRpc, type StateSource, stateSourceFromRpc } from "../service_source.ts";

export const dataIndexContributorId = "data_index";
export const dataIndexContributorBudgetChars = 1_600;

type Json = Record<string, unknown>;
const rec = (value: unknown): Json =>
  value && typeof value === "object" && !Array.isArray(value) ? value as Json : {};

const nouns: Readonly<Record<string, string>> = {
  workouts: "completed workouts",
  meals: "days with confirmed meals",
  body: "weight and tape readings",
  check_ins: "daily check-ins",
  recovery: "days of watch and recovery data",
  plan_history: "training plan versions",
  goals: "goals",
  weekly_reviews: "weekly reviews",
  physique: "physique checks",
  health_history: "months imported from Apple Health at onboarding",
};

/** The text for one index payload. Exposed for tests. */
export function renderDataIndex(payload: unknown, localDate: string): string | null {
  const body = rec(payload);
  if (typeof body.schema_version !== "string" || !body.schema_version.startsWith("1.")) {
    return null;
  }
  const domains = rec(body.domains);
  const held: string[] = [];
  const empty: string[] = [];
  for (const name of coachLookupNames) {
    if (name === "exercise_history") continue;
    const domain = rec(domains[name]);
    const count = typeof domain.count === "number" ? domain.count : 0;
    if (count === 0 || typeof domain.first !== "string" || typeof domain.last !== "string") {
      empty.push(name);
      continue;
    }
    held.push(
      `- ${name}: ${String(domain.first).slice(0, 10)} to ${
        String(domain.last).slice(0, 10)
      }, ${count} ${nouns[name] ?? "records"}`,
    );
  }
  return [
    `Records the athlete has, by lookup name (first to last date, today is ${localDate}). The ` +
    "sections above show only the recent part; anything else, or any other period, you can look up " +
    "with data_requests:",
    ...held,
    empty.length ? `No records yet for: ${empty.join(", ")}.` : "",
    "exercise_history reads one exercise out of the workouts.",
  ].filter(Boolean).join("\n");
}

export function createDataIndexContributor(source: StateSource): CoachContextContributor {
  return {
    id: dataIndexContributorId,
    slot: "volatile",
    budgetChars: dataIndexContributorBudgetChars,
    async render(input) {
      return renderDataIndex(await source(input.userId, input.localDate), input.localDate);
    },
  };
}

export const dataIndexContributor: CoachContextContributor = createDataIndexContributor(
  stateSourceFromRpc(coachServiceRpc, "get_coach_data_index_v1"),
);
