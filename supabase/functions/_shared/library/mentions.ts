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
export type StudyMention = Readonly<{
  authors: readonly string[];
  year: number | null;
  /** Initials of an institution ("NIH"), which name a source only by its id or title, never its excerpt. */
  initials?: true;
}>;

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
  // Calorie and plan wording that sits beside a number ("BMR 1980", "Target 1990 kcal").
  "bmr",
  "tdee",
  "target",
  "targets",
  "eat",
  "roughly",
  "approximately",
  "approx",
  "aim",
  "maintenance",
  "deficit",
  "surplus",
  "calories",
  "kcal",
  "goal",
  "limit",
  "ceiling",
  "floor",
  "range",
  "estimate",
  "total",
  "daily",
  "weight",
  "protein",
  "under",
  "over",
  "near",
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
// The year must end at a word boundary: "Smith 2019 found" is a year, "BMR 19800" is not.
const authorYear = new RegExp(
  String
    .raw`\b(${name}(?:(?:,|,? and|,? &)\s+${name})*(?:,? et al\.?)?),?\s*\(?((?:19[5-9]|20[0-2])\d)[a-z]?\)?(?![\p{L}\p{N}])`,
  "gu",
);
// "Grgic et al. found ..." names a study without its year.
const etAl = new RegExp(
  String.raw`\b(${name}(?:(?:,|,? and|,? &)\s+${name})*,? et al\.?)`,
  "gu",
);
// A number with its unit is a measurement, never a year: "BMR 1980 kcal", "Eat 2000 kcal".
const measurement =
  /\d[\d,.]*\s?(?:kcal|cal|calories|kg|lbs?|g|steps|min|minutes|%)(?![\p{L}\p{N}])/gu;
const institution = new RegExp(
  String
    .raw`\b([A-Z]{2,6})\b(?=\s+(?:fact ?sheets?|position (?:stands?|statements?)|consensus(?: statements?)?|(?:dietary |physical activity )?guidelines?|recommendations?))`,
  "g",
);

/** Lower-case words with accents removed ("Jäger" and "jager" are the same author). */
const words = (text: string) =>
  text.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase().split(/[^a-z0-9]+/).filter(Boolean);

type Scanned = Readonly<{ mention: StudyMention; phrase: string }>;

/** The studies a text names, each with the words of the text that name it. */
function scan(text: string): Scanned[] {
  const found: Scanned[] = [];
  const plain = text.replace(measurement, " ");
  const authorsOf = (raw: string) =>
    words(raw).filter((word) =>
      word !== "et" && word !== "al" && word !== "and" && !notAnAuthor.has(word)
    );
  const dated: [number, number][] = [];
  for (const match of plain.matchAll(authorYear)) {
    dated.push([match.index, match.index + match[0].length]);
    const authors = authorsOf(match[1]);
    if (authors.length > 0) {
      found.push({ mention: { authors, year: Number(match[2]) }, phrase: match[0].trim() });
    }
  }
  for (const match of plain.matchAll(etAl)) {
    // "Schoenfeld et al. (2017)" is one study, found above with its year.
    if (dated.some(([from, to]) => match.index >= from && match.index < to)) continue;
    const authors = authorsOf(match[1]);
    if (authors.length > 0) {
      found.push({ mention: { authors, year: null }, phrase: match[0].trim() });
    }
  }
  for (const match of plain.matchAll(institution)) {
    const initials = match[1].toLowerCase();
    if (!notAnInstitution.has(initials)) {
      found.push({
        mention: { authors: [initials], year: null, initials: true },
        phrase: match[0].trim(),
      });
    }
  }
  return found;
}

/** The studies a text names, by author words and year. */
export function studyMentions(text: string): StudyMention[] {
  return scan(text).map((entry) => entry.mention);
}

type Identity = Readonly<{
  authors: ReadonlySet<string>;
  titleWords: ReadonlySet<string>;
  /** Initials of the title's capitalised runs and its all-capitals words ("ISSN", "IOC"). */
  acronyms: ReadonlySet<string>;
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
  const label = source.label ?? "";
  const parts = words(id.replaceAll("_", " "));
  const at = parts.findIndex((part) => yearSegment.test(part));
  const labelYear = /\b((?:19|20)\d{2})\b/.exec(label)?.[1];
  return {
    authors: new Set(at === -1 ? parts.slice(0, 1) : parts.slice(0, at)),
    titleWords: new Set(words(label).filter((word) => word.length >= 3)),
    // Case matters here: "WHO" is an acronym in a title, "who" is a word in an excerpt.
    acronyms: new Set([
      ...acronymsOf(label),
      ...(label.match(/\b\p{Lu}{2,6}\b/gu) ?? []).map((word) => word.toLowerCase()),
    ]),
    year: at !== -1 ? Number(parts[at]) : labelYear ? Number(labelYear) : null,
    text: ` ${words(source.text ?? "").join(" ")} `,
  };
}

function names(mention: StudyMention, source: Identity): boolean {
  if (mention.year !== null && source.year !== null && mention.year !== source.year) return false;
  // An institution's initials name a source by its id or its title's acronyms, never by a word in
  // the excerpt ("The WHO guidelines" is not a source whose excerpt says "athletes who train").
  if (mention.initials) {
    return mention.authors.some((initials) =>
      source.authors.has(initials) || source.acronyms.has(initials)
    );
  }
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

/** The shown sources the text names, each with the words of the text that name it. */
export function namedShownPhrases(
  text: string,
  shown: ShownSources,
): { id: string; phrase: string }[] {
  const identities = Object.entries(shown).map(([id, source]) => ({
    id,
    identity: identityOf(id, source),
  }));
  return scan(text).flatMap((entry) =>
    identities.filter(({ identity }) => names(entry.mention, identity)).map(({ id }) => ({
      id,
      phrase: entry.phrase,
    }))
  );
}

/** The studies the text names that no shown source matches. */
export function unshownStudies(text: string, shown: ShownSources): StudyMention[] {
  return unshownStudyPhrases(text, shown).map((entry) => entry.mention);
}

/** The same, each with the words of the text that name it (for a repair that quotes them). */
export function unshownStudyPhrases(text: string, shown: ShownSources): Scanned[] {
  const identities = Object.entries(shown).map(([id, source]) => identityOf(id, source));
  return scan(text).filter((entry) =>
    !identities.some((identity) => names(entry.mention, identity))
  );
}
