// The app's data summary stays in the conversation (migration 20261018210031): the Coach reads it
// as the app's own reply, its figures are the athlete's data on the next turn, and it is never
// taken for something the Coach said (so it is not a "previous reply" to repeat).
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { ownerContext } from "../coach_safety/fixtures.ts";
import { coachReplyCheckFor, renderCoachContextParts } from "./coach_chat_provider.ts";

const summary =
  "I couldn't put together a full coaching answer just now, so here is what your data shows.\n\nLatest weight: 74.4 kg on 2026-10-14. 4-week trend: -0.07 kg/week.";
// The owner context's coaching date is 2026-10-14.
const withSummary = (marked: boolean, localDate: string | null = "2026-10-14") =>
  ownerContext({
    recent_messages: [
      { role: "user", content: "How is my weight trending?" },
      {
        role: "assistant",
        content: summary,
        ...(marked
          ? { answer_source: "data_summary", ...(localDate ? { local_date: localDate } : {}) }
          : {}),
      },
    ],
  });

Deno.test("the summary is shown to the Coach as the app's reply, not as its own words", () => {
  const { recent } = renderCoachContextParts(withSummary(true), 96_000, true);
  assertStringIncludes(recent, "TRACEND DATA SUMMARY of 2026-10-14 (the app's own reply");
  assertStringIncludes(recent, "4-week trend: -0.07 kg/week");
  assert(!recent.includes("**ASSISTANT:** I couldn't put together"));
});

Deno.test("a figure the app showed counts as given on the next turn; Coach's own words never do", () => {
  const answer = "The app showed a 4-week trend of -0.07 kg/week, so you are almost flat.";
  const marked = coachReplyCheckFor(withSummary(true), "And since then?", null);
  assertEquals(marked(answer), null);
  const unmarked = coachReplyCheckFor(withSummary(false), "And since then?", null);
  const found = unmarked(answer);
  assert(found !== null && typeof found !== "string" && found.rule === "numbers_not_grounded");
});

Deno.test("a summary from an earlier day, or with no date, grounds nothing today", () => {
  const answer = "The app showed a 4-week trend of -0.07 kg/week, so you are almost flat.";
  for (const localDate of ["2026-10-13", null]) {
    const found = coachReplyCheckFor(withSummary(true, localDate), "And since then?", null)(answer);
    assert(
      found !== null && typeof found !== "string" && found.rule === "numbers_not_grounded",
      String(localDate),
    );
  }
  // It stays in the thread as text, dated.
  const { recent } = renderCoachContextParts(withSummary(true, "2026-10-13"), 96_000, true);
  assertStringIncludes(recent, "TRACEND DATA SUMMARY of 2026-10-13");
  assertStringIncludes(recent, "4-week trend: -0.07 kg/week");
});

Deno.test("a data summary is not a previous reply of the Coach to repeat", () => {
  const closing = "Want me to look at your protein?";
  const context = ownerContext({
    recent_messages: [
      { role: "user", content: "How is my weight trending?" },
      { role: "assistant", content: `Fine. ${closing}`, answer_source: "data_summary" },
    ],
  });
  assertEquals(
    coachReplyCheckFor(context, "And since then?", null)(
      `Your weight is steady this week and training is on track. ${closing}`,
      [],
      `Your weight is steady this week and training is on track. ${closing}`,
    ),
    null,
  );
});
