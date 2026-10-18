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
  assertEquals(maxRequestsPerRound, 4);
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

Deno.test("more than four requests in a round are refused; repeats are merged", () => {
  const request = (lookup: string) => ({ lookup, from: "2026-10-01", to: today });
  assertStringIncludes(
    refused([
      request("body"),
      request("recovery"),
      request("check_ins"),
      request("goals"),
      request("weekly_reviews"),
    ]),
    "at most 4 requests",
  );
  assertEquals(ok([request("body"), request("body")]).length, 1);
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
