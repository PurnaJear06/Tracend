import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { proposalRpcPayloads, stateFixture, today } from "./fixtures.ts";
import { type ProposalRpc, proposeCoachChange, proposeSuggestedDeload } from "./service.ts";
import { parseAthleteState } from "./state.ts";
import { buildCoachProposal } from "./build.ts";
import { buildSuggestedDeload } from "./training.ts";

const user = "00000000-0000-4000-8000-0000000000aa";

type Call = { name: string; params: Record<string, unknown> };

function fakeRpc(
  overrides: Record<string, { data?: unknown; error?: { code?: string; message?: string } }> = {},
) {
  const data = proposalRpcPayloads();
  const calls: Call[] = [];
  const rpc: ProposalRpc = (name, params) => {
    calls.push({ name, params });
    const override = overrides[name];
    if (override) {
      return Promise.resolve({ data: override.data ?? null, error: override.error ?? null });
    }
    const stored = {
      schema_version: "1.0",
      proposal_id: "p-1",
      expires_at: "2026-10-21T10:00:00Z",
    };
    const table: Record<string, unknown> = {
      get_coach_proposal_inputs_v1: data.inputs,
      get_goal_phase_inputs_v1: data.goalPhase,
      get_progression_summary_v1: data.progression,
      persist_coach_proposal_v1: stored,
      persist_suggested_deload_v1: stored,
    };
    return Promise.resolve({ data: table[name], error: null });
  };
  return { rpc, calls };
}

const lowerIntent = { kind: "nutrition_targets", reason: "plateau", direction: "lower" };

Deno.test("the payloads read into the athlete state the rules use", () => {
  const data = proposalRpcPayloads();
  const state = parseAthleteState({ ...data, athleteMessage: "hi" })!;
  assertEquals(state.today, today);
  assertEquals(state.profile.age, 32);
  assertEquals(state.profile.trainingWeekdays, [1, 3, 5]);
  assertEquals(state.profile.priorityMuscles, []);
  assertEquals(state.plan!.workouts.length, 3);
  assertEquals(state.nutrition!.calories, 2300);
  assertEquals(state.goal!.goalType, "fat_loss");
  assertEquals(state.goalPhase.currentWeightKg !== null, true);
  assertEquals(state.eligibility.nutritionEligible, true);
  assertEquals(state.athleteMessage, "hi");
});

Deno.test("a payload that leaves out something the rules need yields no state", () => {
  type Inputs = ReturnType<typeof proposalRpcPayloads>["inputs"];
  const broken = (change: (inputs: Inputs) => void) => {
    const data = structuredClone(proposalRpcPayloads());
    change(data.inputs);
    return parseAthleteState(data);
  };
  assertEquals(broken((i) => Reflect.deleteProperty(i.profile, "birth_year")), null);
  assertEquals(broken((i) => (i.profile.sex = "robot")), null);
  assertEquals(broken((i) => (i.screening = "maybe")), null);
  assertEquals(broken((i) => (i.profile.training_days = [])), null);
  assertEquals(broken((i) => Reflect.deleteProperty(i, "eligibility")), null);
  assertEquals(broken((i) => (i.plan.workouts[0].exercises = [])), null);
  assertEquals(broken((i) => (i.nutrition.calories = "lots" as unknown as number)), null);
  assertEquals(broken((i) => (i.goal.goal_type = "world_peace")), null);
  assertEquals(parseAthleteState({ inputs: null, goalPhase: null, progression: null }), null);
  // No plan or goal is a valid state: the builders refuse with a reason.
  const bare = broken((i) => {
    Object.assign(i, { plan: null, goal: null, nutrition: null });
  })!;
  assertEquals([bare.plan, bare.goal, bare.nutrition], [null, null, null]);
});

Deno.test("a proposal is built from the rules and stored with its basis", async () => {
  const { rpc, calls } = fakeRpc();
  const result = await proposeCoachChange(rpc, {
    userId: user,
    intent: lowerIntent,
    athleteMessage: "lower my calories a little",
    sourceMessageId: "m-1",
  });
  assert(result.ok);
  assertEquals(result.proposalId, "p-1");
  assertEquals(result.kind, "nutrition_targets");
  const persist = calls.find((call) => call.name === "persist_coach_proposal_v1")!;
  assertEquals(persist.params.p_user_id, user);
  assertEquals(persist.params.p_kind, "nutrition_targets");
  assertEquals(persist.params.p_source_message_id, "m-1");
  assertEquals(persist.params.p_expires_in_hours, 72);
  assertEquals(
    (persist.params.p_payload as { nutrition: { calories: number } }).nutrition.calories,
    2190,
  );
  assertEquals(
    (persist.params.p_basis as { nutrition_version_id: string }).nutrition_version_id,
    stateFixture().nutrition!.versionId,
  );
  assertEquals(calls.filter((call) => call.name === "persist_coach_proposal_v1").length, 1);
});

Deno.test("a refusal is returned in plain words and nothing is stored", async () => {
  const { rpc, calls } = fakeRpc();
  const result = await proposeCoachChange(rpc, {
    userId: user,
    intent: { ...lowerIntent, requested_calories: 1200 },
    athleteMessage: "Lower my calories to 1,200",
  });
  assert(!result.ok);
  assertEquals(result.code, "below_calorie_floor");
  assertStringIncludes(result.reason, "calorie floor");
  assertEquals(calls.some((call) => call.name === "persist_coach_proposal_v1"), false);
});

Deno.test("an invalid intent never reaches the database", async () => {
  const { rpc, calls } = fakeRpc();
  const result = await proposeCoachChange(rpc, {
    userId: user,
    intent: { kind: "delete_everything" },
    athleteMessage: "x",
  });
  assert(!result.ok);
  assertEquals(result.code, "invalid_intent");
  assertEquals(calls.length, 0);
});

Deno.test("an unreadable profile or a failing read is reported without a guess", async () => {
  const profile = await proposeCoachChange(
    fakeRpc({ get_coach_proposal_inputs_v1: { data: { profile: null } } }).rpc,
    { userId: user, intent: lowerIntent, athleteMessage: "x" },
  );
  assert(!profile.ok);
  assertEquals(profile.code, "profile_incomplete");
  const failing = await proposeCoachChange(
    fakeRpc({ get_goal_phase_inputs_v1: { error: { code: "XX000" } } }).rpc,
    { userId: user, intent: lowerIntent, athleteMessage: "x" },
  );
  assert(!failing.ok);
  assertEquals(failing.code, "unavailable");
});

Deno.test("a missing progression summary does not block a change", async () => {
  const { rpc } = fakeRpc({ get_progression_summary_v1: { error: { code: "XX000" } } });
  const result = await proposeCoachChange(rpc, {
    userId: user,
    intent: lowerIntent,
    athleteMessage: "x",
  });
  assert(result.ok);
});

Deno.test("a plan that changed while the proposal was built is reported, other store errors are not leaked", async () => {
  const changed = await proposeCoachChange(
    fakeRpc({ persist_coach_proposal_v1: { error: { code: "55000" } } }).rpc,
    { userId: user, intent: lowerIntent, athleteMessage: "x" },
  );
  assert(!changed.ok);
  assertEquals(changed.code, "plan_changed");
  const other = await proposeCoachChange(
    fakeRpc({ persist_coach_proposal_v1: { error: { code: "22023" } } }).rpc,
    { userId: user, intent: lowerIntent, athleteMessage: "x" },
  );
  assert(!other.ok);
  assertEquals(other.code, "unavailable");
  assert(!other.reason.includes("22023"));
  const malformed = await proposeCoachChange(
    fakeRpc({ persist_coach_proposal_v1: { data: { nope: true } } }).rpc,
    { userId: user, intent: lowerIntent, athleteMessage: "x" },
  );
  assert(!malformed.ok);
  assertEquals(malformed.code, "unavailable");
});

Deno.test("a note is kept only when it is the athlete's own words", async () => {
  const note = (athleteMessage: string, text: string) => {
    const { rpc, calls } = fakeRpc();
    return proposeCoachChange(rpc, {
      userId: user,
      intent: { ...lowerIntent, note: text },
      athleteMessage,
    }).then(() =>
      String(calls.find((call) => call.name === "persist_coach_proposal_v1")!.params.p_rationale)
    );
  };
  assertStringIncludes(
    await note("I have slept   badly this week", "Slept badly"),
    '"slept badly"',
  );
  const invented = await note("Please lower my calories", "feeling worn down");
  assertEquals(invented.includes("worn down"), false);
  assertEquals(invented.includes("In your words"), false);
});

Deno.test("a refused store is told by what the database said", async () => {
  const stored = async (message: string) => {
    const result = await proposeCoachChange(
      fakeRpc({ persist_coach_proposal_v1: { error: { code: "55000", message } } }).rpc,
      { userId: user, intent: lowerIntent, athleteMessage: "x" },
    );
    assert(!result.ok);
    return result.code;
  };
  assertEquals(
    await stored("a health professional must clear this athlete first"),
    "screening_see_professional",
  );
  assertEquals(
    await stored("the plan was built before the health check changed"),
    "screening_changed",
  );
  assertEquals(await stored("not enough logged data for this change"), "evidence_changed");
  assertEquals(await stored("the plan changed while the proposal was built"), "plan_changed");
});

Deno.test("the deload the rules suggest needs a reason and is stored without a message", async () => {
  const none = fakeRpc();
  const empty = await proposeSuggestedDeload(none.rpc, { userId: user, reasons: [] });
  assert(!empty.ok);
  assertEquals(none.calls.length, 0);

  const { rpc, calls } = fakeRpc();
  const result = await proposeSuggestedDeload(rpc, { userId: user, reasons: ["run_down"] });
  assert(result.ok);
  assertEquals(result.kind, "intensity_or_phase");
  const persist = calls.find((call) => call.name === "persist_suggested_deload_v1")!;
  assertEquals(persist.params.p_source_message_id, null);
  assertStringIncludes(String(persist.params.p_rationale), "readiness has read low");
});

Deno.test("the rules' deload is refused, not stored, while another change waits for an answer", async () => {
  const { rpc, calls } = fakeRpc({
    persist_suggested_deload_v1: {
      error: { code: "TP001", message: "another change is waiting for an answer" },
    },
  });
  const result = await proposeSuggestedDeload(rpc, { userId: user, reasons: ["run_down"] });
  assert(!result.ok);
  assertEquals(result.code, "other_proposal_pending");
  assertEquals(calls.filter((c) => c.name === "persist_coach_proposal_v1"), []);
});

Deno.test("Coach's own proposals still use the general store", async () => {
  const { rpc, calls } = fakeRpc();
  await proposeCoachChange(rpc, { userId: user, intent: lowerIntent, athleteMessage: "x" });
  assertEquals(calls.filter((c) => c.name === "persist_suggested_deload_v1"), []);
  assertEquals(calls.filter((c) => c.name === "persist_coach_proposal_v1").length, 1);
});

Deno.test("only the rules' suggestion carries DELOAD_SIGNALS; a deload Coach builds never does", () => {
  const state = stateFixture();
  const coach = buildCoachProposal(
    { kind: "intensity_or_phase", reason: "fatigue", level: "deload", weeks: 1 },
    state,
  );
  assert(coach.ok);
  assertEquals(coach.proposal.evidence.some((e) => e.code === "DELOAD_SIGNALS"), false);
  // Whatever the athlete says about why, the model's intent cannot add it.
  const withNote = buildCoachProposal({
    kind: "intensity_or_phase",
    reason: "athlete_request",
    note: "DELOAD_SIGNALS",
    level: "deload",
    weeks: 1,
  }, state);
  assert(withNote.ok);
  assertEquals(withNote.proposal.evidence.some((e) => e.code === "DELOAD_SIGNALS"), false);
  const rules = buildSuggestedDeload(["run_down"], state);
  assert(rules.ok);
  assertEquals(rules.proposal.evidence.some((e) => e.code === "DELOAD_SIGNALS"), true);
});
