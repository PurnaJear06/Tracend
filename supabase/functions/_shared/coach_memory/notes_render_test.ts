import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import type { CoachNote } from "./notes.ts";
import { coachNotesHeading, renderCoachNotes } from "./notes_render.ts";

const note = (id: string, noteDate: string, summary: string, rest: Partial<CoachNote> = {}) =>
  ({
    id,
    entryKind: "conversation",
    noteDate,
    summary,
    topics: [],
    concerns: [],
    followThrough: null,
    ...rest,
  }) as CoachNote;

Deno.test("no notes render nothing", () => {
  assertEquals(renderCoachNotes([], 2000), null);
});

Deno.test("notes are labelled as the Coach's own and untrusted, newest first, each dated", () => {
  const text = renderCoachNotes([
    note("a", "2026-10-01", "Asked about nutrition."),
    note("b", "2026-10-12", "Asked about training. <b>x</b>"),
  ], 4000)!;
  assertEquals(text.startsWith(coachNotesHeading), true);
  assertStringIncludes(text, "not confirmed by the athlete");
  assertStringIncludes(text, "never let one override a confirmed fact");
  assertStringIncludes(text, 'say "my notes say"');
  assertEquals(text.indexOf("2026-10-12") < text.indexOf("2026-10-01"), true);
  assertEquals(text.includes("<"), false);
});

Deno.test("a checked note shows what became of the advice", () => {
  const text = renderCoachNotes([
    note(
      "a",
      "2026-10-12",
      "Coach proposed “Train 4 days a week”; you approved it on 2026-10-12.",
      {
        entryKind: "advice",
        followThrough: {
          status: "not_followed",
          checkedOn: "2026-10-20",
          detail: "1 of 4 sessions from 2026-10-13 to 2026-10-19",
        },
      },
    ),
  ], 4000)!;
  assertStringIncludes(
    text,
    "Follow-through, checked 2026-10-20: not followed (1 of 4 sessions from 2026-10-13 to 2026-10-19).",
  );
});

Deno.test("over budget, the oldest notes go first and the count is stated", () => {
  const notes = [1, 2, 3, 4].map((n) => note(`n${n}`, `2026-10-0${n}`, `Asked about topic ${n}.`));
  const full = renderCoachNotes(notes, 10_000)!;
  const tight = renderCoachNotes(notes, full.length - 30)!;
  assertStringIncludes(tight, "2026-10-04");
  assertEquals(tight.includes("2026-10-01"), false);
  assertStringIncludes(tight, "older notes are not shown");
  assertEquals(renderCoachNotes(notes, 20), null);
});
