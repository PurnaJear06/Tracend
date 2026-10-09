import { assertEquals } from "jsr:@std/assert@1.0.14";
import {
  buildCoachChatAnswerSchema,
  buildCoachChatUserMessage,
  classifyQuestion,
  coachChatFailureUsage,
  coachChatTiming,
  CoachChatUnavailableError,
  compactContext,
  formatContextAsMarkdown,
  formatPlanProposal,
  generateCoachChat,
  isCoachChatLiveProviderConfigured,
} from "./coach_chat_provider.ts";
import { coachChatAnswerLimits } from "../contracts/coach_chat_v1.ts";
import v7ContextFixture from "../../../../test/contract/fixtures/coach_chat_context_v7_0.json" with {
  type: "json",
};

Deno.test("Coach chat never turns an unconfigured provider into a mock answer", () => {
  const environment = new Map<string, string>([
    ["COACH_AI_ENABLED", "false"],
    ["COACH_MODEL_PROVIDER", "mock"],
  ]);
  if (isCoachChatLiveProviderConfigured(environment)) {
    throw new Error("Unconfigured chat must fail closed instead of returning a mock reply.");
  }
});

Deno.test("DeepSeek chat accepts V4.1 Flash under its new and legacy names only", () => {
  const configured = (model: string) =>
    isCoachChatLiveProviderConfigured(
      new Map<string, string>([
        ["COACH_AI_ENABLED", "true"],
        ["COACH_MODEL_PROVIDER", "deepseek"],
        ["DEEPSEEK_API_KEY", "synthetic-key"],
        ["DEEPSEEK_MODEL", model],
      ]),
    );
  if (!configured("deepseek-flash") || !configured("deepseek-v4-flash")) {
    throw new Error("Both names of the approved DeepSeek Flash model must enable chat.");
  }
  if (configured("deepseek-v4-pro") || configured("deepseek-chat")) {
    throw new Error("Any other DeepSeek model must keep chat fail-closed.");
  }
});

Deno.test("classifyQuestion requires an explicit plan modification request", () => {
  const planChanges = [
    "Can you create a new plan?",
    "I want to change my plan",
    "Design my next block",
    "Change my training program",
    "My routine needs an update",
    "I need a new split",
    "Should I deload this week?",
    "Recovery is poor; should I change my plan?",
  ];
  for (const q of planChanges) {
    if (classifyQuestion(q) !== "plan_change") {
      throw new Error(`Expected plan_change for: "${q}", got: ${classifyQuestion(q)}`);
    }
  }

  const productionPrompt =
    "hey couch my recovery is very poor idk why can you help me to improve my recovery and i have already completed my workout and for few ive splited the rotine morning i had weight training with abs and now eveing ill have cardio !";
  if (classifyQuestion(productionPrompt) !== "recovery") {
    throw new Error("The exact production prompt must classify as recovery");
  }
  if (classifyQuestion("My weekly progress?") !== "explain_evidence") {
    throw new Error("Weekly progress is an evidence question, not a plan change");
  }
  if (classifyQuestion("I split training between morning and evening") !== "daily_action") {
    throw new Error("Describing a split day is a daily action, not a plan change");
  }
  if (classifyQuestion("I want my routine explained") !== "explain_evidence") {
    throw new Error("Mentioning a routine without requesting a change must not route to planning");
  }
});

Deno.test("classifyQuestion returns daily_action for today/training keywords", () => {
  const cases = [
    "What should I do today?",
    "What is next?",
    "What workout should I do?",
    "Today's training",
    "Should I train today?",
    "What exercise next?",
    "Show me my schedule",
    "Today workout",
  ];
  for (const q of cases) {
    if (classifyQuestion(q) !== "daily_action") {
      throw new Error(`Expected daily_action for: "${q}", got: ${classifyQuestion(q)}`);
    }
  }
});

Deno.test("classifyQuestion returns explain_evidence for data/evidence queries", () => {
  const cases = [
    "What evidence do you have?",
    "Show me my data",
    "What data is missing?",
    "Are there gaps in my tracking?",
    "What's my health summary?",
    "Explain my progress",
    "Why is my trend flat?",
    "Show my tracking history",
    "What have I logged?",
    "Explain why you suggest that",
    "What is my latest summary?",
  ];
  for (const q of cases) {
    if (classifyQuestion(q) !== "explain_evidence") {
      throw new Error(`Expected explain_evidence for: "${q}", got: ${classifyQuestion(q)}`);
    }
  }
});

Deno.test("classifyQuestion returns nutrition_focus for diet/nutrition queries", () => {
  const cases = [
    "What should I eat?",
    "Give me nutrition advice",
    "What is my diet like?",
    "How many calories did I eat?",
    "Am I getting enough protein?",
    "Review my macros",
    "What meal should I have?",
    "Too many carbs today?",
    "Check my fat intake",
    "I need more fiber",
    "Track my sodium",
    "Sugar intake this week",
  ];
  for (const q of cases) {
    if (classifyQuestion(q) !== "nutrition_focus") {
      throw new Error(`Expected nutrition_focus for: "${q}", got: ${classifyQuestion(q)}`);
    }
  }
});

Deno.test("classifyQuestion returns recovery for recovery/health queries", () => {
  const cases = [
    "I need more recovery time",
    "Should I rest today?",
    "My sleep has been poor",
    "I feel sore after yesterday",
    "Dealing with fatigue",
    "I hurt my shoulder",
    "My knee is in pain",
    "I feel sick today",
    "I have a fever",
    "Caught a cold",
    "Feeling ill after workout",
    "Too much stress lately",
    "Low energy today",
  ];
  for (const q of cases) {
    if (classifyQuestion(q) !== "recovery") {
      throw new Error(`Expected recovery for: "${q}", got: ${classifyQuestion(q)}`);
    }
  }
});

Deno.test("classifyQuestion returns general for ambiguous queries", () => {
  const cases = [
    "Hello",
    "How are you?",
    "Thanks",
    "Tell me something",
    "What can you do?",
    "Hi coach",
    "Good morning",
    "Help",
    "Let's talk",
    "I need advice",
  ];
  for (const q of cases) {
    if (classifyQuestion(q) !== "general") {
      throw new Error(`Expected general for: "${q}", got: ${classifyQuestion(q)}`);
    }
  }
});

Deno.test("classifyQuestion uses whole words and routes the acceptance prompts", () => {
  const cases: Array<[string, string]> = [
    ["What will I eat for dinner to hit my protein target?", "nutrition_focus"],
    ["I'm interested in improving my squat.", "general"],
    ["Great session today — what should I do next?", "daily_action"],
    ["How are my HRV and readiness today?", "recovery"],
    ["I feel tired and exhausted.", "recovery"],
    ["I slept badly last night — what should I change in today's workout?", "recovery"],
    ["Another sleepless night; should I still lift?", "recovery"],
    ["I'm still a bit sore from my last session — will that affect today?", "recovery"],
  ];
  for (const [question, expected] of cases) {
    const actual = classifyQuestion(question);
    if (actual !== expected) {
      throw new Error(`Expected ${expected} for "${question}", got ${actual}`);
    }
  }
});

Deno.test("classifyQuestion nutrition_focus takes priority over daily_action for food queries", () => {
  if (classifyQuestion("What should I eat for protein?") !== "nutrition_focus") {
    throw new Error(
      "Nutrition question with 'what' and 'protein' should classify as nutrition_focus",
    );
  }
});

Deno.test("compactContext preserves null values as NOT MEASURED (Pass 4)", () => {
  const input = { a: "hello", b: null, c: 0 };
  const result = compactContext(input);
  // null must survive compaction: the prompt contract teaches the model
  // "null = NOT MEASURED that day, never zero", which only works if the
  // null actually reaches the model.
  if (!("b" in result)) {
    throw new Error("null value b must be preserved as NOT MEASURED, not stripped");
  }
  if (result.b !== null) throw new Error("preserved b must be exactly null");
  if (result.a !== "hello") throw new Error("non-null value a should be preserved");
  if (result.c !== 0) throw new Error("falsy value 0 should be preserved");
});

Deno.test("compactContext abbreviates known keys", () => {
  const input = { session_id: "abc", duration_seconds: 3600, prescribed_workout: "Push Day" };
  const result = compactContext(input);
  if (!("sid" in result)) throw new Error("session_id should abbreviate to sid");
  if (!("dur" in result)) throw new Error("duration_seconds should abbreviate to dur");
  if (!("w" in result)) throw new Error("prescribed_workout should abbreviate to w");
  if (result.sid !== "abc") throw new Error("abbreviated value should be preserved");
});

Deno.test("compactContext drops empty arrays", () => {
  const input = { exercises: [], sessions: [{ name: "Test" }] };
  const result = compactContext(input);
  if ("exercises" in result) throw new Error("empty array exercises should be dropped");
  if (!("sessions" in result)) throw new Error("non-empty array sessions should be kept");
});

Deno.test("compactContext truncates long rationales", () => {
  const input = {
    plan_proposals: [{
      rationale: "A".repeat(300),
      status: "pending",
    }],
  };
  const result = compactContext(input);
  const rationale = (result.plan_proposals as Array<Record<string, unknown>>)[0]
    .rationale as string;
  if (rationale.length > 120) {
    throw new Error(`Rationale should be truncated to 120 chars, got ${rationale.length}`);
  }
});

Deno.test("compactContext keeps null-bearing keys but drops null-only-nested empties distinctly", () => {
  // A top-level null is a NOT MEASURED signal and must survive.
  const withNull = { a: null, b: { c: null } };
  const result = compactContext(withNull);
  if (!("a" in result) || result.a !== null) {
    throw new Error("top-level null must be preserved as null");
  }
  // { c: null } still holds one nullable field, so it survives too — the
  // nested null is the honest "c not measured" signal.
  if (!("b" in result)) throw new Error("null-bearing nested object must be preserved");
  const b = result.b as Record<string, unknown>;
  if (!("c" in b) || b.c !== null) throw new Error("nested null must be preserved as null");
});

Deno.test("compactContext preserves unknown keys as-is", () => {
  const input = { my_custom_field: "value", unusual_key: 42 };
  const result = compactContext(input);
  if (result.my_custom_field !== "value") throw new Error("unknown key should be preserved");
  if (result.unusual_key !== 42) throw new Error("unknown key with number should be preserved");
});

Deno.test("compactContext handles nested objects with mixed abbreviations", () => {
  const input = {
    sessions: [{
      session_id: "s1",
      local_date: "2026-07-15",
      exercises: [{
        prescribed_name: "Bench Press",
        sets: [
          { set_number: 1, repetitions: 10, load_kg: 60, rpe: 7 },
          { set_number: 2, repetitions: 8, load_kg: 65, rpe: 8 },
        ],
      }],
    }],
    measurement_history: [{
      weight_kg: 82.5,
      body_fat_pct: 15.2,
    }],
  };
  const result = compactContext(input);
  const sessions = result.sessions as Array<Record<string, unknown>>;
  const session = sessions[0];
  if (!("sid" in session)) throw new Error("nested session_id should abbreviate");
  if (!("d" in session)) throw new Error("nested local_date should abbreviate");
  const exercises = session.exercises as Array<Record<string, unknown>>;
  const exercise = exercises[0];
  if (!("n" in exercise)) throw new Error("nested prescribed_name should abbreviate");
  const sets = exercise.ss as Array<Record<string, unknown>>;
  if (((sets[0]) as Record<string, unknown>).r !== 10) {
    throw new Error("nested repetitions should map to r");
  }
});

Deno.test("classifyQuestion returns explain_evidence for physique/visual progress queries", () => {
  const cases = [
    "How does my physique look?",
    "Show visual progress",
    "Run a photo comparison",
    "What is my body composition?",
    "Can you compare my progress photos?",
  ];
  for (const q of cases) {
    if (classifyQuestion(q) !== "explain_evidence") {
      throw new Error(`Expected explain_evidence for: "${q}", got: ${classifyQuestion(q)}`);
    }
  }
});

Deno.test("classifyQuestion returns nutrition_focus for adherence/compliance queries", () => {
  const cases = [
    "How is my diet adherence?",
    "Check my nutrition compliance",
    "Am I sticking to my meal plan?",
    "Review my diet plan this week",
  ];
  for (const q of cases) {
    if (classifyQuestion(q) !== "nutrition_focus") {
      throw new Error(`Expected nutrition_focus for: "${q}", got: ${classifyQuestion(q)}`);
    }
  }
});

Deno.test("classifyQuestion explain_evidence wins over nutrition_focus when both matched (waterfall priority)", () => {
  if (classifyQuestion("Track my diet progress and adherence") !== "explain_evidence") {
    throw new Error(
      "'progress' matches explain_evidence which is checked before nutrition_focus",
    );
  }
});

Deno.test("compactContext abbreviates v5 context keys", () => {
  const input = {
    nutrition_adherence: { days_with_confirmed_meals_7d: 5, confirmed_meal_count_7d: 14 },
    nutrition_compliance_7day: {
      avg_daily_carbohydrate_g: 220,
      avg_daily_fat_g: 65,
      days_with_meals: 6,
    },
    schedule_slot_compliance: { scheduled_slots: 6, matched_slots_today: 4 },
    last_photo_set: "2026-07-10",
    photo_sets_completed: 3,
    has_physique_analysis: true,
  };
  const result = compactContext(input);
  if (!("na" in result)) throw new Error("nutrition_adherence should abbreviate to na");
  if (!("nc7" in result)) throw new Error("nutrition_compliance_7day should abbreviate to nc7");
  if (!("lps" in result)) throw new Error("last_photo_set should abbreviate to lps");
  if (!("psc" in result)) throw new Error("photo_sets_completed should abbreviate to psc");
  if (!("hpa" in result)) throw new Error("has_physique_analysis should abbreviate to hpa");
  const na = result.na as Record<string, unknown>;
  if (!("dwm" in na)) throw new Error("days_with_confirmed_meals_7d should abbreviate to dwm");
  if (!("cm7" in na)) throw new Error("confirmed_meal_count_7d should abbreviate to cm7");
  const nc = result.nc7 as Record<string, unknown>;
  if (!("adc" in nc)) throw new Error("avg_daily_carbohydrate_g should abbreviate to adc");
  if (!("adf" in nc)) throw new Error("avg_daily_fat_g should abbreviate to adf");
  if (nc.dwm !== 6) throw new Error("days_with_meals should abbreviate to dwm and preserve value");
});

Deno.test("compactContext handles v5 schedule_slot_compliance deeply", () => {
  const input = {
    schedule_slot_compliance: { scheduled_slots: 6, matched_slots_today: 4 },
  };
  const result = compactContext(input);
  if (!("ssc" in result)) throw new Error("schedule_slot_compliance should abbreviate to ssc");
  const ssc = result.ssc as Record<string, unknown>;
  if (!("ss" in ssc)) throw new Error("scheduled_slots should abbreviate to ss");
  if (!("mst" in ssc)) throw new Error("matched_slots_today should abbreviate to mst");
  if (ssc.ss !== 6) throw new Error("abbreviated value should be preserved");
  if (ssc.mst !== 4) throw new Error("abbreviated value should be preserved");
});

function buildMassiveContext(): Record<string, unknown> {
  const longText = "x".repeat(800);
  const msg = (role: string) => ({ role, content: longText });
  const messages = Array.from({ length: 20 }, (_, i) => msg(i % 2 === 0 ? "user" : "assistant"));

  const session = (i: number) => ({
    local_date: `2026-07-${String(i + 1).padStart(2, "0")}`,
    evidence_id: `TRAINING.SESSION.2026-07-${i}`,
    session_id: `sid-${i}`,
    prescribed_workout: `Workout Day ${i}`,
    duration_seconds: 3600,
    logging_completeness: 0.85,
    effort: "moderate",
    exercise_count: 6,
    set_count: 24,
    completion_rate: 0.85,
  });

  const preference = (i: number) => ({
    id: `pref-${i}`,
    category: i % 2 === 0 ? "food" : "training",
    key: `pref_key_${i}`,
    value: `${longText.slice(0, 150)}_${i}`,
    provenance: "chat_statement",
  });

  return {
    active_plan: {
      title: "Strength Block",
      version_number: 3,
      sessions_per_week: 5,
      rationale: longText,
    },
    nutrition_targets: { calories: 2800, protein_g: 180, carbohydrate_g: 320, fat_g: 80 },
    nutrition_schedule: Array.from({ length: 6 }, (_, i) => ({
      slot_key: `slot_${i}`,
      label: `Meal ${i}`,
      local_time: "12:00",
      foods: [{ name: `Food ${i}`, quantity: "1 serving" }],
      optional: false,
    })),
    latest_check_in: {
      local_date: "2026-07-18",
      sleep_quality: 3,
      energy: 4,
      soreness: 2,
      hunger: 3,
      mood: "good",
      pain_severity: 0,
      available_to_train: true,
    },
    recent_execution: Array.from({ length: 8 }, (_, i) => ({
      local_date: `2026-07-${String(i + 10).padStart(2, "0")}`,
      workout: `Workout ${i}`,
      duration_seconds: 3600,
      effort: "moderate",
    })),
    latest_decision: {
      final_decision: "Proceed as planned",
      reason: "Recovery within baseline",
      evidence: [],
      missing_data: [],
      confidence: "medium",
    },
    recent_messages: messages,
    recent_other_conversations: messages,
    permitted_evidence: ["APPROVED_PLAN_ACTIVE", "HEALTH_CONTEXT_AVAILABLE"],
    missing_data: [],
    context_coverage: {
      approved_plan: true,
      active_goal: true,
      profile: true,
      healthkit_recent: true,
      today_check_in: true,
      confirmed_nutrition: true,
      completed_workouts: true,
      measurements: true,
      conversation_messages: true,
    },
    schema_version: "3.0",
    context_kind: "plan_change",
    session_trends: Array.from({ length: 12 }, (_, i) => session(i)),
    plan_proposals: Array.from({ length: 5 }, (_, i) => ({
      evidence_id: `PROPOSAL.${i}`,
      proposal_id: `prop-${i}`,
      status: "pending",
      proposed_training: longText,
      proposed_nutrition: longText,
      rationale: longText,
      confidence: "medium",
      expected_benefit: longText.slice(0, 200),
      effective_date: "2026-07-20",
    })),
    workout_reconciliations: Array.from({ length: 5 }, (_, i) => ({
      evidence_id: `HEALTH.WORKOUT.${i}`,
      status: "matched",
      confidence: "high",
      activity_type: "running",
      duration_difference_seconds: 0,
    })),
    eight_week_measurement_delta: {
      earliest: { measured_on: "2026-05-01", weight_kg: 82, waist_cm: 88 },
      latest: { measured_on: "2026-07-01", weight_kg: 80, waist_cm: 86 },
    },
    seven_day_healthkit_trend: { avg_resting_hr: 58, avg_hrv_sdnn: 45, avg_sleep_minutes: 420 },
    nutrition_adherence: {
      days_with_confirmed_meals_7d: 6,
      confirmed_meal_count_7d: 18,
      schedule_slot_compliance: { scheduled_slots: 5, matched_slots_today: 4 },
    },
    data_quality: {
      training_logging_coverage: 0.8,
      last_health_sync: "2026-07-18T08:00:00Z",
      last_confirmed_meal: "2026-07-18T12:00:00Z",
      conflict_count: 0,
    },
    coaching_narrative: {
      active: { phase: "strength_block", headline: longText.slice(0, 300), since: "2026-07-01" },
      recent: Array.from(
        { length: 4 },
        (_, i) => ({
          phase: `phase_${i}`,
          headline: longText.slice(0, 300),
          since: `2026-0${i + 1}-01`,
          until: `2026-0${i + 2}-01`,
        }),
      ),
    },
    active_preferences: Array.from({ length: 20 }, (_, i) => preference(i)),
    session_journal: Array.from(
      { length: 10 },
      (_, i) => ({
        coaching_date: `2026-07-${String(i + 1).padStart(2, "0")}`,
        summary: longText.slice(0, 300),
        thread_id: `thread-${i}`,
      }),
    ),
    fts_messages: messages.slice(0, 8),
  };
}

Deno.test("generateCoachChat handles massive context without throwing non-CoachChatUnavailableError", async () => {
  Deno.env.set("COACH_AI_ENABLED", "true");
  Deno.env.set("COACH_MODEL_PROVIDER", "groq");
  Deno.env.set("GROQ_API_KEY", "synthetic-key");
  Deno.env.set("GROQ_MODEL", "qwen/qwen3.6-27b");

  try {
    const massiveContext = buildMassiveContext();
    const compacted = compactContext(massiveContext);
    const bounded = JSON.stringify({ question: "Hello", context: compacted });
    if (bounded.length <= 32000) {
      throw new Error(
        `Test precondition failed: compacted context is ${bounded.length} chars, need > 32000 to trigger trimming logic`,
      );
    }

    let fetcherCalled = false;
    const mockFetcher = () => {
      fetcherCalled = true;
      return Promise.resolve(
        new Response(
          JSON.stringify({
            choices: [{
              message: {
                content: JSON.stringify({
                  answer: "I see you have been training consistently.",
                  evidence: [],
                  missing_data: [],
                  safety_state: "allowed",
                  suggested_follow_ups: ["What should I work on today?"],
                  reasoning_chain: [],
                }),
              },
            }],
            usage: { prompt_tokens: 500, completion_tokens: 50 },
          }),
          { status: 200 },
        ),
      );
    };

    await generateCoachChat(
      "Hello",
      massiveContext,
      "general",
      mockFetcher as unknown as typeof fetch,
    );

    if (!fetcherCalled) {
      throw new Error("Fetcher was never called — error occurred before API call");
    }
  } finally {
    Deno.env.delete("COACH_AI_ENABLED");
    Deno.env.delete("COACH_MODEL_PROVIDER");
    Deno.env.delete("GROQ_API_KEY");
    Deno.env.delete("GROQ_MODEL");
  }
});

Deno.test("CONTEXT BUDGET CONTRACT: all context kinds stay within compacted 32K ceiling", () => {
  const longText = "x".repeat(400);
  const msg = (role: string) => ({ role, content: longText });
  const moderateMessages = Array.from(
    { length: 10 },
    (_, i) => msg(i % 2 === 0 ? "user" : "assistant"),
  );

  const baseContext = {
    active_plan: {
      title: "Strength Block",
      version_number: 3,
      sessions_per_week: 5,
      rationale: longText.slice(0, 200),
    },
    nutrition_targets: { calories: 2800, protein_g: 180, carbohydrate_g: 320, fat_g: 80 },
    nutrition_schedule: Array.from({ length: 6 }, (_, i) => ({
      slot_key: `slot_${i}`,
      label: `Meal ${i}`,
      local_time: "12:00",
      foods: [{ name: `Food ${i}`, quantity: "1 serving" }],
    })),
    latest_check_in: {
      local_date: "2026-07-18",
      sleep_quality: 3,
      energy: 4,
      soreness: 2,
      hunger: 3,
      mood: "good",
      pain_severity: 0,
      available_to_train: true,
    },
    recent_execution: Array.from({ length: 8 }, (_, i) => ({
      local_date: `2026-07-${String(i + 10).padStart(2, "0")}`,
      workout: `Workout ${i}`,
      duration_seconds: 3600,
      effort: "moderate",
    })),
    latest_decision: {
      final_decision: "Proceed as planned",
      reason: "Baseline normal",
      evidence: [],
      missing_data: [],
      confidence: "medium",
    },
    recent_messages: moderateMessages,
    recent_other_conversations: moderateMessages,
    permitted_evidence: ["APPROVED_PLAN_ACTIVE"],
    missing_data: [],
    coaching_narrative: {
      active: { phase: "strength", headline: longText.slice(0, 200), since: "2026-07-01" },
      recent: Array.from(
        { length: 3 },
        (_, i) => ({
          phase: `phase_${i}`,
          headline: longText.slice(0, 200),
          since: `2026-0${i + 1}-01`,
          until: `2026-0${i + 2}-01`,
        }),
      ),
    },
    active_preferences: Array.from({ length: 10 }, (_, i) => ({
      id: `p-${i}`,
      category: "food",
      key: `key_${i}`,
      value: longText.slice(0, 100),
      provenance: "chat_statement",
    })),
    session_journal: Array.from({ length: 5 }, (_, i) => ({
      coaching_date: `2026-07-${String(i + 1).padStart(2, "0")}`,
      summary: longText.slice(0, 200),
      thread_id: `t-${i}`,
    })),
    fts_messages: moderateMessages.slice(0, 5),
  };

  // Test multiple context kinds
  const contextKinds: [string, Record<string, unknown>][] = [
    ["plan_change", {
      ...baseContext,
      session_trends: Array.from({ length: 12 }, (_, i) => ({
        local_date: `2026-07-${String(i + 1).padStart(2, "0")}`,
        prescribed_workout: `Workout ${i}`,
        duration_seconds: 3600,
        effort: "moderate",
        logging_completeness: 0.85,
      })),
      plan_proposals: Array.from({ length: 5 }, (_, _i) => ({
        proposed_training: longText.slice(0, 300),
        proposed_nutrition: longText.slice(0, 300),
        rationale: longText.slice(0, 300),
      })),
      nutrition_adherence: { days_with_confirmed_meals_7d: 5, confirmed_meal_count_7d: 14 },
    }],
    ["nutrition_focus", {
      ...baseContext,
      today_confirmed_meals: Array.from({ length: 3 }, (_, i) => ({
        local_date: "2026-07-18",
        foods: Array.from({ length: 4 }, (_, j) => ({
          food: `Food item ${j} on meal ${i}`,
          serving: "1 serving",
          calories: 350,
          protein_g: 25,
          carbohydrate_g: 40,
          fat_g: 12,
        })),
      })),
      nutrition_compliance_7day: {
        avg_daily_calories: 2800,
        avg_daily_protein_g: 160,
        avg_daily_carbohydrate_g: 300,
        avg_daily_fat_g: 75,
        days_with_meals: 6,
      },
    }],
    ["recovery", {
      ...baseContext,
      latest_healthkit: {
        resting_heart_rate_bpm: 58,
        hrv_value_ms: 45,
        sleep_minutes: 420,
        completeness: 0.9,
      },
      last_3_sessions_summary: Array.from({ length: 3 }, (_, i) => ({
        local_date: `2026-07-${String(15 - i).padStart(2, "0")}`,
        prescribed_workout: `Workout ${i}`,
        duration_seconds: 3600,
        effort: "moderate",
        logging_completeness: 0.85,
      })),
    }],
    ["general", baseContext],
  ];

  for (const [kind, ctx] of contextKinds) {
    const compacted = compactContext(ctx);
    const bounded = JSON.stringify({ question: "Hello", context: compacted });
    if (bounded.length > 32000) {
      throw new Error(
        `CONTEXT BUDGET VIOLATION: ${kind} context is ${bounded.length} chars after compaction, ` +
          `exceeds 32,000 char ceiling. Reduce data volume or increase budget.`,
      );
    }
    // Verify the DB-level 40K guard wouldn't trigger unnecessarily
    if (JSON.stringify(ctx).length > 40000) {
      throw new Error(
        `CONTEXT BUDGET WARNING: ${kind} raw context is ${JSON.stringify(ctx).length} chars, ` +
          `approaching 40,000 char DB guard threshold.`,
      );
    }
  }
});

Deno.test("CONTEXT BUDGET CONTRACT: markdown formatter stays within 28K ceiling", () => {
  const ctx = buildMassiveContext();
  const markdown = formatContextAsMarkdown(ctx, 28_000);
  if (markdown.length > 28_000) {
    throw new Error(
      `CONTEXT BUDGET VIOLATION: markdown context is ${markdown.length} chars, ` +
        `exceeds 28,000 char formatter ceiling.`,
    );
  }
  const userMessage = "Hello" + "\n\n---\n\n<coaching_context>\n" + markdown +
    "\n</coaching_context>";
  if (userMessage.length > 32_000) {
    throw new Error(
      `CONTEXT BUDGET VIOLATION: full userMessage is ${userMessage.length} chars, ` +
        `exceeds 32,000 char hard ceiling.`,
    );
  }
});

Deno.test("v7 contract fixture keeps authoritative sections whole and sends the question once", () => {
  const question = "How is my recovery today?";
  const oversized = {
    ...v7ContextFixture,
    recent_messages: Array.from(
      { length: 100 },
      () => ({ role: "assistant", content: "history ".repeat(500) }),
    ),
    session_journal: Array.from(
      { length: 50 },
      (_, index) => ({
        coaching_date: `2026-08-${String(index + 1).padStart(2, "0")}`,
        summary: "x".repeat(1000),
      }),
    ),
  } as Record<string, unknown>;
  const message = buildCoachChatUserMessage(question, oversized, "recovery");
  if (!message.includes("## Context Date") || !message.includes("## Null Contract")) {
    throw new Error("Required date/null sections must survive context pressure");
  }
  if (!message.includes("## Evidence Contract") || !message.includes("## Computed Scores")) {
    throw new Error("Evidence and computed-score contracts must be first-class sections");
  }
  if (!message.includes("- recovery: 62/100")) {
    throw new Error("Authoritative score must remain byte-exact under context pressure");
  }
  if (!message.includes("</coaching_context>\n\nUser's message:\n")) {
    throw new Error("Context wrapper must always close before the question");
  }
  if (!message.endsWith(question)) {
    throw new Error("The question must come last so the stable context can be cached");
  }
  if (message.split(question).length - 1 !== 1) {
    throw new Error("The user question must be sent exactly once");
  }
});

// ---------------------------------------------------------------------------
// v8 — one complete athlete file for every question.
// ---------------------------------------------------------------------------

function v8AthleteContext(): Record<string, unknown> {
  return {
    ...v7ContextFixture,
    schema_version: "8.0",
    active_plan: { title: "Cut plan", version_number: 2, sessions_per_week: 5 },
    nutrition_targets: { calories: 1900, protein_g: 150, carbohydrate_g: 190, fat_g: 60 },
    training_totals: {
      last_7_days: {
        days: 7,
        sessions: 3,
        total_minutes: 170,
        completed_sets: 54,
        volume_kg: 9120,
      },
      last_14_days: {
        days: 14,
        sessions: 7,
        total_minutes: 400,
        completed_sets: 120,
        volume_kg: 20450,
      },
      last_28_days: {
        days: 28,
        sessions: 13,
        total_minutes: 760,
        completed_sets: 230,
        volume_kg: 38900,
      },
    },
    training_log_28d: [{
      local_date: "2026-09-26",
      workout: "Push day",
      duration_minutes: 62,
      completed_sets: 18,
      volume_kg: 3120,
      avg_rpe: 8,
      effort: 7,
    }],
    watch_workouts_14d: [{
      local_date: "2026-09-26",
      activity_type: "running",
      duration_minutes: 31,
    }],
    training_week_structure: {
      sessions_per_week: 5,
      block_weeks: 4,
      planned_workouts: [{ name: "Push day", target_day: 1 }],
    },
    health_daily_28d: [{
      local_date: "2026-09-27",
      sleep_minutes: 402,
      resting_heart_rate_bpm: 58,
      hrv_ms: 44,
      steps: 9100,
      active_energy_kcal: 610,
      workout_minutes: 70,
      weight_kg: null,
    }],
    health_averages: {
      last_7_days: {
        days_synced: 7,
        days_with_sleep: 1,
        avg_sleep_minutes: 395,
        days_with_resting_heart_rate: 7,
        avg_resting_heart_rate_bpm: 57.9,
      },
    },
    weight_series_8w: [
      { measured_on: "2026-09-25", weight_kg: 78.4 },
      { measured_on: "2026-08-10", weight_kg: 80.1 },
    ],
    check_ins_14d: [{ local_date: "2026-09-27", sleep_quality: 2, energy: 3, soreness: 4 }],
    nutrition_daily_28d: [{ local_date: "2026-09-20", confirmed_meals: 3, calories: 1880 }],
    today_confirmed_meals: [],
    recent_messages: [
      { role: "user", content: "How much should I eat?" },
      { role: "assistant", content: "Is 1,900 kcal your intake on rest days too?" },
    ],
    omitted_sections: [],
  };
}

const v8Sections = [
  "## Training Totals",
  "## Training Log (last 28 days)",
  "## Watch Workouts (last 14 days)",
  "## Training Week Structure",
  "## Watch Data (last 28 days)",
  "## Weight (last 8 weeks)",
  "## Check-ins (last 14 days",
  "## Nutrition\n",
  "## Logged Nutrition",
  "## This Conversation",
];

Deno.test("v8: every question kind renders the same full athlete file", () => {
  const context = v8AthleteContext();
  for (
    const kind of [
      "recovery",
      "nutrition_focus",
      "daily_action",
      "explain_evidence",
      "plan_change",
      "general",
    ]
  ) {
    const message = buildCoachChatUserMessage("Question", context, kind);
    for (const section of v8Sections) {
      if (!message.includes(section)) {
        throw new Error(`${kind} question lost the "${section.trim()}" section`);
      }
    }
  }
});

Deno.test("v8: the real failing prompts keep training, weight and nutrition data", () => {
  const prompts = [
    "hey coach, so can you please check my last two weeks workload? Let me know how much long it may take for me to go till 73 or 72 kg from my current weight and for diet. I am not logging the meals in the app, but I am having exact 1900 cal per day or whatever,",
    "hey couch my recovery is very poor idk why can you help me to improve my recovery and i have already completed my workout and for few ive splited the rotine morning i had weight training with abs and now eveing ill have cardio !",
  ];
  for (const prompt of prompts) {
    const message = buildCoachChatUserMessage(
      prompt,
      v8AthleteContext(),
      classifyQuestion(prompt),
    );
    for (
      const fact of [
        "7 sessions, 400 min",
        "2026-09-25: 78.4 kg",
        "Targets: 1900 kcal",
        "| 2026-09-26 | Push day | 62 |",
      ]
    ) {
      if (!message.includes(fact)) throw new Error(`Prompt lost "${fact}"`);
    }
  }
});

Deno.test("v8: each watch average names the days its metric was measured", () => {
  const message = buildCoachChatUserMessage("How did I sleep?", v8AthleteContext(), "recovery");
  for (
    const fact of [
      "last 7 days averages (7 days synced)",
      "sleep 395 min over 1 day measured",
      "RHR 57.9 bpm over 7 days measured",
    ]
  ) {
    if (!message.includes(fact)) throw new Error(`Watch averages lost "${fact}"`);
  }
});

Deno.test("v8: the conversation sits right before the question, which comes last", () => {
  const question = "Yes, every day";
  const message = buildCoachChatUserMessage(question, v8AthleteContext(), "general");
  const conversation = message.indexOf("## This Conversation");
  const coachQuestion = message.indexOf("Is 1,900 kcal your intake on rest days too?");
  const userMessage = message.indexOf("User's message:");
  if (!(conversation > 0 && coachQuestion > conversation && userMessage > coachQuestion)) {
    throw new Error("History must precede the question so a clarifying answer has its question");
  }
  if (!message.endsWith(question)) throw new Error("The question must come last");
});

Deno.test("v8: long coach messages keep their ending in history", () => {
  const context = {
    ...v8AthleteContext(),
    recent_messages: [{
      role: "assistant",
      content: "x".repeat(2_000) + " Which session do you mean?",
    }],
  };
  const message = buildCoachChatUserMessage("The morning one", context, "general");
  if (!message.includes("Which session do you mean?")) {
    throw new Error("A clarifying question at the end of a long message must survive");
  }
});

Deno.test("v8: sections dropped for size are named for the coach", () => {
  const context = {
    ...v8AthleteContext(),
    omitted_sections: ["recent_other_conversations"],
    training_log_28d: Array.from({ length: 4_000 }, (_, index) => ({
      local_date: `2026-09-${String((index % 28) + 1).padStart(2, "0")}`,
      workout: "Push day",
      duration_minutes: 60,
    })),
  };
  const message = buildCoachChatUserMessage("How is my training?", context, "general");
  if (!message.includes("## Omitted This Turn")) {
    throw new Error("Dropped sections must be listed");
  }
  if (!message.includes("recent other conversations")) {
    throw new Error("Sections dropped by the SQL size guard must be listed too");
  }
  if (!message.includes("- recovery: 62/100")) {
    throw new Error("Required truth must survive when optional sections are dropped");
  }
});

Deno.test("v8: the contract allows labeled estimates and one clarifying question", async () => {
  let systemPrompt = "";
  await withDeepSeekEnvironment(() =>
    generateCoachChat(
      "How long until 72 kg?",
      v8AthleteContext(),
      "general",
      ((_input: unknown, init?: RequestInit) => {
        const body = JSON.parse(String(init?.body));
        systemPrompt = body.messages[0].content;
        return Promise.resolve(deepSeekResponse(validDeepSeekAnswer));
      }) as typeof fetch,
    )
  );
  for (
    const phrase of [
      "Call it an estimate, show its inputs and assumptions",
      "ask one short clarifying question",
      "Numbers about the athlete's data come only from the prepared context",
    ]
  ) {
    if (!systemPrompt.includes(phrase)) throw new Error(`System prompt lost: ${phrase}`);
  }
  if (systemPrompt.includes("Never calculate a new average")) {
    throw new Error("The retired no-projection rule must not remain");
  }
});

Deno.test("the persona limits formatting to what the app displays", async () => {
  let systemPrompt = "";
  await withDeepSeekEnvironment(() =>
    generateCoachChat(
      "How is my training?",
      v8AthleteContext(),
      "general",
      ((_input: unknown, init?: RequestInit) => {
        systemPrompt = JSON.parse(String(init?.body)).messages[0].content;
        return Promise.resolve(deepSeekResponse(validDeepSeekAnswer));
      }) as typeof fetch,
    )
  );
  for (
    const phrase of [
      'The app displays **bold**, *italic*, bullet lists ("- item") and numbered lists ("1. item"), and nothing else.',
      "Never use headings, tables, code blocks, links, or emoji bullets.",
    ]
  ) {
    if (!systemPrompt.includes(phrase)) throw new Error(`System prompt lost: ${phrase}`);
  }
});

Deno.test("model-facing schema is generated from validator limits and permitted codes", () => {
  const schema = buildCoachChatAnswerSchema(["APPROVED_PLAN_ACTIVE"]);
  const properties = schema.properties;
  if (properties.answer.maxLength !== coachChatAnswerLimits.answerMaxLength) {
    throw new Error("Answer schema limit drifted from validator constant");
  }
  if (properties.reasoning_chain.maxItems !== coachChatAnswerLimits.reasoningMaxItems) {
    throw new Error("Reasoning item limit drifted from validator constant");
  }
  const reasoningProperties = properties.reasoning_chain.items.properties;
  if (reasoningProperties.value.maxLength !== coachChatAnswerLimits.reasoningValueMaxLength) {
    throw new Error("Reasoning value limit drifted from validator constant");
  }
  const evidenceCodes = properties.evidence.items.properties.code.enum;
  if (evidenceCodes.length !== 1 || evidenceCodes[0] !== "APPROVED_PLAN_ACTIVE") {
    throw new Error("Per-request evidence enum must match the validator whitelist");
  }
});

// ---------------------------------------------------------------------------
// Pass 4 — AI-context honesty: nulls must reach the model as NOT MEASURED.
// ---------------------------------------------------------------------------

Deno.test("formatContextAsMarkdown renders null health metrics as the NOT MEASURED sentinel", () => {
  const markdown = formatContextAsMarkdown({
    coaching_date: "2026-09-08",
    today_healthkit: {
      local_date: "2026-09-08",
      resting_heart_rate_bpm: null,
      hrv_sdnn_ms: null,
      sleep_minutes: null,
      steps_count: null,
    },
  });
  // Null metrics must appear as "—" (the sentinel the null contract defines),
  // not vanish: a watch-off day reads as NOT MEASURED, never as absent data.
  if (!markdown.includes("resting heart rate bpm: —")) {
    throw new Error("null RHR must render as the '—' sentinel, not be omitted");
  }
  if (!markdown.includes("hrv sdnn ms: —")) {
    throw new Error("null HRV must render as the '—' sentinel, not be omitted");
  }
  if (!markdown.includes("sleep minutes: —")) {
    throw new Error("null sleep must render as the '—' sentinel, not be omitted");
  }
});

Deno.test("formatContextAsMarkdown renders the context date for date discipline", () => {
  const markdown = formatContextAsMarkdown({ coaching_date: "2026-09-08" });
  if (!markdown.includes("2026-09-08")) {
    throw new Error("coaching_date must be visible so the model can compare value dates");
  }
  const withNone = formatContextAsMarkdown({ active_plan: { title: "Block" } });
  if (withNone.includes("## Context Date")) {
    throw new Error("no date section should render when the context has no coaching_date");
  }
});

Deno.test("formatContextAsMarkdown carries the null contract header", () => {
  const markdown = formatContextAsMarkdown({});
  if (!markdown.includes("NOT MEASURED")) {
    throw new Error("null contract header must be present in every context");
  }
});

Deno.test("formatContextAsMarkdown distinguishes measured zero from null (Pass 4)", () => {
  const markdown = formatContextAsMarkdown({
    today_healthkit: {
      local_date: "2026-09-08",
      steps_count: 0,
      resting_heart_rate_bpm: null,
    },
  });
  if (!markdown.includes("steps count: 0")) {
    throw new Error("measured 0 must render as 0 (a real zero, distinct from null)");
  }
  if (!markdown.includes("resting heart rate bpm: —")) {
    throw new Error("null must still render as '—'");
  }
});

Deno.test("formatContextAsMarkdown renders null check-in fields rather than dropping them", () => {
  const markdown = formatContextAsMarkdown({
    latest_check_in: {
      local_date: "2026-09-08",
      sleep_quality: 3,
      energy: null,
      available_to_train: null,
    },
  });
  if (!markdown.includes("energy: —")) {
    throw new Error("null check-in energy must render as '—'");
  }
  if (!markdown.includes("available to train: —")) {
    throw new Error("null available_to_train must render as '—'");
  }
  if (!markdown.includes("sleep quality: 3")) {
    throw new Error("measured sleep quality must still render");
  }
});

Deno.test("compactContext null preservation survives fitContextToLimit tiers (Groq path)", () => {
  const ctx = {
    coaching_date: "2026-09-08",
    latest_check_in: { local_date: "2026-09-08", energy: null, sleep_quality: 3 },
  };
  const compacted = compactContext(ctx);
  const ci = compacted.latest_check_in as Record<string, unknown>;
  if (!("energy" in ci) || ci.energy !== null) {
    throw new Error("null energy must survive compaction on the JSON path");
  }
  const bounded = JSON.stringify({ question: "How was my sleep?", context: compacted });
  if (!bounded.includes('"energy":null')) {
    throw new Error("serialized context must carry the null token");
  }
});

const validDeepSeekAnswer = JSON.stringify({
  answer: "Your recovery evidence supports taking the evening session easier.",
  evidence: [],
  missing_data: [],
  safety_state: "allowed",
  suggested_follow_ups: [],
  reasoning_chain: [],
});

function deepSeekResponse(
  content: string,
  finishReason: string | null = "stop",
  promptTokens = 10,
  completionTokens = 5,
): Response {
  return new Response(
    JSON.stringify({
      choices: [{
        message: { content },
        finish_reason: finishReason,
      }],
      usage: {
        prompt_tokens: promptTokens,
        completion_tokens: completionTokens,
      },
    }),
    { status: 200 },
  );
}

async function withDeepSeekEnvironment<T>(run: () => Promise<T>): Promise<T> {
  const names = [
    "COACH_AI_ENABLED",
    "COACH_MODEL_PROVIDER",
    "DEEPSEEK_API_KEY",
    "DEEPSEEK_MODEL",
  ] as const;
  const previous = new Map(names.map((name) => [name, Deno.env.get(name)]));
  Deno.env.set("COACH_AI_ENABLED", "true");
  Deno.env.set("COACH_MODEL_PROVIDER", "deepseek");
  Deno.env.set("DEEPSEEK_API_KEY", "synthetic-key");
  Deno.env.set("DEEPSEEK_MODEL", "deepseek-v4-flash");
  try {
    return await run();
  } finally {
    for (const name of names) {
      const value = previous.get(name);
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
}

Deno.test("DeepSeek Coach chat accepts complete JSON with finish_reason stop", async () => {
  await withDeepSeekEnvironment(async () => {
    let calls = 0;
    const generation = await generateCoachChat(
      "How is my recovery?",
      {},
      "recovery",
      (() => {
        calls += 1;
        return Promise.resolve(deepSeekResponse(validDeepSeekAnswer));
      }) as typeof fetch,
    );
    if (calls !== 1) throw new Error(`Expected one provider call, got ${calls}`);
    if (generation.answer.safety_state !== "allowed") {
      throw new Error("Valid DeepSeek JSON should be accepted");
    }
    if (generation.inputUnits !== 10 || generation.outputUnits !== 5) {
      throw new Error("Provider usage must be returned from the attempt");
    }
  });
});

Deno.test("DeepSeek accepts a realistic recovery answer with evidence and reasoning", async () => {
  await withDeepSeekEnvironment(async () => {
    const answer = JSON.stringify({
      answer: "Your recovery is 62/100. Keep today's work controlled.",
      evidence: [{
        code: "RECOVERY_WITHIN_BASELINE",
        label: "Recovery is within the configured score band",
        source: "feature_snapshot",
      }],
      missing_data: ["Respiratory rate was not measured"],
      safety_state: "allowed",
      suggested_follow_ups: ["Review today's workout intensity"],
      reasoning_chain: [{
        step: "Recovery",
        value: "The supplied score is 62/100.",
        evidence_id: "RECOVERY_WITHIN_BASELINE",
      }],
    });
    const generation = await generateCoachChat(
      "How is my recovery today?",
      v7ContextFixture as Record<string, unknown>,
      "recovery",
      (() => Promise.resolve(deepSeekResponse(answer))) as typeof fetch,
    );
    if (generation.answer.evidence.length !== 1 || generation.attempts[0]?.outcome !== "valid") {
      throw new Error("A grounded non-empty answer must pass on the first attempt");
    }
  });
});

Deno.test("DeepSeek thinking is high only for an explicit plan change", async () => {
  await withDeepSeekEnvironment(async () => {
    const bodies: Array<Record<string, unknown>> = [];
    const fetcher = ((_input: RequestInfo | URL, init?: RequestInit) => {
      bodies.push(JSON.parse(String(init?.body)) as Record<string, unknown>);
      return Promise.resolve(deepSeekResponse(validDeepSeekAnswer));
    }) as typeof fetch;

    await generateCoachChat("Create a new split", {}, "plan_change", fetcher);
    await generateCoachChat("How is my recovery?", {}, "recovery", fetcher);

    if (bodies[0].reasoning_effort !== "high") {
      throw new Error("Explicit plan changes must retain high reasoning effort");
    }
    if ((bodies[0].thinking as Record<string, unknown>)?.type !== "enabled") {
      throw new Error("Explicit plan changes must enable thinking");
    }
    if ((bodies[1].thinking as Record<string, unknown>)?.type !== "disabled") {
      throw new Error("Recovery chat must disable thinking");
    }
    if ("reasoning_effort" in bodies[1]) {
      throw new Error("Recovery chat must not request reasoning effort");
    }
  });
});

Deno.test("DeepSeek system prompt carries the full coach persona before the output contract", async () => {
  await withDeepSeekEnvironment(async () => {
    const bodies: Array<Record<string, unknown>> = [];
    const fetcher = ((_input: RequestInfo | URL, init?: RequestInit) => {
      bodies.push(JSON.parse(String(init?.body)) as Record<string, unknown>);
      return Promise.resolve(deepSeekResponse(validDeepSeekAnswer));
    }) as typeof fetch;

    await generateCoachChat("How is my recovery?", {}, "recovery", fetcher);

    const messages = bodies[0].messages as Array<Record<string, unknown>>;
    const system = String(messages[0]?.content ?? "");
    const markers = [
      "working with this athlete through their journey",
      "Build a mental timeline",
      "Celebrate wins",
      "Acknowledge setbacks without judgment",
      "Match your tone to their mood",
      "Offer natural follow-ups",
      "# Hard boundaries — never violate",
      "# Data honesty — never violate",
      "# Output accuracy and validation contract",
    ];
    for (const marker of markers) {
      if (!system.includes(marker)) {
        throw new Error(`DeepSeek system prompt is missing: ${marker}`);
      }
    }
    if (system.indexOf("Celebrate wins") > system.indexOf("# Output accuracy")) {
      throw new Error("The output contract must follow the persona so its rules take precedence");
    }
  });
});

Deno.test("DeepSeek Coach chat repairs a finish_reason length response once", async () => {
  await withDeepSeekEnvironment(async () => {
    const bodies: Array<Record<string, unknown>> = [];
    const responses = [
      deepSeekResponse('{"answer":"cut off', "length", 11, 6),
      deepSeekResponse(validDeepSeekAnswer, "stop", 12, 7),
    ];
    const generation = await generateCoachChat(
      "How is my recovery?",
      {},
      "recovery",
      ((_input: RequestInfo | URL, init?: RequestInit) => {
        bodies.push(JSON.parse(String(init?.body)) as Record<string, unknown>);
        return Promise.resolve(responses.shift()!);
      }) as typeof fetch,
    );
    if (bodies.length !== 2) throw new Error("A truncated response must get exactly one repair");
    if (generation.inputUnits !== 23 || generation.outputUnits !== 13) {
      throw new Error("Usage must include both provider attempts");
    }
    const first = bodies[0];
    const repair = bodies[1];
    if (first.max_tokens !== 4096 || repair.max_tokens !== 4096) {
      throw new Error("Both attempts must use the 4,096 output ceiling");
    }
    if ((repair.thinking as Record<string, unknown>)?.type !== "disabled") {
      throw new Error("Repair must disable thinking");
    }
    if (repair.temperature !== 0) throw new Error("Repair temperature must be zero");
    const messages = repair.messages as Array<Record<string, unknown>>;
    const repairInput = String(messages[1]?.content ?? "");
    if (!repairInput.includes("<invalid_candidate>")) {
      throw new Error("Repair must carry the delimited untrusted candidate");
    }
  });
});

Deno.test("DeepSeek Coach chat repairs empty and malformed response content", async () => {
  for (const invalid of ["", '{"answer":']) {
    await withDeepSeekEnvironment(async () => {
      let calls = 0;
      const generation = await generateCoachChat(
        "How is my recovery?",
        {},
        "recovery",
        (() => {
          calls += 1;
          return Promise.resolve(
            calls === 1 ? deepSeekResponse(invalid) : deepSeekResponse(validDeepSeekAnswer),
          );
        }) as typeof fetch,
      );
      if (calls !== 2 || generation.answer.safety_state !== "allowed") {
        throw new Error("Empty or malformed content should receive one successful repair");
      }
    });
  }
});

Deno.test("DeepSeek Coach chat repairs schema-invalid JSON", async () => {
  await withDeepSeekEnvironment(async () => {
    let calls = 0;
    await generateCoachChat(
      "How is my recovery?",
      {},
      "recovery",
      (() => {
        calls += 1;
        return Promise.resolve(
          calls === 1
            ? deepSeekResponse(JSON.stringify({ answer: "Missing required fields" }))
            : deepSeekResponse(validDeepSeekAnswer),
        );
      }) as typeof fetch,
    );
    if (calls !== 2) throw new Error("Schema-invalid JSON must receive one repair");
  });
});

Deno.test("DeepSeek targeted repair names the rule, path, limit, and allowed codes", async () => {
  const scenarios = [
    {
      invalid: JSON.stringify({
        answer: "Unsupported citation",
        evidence: [{ code: "INVENTED", label: "Invented", source: "feature_snapshot" }],
        missing_data: [],
        safety_state: "allowed",
        suggested_follow_ups: [],
        reasoning_chain: [],
      }),
      rule: "evidence_code_not_permitted",
      path: "evidence[0].code",
      limit: null,
    },
    {
      invalid: JSON.stringify({
        answer: "Long reasoning",
        evidence: [],
        missing_data: [],
        safety_state: "allowed",
        suggested_follow_ups: [],
        reasoning_chain: [{
          step: "Recovery",
          value: "x".repeat(coachChatAnswerLimits.reasoningValueMaxLength + 1),
          evidence_id: null,
        }],
      }),
      rule: "reasoning_value_too_long",
      path: "reasoning_chain[0].value",
      limit: coachChatAnswerLimits.reasoningValueMaxLength,
    },
  ];

  for (const scenario of scenarios) {
    await withDeepSeekEnvironment(async () => {
      const bodies: Array<Record<string, unknown>> = [];
      const responses = [
        deepSeekResponse(scenario.invalid),
        deepSeekResponse(validDeepSeekAnswer),
      ];
      const generation = await generateCoachChat(
        "How is my recovery?",
        { permitted_evidence: ["APPROVED_PLAN_ACTIVE"] },
        "recovery",
        ((_input: RequestInfo | URL, init?: RequestInit) => {
          bodies.push(JSON.parse(String(init?.body)) as Record<string, unknown>);
          return Promise.resolve(responses.shift()!);
        }) as typeof fetch,
      );
      if (bodies.length !== 2 || generation.attempts.length !== 2) {
        throw new Error("Targeted repair must make exactly one retry and retain both outcomes");
      }
      const repairMessages = bodies[1].messages as Array<Record<string, unknown>>;
      const system = String(repairMessages[0]?.content ?? "");
      for (
        const required of [
          `rule=${scenario.rule}`,
          `path=${scenario.path}`,
          "Allowed evidence codes: APPROVED_PLAN_ACTIVE",
        ]
      ) {
        if (!system.includes(required)) throw new Error(`Repair prompt omitted ${required}`);
      }
      if (scenario.limit != null && !system.includes(`limit=${scenario.limit}`)) {
        throw new Error("Repair prompt omitted the shared validator limit");
      }
      if (generation.attempts[0]?.rule !== scenario.rule) {
        throw new Error("Initial validation rule must remain observable after successful repair");
      }
    });
  }
});

Deno.test("DeepSeek Coach chat exposes only a stable code after two invalid responses", async () => {
  await withDeepSeekEnvironment(async () => {
    let calls = 0;
    try {
      await generateCoachChat(
        "How is my recovery?",
        {},
        "recovery",
        (() => {
          calls += 1;
          return Promise.resolve(deepSeekResponse("Unexpected end of JSON input"));
        }) as typeof fetch,
      );
      throw new Error("Expected the second invalid response to fail closed");
    } catch (error) {
      if (!(error instanceof CoachChatUnavailableError)) throw error;
      if (calls !== 2) throw new Error(`Expected exactly two calls, got ${calls}`);
      if (error.failureReason !== "provider_response_invalid") {
        throw new Error(`Unexpected failure code: ${error.failureReason}`);
      }
      if (error.message.includes("Unexpected end")) {
        throw new Error("Raw parser/provider content must not enter the public error");
      }
      if (error.metadata.attempt !== "repair") {
        throw new Error("Failure metadata must identify the repair attempt");
      }
      if (
        error.metadata.initialRule !== "json_syntax" || error.metadata.repairRule !== "json_syntax"
      ) {
        throw new Error("Terminal failure must retain both finite validation rule names");
      }
      const metadata = JSON.stringify(error.metadata);
      if (metadata.includes("Unexpected end")) {
        throw new Error("Raw model content must not enter terminal metadata");
      }
    }
  });
});

Deno.test("DeepSeek Coach chat preserves empty and truncated failure categories", async () => {
  const scenarios = [
    {
      response: () => deepSeekResponse("", "stop"),
      expected: "provider_response_empty",
    },
    {
      response: () => deepSeekResponse('{"answer":"cut', "length"),
      expected: "provider_response_truncated",
    },
  ];
  for (const scenario of scenarios) {
    await withDeepSeekEnvironment(async () => {
      try {
        await generateCoachChat(
          "How is my recovery?",
          {},
          "recovery",
          (() => Promise.resolve(scenario.response())) as typeof fetch,
        );
        throw new Error(`Expected ${scenario.expected}`);
      } catch (error) {
        if (!(error instanceof CoachChatUnavailableError)) throw error;
        if (error.failureReason !== scenario.expected) {
          throw new Error(`Expected ${scenario.expected}, got ${error.failureReason}`);
        }
        if (error.metadata.attempt !== "repair") {
          throw new Error("The terminal category must identify the repair attempt");
        }
      }
    });
  }
});

Deno.test("DeepSeek Coach chat does not retry HTTP, rate-limit, or timeout failures", async () => {
  const scenarios: Array<{
    expected: string;
    fetcher: typeof fetch;
  }> = [
    {
      expected: "provider_http_error",
      fetcher:
        (() => Promise.resolve(new Response("server error", { status: 500 }))) as typeof fetch,
    },
    {
      expected: "provider_rate_limited",
      fetcher: (() => Promise.resolve(new Response("slow down", { status: 429 }))) as typeof fetch,
    },
    {
      expected: "provider_timeout",
      fetcher: (() => Promise.reject(new DOMException("aborted", "AbortError"))) as typeof fetch,
    },
  ];
  for (const scenario of scenarios) {
    await withDeepSeekEnvironment(async () => {
      let calls = 0;
      try {
        await generateCoachChat(
          "How is my recovery?",
          {},
          "recovery",
          ((input: RequestInfo | URL, init?: RequestInit) => {
            calls += 1;
            return scenario.fetcher(input, init);
          }) as typeof fetch,
        );
        throw new Error(`Expected ${scenario.expected}`);
      } catch (error) {
        if (!(error instanceof CoachChatUnavailableError)) throw error;
        if (error.failureReason !== scenario.expected) {
          throw new Error(`Expected ${scenario.expected}, got ${error.failureReason}`);
        }
        if (calls !== 1) throw new Error(`${scenario.expected} must not be retried`);
      }
    });
  }
});

Deno.test("DeepSeek Coach chat attempt budgets reserve time inside the Edge deadline", () => {
  if (
    coachChatTiming.initialAttemptMs + coachChatTiming.repairAttemptMs >=
      coachChatTiming.totalDeadlineMs
  ) {
    throw new Error("Provider attempts must leave time for validation and persistence");
  }
  if (
    coachChatTiming.totalDeadlineMs !== 40_000 ||
    coachChatTiming.initialAttemptMs !== 28_000 ||
    coachChatTiming.repairAttemptMs !== 10_000
  ) {
    throw new Error("Coach chat timing contract changed unexpectedly");
  }
});

Deno.test("DeepSeek Coach chat applies a caller's attempt timing", async () => {
  await withDeepSeekEnvironment(async () => {
    const started = performance.now();
    try {
      await generateCoachChat(
        "How is my recovery?",
        {},
        "recovery",
        ((_input: RequestInfo | URL, init?: RequestInit) =>
          new Promise<Response>((_resolve, reject) => {
            init?.signal?.addEventListener(
              "abort",
              () => reject(new DOMException("aborted", "AbortError")),
            );
          })) as typeof fetch,
        { totalDeadlineMs: 400, initialAttemptMs: 50, repairAttemptMs: 50 },
      );
      throw new Error("Expected provider_timeout");
    } catch (error) {
      if (!(error instanceof CoachChatUnavailableError)) throw error;
      if (error.failureReason !== "provider_timeout") {
        throw new Error(`Expected provider_timeout, got ${error.failureReason}`);
      }
    }
    // The default initial attempt waits 28 s; this one must stop after 50 ms.
    if (performance.now() - started > 5_000) throw new Error("The caller's timing was ignored");
  });
});

Deno.test("formatPlanProposal summarises structured and text proposals", () => {
  const structured = formatPlanProposal({
    status: "pending",
    proposed_training: {
      title: "Foundation Block",
      block_weeks: 6,
      sessions_per_week: 3,
      weekly_structure: ["Full body A", { name: "Full body B" }],
      prescription: { strategy: "repeatable_full_body_foundation" },
    },
    proposed_nutrition: { calories: 2250, protein_g: 150 },
    confidence: "medium",
    effective_date: "2026-10-01",
  });
  assertEquals(
    structured,
    "pending · Foundation Block · 6 wk · 3/wk · Full body A, Full body B · " +
      "2250 kcal / 150 g protein · confidence medium · from 2026-10-01",
  );
  assertEquals(
    formatPlanProposal({ status: "accepted", proposed_training: "Keep the split" }),
    "accepted · Keep the split",
  );
});

Deno.test("the athlete profile shows the onboarding answers approval stores", () => {
  const markdown = formatContextAsMarkdown({
    coaching_date: "2026-10-02",
    profile_context: {
      experience_level: "beginner",
      training_days: [1, 3, 5],
      sex: "female",
      age: 34,
      daily_activity: "some_standing",
      equipment: ["dumbbells", "pull_up_bar"],
      limitations: "Left knee dislikes deep lunges",
      nutrition_notes: "Vegetarian",
      equipment_note: "Dumbbells up to 20 kg",
      movements_to_avoid: ["squat", "vertical_push"],
      training_years: "over_5",
      priority_muscles: ["chest", "shoulders"],
      strong_muscles: ["back"],
    },
  });
  for (
    const line of [
      "- sex: female",
      "- age: 34",
      "- daily activity outside training: some standing",
      "- equipment: dumbbells, pull up bar",
      "- limitations (athlete's words): Left knee dislikes deep lunges",
      "- diet notes (athlete's words): Vegetarian",
      "- equipment note (athlete's words): Dumbbells up to 20 kg",
      "- movements to avoid (the athlete's choice; never suggest an exercise from these): squats, overhead pressing",
      "- training for: over 5 years",
      "- focus muscles (the athlete's choice; their plan gives these extra weekly sets): chest, shoulders",
      "- strong muscles (the athlete's view): back",
    ]
  ) {
    if (!markdown.includes(line)) throw new Error(`missing: ${line}`);
  }
  const bodyweight = formatContextAsMarkdown({ profile_context: { equipment: [] } });
  if (!bodyweight.includes("- equipment: bodyweight only")) {
    throw new Error("empty equipment should read bodyweight only");
  }
});

Deno.test("a failed Coach request counts every attempt's tokens at the list price", () => {
  const previous = Deno.env.get("DEEPSEEK_INPUT_COST_PER_MILLION_USD");
  Deno.env.delete("DEEPSEEK_INPUT_COST_PER_MILLION_USD");
  try {
    const usage = coachChatFailureUsage(
      new CoachChatUnavailableError(
        "deepseek",
        "deepseek-flash",
        "provider_response_invalid",
        null,
        {
          attempts: [
            {
              attempt: "initial",
              outcome: "invalid",
              latencyMs: 1,
              promptTokens: 1000,
              completionTokens: 200,
            },
            {
              attempt: "repair",
              outcome: "invalid",
              latencyMs: 1,
              promptTokens: 500,
              completionTokens: 100,
            },
          ],
        },
      ),
    );
    assertEquals(usage.inputUnits, 1500);
    assertEquals(usage.outputUnits, 300);
    assertEquals(usage.estimatedCostUsd > 0, true);
  } finally {
    if (previous !== undefined) Deno.env.set("DEEPSEEK_INPUT_COST_PER_MILLION_USD", previous);
  }
});
