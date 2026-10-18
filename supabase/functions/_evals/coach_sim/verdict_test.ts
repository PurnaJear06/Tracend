// When a run is a harness failure: the thresholds, on hand-built conversation runs.
import type { ProviderError } from "./diagnostics.ts";
import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import type { ConversationRun, TurnRun } from "./simulate.ts";
import { athleteFailureLimit, harnessFailures, providerErrorLimit } from "./verdict.ts";
import { selectConversations } from "./scenarios.ts";

const conversation = selectConversations("primary/pushback")[0];

function turn(overrides: {
  outcome?: string;
  failureCode?: string;
  expert?: boolean;
  judgeFailures?: string[];
  claims?: boolean;
}): TurnRun {
  return {
    number: 1,
    reply: {
      outcome: overrides.outcome ?? "model",
      answer: "a",
      ...(overrides.failureCode ? { failureCode: overrides.failureCode } : {}),
    },
    judgeFailures: overrides.judgeFailures ?? [],
    ...(overrides.expert ? { expert: { mean: 4 } } : {}),
    ...(overrides.claims ? { claims: [] } : {}),
  } as unknown as TurnRun;
}

const run = (
  turns: TurnRun[],
  ended: ConversationRun["ended"] = "planned",
  error?: string,
): ConversationRun => ({
  id: "c",
  conversation,
  turns,
  grades: [],
  ended,
  ...(error ? { error } : {}),
  costUsd: 0,
});

const good = () => turn({ expert: true });
const broken = () => turn({ outcome: "data_summary", failureCode: "provider_http_error" });

Deno.test("a sound run has no harness failure, whatever the quality findings", () => {
  const poor = turn({ outcome: "data_summary", failureCode: "provider_response_invalid" });
  assertEquals(harnessFailures([run([good(), good(), poor])], true), []);
  // A red-flag referral is fixed text and never counts as a Coach turn.
  const referral = turn({ outcome: "boundary" });
  assertEquals(harnessFailures([run([good(), referral])], true), []);
});

Deno.test("more than 20% of Coach turns ending in a provider error fails the run", () => {
  assertEquals(providerErrorLimit, 0.2);
  // 1 of 5 is exactly 20%: allowed.
  assertEquals(harnessFailures([run([broken(), good(), good(), good(), good()])], true), []);
  // 2 of 5 is over.
  const failures = harnessFailures([run([broken(), broken(), good(), good(), good()])], true);
  assertEquals(failures.length, 1);
  assertStringIncludes(failures[0], "2 of 5 Coach turns ended in a provider error");
  // Timeouts and rate limits are provider errors too.
  const slow = turn({ outcome: "data_summary", failureCode: "provider_timeout" });
  assertEquals(harnessFailures([run([slow, slow, good()])], true).length, 1);
});

Deno.test("every Coach turn failing is reported as one", () => {
  const failures = harnessFailures([run([broken(), broken(), broken()])], true);
  assertStringIncludes(failures.join("\n"), "3 of 3 Coach turns ended in a provider error");
  assertStringIncludes(failures.join("\n"), "No Coach turn got a model answer");
});

Deno.test("a judge with no verdicts fails the run only when judges are on", () => {
  const noVerdict = () => turn({ judgeFailures: ["expert: http 400: nope"] });
  const failures = harnessFailures([run([noVerdict(), noVerdict()])], true);
  assertEquals(failures.length, 2);
  assertStringIncludes(failures[0], "expert judge produced no verdicts");
  assertStringIncludes(failures[1], "2 of 2 judge calls gave no verdict");
  assertEquals(harnessFailures([run([noVerdict(), noVerdict()])], false), []);
  // A judge that fails more than one call in ten is not trusted, even with some verdicts.
  assertStringIncludes(
    harnessFailures([run([noVerdict(), good()])], true).join("\n"),
    "1 of 2 judge calls gave no verdict",
  );
  const sound = Array.from({ length: 10 }, () => good());
  assertEquals(harnessFailures([run([noVerdict(), ...sound])], true), []);
  // The claim judge failing every call is reported, an empty verdict is not a failure.
  const claimFail = () => turn({ expert: true, judgeFailures: ["claims: http 500: down"] });
  assertStringIncludes(
    harnessFailures([run([claimFail(), claimFail()])], true).join("\n"),
    "claim-support judge produced no verdicts in 2 calls",
  );
  assertEquals(harnessFailures([run([turn({ expert: true, claims: true })])], true), []);
});

Deno.test("an athlete that cannot continue more than 20% of conversations fails the run", () => {
  assertEquals(athleteFailureLimit, 0.2);
  const stuck = run([good()], "athlete_failed", "athlete model: empty answer");
  const fine = () => run([good()]);
  assertEquals(harnessFailures([stuck, fine(), fine(), fine(), fine()], true), []);
  assertStringIncludes(
    harnessFailures([stuck, stuck, fine(), fine(), fine()], true).join("\n"),
    "athlete model could not continue 2 of 5 conversations",
  );
});

Deno.test("an exception in the simulator and a run with no turn fail it", () => {
  assertStringIncludes(
    harnessFailures([run([good()], "harness_error", "TypeError: boom")], true).join("\n"),
    "Harness error in c: TypeError: boom",
  );
  assertStringIncludes(harnessFailures([run([], "budget")], true).join("\n"), "No Coach turn ran");
});

Deno.test("a judge call that ran out of output tokens is a harness error, never a pass", () => {
  const cut: ProviderError = {
    source: "judge",
    model: "claude-opus-5.5",
    status: 200,
    kind: "truncated",
    body: "finish_reason=length completion_tokens=3000 max_tokens=3000",
  };
  const sound = Array.from({ length: 20 }, () => good());
  assertEquals(harnessFailures([run(sound)], true, []), []);
  assertStringIncludes(
    harnessFailures([run(sound)], true, [cut]).join("\n"),
    "1 judge calls ran into their output limit",
  );
  // The Coach hitting its own limit is a finding about the Coach, not the harness.
  assertEquals(harnessFailures([run(sound)], true, [{ ...cut, source: "coach" }]), []);
  assertEquals(harnessFailures([run(sound)], false, [cut]), []);
});
