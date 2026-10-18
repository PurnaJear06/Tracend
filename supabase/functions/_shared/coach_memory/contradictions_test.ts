import { assertEquals } from "jsr:@std/assert@1.0.14";
import { type ClaimVerdict, judgeClaim } from "./contradictions.ts";
import { makeFact } from "./memory_fixtures.ts";
import { extractClaims, type StatementClaim } from "./statements.ts";

const one = (text: string): StatementClaim => {
  const found = extractClaims(text);
  if (found.length !== 1) throw new Error(`expected one claim in ${text}`);
  return found[0];
};
const verdict = (text: string, ...facts: ReturnType<typeof makeFact>[]): ClaimVerdict =>
  judgeClaim(one(text), facts);
const kind = (result: ClaimVerdict) => result.verdict;
const conflictWith = (result: ClaimVerdict) =>
  result.verdict === "conflict" ? result.fact.statement : null;

Deno.test("nothing saved means a new fact", () => {
  assertEquals(kind(verdict("I hate mushrooms")), "new");
  assertEquals(kind(verdict("I can't train on Saturdays")), "new");
  assertEquals(kind(verdict("always keep it short")), "new");
});

Deno.test("food: the opposite feeling about the same food contradicts", () => {
  const dislike = makeFact("food_dislike", "mushrooms", "Dislikes mushrooms");
  assertEquals(conflictWith(verdict("I love mushrooms", dislike)), "Dislikes mushrooms");
  assertEquals(kind(verdict("I hate mushrooms", dislike)), "known");
  assertEquals(kind(verdict("I love rice", dislike)), "new");
  const like = makeFact("food_like", "pizza", "Likes pizza");
  assertEquals(conflictWith(verdict("I hate pizza", like)), "Likes pizza");
  assertEquals(kind(verdict("I love pizza", like)), "known");
});

Deno.test("exercise: same rule, and food and exercise do not mix", () => {
  const dislike = makeFact("exercise_dislike", "squats", "Dislikes squats");
  assertEquals(conflictWith(verdict("I love squats", dislike)), "Dislikes squats");
  assertEquals(kind(verdict("I hate squats", dislike)), "known");
  const food = makeFact("food_dislike", "squash", "Dislikes squash");
  assertEquals(kind(verdict("I love squats", food)), "new");
});

Deno.test("a broader or narrower name for the same thing still matches", () => {
  const dislike = makeFact(
    "exercise_dislike",
    "barbell back squats",
    "Dislikes barbell back squats",
  );
  assertEquals(kind(verdict("I love squats", dislike)), "conflict");
  const short = makeFact("food_dislike", "mushroom", "Dislikes mushroom");
  assertEquals(kind(verdict("I love mushroom pizza", short)), "conflict");
});

Deno.test("an unclassified liking is judged against food and exercise facts alike", () => {
  const dislike = makeFact("exercise_dislike", "early mornings", "Dislikes early mornings");
  assertEquals(kind(verdict("I love early mornings", dislike)), "conflict");
});

Deno.test("a migrated preference with no like or dislike in it is never contradicted by its subject alone", () => {
  const legacy = makeFact("other_preference", "mushrooms", "mushrooms");
  assertEquals(kind(verdict("I hate mushrooms", legacy)), "known");
  assertEquals(kind(verdict("I love mushrooms", legacy)), "known");
  const typed = makeFact("other_preference", "mushrooms", "I don't eat mushrooms");
  assertEquals(kind(verdict("I don't eat mushrooms", typed)), "known");
});

Deno.test("a vague preference that says like or dislike is judged by it", () => {
  const same = makeFact("other_preference", "early mornings", "Dislikes early mornings");
  assertEquals(kind(verdict("I can't stand early mornings", same)), "known");
  assertEquals(kind(verdict("I love early mornings", same)), "conflict");
  const liked = makeFact("other_preference", "early mornings", "Likes early mornings");
  assertEquals(kind(verdict("I can't stand early mornings", liked)), "conflict");
});

Deno.test("an allergy is never overridden by a liking: the athlete is asked", () => {
  const allergy = makeFact("allergy", "peanuts", "Allergy or intolerance: peanuts");
  const result = verdict("I love peanuts", allergy);
  assertEquals(result.verdict, "conflict");
  if (result.verdict === "conflict") {
    assertEquals([result.review, result.resolves], [true, false]);
  }
  assertEquals(kind(verdict("I hate peanuts", allergy)), "known");
  assertEquals(kind(verdict("I'm allergic to peanuts", allergy)), "known");
  const like = makeFact("food_like", "peanuts", "Likes peanuts");
  assertEquals(kind(verdict("I'm allergic to peanuts", like)), "conflict");
});

Deno.test("injury: the same part is known; a healed part closes the saved injury", () => {
  const injury = makeFact("injury_limitation", "left knee", "Left knee pain on deep squats");
  assertEquals(kind(verdict("my left knee hurts", injury)), "known");
  assertEquals(kind(verdict("my knee hurts", injury)), "known");
  assertEquals(kind(verdict("my right shoulder hurts", injury)), "new");
  const healed = verdict("my knee is fine now", injury);
  assertEquals(healed.verdict, "conflict");
  if (healed.verdict === "conflict") assertEquals(healed.resolves, true);
  assertEquals(kind(verdict("my shoulder is fine now", injury)), "known");
  assertEquals(kind(verdict("my knee is fine now")), "known");
});

Deno.test("equipment: gaining or losing an item contradicts a saved statement", () => {
  const none = makeFact("equipment", "barbell", "No barbell");
  assertEquals(kind(verdict("I bought a barbell", none)), "conflict");
  assertEquals(kind(verdict("I don't have a barbell", none)), "known");
  const has = makeFact("equipment", "dumbbells", "Has dumbbells");
  assertEquals(kind(verdict("I don't have dumbbells", has)), "conflict");
  assertEquals(kind(verdict("I have dumbbells", has)), "known");
  assertEquals(kind(verdict("I have a treadmill", has)), "new");
});

Deno.test("equipment: joining a gym contradicts a home setup, and quitting contradicts a gym", () => {
  const home = makeFact("equipment", "home dumbbells", "Trains at home with dumbbells only");
  assertEquals(kind(verdict("I joined a gym", home)), "conflict");
  const gym = makeFact("equipment", "gym", "Has a gym membership");
  assertEquals(kind(verdict("I quit my gym", gym)), "conflict");
  assertEquals(kind(verdict("I joined a gym", gym)), "known");
  const noGym = makeFact("equipment", "no gym", "No gym, trains at home");
  assertEquals(kind(verdict("I joined a gym", noGym)), "conflict");
});

Deno.test("schedule: a different number of days or minutes contradicts", () => {
  const days = makeFact("schedule_constraint", "days per week", "Can train 3 days a week");
  assertEquals(conflictWith(verdict("I can train 5 days a week", days)), "Can train 3 days a week");
  assertEquals(kind(verdict("I can only train 3 days a week", days)), "known");
  const minutes = makeFact(
    "schedule_constraint",
    "session length",
    "Has about 45 minutes per session",
  );
  assertEquals(kind(verdict("I only have 30 minutes", minutes)), "conflict");
  assertEquals(kind(verdict("I have 45 minutes", minutes)), "known");
  assertEquals(kind(verdict("I have 45 minutes", days)), "new");
  assertEquals(kind(verdict("I can only train 3 days a week", minutes)), "new");
});

Deno.test("schedule: a day that was free but is now out contradicts; one already out is known", () => {
  const free = makeFact("schedule_constraint", "saturday training", "Trains on Saturday mornings");
  assertEquals(kind(verdict("I can't train on Saturdays", free)), "conflict");
  const out = makeFact("schedule_constraint", "no weekends", "Cannot train on weekends");
  assertEquals(kind(verdict("I can't train on Saturdays", out)), "known");
  assertEquals(kind(verdict("I can't train on Mondays", out)), "new");
});

Deno.test("coaching style: the opposite style contradicts, the same is known", () => {
  const direct = makeFact("coaching_style", "direct", "Prefers direct, blunt feedback");
  assertEquals(kind(verdict("I prefer gentle coaching", direct)), "conflict");
  assertEquals(kind(verdict("from now on be direct with me", direct)), "known");
  assertEquals(kind(verdict("always keep it short", direct)), "new");
  const typed = makeFact(
    "coaching_style",
    "be blunt with me",
    "Be blunt with me, no sugar coating",
  );
  assertEquals(kind(verdict("from now on be nicer to me", typed)), "conflict");
  const short = makeFact("coaching_style", "brief", "Prefers short answers");
  assertEquals(kind(verdict("in general I want more detail", short)), "conflict");
});

Deno.test("an unrelated saved fact never matches", () => {
  const unrelated = makeFact("food_dislike", "olives", "Dislikes olives");
  for (
    const text of [
      "I love pizza",
      "my knee hurts",
      "I joined a gym",
      "I can train 4 days a week",
      "always keep it short",
    ]
  ) assertEquals(kind(verdict(text, unrelated)), "new", text);
});
