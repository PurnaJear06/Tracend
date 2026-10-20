import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import {
  coachLookupCatalogue,
  coachLookupNames,
  dataRequestsJsonSchema,
  dayNumber,
  describeLookupCatalogue,
  maxLookupRangeDays,
  maxLookupRounds,
  maxRequestsPerRound,
  maxRoundResultChars,
  maxScheduleAheadDays,
  validateDataRequests,
} from "./catalogue.ts";

const today = "2026-10-17";
const ok = (raw: unknown) => {
  const checked = validateDataRequests(raw, today);
  if (!checked.ok) throw new Error(checked.reason);
  return checked.requests;
};
const refused = (raw: unknown) => {
  const checked = validateDataRequests(raw, today);
  if (checked.ok) throw new Error("expected a refusal");
  return checked.reason;
};

Deno.test("the catalogue is a closed list: eleven lookups, each with its own RPC", () => {
  assertEquals(coachLookupNames.length, 11);
  assertEquals(new Set(coachLookupCatalogue.map((spec) => spec.rpc)).size, 11);
  for (const spec of coachLookupCatalogue) {
    assertEquals(spec.rpc, `coach_lookup_${spec.name}_v1`);
  }
  assertEquals(maxLookupRounds, 2);
  assertEquals(maxRequestsPerRound, 8);
  assertEquals(maxRoundResultChars, 24_000);
  assertEquals(maxLookupRangeDays, 400);
});

Deno.test("a valid request passes unchanged; a range after the coaching date is cut to it", () => {
  assertEquals(ok([{ lookup: "body", from: "2026-08-01", to: "2026-10-17" }]), [
    { lookup: "body", from: "2026-08-01", to: "2026-10-17", filter: null },
  ]);
  assertEquals(ok([{ lookup: "check_ins", from: "2026-10-01", to: "2026-12-31" }])[0].to, today);
});

Deno.test("unknown lookups and unknown keys are refused", () => {
  assertStringIncludes(
    refused([{ lookup: "everything", from: "2026-08-01", to: today }]),
    "unknown lookup",
  );
  assertStringIncludes(
    refused([{ lookup: "body", from: "2026-08-01", to: today, user_id: "someone-else" }]),
    "a key other than",
  );
  assertStringIncludes(refused("body"), "non-empty list");
  assertStringIncludes(refused([]), "non-empty list");
  assertStringIncludes(refused([null]), "must be an object");
});

Deno.test("the physique lookup is not offered: summaries of photos reach the Coach provider only under an accepted notice", () => {
  assertEquals(coachLookupNames.includes("physique" as never), false);
  assertStringIncludes(
    refused([{ lookup: "physique", from: "2026-08-01", to: today }]),
    "unknown lookup",
  );
});

Deno.test("an oversized range is refused: 400 days pass, 401 do not", () => {
  const from400 = new Date((dayNumber(today)! - 399) * 86_400_000).toISOString().slice(0, 10);
  const from401 = new Date((dayNumber(today)! - 400) * 86_400_000).toISOString().slice(0, 10);
  assertEquals(ok([{ lookup: "workouts", from: from400, to: today }]).length, 1);
  assertStringIncludes(
    refused([{ lookup: "workouts", from: from401, to: today }]),
    "at most 400 days",
  );
});

Deno.test("bad dates, a reversed range and a range wholly in the future are refused", () => {
  assertStringIncludes(refused([{ lookup: "body", from: "2026-13-01", to: today }]), "YYYY-MM-DD");
  assertStringIncludes(refused([{ lookup: "body", from: "last month", to: today }]), "YYYY-MM-DD");
  assertStringIncludes(refused([{ lookup: "body", from: "2026-02-30", to: today }]), "YYYY-MM-DD");
  assertStringIncludes(
    refused([{ lookup: "body", from: "2026-10-10", to: "2026-10-01" }]),
    "after to",
  );
  assertStringIncludes(
    refused([{ lookup: "body", from: "2026-11-01", to: "2026-11-30" }]),
    "in the future",
  );
});

Deno.test("more than eight requests in a round are refused; eight pass; repeats are merged", () => {
  const request = (lookup: string, filter = "") => ({
    lookup,
    from: "2026-10-01",
    to: today,
    filter,
  });
  const eight = [
    request("body"),
    request("recovery"),
    request("check_ins"),
    request("goals"),
    request("weekly_reviews"),
    request("workouts"),
    request("meals"),
    request("plan_history", "proposals"),
  ];
  assertEquals(ok(eight).length, 8);
  assertStringIncludes(refused([...eight, request("health_history")]), "at most 8 requests");
  assertEquals(ok([request("body"), request("body")]).length, 1);
});

Deno.test("the new kinds of record are filters on existing lookups, so the lookup names are unchanged", () => {
  assertEquals(coachLookupNames.length, 11);
  const asked = (lookup: string, filter: string) =>
    ok([{ lookup, from: "2026-08-01", to: today, filter }])[0].filter;
  assertEquals(asked("plan_history", "proposals"), "proposals");
  assertEquals(asked("health_history", "workouts"), "workouts");
  assertEquals(asked("weekly_reviews", "decisions"), "decisions");
  // No lookup reaches ahead with them: only the schedule does.
  assertStringIncludes(
    refused([{
      lookup: "health_history",
      from: "2026-10-18",
      to: "2026-11-30",
      filter: "workouts",
    }]),
    "in the future",
  );
  const text = describeLookupCatalogue();
  assertStringIncludes(text, "with the filter proposals");
  assertStringIncludes(text, "with the filter workouts");
  assertStringIncludes(text, "with the filter decisions");
  assertStringIncludes(text, "session and exercise notes");
  assertStringIncludes(text, "Coach's own earlier replies");
  assertStringIncludes(text, "sleep and its stages");
});

Deno.test("filters: required for exercise_history, plain words only, dropped where unused", () => {
  const history = { lookup: "exercise_history", from: "2026-08-01", to: today };
  assertStringIncludes(refused([history]), "a filter is required");
  assertEquals(ok([{ ...history, filter: "bench press" }])[0].filter, "bench press");
  assertStringIncludes(refused([{ ...history, filter: "bench%'; drop table" }]), "plain words");
  assertStringIncludes(refused([{ ...history, filter: "x".repeat(61) }]), "plain words");
  assertEquals(
    ok([{ lookup: "body", from: "2026-08-01", to: today, filter: "anything" }])[0].filter,
    null,
  );
  assertEquals(
    ok([{ lookup: "meals", from: "2026-10-01", to: today, filter: "lunch" }])[0].filter,
    "lunch",
  );
});

Deno.test("the catalogue text names every lookup for the model", () => {
  const text = describeLookupCatalogue();
  for (const name of coachLookupNames) assertStringIncludes(text, `- ${name}:`);
  assertStringIncludes(text, "Filter (required)");
});

Deno.test("dayNumber accepts only real dates", () => {
  assertEquals(dayNumber("2026-10-17"), 20743);
  assertEquals(dayNumber("2026-02-29"), null);
  assertEquals(dayNumber("2026-1-1"), null);
  assertEquals(dayNumber(20260101), null);
});

Deno.test("past_messages needs words to search for and takes plain words only", () => {
  assertEquals(
    refused([{ lookup: "past_messages", from: "2026-09-01", to: today }]),
    'past_messages: a filter is required (the words to find, such as "knee pain"; any of them matches)',
  );
  assertEquals(
    ok([{ lookup: "past_messages", from: "2026-09-01", to: today, filter: "knee pain" }])[0].filter,
    "knee pain",
  );
  assertStringIncludes(
    refused([{ lookup: "past_messages", from: "2026-09-01", to: today, filter: "knee; drop" }]),
    "plain words",
  );
});

Deno.test("the schema's form: an empty filter is no filter, and a required filter still has to be written", () => {
  // The schema has no optional field and no null, so a lookup without a filter carries "".
  assertEquals(ok([{ lookup: "body", from: "2026-08-01", to: "2026-10-17", filter: "" }]), [
    { lookup: "body", from: "2026-08-01", to: "2026-10-17", filter: null },
  ]);
  assertEquals(
    ok([{ lookup: "meals", from: "2026-08-01", to: "2026-10-17", filter: "  " }])[0].filter,
    null,
  );
  assertStringIncludes(
    refused([{ lookup: "exercise_history", from: "2026-08-01", to: today, filter: "" }]),
    "a filter is required",
  );
  assertEquals(
    ok([{ lookup: "exercise_history", from: "2026-08-01", to: today, filter: "bench" }])[0].filter,
    "bench",
  );
});

Deno.test("the data_requests schema: every field required, no union, every lookup name", () => {
  const item = dataRequestsJsonSchema.items;
  assertEquals(item.required, ["lookup", "from", "to", "filter"]);
  assertEquals(Object.keys(item.properties), [...item.required]);
  assertEquals(item.properties.lookup.enum, [...coachLookupNames]);
  assertEquals(item.properties.filter, { type: "string" });
  assertEquals(JSON.stringify(dataRequestsJsonSchema).includes("anyOf"), false);
});

Deno.test("only the plan's schedule may look ahead: up to 90 days, with the filter schedule", () => {
  const ahead = (filter: string, to = "2026-11-30", from = "2026-10-18") =>
    validateDataRequests([{ lookup: "plan_history", from, to, filter }], today);
  assertEquals(maxScheduleAheadDays, 90);
  const checked = ahead("schedule");
  if (!checked.ok) throw new Error(checked.reason);
  assertEquals(checked.requests[0], {
    lookup: "plan_history",
    from: "2026-10-18",
    to: "2026-11-30",
    filter: "schedule",
  });
  // The upper bound: today + 90 days, then cut.
  const far = ahead("Schedule", "2027-03-01");
  if (!far.ok) throw new Error(far.reason);
  assertEquals(far.requests[0].to, "2027-01-15");
  // A range wholly past that horizon, without the filter, or for any other lookup, is refused.
  assertEquals(ahead("schedule", "2027-03-01", "2027-02-01").ok, false);
  assertEquals(ahead("", "2026-11-30").ok, false);
  assertEquals(
    validateDataRequests(
      [{ lookup: "body", from: "2026-10-18", to: "2026-11-30", filter: "" }],
      today,
    )
      .ok,
    false,
  );
  // A past week, with or without the filter, still works.
  assertEquals(ahead("schedule", "2026-10-11", "2026-10-05").ok, true);
  assertEquals(ahead("", "2026-10-11", "2026-10-05").ok, true);
});

Deno.test("the catalogue tells the model the schedule filter and the horizon", () => {
  const text = describeLookupCatalogue();
  assertStringIncludes(text, "with the filter schedule");
  assertStringIncludes(text, "up to 90 days ahead");
});
