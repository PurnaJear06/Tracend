// Sizing a run to its cap: every conversation runs, with fewer messages before fewer judged ones.
import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { capShare, estimateRun, fewestTurns, fitRun } from "./run.ts";
import { conversations } from "./scenarios.ts";

// The sizes below are pinned on the run before the standing-state scenarios (2026-11-01), which
// change the athlete's records in a setup; a run that includes them is sized by the same rules.
const all = conversations().filter((conversation) => conversation.scenario.setup === undefined);
const base = {
  conversations: all,
  athleteModel: "deepseek-v4-flash",
  promptTokens: () => 21_000,
};

Deno.test("a cheap Coach keeps the requested messages and judges every reply", () => {
  const fit = fitRun(
    { ...base, coachModel: "claude-haiku-5-5", judgeModel: "claude-sonnet-5-5" },
    3,
    3,
  );
  assertEquals([fit.maxTurns, fit.judgeEvery, fit.fits], [3, 1, true]);
  assertEquals(fit.turns, all.length * 3);
  assert(fit.estimateUsd <= 3 * capShare);
});

Deno.test("a dear judge or Coach shrinks the run instead of skipping conversations", () => {
  const input = { ...base, coachModel: "claude-haiku-5-5", judgeModel: "claude-opus-5-5" };
  const fit = fitRun(input, 3, 3);
  assert(fit.fits, `estimate ${fit.estimateUsd}`);
  assert(fit.maxTurns < 3 || fit.judgeEvery > 1, "the full size does not fit");
  assert(fit.maxTurns >= fewestTurns);
  // It is the biggest that fits: the next size up is over the share of the cap.
  const bigger = fit.judgeEvery > 1
    ? estimateRun({ ...input, maxTurns: fit.maxTurns, judgeEvery: 1 })
    : estimateRun({ ...input, maxTurns: fit.maxTurns + 1, judgeEvery: 2 });
  assert(bigger.usd > 3 * capShare || fit.maxTurns === 3, `bigger ${bigger.usd}`);
});

Deno.test("a Sonnet Coach leaves room for no Opus judge, and fits with two messages and none", () => {
  const sonnet = { ...base, coachModel: "claude-sonnet-5-5" };
  assertEquals(fitRun({ ...sonnet, judgeModel: "claude-opus-5-5" }, 3, 3).fits, false);
  const alone = fitRun({ ...sonnet, judgeModel: null }, 3, 3);
  assertEquals([alone.maxTurns, alone.fits], [2, true]);
});

Deno.test("when nothing fits the run keeps two messages and says it does not fit", () => {
  const fit = fitRun(
    { ...base, coachModel: "claude-opus-5-5", judgeModel: "claude-opus-5-5" },
    3,
    0.5,
  );
  assertEquals([fit.maxTurns, fit.judgeEvery, fit.fits], [2, 2, false]);
});

Deno.test("judging every other reply costs less, and no judge costs least", () => {
  const input = {
    ...base,
    maxTurns: 3,
    coachModel: "claude-haiku-5-5",
    judgeModel: "claude-sonnet-5-5",
  };
  const every = estimateRun(input).usd;
  const other = estimateRun({ ...input, judgeEvery: 2 }).usd;
  const none = estimateRun({ ...input, judgeModel: null }).usd;
  assert(every > other && other > none);
});
