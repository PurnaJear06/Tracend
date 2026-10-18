// Which research sources a reply names in its text. Coach is told to cite a library source in its
// evidence when it relies on one, but it sometimes writes "Maughan 2018" or "the NIH fact sheet"
// and leaves evidence empty, so the app shows no source. The reply guard reads the text instead:
//   - a source named in the text that was shown this turn is attached to the evidence by the
//     server (its label is the retrieved title and year, never the model's wording);
//   - a study named in the text that was not shown this turn is refused (citation_not_retrieved):
//     the model drops the claim or cites only what it was shown.
// A mention is found generically, not from a list of sources: a capitalised surname beside a year
// ("Maughan 2018", "Schoenfeld et al. (2017)", "Burke & Maughan, 2018") or an institution's
// initials beside the kind of document it publishes ("the NIH fact sheet", "ACSM position stand").
// It matches a shown source by the words of the source's own id (author, year, topic: the id reads
// author_year_topic), its title, and, with the year, the author's name in the excerpt shown.
export type ShownSources = Readonly<
  Record<string, Readonly<{ label: string; text?: string }>>
>;

/** A study the text names: the words that name its authors and the year, when it gives one. */
export type StudyMention = Readonly<{ authors: readonly string[]; year: number | null }>;

// Capitalised words that sit beside a year without naming an author ("Since 2018", "Spring 2026").
const notAnAuthor = new Set([
  "about",
  "after",
  "also",
  "and",
  "around",
  "before",
  "between",
  "by",
  "during",
  "early",
  "from",
  "in",
  "late",
  "mid",
  "since",
  "the",
  "until",
  "week",
  "year",
  "version",
  "build",
  "january",
  "february",
  "march",
  "april",
  "may",
  "june",
  "july",
  "august",
  "september",
  "october",
  "november",
  "december",
  "monday",
  "tuesday",
  "wednesday",
  "thursday",
  "friday",
  "saturday",
  "sunday",
  "spring",
  "summer",
  "autumn",
  "winter",
  "fall",
  "jan",
  "feb",
  "mar",
  "apr",
  "jun",
  "jul",
  "aug",
  "sep",
  "sept",
  "oct",
  "nov",
  "dec",
  "q1",
  "q2",
  "q3",
  "q4",
]);

// Initials that are not an institution, so "BMI guidelines" or "HIIT recommendations" name no source.
const notAnInstitution = new Set([
  "bmi",
  "bmr",
  "doms",
  "epoc",
  "hiit",
  "hrv",
  "liss",
  "rhr",
  "rir",
  "rpe",
  "tdee",
]);

const name = String.raw`\p{Lu}[\p{L}'’-]{2,}`;
const authorYear = new RegExp(
  String
    .raw`\b(${name}(?:(?:,|,? and|,? &)\s+${name})*(?:,? et al\.?)?),?\s*\(?((?:19[5-9]|20[0-2])\d)[a-z]?\)?`,
  "gu",
);
const institution = new RegExp(
  String
    .raw`\b([A-Z]{2,6})\b(?=\s+(?:fact ?sheets?|position (?:stands?|statements?)|consensus(?: statements?)?|(?:dietary |physical activity )?guidelines?|recommendations?))`,
  "g",
);

/** Lower-case words with accents removed ("Jäger" and "jager" are the same author). */
const words = (text: string) =>
  text.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase().split(/[^a-z0-9]+/).filter(Boolean);

/** The studies a text names, by author words and year. */
export function studyMentions(text: string): StudyMention[] {
  const found: StudyMention[] = [];
  for (const match of text.matchAll(authorYear)) {
    const authors = words(match[1]).filter((word) =>
      word !== "et" && word !== "al" && word !== "and" && !notAnAuthor.has(word)
    );
    if (authors.length > 0) found.push({ authors, year: Number(match[2]) });
  }
  for (const match of text.matchAll(institution)) {
    const initials = match[1].toLowerCase();
    if (!notAnInstitution.has(initials)) found.push({ authors: [initials], year: null });
  }
  return found;
}

type Identity = Readonly<{
  authors: ReadonlySet<string>;
  titleWords: ReadonlySet<string>;
  year: number | null;
  text: string;
}>;

const yearSegment = /^(?:19|20)\d{2}$/;

/**
 * The initials of each run of capitalised words in a title ("International Society of Sports
 * Nutrition" is ISSN), so "the ISSN position stand" names the source with that title.
 */
function acronymsOf(title: string): string[] {
  const runs = title.match(/\p{Lu}[\p{L}]*(?:\s+(?:(?:of|the|and|for)\s+)?\p{Lu}[\p{L}]*)*/gu) ??
    [];
  return runs.map((run) =>
    [...run.matchAll(/\p{Lu}[\p{L}]*/gu)].map((word) => word[0][0]).join("").toLowerCase()
  ).filter((initials) => initials.length >= 2);
}

function identityOf(id: string, source: ShownSources[string]): Identity {
  const parts = words(id.replaceAll("_", " "));
  const at = parts.findIndex((part) => yearSegment.test(part));
  const labelYear = /\b((?:19|20)\d{2})\b/.exec(source.label)?.[1];
  return {
    authors: new Set(at === -1 ? parts.slice(0, 1) : parts.slice(0, at)),
    titleWords: new Set([
      ...words(source.label).filter((word) => word.length >= 3),
      ...acronymsOf(source.label),
    ]),
    year: at !== -1 ? Number(parts[at]) : labelYear ? Number(labelYear) : null,
    text: ` ${words(source.text ?? "").join(" ")} `,
  };
}

function names(mention: StudyMention, source: Identity): boolean {
  if (mention.year !== null && source.year !== null && mention.year !== source.year) return false;
  return mention.authors.some((author) =>
    source.authors.has(author) || source.titleWords.has(author) ||
    // The author's name in the excerpt itself, with the year, or an institution's initials in it.
    ((mention.year === null || mention.year === source.year) && source.text.includes(` ${author} `))
  );
}

/** The ids of the shown sources the text names, in the order the sources were shown. */
export function namedShownSources(text: string, shown: ShownSources): string[] {
  const mentions = studyMentions(text);
  if (mentions.length === 0) return [];
  return Object.entries(shown).filter(([id, source]) => {
    const identity = identityOf(id, source);
    return mentions.some((mention) => names(mention, identity));
  }).map(([id]) => id);
}

/** The studies the text names that no shown source matches. */
export function unshownStudies(text: string, shown: ShownSources): StudyMention[] {
  const identities = Object.entries(shown).map(([id, source]) => identityOf(id, source));
  return studyMentions(text).filter((mention) =>
    !identities.some((identity) => names(mention, identity))
  );
}
