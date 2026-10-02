import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { generateFollowUpQuestions, parseFollowUpQuestions } from "./questions.ts";
import { answersFor } from "./test_helpers.ts";
import type { OnboardingModelConfig } from "../providers/onboarding_plan_provider.ts";

const question = (category: string, text: string, choices: string[] = []) => ({
  category,
  question: text,
  choices,
});

Deno.test("valid questions: allowed topic, one sentence, optional quick answers", () => {
  assertEquals(
    parseFollowUpQuestions(JSON.stringify({
      questions: [
        question("split_history", "What split have you run for the last few months?", [
          "Full body",
          "Upper/lower",
          "Push/pull/legs",
        ]),
        question("stalled_lift", "Which lift has stopped moving?"),
      ],
    })),
    [
      {
        category: "split_history",
        question: "What split have you run for the last few months?",
        choices: ["Full body", "Upper/lower", "Push/pull/legs"],
      },
      { category: "stalled_lift", question: "Which lift has stopped moving?", choices: [] },
    ],
  );
  assertEquals(parseFollowUpQuestions('{"questions":[]}'), []);
});

Deno.test("any broken rule drops the whole reply", () => {
  const bad = [
    "not json",
    "[]",
    '{"questions":[],"note":"x"}',
    JSON.stringify({ questions: [question("injury_history", "Any old injuries?")] }),
    JSON.stringify({ questions: [question("stalled_lift", "Does your knee pain stop you?")] }),
    JSON.stringify({ questions: [question("recovery_between_sessions", "Seen a doctor lately?")] }),
    JSON.stringify({ questions: [question("split_history", "Tell me your split")] }),
    JSON.stringify({ questions: [question("split_history", `${"x".repeat(170)}?`)] }),
    JSON.stringify({ questions: [question("split_history", "Which split?", ["Only one"])] }),
    JSON.stringify({ questions: [question("split_history", "Which split?", ["A", "A"])] }),
    JSON.stringify({
      questions: [1, 2, 3, 4].map((n) => question("split_history", `Question ${n}?`)),
    }),
    JSON.stringify({
      questions: [
        question("split_history", "Which split?"),
        question("stalled_lift", "Which split?"),
      ],
    }),
  ];
  for (const content of bad) assertEquals(parseFollowUpQuestions(content), null, content);
});

const config: OnboardingModelConfig = {
  provider: "deepseek",
  model: "deepseek-flash",
  url: "https://example.test/v1/chat/completions",
  apiKey: "test",
  extraBody: { thinking: { type: "disabled" } },
  thinkingBody: { thinking: { type: "enabled" }, reasoning_effort: "high" },
  thinking: true,
  price: { input: 0.3, output: 1.2 },
};
const open = { consentGranted: true, budgetAvailable: true };

const replying = (content: string, finish = "stop", requests: unknown[] = []) =>
  ((_input: unknown, init?: RequestInit) => {
    requests.push(JSON.parse(String(init?.body)));
    return Promise.resolve(
      new Response(JSON.stringify({
        choices: [{ message: { content }, finish_reason: finish }],
        usage: {
          prompt_tokens: 900,
          completion_tokens: 1400,
          completion_tokens_details: { reasoning_tokens: 1200 },
        },
      })),
    );
  }) as typeof fetch;

Deno.test("questions think within their own small output limit and record usage", async () => {
  const requests: Record<string, unknown>[] = [];
  const result = await generateFollowUpQuestions(
    answersFor(),
    { kind: "model", config },
    open,
    null,
    null,
    replying(
      JSON.stringify({ questions: [question("schedule_flexibility", "Can sessions move days?")] }),
      "stop",
      requests,
    ),
  );
  assertEquals(result.questions.length, 1);
  assertEquals(result.skippedReason, null);
  assertEquals(result.usage?.reasoningUnits, 1200);
  assertEquals(requests[0].max_tokens, 4000);
  assertEquals(requests[0].thinking, { type: "enabled" });
  const messages = requests[0].messages as { content: string }[];
  assertStringIncludes(messages[0].content, "Never ask about injuries");
  assertStringIncludes(messages[1].content, "<athlete>");
});

Deno.test("no consent, no budget or the rules provider ask nothing and spend nothing", async () => {
  const never = (() => {
    throw new Error("no call expected");
  }) as unknown as typeof fetch;
  for (
    const [resolution, gate, reason] of [
      [{ kind: "model", config }, { ...open, consentGranted: false }, "ai_consent_not_granted"],
      [{ kind: "model", config }, { ...open, budgetAvailable: false }, "ai_usage_limit"],
      [{ kind: "rules", reason: "provider_mock" }, open, "provider_mock"],
    ] as const
  ) {
    const result = await generateFollowUpQuestions(
      answersFor(),
      resolution,
      gate,
      null,
      null,
      never,
    );
    assertEquals(result, { questions: [], usage: null, skippedReason: reason });
  }
});

Deno.test("an invalid or cut-off reply asks nothing, but its tokens are recorded", async () => {
  const invalid = await generateFollowUpQuestions(
    answersFor(),
    { kind: "model", config },
    open,
    null,
    null,
    replying(JSON.stringify({ questions: [question("injury_history", "Any injuries?")] })),
  );
  assertEquals(invalid.questions, []);
  assertEquals(invalid.skippedReason, "questions_invalid");
  assertEquals(invalid.usage?.outputUnits, 1400);

  const truncated = await generateFollowUpQuestions(
    answersFor(),
    { kind: "model", config },
    open,
    null,
    null,
    replying("", "length"),
  );
  assertEquals(truncated.skippedReason, "provider_response_truncated");
  assertEquals(truncated.usage?.finishReason, "length");
  assertEquals(truncated.usage?.outputUnits, 1400);

  const failing = await generateFollowUpQuestions(
    answersFor(),
    { kind: "model", config },
    open,
    null,
    null,
    (() => Promise.resolve(new Response("busy", { status: 503 }))) as typeof fetch,
  );
  assertEquals(failing, { questions: [], usage: null, skippedReason: "provider_http_error" });
});
