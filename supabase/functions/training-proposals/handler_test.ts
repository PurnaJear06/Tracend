// training-proposals end to end with fake Supabase clients: when a deload is stored, when the call
// stores nothing, and that no body can name another athlete.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { AuthError } from "../_shared/auth.ts";
import { proposalRpcPayloads, today } from "../_shared/coach_proposals/fixtures.ts";
import { type Auth, trainingProposalsHandler } from "./handler.ts";

const athlete = "00000000-0000-4000-8000-0000000000aa";
const proposalId = "00000000-0000-4000-8000-0000000000b1";

type Call = { name: string; params: Record<string, unknown> };
type Answer = { data?: unknown; error?: { code?: string; message?: string } };

const deload = (over: Record<string, unknown>) => ({
  status: "suggested",
  reasons: ["performance_drop", "run_down"],
  last_ended_on: null,
  weeks_since: 9,
  proposal_id: null,
  suppressed_by: null,
  ...over,
});

const guidance = (over: Record<string, unknown> = {}, safetyRoute: string | null = null) => ({
  schema_version: "1.1",
  local_date: today,
  safety_route: safetyRoute,
  deload: deload(over),
  cardio_withheld: safetyRoute ? "safety_route" : null,
  cardio_week: null,
  ...(safetyRoute ? {} : {
    cardio_week: {
      target_min: 150,
      stretch_max: 300,
      done_min: 85,
      intensity_known: false,
      vigorous_allowed: true,
      vigorous_sessions_max: 2,
      vigorous_counts_as: 2,
      lift_separation_hours: 3,
      easy_hr_reserve_max: 60,
      window_from: "2026-10-12",
      window_to: today,
    },
  }),
});

function setup(
  userAnswer: Answer,
  serviceOverrides: Record<string, Answer> = {},
  inputs: ReturnType<typeof proposalRpcPayloads> = proposalRpcPayloads(),
) {
  const userCalls: Call[] = [];
  const serviceCalls: Call[] = [];
  const serviceTable: Record<string, unknown> = {
    get_coach_proposal_inputs_v1: inputs.inputs,
    get_goal_phase_inputs_v1: inputs.goalPhase,
    get_progression_summary_v1: inputs.progression,
    persist_suggested_deload_v1: {
      schema_version: "1.0",
      proposal_id: proposalId,
      expires_at: "2026-10-21T10:00:00Z",
    },
  };
  const auth = {
    userId: athlete,
    userEmail: "athlete@example.test",
    userClient: {
      rpc: (name: string, params: Record<string, unknown>) => {
        userCalls.push({ name, params });
        return Promise.resolve({ data: userAnswer.data ?? null, error: userAnswer.error ?? null });
      },
    },
    serviceClient: {
      rpc: (name: string, params: Record<string, unknown>) => {
        serviceCalls.push({ name, params });
        const override = serviceOverrides[name];
        return Promise.resolve(
          override
            ? { data: override.data ?? null, error: override.error ?? null }
            : { data: serviceTable[name], error: null },
        );
      },
    },
  } as unknown as Auth;
  const handler = trainingProposalsHandler({ requireAuth: () => Promise.resolve(auth) });
  return { handler, userCalls, serviceCalls };
}

const request = (body: unknown = {
  schema_version: "1.0",
  kind: "deload",
  local_date: today,
}, method = "POST") =>
  new Request("https://edge.test/training-proposals", {
    method,
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });

const persisted = (calls: Call[]) => calls.filter((c) => c.name === "persist_suggested_deload_v1");

Deno.test("a suggested deload is stored as a pending proposal and nothing is applied", async () => {
  const { handler, userCalls, serviceCalls } = setup({ data: guidance() });
  const response = await handler(request());
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    schema_version: "1.0",
    proposal_id: proposalId,
    created: true,
  });
  // The athlete's own reader, for the day the app sent.
  assertEquals(userCalls, [{ name: "get_my_training_guidance_v1", params: { local_date: today } }]);
  const [store] = persisted(serviceCalls);
  assertEquals(persisted(serviceCalls).length, 1);
  assertEquals(store.params.p_user_id, athlete);
  assertEquals(store.params.p_kind, "intensity_or_phase");
  assertEquals(store.params.p_source_message_id, null);
  const payload = store.params.p_payload as {
    training: { block_kind: string; intensity_level: string; block_weeks: number };
  };
  assertEquals(payload.training.block_kind, "intensity");
  assertEquals(payload.training.intensity_level, "deload");
  assertEquals(payload.training.block_weeks, 1);
  // The reasons are the rules' own, in the athlete's terms; no model words them.
  const rationale = String(store.params.p_rationale);
  assertStringIncludes(rationale, "stalled or slipped");
  assertStringIncludes(rationale, "readiness has read low");
  assertEquals(rationale.includes("You've been feeling worn down"), false);
  assertEquals(
    (store.params.p_evidence as { code: string }[]).some((e) => e.code === "DELOAD_SIGNALS"),
    true,
  );
  // Only reads and the one store: nothing answers the proposal.
  assertEquals(
    serviceCalls.map((c) => c.name).filter((n) => n !== "persist_suggested_deload_v1").sort(),
    ["get_coach_proposal_inputs_v1", "get_goal_phase_inputs_v1", "get_progression_summary_v1"],
  );
});

Deno.test("the week is the same one-week deload Coach would propose, from the same builder", async () => {
  const { handler, serviceCalls } = setup({ data: guidance({ reasons: ["block_done"] }) });
  await handler(request());
  const [store] = persisted(serviceCalls);
  assertStringIncludes(String(store.params.p_rationale), "full block");
  const training = (store.params.p_payload as {
    training: { weekly_structure: { exercises: { sets: number; target_rpe: number | null }[] }[] };
  }).training;
  const planned = proposalRpcPayloads().inputs.plan.workouts;
  training.weekly_structure.forEach((workout, w) =>
    workout.exercises.forEach((exercise, e) => {
      assertEquals(exercise.sets, Math.max(1, Math.ceil(planned[w].exercises[e].sets / 2)));
      assert((exercise.target_rpe ?? 7) <= 7);
    })
  );
});

Deno.test("asking again while one is open returns it and stores nothing", async () => {
  const { handler, serviceCalls } = setup({
    data: guidance({ status: "pending", reasons: ["run_down"], proposal_id: proposalId }),
  });
  const response = await handler(request());
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    schema_version: "1.0",
    proposal_id: proposalId,
    created: false,
  });
  assertEquals(serviceCalls, []);
});

Deno.test("nothing is stored unless the rules suggest a deload today", async () => {
  const states: Record<string, unknown>[] = [
    { status: "not_due", reasons: [], suppressed_by: "recent_deload" },
    { status: "not_due", reasons: [], suppressed_by: "declined_recently" },
    { status: "not_due", reasons: [], suppressed_by: "not_enough_training" },
    { status: "not_due", reasons: [], suppressed_by: "screening" },
    { status: "not_due", reasons: [] },
    { status: "running", reasons: [], proposal_id: proposalId },
  ];
  for (const state of states) {
    const { handler, serviceCalls } = setup({ data: guidance(state) });
    const response = await handler(request());
    assertEquals(response.status, 409, JSON.stringify(state));
    assertEquals((await response.json()).error, "not_suggested");
    assertEquals(serviceCalls, []);
  }
});

Deno.test("a day with a safety route stores nothing, however the payload reads", async () => {
  // As the database answers it: the suggestion is suppressed.
  const suppressed = setup({
    data: guidance({ status: "not_due", reasons: [], suppressed_by: "safety_route" }, "clinician"),
  });
  assertEquals((await suppressed.handler(request())).status, 409);
  assertEquals(suppressed.serviceCalls, []);
  // A payload that contradicts itself (a suggestion on a route day) is not trusted.
  const contradiction = setup({ data: guidance({}, "clinician") });
  assertEquals((await contradiction.handler(request())).status, 503);
  assertEquals(contradiction.serviceCalls, []);
});

Deno.test("a guidance this version cannot read stores nothing", async () => {
  const unknownStatus = setup({ data: guidance({ status: "a_status_from_the_future" }) });
  assertEquals((await unknownStatus.handler(request())).status, 503);
  const nothing = setup({ data: null });
  assertEquals((await nothing.handler(request())).status, 503);
  const failing = setup({ error: { code: "XX000" } });
  const response = await failing.handler(request());
  assertEquals(response.status, 503);
  assertEquals((await response.json()).error, "guidance_unavailable");
  for (const run of [unknownStatus, nothing, failing]) assertEquals(run.serviceCalls, []);
});

Deno.test("a day that is not the server's today is refused", async () => {
  const { handler, serviceCalls } = setup({ error: { code: "22023" } });
  const response = await handler(request());
  assertEquals(response.status, 422);
  assertEquals((await response.json()).error, "wrong_date");
  assertEquals(serviceCalls, []);
});

Deno.test("the body can only ask for the deload on a day: it can name no athlete", async () => {
  const bodies: unknown[] = [
    { schema_version: "1.0", kind: "deload", local_date: today, user_id: "someone-else" },
    { schema_version: "1.0", kind: "deload", local_date: today, p_user_id: "someone-else" },
    { schema_version: "1.0", kind: "moderate", local_date: today },
    { schema_version: "1.0", kind: "deload", local_date: "tomorrow" },
    { schema_version: "2.0", kind: "deload", local_date: today },
    { schema_version: "1.0", kind: "deload" },
    [],
    "deload",
  ];
  for (const body of bodies) {
    const { handler, userCalls, serviceCalls } = setup({ data: guidance() });
    const response = await handler(request(body));
    assertEquals(response.status, 422, JSON.stringify(body));
    assertEquals((await response.json()).error, "invalid_request");
    assertEquals([userCalls, serviceCalls], [[], []]);
  }
  const { handler } = setup({ data: guidance() });
  const unreadable = await handler(
    new Request("https://edge.test/training-proposals", { method: "POST", body: "{" }),
  );
  assertEquals(unreadable.status, 422);
});

Deno.test("the athlete is the signed-in one and the method is POST", async () => {
  const { handler, serviceCalls } = setup({ data: guidance() });
  assertEquals((await handler(request(undefined, "GET"))).status, 405);
  const denied = trainingProposalsHandler({
    requireAuth: () => Promise.reject(new AuthError("invalid_session", 401)),
  });
  const response = await denied(request());
  assertEquals(response.status, 401);
  assertEquals((await response.json()).error, "invalid_session");
  assertEquals(serviceCalls, []);
  await handler(request());
  assertEquals(persisted(serviceCalls)[0].params.p_user_id, athlete);
});

Deno.test("the builder's own refusals come back as a code only and store nothing", async () => {
  const data = proposalRpcPayloads();
  data.inputs.screening = "see_professional";
  const { handler, serviceCalls } = setup({ data: guidance() }, {}, data);
  const response = await handler(request());
  assertEquals(response.status, 409);
  const body = await response.json();
  assertEquals(body.error, "screening_see_professional");
  // Only the code: the refusal's words are Coach's, the app words it as Tracend's.
  assertEquals(Object.keys(body), ["error"]);
  assertEquals(persisted(serviceCalls), []);
});

Deno.test("a plan that moved on, or a failed store, stores nothing and leaks no detail", async () => {
  const moved = setup({ data: guidance() }, {
    persist_suggested_deload_v1: {
      error: { code: "55000", message: "the plan changed while the proposal was built" },
    },
  });
  const changed = await moved.handler(request());
  assertEquals(changed.status, 409);
  assertEquals((await changed.json()).error, "plan_changed");
  const broken = setup({ data: guidance() }, {
    persist_suggested_deload_v1: { error: { code: "XX000", message: "relation secret_table" } },
  });
  const failed = await broken.handler(request());
  assertEquals(failed.status, 503);
  assertEquals(JSON.stringify(await failed.json()).includes("secret_table"), false);
  const unreadable = setup({ data: guidance() }, { get_coach_proposal_inputs_v1: { data: null } });
  assertEquals((await unreadable.handler(request())).status, 409);
});

Deno.test("a change waiting in Coach is never expired by a tap on a suggestion", async () => {
  // The refusal is the store's own, in the transaction that would have expired it.
  const { handler, serviceCalls, userCalls } = setup({ data: guidance() }, {
    persist_suggested_deload_v1: {
      error: { code: "TP001", message: "another change is waiting for an answer" },
    },
  });
  const response = await handler(request());
  assertEquals(response.status, 409);
  assertEquals(await response.json(), { error: "other_proposal_pending" });
  assertEquals(persisted(serviceCalls).length, 1, "the store was asked once and refused");
  // No check ahead of the store that another store could slip past.
  assertEquals(userCalls.map((c) => c.name), ["get_my_training_guidance_v1"]);
});

Deno.test("the rules' deload is stored through their own store, never the general one", async () => {
  const { handler, serviceCalls } = setup({ data: guidance() });
  await handler(request());
  assertEquals(
    serviceCalls.filter((c) => c.name === "persist_coach_proposal_v1"),
    [],
  );
  assertEquals(persisted(serviceCalls).length, 1);
});

Deno.test("an unexpected failure answers 503 and is reported by a fixed name only", async () => {
  const seen: unknown[][] = [];
  const secret = "athlete@example.test lifts 142.5 kg";
  const failing = trainingProposalsHandler({
    requireAuth: () =>
      Promise.resolve({
        userId: athlete,
        userEmail: secret,
        userClient: {
          rpc: () => {
            throw new Error(secret);
          },
        },
        serviceClient: {},
      } as unknown as Auth),
    capture: (...args) => seen.push(args),
  });
  const response = await failing(request());
  assertEquals(response.status, 503);
  const body = await response.json();
  assertEquals(body, { error: "unavailable" });
  assertEquals(seen, [["training_proposals_unexpected"]]);
  assertEquals(JSON.stringify([body, seen]).includes("142.5"), false);
  assertEquals(JSON.stringify([body, seen]).includes("example.test"), false);

  // A thrown auth failure still answers as one.
  const unauthorized = trainingProposalsHandler({
    requireAuth: () => Promise.reject(new AuthError("invalid_session", 401)),
    capture: (...args) => seen.push(args),
  });
  assertEquals((await unauthorized(request())).status, 401);
  assertEquals(seen.length, 1, "an auth failure is not an unexpected failure");
});
