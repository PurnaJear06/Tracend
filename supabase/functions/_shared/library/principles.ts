import type { CoachContextContributor } from "../coach_context/host.ts";
import {
  coachingPrinciplesText,
  coachingPrinciplesVersion,
} from "../../../library/coaching_principles.ts";

// The coaching principles digest as a Contract 7 contributor for the stable (cached) prompt
// prefix. It is fixed text without athlete data. It is NOT registered here: the registry
// changes with E3 (coach_context/registry.ts belongs to the lead).

/** Largest size the digest may reach: 1,800 tokens at four characters a token. */
export const coachingPrinciplesMaxChars = 7_200;
/** Smallest sensible size: 1,200 tokens at four characters a token. */
export const coachingPrinciplesMinChars = 4_800;

export const coachingPrinciples = Object.freeze({
  version: coachingPrinciplesVersion,
  text: coachingPrinciplesText,
});

/** Manifest keys cited inline, as [key] or [key; key]. */
export function citedSourceKeys(text: string): string[] {
  const keys = new Set<string>();
  for (const group of text.matchAll(/\[([a-z0-9_.;\s-]+)\]/g)) {
    for (const key of group[1].split(";")) {
      const trimmed = key.trim();
      if (trimmed !== "") keys.add(trimmed);
    }
  }
  return [...keys];
}

export const coachingPrinciplesContributor: CoachContextContributor = Object.freeze({
  id: "coaching_principles",
  slot: "stable",
  budgetChars: coachingPrinciplesMaxChars,
  render: () => Promise.resolve(coachingPrinciples.text),
});
