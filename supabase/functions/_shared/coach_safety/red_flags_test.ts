import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { parseCoachChatAnswer } from "../contracts/coach_chat_v1.ts";
import { mayConcernHealthRisk } from "../coach_chat_fallback.ts";
import { referralFor } from "./referrals.ts";
import {
  checkInEscalated,
  type RedFlagCategory,
  screenCheckIn,
  screenMessage,
  screenTurn,
} from "./red_flags.ts";

const hits: readonly (readonly [string, RedFlagCategory])[] = [
  // Chest and heart
  ["I have chest pain after my workout", "chest"],
  ["Chest pain during squats today", "chest"],
  ["my chest feels tight when I run", "chest"],
  ["There's pressure in my chest", "chest"],
  ["pain across my chest and left arm", "chest"],
  ["my chest hurts and I feel sick", "chest"],
  ["I think I'm having a heart attack", "chest"],
  ["I get palpitations after cardio", "chest"],
  ["my heart keeps skipping beats", "chest"],
  ["heart was racing while sitting for an hour", "chest"],
  // Fainting and collapse
  ["I fainted at the gym yesterday", "collapse"],
  ["I felt fainting during squats", "collapse"],
  ["I almost passed out on my last set", "collapse"],
  ["I blacked out after the sprint", "collapse"],
  ["I nearly collapsed on the treadmill", "collapse"],
  ["I feel faint when I stand up after training", "collapse"],
  ["my vision went black on the last rep", "collapse"],
  ["bhai gym mein behosh ho gaya", "collapse"],
  // Breathing
  ["I can't breathe properly", "breathing"],
  ["Experiencing severe shortness of breath", "breathing"],
  ["I'm short of breath even when sitting", "breathing"],
  ["trouble breathing after the intervals", "breathing"],
  ["I get a pain when I breathe in after sprints", "breathing"],
  ["my pulse is irregular since the weekend", "chest"],
  ["I ate nothing for 2 days and I'm training tonight", "eating"],
  ["I'm wheezing during my run", "breathing"],
  // Stroke signs
  ["my speech was slurred after the workout", "stroke"],
  ["numbness on one side of my face", "stroke"],
  ["my left side feels weak and numb", "stroke"],
  ["worst headache of my life during deadlifts", "stroke"],
  // Blood
  ["I've been coughing up blood since the weekend", "bleeding"],
  ["there is blood in my stool", "bleeding"],
  // Eating-disorder behaviour
  ["I've been purging after dinner", "eating"],
  ["been taking laxatives to drop water weight before the weigh in", "eating"],
  ["I make myself throw up after I eat", "eating"],
  ["I haven't eaten in 3 days, how do I train fasted", "eating"],
  ["I've been fasting for four days to cut faster", "eating"],
  ["doing a 5 day water fast", "eating"],
  ["I binge and then fast the next day", "eating"],
  ["I think I have an eating disorder", "eating"],
  ["I'm starving myself to hit my weight", "eating"],
  // Self-harm
  ["honestly some days i want to die", "self_harm"],
  ["I've been thinking about suicide", "self_harm"],
  ["I want to kill myself", "self_harm"],
  ["I feel like hurting myself", "self_harm"],
  // Dark urine
  ["my urine is dark brown after leg day", "dark_urine"],
  ["I think I have rhabdo", "dark_urine"],
  ["there was blood in my urine", "dark_urine"],
  // Dizziness
  ["I get dizzy after my sets", "dizziness"],
  ["felt lightheaded during cardio", "dizziness"],
  ["bhai kal se chakkar aa raha hai, gym jaun?", "dizziness"],
  ["I keep getting dizzy, how do I avoid it", "dizziness"],
  ["if I feel dizzy again should I keep training", "dizziness"],
  ["I didn't train today and felt dizzy", "dizziness"],
  ["I'm not sure if I fainted or got dizzy", "collapse"],
  // Pain
  ["I felt a sharp pain in my lower back on deadlifts", "injury_pain"],
  ["sudden pain in my knee during the squat", "injury_pain"],
  ["I heard a pop in my shoulder on bench", "injury_pain"],
  ["I tore my hamstring sprinting", "injury_pain"],
  ["pain is 8/10 in my elbow after pulling", "injury_pain"],
  ["something snapped in my knee", "injury_pain"],
  // Numbness
  ["my hands go numb on bench press", "numbness"],
  ["tingling in my left leg after squats", "numbness"],
  // Unsupported requests (the scope answer)
  ["Please diagnose my knee pain", "scope"],
  ["Should I take any medication for this?", "scope"],
  ["Can you read my medical report?", "scope"],
  ["I need rehab for my shoulder", "scope"],
  ["I am pregnant, can I still train?", "scope"],
  ["should I stop taking my meds before the cut", "scope"],
  ["Can I take a fat burner with my blood pressure medication?", "scope"],
  ["I think I tore something in my shoulder, it's swollen and I can't lift my arm.", "injury_pain"],
  ["I've been making myself throw up after big meals to stay in my calories.", "eating"],
];

Deno.test("red flags the athlete reports are caught, with their category", () => {
  const wrong = hits.filter(([message, category]) => screenMessage(message)?.category !== category)
    .map(([message]) => message);
  assertEquals(wrong, []);
  assertEquals(screenMessage(hits[0][0])?.source, "message");
});

const ordinary = [
  // Negation
  "no chest pain, no dizziness, just a tired week",
  "I don't feel dizzy at all, should I train legs?",
  "I have no chest pain or dizziness or fainting",
  "never fainted in my life, how heavy can I go?",
  "I wasn't dizzy and my breathing was fine",
  "without any chest pain I finished the session",
  "I haven't had any numbness since last month",
  "no pain, no sharp pain, just soreness",
  // Hypothetical and education
  "how do I avoid dizziness when cutting?",
  "how can I prevent feeling lightheaded on a deficit",
  "what causes dizziness during workouts?",
  "what are the signs of overtraining",
  "what should I do if I ever feel chest tightness on a run",
  "what if I get dizzy during intervals",
  // Ordinary talk that mentions the body
  "my legs are sore",
  "I'm so sore after leg day, can I train?",
  "my chest day workout felt great",
  "chest press felt heavy, should I lower the weight?",
  "my back is stiff this morning",
  "I'm out of breath after my last set, is that normal?",
  "my heart rate went to 170 on the last interval",
  "I take medication, can I train?",
  "does my medication change how I should warm up?",
  "Is it fine to train after my blood pressure tablet?",
  "I take a blood pressure tablet every morning, can I do heavy squats?",
  "I was diagnosed with diabetes last year, how should I eat?",
  "I get a tingle from beta-alanine in my pre-workout",
  "I feel a bit weird today",
  "feeling weird and a bit off since lunch",
  "my knee is a bit achy after running",
  "what causes a plateau?",
  "does creatine cause dizziness?",
  "can you explain dizziness on keto",
  "it's hard to breathe through my nose with this cold",
  "I cut myself shaving",
  "this workout is killing me",
  "how long should I fast for fat loss",
  "3 day split or 4 day?",
  "I'm starving after leg day, is a big dinner ok?",
  "I'm not eating enough protein, am I?",
  "I binged on pizza on Saturday, how do I get back on track?",
  "I do intermittent fasting 16:8, is that fine?",
  "The prescribed weight felt heavy today.",
  "I broke my bench PR today! What next?",
  "I'm dying after that workout lol",
  "Hi",
  "How many sets should I do today?",
  "What should I eat for dinner?",
  "Show me my progress",
  "my stroke rate on the rower is 24",
  "my form collapsed on the last squat rep",
];

Deno.test("negated, hypothetical and everyday messages reach the model", () => {
  assertEquals(ordinary.filter((message) => screenMessage(message) !== null), []);
});

Deno.test("the most urgent flag wins when a message carries several", () => {
  assertEquals(screenMessage("I fainted and now my knee hurts, sharp pain")?.category, "collapse");
  assertEquals(screenMessage("I want to die, I purge every night")?.category, "self_harm");
  assertEquals(screenMessage("no chest pain but I fainted")?.category, "collapse");
  assertEquals(screenMessage("I didn't faint but I felt dizzy")?.category, "dizziness");
});

Deno.test("every message the screen catches is also caught by the wider data-summary screen", () => {
  const missed = hits.filter(([message, category]) =>
    category !== "scope" && !mayConcernHealthRisk(message)
  );
  assertEquals(missed, []);
});

Deno.test("every referral is a valid answer without numbers from the athlete's data", () => {
  const categories = new Set(hits.map(([, category]) => category));
  for (const category of categories) {
    const reply = referralFor({ category, rule: "x", source: "message" });
    parseCoachChatAnswer(reply, []);
    assertEquals(reply.evidence, []);
    assert(reply.answer.length > 80, category);
    const expected = category === "self_harm" || category === "scope" ? "refused" : "limited";
    assertEquals(reply.safety_state, expected, category);
    assert(!/\b(?:reassur|nothing to worry|probably fine|harmless)/i.test(reply.answer), category);
  }
  const urgent = ["chest", "collapse", "breathing", "stroke", "bleeding", "self_harm"] as const;
  for (const category of urgent) {
    assertStringIncludes(
      referralFor({ category, rule: "x", source: "message" }).answer,
      "emergency number",
    );
  }
  assertStringIncludes(
    referralFor({ category: "injury_pain", rule: "x", source: "message" }).answer,
    "doctor or physio",
  );
  assertStringIncludes(
    referralFor({ category: "self_harm", rule: "x", source: "message" }).answer,
    "988",
  );
});

Deno.test("scope requests keep the clinical-boundary answer and its follow-ups", () => {
  const reply = referralFor({ category: "scope", rule: "diagnosis_request", source: "message" });
  assertStringIncludes(reply.answer, "diagnosis");
  assertStringIncludes(reply.answer, "qualified clinician");
  assert(reply.suggested_follow_ups.length > 0);
});

const escalatedContext = {
  coaching_date: "2026-10-17",
  permitted_evidence: ["APPROVED_PLAN_ACTIVE", "CHECK_IN_SAFETY_ESCALATION"],
};

Deno.test("pain of 7 or more on today's check-in stops training questions only", () => {
  assert(checkInEscalated(escalatedContext));
  for (
    const question of [
      "Should I train legs today?",
      "can I do my planned workout",
      "should i skip the gym or push through",
      "can I still do my planned workout",
    ]
  ) {
    assertEquals(screenCheckIn(escalatedContext, question)?.category, "check_in_pain", question);
    assertEquals(screenCheckIn(escalatedContext, question)?.source, "check_in");
  }
  for (
    const question of [
      "What should I eat tonight?",
      "How did I sleep this week?",
      "Why is my weight stable?",
      "what's my protein plan for the week",
      "hello",
    ]
  ) {
    assertEquals(screenCheckIn(escalatedContext, question), null, question);
  }
  assertEquals(
    screenCheckIn({ coaching_date: "2026-10-17", permitted_evidence: [] }, "train?"),
    null,
  );
});

Deno.test("the check-in is also read from the context when the evidence code is absent", () => {
  const context = {
    coaching_date: "2026-10-17",
    permitted_evidence: [],
    latest_check_in: { local_date: "2026-10-17", pain_severity: 7 },
  };
  assert(checkInEscalated(context));
  assert(
    !checkInEscalated({
      ...context,
      latest_check_in: { local_date: "2026-10-15", pain_severity: 9 },
    }),
  );
  assert(
    !checkInEscalated({
      ...context,
      latest_check_in: { local_date: "2026-10-17", pain_severity: 6 },
    }),
  );
});

Deno.test("a turn is screened on the message first, then on the check-in", () => {
  assertEquals(screenTurn("I fainted", escalatedContext)?.source, "message");
  assertEquals(screenTurn("Should I train?", escalatedContext)?.source, "check_in");
  assertEquals(screenTurn("What should I eat?", escalatedContext), null);
});

Deno.test("a hit carries a finite rule name and never the message", () => {
  const hit = screenMessage("I fainted at 7pm in my kitchen")!;
  assertEquals(hit, { category: "collapse", rule: "faint", source: "message" });
  assert(!JSON.stringify(hit).includes("kitchen"));
});
