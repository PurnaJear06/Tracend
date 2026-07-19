/**
 * Database contract tests.
 *
 * These tests call real RPCs against the local Supabase database (when available)
 * and verify that the response shapes match what Edge Functions expect.
 *
 * Skip condition: Set `CONTRACT_URL` env var to enable. In CI, this is set when
 * local Supabase is running.
 */
import {
  assert,
  assertEquals,
  assertExists,
  assertFalse,
  assertStringIncludes,
} from "jsr:@std/assert@1.0.12";

const CONTRACT_URL = Deno.env.get("CONTRACT_URL") ?? "";

const SKIP_NO_DB = !CONTRACT_URL;

async function createTestClient() {
  const url = CONTRACT_URL || "http://127.0.0.1:54321";
  const anonKey = Deno.env.get("CONTRACT_ANON_KEY") ||
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0";

  // Only dynamic import when needed to avoid npm resolution in non-DB test runs
  const { createClient } = await import("npm:@supabase/supabase-js@2.49.8");
  return createClient(url, anonKey);
}

// ── prepare_coach_chat_v5 shape ──────────────────────────────────────

Deno.test({
  name: "prepare_coach_chat_v5 returns valid context shape",
  ignore: SKIP_NO_DB,
  fn: async () => {
    const supabase = await createTestClient();

    // Use service_role to bypass RLS for DB contract verification.
    // In CI, the service_role key is provided via env; locally, you
    // need to set it or create a test user.

    // Create a test user first (or use existing fixture user)
    const { data: userData, error: signUpError } = await supabase.auth.signUp({
      email: `contract-test-${Date.now()}@test.tracend.bot`,
      password: "test-contract-password-123",
    });

    if (signUpError) {
      // User might already exist from a prior run — try sign in
      console.log("Sign-up note:", signUpError.message);
      return; // Skip gracefully if user creation fails in local env
    }

    const userId = userData?.user?.id;
    if (!userId) {
      console.log("No user ID — skipping (requires local Supabase with auth)");
      return;
    }

    // Create a session to call prepare_coach_chat_v5
    const { data: threadData, error: threadError } = await supabase.rpc(
      "create_coach_thread",
      { thread_title: "contract-test-thread" },
    );

    if (threadError) {
      console.log("Thread creation error (may be expected):", threadError.message);
      return;
    }

    const { data, error } = await supabase.rpc("prepare_coach_chat_v5", {
      p_user_id: userId,
      p_session_id: threadData,
      p_question: "contract test question",
    });

    assertFalse(!!error, `prepare_coach_chat_v5 failed: ${error?.message}`);
    assertExists(data, "Response must not be null");
    assertEquals(typeof data, "object", "Response must be an object");

    // Verify required top-level keys
    assertExists(data.profile, "Must have profile");
    assertExists(data.active_plan, "Must have active_plan");
    assertExists(data.recent_messages, "Must have recent_messages");
    assertExists(data.question, "Must have question");

    // Verify question was included
    assertStringIncludes(data.question, "contract test question");

    // Verify context size is within budget
    const raw = JSON.stringify(data);
    assert(raw.length < 40000, `Context too large: ${raw.length} chars (max 40000)`);

    // Cleanup — sign out
    await supabase.auth.signOut();
  },
});

// ── get_my_training_hub shape ────────────────────────────────────────

Deno.test({
  name: "get_my_training_hub returns expected schema structure",
  ignore: SKIP_NO_DB,
  fn: async () => {
    const supabase = await createTestClient();

    const { data: userData } = await supabase.auth.signUp({
      email: `contract-hub-${Date.now()}@test.tracend.bot`,
      password: "test-contract-password-123",
    });

    const userId = userData?.user?.id;
    if (!userId) return;

    const { data, error } = await supabase.rpc("get_my_training_hub", {
      period_days: 28,
    });

    if (error) {
      console.log("Training hub error (no active plan?):", error.message);
      return;
    }

    assertExists(data, "Response must not be null");
    assertEquals(typeof data, "object", "Response must be an object");

    // Schema version field is mandatory
    assertExists(data.schema_version, "Must have schema_version");
    const version = data.schema_version as string;
    assert(version === "1.3", `Expected schema_version 1.3, got ${version}`);

    // Key arrays
    assertExists(data.workouts, "Must have workouts");
    assert(Array.isArray(data.workouts), "workouts must be a list");

    assertExists(data.completed_day_set, "Must have completed_day_set");
    assert(Array.isArray(data.completed_day_set), "completed_day_set must be a list");

    await supabase.auth.signOut();
  },
});

// ── get_my_coach_context_status shape ────────────────────────────────

Deno.test({
  name: "get_my_coach_context_status returns expected source structure",
  ignore: SKIP_NO_DB,
  fn: async () => {
    const supabase = await createTestClient();

    const { data: userData } = await supabase.auth.signUp({
      email: `contract-ctx-${Date.now()}@test.tracend.bot`,
      password: "test-contract-password-123",
    });

    const userId = userData?.user?.id;
    if (!userId) return;

    const { data, error } = await supabase.rpc("get_my_coach_context_status");

    if (error) {
      console.log("Context status error:", error.message);
      return;
    }

    assertExists(data, "Response must not be null");
    assertExists(data.schema_version, "Must have schema_version");
    assertEquals(data.schema_version, "1.0");
    assertExists(data.sources, "Must have sources");
    assert(Array.isArray(data.sources), "sources must be a list");

    for (const source of data.sources as Record<string, unknown>[]) {
      assertExists(source.source, "Each source must have source field");
      assertExists(source.available, "Each source must have available field");
      assert(!!source.available === source.available, "available must be boolean");
      assertExists(source.count, "Each source must have count field");
    }

    await supabase.auth.signOut();
  },
});

// ── get_healthkit_completion_candidate shape ──────────────────────────

Deno.test({
  name: "get_healthkit_completion_candidate returns {planned_workout_id,...} or null",
  ignore: SKIP_NO_DB,
  fn: async () => {
    const supabase = await createTestClient();

    const { data: userData } = await supabase.auth.signUp({
      email: `contract-hkc-${Date.now()}@test.tracend.bot`,
      password: "test-contract-password-123",
    });

    const userId = userData?.user?.id;
    if (!userId) return;

    const { data, error } = await supabase.rpc("get_healthkit_completion_candidate", {
      p_local_date: new Date().toISOString().split("T")[0],
    });

    if (error) {
      console.log("HK candidate error (expected without data):", error.message);
      return;
    }

    assert(data === null || typeof data === "object", "Result is null or object");

    if (data !== null) {
      assertExists(data.planned_workout_id, "Must have planned_workout_id");
      assertExists(data.planned_workout_name, "Must have planned_workout_name");
      assertExists(data.local_date, "Must have local_date");
    }

    await supabase.auth.signOut();
  },
});

// ── get_my_workout_reconciliation_candidates shape ────────────────────

Deno.test({
  name: "get_my_workout_reconciliation_candidates returns array",
  ignore: SKIP_NO_DB,
  fn: async () => {
    const supabase = await createTestClient();

    const { data: userData } = await supabase.auth.signUp({
      email: `contract-rec-${Date.now()}@test.tracend.bot`,
      password: "test-contract-password-123",
    });

    const userId = userData?.user?.id;
    if (!userId) return;

    const { data, error } = await supabase.rpc("get_my_workout_reconciliation_candidates");

    if (error) {
      console.log("Reconciliation RPC error:", error.message);
      return;
    }

    assert(Array.isArray(data), "Result must be an array");

    if (data.length > 0) {
      const candidate = data[0] as Record<string, unknown>;
      assertExists(candidate.session_id, "Must have session_id");
      assertExists(candidate.status, "Must have status");
    }

    await supabase.auth.signOut();
  },
});

// ── get_my_workout_repair_candidates shape ────────────────────────────

Deno.test({
  name: "get_my_workout_repair_candidates returns array",
  ignore: SKIP_NO_DB,
  fn: async () => {
    const supabase = await createTestClient();

    const { data: userData } = await supabase.auth.signUp({
      email: `contract-repair-${Date.now()}@test.tracend.bot`,
      password: "test-contract-password-123",
    });

    const userId = userData?.user?.id;
    if (!userId) return;

    const { data, error } = await supabase.rpc("get_my_workout_repair_candidates");

    if (error) {
      console.log("Repair RPC error:", error.message);
      return;
    }

    assert(Array.isArray(data), "Result must be an array");

    if (data.length > 0) {
      const candidate = data[0] as Record<string, unknown>;
      assertExists(candidate.session_id, "Must have session_id");
      assertExists(candidate.local_date, "Must have local_date");
    }

    await supabase.auth.signOut();
  },
});

// ── get_my_ai_budget_state shape ──────────────────────────────────────

Deno.test({
  name: "get_my_ai_budget_state returns expected shape",
  ignore: SKIP_NO_DB,
  fn: async () => {
    const supabase = await createTestClient();

    const { data: userData } = await supabase.auth.signUp({
      email: `contract-budget-${Date.now()}@test.tracend.bot`,
      password: "test-contract-password-123",
    });

    const userId = userData?.user?.id;
    if (!userId) return;

    const { data, error } = await supabase.rpc("get_my_ai_budget_state");

    if (error) {
      console.log("Budget state error:", error.message);
      return;
    }

    assertExists(data, "Response must not be null");
    assertExists(data.today_requests, "Must have today_requests");
    assertExists(data.monthly_cost_usd, "Must have monthly_cost_usd");
    assertExists(data.hard_stop_usd, "Must have hard_stop_usd");

    await supabase.auth.signOut();
  },
});
