import type { LibrarySource } from "../../functions/_shared/library/types.ts";

// Supplements beyond protein, creatine and caffeine basics: the IOC consensus on supplement use and
// contamination, common creatine questions, creatine for vegetarians, beta-alanine, nitrate, BCAAs
// and the NIH fact sheet on what lacks evidence. Summaries are written in Tracend's own words from
// each source's full text; no source text is copied.

export const supplementSources: readonly LibrarySource[] = [
  {
    slug: "maughan_2018_ioc_supplements",
    label: "Maughan et al. 2018 (IOC)",
    title: "IOC consensus statement: dietary supplements and the high-performance athlete",
    authors: ["Maughan RJ", "Burke LM", "Dvorak J", "Larson-Meyer DE", "Peeling P", "Phillips SM"],
    year: 2018,
    doi: "10.1136/bjsports-2018-099027",
    url: "https://doi.org/10.1136/bjsports-2018-099027",
    licence: "CC-BY-NC-4.0",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: [
      "nutrition",
      "supplements",
      "safety",
      "performance",
      "creatine",
      "caffeine",
      "nitrate",
      "beta-alanine",
    ],
    evidenceLevel: "expert consensus statement",
    kind: "guideline",
    chosenBecause:
      "The leading independent statement on which supplements work and what can go wrong, for anyone asking whether they should take something. Summarised from the full text.",
    sections: [
      {
        title: "Where supplements fit",
        body:
          `An International Olympic Committee expert panel sees supplements as at most a small addition to a sound diet. They can correct a deficiency (iron, calcium and vitamin D are the usual ones, and vitamin B12 for vegans), provide energy and nutrients conveniently (sports drinks, gels, bars, protein), or claim to improve performance directly or indirectly. The panel advises a full nutrition assessment before deciding, ideally with a sports nutrition professional.`,
      },
      {
        title: "What has good evidence",
        body:
          `Only a few performance supplements have enough support to suggest marginal gains: caffeine, creatine monohydrate, nitrate, sodium bicarbonate and possibly beta-alanine. Responses vary widely between people, so anything used for competition should be tried in training first. Caffeine usually gives its full benefit at 3 to 6 mg per kg, and side effects become more common at 9 mg per kg or more. Protein helps lean mass gain alongside resistance training. For most products sold as fat burners there is no evidence at all, and high doses of single antioxidants such as vitamins C and E may blunt training adaptations.`,
      },
      {
        title: "Risks and contamination",
        body:
          `In most countries supplements are regulated like foods, so makers need not prove that claims are true, that products are safe, or that labels match contents. Products have contained undeclared stimulants, anabolic steroids, SARMs, diuretics and other banned drugs, sometimes at medicinal doses; an early survey found undeclared steroid precursors in about 15 percent of over 600 products. Under anti-doping rules an athlete is responsible even for an unknowing intake, and traces too small to have any effect can still give a positive test. Third-party testing schemes reduce but cannot remove this risk.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `Written for elite athletes, but the principles suit any lifter: food, training and sleep come first, very few products add anything, and none is required. Anyone competing in a drug-tested sport should use only third-party tested products, if any. The doses in the statement's tables are not reproduced here; see the Kreider 2017, Guest 2021, Trexler 2015 and Senefeld 2020 entries.`,
      },
    ],
  },
  {
    slug: "antonio_2021_creatine_questions",
    label: "Antonio et al. 2021",
    title:
      "Common questions and misconceptions about creatine supplementation: what does the scientific evidence really show?",
    authors: ["Antonio J", "Candow DG", "Forbes SC", "Gualano B", "Jagim AR", "Kreider RB"],
    year: 2021,
    doi: "10.1186/s12970-021-00412-w",
    url: "https://doi.org/10.1186/s12970-021-00412-w",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["nutrition", "creatine", "supplements", "safety", "women", "older-adults"],
    evidenceLevel: "expert review of published trials",
    kind: "paper",
    chosenBecause:
      "Answers the worries people raise before trying creatine (water, kidneys, hair, fat, loading), complementing the Kreider 2017 entry. Summarised from the full text.",
    sections: [
      {
        title: "Common worries",
        body:
          `A panel of creatine researchers answered frequent questions. Water: loading at about 20 g a day usually adds 1 to 3 kg in the first days, mostly water, but longer studies mostly show no change in body water relative to muscle. Creatine is not an anabolic steroid. Kidneys: in healthy people, recommended doses have not harmed kidney function, though creatine (like meat) can raise creatinine on blood tests without meaning damage. Hair loss: the idea comes from one study of rugby players whose DHT rose within normal limits; it has not been repeated and no study has reported hair loss. Cramping and dehydration are not supported; a season-long study of college football players in hot conditions found fewer cramps in creatine users. Creatine does not increase fat mass.`,
      },
      {
        title: "Dosing and forms",
        body:
          `Loading is optional. Either 20 to 25 g a day for 5 to 7 days in servings of 10 g or less (larger servings can upset the gut), then 3 to 5 g a day, or simply 3 to 5 g a day (about 0.1 g per kg), which reaches similar muscle levels after about 4 weeks. Creatine monohydrate remains the best supported form; other forms have not proved superior. Creatine breaks down in liquids, so ready-made drinks carry little. Benefits are reported in women and, mainly when combined with resistance training, in older adults.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `Most authors have financial ties to the creatine industry, including advisory roles with a creatine manufacturer, so this should be read alongside independent sources such as the Maughan 2018 IOC entry, which also rates creatine as well supported. The sections on children and pregnancy are outside Tracend's scope and are not summarised. Tracend's reading: creatine is optional, low risk for healthy adults at 3 to 5 g a day, and anyone having blood tests can mention it to their clinician.`,
      },
    ],
  },
  {
    slug: "kaviani_2020_creatine_vegetarians",
    label: "Kaviani et al. 2020",
    title:
      "Benefits of Creatine Supplementation for Vegetarians Compared to Omnivorous Athletes: A Systematic Review",
    authors: ["Kaviani M", "Shaw K", "Chilibeck PD"],
    year: 2020,
    doi: "10.3390/ijerph17093041",
    url: "https://doi.org/10.3390/ijerph17093041",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["nutrition", "creatine", "supplements", "vegetarian", "plant-protein", "strength"],
    evidenceLevel: "systematic review (9 studies in 11 papers)",
    kind: "paper",
    chosenBecause:
      "Vegetarians and vegans eat almost no creatine, so this answers whether creatine matters more for them, a common question in India and among plant-based lifters. Summarised from the full text.",
    sections: [
      {
        title: "Why vegetarians differ",
        body:
          `The body makes about 1 g of creatine a day and meat eaters get roughly another gram from food; vegans get almost none. Studies find creatine about 50 percent lower in the plasma of vegetarians and total creatine about 10 to 15 percent lower in thigh muscle, though not lower in the brain or calf muscle. The reviewers searched two databases up to April 2020 and included 9 studies of creatine supplements in vegetarians.`,
      },
      {
        title: "Findings",
        body:
          `Supplements raised creatine in vegetarians' muscle and blood, often to higher levels than in omnivores given the same dose. In vegetarians they improved lean tissue mass, type II fibre size, strength, muscular endurance, sprint cycling power and, in two studies, memory. Whether vegetarians gain more than omnivores was mixed: the one trial in recreational athletes, which added a resistance training programme of about two months, found greater lean mass and work gains in the vegetarians, while short sprint studies did not. In one trial of women who switched to a vegetarian diet, just 1 g a day kept muscle creatine from falling over three months, while it fell about 15 percent on placebo. Most creatine is made synthetically, so it suits vegans, though capsules may contain gelatin.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `Most studies were small, short and in non-athletes, and most carried some or high risk of bias. Tracend's reading: for vegetarian and vegan lifters creatine has a clearer reason than most supplements, at the usual 3 to 5 g a day (see the Antonio 2021 entry), but it remains optional, not a requirement of a plant-based diet.`,
      },
    ],
  },
  {
    slug: "trexler_2015_beta_alanine",
    label: "Trexler et al. 2015 (ISSN)",
    title: "International society of sports nutrition position stand: Beta-Alanine",
    authors: ["Trexler ET", "Smith-Ryan AE", "Stout JR", "Hoffman JR", "Wilborn CD", "Sale C"],
    year: 2015,
    doi: "10.1186/s12970-015-0090-y",
    url: "https://doi.org/10.1186/s12970-015-0090-y",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["nutrition", "supplements", "beta-alanine", "performance", "safety"],
    evidenceLevel: "position stand",
    kind: "position_stand",
    chosenBecause:
      "Beta-alanine is in most pre-workout products and causes the tingling people ask about, so Coach needs to know what it does and does not do. Summarised from the full text.",
    sections: [
      {
        title: "How it works and how it is taken",
        body:
          `Beta-alanine raises muscle carnosine, which buffers the acid that builds up in hard efforts. It works by build-up, not on the day: 4 to 6 g a day, split into doses of 2 g or less, raises carnosine by about 20 to 30 percent after 2 weeks and about 40 to 60 percent after 4. Taking it with meals may help. Levels take about 6 to 15 weeks to fall back after stopping. A single 2 to 4 g serving in a pre-workout drink is therefore unlikely to explain any effect felt that day.`,
      },
      {
        title: "What it helps",
        body:
          `Benefits are clearest in continuous high-intensity efforts lasting about 1 to 4 minutes, especially tests to exhaustion, with smaller effects in time trials and little or none in efforts under a minute. Modest benefits appear up to about 25 minutes, with no consistent effect beyond. In resistance training it may allow a little more volume and less fatigue, but no added strength gain has been shown. Adding it to creatine or sodium bicarbonate may give a small extra benefit.`,
      },
      {
        title: "Safety",
        body:
          `The only reported side effect is tingling of the skin, mostly on the face, neck and hands, after single doses above about 800 mg; it is harmless and fades within 60 to 90 minutes. Splitting the dose (for example 1.6 g at a time) or using a sustained-release form reduces it. It appears safe in healthy people at recommended doses, but there are no safety data beyond one year.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `Most relevant to sustained hard efforts such as high-repetition sets, intervals or a 2,000 metre row; of little use for heavy, low-repetition strength work. Tracend's reading: optional, worth it only for someone who wants a small edge in those efforts and accepts the tingle.`,
      },
    ],
  },
  {
    slug: "senefeld_2020_nitrate",
    label: "Senefeld et al. 2020",
    title: "Ergogenic Effect of Nitrate Supplementation: A Systematic Review and Meta-analysis",
    authors: ["Senefeld JW", "Wiggins CC", "Regimbal RJ", "Dominelli PB", "Baker SE", "Joyner MJ"],
    year: 2020,
    doi: "10.1249/mss.0000000000002363",
    url: "https://doi.org/10.1249/mss.0000000000002363",
    licence: "CC-BY-NC-ND-4.0",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["nutrition", "supplements", "nitrate", "performance", "cardio", "sex-differences"],
    evidenceLevel: "systematic review and meta-analysis (80 crossover trials, about 1,300 adults)",
    kind: "paper",
    chosenBecause:
      "Beetroot juice is the best-known food-based performance aid, and this is the largest analysis of who it helps and how to take it. Summarised from the full text.",
    sections: [
      {
        title: "What the review did",
        body:
          `The authors pooled 80 placebo-controlled crossover studies of dietary nitrate (mostly beetroot juice) in healthy adults aged 18 to 40, with 1,179 men and 156 women, published from 2009 to 2019. Doses ranged widely, taken 1 to 15 days, and performance was measured in time trials, tests to exhaustion and fatigue tests, mostly in cycling and running.`,
      },
      {
        title: "Findings",
        body:
          `Nitrate improved performance overall, but the effect was small (effect size about 0.17), which is why about two thirds of single studies found no difference; none found harm. The benefit was seen in recreationally active and moderately fit people but not in highly fit endurance athletes (VO2max above about 65 ml per kg per minute), and was larger in tests to exhaustion than in time trials and in efforts under about 15 minutes. Studies of women alone showed no effect, but there were only six, so the question is open. No benefit was seen at 5 mmol a day or less; doses of about 5 to 25 mmol taken 2 to 3.5 hours before exercise worked best, and one day was enough.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `The authors put the typical gain at about 3 percent in a race-like test, meaningful for competition but easy to miss day to day. Nitrate is turned into its active form by mouth bacteria, and only about half the studies reported asking people to avoid antibacterial mouthwash and chewing gum, which may add to the variation. Little of the evidence concerns lifting. Tracend's reading: an optional food-based aid for endurance or repeated hard efforts in recreational athletes; leafy greens and beetroot supply nitrate anyway, and the NIH ODS 2024 entry covers its safety.`,
      },
    ],
  },
  {
    slug: "wolfe_2017_bcaa",
    label: "Wolfe 2017",
    title: "Branched-chain amino acids and muscle protein synthesis in humans: myth or reality?",
    authors: ["Wolfe RR"],
    year: 2017,
    doi: "10.1186/s12970-017-0184-9",
    url: "https://doi.org/10.1186/s12970-017-0184-9",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["nutrition", "supplements", "protein", "hypertrophy"],
    evidenceLevel: "narrative review",
    kind: "paper",
    chosenBecause:
      "BCAAs are among the most bought supplements, and this explains why on their own they are unlikely to build muscle. Summarised from the full text.",
    sections: [
      {
        title: "The argument",
        body:
          `Branched-chain amino acids (leucine, isoleucine and valine) are three of the nine essential amino acids, and building new muscle protein needs all nine. Between meals, muscle breaks down protein about 30 percent faster than it builds it, and the only source of the other six essential amino acids is that breakdown. So BCAAs alone can at best help recycle amino acids more efficiently; the author estimates a ceiling of about a 15 percent rise in muscle protein building, never a net gain of muscle.`,
      },
      {
        title: "The human evidence",
        body:
          `The author found no human study measuring muscle protein building after drinking BCAAs alone. Two small studies infused BCAAs into a vein, for 3 hours in 10 people and 16 hours in 8. In both, muscle protein building fell rather than rose, along with breakdown, and muscle stayed in net loss. Signals inside muscle that switch on protein building do not raise it when the other essential amino acids are missing. Things differ with protein: adding 5 g of BCAAs to a small 6.25 g serving of whey raised protein building to about the level of 25 g of whey.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `This is one author's analysis of mostly theoretical and short-term evidence, not a trial of long-term muscle growth, and the author declares funding from food companies and shares in a nutrition company. The NIH ODS 2024 entry notes a few short studies in which 10 to 14 g a day went with greater gains, but judges the evidence inconsistent overall. Tracend's reading: for someone already eating enough protein, BCAAs add little; money is better spent on complete protein from food or a protein powder.`,
      },
    ],
  },
  {
    slug: "nih_ods_2024_exercise_supplements",
    label: "NIH ODS 2024",
    title:
      "Dietary Supplements for Exercise and Athletic Performance - Health Professional Fact Sheet",
    authors: ["NIH Office of Dietary Supplements"],
    year: 2024,
    doi: null,
    url: "https://ods.od.nih.gov/factsheets/ExerciseAndAthleticPerformance-HealthProfessional/",
    licence: "public-domain-us-gov",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["nutrition", "supplements", "safety", "performance", "guidelines"],
    evidenceLevel: "government fact sheet summarising published research",
    kind: "summary",
    chosenBecause:
      "A neutral, regularly updated overview of popular sports supplements, especially useful for the many that lack evidence. Summarised from the full text.",
    sections: [
      {
        title: "The overall message",
        body:
          `The US National Institutes of Health fact sheet (updated April 2024) says a nutritionally adequate diet and enough fluid come first, and a few supplements might help only on top of that. Most studies are small and short, in young, mostly male, well-conditioned athletes, so benefits for recreational exercisers are often unclear. Multi-ingredient products and proprietary blends have rarely been tested as sold, and sellers rarely fund research of publishable quality.`,
      },
      {
        title: "Ingredients with little or no support",
        body:
          `The sheet finds little or no support for arginine (2 to 20 g a day had little or no effect), citrulline, glutamine, ribose, DHEA, tribulus and deer antler velvet, and no expert consensus for HMB or tart cherry. For BCAAs, a few short studies of 10 to 14 g a day hint at extra gains, but overall they have not consistently improved performance, muscle or recovery beyond enough complete protein. DHEA and the IGF-1 in deer antler velvet are banned in tested sport, and claimed testosterone boosters carry a high contamination risk.`,
      },
      {
        title: "Regulation and safety",
        body:
          `In the US, supplements need no approval before sale, and makers are responsible for safety and truthful labels. Bodybuilding products are among those most often found to contain undeclared steroids, SARMs or prescription drugs, which can harm health and cause failed drug tests. Third-party certification (NSF Certified for Sport, Informed-Choice, BSCG) gives some independent assurance. Some ingredients interact with medicines, so anyone on regular medication should check with a clinician or pharmacist. Beetroot juice of about two cups a day for several weeks raised no safety concerns.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `A US federal work in the public domain, so short quotation with attribution is allowed. Its regulatory details are American; the science applies elsewhere. Tracend's reading: Coach can explain what an ingredient is claimed to do and what the evidence shows, but never recommends one as necessary.`,
      },
    ],
  },
];
