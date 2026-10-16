// Sources behind Tracend's coaching standard (decision D3): guidelines, open
// papers and Tracend's own summaries. Every rule value in this folder names at
// least one of these. Each entry and every value that cites it were checked
// against its PubMed abstract on 2026-10-15; ACSM 2026's values were also
// checked in its full text. `access` says what anyone can read for free:
// "full_text" is open in PubMed Central, "abstract" is the abstract only.
// Paid course material (NASM, ACE, K11) is never a source.

export type SourceAccess = "full_text" | "abstract" | "in_house";

export type Source = Readonly<{
  id: string;
  /** Short label for notes and logs, e.g. "ACSM 2009". */
  label: string;
  citation: string;
  doi: string | null;
  pmid: string | null;
  pmcid: string | null;
  access: SourceAccess;
}>;

const source = (entry: Source): Source => Object.freeze(entry);

export const sources = Object.freeze({
  acsm_2009: source({
    id: "acsm_2009",
    label: "ACSM 2009",
    citation: "American College of Sports Medicine. Position stand: progression models in " +
      "resistance training for healthy adults. Med Sci Sports Exerc. 2009;41(3):687-708.",
    doi: "10.1249/MSS.0b013e3181915670",
    pmid: "19204579",
    pmcid: null,
    access: "abstract",
  }),
  acsm_2011: source({
    id: "acsm_2011",
    label: "ACSM 2011",
    citation: "Garber CE, et al. American College of Sports Medicine position stand: quantity " +
      "and quality of exercise for developing and maintaining cardiorespiratory, " +
      "musculoskeletal, and neuromotor fitness in apparently healthy adults. Med Sci Sports " +
      "Exerc. 2011;43(7):1334-59.",
    doi: "10.1249/MSS.0b013e318213fefb",
    pmid: "21694556",
    pmcid: null,
    access: "abstract",
  }),
  acsm_2026: source({
    id: "acsm_2026",
    label: "ACSM 2026",
    citation: "Currier BS, et al. American College of Sports Medicine position stand: " +
      "resistance training prescription for muscle function, hypertrophy, and physical " +
      "performance in healthy adults: an overview of reviews. Med Sci Sports Exerc. " +
      "2026;58(4):851-872.",
    doi: "10.1249/MSS.0000000000003897",
    pmid: "41843416",
    pmcid: "PMC12965823",
    access: "full_text",
  }),
  schoenfeld_2017: source({
    id: "schoenfeld_2017",
    label: "Schoenfeld 2017",
    citation: "Schoenfeld BJ, Ogborn D, Krieger JW. Dose-response relationship between weekly " +
      "resistance training volume and increases in muscle mass: a systematic review and " +
      "meta-analysis. J Sports Sci. 2017;35(11):1073-1082.",
    doi: "10.1080/02640414.2016.1210197",
    pmid: "27433992",
    pmcid: null,
    access: "abstract",
  }),
  schoenfeld_2021: source({
    id: "schoenfeld_2021",
    label: "Schoenfeld 2021",
    citation: "Schoenfeld BJ, Grgic J, Van Every DW, Plotkin DL. Loading recommendations for " +
      "muscle strength, hypertrophy, and local endurance: a re-examination of the repetition " +
      "continuum. Sports (Basel). 2021;9(2):32.",
    doi: "10.3390/sports9020032",
    pmid: "33671664",
    pmcid: "PMC7927075",
    access: "full_text",
  }),
  iversen_2021: source({
    id: "iversen_2021",
    label: "Iversen 2021",
    citation: "Iversen VM, Norum M, Schoenfeld BJ, Fimland MS. No time to lift? Designing " +
      "time-efficient training programs for strength and hypertrophy: a narrative review. " +
      "Sports Med. 2021;51(10):2079-2095.",
    doi: "10.1007/s40279-021-01490-1",
    pmid: "34125411",
    pmcid: "PMC8449772",
    access: "full_text",
  }),
  baz_valle_2022: source({
    id: "baz_valle_2022",
    label: "Baz-Valle 2022",
    citation: "Baz-Valle E, Balsalobre-Fernández C, Alix-Fages C, Santos-Concejero J. A " +
      "systematic review of the effects of different resistance training volumes on muscle " +
      "hypertrophy. J Hum Kinet. 2022;81:199-210.",
    doi: "10.2478/hukin-2022-0017",
    pmid: "35291645",
    pmcid: "PMC8884877",
    access: "full_text",
  }),
  pelland_2026: source({
    id: "pelland_2026",
    label: "Pelland 2026",
    citation: "Pelland JC, Remmert JF, Robinson ZP, Hinson SR, Zourdos MC. The resistance " +
      "training dose response: meta-regressions exploring the effects of weekly volume and " +
      "frequency on muscle hypertrophy and strength gains. Sports Med. 2026;56(2):481-505.",
    doi: "10.1007/s40279-025-02344-w",
    pmid: "41343037",
    pmcid: null,
    access: "abstract",
  }),
  singer_2024: source({
    id: "singer_2024",
    label: "Singer 2024",
    citation: "Singer A, et al. Give it a rest: a systematic review with Bayesian " +
      "meta-analysis on the effect of inter-set rest interval duration on muscle hypertrophy. " +
      "Front Sports Act Living. 2024;6:1429789.",
    doi: "10.3389/fspor.2024.1429789",
    pmid: "39205815",
    pmcid: "PMC11349676",
    access: "full_text",
  }),
  zourdos_2016: source({
    id: "zourdos_2016",
    label: "Zourdos 2016",
    citation: "Zourdos MC, et al. Novel resistance training-specific rating of perceived " +
      "exertion scale measuring repetitions in reserve. J Strength Cond Res. " +
      "2016;30(1):267-75.",
    doi: "10.1519/JSC.0000000000001049",
    pmid: "26049792",
    pmcid: null,
    access: "abstract",
  }),
  helms_2016: source({
    id: "helms_2016",
    label: "Helms 2016",
    citation: "Helms ER, Cronin J, Storey A, Zourdos MC. Application of the repetitions in " +
      "reserve-based rating of perceived exertion scale for resistance training. Strength " +
      "Cond J. 2016;38(4):42-49.",
    doi: "10.1519/SSC.0000000000000218",
    pmid: "27531969",
    pmcid: "PMC4961270",
    access: "full_text",
  }),
  robinson_2024: source({
    id: "robinson_2024",
    label: "Robinson 2024",
    citation: "Robinson ZP, et al. Exploring the dose-response relationship between estimated " +
      "resistance training proximity to failure, strength gain, and muscle hypertrophy: a " +
      "series of meta-regressions. Sports Med. 2024;54(9):2209-2231.",
    doi: "10.1007/s40279-024-02069-2",
    pmid: "38970765",
    pmcid: null,
    access: "abstract",
  }),
  tracend_in_house: source({
    id: "tracend_in_house",
    label: "Tracend in-house",
    citation: "Tracend coaching standard, in-house summary written in our own words. Used " +
      "where no open source sets the number: equipment increments, Tracend's existing " +
      "onboarding policy limits, and the joint-stress rating method. Each use explains its " +
      "reasoning in its basis.",
    doi: null,
    pmid: null,
    pmcid: null,
    access: "in_house",
  }),
});

export type SourceId = keyof typeof sources;

/**
 * One rule value with the sources it rests on and, in our own words, how the
 * value follows from them.
 */
export type Sourced<T> = Readonly<{
  value: T;
  sources: readonly SourceId[];
  basis: string;
}>;

export const sourced = <T>(
  value: T,
  sourceIds: readonly SourceId[],
  basis: string,
): Sourced<T> => Object.freeze({ value, sources: Object.freeze([...sourceIds]), basis });
