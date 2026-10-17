// Coach proposals (A8): the public surface Coach chat uses.
export { buildCoachProposal, buildFromRawIntent } from "./build.ts";
export { parseCoachProposalIntent } from "./intent.ts";
export {
  type ProposalRpc,
  proposeCoachChange,
  type ProposeRequest,
  type ProposeResult,
} from "./service.ts";
export { parseAthleteState } from "./state.ts";
export {
  type AthleteState,
  type BuildResult,
  type CoachProposal,
  type CoachProposalIntent,
  type ProposalKind,
  proposalKinds,
  proposalReasons,
  type RefusalCode,
} from "./types.ts";
