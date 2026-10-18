// The research library's content model (decision D3). Content lives in
// supabase/library/sources/*.ts; chunk.ts turns it into the rows migrations load.

export type LibraryKind = "paper" | "guideline" | "position_stand" | "summary";

/** One titled section of a source's summary. Long sections are split into several chunks. */
export type LibrarySection = Readonly<{
  title: string;
  body: string;
}>;

/**
 * What a source is published under, as an SPDX identifier where one exists. Tracend is a
 * commercial app, so the licence decides what may be stored: an own-words summary with a
 * citation is fine for any of them, short verbatim text only for the licences in
 * verbatimLicences (library_content_test.ts enforces this).
 *
 * - `OGL-UK-3.0`: UK Open Government Licence v3.0.
 * - `public-domain-us-gov`: a work of the US federal government (17 U.S.C. 105).
 * - `proprietary`: publisher or author copyright with no open licence found, or a licence
 *   whose terms are unclear; summary and link only.
 */
export type LibraryLicence =
  | "CC-BY-2.0"
  | "CC-BY-3.0"
  | "CC-BY-4.0"
  | "CC-BY-NC-4.0"
  | "CC-BY-NC-ND-4.0"
  | "CC-BY-NC-SA-3.0-IGO"
  | "OGL-UK-3.0"
  | "public-domain-us-gov"
  | "proprietary";

/** The only licences that let Tracend quote a source word for word (with attribution). */
export const verbatimLicences: ReadonlySet<LibraryLicence> = new Set([
  "CC-BY-2.0",
  "CC-BY-3.0",
  "CC-BY-4.0",
  "OGL-UK-3.0",
  "public-domain-us-gov",
]);

/**
 * A source and the summary Tracend stores for it. Every summary is written in Tracend's own
 * words; no source's text is copied, and no full text is stored.
 */
export type LibrarySource = Readonly<{
  /** Stable key: re-loading a source replaces it by this key. */
  slug: string;
  /** Short label used in chunk headers and citations, e.g. "Jäger et al. 2017". */
  label: string;
  title: string;
  authors: readonly string[];
  year: number;
  doi: string | null;
  url: string;
  /** What the source itself is published under. */
  licence: LibraryLicence;
  /**
   * Whether the licence lets Tracend store short verbatim passages (with attribution). True
   * only for a licence in verbatimLicences; false keeps the entry to own-words summary.
   */
  verbatimAllowed: boolean;
  /** ISO date (YYYY-MM-DD) the entry was last checked against the source. */
  lastReviewed: string;
  /** Slug of a newer library source that replaces this one, when there is one. */
  supersededBy?: string;
  /** "global", or ISO 3166-1 alpha-2 codes when the source applies to one country. */
  region: readonly string[];
  topics: readonly string[];
  /** e.g. "systematic review and meta-analysis", "position stand". */
  evidenceLevel: string;
  kind: LibraryKind;
  /**
   * Why the source earned a place; shown in the owner's review table. Ends with what the
   * summary was written from, e.g. "Summarised from the full text." or "Summarised from the
   * abstract only."
   */
  chosenBecause: string;
  sections: readonly LibrarySection[];
}>;

/** A chunk ready to load: the context header is embedded and searched with the body. */
export type LibraryChunk = Readonly<{
  ordinal: number;
  section: string;
  header: string;
  body: string;
  tokenCount: number;
}>;
