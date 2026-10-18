import type { CoachContextContributor } from "../coach_context/host.ts";
import {
  coachingPrinciplesText,
  coachingPrinciplesVersion,
} from "../../../library/coaching_principles.ts";

// The coaching principles digest as a Contract 7 contributor for the stable (cached) prompt
// prefix. It is fixed text without athlete data. Coach chat registers it first (A9, lead decision
// 2026-10-17): the digest shapes every reply, and its figures (for example 1.6 g of protein per kg)
// count as given to the numbers check. E3 adds retrieval on top of it.
//
// The authored text names its sources inline in square brackets, so a reviewer (and the test) can
// trace every line. Coach sees it without them: only excerpts retrieved this turn are citable, and
// an id copied from the digest into a reply was a citation the reply guard had to refuse.

/** Largest size the digest may reach: 1,800 tokens at four characters a token. */
export const coachingPrinciplesMaxChars = 7_200;
/** Smallest sensible size: 1,200 tokens at four characters a token. */
export const coachingPrinciplesMinChars = 4_800;

const citationGroup = /\[([a-z0-9_.;\s-]+)\]/g;

/** The text without its inline source ids (and the space before each). */
export function withoutSourceIds(text: string): string {
  return text.replace(/ ?\[[a-z0-9_.;\s-]+\]/g, "");
}

export const coachingPrinciples = Object.freeze({
  version: coachingPrinciplesVersion,
  /** The authored digest, with its source ids. */
  authoredText: coachingPrinciplesText,
  /** What Coach is shown: the digest without the ids. */
  text: withoutSourceIds(coachingPrinciplesText),
});

/** Manifest keys cited inline, as [key] or [key; key]. */
export function citedSourceKeys(text: string): string[] {
  const keys = new Set<string>();
  for (const group of text.matchAll(citationGroup)) {
    for (const key of group[1].split(";")) {
      const trimmed = key.trim();
      if (trimmed !== "") keys.add(trimmed);
    }
  }
  return [...keys];
}

export const coachingPrinciplesContributorId = "coaching_principles";

export const coachingPrinciplesContributor: CoachContextContributor = Object.freeze({
  id: coachingPrinciplesContributorId,
  slot: "stable",
  budgetChars: coachingPrinciplesMaxChars,
  render: () => Promise.resolve(coachingPrinciples.text),
});
