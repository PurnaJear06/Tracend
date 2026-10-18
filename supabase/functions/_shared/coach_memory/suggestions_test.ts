import { assertEquals } from "jsr:@std/assert@1.0.14";
import { makeFact } from "./memory_fixtures.ts";
import {
  maxModelSuggestions,
  maxSuggestionsPerTurn,
  mergeSuggestions,
  sanitizeModelSuggestions,
  suggestFromStatement,
  suggestionToWire,
} from "./suggestions.ts";

Deno.test("a new statement is offered as an add and nothing is stored", () => {
  const [suggestion] = suggestFromStatement("I hate mushrooms", []);
  assertEquals(
    [suggestion.action, suggestion.kind, suggestion.subject, suggestion.statement],
    ["add", "food_dislike", "mushrooms", "Dislikes mushrooms"],
  );
  assertEquals([suggestion.factId, suggestion.previous, suggestion.origin], [
    null,
    null,
    "athlete_statement",
  ]);
});

Deno.test("the owner's cases: squats are an exercise, weekends are a schedule", () => {
  assertEquals(suggestFromStatement("I don't like squats", []).map((s) => s.kind), [
    "exercise_dislike",
  ]);
  assertEquals(suggestFromStatement("I don't have time on weekends", []).map((s) => s.kind), [
    "schedule_constraint",
  ]);
});

Deno.test("a statement that contradicts a confirmed fact is an update that names the fact", () => {
  const saved = makeFact("food_dislike", "mushrooms", "Dislikes mushrooms", {
    confirmedOn: "2026-09-02",
  });
  const [suggestion] = suggestFromStatement("Actually I love mushrooms now", [saved]);
  assertEquals(suggestion.action, "update");
  assertEquals(suggestion.kind, "food_like");
  assertEquals(suggestion.statement, "Likes mushrooms");
  assertEquals(suggestion.factId, saved.id);
  assertEquals(suggestion.previous, "Dislikes mushrooms");
  assertEquals(suggestion.reason.includes("2026-09-02"), true);
  assertEquals(suggestion.reason.includes("Dislikes mushrooms"), true);
});

Deno.test("an update to a liking about something unclassified keeps the saved fact's domain", () => {
  const saved = makeFact("exercise_dislike", "early mornings", "Dislikes early mornings");
  const [suggestion] = suggestFromStatement("I love early mornings", [saved]);
  assertEquals([suggestion.action, suggestion.kind], ["update", "exercise_like"]);
});

Deno.test("a healed injury is offered as a resolve of the saved fact", () => {
  const saved = makeFact("injury_limitation", "left knee", "Left knee pain on deep squats");
  const [suggestion] = suggestFromStatement("good news, my knee is fine now", [saved]);
  assertEquals(suggestion.action, "resolve");
  assertEquals(suggestion.factId, saved.id);
  assertEquals(suggestion.statement, saved.statement);
});

Deno.test("a liking that cuts across an allergy is a review, never a replacement", () => {
  const saved = makeFact("allergy", "peanuts", "Allergy or intolerance: peanuts");
  const [suggestion] = suggestFromStatement("I love peanuts", [saved]);
  assertEquals([suggestion.action, suggestion.factId], ["review", saved.id]);
});

Deno.test("a fact already saved is not offered again", () => {
  const saved = makeFact("food_dislike", "mushrooms", "Dislikes mushrooms");
  assertEquals(suggestFromStatement("I hate mushrooms", [saved]), []);
});

Deno.test("no claim, no suggestion", () => {
  assertEquals(suggestFromStatement("what should I eat today?", []), []);
  assertEquals(suggestFromStatement("", []), []);
});

Deno.test("at most two suggestions follow one message, without repeats for one fact", () => {
  const found = suggestFromStatement(
    "I hate mushrooms. I love running. I hate rice. I hate fish.",
    [],
  );
  assertEquals(found.length, maxSuggestionsPerTurn);
  const saved = makeFact("food_like", "pizza", "Likes pizza");
  const twice = suggestFromStatement("I hate pizza. I really dislike pizza.", [saved]);
  assertEquals(twice.length, 1);
});

Deno.test("merge puts the athlete's own statement first and drops repeats", () => {
  const saved = makeFact("food_like", "pizza", "Likes pizza");
  const fromStatement = suggestFromStatement("I hate pizza", [saved]);
  const fromModel = sanitizeModelSuggestions(
    [
      {
        action: "update",
        kind: "food_dislike",
        subject: "pizza",
        statement: "Dislikes pizza",
        fact_id: saved.id,
      },
      { action: "add", kind: "equipment", subject: "bench", statement: "Has a bench" },
      { action: "add", kind: "equipment", subject: "rack", statement: "Has a squat rack" },
    ],
    [saved],
  ).suggestions;
  const merged = mergeSuggestions(fromStatement, fromModel);
  assertEquals(merged.map((s) => s.origin), ["athlete_statement", "coach"]);
  assertEquals(merged.map((s) => s.subject), ["pizza", "bench"]);
});

Deno.test("model suggestions: only closed kinds, real fact ids and plain words survive", () => {
  const saved = makeFact("injury_limitation", "left knee", "Left knee pain");
  const check = (raw: unknown) => sanitizeModelSuggestions(raw, [saved]);
  const valid = {
    action: "add",
    kind: "equipment",
    subject: "Kettlebells",
    statement: "Has kettlebells",
  };
  const result = check([valid]);
  assertEquals(result.dropped, 0);
  assertEquals(result.suggestions[0].subject, "kettlebells");
  assertEquals(result.suggestions[0].origin, "coach");
  const refused = [
    { ...valid, kind: "medication" },
    { ...valid, action: "delete" },
    { ...valid, action: "review" },
    { ...valid, subject: "" },
    { ...valid, subject: "x".repeat(61) },
    { ...valid, subject: "<script>" },
    { ...valid, statement: "" },
    { ...valid, statement: "y".repeat(201) },
    { ...valid, statement: "Has <b>kettlebells</b>" },
    { ...valid, extra: true },
    { ...valid, fact_id: saved.id },
    { action: "update", kind: "injury_limitation", subject: "left knee", statement: "Healed" },
    {
      action: "update",
      kind: "injury_limitation",
      subject: "left knee",
      statement: "Healed",
      fact_id: "00000000-0000-4000-8000-ffffffffffff",
    },
    {
      action: "update",
      kind: "injury_limitation",
      subject: "left knee",
      statement: "Left knee pain",
      fact_id: saved.id,
    },
    "text",
    null,
    [1],
  ];
  for (const item of refused) {
    assertEquals(check([item]).suggestions, [], JSON.stringify(item));
    assertEquals(check([item]).dropped, 1, JSON.stringify(item));
  }
});

Deno.test("model suggestions: update and resolve act on a saved fact; add skips what is saved", () => {
  const saved = makeFact("injury_limitation", "left knee", "Left knee pain");
  const update = sanitizeModelSuggestions(
    [{
      action: "update",
      kind: "injury_limitation",
      subject: "left knee",
      statement: "Left knee pain on deep squats only",
      fact_id: saved.id,
    }],
    [saved],
  ).suggestions[0];
  assertEquals([update.action, update.factId, update.previous], [
    "update",
    saved.id,
    saved.statement,
  ]);
  const resolve = sanitizeModelSuggestions(
    [{ action: "resolve", kind: "equipment", subject: "x", statement: "y", fact_id: saved.id }],
    [saved],
  ).suggestions[0];
  assertEquals([resolve.action, resolve.kind, resolve.statement], [
    "resolve",
    "injury_limitation",
    saved.statement,
  ]);
  const repeat = sanitizeModelSuggestions(
    [{ action: "add", kind: "injury_limitation", subject: "knee", statement: "Knee pain" }],
    [saved],
  );
  assertEquals([repeat.suggestions, repeat.dropped], [[], 1]);
});

Deno.test("model suggestions: a missing field is fine, a non-list or an overlong list is counted", () => {
  assertEquals(sanitizeModelSuggestions(undefined, []), { suggestions: [], dropped: 0 });
  assertEquals(sanitizeModelSuggestions(null, []), { suggestions: [], dropped: 0 });
  assertEquals(sanitizeModelSuggestions({}, []), { suggestions: [], dropped: 1 });
  const item = { action: "add", kind: "equipment", subject: "bench", statement: "Has a bench" };
  const long = sanitizeModelSuggestions(Array(maxModelSuggestions + 2).fill(item), []);
  assertEquals(long.suggestions.length, maxModelSuggestions);
  assertEquals(long.dropped, 2);
});

Deno.test("the wire shape has a fixed set of keys", () => {
  const [suggestion] = suggestFromStatement("I hate mushrooms", []);
  assertEquals(Object.keys(suggestionToWire(suggestion)).sort(), [
    "action",
    "fact_id",
    "kind",
    "origin",
    "previous",
    "reason",
    "statement",
    "subject",
  ]);
});
