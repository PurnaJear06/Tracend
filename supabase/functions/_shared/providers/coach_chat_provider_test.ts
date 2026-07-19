import {
  classifyQuestion,
  compactContext,
  generateCoachChat,
  isCoachChatLiveProviderConfigured,
} from "./coach_chat_provider.ts";

Deno.test("Coach chat never turns an unconfigured provider into a mock answer", () => {
  const environment = new Map<string, string>([
    ["COACH_AI_ENABLED", "false"],
    ["COACH_MODEL_PROVIDER", "mock"],
  ]);
  if (isCoachChatLiveProviderConfigured(environment)) {
    throw new Error("Unconfigured chat must fail closed instead of returning a mock reply.");
  }
});

Deno.test("classifyQuestion returns plan_change for planning keywords", () => {
  const cases = [
    "What is my weekly progress?",
    "Can you create a new plan?",
    "I want to change my plan",
    "I have plateaued on bench",
    "Rate my progression this month",
    "Design my next block",
    "Change my training program",
    "My routine needs an update",
    "I need a new split",
    "Should I deload this week?",
    "Let's talk periodization",
    "I think I hit a plateau",
  ];
  for (const q of cases) {
    if (classifyQuestion(q) !== "plan_change") {
      throw new Error(`Expected plan_change for: "${q}", got: ${classifyQuestion(q)}`);
    }
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

Deno.test("classifyQuestion nutrition_focus takes priority over daily_action for food queries", () => {
  if (classifyQuestion("What should I eat for protein?") !== "nutrition_focus") {
    throw new Error(
      "Nutrition question with 'what' and 'protein' should classify as nutrition_focus",
    );
  }
});

Deno.test("compactContext strips null values", () => {
  const input = { a: "hello", b: null, c: 0 };
  const result = compactContext(input);
  if ("b" in result) throw new Error("null value b should be stripped");
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

Deno.test("compactContext removes undefined-level keys after compaction", () => {
  const input = { a: null, b: { c: null } };
  const result = compactContext(input);
  if ("a" in result) throw new Error("null top-level should be absent");
  if ("b" in result) throw new Error("null-only nested should be absent");
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

    await generateCoachChat("Hello", massiveContext, mockFetcher as unknown as typeof fetch);

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
