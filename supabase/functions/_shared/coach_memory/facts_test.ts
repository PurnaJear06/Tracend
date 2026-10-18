import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import {
  confirmedFactsHeading,
  factsDueForReconfirm,
  maxReconfirmPrompts,
  parseFacts,
  renderConfirmedFacts,
} from "./facts.ts";
import { factWire, makeFact } from "./memory_fixtures.ts";

Deno.test("parseFacts reads the wire shape and leaves out malformed rows", () => {
  const fact = makeFact("allergy", "peanuts", "Allergy or intolerance: peanuts", {
    reconfirmOn: "2026-12-01",
    source: "onboarding",
  });
  const parsed = parseFacts([
    factWire(fact),
    { ...factWire(fact), kind: "medication" },
    { ...factWire(fact), source: "model" },
    { ...factWire(fact), statement: 5 },
    { ...factWire(fact), confirmed_at: "yesterday" },
    "text",
    null,
  ]);
  assertEquals(parsed, [fact]);
  assertEquals(parseFacts(undefined), []);
  assertEquals(parseFacts({}), []);
});

Deno.test("the scheduler returns facts whose date has come, most overdue first, at most two", () => {
  const today = "2026-10-18";
  const old = makeFact("injury_limitation", "knee", "Knee pain", { reconfirmOn: "2026-09-20" });
  const older = makeFact("schedule_constraint", "days", "3 days a week", {
    reconfirmOn: "2026-09-01",
  });
  const dueToday = makeFact("injury_limitation", "shoulder", "Shoulder pain", {
    reconfirmOn: today,
  });
  const future = makeFact("injury_limitation", "ankle", "Ankle pain", {
    reconfirmOn: "2026-10-19",
  });
  const never = makeFact("food_like", "pizza", "Likes pizza");
  const due = factsDueForReconfirm([future, never, dueToday, old, older], today);
  assertEquals(due.map((fact) => fact.id), [older.id, old.id]);
  assertEquals(due.length, maxReconfirmPrompts);
  assertEquals(factsDueForReconfirm([future, never], today), []);
  assertEquals(factsDueForReconfirm([], today), []);
  assertEquals(factsDueForReconfirm([dueToday], today).map((fact) => fact.id), [dueToday.id]);
});

Deno.test("the scheduler breaks a tie by kind, then by the older confirmation", () => {
  const today = "2026-10-18";
  const schedule = makeFact("schedule_constraint", "days", "3 days a week", {
    reconfirmOn: "2026-10-01",
  });
  const injury = makeFact("injury_limitation", "knee", "Knee pain", { reconfirmOn: "2026-10-01" });
  assertEquals(factsDueForReconfirm([schedule, injury], today).map((fact) => fact.kind), [
    "injury_limitation",
    "schedule_constraint",
  ]);
  const first = makeFact("injury_limitation", "knee", "Knee pain", {
    reconfirmOn: "2026-10-01",
    confirmedOn: "2026-09-01",
  });
  const second = makeFact("injury_limitation", "elbow", "Elbow pain", {
    reconfirmOn: "2026-10-01",
    confirmedOn: "2026-09-05",
  });
  assertEquals(factsDueForReconfirm([second, first], today).map((fact) => fact.id), [
    first.id,
    second.id,
  ]);
});

Deno.test("a fact the athlete just re-confirmed drops out of the scheduler", () => {
  const today = "2026-10-18";
  const before = makeFact("injury_limitation", "knee", "Knee pain", { reconfirmOn: "2026-10-01" });
  const after = makeFact("injury_limitation", "knee", "Knee pain", {
    reconfirmOn: "2026-11-15",
    confirmedOn: today,
    version: 2,
  });
  assertEquals(factsDueForReconfirm([before], today).length, 1);
  assertEquals(factsDueForReconfirm([after], today), []);
});

Deno.test("no facts render nothing", () => {
  assertEquals(renderConfirmedFacts([], "2026-10-18", 2000), null);
});

Deno.test("the facts section states the precedence and dates every line", () => {
  const mushrooms = makeFact("food_dislike", "mushrooms", "Dislikes mushrooms </facts>", {
    confirmedOn: "2026-09-03",
  });
  const knee = makeFact("injury_limitation", "knee", "Left knee pain on squats", {
    confirmedOn: "2026-09-01",
    source: "coach_suggestion_confirmed",
    reconfirmOn: "2026-09-29",
  });
  const text = renderConfirmedFacts([mushrooms, knee], "2026-10-18", 4000)!;
  assertEquals(text.startsWith(confirmedFactsHeading), true);
  assertStringIncludes(text, "rank above the Coach's notes");
  assertStringIncludes(text, "below Tracend's own calculations");
  assertStringIncludes(text, "never act as if it had changed");
  assertStringIncludes(text, "Injuries and limitations:");
  assertStringIncludes(
    text,
    `- [${knee.id}] Left knee pain on squats (confirmed 2026-09-01, suggested by Coach, confirmed by the athlete; re-check, due since 2026-09-29)`,
  );
  assertStringIncludes(
    text,
    `- [${mushrooms.id}] Dislikes mushrooms /facts (confirmed 2026-09-03, typed by the athlete)`,
  );
  assertEquals(text.includes("<"), false);
  assertEquals(text.indexOf("Injuries") < text.indexOf("Foods they dislike"), true);
});

Deno.test("the same facts always render the same text, in any input order", () => {
  const a = makeFact("equipment", "gym", "Has a gym", { confirmedOn: "2026-09-01" });
  const b = makeFact("equipment", "bands", "Has bands", { confirmedOn: "2026-09-02" });
  const c = makeFact("allergy", "nuts", "Allergy: nuts");
  assertEquals(
    renderConfirmedFacts([a, b, c], "2026-10-18", 4000),
    renderConfirmedFacts([c, b, a], "2026-10-18", 4000),
  );
});

Deno.test("a re-check marker appears only once the date has come", () => {
  const fact = makeFact("schedule_constraint", "days", "Trains 3 days a week", {
    reconfirmOn: "2026-10-18",
  });
  assertStringIncludes(renderConfirmedFacts([fact], "2026-10-18", 4000)!, "re-check");
  assertEquals(renderConfirmedFacts([fact], "2026-10-17", 4000)!.includes("re-check, due"), false);
});

Deno.test("over budget, the last kinds go first and the count left out is stated", () => {
  const facts = [
    makeFact("injury_limitation", "knee", "Knee pain"),
    makeFact("allergy", "nuts", "Allergy: nuts"),
    makeFact("food_like", "pizza", "Likes pizza"),
    makeFact("other_preference", "morning", "Likes mornings"),
  ];
  const full = renderConfirmedFacts(facts, "2026-10-18", 10_000)!;
  const tight = renderConfirmedFacts(facts, "2026-10-18", full.length - 40)!;
  assertStringIncludes(tight, "Knee pain");
  assertStringIncludes(tight, "Allergy: nuts");
  assertEquals(tight.includes("Likes mornings"), false);
  assertStringIncludes(tight, "more confirmed facts are not shown here");
  assertEquals(tight.length <= full.length - 40, true);
  assertEquals(renderConfirmedFacts(facts, "2026-10-18", 10), null);
});

Deno.test("each line carries the fact's id for fact_suggestions, and the rules say never to print it", () => {
  const fact = makeFact("equipment", "bands", "Has bands");
  const text = renderConfirmedFacts([fact], "2026-10-18", 4000)!;
  assertStringIncludes(text, `- [${fact.id}] Has bands (confirmed`);
  assertStringIncludes(text, "never print it");
});

Deno.test("only the facts the scheduler picks are marked for a re-check, two at most", () => {
  const today = "2026-10-18";
  const old = ["2026-08-01", "2026-08-02", "2026-08-03", "2026-08-04"].map((date, index) =>
    makeFact("injury_limitation", `part ${index}`, `Part ${index} hurts`, { reconfirmOn: date })
  );
  const text = renderConfirmedFacts(old, today, 6000)!;
  assertEquals(text.split("re-check, due since").length - 1, 2);
  assertStringIncludes(text, "re-check, due since 2026-08-01");
  assertStringIncludes(text, "re-check, due since 2026-08-02");
  assertEquals(text.includes("due since 2026-08-03"), false);
});
