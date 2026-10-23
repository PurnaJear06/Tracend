// How a contributor says which figures of its text are values (`grounding.ts` says what a value is
// worth). A contributor mixes fixed wording with values: the windows it looks at ("last 14 days"),
// the thresholds it applies ("below 40"), the definition of a baseline, and the athlete's records
// and Tracend's calculations. Only the values may stand behind a figure in a reply, so a contributor
// writes each one through `record` (or `figure`, for what a proposal would set) while it builds its
// text, and everything it does not mark grounds nothing. The host gets the text without the marks,
// and the marked values as structured data (`pieces`), the way `RenderedBlock.figures` always
// carried a proposal's figures; it never gets the whole text as a ground.
//
// A marked value is handed over with the few words around it that make its unit ("7 h", "31 on"),
// cut at the nearest digit and at the line, so the numbers check reads it the way it reads the
// text, and a constant next to a value never comes with it.

const recordOpen = "\u{E000}";
const recordClose = "\u{E001}";
const figureOpen = "\u{E002}";
const figureClose = "\u{E003}";
const marks = /[\u{E000}-\u{E003}]/gu;

/** What the athlete or Tracend recorded or calculated: any figure in a reply may rest on it. */
export const record = (value: string | number): string =>
  `${recordOpen}${String(value).replace(marks, "")}${recordClose}`;

/** What Tracend built for a proposal: a figure may rest on it, never one that states the athlete's own target. */
export const figure = (value: string | number): string =>
  `${figureOpen}${String(value).replace(marks, "")}${figureClose}`;

/** A text built with `record` and `figure`, read as the text and the values in it. */
export type Pieces = Readonly<{
  /** The text as the model reads it: no marks. */
  text: string;
  /** Each recorded value with the words around it that give its unit. */
  records: readonly string[];
  /** Each proposal figure, the same way. */
  figures: readonly string[];
}>;

/** How far the words around a value may reach: the numbers check reads that far for a unit. */
const reach = 28;

/**
 * The words next to a value on one side, up to the nearest digit or the end of the line (a digit
 * belongs to another value; the numbers check reads a unit from the letters before the next one).
 * When it is the reach that cuts the words, not a digit, a word cut in half is dropped.
 */
function wordsNextTo(text: string, at: number, side: "before" | "after"): string {
  const window = side === "after"
    ? text.slice(at, at + reach)
    : text.slice(Math.max(0, at - reach), at);
  const stop = side === "after" ? /^[^\d\n]*/ : /[^\d\n]*$/;
  const words = stop.exec(window)![0];
  if (words !== window) return words;
  const beyond = side === "after" ? text[at + reach] : text[at - reach - 1];
  if (
    beyond === undefined || /\s/.test(beyond) || /\s/.test(window.at(side === "after" ? -1 : 0)!)
  ) {
    return words;
  }
  return side === "after" ? words.replace(/\S*$/, "") : words.replace(/^\S*/, "");
}

export function pieces(marked: string): Pieces {
  let text = "";
  const found: { kind: "records" | "figures"; start: number; end: number }[] = [];
  let open: { kind: "records" | "figures"; start: number } | null = null;
  for (const char of marked) {
    if (char === recordOpen || char === figureOpen) {
      open = { kind: char === recordOpen ? "records" : "figures", start: text.length };
    } else if (char === recordClose || char === figureClose) {
      if (open) found.push({ ...open, end: text.length });
      open = null;
    } else text += char;
  }
  const records: string[] = [];
  const figures: string[] = [];
  for (const { kind, start, end } of found) {
    const piece = `${wordsNextTo(text, start, "before")}${text.slice(start, end)}${
      wordsNextTo(text, end, "after")
    }`.trim();
    if (piece !== "" && /\d/.test(piece)) (kind === "records" ? records : figures).push(piece);
  }
  return { text, records, figures };
}

/** The text of a marked string, as the model reads it. */
export const plain = (marked: string): string => marked.replace(marks, "");
