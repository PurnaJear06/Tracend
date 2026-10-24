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
import { type ProposalRpc, proposeSuggestedDeload } from "../_shared/coach_proposals/service.ts";
import { parseTrainingGuidance } from "../_shared/training/guidance/payload.ts";

export type Auth = Awaited<ReturnType<typeof requireAuth>>;

export type TrainingProposalsDeps = Readonly<{
  requireAuth: (request: Request) => Promise<Auth>;
}>;

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
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });
    let auth: Auth;
    try {
      auth = await deps.requireAuth(request);
    } catch (e) {
      if (e instanceof AuthError) return reply(e.status, { error: e.message });
      throw e;
    }

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

    const rpc: ProposalRpc = (name, params) => auth.serviceClient.rpc(name, params);
    const stored = await proposeSuggestedDeload(rpc, {
      userId: auth.userId,
      reasons: deload.reasons,
    });
    if (!stored.ok) {
      return stored.code === "unavailable"
        ? reply(503, { error: "proposal_unavailable" })
        : reply(409, { error: stored.code, reason: stored.reason });
    }
    return reply(200, {
      schema_version: trainingProposalsSchemaVersion,
      proposal_id: stored.proposalId,
      created: true,
    });
  };
}
