import { requireAuth } from "../_shared/auth.ts";
import { coachDecideHandler } from "./handler.ts";

Deno.serve(coachDecideHandler({ requireAuth }));
