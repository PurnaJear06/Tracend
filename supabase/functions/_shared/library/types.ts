// The research library's content model (decision D3). Content lives in
// supabase/library/sources/*.ts; chunk.ts turns it into the rows migrations load.

export type LibraryKind = "paper" | "guideline" | "position_stand" | "summary";

/** One titled section of a source's summary. Long sections are split into several chunks. */
export type LibrarySection = Readonly<{
  title: string;
  body: string;
}>;

/**
 * A source and the summary Tracend stores for it. Every summary is written in
 * Tracend's own words; no source's text is copied (see licence for what the source allows).
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
  /** What the source itself is published under, e.g. "CC BY 4.0". */
  licence: string;
  /** "global", or ISO 3166-1 alpha-2 codes when the source applies to one country. */
  region: readonly string[];
  topics: readonly string[];
  /** e.g. "systematic review and meta-analysis", "position stand". */
  evidenceLevel: string;
  kind: LibraryKind;
  /** Why the source earned a place; shown in the owner's review table. */
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
