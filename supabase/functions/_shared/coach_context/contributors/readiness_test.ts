import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { redFlagCodes } from "../../training/joints/red_flags.ts";
import {
  adjustmentKinds,
  readinessBands,
  safetyRoutes,
  unavailableReasons,
} from "../../training/readiness/payload.ts";
import {
  contextJointAreas,
  contextJointStates,
  parseReadinessContext,
  readinessContextRpc,
} from "../../training/readiness/context_payload.ts";
import { coachContextContributors, coachContextContributorsFor } from "../registry.ts";
import { renderCoachContext } from "../host.ts";
import {
  createReadinessContributor,
  readinessBudgetChars,
  readinessDeadlineMs,
  readinessSourceFromRpc,
} from "./readiness.ts";
import type { ServiceRpc } from "../service_source.ts";

const today = "2026-10-24";
const turn = { userId: "user-1", question: "What should I do today?", localDate: today };

/** A payload as get_readiness_context_v1 returns it, with changes. */
function payload(changes: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    schema_version: "1.0",
    local_date: today,
    band: "green",
    kind: "none",
    status: "none",
    available: true,
    unavailable_reason: null,
    safety_route: null,
    triggers: [],
    confidence: "medium",
    joint_states: [],
    rules_version: "readiness-v1",
    ...changes,
  };
}

const rpcReturning = (data: unknown): ServiceRpc => () => Promise.resolve({ data, error: null });

async function rendered(data: unknown, deadlineMs?: number) {
  const result = await renderCoachContext(
    [createReadinessContributor(readinessSourceFromRpc(rpcReturning(data)), deadlineMs)],
    turn,
  );
  return {
    text: result.texts.readiness ?? "",
    trace: result.traces?.readiness,
    outcome: result.outcomes[0],
    records: result.records?.readiness ?? [],
  };
}

Deno.test("the parser keeps only what the context renders and ignores keys it does not know", () => {
  const card = parseReadinessContext(
    payload({
      band: "amber",
      kind: "hold_load",
      status: "proposed",
      triggers: ["sleep_poor", "pain_severe", "red_flag:numb_weak_limb"],
      joint_states: [{
        area: "knee",
        state: "held",
        persistent: true,
        severity: 8,
        hold_outcome: "urgent",
      }],
      severity: 9,
      answer: "free text",
    }),
    today,
  );
  assertEquals(card, {
    localDate: today,
    band: "amber",
    kind: "hold_load",
    status: "proposed",
    available: true,
    unavailableReason: null,
    safetyRoute: null,
    confidence: "medium",
    jointStates: [{ area: "knee", state: "held", persistent: true }],
  });
});

Deno.test("the parser refuses a payload that is not exactly the card", () => {
  const bad: [string, unknown][] = [
    ["not an object", "x"],
    ["an array", []],
    ["another schema version", payload({ schema_version: "1.1" })],
    ["another day", payload({ local_date: "2026-10-23" })],
    ["an unknown band", payload({ band: "blue" })],
    ["an unknown kind", payload({ kind: "deload", status: "proposed" })],
    ["an unknown status", payload({ status: "applied" })],
    ["a kind with no status", payload({ kind: "hold_load" })],
    ["a status with no kind", payload({ status: "proposed" })],
    [
      "a route with a training change",
      payload({
        kind: "hold_load",
        status: "proposed",
        safety_route: "urgent",
      }),
    ],
    ["an unknown route", payload({ safety_route: "ambulance" })],
    ["open with a reason", payload({ unavailable_reason: "rest_day" })],
    ["closed with no reason", payload({ available: false })],
    ["an unknown reason", payload({ available: false, unavailable_reason: "holiday" })],
    ["a mistyped availability", payload({ available: "yes" })],
    ["an unknown confidence", payload({ confidence: "certain" })],
    ["joint states that are not a list", payload({ joint_states: {} })],
    [
      "an unknown area",
      payload({ joint_states: [{ area: "hip", state: "held", persistent: false }] }),
    ],
    [
      "an unknown joint state",
      payload({
        joint_states: [{ area: "knee", state: "healed", persistent: false }],
      }),
    ],
    [
      "a joint state with no persistence",
      payload({ joint_states: [{ area: "knee", state: "held" }] }),
    ],
    [
      "a repeated area",
      payload({
        joint_states: [
          { area: "knee", state: "held", persistent: false },
          { area: "knee", state: "limited", persistent: false },
        ],
      }),
    ],
  ];
  for (const [name, value] of bad) assertEquals(parseReadinessContext(value, today), null, name);
  // Null values the reader may send are fine.
  assert(parseReadinessContext(payload({ confidence: null }), today) !== null);
});

Deno.test("each state of the card renders its own facts and its own rules", async () => {
  const green = await rendered(payload());
  assertEquals(green.trace, { readiness: "ok" });
  assertStringIncludes(green.text, "Today's readiness card (2026-10-24)");
  assertStringIncludes(green.text, "Readiness: green");
  assertStringIncludes(green.text, "Adjustment: none");
  assertStringIncludes(green.text, "never contradict the card");
  assertStringIncludes(green.text, "you explain it and never apply, accept, decline or change it");
  assertStringIncludes(green.text, "a proposal the athlete approves");
  assert(!green.text.includes("Safety route"));
  assert(!green.text.includes("Held"));
  assert(!green.text.includes("Limited"));

  const proposed = await rendered(
    payload({ band: "amber", kind: "reduce_sets", status: "proposed" }),
  );
  assertStringIncludes(proposed.text, "Readiness: amber");
  assertStringIncludes(proposed.text, "Adjustment offered: fewer sets today");
  assertStringIncludes(proposed.text, "has not answered yet; do not answer it for them");

  const accepted = await rendered(payload({
    band: "amber",
    kind: "swap_to_easy_cardio",
    status: "accepted",
  }));
  assertStringIncludes(
    accepted.text,
    "accepted by the athlete: swap today's lifting for easy cardio",
  );

  const declined = await rendered(
    payload({ band: "amber", kind: "hold_load", status: "declined" }),
  );
  assertStringIncludes(declined.text, "declined it, so today's session stays as planned");

  const closed = await rendered(
    payload({ available: false, unavailable_reason: "session_started" }),
  );
  assertStringIncludes(closed.text, "The card is closed: the session has already started.");

  const noReading = await rendered(payload({ band: "unknown", confidence: null }));
  assertStringIncludes(noReading.text, "Readiness: no reading yet");
  assert(!noReading.text.includes("confidence"));
  assertStringIncludes(green.text, "confidence in the reading: medium");
});

Deno.test("every band, kind, status, reason and route renders, with no figure but the date", async () => {
  const cases: Record<string, unknown>[] = [];
  for (const band of readinessBands) cases.push(payload({ band }));
  for (const kind of adjustmentKinds) {
    for (const status of ["proposed", "accepted", "declined"]) {
      cases.push(payload({ band: "amber", kind, status }));
    }
  }
  for (const reason of unavailableReasons) {
    cases.push(payload({ available: false, unavailable_reason: reason }));
  }
  for (const route of safetyRoutes) cases.push(payload({ band: "red", safety_route: route }));
  for (const area of contextJointAreas) {
    for (const state of contextJointStates) {
      for (const persistent of [false, true]) {
        cases.push(payload({ joint_states: [{ area, state, persistent }] }));
      }
    }
  }
  for (const data of cases) {
    const result = await rendered(data);
    assertEquals(result.trace, { readiness: "ok" }, JSON.stringify(data));
    assertEquals(result.outcome.outcome, "rendered");
    // The date is the only figure, and it is the one record.
    assertEquals(result.text.replace(today, "").match(/\d/g), null, JSON.stringify(data));
    assertEquals(result.records.length, 1);
    assertStringIncludes(result.records[0], today);
  }
});

Deno.test("a safety route stops the training talk and points to the referral, by strictness", async () => {
  for (const route of safetyRoutes) {
    const result = await rendered(payload({ band: "red", safety_route: route }));
    assertStringIncludes(result.text, `Safety route: ${route}.`);
    assertStringIncludes(result.text, "The card shows a referral and no training change.");
    assertStringIncludes(
      result.text,
      "suggest no training, loads, exercises or cardio, and never say it is fine to train",
    );
    assertStringIncludes(result.text, "Point to the referral on the card; never diagnose");
    assert(!result.text.includes("Adjustment"), route);
  }
  const urgent = await rendered(payload({ band: "red", safety_route: "urgent" }));
  assertStringIncludes(urgent.text, "get medical care now");
  const today_ = await rendered(payload({ band: "red", safety_route: "clinician_today" }));
  assertStringIncludes(today_.text, "seen by a doctor or physio today");
  assert(!today_.text.includes("medical care now"));
  const soon = await rendered(payload({ band: "red", safety_route: "clinician" }));
  assertStringIncludes(soon.text, "have it checked by a doctor or physio");
});

Deno.test("held, limited and watched areas each get their rule, and lasting ones the referral", async () => {
  const result = await rendered(payload({
    band: "amber",
    kind: "joint_adjust",
    status: "proposed",
    joint_states: [
      { area: "knee", state: "held", persistent: true },
      { area: "other", state: "held", persistent: false },
      { area: "back", state: "limited", persistent: false },
      { area: "shoulder", state: "watch", persistent: true },
    ],
  }));
  assertStringIncludes(
    result.text,
    "Held (on hold until the athlete has had it checked): knee, pain reported elsewhere.",
  );
  assertStringIncludes(
    result.text,
    "Suggest no exercise, load, stretch, range or test that works that area",
  );
  assertStringIncludes(
    result.text,
    "never lift the hold yourself, only the athlete's own clearance does",
  );
  assertStringIncludes(result.text, "Limited: lower back.");
  assertStringIncludes(result.text, "do not push load or range there");
  assertStringIncludes(result.text, "Watch: shoulder.");
  assertStringIncludes(result.text, "knee, shoulder: this has lasted two weeks or more.");
  assertStringIncludes(result.text, "Say it should be seen by a physio or doctor.");
  assertStringIncludes(result.text, "swap or shorten the exercises that load a sore joint");

  const limitedOnly = await rendered(payload({
    joint_states: [{ area: "back", state: "limited", persistent: false }],
  }));
  assert(!limitedOnly.text.includes("Held"));
  assert(!limitedOnly.text.includes("lasted"));
});

Deno.test("no red-flag code, trigger or pain severity reaches the text, whatever the payload carries", async () => {
  const everything = payload({
    band: "red",
    safety_route: "clinician_today",
    triggers: [
      "pain_severe",
      "pain_moderate",
      "pain_mild",
      "recovery_low",
      "sleep_poor",
      ...redFlagCodes.map((code) => `red_flag:${code}`),
    ],
    joint_states: contextJointAreas.map((area) => ({
      area,
      state: "held",
      persistent: true,
      severity: 9,
      pain_severity: 9,
      hold_outcome: "urgent",
      hold_codes: [...redFlagCodes],
      hold_severe: true,
    })),
    pain_severity: 9,
    severity: 9,
    red_flags: [...redFlagCodes],
    explanation: "Your pain of 9 needs a look",
  });
  const result = await rendered(everything);
  assertEquals(result.trace, { readiness: "ok" });
  const lower = result.text.toLowerCase();
  for (
    const forbidden of [
      "red_flag",
      "red flag",
      "severity",
      "pain_severe",
      "pain_moderate",
      "pain_mild",
      "recovery_low",
      "sleep_poor",
      "trigger",
      "your pain of",
      ...redFlagCodes,
    ]
  ) assert(!lower.includes(forbidden), forbidden);
  assertEquals(result.text.replace(today, "").match(/\d/g), null);
});

Deno.test("the reader is called for the athlete and the day, and its error leaves the card unavailable", async () => {
  const calls: [string, Record<string, unknown>][] = [];
  const recording: ServiceRpc = (name, params) => {
    calls.push([name, params]);
    return Promise.resolve({ data: payload(), error: null });
  };
  await renderCoachContext(
    [createReadinessContributor(readinessSourceFromRpc(recording))],
    turn,
  );
  assertEquals(calls, [[readinessContextRpc, { p_user_id: "user-1", p_local_date: today }]]);

  const failing: ServiceRpc = () =>
    Promise.resolve({ data: null, error: { message: "only the athlete's own today can be read" } });
  const result = await renderCoachContext(
    [createReadinessContributor(readinessSourceFromRpc(failing))],
    turn,
  );
  assertEquals(result.traces?.readiness, { readiness: "unavailable" });
});

Deno.test("a card that cannot be read says so and never reads as all clear", async () => {
  const unreadable: [string, () => Promise<unknown>, string][] = [
    ["a payload that is not the card", () => Promise.resolve({ band: "green" }), "unavailable"],
    [
      "another day's card",
      () => Promise.resolve(payload({ local_date: "2026-10-23" })),
      "unavailable",
    ],
    ["a null payload", () => Promise.resolve(null), "unavailable"],
    ["a rejected read", () => Promise.reject(new Error("down")), "failed"],
    ["a read that throws at once", () => {
      throw new Error("sync");
    }, "failed"],
  ];
  for (const [name, read, status] of unreadable) {
    const result = await renderCoachContext(
      [createReadinessContributor(async () => {
        const data = await read();
        return parseReadinessContext(data, today);
      })],
      turn,
    );
    assertEquals(result.outcomes[0].outcome, "rendered", name);
    assertEquals(result.traces?.readiness, { readiness: status }, name);
    const text = result.texts.readiness;
    assertStringIncludes(text, "could not be read just now", name);
    assertStringIncludes(
      text,
      "Do not say what the card shows, or that nothing is wrong with a joint",
      name,
    );
    assertStringIncludes(text, "Anything the athlete tells you about pain still counts", name);
    assert(!text.includes("Readiness:"), name);
    assertEquals((result.records?.readiness ?? []).length, 0, name);
  }
});

Deno.test("a read that never answers cannot hold the turn: it times out on its own short deadline", async () => {
  const started = performance.now();
  const hung = await renderCoachContext(
    [createReadinessContributor(() => new Promise(() => {}), 50)],
    turn,
  );
  assert(performance.now() - started < 1_000, "the card's deadline is its own");
  assertEquals(hung.outcomes[0].outcome, "rendered");
  assertEquals(hung.traces?.readiness, { readiness: "timeout" });
  assertStringIncludes(hung.texts.readiness, "could not be read just now");

  // A late answer after the deadline changes nothing.
  const late = await renderCoachContext(
    [createReadinessContributor(
      () => new Promise((resolve) => setTimeout(() => resolve(null), 200)),
      20,
    )],
    turn,
  );
  assertEquals(late.traces?.readiness, { readiness: "timeout" });
});

Deno.test("the real deadline is shorter than the host's, so the card times out before the host does", async () => {
  assert(readinessDeadlineMs < 4_000);
  const started = performance.now();
  const hung = await renderCoachContext(
    [createReadinessContributor(() => new Promise(() => {}))],
    turn,
  );
  const elapsed = performance.now() - started;
  assertEquals(hung.traces?.readiness, { readiness: "timeout" });
  assert(elapsed >= readinessDeadlineMs - 50 && elapsed < 2_500, `${elapsed} ms`);
});

Deno.test("the largest card fits the budget with nothing cut, and the budget is small against the turn's", async () => {
  const worst = await rendered(payload({
    band: "amber",
    kind: "swap_to_easy_cardio",
    status: "declined",
    available: false,
    unavailable_reason: "coach_adjusted",
    safety_route: null,
    joint_states: contextJointAreas.map((area) => ({ area, state: "held", persistent: true })),
  }));
  const worstRoute = await rendered(payload({
    band: "red",
    safety_route: "clinician_today",
    available: false,
    unavailable_reason: "coach_adjusted",
    joint_states: [
      { area: "knee", state: "held", persistent: true },
      { area: "back", state: "limited", persistent: true },
      { area: "shoulder", state: "watch", persistent: true },
      { area: "other", state: "held", persistent: true },
    ],
  }));
  for (const result of [worst, worstRoute]) {
    assertEquals(result.outcome.clipped, false);
    assert(!result.text.includes("The rest of this block was cut"));
    assert(result.text.length <= readinessBudgetChars * 0.8, `${result.text.length} chars`);
  }
  assert(readinessBudgetChars <= 2_500);
});

Deno.test("the contributor is registered right after the plan, volatile, on both routes", () => {
  const ids = coachContextContributors.map((item) => item.id);
  assertEquals(ids.indexOf("readiness"), ids.indexOf("training_plan") + 1);
  assertEquals(
    coachContextContributors.find((item) => item.id === "readiness")?.slot,
    "volatile",
  );
  for (const gateway of [true, false]) {
    assert(
      coachContextContributorsFor(gateway).some((item) => item.id === "readiness"),
      `${gateway}`,
    );
  }
});

// The reader runs in SQL; this keeps what it returns from growing unseen. A new key in it is a
// new thing the Coach could be shown, so the list below has to be read and changed on purpose.
Deno.test("the migration's reader returns exactly the keys the context parser knows", async () => {
  const sql = await Deno.readTextFile(
    new URL("../../../../migrations/20261024060025_pain_checks.sql", import.meta.url),
  );
  const start = sql.indexOf("create function public.get_readiness_context_v1");
  const end = sql.indexOf("revoke all on function public.get_readiness_context_v1");
  assert(start > 0 && end > start, "reader found");
  const body = sql.slice(start, end);
  const returned = body.slice(body.indexOf("return jsonb_build_object("));
  const keys = [...returned.matchAll(/^ {4}'([a-z_]+)',/gm)].map((match) => match[1]);
  assertEquals(keys, [
    "schema_version",
    "local_date",
    "band",
    "kind",
    "status",
    "available",
    "unavailable_reason",
    "safety_route",
    "triggers",
    "confidence",
    "joint_states",
    "rules_version",
  ]);
  // The joint projection carries the area, the state and persistence only, and no red-flag trigger.
  assertStringIncludes(
    returned,
    "jsonb_build_object('area', s -> 'area',\n        'state', s -> 'state', 'persistent', s -> 'persistent')",
  );
  assertStringIncludes(returned, "t.value not like 'red_flag:%'");
  assertStringIncludes(body, "p_local_date is distinct from private.local_date_for(p_user_id)");
  assertStringIncludes(
    sql,
    "grant execute on function public.get_readiness_context_v1(uuid, date) to service_role;",
  );
  assertStringIncludes(
    sql,
    "revoke all on function public.get_readiness_context_v1(uuid, date) from public, anon, authenticated;",
  );
});

Deno.test("a card from a pain report or a hold alone does not claim a check-in, sleep or recovery behind it", async () => {
  const cards = [
    // Only a hold on a joint: no reading, nothing offered.
    payload({
      band: "unknown",
      confidence: null,
      joint_states: [{ area: "knee", state: "held", persistent: false }],
    }),
    // Only a pain report that routed out.
    payload({
      band: "red",
      confidence: null,
      safety_route: "clinician_today",
      joint_states: [{ area: "back", state: "held", persistent: false }],
    }),
    // A limited joint with an adjustment and no confidence.
    payload({
      band: "unknown",
      confidence: null,
      kind: "joint_adjust",
      status: "proposed",
      joint_states: [{ area: "shoulder", state: "limited", persistent: true }],
    }),
  ];
  for (const data of cards) {
    const result = await rendered(data);
    assertEquals(result.trace, { readiness: "ok" });
    assertStringIncludes(
      result.text,
      "Today's readiness card (2026-10-24), as Tracend worked it out.",
    );
    assert(!/check-in|sleep|recover|confidence/i.test(result.text), result.text);
  }
});
