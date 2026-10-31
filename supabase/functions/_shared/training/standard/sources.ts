// Sources behind Tracend's coaching standard (decision D3): guidelines, open
// papers and Tracend's own summaries. Every rule value in this folder names at
// least one of these. Each entry and every value that cites it were checked
// against its PubMed abstract on 2026-10-15; ACSM 2026's values were also
// checked in its full text. Bell 2023, Hickmott 2022, Craven 2022, Saw 2016,
// Impellizzeri 2020 and WHO 2020 were added with the readiness rules (B4) and
// their ids, DOIs and open-access status checked against Europe PMC on 2026-10-23. Finucane 2020,
// Stiell 1997, Keogh 2017, Schoenfeld 2020, Haugen 2023 and Lopez 2021 were added with the pain
// check and joint rules (B5-1) and checked against Europe PMC on 2026-10-24. Coleman 2024,
// Schumann 2022 and Riebe 2015 were added with the deload and cardio rules (B5-3, B5-4) and
// checked against Europe PMC on 2026-10-24.
// `access` says what anyone can read for free: "full_text" is open in PubMed Central,
// "abstract" is the abstract only.
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
  moesgaard_2022: source({
    id: "moesgaard_2022",
    label: "Moesgaard 2022",
    citation: "Moesgaard L, Beck MM, Christiansen L, Aagaard P, Lundbye-Jensen J. Effects of " +
      "periodization on strength and muscle hypertrophy in volume-equated resistance " +
      "training programs: a systematic review and meta-analysis. Sports Med. " +
      "2022;52(7):1647-1666.",
    doi: "10.1007/s40279-021-01636-1",
    pmid: "35044672",
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
  refalo_2023: source({
    id: "refalo_2023",
    label: "Refalo 2023",
    citation: "Refalo MC, Helms ER, Trexler ET, Hamilton DL, Fyfe JJ. Influence of resistance " +
      "training proximity-to-failure on skeletal muscle hypertrophy: a systematic review " +
      "with meta-analysis. Sports Med. 2023;53(3):649-665.",
    doi: "10.1007/s40279-022-01784-y",
    pmid: "36334240",
    pmcid: "PMC9935748",
    access: "full_text",
  }),
  bell_2023: source({
    id: "bell_2023",
    label: "Bell 2023",
    citation: "Bell L, Strafford BW, Coleman M, Androulakis Korakakis P, Nolan D. Integrating " +
      "deloading into strength and physique sports training programmes: an international " +
      "Delphi consensus approach. Sports Med Open. 2023;9(1):87.",
    doi: "10.1186/s40798-023-00633-0",
    pmid: "37730925",
    pmcid: "PMC10511399",
    access: "full_text",
  }),
  hickmott_2022: source({
    id: "hickmott_2022",
    label: "Hickmott 2022",
    citation: "Hickmott LM, Chilibeck PD, Shaw KA, Butcher SJ. The effect of load and volume " +
      "autoregulation on muscular strength and hypertrophy: a systematic review and " +
      "meta-analysis. Sports Med Open. 2022;8(1):9.",
    doi: "10.1186/s40798-021-00404-9",
    pmid: "35038063",
    pmcid: "PMC8762534",
    access: "full_text",
  }),
  craven_2022: source({
    id: "craven_2022",
    label: "Craven 2022",
    citation: "Craven J, McCartney D, Desbrow B, Sabapathy S, Bellinger P, Roberts L, Irwin C. " +
      "Effects of acute sleep loss on physical performance: a systematic and meta-analytical " +
      "review. Sports Med. 2022;52(11):2669-2690.",
    doi: "10.1007/s40279-022-01706-y",
    pmid: "35708888",
    pmcid: "PMC9584849",
    access: "full_text",
  }),
  saw_2016: source({
    id: "saw_2016",
    label: "Saw 2016",
    citation: "Saw AE, Main LC, Gastin PB. Monitoring the athlete training response: subjective " +
      "self-reported measures trump commonly used objective measures: a systematic review. " +
      "Br J Sports Med. 2016;50(5):281-291.",
    doi: "10.1136/bjsports-2015-094758",
    pmid: "26423706",
    pmcid: "PMC4789708",
    access: "full_text",
  }),
  impellizzeri_2020: source({
    id: "impellizzeri_2020",
    label: "Impellizzeri 2020",
    citation: "Impellizzeri FM, Tenan MS, Kempton T, Novak A, Coutts AJ. Acute:chronic workload " +
      "ratio: conceptual issues and fundamental pitfalls. Int J Sports Physiol Perform. " +
      "2020;15(6):907-913.",
    doi: "10.1123/ijspp.2019-0864",
    pmid: "32502973",
    pmcid: null,
    access: "abstract",
  }),
  who_2020: source({
    id: "who_2020",
    label: "WHO 2020",
    citation: "Bull FC, Al-Ansari SS, Biddle S, et al. World Health Organization 2020 " +
      "guidelines on physical activity and sedentary behaviour. Br J Sports Med. " +
      "2020;54(24):1451-1462.",
    doi: "10.1136/bjsports-2020-102955",
    pmid: "33239350",
    pmcid: "PMC7719906",
    access: "full_text",
  }),
  finucane_2020: source({
    id: "finucane_2020",
    label: "Finucane 2020",
    citation: "Finucane LM, Downie A, Mercer C, et al. International framework for red flags for " +
      "potential serious spinal pathologies. J Orthop Sports Phys Ther. 2020;50(7):350-372.",
    doi: "10.2519/jospt.2020.9971",
    pmid: "32438853",
    pmcid: null,
    access: "abstract",
  }),
  stiell_1997: source({
    id: "stiell_1997",
    label: "Stiell 1997",
    citation:
      "Stiell IG, Wells GA, Hoag RH, et al. Implementation of the Ottawa knee rule for the " +
      "use of radiography in acute knee injuries. JAMA. 1997;278(23):2075-2079.",
    doi: "10.1001/jama.1997.03550230051036",
    pmid: "9403421",
    pmcid: null,
    access: "abstract",
  }),
  keogh_2017: source({
    id: "keogh_2017",
    label: "Keogh 2017",
    citation: "Keogh JWL, Winwood PW. The epidemiology of injuries across the weight-training " +
      "sports. Sports Med. 2017;47(3):479-501.",
    doi: "10.1007/s40279-016-0575-0",
    pmid: "27328853",
    pmcid: null,
    access: "abstract",
  }),
  schoenfeld_2020_rom: source({
    id: "schoenfeld_2020_rom",
    label: "Schoenfeld 2020",
    citation: "Schoenfeld BJ, Grgic J. Effects of range of motion on muscle development during " +
      "resistance training interventions: a systematic review. SAGE Open Med. 2020;8:2050312120901559.",
    doi: "10.1177/2050312120901559",
    pmid: "32030125",
    pmcid: "PMC6977096",
    access: "full_text",
  }),
  haugen_2023: source({
    id: "haugen_2023",
    label: "Haugen 2023",
    citation:
      "Haugen ME, Varvik FT, Larsen S, Haugen AS, van den Tillaar R, Bjornsen T. Effect of " +
      "free-weight vs. machine-based strength training on maximal strength, hypertrophy and jump " +
      "performance: a systematic review and meta-analysis. BMC Sports Sci Med Rehabil. " +
      "2023;15(1):103.",
    doi: "10.1186/s13102-023-00713-4",
    pmid: "37582807",
    pmcid: "PMC10426227",
    access: "full_text",
  }),
  lopez_2021: source({
    id: "lopez_2021",
    label: "Lopez 2021",
    citation: "Lopez P, Radaelli R, Taaffe DR, et al. Resistance training load effects on muscle " +
      "hypertrophy and strength gain: systematic review and network meta-analysis. Med Sci Sports " +
      "Exerc. 2021;53(6):1206-1216.",
    doi: "10.1249/MSS.0000000000002585",
    pmid: "33433148",
    pmcid: "PMC8126497",
    access: "full_text",
  }),
  coleman_2024: source({
    id: "coleman_2024",
    label: "Coleman 2024",
    citation: "Coleman M, Burke R, Augustin F, Piñero A, Maldonado J, Fisher JP, Israetel M, " +
      "Androulakis Korakakis P, Swinton P, Oberlin D, Schoenfeld BJ. Gaining more from doing " +
      "less? The effects of a one-week deload period during supervised resistance training on " +
      "muscular adaptations. PeerJ. 2024;12:e16777.",
    doi: "10.7717/peerj.16777",
    pmid: "38274324",
    pmcid: "PMC10809978",
    access: "full_text",
  }),
  schumann_2022: source({
    id: "schumann_2022",
    label: "Schumann 2022",
    citation: "Schumann M, Feuerbacher JF, Sünkeler M, Freitag N, Rønnestad BR, Doma K, " +
      "Lundberg TR. Compatibility of concurrent aerobic and strength training for skeletal " +
      "muscle size and function: an updated systematic review and meta-analysis. Sports Med. " +
      "2022;52(3):601-612.",
    doi: "10.1007/s40279-021-01587-7",
    pmid: "34757594",
    pmcid: "PMC8891239",
    access: "full_text",
  }),
  riebe_2015: source({
    id: "riebe_2015",
    label: "Riebe 2015",
    citation: "Riebe D, Franklin BA, Thompson PD, Garber CE, Whitfield GP, Magal M, Pescatello " +
      "LS. Updating ACSM's recommendations for exercise preparticipation health screening. " +
      "Med Sci Sports Exerc. 2015;47(11):2473-2479.",
    doi: "10.1249/MSS.0000000000000664",
    pmid: "26473759",
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
