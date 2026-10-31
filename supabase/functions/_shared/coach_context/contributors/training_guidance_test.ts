import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import suggestedFixture from "../../../../../test/contract/fixtures/training_guidance_v1_2.json" with {
  type: "json",
};
import coachPendingFixture from "../../../../../test/contract/fixtures/training_guidance_v1_2_coach_pending.json" with {
  type: "json",
};
import runningFixture from "../../../../../test/contract/fixtures/training_guidance_v1_2_running.json" with {
  type: "json",
};
import { deloadReasons, deloadSuppressions } from "../../training/guidance/payload.ts";
import { parseReadinessContext } from "../../training/readiness/context_payload.ts";
import { createReadinessContributor } from "./readiness.ts";
import { coachContextContributors, coachContextContributorsFor } from "../registry.ts";
import { renderCoachContext } from "../host.ts";
import {
  createTrainingGuidanceContributor,
  trainingGuidanceBudgetChars,
  trainingGuidanceDeadlineMs,
  trainingGuidanceRpc,
  trainingGuidanceSourceFromRpc,
} from "./training_guidance.ts";
import type { ServiceRpc } from "../service_source.ts";

const today = "2026-10-24";
const id = "11111111-2222-4333-8444-555555555555";
const turn = { userId: "user-1", question: "Do I need a deload?", localDate: today };

type Json = Record<string, unknown>;

const cardio = (changes: Json = {}): Json => ({
  target_min: 150,
  stretch_max: null,
  done_min: 85,
  intensity_known: false,
  vigorous_allowed: false,
  vigorous_sessions_max: 2,
  vigorous_counts_as: 2,
  lift_separation_hours: 3,
  easy_hr_reserve_max: 60,
  window_from: "2026-10-18",
  window_to: today,
  ...changes,
});

const deload = (changes: Json = {}): Json => ({
  status: "not_due",
  reasons: [],
  last_ended_on: null,
  weeks_since: 3,
  proposal_id: null,
  proposal_origin: null,
  ends_on: null,
  suppressed_by: null,
  ...changes,
});

/** A payload as get_training_guidance_for_v1 returns it (1.2), with changes. */
function payload(changes: Json = {}): Json {
  return {
    schema_version: "1.2",
    local_date: today,
    safety_route: null,
    deload: deload(),
    cardio_withheld: null,
    cardio_week: cardio(),
    ...changes,
  };
}

const rpcReturning = (data: unknown): ServiceRpc => () => Promise.resolve({ data, error: null });

async function rendered(data: unknown, deadlineMs?: number) {
  const result = await renderCoachContext(
    [createTrainingGuidanceContributor(
      trainingGuidanceSourceFromRpc(rpcReturning(data)),
      deadlineMs,
    )],
    turn,
  );
  return {
    text: result.texts.training_guidance ?? "",
    trace: result.traces?.training_guidance,
    outcome: result.outcomes[0],
    records: result.records?.training_guidance ?? [],
  };
}

Deno.test("the reader is called for the athlete and the day, and an error leaves the guidance unavailable", async () => {
  const calls: [string, Record<string, unknown>][] = [];
  const recording: ServiceRpc = (name, params) => {
    calls.push([name, params]);
    return Promise.resolve({ data: payload(), error: null });
  };
  const ok = await renderCoachContext(
    [createTrainingGuidanceContributor(trainingGuidanceSourceFromRpc(recording))],
    turn,
  );
  assertEquals(calls, [[trainingGuidanceRpc, { p_user_id: "user-1", p_local_date: today }]]);
  assertEquals(ok.traces?.training_guidance, { training_guidance: "ok" });

  const failing: ServiceRpc = () =>
    Promise.resolve({ data: null, error: { message: "only the athlete's own today can be read" } });
  const result = await renderCoachContext(
    [createTrainingGuidanceContributor(trainingGuidanceSourceFromRpc(failing))],
    turn,
  );
  assertEquals(result.traces?.training_guidance, { training_guidance: "unavailable" });
});

Deno.test("a suggestion tells the reasons in words, leaves the decision to the athlete and states no count", async () => {
  const result = await rendered(suggestedFixture);
  assertEquals(result.trace, { training_guidance: "ok" });
  assertStringIncludes(result.text, "Training guidance for 2026-10-24");
  assertStringIncludes(result.text, "Tracend's rules suggest one could help, because");
  assertStringIncludes(result.text, "several lifts are heading down");
  assertStringIncludes(result.text, "recent check-ins read amber or red");
  assertStringIncludes(result.text, "It is only a suggestion: the athlete sees it on Train");
  assertStringIncludes(result.text, "You never start one.");
  assertStringIncludes(result.text, "never start, accept, decline or change a lighter week");
  assertStringIncludes(result.text, "a widely used coaching practice, not a proven requirement");
  // 85 of 150 minutes, the upper figure for the goal, and hard cardio open.
  assertStringIncludes(result.text, "85 of 150 minutes of moderate cardio (up to 300 for");
  assertStringIncludes(result.text, "every counted minute is read as moderate");
  assertStringIncludes(result.text, "Hard cardio is open today, up to 2 sessions a week");
  assertStringIncludes(result.text, "at least 3 hours from lifting");
  assert(!result.text.includes("weeks_since"));
});

Deno.test("a pending and a running week say who made it, whose answer it waits for and how to undo", async () => {
  const pending = await rendered(coachPendingFixture);
  assertStringIncludes(pending.text, "a proposal is waiting for the athlete's answer");
  assertStringIncludes(pending.text, "It came from a Coach proposal.");
  assertStringIncludes(pending.text, "Do not answer it for them");
  assert(!pending.text.includes("suggest one could help"));

  const running = await rendered(runningFixture);
  assertStringIncludes(running.text, "Lighter week (deload): running until");
  assertStringIncludes(running.text, "The athlete approved it.");
  assertStringIncludes(running.text, "half the sets, loads held and effort 7 or lower");
  assertStringIncludes(running.text, "the athlete can undo it on Train");

  const tracend = await rendered(payload({
    deload: deload({
      status: "pending",
      proposal_id: id,
      proposal_origin: "tracend",
    }),
  }));
  assertStringIncludes(tracend.text, "Tracend's rules suggested it.");
  // No proposal id reaches the model.
  assert(!tracend.text.includes(id));
  assert(!running.text.includes("proposal_id"));
});

Deno.test("each reason a lighter week is not offered has its own words, and an end date is a record", async () => {
  for (const suppressed of deloadSuppressions) {
    if (suppressed === "safety_route" || suppressed === "screening") continue;
    const result = await rendered(payload({ deload: deload({ suppressed_by: suppressed }) }));
    assertStringIncludes(result.text, "none is offered, because", suppressed);
    assertStringIncludes(result.text, "can still ask Coach for one", suppressed);
  }
  const none = await rendered(payload());
  assertStringIncludes(none.text, "none is due; nothing in the athlete's logs points to one");
  const ended = await rendered(payload({
    deload: deload({ suppressed_by: "recent_deload", last_ended_on: "2026-10-20" }),
  }));
  assertStringIncludes(ended.text, "The last lighter week ended on 2026-10-20.");
  assert(ended.records.some((piece) => piece.includes("2026-10-20")));
});

Deno.test("the cardio week reads as it is: not countable, zero and the hard or easy day", async () => {
  const missing = await rendered(payload({ cardio_week: cardio({ done_min: null }) }));
  assertStringIncludes(missing.text, "not countable yet");
  assertStringIncludes(missing.text, "Do not state minutes done");
  assert(!missing.text.includes("0 of 150"));

  const zero = await rendered(payload({ cardio_week: cardio({ done_min: 0 }) }));
  assertStringIncludes(zero.text, "0 of 150 minutes");
  assertStringIncludes(zero.text, "do not conclude they did no cardio");

  const easy = await rendered(payload());
  assertStringIncludes(easy.text, "Today is an easy-cardio day: hard cardio is not open");
  assertStringIncludes(easy.text, "below 60% of heart-rate reserve");
  assert(!easy.text.includes("Hard cardio is open"));

  const known = await rendered(payload({ cardio_week: cardio({ intensity_known: true }) }));
  assert(!known.text.includes("every counted minute is read as moderate"));

  // The 1.0 payload has no cardio: no cardio line, and nothing claims it is unreadable.
  const old = await rendered({
    schema_version: "1.0",
    local_date: today,
    safety_route: null,
    deload: deload(),
  });
  assert(!old.text.includes("Cardio"));
  assertEquals(old.trace, { training_guidance: "ok" });
});

Deno.test("a safety route or a health check that asks for a professional gives no training line at all", async () => {
  const route = await rendered(payload({
    safety_route: "clinician_today",
    deload: deload({ status: "running", proposal_id: id, ends_on: "2026-10-27" }),
    cardio_withheld: "safety_route",
    cardio_week: null,
  }));
  assertStringIncludes(route.text, "A safety route applies today, so training is not the topic");
  assertStringIncludes(route.text, "never say it is fine to train");
  assertStringIncludes(route.text, "Point to the referral the app shows on Today");
  for (const forbidden of ["Lighter week", "Cardio", "Hard cardio", "Rules:", "2026-10-27"]) {
    assert(!route.text.includes(forbidden), forbidden);
  }

  const screening = await rendered(payload({
    cardio_withheld: "screening",
    cardio_week: null,
    deload: deload({ suppressed_by: "screening" }),
  }));
  assertStringIncludes(screening.text, "see a professional first");
  for (const forbidden of ["Lighter week", "Cardio this week", "Hard cardio", "Today is an easy"]) {
    assert(!screening.text.includes(forbidden), forbidden);
  }
  // Only the date is a record: no figure is given on such a day.
  assertEquals(route.records.length, 1);
  assertStringIncludes(route.records[0], "2026-10-24");
});

Deno.test("guidance that cannot be read says so and never reads as nothing due", async () => {
  const unreadable: [string, () => Promise<unknown>, string][] = [
    ["a payload that is not the guidance", () => Promise.resolve({ deload: {} }), "unavailable"],
    [
      "another day's guidance",
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
      [createTrainingGuidanceContributor(trainingGuidanceSourceFromRpc(async () => ({
        data: await read(),
        error: null,
      })))],
      turn,
    );
    assertEquals(result.outcomes[0].outcome, "rendered", name);
    assertEquals(result.traces?.training_guidance, { training_guidance: status }, name);
    const text = result.texts.training_guidance;
    assertStringIncludes(text, "could not be read just now", name);
    assertStringIncludes(text, "Do not say a lighter week is due, is not due or has started", name);
    assertStringIncludes(text, "do not state cardio minutes", name);
    assertStringIncludes(text, "Never start a lighter week or change a plan yourself", name);
    assert(!text.includes("Cardio this week"), name);
    assertEquals((result.records?.training_guidance ?? []).length, 0, name);
  }
});

Deno.test("a read that never answers cannot hold the turn: it times out on its own short deadline", async () => {
  const started = performance.now();
  const hung = await renderCoachContext(
    [createTrainingGuidanceContributor(() => new Promise(() => {}), 50)],
    turn,
  );
  assert(performance.now() - started < 1_000, "the guidance's deadline is its own");
  assertEquals(hung.outcomes[0].outcome, "rendered");
  assertEquals(hung.traces?.training_guidance, { training_guidance: "timeout" });
  assertStringIncludes(hung.texts.training_guidance, "could not be read just now");
  const late = await renderCoachContext(
    [createTrainingGuidanceContributor(
      () => new Promise((resolve) => setTimeout(() => resolve(null), 200)),
      20,
    )],
    turn,
  );
  assertEquals(late.traces?.training_guidance, { training_guidance: "timeout" });
});

Deno.test("a slow guidance costs the readiness card nothing: each has its own deadline", async () => {
  assert(trainingGuidanceDeadlineMs < 4_000);
  const card = createReadinessContributor(() =>
    Promise.resolve(parseReadinessContext({
      schema_version: "1.0",
      local_date: today,
      band: "green",
      kind: "none",
      status: "none",
      available: true,
      unavailable_reason: null,
      safety_route: null,
      confidence: "medium",
      joint_states: [],
    }, today))
  );
  const slow = createTrainingGuidanceContributor(() => new Promise(() => {}), 100);
  const result = await renderCoachContext([card, slow], turn);
  assertEquals(result.traces?.readiness, { readiness: "ok" });
  assertEquals(result.traces?.training_guidance, { training_guidance: "timeout" });
  assertStringIncludes(result.texts.readiness, "Readiness: green");
  assertStringIncludes(result.texts.training_guidance, "could not be read just now");
});

Deno.test("every reason and suppression renders, with figures only as records", async () => {
  const cases: Json[] = [payload()];
  for (const reason of deloadReasons) {
    cases.push(payload({ deload: deload({ status: "suggested", reasons: [reason] }) }));
  }
  cases.push(payload({ deload: deload({ status: "suggested", reasons: [...deloadReasons] }) }));
  for (const done of [null, 0, 85, 150, 400]) {
    for (const allowed of [false, true]) {
      cases.push(payload({ cardio_week: cardio({ done_min: done, vigorous_allowed: allowed }) }));
    }
  }
  for (const data of cases) {
    const result = await rendered(data);
    assertEquals(result.trace, { training_guidance: "ok" }, JSON.stringify(data));
    assertEquals(result.outcome.outcome, "rendered");
    assertEquals(result.outcome.clipped, false);
    // Every number in the text is marked as a record: the date, the minutes, the rules' own figures.
    const unmarked = result.text.replace(/\d{4}-\d{2}-\d{2}/g, "").match(/\d+/g) ?? [];
    for (const digits of unmarked) {
      assert(
        result.records.some((piece) => new RegExp(`(^|\\D)${digits}(\\D|$)`).test(piece)),
        `${digits} is not a record in ${JSON.stringify(data)}`,
      );
    }
  }
});

Deno.test("no diagnosis word, id or heart-rate value reaches the text, whatever the payload carries", async () => {
  const everything = payload({
    deload: deload({
      status: "pending",
      proposal_id: id,
      proposal_origin: "coach",
      reasons: [],
    }),
    resting_hr: 48,
    hrv: 31,
    pain_severity: 9,
    red_flags: ["chest_pain"],
  });
  const result = await rendered(everything);
  const lower = result.text.toLowerCase();
  for (
    const forbidden of [
      id,
      "hrv",
      "resting",
      "bpm",
      "severity",
      "red_flag",
      "diagnos",
      "overtrain",
      "injur",
      "syndrome",
    ]
  ) assert(!lower.includes(forbidden), forbidden);
});

Deno.test("the largest guidance fits the budget with nothing cut", async () => {
  const worst = await rendered(payload({
    deload: deload({
      status: "suggested",
      reasons: [...deloadReasons],
      last_ended_on: "2026-09-01",
    }),
    cardio_week: cardio({
      stretch_max: 300,
      done_min: 0,
      vigorous_allowed: true,
    }),
  }));
  const worstNotDue = await rendered(payload({
    deload: deload({ suppressed_by: "not_enough_training", last_ended_on: "2026-09-01" }),
    cardio_week: cardio({ stretch_max: 300, done_min: 0 }),
  }));
  const worstRunning = await rendered(payload({
    deload: deload({
      status: "running",
      proposal_id: id,
      proposal_origin: "tracend",
      ends_on: "2026-10-27",
    }),
    cardio_week: cardio({ stretch_max: 300, done_min: 0 }),
  }));
  for (const result of [worst, worstNotDue, worstRunning]) {
    assertEquals(result.outcome.clipped, false);
    assert(!result.text.includes("The rest of this block was cut"));
    assert(result.text.length <= trainingGuidanceBudgetChars * 0.8, `${result.text.length} chars`);
  }
  assert(trainingGuidanceBudgetChars <= 2_500);
});

Deno.test("the contributor is registered right after the readiness card, volatile, on both routes", () => {
  const ids = coachContextContributors.map((item) => item.id);
  assertEquals(ids.indexOf("training_guidance"), ids.indexOf("readiness") + 1);
  assertEquals(
    coachContextContributors.find((item) => item.id === "training_guidance")?.slot,
    "volatile",
  );
  for (const gateway of [true, false]) {
    assert(
      coachContextContributorsFor(gateway).some((item) => item.id === "training_guidance"),
      `${gateway}`,
    );
  }
});

// The reader runs in SQL: it answers only for the athlete's own today and only to the service role.
Deno.test("the migration's reader is the service role's, for the athlete's own today only", async () => {
  const sql = await Deno.readTextFile(
    new URL("../../../../migrations/20261024060125_deloads.sql", import.meta.url),
  );
  const start = sql.indexOf("create function public.get_training_guidance_for_v1");
  const end = sql.indexOf("grant execute on function public.get_training_guidance_for_v1");
  assert(start > 0 && end > start, "reader found");
  const body = sql.slice(start, end);
  assertStringIncludes(body, "p_local_date is distinct from private.local_date_for(p_user_id)");
  assertStringIncludes(
    body,
    "revoke all on function public.get_training_guidance_for_v1(uuid, date) from public, anon, authenticated;",
  );
  assertStringIncludes(
    sql,
    "grant execute on function public.get_training_guidance_for_v1(uuid, date) to service_role;",
  );
});
