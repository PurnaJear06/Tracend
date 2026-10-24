// training-proposals (owner decision O7): the one place the rules start a training proposal. Today
// that is the deload Tracend suggests on Train ("A lighter week could help"). The athlete taps the
// card; this stores the pending proposal; the athlete's own answer applies it, through the same
// proposal path as Coach (respond_to_coach_proposal_v1). No model is called and nothing is applied.
//
// The caller is the signed-in athlete and nobody else: the user is `auth.uid()` from the JWT, never
// a field of the body. The guidance is read through the athlete's own reader, so the server's own
// day, the safety route and every suppression decide whether a deload may be offered at all. The
// call is idempotent: while a deload is pending it returns that proposal and stores nothing.
import { AuthError, reply, type requireAuth } from "../_shared/auth.ts";
import { captureException } from "../_shared/sentry.ts";
import { type ProposalRpc, proposeSuggestedDeload } from "../_shared/coach_proposals/service.ts";
import { parseTrainingGuidance } from "../_shared/training/guidance/payload.ts";

export type Auth = Awaited<ReturnType<typeof requireAuth>>;

export type TrainingProposalsDeps = Readonly<{
  requireAuth: (request: Request) => Promise<Auth>;
  /** Reports an unexpected failure by its fixed name; production sends it to Sentry. */
  capture?: (event: string) => void;
}>;

/** The one event name an unexpected failure is reported under: nothing of the request or the error. */
export const unexpectedEvent = "training_proposals_unexpected";

const sentry = (event: string) =>
  captureException(new Error(event), { functionName: "training-proposals", runtime: "edge" });

/** Proposal kinds that change the plan: storing a new one expires every open one of these. */
const planChangingKinds = [
  "temporary_block",
  "training_schedule",
  "exercise_swap",
  "intensity_or_phase",
  "next_session_adjustment",
] as const;

/** An open proposal that would be expired by storing a deload, other than a deload itself. */
function openPlanChange(raw: unknown): boolean | null {
  const body = typeof raw === "object" && raw !== null ? raw as { proposals?: unknown } : null;
  if (!body || !Array.isArray(body.proposals)) return null;
  let open = false;
  for (const item of body.proposals) {
    if (typeof item !== "object" || item === null) return null;
    const { kind, status, title } = item as Record<string, unknown>;
    if (typeof kind !== "string" || typeof status !== "string") return null;
    const deload = kind === "intensity_or_phase" && typeof title === "string" &&
      title.startsWith("Deload until ");
    if (
      status === "pending" && !deload &&
      (planChangingKinds as readonly string[]).includes(kind)
    ) open = true;
  }
  return open;
}

export const trainingProposalsSchemaVersion = "1.0";

const isoDate = /^\d{4}-\d{2}-\d{2}$/;

/** The only request: the deload the rules suggest, for the athlete's own day as the server named it. */
function parseRequest(raw: unknown): { localDate: string } | null {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return null;
  const body = raw as Record<string, unknown>;
  const keys = Object.keys(body).sort().join(",");
  if (keys !== "kind,local_date,schema_version") return null;
  if (
    body.schema_version !== trainingProposalsSchemaVersion || body.kind !== "deload" ||
    typeof body.local_date !== "string" || !isoDate.test(body.local_date)
  ) return null;
  return { localDate: body.local_date };
}

export function trainingProposalsHandler(deps: TrainingProposalsDeps) {
  const capture = deps.capture ?? sentry;
  return async (request: Request): Promise<Response> => {
    try {
      return await handle(request, deps);
    } catch (e) {
      if (e instanceof AuthError) return reply(e.status, { error: e.message });
      // An unexpected failure answers like an unavailable one and is reported by name only: the
      // error and the request can hold the athlete's data.
      capture(unexpectedEvent);
      return reply(503, { error: "unavailable" });
    }
  };
}

async function handle(request: Request, deps: TrainingProposalsDeps): Promise<Response> {
  if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });
  const auth = await deps.requireAuth(request);

  let input: { localDate: string } | null;
  try {
    input = parseRequest(await request.json());
  } catch {
    input = null;
  }
  if (!input) return reply(422, { error: "invalid_request" });

  // The athlete's own reader: it answers for the server's own today only (22023 otherwise).
  const read = await auth.userClient.rpc("get_my_training_guidance_v1", {
    local_date: input.localDate,
  });
  if (read.error) {
    return read.error.code === "22023"
      ? reply(422, { error: "wrong_date" })
      : reply(503, { error: "guidance_unavailable" });
  }
  const guidance = parseTrainingGuidance(read.data);
  if (!guidance) return reply(503, { error: "guidance_unavailable" });
  const deload = guidance.deload;

  // Asked again while one is open: that same proposal, nothing new stored.
  if (deload.status === "pending" && deload.proposalId !== null) {
    return reply(200, {
      schema_version: trainingProposalsSchemaVersion,
      proposal_id: deload.proposalId,
      created: false,
    });
  }
  // Only a suggestion the rules stand behind today becomes a proposal.
  if (deload.status !== "suggested") {
    return reply(409, { error: "not_suggested", status: deload.status });
  }

  // Storing a plan change expires every open one. Another change the athlete has not answered is
  // theirs to answer first: it is never expired by a tap on a suggestion.
  const proposals = await auth.userClient.rpc("get_my_coach_proposals_v1", { p_limit: 50 });
  const open = proposals.error ? null : openPlanChange(proposals.data);
  if (open === null) return reply(503, { error: "proposals_unavailable" });
  if (open) return reply(409, { error: "other_proposal_pending" });

  const rpc: ProposalRpc = (name, params) => auth.serviceClient.rpc(name, params);
  const stored = await proposeSuggestedDeload(rpc, {
    userId: auth.userId,
    reasons: deload.reasons,
  });
  if (!stored.ok) {
    // The refusal's code only: its words are Coach's, and the app words it as Tracend's.
    return stored.code === "unavailable"
      ? reply(503, { error: "proposal_unavailable" })
      : reply(409, { error: stored.code });
  }
  return reply(200, {
    schema_version: trainingProposalsSchemaVersion,
    proposal_id: stored.proposalId,
    created: true,
  });
}
