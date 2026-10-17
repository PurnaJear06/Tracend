// Coach chat's budget outcomes on the gateway path, offline: a fake provider answers, a fake
// budget RPC records every reservation and settlement, and the failure rule is the handler's
// own (`keepAfterFailure`).

import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import {
  captureLogs,
  claudeMessage,
  fakeFetch,
  jsonResponse,
  routeFor,
  type Sent,
} from "../_shared/ai/fakes.ts";
import { evalProfiles } from "../_evals/fixtures.ts";
import {
  chooseCoachChatRoute,
  type CoachChatAttemptBudget,
  coachChatReservationCapUsd,
  coachChatReservationUsd,
  generateCoachChatViaGateway,
} from "../_shared/providers/coach_chat_provider_gateway.ts";
import {
  classifyQuestion,
  coachChatFailureUsage,
  CoachChatUnavailableError,
} from "../_shared/providers/coach_chat_provider.ts";
import { CoachChatBudgetLedger, keepAfterFailure } from "./budget_ledger.ts";

const question = "How did my training go this week?";
const rich = () => structuredClone(evalProfiles().find((p) => p.id === "rich")!.context);

const good = JSON.stringify({
  answer: "Your recovery is **38/100**, so keep today's session light.",
  evidence: [{ code: "RECOVERY_BELOW_BASELINE", label: "Recovery 38", source: "coach_context" }],
  missing_data: [],
  safety_state: "allowed",
  suggested_follow_ups: [],
  reasoning_chain: [],
});
const answered = (text: string, usage: Record<string, unknown> = {}) =>
  jsonResponse(claudeMessage({ content: [{ type: "text", text }] }, usage));

/** A budget RPC that numbers each reservation r1, r2, ... and records what happens to it. */
function fakeBudget(options: { refuseFrom?: number } = {}) {
  const reserved: { id: string; ceilingUsd: number }[] = [];
  const settled: string[] = [];
  const rpc = (fn: string, args: Record<string, unknown>) => {
    if (fn === "reserve_ai_budget_v2") {
      if (options.refuseFrom !== undefined && reserved.length + 1 >= options.refuseFrom) {
        return Promise.resolve({ data: null, error: { message: "refused" } });
      }
      const id = `r${reserved.length + 1}`;
      reserved.push({ id, ceilingUsd: args.ceiling_usd as number });
      return Promise.resolve({ data: id, error: null });
    }
    if (fn === "settle_ai_budget") {
      settled.push(args.reservation_id as string);
      return Promise.resolve({ data: null, error: null });
    }
    throw new Error(`unexpected rpc ${fn}`);
  };
  return { reserved, settled, ledger: new CoachChatBudgetLedger(rpc, "user-1") };
}

type Turn = Readonly<{
  fetch: typeof fetch;
  sent: ReturnType<typeof fakeFetch>["sent"];
  ledger: CoachChatBudgetLedger;
  reserved: { id: string; ceilingUsd: number }[];
  settled: string[];
  error: unknown;
}>;

/** What coach-chat does around one turn: reserve the first place, run, apply the failure rule, release. */
async function turn(
  respond: (sent: Sent, index: number) => Response | Promise<Response>,
  options: {
    route?: ReturnType<typeof routeFor>;
    refuseFrom?: number;
    budget?: (ledger: CoachChatBudgetLedger) => CoachChatAttemptBudget;
    timing?: Parameters<typeof generateCoachChatViaGateway>[2];
  } = {},
): Promise<Turn & { generation: Awaited<ReturnType<typeof generateCoachChatViaGateway>> | null }> {
  const route = options.route ?? routeFor("coach_chat", { MODEL: "claude-haiku-5-5" });
  let index = 0;
  const fake = fakeFetch((sent) => respond(sent, index++));
  const { reserved, settled, ledger } = fakeBudget({ refuseFrom: options.refuseFrom });
  assert(await ledger.reserveInitial(coachChatReservationUsd(route, [])!));
  let generation: Awaited<ReturnType<typeof generateCoachChatViaGateway>> | null = null;
  let error: unknown = null;
  await captureLogs(async () => {
    try {
      generation = await generateCoachChatViaGateway(
        {
          question,
          context: rich(),
          contextKind: classifyQuestion(question),
          route,
          consentVendor: "anthropic",
          budget: options.budget ? options.budget(ledger) : ledger.attemptBudget,
        },
        { fetch: fake.fetch },
        options.timing,
      );
    } catch (caught) {
      error = caught;
      keepAfterFailure(ledger, caught, true);
    }
  });
  await ledger.release();
  return { fetch: fake.fetch, sent: fake.sent, ledger, reserved, settled, error, generation };
}

Deno.test("an unbilled provider failure releases its place", async () => {
  const result = await turn(() =>
    jsonResponse({ type: "error", error: { type: "overloaded_error", message: "busy" } }, 529)
  );
  assert(result.error instanceof CoachChatUnavailableError);
  assertEquals(result.error.failureReason, "provider_http_error");
  assertEquals(result.sent.length, 1);
  assertEquals(result.reserved.map((r) => r.id), ["r1"]);
  assertEquals(result.settled, ["r1"]);
});

Deno.test("a billed answer settles its place", async () => {
  const result = await turn(() => answered(good, { output_tokens: 200 }));
  assert(result.generation);
  assertEquals(result.reserved.map((r) => r.id), ["r1"]);
  assertEquals(result.settled, ["r1"]);
});

Deno.test("a repair reserves its own place and both are settled", async () => {
  const result = await turn((_, index) =>
    answered(index === 0 ? "not json" : good, { output_tokens: 20 })
  );
  assert(result.generation);
  assertEquals(result.sent.length, 2);
  assertEquals(result.reserved.map((r) => r.id), ["r1", "r2"]);
  assert(
    result.reserved.every((r) => r.ceilingUsd > 0 && r.ceilingUsd <= coachChatReservationCapUsd),
  );
  assertEquals(result.settled, ["r1", "r2"]);
});

Deno.test("a refused repair place sends no repair and still settles the first", async () => {
  const result = await turn(() => answered("not json", { output_tokens: 20 }), { refuseFrom: 2 });
  assert(result.error instanceof CoachChatUnavailableError);
  assertEquals(result.sent.length, 1);
  assertEquals(result.error.metadata.repairSkipped, "reservation_refused");
  assertEquals(result.reserved.map((r) => r.id), ["r1"]);
  assertEquals(result.settled, ["r1"]);
  assert(coachChatFailureUsage(result.error).estimatedCostUsd > 0);
});

Deno.test("a sent request that timed out with no usage keeps its place open", async () => {
  const result = await turn(
    (sent) =>
      new Promise<Response>((_, reject) => {
        sent.signal?.addEventListener("abort", () => reject(new DOMException("", "AbortError")));
      }),
    { route: routeFor("coach_chat", { MODEL: "claude-haiku-5-5", TIMEOUT_MS: "1000" }) },
  );
  assert(result.error instanceof CoachChatUnavailableError);
  assertEquals(result.error.failureReason, "provider_timeout");
  assertEquals(result.sent.length, 1);
  assertEquals(result.reserved.map((r) => r.id), ["r1"]);
  assertEquals(result.settled, []);
});

Deno.test("a repair that times out keeps only the repair's place; the recorded first is settled", async () => {
  const result = await turn(
    (sent, index) =>
      index === 0 ? answered("not json", { output_tokens: 20 }) : new Promise<Response>(
        (_, reject) => {
          sent.signal?.addEventListener("abort", () => reject(new DOMException("", "AbortError")));
        },
      ),
    { route: routeFor("coach_chat", { MODEL: "claude-haiku-5-5", TIMEOUT_MS: "1000" }) },
  );
  assert(result.error instanceof CoachChatUnavailableError);
  assertEquals(result.error.failureReason, "provider_timeout");
  assertEquals(result.reserved.map((r) => r.id), ["r1", "r2"]);
  assertEquals(result.settled, ["r1"]);
});

Deno.test("a deadline that passes before the repair releases everything and charges the first attempt once", async () => {
  const realNow = Date.now;
  let skewMs = 0;
  Date.now = () => realNow() + skewMs;
  try {
    const result = await turn(() => {
      // The first answer arrives after the turn's whole deadline.
      skewMs = 60_000;
      return answered("not json", { output_tokens: 20 });
    });
    assert(result.error instanceof CoachChatUnavailableError);
    assertEquals(result.error.failureReason, "provider_timeout");
    assertEquals(result.sent.length, 1);
    assertEquals(result.reserved.map((r) => r.id), ["r1"]);
    assertEquals(result.settled, ["r1"]);
    // Only the first attempt's priced usage is recorded: 1,000 × 0.10 + 20 × 0.50 µUSD.
    assertEquals(coachChatFailureUsage(result.error).estimatedCostUsd, 0.00011);
  } finally {
    Date.now = realNow;
  }
});

Deno.test("a failure that is not the provider's own outcome keeps every place", async () => {
  const { ledger, reserved, settled } = fakeBudget();
  assert(await ledger.reserveInitial(0.01));
  assert(await ledger.reserveAttempt(0.01, "repair"));
  keepAfterFailure(ledger, new Error("unexpected"), true);
  await ledger.release();
  assertEquals(reserved.length, 2);
  assertEquals(settled, []);
});

Deno.test("a timeout on the second lookup call keeps only that call's place, not the settled first round's", async () => {
  const { ledger, reserved, settled } = fakeBudget();
  assert(await ledger.reserveInitial(0.01)); // r1: the first call
  assert(await ledger.reserveAttempt(0.01, "lookup")); // r2: round one's call, answered
  assert(await ledger.reserveAttempt(0.01, "lookup")); // r3: round two's call, timed out
  ledger.attemptBudget.inFlight("lookup");
  await ledger.release();
  assertEquals(reserved.length, 3);
  // The initial call and the first lookup call settle; only the call in flight stays open.
  assertEquals(settled.sort(), ["r1", "r2"]);
});

Deno.test("an initial or repair timeout keeps that one place", async () => {
  for (const kind of ["initial", "repair"] as const) {
    const { ledger, settled } = fakeBudget();
    assert(await ledger.reserveInitial(0.01));
    assert(await ledger.reserveAttempt(0.01, "repair"));
    ledger.attemptBudget.inFlight(kind);
    await ledger.release();
    assertEquals(settled, [kind === "initial" ? "r2" : "r1"]);
  }
});

Deno.test("today's path still keeps its place on a timeout", async () => {
  const timeout = new CoachChatUnavailableError("deepseek", "deepseek-flash", "provider_timeout");
  const other = new CoachChatUnavailableError("deepseek", "deepseek-flash", "provider_http_error");
  for (const [error, settledPlaces] of [[timeout, 0], [other, 1]] as const) {
    const settled: string[] = [];
    const ledger = new CoachChatBudgetLedger((fn, args) => {
      if (fn === "settle_ai_budget") settled.push(args.reservation_id as string);
      return Promise.resolve({ data: fn === "reserve_ai_budget" ? "legacy-1" : null, error: null });
    }, "user-1");
    assert(await ledger.reserveLegacy());
    keepAfterFailure(ledger, error, false);
    await ledger.release();
    assertEquals(settled.length, settledPlaces);
  }
});

Deno.test("a route that is not evaluated or cannot be reserved never reaches the gateway", () => {
  const unevaluated = routeFor("coach_chat", { MODEL: "claude-haiku-5-5" });
  assertEquals(chooseCoachChatRoute(unevaluated, []).route, null);
  const huge = routeFor("coach_chat", {
    MODEL: "claude-sonnet-5-5",
    MAX_OUTPUT_TOKENS: "32000",
    EVALUATED: "true",
  });
  assertEquals(chooseCoachChatRoute(huge, []).route, null);
});

Deno.test("a refused first place carries the database's reason for the 429", async () => {
  for (
    const [message, reason] of [
      ["monthly cost limit reached", "monthly_cost_limit"],
      ["daily rate limit reached", "daily_rate_limit"],
      ["global monthly cost limit reached", "global_monthly_cost_limit"],
    ] as const
  ) {
    const ledger = new CoachChatBudgetLedger(
      () => Promise.resolve({ data: null, error: { message } }),
      "user-1",
    );
    assertEquals(ledger.refusal, null);
    assertEquals(await ledger.reserveInitial(0.01), false);
    assertEquals(ledger.refusal, reason);
    assertEquals(await ledger.reserveLegacy(), false);
    assertEquals(ledger.refusal, reason);
  }
});
