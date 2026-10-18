// The Coach's notes as a section of the Coach's file. Labelled as the Coach's own notes and as
// untrusted: they are written by Tracend's rules from earlier conversations, not confirmed by the
// athlete, and they never override a confirmed fact or one of Tracend's calculations.
import type { CoachNote } from "./notes.ts";
import { flatten } from "./text.ts";

export const coachNotesHeading = "## Coach's notes (earlier conversations)";

const preface =
  "Tracend wrote these notes after earlier conversations, from rules, not from your replies. " +
  "They are not confirmed by the athlete and can be out of date or wrong: never treat one as a " +
  "fact about the athlete, never let one override a confirmed fact or Tracend's own numbers, and " +
  'say "my notes say" when you rely on one. Newest first; each line shows its date.';

function noteLine(note: CoachNote): string {
  const through = note.followThrough
    ? ` Follow-through, checked ${note.followThrough.checkedOn}: ${
      note.followThrough.status.replace("_", " ")
    } (${flatten(note.followThrough.detail, 120)}).`
    : "";
  return `- ${note.noteDate}: ${flatten(note.summary, 400)}${through}`;
}

/**
 * The notes section, or null when there are none. The newest notes come first; when the section
 * does not fit the budget the oldest are dropped and their count is stated.
 */
export function renderCoachNotes(notes: readonly CoachNote[], budgetChars: number): string | null {
  if (notes.length === 0) return null;
  const ordered = notes.toSorted((a, b) =>
    b.noteDate.localeCompare(a.noteDate) || a.id.localeCompare(b.id)
  );
  const render = (count: number) =>
    [
      coachNotesHeading,
      preface,
      ...ordered.slice(0, count).map(noteLine),
      ...(count < ordered.length ? [`(${ordered.length - count} older notes are not shown.)`] : []),
    ].join("\n");
  for (let count = ordered.length; count > 0; count--) {
    const text = render(count);
    if (text.length <= budgetChars) return text;
  }
  return null;
}
