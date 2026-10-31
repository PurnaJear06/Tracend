// Judge prompts and the parsing of their verdicts, with stubbed answers. No model.
import { assert, assertEquals, assertStringIncludes, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  assertDistinctJudge,
  claimPrompt,
  expertPrompt,
  judgeClaims,
  judgeExpert,
  parseClaims,
  parseExpertVerdict,
} from "./judges.ts";
import type { RouterChat } from "./router_client.ts";

const scores = { specific: 4, correct: 5, not_generic: 3, pushback: 5, coach_like: 2 };

Deno.test("an expert verdict is read from plain or fenced JSON; a missing or out-of-range item is no verdict", () => {
  const plain = parseExpertVerdict(
    JSON.stringify({ scores, problem: "Too vague.", better_answer: "Drop to triples." }),
  );
  assertEquals(plain?.mean, 3.8);
  assertEquals(plain?.pass, false);
  assertEquals(plain?.betterAnswer, "Drop to triples.");
  const fenced = parseExpertVerdict(
    "Here you go:\n```json\n" + JSON.stringify({ scores: { ...scores, coach_like: 4 } }) + "\n```",
  );
  assertEquals(fenced?.pass, true);
  assertEquals(fenced?.problem, "");
  assertEquals(parseExpertVerdict(JSON.stringify({ scores: { ...scores, pushback: 6 } })), null);
  const { coach_like: _dropped, ...partial } = scores;
  assertEquals(parseExpertVerdict(JSON.stringify({ scores: partial })), null);
  assertEquals(parseExpertVerdict("not json"), null);
});

Deno.test("the expert prompt carries the data, the brief, the thread and the looked-up rows", () => {
  const prompt = expertPrompt({
    athleteData: "Bench 100 x 3 on 2026-10-13.",
    coachBrief: "Explain from the rows.",
    earlier: [{ role: "user", content: "Hi" }, { role: "assistant", content: "Hello" }],
    question: "Why was Tuesday bad?",
    reply: "You slept 292 min.",
    lookedUp: "### workouts 2026-10-13",
  });
  assertStringIncludes(prompt.system, "twenty years");
  for (const part of ["Bench 100 x 3", "Explain from the rows.", "Coach: Hello", "### workouts"]) {
    assertStringIncludes(prompt.user, part);
  }
});

const input = {
  reply:
    "Creatine at 3 to 5 g a day is well supported for strength. The hair-loss claim is proven. Take it after your Upper A session.",
  excerpts: { kreider_2017_creatine: "3-5 g per day ... the hair claim rests on one small study." },
};

Deno.test("claims: numbered sentences in, one verdict per research sentence out", () => {
  const prompt = claimPrompt(input);
  assertStringIncludes(
    prompt.user,
    "1. Creatine at 3 to 5 g a day is well supported for strength.",
  );
  assertStringIncludes(prompt.user, '<excerpt source="kreider_2017_creatine">');
  const claims = parseClaims(
    JSON.stringify({
      claims: [
        {
          sentence: 1,
          source: "kreider_2017_creatine",
          verdict: "supported",
          reason: "says 3-5 g",
        },
        {
          sentence: 2,
          source: "kreider_2017_creatine",
          verdict: "unsupported",
          reason: "says one study",
        },
        { sentence: 2, source: "other_2019_source", verdict: "supported", reason: "x" },
        { sentence: 9, source: "kreider_2017_creatine", verdict: "supported" },
        { sentence: 1, source: "kreider_2017_creatine", verdict: "maybe" },
      ],
    }),
    input,
  )!;
  assertEquals(claims.map((c) => [c.verdict, c.source]), [
    ["supported", "kreider_2017_creatine"],
    ["unsupported", "kreider_2017_creatine"],
    ["unsupported", "other_2019_source"],
  ]);
  assertEquals(claims[0].sentence, "Creatine at 3 to 5 g a day is well supported for strength.");
  assertEquals(claims[2].reason, "relies on other_2019_source the reply did not cite");
  assertEquals(parseClaims(JSON.stringify({ claims: [] }), input), []);
  assertEquals(parseClaims("{}", input), null);
});

Deno.test("a judge call reports its cost and a failure in place of a verdict", async () => {
  const answering: RouterChat = () =>
    Promise.resolve({
      ok: true,
      text: JSON.stringify({ scores }),
      model: "judge",
      tokens: { inputTokens: 1, outputTokens: 1, cacheReadTokens: 0, cacheWriteTokens: 0 },
      costUsd: 0.01,
      finishReason: "stop",
    });
  const verdict = await judgeExpert(answering, "judge", {
    athleteData: "",
    coachBrief: "",
    earlier: [],
    question: "q",
    reply: "r",
    lookedUp: "",
  });
  assertEquals(verdict.costUsd, 0.01);
  assert(verdict.verdict);
  const failing: RouterChat = () =>
    Promise.resolve({
      ok: false,
      reason: "http 429",
      costUsd: 0,
      kind: "http",
      status: 429,
      body: "slow down",
    });
  const failed = await judgeClaims(failing, "judge", input);
  assertEquals(failed.verdict, null);
  assertEquals(failed.failure, "http 429: slow down");
});

Deno.test("a judge must not be the Coach's own model, however the router spells it", () => {
  assertThrows(() => assertDistinctJudge("anthropic/claude-haiku-5.5", "claude-haiku-5-5"));
  assertDistinctJudge("anthropic/claude-sonnet-5.5", "claude-haiku-5-5");
});
