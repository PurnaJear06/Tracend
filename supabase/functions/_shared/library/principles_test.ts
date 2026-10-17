import { assert, assertEquals } from "jsr:@std/assert@1";
import { validateCoachContextContributors } from "../coach_context/host.ts";
import { librarySources } from "../../../library/index.ts";
import {
  citedSourceKeys,
  coachingPrinciples,
  coachingPrinciplesContributor,
  coachingPrinciplesMaxChars,
  coachingPrinciplesMinChars,
} from "./principles.ts";

Deno.test("every source id the digest cites exists in the library", () => {
  const known = new Set(librarySources.map((source) => source.slug));
  const cited = citedSourceKeys(coachingPrinciples.text);
  assert(cited.length >= 20, `digest cites only ${cited.length} sources`);
  for (const key of cited) assert(known.has(key), `unknown source id: ${key}`);
});

Deno.test("the digest stays between 1,200 and 1,800 tokens (four characters a token)", () => {
  const length = coachingPrinciples.text.length;
  assert(length <= coachingPrinciplesMaxChars, `digest is ${length} characters`);
  assert(length >= coachingPrinciplesMinChars, `digest is ${length} characters`);
});

Deno.test("the digest covers the areas the owner asked for", () => {
  for (
    const heading of [
      "TRAINING",
      "CARDIO AND DAILY ACTIVITY",
      "NUTRITION",
      "RECOVERY AND SLEEP",
      "SCREENING AND SAFETY",
      "HOW A GOOD COACH COMMUNICATES",
    ]
  ) {
    assert(coachingPrinciples.text.includes(`\n${heading}\n`), `missing section ${heading}`);
  }
});

Deno.test("the digest is plain text without athlete data, dates or markup", () => {
  assert(!/<\/?[a-z]/i.test(coachingPrinciples.text), "no markup");
  assert(!/\d{4}-\d{2}-\d{2}/.test(coachingPrinciples.text), "no dates");
  assert(!/@/.test(coachingPrinciples.text), "no addresses");
});

Deno.test("the contributor is a valid stable contributor that renders the digest unclipped", async () => {
  validateCoachContextContributors([coachingPrinciplesContributor]);
  assertEquals(coachingPrinciplesContributor.slot, "stable");
  assert(coachingPrinciplesContributor.budgetChars >= coachingPrinciples.text.length);
  const input = { userId: "u", question: "q", localDate: "2026-10-17" };
  const first = await coachingPrinciplesContributor.render(input);
  const second = await coachingPrinciplesContributor.render({ ...input, question: "other" });
  assertEquals(first, coachingPrinciples.text);
  assertEquals(second, first);
});
