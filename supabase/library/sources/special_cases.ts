import type { LibrarySource } from "../../functions/_shared/library/types.ts";

// Training that does not fit the usual gym week: time off, equipment at home, older adults and
// the menstrual cycle (E2.1).

export const specialCaseSources: readonly LibrarySource[] = [
  {
    slug: "mujika_2001_muscular_detraining",
    label: "Mujika and Padilla 2001",
    title: "Muscular characteristics of detraining in humans",
    authors: ["Mujika I", "Padilla S"],
    year: 2001,
    doi: "10.1097/00005768-200108000-00009",
    url: "https://doi.org/10.1097/00005768-200108000-00009",
    licence: "Publisher copyright (no open licence found); stored as an own-words summary with citation",
    region: ["global"],
    topics: ["detraining", "training", "strength", "recovery", "time-off"],
    evidenceLevel: "narrative review",
    kind: "paper",
    chosenBecause:
      "Directly answers 'will I lose my gains if I cannot train for a couple of weeks?' for trained people.",
    sections: [
      {
        title: "What detraining is",
        body: `During periods when the training stimulus is too low, muscle detrains: it loses part of what training built. The review describes what happens inside muscle in people who stop training.`,
      },
      {
        title: "Strength and muscle size",
        body: `Strength performance is in general readily maintained for up to four weeks of inactivity. The exceptions are the eccentric force and sport-specific power of highly trained athletes, and strength that was gained recently, which may fall significantly. Muscle fibre size drops quickly in strength and sprint athletes, while force production declines slowly, in line with a fall in the muscle's electrical activity (EMG). The mix of fibre types stays unchanged during the first weeks.`,
      },
      {
        title: "Endurance-related changes",
        body: `The finer blood-supply and energy-production features of muscle start to change sooner: capillary density can fall within two to three weeks of inactivity, and oxygen extraction from the blood declines if the stoppage goes beyond three to eight weeks. These features remain above untrained levels in a detrained athlete but usually return to baseline in someone who trained only recently.`,
      },
      {
        title: "Practical reading and limits",
        body: `A break of one to three weeks is unlikely to erase strength in someone who has trained for a while, although muscle fibre size can shrink early and recently gained strength is the least secure. Longer breaks cost more. The review is about stopping altogether, so light activity during the break is not covered, and as a narrative review it is not a pooled analysis, so the effect for a particular lifter is an estimate.`,
      },
    ],
  },
  {
    slug: "bosquet_2013_training_cessation",
    label: "Bosquet et al. 2013",
    title: "Effect of training cessation on muscular performance: a meta-analysis",
    authors: ["Bosquet L", "Berryman N", "Dupuy O", "Mekary S", "Arvisais D", "Bherer L"],
    year: 2013,
    doi: "10.1111/sms.12047",
    url: "https://doi.org/10.1111/sms.12047",
    licence: "Publisher copyright (no open licence found); stored as an own-words summary with citation",
    region: ["global"],
    topics: ["detraining", "training", "strength", "time-off", "older-adults"],
    evidenceLevel: "meta-analysis (103 studies)",
    kind: "paper",
    chosenBecause:
      "The broadest pooled analysis of how much strength is lost when resistance training stops and who loses it fastest.",
    sections: [
      {
        title: "What the analysis did",
        body: `The authors searched seven databases and pooled 103 studies of resistance training cessation, grouping the results by training status, sex, age and the length of the break.`,
      },
      {
        title: "Results",
        body: `Stopping resistance training reduced every component of muscular performance: submaximal strength (a standardised effect of -0.62), maximal force (-0.46) and maximal power (-0.20), so the pooled effect was larger for submaximal strength than for power. The loss grew with the length of the break. It was larger in people over 65, and for maximal force and power it was larger in inactive people than in recreational athletes.`,
      },
      {
        title: "Practical reading and limits",
        body: `Stopping does cost strength, more so the longer it lasts, and for maximal force and power the cost was smaller in recreational athletes than in inactive people. The abstract does not give weeks or percentages, so this source cannot be used to quote how much is lost after a particular number of weeks. Taken with Mujika and Padilla, it supports saying that a couple of weeks off is unlikely to be a setback for a regular lifter.`,
      },
    ],
  },
  {
    slug: "lopes_2019_elastic_resistance",
    label: "Lopes et al. 2019",
    title:
      "Effects of training with elastic resistance versus conventional resistance on muscular strength: a systematic review and meta-analysis",
    authors: ["Lopes JSS", "Machado AF", "Micheletti JK", "de Almeida AC", "Cavina AP", "Pastre CM"],
    year: 2019,
    doi: "10.1177/2050312119831116",
    url: "https://doi.org/10.1177/2050312119831116",
    licence: "CC BY-NC (open access); own-words summary, no text copied",
    region: ["global"],
    topics: ["home-training", "equipment", "strength", "training", "minimal-equipment"],
    evidenceLevel: "systematic review and meta-analysis (8 studies)",
    kind: "paper",
    chosenBecause:
      "Shows that resistance bands, which fit in a bag, build strength about as well as weights, which is the main question when a person must train away from a gym.",
    sections: [
      {
        title: "What the review did",
        body: `Elastic resistance (tubes and bands) is cheap and easy to use, so the reviewers compared training with it against training with conventional equipment (weight machines and dumbbells) on muscular strength. They searched four databases up to December 2017 and pooled eight studies.`,
      },
      {
        title: "Results",
        body: `Neither method was better for lower-limb strength or upper-limb strength. The authors conclude that elastic resistance training can produce strength gains similar to conventional training, across different groups of people and different training protocols.`,
      },
      {
        title: "Practical reading and limits",
        body: `A person without a gym can reasonably expect to keep and even build strength with bands, and Coach should not call that second-best. Only eight studies were pooled, and the abstract does not say how muscle size changed. Another source in the library (Lopez 2021) covers lighter loads taken close to failure. This review does not test bodyweight training, so Coach should not claim bodyweight exercise works as well as weights on the strength of this paper alone.`,
      },
    ],
  },
  {
    slug: "fragala_2019_older_adults",
    label: "Fragala et al. 2019 (NSCA)",
    title: "Resistance training for older adults: position statement from the National Strength and Conditioning Association",
    authors: ["Fragala MS", "Cadore EL", "Dorgo S", "Izquierdo M", "Kraemer WJ", "Peterson MD"],
    year: 2019,
    doi: "10.1519/jsc.0000000000003230",
    url: "https://doi.org/10.1519/jsc.0000000000003230",
    licence: "Publisher copyright (no open licence found); stored as an own-words summary with citation",
    region: ["global"],
    topics: ["older-adults", "strength", "training", "safety", "guidelines"],
    evidenceLevel: "position statement",
    kind: "position_stand",
    chosenBecause:
      "The most thorough professional position on resistance training for older adults, so Coach can explain why lifting matters with age.",
    sections: [
      {
        title: "Why it matters",
        body: `Ageing, even without chronic disease, brings biological changes that can reduce skeletal muscle mass, strength and function, which lowers resilience and raises vulnerability to serious events. The position statement argues that countering muscle disuse through resistance training is a powerful way to fight the loss of strength and muscle and their consequences for physical function, mobility, independence, chronic disease management, wellbeing, quality of life and healthy life expectancy.`,
      },
      {
        title: "What it covers",
        body: `The statement gives evidence-based recommendations in four parts: programme design variables, physiological adaptations, functional benefits, and considerations for frailty, sarcopenia and other chronic conditions. Its stated aims are a more unified approach, promotion of the health and functional benefits, and reducing fears and barriers to starting.`,
      },
      {
        title: "Practical reading and limits",
        body: `This summary is written from the abstract, which gives no sets, loads or frequencies, so Tracend's rules and the shared training sources set those. The usable message for Coach is that older adults benefit from lifting and that fear and other barriers to starting are worth addressing kindly. Frailty, sarcopenia and chronic conditions are matters for a professional, and Coach does not plan rehabilitation. This is a peer-reviewed journal article; the association's courses and textbooks are not used.`,
      },
    ],
  },
  {
    slug: "mcnulty_2020_menstrual_cycle",
    label: "McNulty et al. 2020",
    title:
      "The effects of menstrual cycle phase on exercise performance in eumenorrheic women: a systematic review and meta-analysis",
    authors: ["McNulty KL", "Elliott-Sale KJ", "Dolan E", "Swinton PA", "Ansdell P", "Goodall S"],
    year: 2020,
    doi: "10.1007/s40279-020-01319-3",
    url: "https://doi.org/10.1007/s40279-020-01319-3",
    licence: "CC BY 4.0 (open access); own-words summary",
    region: ["global"],
    topics: ["women", "menstrual-cycle", "performance", "training", "individualisation"],
    evidenceLevel: "systematic review and network meta-analysis (78 studies)",
    kind: "paper",
    chosenBecause:
      "The best pooled answer to whether training should change across the menstrual cycle, which Coach is often asked.",
    sections: [
      {
        title: "What the review did",
        body: `Sex hormones change across the menstrual cycle, and results on whether this affects exercise performance conflict. The authors followed standard systematic review rules, searched four databases and included 78 studies of women with regular cycles, 51 of which could be pooled in a first analysis comparing the early follicular phase (the early part of the cycle) with all other phases. A broader network analysis compared every phase with every other using 73 studies.`,
      },
      {
        title: "Results",
        body: `Performance might be trivially lower in the early follicular phase than in the other phases, for both endurance and strength outcomes. The largest difference was between the early follicular and the late follicular phase, and it was small. The quality of the evidence was low.`,
      },
      {
        title: "Practical reading and limits",
        body: `Because the effect is trivial, the variation between studies is large and many included studies were of poor quality, the authors say general guidelines on exercise across the cycle cannot be made and recommend a personalised approach based on how each woman responds. Coach should therefore not change a plan by cycle day by default, but should listen when a woman reports a pattern in her own training. The review covers women with regular cycles, not irregular cycles, hormonal contraception or the menopause, and Coach should not give medical advice on these.`,
      },
    ],
  },
];
