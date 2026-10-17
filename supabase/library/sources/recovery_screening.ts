import type { LibrarySource } from "../../functions/_shared/library/types.ts";

// Recovery and sleep, and pre-exercise screening.

export const recoverySources: readonly LibrarySource[] = [
  {
    slug: "watson_2015_sleep_duration",
    label: "Watson et al. 2015 (AASM and SRS)",
    title:
      "Recommended amount of sleep for a healthy adult: a joint consensus statement of the American Academy of Sleep Medicine and Sleep Research Society",
    authors: ["Watson NF", "Badr MS", "Belenky G", "Bliwise DL", "Buxton OM", "Buysse D"],
    year: 2015,
    doi: "10.5665/sleep.4716",
    url: "https://doi.org/10.5665/sleep.4716",
    licence: "Publisher copyright (free to read in PubMed Central); stored as an own-words summary with citation",
    region: ["global"],
    topics: ["sleep", "recovery", "health", "guidelines"],
    evidenceLevel: "expert consensus statement (15 experts)",
    kind: "guideline",
    chosenBecause:
      "The clearest professional statement on how much sleep adults need, the baseline for any recovery advice.",
    sections: [
      {
        title: "The recommendation",
        body: `A panel of 15 sleep experts, using a structured rating process, agreed that adults should regularly sleep 7 or more hours a night to support good health. Sleeping less than 7 hours on a regular basis is linked with worse health, including weight gain and obesity, diabetes, high blood pressure, heart disease and stroke, depression and a higher risk of death. It is also linked with weaker immunity, more pain, worse performance, more errors and a higher risk of accidents.`,
      },
      {
        title: "Longer sleep",
        body: `Sleeping more than 9 hours regularly may be appropriate for young adults, people paying back a sleep debt and people who are ill. For other people it is unclear whether more than 9 hours carries any health risk. Anyone worried they sleep too little or too much should talk to a healthcare provider.`,
      },
      {
        title: "Practical reading and limits",
        body: `Seven hours is a floor for most adults, so a person regularly sleeping five or six hours is a good reason to tell them recovery will suffer, and to make sleep a first target before changing the training. The statement covers adults aged 18 to 60 and is about health generally, not about how sleep changes training results specifically. Coach should not diagnose sleep disorders.`,
      },
    ],
  },
  {
    slug: "walsh_2021_sleep_athlete",
    label: "Walsh et al. 2021",
    title: "Sleep and the athlete: narrative review and 2021 expert consensus recommendations",
    authors: ["Walsh NP", "Halson SL", "Sargent C", "Roach GD", "Nédélec M", "Gupta L"],
    year: 2021,
    doi: "10.1136/bjsports-2020-102025",
    url: "https://doi.org/10.1136/bjsports-2020-102025",
    licence: "Publisher copyright (no open licence found); stored as an own-words summary with citation",
    region: ["global"],
    topics: ["sleep", "recovery", "performance", "training"],
    evidenceLevel: "narrative review and expert consensus",
    kind: "paper",
    chosenBecause:
      "Covers sleep specifically for people who train: how common sleep problems are, what hurts performance and why one-size-fits-all targets are unwise.",
    sections: [
      {
        title: "What athletes face",
        body: `Athletes are especially likely to sleep too little (under seven hours) and to sleep poorly, for example with broken sleep. Reasons include training schedules, travel and competition, and non-sport factors such as stress and anxiety, and the review notes that female athletes are more at risk.`,
      },
      {
        title: "Effects on performance and health",
        body: `A night or more without sleep reduces athletic performance, but the effect of partial restriction over one to three nights, the more realistic case, is less clear. In the wider population, habitually sleeping under seven hours makes catching respiratory infections more likely. Much sleep research in athletes is weak: controls are poor, women are under-represented and the sleep measuring tools are questionable.`,
      },
      {
        title: "Recommendations",
        body: `The panel provides a toolbox for practitioners covering sleep education and screening, aimed at the known risk factors. It recommends an individualised approach that takes the athlete's own sense of how much sleep they need into account, instead of a blanket seven-to-nine-hour target. Napping and sleep extension might help but need more research.`,
      },
      {
        title: "Practical reading and limits",
        body: `Ask about and take sleep seriously, treat the number of hours as a guide, and weigh how the person feels. The paper is mainly about elite athletes, so conclusions for recreational lifters are an extrapolation. It is not a basis for diagnosing sleep disorders.`,
      },
    ],
  },
  {
    slug: "dupuy_2018_recovery_techniques",
    label: "Dupuy et al. 2018",
    title:
      "An evidence-based approach for choosing post-exercise recovery techniques to reduce markers of muscle damage, soreness, fatigue, and inflammation: a systematic review with meta-analysis",
    authors: ["Dupuy O", "Douzi W", "Theurot D", "Bosquet L", "Dugué B"],
    year: 2018,
    doi: "10.3389/fphys.2018.00403",
    url: "https://doi.org/10.3389/fphys.2018.00403",
    licence: "CC BY 4.0 (open access); own-words summary",
    region: ["global"],
    topics: ["recovery", "soreness", "training"],
    evidenceLevel: "systematic review and meta-analysis (99 studies)",
    kind: "paper",
    chosenBecause:
      "Compares popular recovery methods on soreness and fatigue, so Coach can say which ones have evidence and which do not.",
    sections: [
      {
        title: "What the review did",
        body: `The authors pooled 99 studies that tested recovery methods after exercise: active recovery, massage, compression garments, water immersion, contrast water therapy, cold exposure and others. They measured delayed-onset muscle soreness, perceived fatigue, muscle damage and inflammation markers.`,
      },
      {
        title: "Findings",
        body: `Active recovery, massage, compression garments, immersion, contrast water therapy and cryotherapy all reduced soreness. Massage appeared to be the most effective method for reducing soreness and perceived fatigue. Perceived fatigue also fell with compression garments, water immersion and massage. Massage and cold exposure were the most powerful for lowering inflammation markers, which fell by small amounts.`,
      },
      {
        title: "Practical reading and limits",
        body: `Several options can ease soreness for a day or two, so people can pick what they enjoy or can access. These effects are about how a person feels and about short-term markers; the review does not show that these methods improve long-term strength or muscle growth. Sleep, enough food and a sensible plan remain the foundation of recovery, and this entry does not cover treating injuries.`,
      },
    ],
  },
];

export const screeningSources: readonly LibrarySource[] = [
  {
    slug: "riebe_2015_screening",
    label: "Riebe et al. 2015 (ACSM)",
    title: "Updating ACSM's recommendations for exercise preparticipation health screening",
    authors: ["Riebe D", "Franklin BA", "Thompson PD", "Garber CE", "Whitfield GP", "Magal M"],
    year: 2015,
    doi: "10.1249/MSS.0000000000000664",
    url: "https://doi.org/10.1249/MSS.0000000000000664",
    licence: "Publisher copyright (no open licence); stored as an own-words summary with citation",
    region: ["global"],
    topics: ["screening", "safety", "health"],
    evidenceLevel: "expert roundtable consensus",
    kind: "guideline",
    chosenBecause:
      "The professional basis for deciding who should check with a doctor before starting or stepping up exercise, central to Tracend's safety gate.",
    sections: [
      {
        title: "Why the screening was changed",
        body: `Screening aims to spot people at raised risk of exercise-related sudden cardiac death or heart attack. The older approach sent many people to a doctor unnecessarily, which could itself discourage them from becoming active. A 2014 roundtable of the American College of Sports Medicine reviewed the evidence, noting that exercise is safe for most people, that exercise-related heart events are often preceded by warning signs and symptoms, and that the risk falls as people become more active and fit.`,
      },
      {
        title: "The three-factor model",
        body: `The new model asks about three things: the person's current level of physical activity, whether they have signs or symptoms or a known heart, metabolic or kidney disease, and the intensity of exercise they want to do. Listing cardiovascular risk factors is no longer part of the screening.`,
      },
      {
        title: "Practical reading and limits",
        body: `Someone who already exercises regularly and has no symptoms or known disease can usually continue; someone inactive who wants to start vigorous exercise, or anyone with warning symptoms or known disease, should speak with a healthcare professional first. Screening should be a short, non-diagnostic set of questions, and a flag is a reason to refer, not a verdict. Starting with moderate effort and building gradually is a sensible default.`,
      },
    ],
  },
  {
    slug: "bredin_2013_parq_plus",
    label: "Bredin et al. 2013",
    title:
      "PAR-Q+ and ePARmed-X+: new risk stratification and physical activity clearance strategy for physicians and patients alike",
    authors: ["Bredin SSD", "Gledhill N", "Jamnik VK", "Warburton DER"],
    year: 2013,
    doi: null,
    url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC3596208/",
    licence: "Publisher copyright (free to read in PubMed Central); stored as an own-words summary with citation",
    region: ["global"],
    topics: ["screening", "safety", "health"],
    evidenceLevel: "evidence-based clearance tool (systematic reviews and consensus)",
    kind: "guideline",
    chosenBecause:
      "Describes the widely used PAR-Q+ readiness questionnaire and its risk tiers, matching how Tracend's screening decides between proceed, moderate and refer.",
    sections: [
      {
        title: "Why it replaced the old questionnaire",
        body: `The original seven-question PAR-Q was deliberately cautious, which produced many false alarms and needless doctor referrals, excluded people under 15 and over 69 without a sound reason, and was often used inconsistently. The research team behind the new PAR-Q+ built it from systematic reviews of more than 540,000 articles and a structured consensus process, producing more than 60 evidence-based recommendations.`,
      },
      {
        title: "How the PAR-Q+ works",
        body: `A person answers seven questions. If every answer is no, they are cleared for unrestricted activity following the general guidelines. If any answer is yes, they answer follow-up questions about specific medical conditions. If all of those are no, they are cleared and receive advice on a safe plan. If any is yes, they are referred to a qualified exercise professional or to the electronic ePARmed-X+ for more detail, and may end up cleared with or without restrictions.`,
      },
      {
        title: "The risk continuum",
        body: `The process found that the risks of staying inactive far outweigh the small, short-lived risks of exercise. Low-risk people can exercise at low to moderate intensity with little supervision; intermediate-risk people should exercise with guidance from qualified professionals; high-risk people should exercise in medically supervised settings. Gradual progression of intensity is important at every level.`,
      },
      {
        title: "Practical reading and limits",
        body: `Screening is about deciding whether and how to start, with referral for anyone who flags a concern, not about diagnosing. It was designed for use with healthcare and fitness professionals; an app can use the same logic for a first check but must route concerning answers to a qualified professional.`,
      },
    ],
  },
];
