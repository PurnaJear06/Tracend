// Sources behind the goal phase review. Each DOI and title was checked against Crossref and the
// PubMed record on 2026-10-17; the rules in thresholds.ts name these ids. Tracend's own values
// (where no source gives a number) are marked in_house there and listed in the handoff for the
// owner or a coach to review.
import type { Source } from "../standard/sources.ts";

const source = (entry: Source): Source => Object.freeze(entry);

export const goalPhaseSources = Object.freeze({
  garthe_2011: source({
    id: "garthe_2011",
    label: "Garthe 2011",
    citation: "Garthe I, et al. Effect of two different weight-loss rates on body composition " +
      "and strength and power-related performance in elite athletes. Int J Sport Nutr Exerc " +
      "Metab. 2011;21(2):97-104.",
    doi: "10.1123/ijsnem.21.2.97",
    pmid: "21558571",
    pmcid: null,
    access: "abstract",
  }),
  helms_2014: source({
    id: "helms_2014",
    label: "Helms 2014",
    citation: "Helms ER, Aragon AA, Fitschen PJ. Evidence-based recommendations for natural " +
      "bodybuilding contest preparation: nutrition and supplementation. J Int Soc Sports Nutr. " +
      "2014;11:20.",
    doi: "10.1186/1550-2783-11-20",
    pmid: "24864135",
    pmcid: null,
    access: "full_text",
  }),
  byrne_2018: source({
    id: "byrne_2018",
    label: "Byrne 2018 (MATADOR)",
    citation: "Byrne NM, et al. Intermittent energy restriction improves weight loss efficiency " +
      "in obese men: the MATADOR study. Int J Obes. 2018;42(2):129-138.",
    doi: "10.1038/ijo.2017.206",
    pmid: "28925405",
    pmcid: null,
    access: "abstract",
  }),
  trexler_2014: source({
    id: "trexler_2014",
    label: "Trexler 2014",
    citation: "Trexler ET, Smith-Ryan AE, Norton LE. Metabolic adaptation to weight loss: " +
      "implications for the athlete. J Int Soc Sports Nutr. 2014;11:7.",
    doi: "10.1186/1550-2783-11-7",
    pmid: null,
    pmcid: null,
    access: "full_text",
  }),
  jensen_2014: source({
    id: "jensen_2014",
    label: "AHA/ACC/TOS 2013",
    citation: "Jensen MD, et al. 2013 AHA/ACC/TOS guideline for the management of overweight " +
      "and obesity in adults. Circulation. 2014;129(25 Suppl 2):S102-38.",
    doi: "10.1161/01.cir.0000437739.71477.ee",
    pmid: null,
    pmcid: null,
    access: "full_text",
  }),
  who_2004: source({
    id: "who_2004",
    label: "WHO Expert Consultation 2004",
    citation: "WHO Expert Consultation. Appropriate body-mass index for Asian populations and " +
      "its implications for policy and intervention strategies. Lancet. 2004;363(9403):157-163.",
    doi: "10.1016/S0140-6736(03)15268-3",
    pmid: null,
    pmcid: null,
    access: "abstract",
  }),
  tracend_in_house: source({
    id: "tracend_in_house",
    label: "Tracend in-house",
    citation: "Tracend's own value where the literature gives a range, not a rule. Listed in " +
      "docs/handoff/training-engine.md for owner or coach review.",
    doi: null,
    pmid: null,
    pmcid: null,
    access: "in_house",
  }),
});

export type GoalPhaseSourceId = keyof typeof goalPhaseSources;
