// Contract 7 contributor (A8): what Coach proposed and how the athlete answered, the temporary
// block that is running and the day it ends, and the goal phase with its end date. A diet break or
// a block that has ended is reported as ended, because nothing reverts nutrition by itself: Coach
// raises the next step as a new proposal. It reads get_coach_proposals_context_v1 (service role).
import type { CoachContextContributor } from "../host.ts";
import { coachServiceRpc, type StateSource, stateSourceFromRpc } from "../service_source.ts";

export const proposalsContributorId = "coach_proposals";
export const proposalsContributorBudgetChars = 1_800;

type Json = Record<string, unknown>;
const rec = (value: unknown): Json =>
  value && typeof value === "object" && !Array.isArray(value) ? value as Json : {};
const str = (value: unknown): string | null =>
  typeof value === "string" && value !== "" ? value : null;

export type ProposalsState = Readonly<{
  localDate: string;
  block: Readonly<{ title: string; kind: string; endsOn: string }> | null;
  phase: Readonly<{ phase: string; startedOn: string | null; endsOn: string | null }> | null;
  proposals: readonly Readonly<{
    kind: string;
    title: string;
    status: string;
    createdOn: string;
    expiresOn: string | null;
    endsOn: string | null;
  }>[];
}>;

export function parseProposalsState(payload: unknown): ProposalsState | null {
  const body = rec(payload);
  const localDate = str(body.local_date);
  if (!str(body.schema_version)?.startsWith("1.") || !localDate) return null;
  const block = rec(body.block);
  const phase = rec(body.phase);
  return {
    localDate,
    block: str(block.title) && str(block.ends_on)
      ? { title: str(block.title)!, kind: str(block.kind) ?? "", endsOn: str(block.ends_on)! }
      : null,
    phase: str(phase.phase)
      ? {
        phase: str(phase.phase)!,
        startedOn: str(phase.started_on),
        endsOn: str(phase.ends_on),
      }
      : null,
    proposals: (Array.isArray(body.proposals) ? body.proposals : []).flatMap((item) => {
      const row = rec(item);
      const title = str(row.title);
      const status = str(row.status);
      return title && status
        ? [{
          kind: str(row.kind) ?? "",
          title,
          status,
          createdOn: str(row.created_on) ?? "",
          expiresOn: str(row.expires_at)?.slice(0, 10) ?? null,
          endsOn: str(row.ends_on),
        }]
        : [];
    }),
  };
}

const phaseWords: Readonly<Record<string, string>> = {
  cut: "a fat-loss phase",
  maintenance: "maintenance",
  diet_break: "a diet break",
  gain: "a gain phase",
};

const statusWords: Readonly<Record<string, string>> = {
  accepted: "approved and applied",
  declined: "declined (not now)",
  changed: "sent back for changes",
  expired: "expired unanswered",
  undone: "approved, then undone",
};

export function renderProposals(state: ProposalsState | null): string | null {
  if (!state) return null;
  const lines: string[] = [];
  if (state.block) {
    lines.push(
      `A temporary change is running: "${state.block.title}" until ${state.block.endsOn}. The ` +
        "regular plan returns by itself the day after.",
    );
  }
  if (state.phase) {
    const name = phaseWords[state.phase.phase] ?? state.phase.phase;
    const ended = state.phase.endsOn !== null && state.phase.endsOn < state.localDate;
    lines.push(
      ended
        ? `The athlete's ${name} ended on ${state.phase.endsOn}. Nutrition does not change back by ` +
          "itself: suggest the next step (resume the deficit or stay at maintenance) as a " +
          "proposal for the athlete to approve."
        : `The athlete is in ${name}${
          state.phase.startedOn ? ` since ${state.phase.startedOn}` : ""
        }${state.phase.endsOn ? `, ending ${state.phase.endsOn}` : ""}.`,
    );
  }
  const waiting = state.proposals.filter((item) => item.status === "pending");
  if (waiting.length) {
    lines.push(
      "Waiting for the athlete to answer (not applied yet): " +
        waiting.map((item) =>
          `"${item.title}"${item.expiresOn ? ` (open until ${item.expiresOn})` : ""}`
        ).join("; ") + ".",
    );
  }
  const answered = state.proposals.filter((item) => item.status !== "pending").slice(0, 5);
  if (answered.length) {
    lines.push(
      "Recent proposals: " +
        answered.map((item) => {
          const ended = item.status === "accepted" && item.endsOn !== null &&
            item.endsOn < state.localDate;
          return `"${item.title}", ${item.createdOn}: ${statusWords[item.status] ?? item.status}${
            ended ? `, ended ${item.endsOn}` : ""
          }`;
        }).join("; ") + ".",
    );
  }
  if (lines.length === 0) return null;
  return [
    "Coach proposals (Tracend's record; a change happens only when the athlete approves it):",
    ...lines,
  ].join("\n");
}

export function createProposalsContributor(source: StateSource): CoachContextContributor {
  return {
    id: proposalsContributorId,
    slot: "volatile",
    budgetChars: proposalsContributorBudgetChars,
    async render(input) {
      const state = parseProposalsState(await source(input.userId, input.localDate));
      const text = renderProposals(state);
      if (text === null) return null;
      // How many proposals wait for an answer, for the route (coach_chat_provider_route.ts).
      return {
        text,
        shown: {},
        trace: { waiting: state!.proposals.filter((item) => item.status === "pending").length },
      };
    },
  };
}

export const proposalsContributor: CoachContextContributor = createProposalsContributor(
  stateSourceFromRpc(coachServiceRpc, "get_coach_proposals_context_v1"),
);
