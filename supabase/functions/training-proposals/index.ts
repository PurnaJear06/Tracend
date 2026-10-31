import { requireAuth } from "../_shared/auth.ts";
import { trainingProposalsHandler } from "./handler.ts";

Deno.serve(trainingProposalsHandler({ requireAuth }));
