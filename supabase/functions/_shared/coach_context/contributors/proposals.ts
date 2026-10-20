// Contract 7 contributor (A8): what Coach proposed and how the athlete answered, the temporary
// block that is running and the day it ends, and the goal phase with its end date. A diet break or
// a block that has ended is reported as ended, because nothing reverts nutrition by itself: Coach
// raises the next step as a new proposal. It reads get_coach_proposals_context_v1 (service role).
//
// A pending proposal's figures (its targets, the sessions a week it would set) are Tracend's own
// (the proposal rules built them), so they ground a figure in a reply, but as the proposal's:
// never as the athlete's target, which a proposal is not until it is approved. They are stated on
// their own line, marked as proposal figures (`figure`, `RenderedBlock.figures`). A proposal's title
// is Tracend's text for it (`columnGrounding`: change_proposals.title) and counts the same way. The
// dates and the rest are records; the words around them ground nothing.
import { figure, record } from "../../recorded_text.ts";
import { blockOf, type CoachContextContributor, type RenderedBlock } from "../host.ts";
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
    figures: ProposalFigures | null;
  }>[];
}>;

/** What a pending proposal would set; each is absent when the proposal does not change it. */
export type ProposalFigures = Readonly<{
  calories?: number;
  proteinG?: number;
  carbohydrateG?: number;
  fatG?: number;
  sessionsPerWeek?: number;
  blockWeeks?: number;
}>;

const fin = (value: unknown): number | undefined =>
  typeof value === "number" && Number.isFinite(value) ? value : undefined;

function parseFigures(value: unknown): ProposalFigures | null {
  const body = rec(value);
  const figures: ProposalFigures = {
    ...(fin(body.calories) === undefined ? {} : { calories: fin(body.calories) }),
    ...(fin(body.protein_g) === undefined ? {} : { proteinG: fin(body.protein_g) }),
    ...(fin(body.carbohydrate_g) === undefined ? {} : { carbohydrateG: fin(body.carbohydrate_g) }),
    ...(fin(body.fat_g) === undefined ? {} : { fatG: fin(body.fat_g) }),
    ...(fin(body.sessions_per_week) === undefined
      ? {}
      : { sessionsPerWeek: fin(body.sessions_per_week) }),
    ...(fin(body.block_weeks) === undefined ? {} : { blockWeeks: fin(body.block_weeks) }),
  };
  return Object.keys(figures).length === 0 ? null : figures;
}

/** The words for what a proposal would set, or null when it sets no figure. */
export function figuresText(figures: ProposalFigures): string {
  return [
    figures.calories === undefined ? null : `${figures.calories} kcal a day`,
    figures.proteinG === undefined ? null : `${figures.proteinG} g protein`,
    figures.carbohydrateG === undefined ? null : `${figures.carbohydrateG} g carbohydrate`,
    figures.fatG === undefined ? null : `${figures.fatG} g fat`,
    figures.sessionsPerWeek === undefined ? null : `${figures.sessionsPerWeek} sessions a week`,
    figures.blockWeeks === undefined ? null : `a ${figures.blockWeeks}-week block`,
  ].filter((part) => part !== null).join(", ");
}

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
          figures: parseFigures(row.figures),
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

/** The lines of the block that state a pending proposal's figures. */
function figureLines(state: ProposalsState): string[] {
  return state.proposals.filter((item) => item.status === "pending" && item.figures !== null)
    .slice(0, 3).map((item) =>
      `The pending proposal "${figure(item.title)}" would set ${
        figure(figuresText(item.figures!))
      } if approved. These are the proposal's figures: the athlete's own targets stay as they are until it is approved.`
    );
}

export function renderProposals(state: ProposalsState | null): string | null {
  return renderProposalsBlock(state)?.text ?? null;
}

/** The block: its text, and the values in it (the dates are records, a proposal's text is figures). */
export function renderProposalsBlock(state: ProposalsState | null): RenderedBlock | null {
  const marked = proposalsMarked(state);
  return marked === null ? null : blockOf(marked);
}

function proposalsMarked(state: ProposalsState | null): string | null {
  if (!state) return null;
  const lines: string[] = [];
  if (state.block) {
    lines.push(
      `A temporary change is running: "${figure(state.block.title)}" until ${
        record(state.block.endsOn)
      }. The regular plan returns by itself the day after.`,
    );
  }
  if (state.phase) {
    const name = phaseWords[state.phase.phase] ?? state.phase.phase;
    const ended = state.phase.endsOn !== null && state.phase.endsOn < state.localDate;
    lines.push(
      ended
        ? `The athlete's ${name} ended on ${
          record(state.phase.endsOn!)
        }. Nutrition does not change back by ` +
          "itself: suggest the next step (resume the deficit or stay at maintenance) as a " +
          "proposal for the athlete to approve."
        : `The athlete is in ${name}${
          state.phase.startedOn ? ` since ${record(state.phase.startedOn)}` : ""
        }${state.phase.endsOn ? `, ending ${record(state.phase.endsOn)}` : ""}.`,
    );
  }
  const waiting = state.proposals.filter((item) => item.status === "pending");
  if (waiting.length) {
    lines.push(
      "Waiting for the athlete to answer (not applied yet): " +
        waiting.map((item) =>
          `"${figure(item.title)}"${
            item.expiresOn ? ` (open until ${record(item.expiresOn)})` : ""
          }`
        ).join("; ") + ".",
    );
  }
  lines.push(...figureLines(state));
  const answered = state.proposals.filter((item) => item.status !== "pending").slice(0, 5);
  if (answered.length) {
    lines.push(
      "Recent proposals: " +
        answered.map((item) => {
          const ended = item.status === "accepted" && item.endsOn !== null &&
            item.endsOn < state.localDate;
          return `"${figure(item.title)}", ${record(item.createdOn)}: ${
            statusWords[item.status] ?? item.status
          }${ended ? `, ended ${record(item.endsOn!)}` : ""}`;
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
      const block = renderProposalsBlock(state);
      if (block === null) return null;
      // How many proposals wait for an answer, for the route (coach_chat_provider_route.ts).
      return {
        ...block,
        trace: { waiting: state!.proposals.filter((item) => item.status === "pending").length },
      };
    },
  };
}

export const proposalsContributor: CoachContextContributor = createProposalsContributor(
  stateSourceFromRpc(coachServiceRpc, "get_coach_proposals_context_v1"),
);
