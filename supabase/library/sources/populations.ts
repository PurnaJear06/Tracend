import type { LibrarySource } from "../../functions/_shared/library/types.ts";

// Training for particular people and situations: older lifters, women (sex differences, the
// menstrual cycle, oral contraceptives), bodyweight and home training, the minimal dose that keeps
// fitness, and travel. Healthy adults only. Summaries are written in Tracend's own words from each
// source's abstract or, for the open-access ones, its full text; no source text is copied.

export const populationSources: readonly LibrarySource[] = [
  {
    slug: "borde_2015_older_adults_dose_response",
    label: "Borde et al. 2015",
    title:
      "Dose-response relationships of resistance training in healthy old adults: a systematic review and meta-analysis",
    authors: ["Borde R", "Hortobágyi T", "Granacher U"],
    year: 2015,
    doi: "10.1007/s40279-015-0385-9",
    url: "https://doi.org/10.1007/s40279-015-0385-9",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["older-adults", "strength", "hypertrophy", "intensity", "volume", "training"],
    evidenceLevel: "systematic review and meta-analysis (25 randomised trials, 819 older adults)",
    kind: "paper",
    chosenBecause:
      "Gives the clearest numbers on how hard, how often and how long healthy older adults should lift for strength, which Coach needs when an older athlete asks what works. Summarised from the full text.",
    sections: [
      {
        title: "What the review did",
        body:
          `The authors pooled 25 randomised trials of resistance training in 819 healthy older adults (average age about 70, range 60 to 90), mostly previously sedentary people starting to lift. They measured strength and muscle size, and used meta-regression plus separate analyses of each training variable to see which settings went with the largest gains.`,
      },
      {
        title: "Findings",
        body:
          `Lifting produced large strength gains (standardised difference about 1.6) for both upper and lower body, but only small gains in muscle size (about 0.4, from nine studies).

Programme length, load and time under tension each predicted strength gains. Looking at one variable at a time, the largest effects came with programmes of about a year (50 to 53 weeks), loads of 70 to 79 percent of the one-repetition maximum, 2 to 3 sets per exercise, 7 to 9 repetitions per set, two sessions a week and about 6 seconds per repetition. A 60 second rest between sets looked best, but that rested on only two studies; most studies used 2 minutes.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `Older adults gain strength readily from moderately heavy, progressive lifting a couple of times a week, and gains keep building over months, so patience pays. Muscle size responds more slowly. Study quality was low (average 4.6 of 10 on the quality scale), results varied widely, and each variable was analysed on its own, so the 'best' values are a starting guide, not a tested combined programme. Tracend's rules set the actual numbers, and anyone frail or with a medical condition should be guided by a professional.`,
      },
    ],
  },
  {
    slug: "izquierdo_2021_icfsr_older_adults",
    label: "Izquierdo et al. 2021 (ICFSR)",
    title:
      "International exercise recommendations in older adults (ICFSR): expert consensus guidelines",
    authors: ["Izquierdo M", "Merchant RA", "Morley JE", "Anker SD", "Aprahamian I", "Arai H"],
    year: 2021,
    doi: "10.1007/s12603-021-1665-8",
    url: "https://doi.org/10.1007/s12603-021-1665-8",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["older-adults", "guidelines", "strength", "cardio", "training", "bodyweight"],
    evidenceLevel: "international expert consensus guideline",
    kind: "guideline",
    chosenBecause:
      "A broad international consensus on how to prescribe strength, power, aerobic and balance training for older adults, giving Coach concrete starting points beyond 'lifting helps'. Summarised from the full text.",
    sections: [
      {
        title: "What the guideline is",
        body:
          `An international group of 36 experts, published under the International Conference on Frailty and Sarcopenia Research (ICFSR) name, reviewed the evidence on exercise in older adults. Much of the document covers frailty, chronic disease and hospital care; this summary uses only the parts on healthy, independent older adults. Its starting points are that some exercise beats none, that advice should be individual and tied to a goal, and that a programme should combine strength, aerobic, balance and flexibility work, though a sedentary person may start with one type and add others.`,
      },
      {
        title: "Strength and power",
        body:
          `It recommends resistance training 2 to 3 times a week, starting with 1 to 2 sets and building to 2 to 3 sets of 8 to 12 repetitions, using about 6 to 10 exercises for the major muscles, both multi-joint and single-joint, with at least a day between sessions for the same muscles. Loads progressing towards 70 to 80 percent of the one-repetition maximum gave larger strength gains than light or moderate loads, with effort kept hard to very hard.

Power training, lifting fast and lowering under control without going to failure, is recommended because power declines earlier than strength. Rising quickly from a chair is a simple bodyweight start, with added load once bodyweight is no longer enough.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `Aerobic work can start at 5 to 10 minutes and build to 15 to 30 minutes, 3 to 7 days a week, and may be split into short bouts; harder intervals give the largest fitness gains. Balance work progresses from the hardest stance that can be held safely. These are expert recommendations built on trials, often in frail or clinical groups, so for a healthy older athlete they are a guide. Frailty, falls, disease and rehabilitation are for a professional; Coach does not plan them.`,
      },
    ],
  },
  {
    slug: "bauer_2013_prot_age_protein",
    label: "Bauer et al. 2013 (PROT-AGE)",
    title:
      "Evidence-based recommendations for optimal dietary protein intake in older people: a position paper from the PROT-AGE study group",
    authors: ["Bauer J", "Biolo G", "Cederholm T", "Cesari M", "Cruz-Jentoft AJ", "Morley JE"],
    year: 2013,
    doi: "10.1016/j.jamda.2013.05.021",
    url: "https://doi.org/10.1016/j.jamda.2013.05.021",
    licence: "CC-BY-NC-ND-4.0",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["older-adults", "protein", "nutrition", "guidelines"],
    evidenceLevel: "expert position paper (international study group)",
    kind: "position_stand",
    chosenBecause:
      "The reference recommendation on how much protein people over 65 need, so Coach can explain why older lifters need more than the general adult minimum. Summarised from the abstract only.",
    sections: [
      {
        title: "What the position paper is",
        body:
          `The European Union Geriatric Medicine Society, with other scientific organisations, appointed an international study group (PROT-AGE) to review protein needs with ageing. It argues that older adults need more protein than younger adults because their muscles respond less to the protein they eat and more of it is taken up by the gut and liver before it reaches the muscles, and because illness, common with age, raises needs further.`,
      },
      {
        title: "Recommendations for healthy older people",
        body:
          `To help people over 65 keep and regain lean mass and function, the group recommends an average intake of at least 1.0 to 1.2 g of protein per kg of body weight a day. For older people who exercise or are otherwise active it advises 1.2 g per kg a day or more, alongside endurance and resistance exercise at a level that is safe and tolerated for the individual.

It found the evidence not yet strong enough for specific advice on protein quality, the timing of protein or other supplements. The paper also covers older people with acute or chronic disease, which this summary leaves out.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `For a healthy older lifter, 1.2 g per kg a day is best read as a floor, not a target; the protein sources for people who train elsewhere in this library (Jäger 2017, Morton 2018) support somewhat higher intakes. This is a 2013 expert position summarised from the abstract only. The paper notes that people with severe kidney disease may need to limit protein, so anyone with kidney disease or another medical condition should get protein advice from a clinician, not from Coach.`,
      },
    ],
  },
  {
    slug: "roberts_2020_sex_differences_resistance_training",
    label: "Roberts et al. 2020",
    title: "Sex differences in resistance training: a systematic review and meta-analysis",
    authors: ["Roberts BM", "Nuckols G", "Krieger JW"],
    year: 2020,
    doi: "10.1519/JSC.0000000000003521",
    url: "https://doi.org/10.1519/JSC.0000000000003521",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["women", "sex-differences", "strength", "hypertrophy", "training"],
    evidenceLevel: "systematic review and meta-analysis (up to 23 studies per outcome)",
    kind: "paper",
    chosenBecause:
      "Directly answers whether women respond to lifting differently from men on the same programme, a frequent question behind requests for a 'women's programme'. Summarised from the abstract only.",
    sections: [
      {
        title: "What the review did",
        body:
          `The authors pooled studies in which young to middle-aged men and women followed the same resistance training programme, to see whether relative gains in muscle size and strength differed by sex. The protocol was registered in advance, and the analysis used methods suited to studies reporting several outcomes.`,
      },
      {
        title: "Findings",
        body:
          `Muscle growth did not differ between men and women (12 outcomes from 10 studies, effect size about 0.07, with no variation between studies).

Lower-body strength gains did not differ significantly either (23 studies). Upper-body strength gains, measured relative to starting strength, were larger in women, a moderate effect (17 studies). The authors suggest untrained women may have a greater capacity to improve upper-body strength, and say it is not yet clear whether this reflects nerves, muscle, learning the movement, or simply the short length of the studies.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `Men and women gain muscle and strength at similar relative rates on the same programme, so women do not need a separate kind of training; the same principles of effort, volume and progression apply, adjusted to the person. The findings are relative, not absolute, changes; the authors note the studies were short and the upper-body result may apply mainly to untrained women, and the strength results varied a lot between studies. This summary is from the abstract only. For cycle and contraceptive questions see the Colenso-Semple 2023, McNulty 2020 and Elliott-Sale 2020 entries.`,
      },
    ],
  },
  {
    slug: "colenso_semple_2023_menstrual_cycle_resistance",
    label: "Colenso-Semple et al. 2023",
    title:
      "Current evidence shows no influence of women's menstrual cycle phase on acute strength performance or adaptations to resistance exercise training",
    authors: ["Colenso-Semple LM", "D'Souza AC", "Elliott-Sale KJ", "Phillips SM"],
    year: 2023,
    doi: "10.3389/fspor.2023.1054542",
    url: "https://doi.org/10.3389/fspor.2023.1054542",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["women", "menstrual-cycle", "strength", "hypertrophy", "training"],
    evidenceLevel: "umbrella review (5 systematic reviews)",
    kind: "paper",
    chosenBecause:
      "Weighs the reviews behind 'cycle-syncing' strength training and explains why phase-based programmes are not yet evidence-based, so Coach can answer that question clearly. Summarised from the full text.",
    sections: [
      {
        title: "What the review did",
        body:
          `This umbrella review searched four databases in January 2022 for systematic reviews and meta-analyses on menstrual cycle phase and resistance training in healthy, naturally cycling women not using hormonal contraception. Five reviews qualified, three with meta-analyses, and each was rated for quality.`,
      },
      {
        title: "Findings",
        body:
          `The reviews disagreed, and the better ones found trivial or no effects of cycle phase on strength, including the McNulty 2020 network analysis in this library. The two reviews suggesting phase effects relied on few, very mixed studies, and one combined women on and off the pill. The two training trials behind 'train harder in the first half of the cycle' had design problems: they assumed regular 28-day cycles and did not confirm ovulation with a reliable test.

The authors stress that cycle length and the timing of ovulation vary widely between women, and between cycles in the same woman, so counting days is a poor guide to hormone levels.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `The authors conclude that there is no good evidence for building strength programmes around cycle phase, and that the plan should fit the individual. Symptoms do affect some women, so logging how training feels across the cycle is useful for spotting a personal pattern. This is an umbrella review whose authors state their opinion; the underlying studies are small and often poorly controlled, so a small effect cannot be ruled out. It does not cover hormonal contraception, irregular cycles or menopause, and Coach gives no medical advice on these.`,
      },
    ],
  },
  {
    slug: "elliott_sale_2020_oral_contraceptives_performance",
    label: "Elliott-Sale et al. 2020",
    title:
      "The effects of oral contraceptives on exercise performance in women: a systematic review and meta-analysis",
    authors: ["Elliott-Sale KJ", "McNulty KL", "Ansdell P", "Goodall S", "Hicks KM", "Thomas K"],
    year: 2020,
    doi: "10.1007/s40279-020-01317-5",
    url: "https://doi.org/10.1007/s40279-020-01317-5",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["women", "oral-contraceptives", "performance", "menstrual-cycle"],
    evidenceLevel: "systematic review and meta-analysis (42 studies, 590 women)",
    kind: "paper",
    chosenBecause:
      "The best pooled answer to whether taking the pill changes training performance, so Coach can reassure women on the pill without giving medical advice. Summarised from the full text.",
    sections: [
      {
        title: "What the review did",
        body:
          `The authors pooled 42 studies with 590 women. They compared women taking oral contraceptive pills with naturally menstruating women, matching the pill-free days with the early part of the cycle and the pill-taking days with the rest of it. They also compared performance on pill-taking days with the pill-free days in the same women. Strength and endurance outcomes were analysed together, and 83 percent of studies were rated moderate, low or very low quality.`,
      },
      {
        title: "Findings",
        body:
          `On average, women taking the pill may perform slightly worse than naturally menstruating women, but the difference was most likely trivial and varied a lot between studies. There was effectively no chance that pill users performed better.

Within pill users, performance was steady across the pill cycle: taking the pill or being on the pill-free days made almost no difference. Restricting the analysis to better-quality studies did not change these conclusions.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `The authors say the evidence does not justify general advice to use or avoid the pill for performance, and suggest an individual approach when performance matters most. For Coach this means a woman on the pill can train as normal, with no need to plan around pill days, and any pattern she notices herself is worth tracking. Most studies were small (about 10 per group) and observational. Choosing or changing contraception is a medical decision for the woman and her clinician; Coach does not advise on it.`,
      },
    ],
  },
  {
    slug: "kikuchi_2017_push_up_bench_press",
    label: "Kikuchi and Nakazato 2017",
    title: "Low-load bench press and push-up induce similar muscle hypertrophy and strength gain",
    authors: ["Kikuchi N", "Nakazato K"],
    year: 2017,
    doi: "10.1016/j.jesf.2017.06.003",
    url: "https://doi.org/10.1016/j.jesf.2017.06.003",
    licence: "CC-BY-NC-ND-4.0",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["bodyweight", "home-training", "minimal-equipment", "hypertrophy", "strength"],
    evidenceLevel: "randomised controlled trial (18 young men)",
    kind: "paper",
    chosenBecause:
      "A direct test of whether push-ups can build the chest and arms like bench pressing, the core question for anyone training at home without weights. Summarised from the full text.",
    sections: [
      {
        title: "What the study did",
        body:
          `Eighteen male university students with at least a year of recreational resistance training were randomly split into two groups for 8 weeks. One did bench press at 40 percent of their one-repetition maximum; the other did push-ups with the body position adjusted (for example on the knees) so the load matched that same 40 percent. Both did 3 sets to failure with 2 minutes' rest, twice a week, with supervision. Muscle thickness was measured by ultrasound at the chest, triceps and biceps.`,
      },
      {
        title: "Findings",
        body:
          `Chest and triceps thickness rose in both groups by similar amounts (chest by about 18 to 19 percent), with no difference between groups. Biceps thickness rose only in the bench press group. Bench press one-repetition maximum rose in both groups, from about 60 to 65 kg with bench press and from about 61 to 64 kg with push-ups, again with no significant difference between groups. Neither group improved upper-body power in a medicine ball throw.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `Push-ups taken close to failure can build the chest and triceps much like light bench pressing, so a person without equipment is not stuck. Difficulty can be adjusted by kneeling, raising the hands or feet, or adding a band or a weight on the back. The trial was small, only young men took part, it lasted 8 weeks, and diet was not controlled. Push-ups were matched to a light load, so this does not show bodyweight work equals heavy lifting for maximal strength.`,
      },
    ],
  },
  {
    slug: "wiedenmann_2025_older_adults_training_modalities",
    label: "Wiedenmann et al. 2025",
    title:
      "The effects of different resistance training modalities on muscle strength in community-dwelling older adults: a network meta-analysis",
    authors: ["Wiedenmann T", "Held S", "Morat T", "Rappelt L", "Isenmann E", "Berndsen E"],
    year: 2025,
    doi: "10.1159/000546346",
    url: "https://doi.org/10.1159/000546346",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["older-adults", "bodyweight", "equipment", "machines", "free-weights", "strength"],
    evidenceLevel: "network meta-analysis (102 trials, 4,754 older adults)",
    kind: "paper",
    chosenBecause:
      "The largest comparison of machines, free weights, bands and bodyweight training in older adults, so Coach can say honestly how well home and bodyweight options work. Summarised from the abstract only.",
    sections: [
      {
        title: "What the review did",
        body:
          `The authors searched three databases for controlled trials in community-dwelling older adults that compared types of resistance training with each other or with no training, on maximal strength. They included 102 trials with 4,754 people (average age about 70, range 63 to 87) and used a network meta-analysis, which ranks options even when they were not tested head to head.`,
      },
      {
        title: "Findings",
        body:
          `Every type of resistance training produced moderate to large strength gains compared with no training. Machine training had the largest effect (standardised difference about 1.3) and the most consistent results, followed by free weights (about 1.2, with a wide range of uncertainty), elastic bands (about 0.9), mixed programmes (about 0.9) and bodyweight training (about 0.7, also with a wide range).

The authors conclude that many types of training can bring large strength gains in older adults, and that once intensity, volume and programme length are adequate, the choice can rest on preference, enjoyment and practicality.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `Bodyweight and band training clearly work for older adults, so home training is a real option, but bodyweight alone gave the smallest estimated gain of the five types. Tracend's reading is that adding load or harder variations as exercises get easy keeps the work hard enough, in line with the authors' point that intensity and volume must be adequate. The ranking is uncertain because some estimates had wide ranges and different trials used different programmes. Only strength was analysed, not muscle size or daily function, and this summary is from the abstract only.`,
      },
    ],
  },
  {
    slug: "spiering_2021_minimal_dose_maintenance",
    label: "Spiering et al. 2021",
    title:
      "Maintaining physical performance: the minimal dose of exercise needed to preserve endurance and strength over time",
    authors: ["Spiering BA", "Mujika I", "Sharp MA", "Foulis SA"],
    year: 2021,
    doi: "10.1519/JSC.0000000000003964",
    url: "https://doi.org/10.1519/JSC.0000000000003964",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["minimal-dose", "time-efficient", "detraining", "intensity", "travel", "older-adults"],
    evidenceLevel: "narrative review",
    kind: "paper",
    chosenBecause:
      "Says how little training keeps fitness and strength during busy spells, travel or time pressure, a question Coach meets whenever life gets in the way. Summarised from the abstract only.",
    sections: [
      {
        title: "What the review did",
        body:
          `Most active people hit periods when time for exercise is short, and the goal becomes keeping what they have rather than improving. This brief narrative review gathered studies on the smallest frequency, volume and intensity of exercise that preserve endurance and strength in general populations, with notes on athletes and military personnel.`,
      },
      {
        title: "Findings",
        body:
          `In general populations, endurance was maintained for up to 15 weeks when training dropped to as few as two sessions a week, or when volume was cut by a third to two thirds (as little as 13 to 26 minutes a session), provided intensity, judged by exercising heart rate, stayed the same.

Strength and muscle size, at least in younger people, were maintained for up to 32 weeks with as little as one strength session a week and one set per exercise, provided the relative load stayed the same. Older people may need about two sessions a week and two to three sets per exercise to keep muscle size. There were too few data to give specific advice for athletes or military personnel.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `The authors' main message is that intensity is the variable to protect: during a busy spell, fewer and shorter sessions can hold fitness if they stay hard. That makes a short, intense maintenance week a reasonable option during travel or a crunch at work. This is a narrative review, not a pooled analysis, and the summary is from the abstract only. It fits the Mujika 2001 and Bosquet 2013 detraining entries: doing a little keeps far more than doing nothing.`,
      },
    ],
  },
  {
    slug: "janse_van_rensburg_2021_travel_jet_lag",
    label: "Janse van Rensburg et al. 2021",
    title: "Managing travel fatigue and jet lag in athletes: a review and consensus statement",
    authors: [
      "Janse van Rensburg DC",
      "Jansen van Rensburg A",
      "Fowler PM",
      "Bender AM",
      "Stevens D",
      "Sullivan KO",
    ],
    year: 2021,
    doi: "10.1007/s40279-021-01502-0",
    url: "https://doi.org/10.1007/s40279-021-01502-0",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["travel", "jet-lag", "sleep", "recovery", "performance"],
    evidenceLevel: "review and expert consensus statement (26 experts)",
    kind: "position_stand",
    chosenBecause:
      "The main consensus on travel fatigue and jet lag, so Coach can explain why training feels off after a long trip and how to plan the first days. Summarised from the full text.",
    sections: [
      {
        title: "What the statement is",
        body:
          `Twenty-six researchers and clinicians from 11 countries reviewed the evidence and voted on recommendations for athletes who travel. They separate two problems. Travel fatigue follows any long journey, whatever the direction, can build up with repeated trips, and comes from the journey itself: cramped seats, mild lack of oxygen in the cabin and sitting still. Jet lag follows fast travel across three or more time zones, when the body clock stays on home time; it is temporary and ends once the clock catches up.`,
      },
      {
        title: "What it says",
        body:
          `As a rule of thumb, the body clock adjusts by about half a day per time zone crossed when flying west and about a day per time zone when flying east. Common symptoms are daytime sleepiness, poor sleep, gut upset and poorer mental and physical performance, worse with more time zones. Air travel without crossing time zones did not measurably reduce performance in team athletes but did worsen mood, alertness and fatigue.

For travel fatigue the statement points to allowing a recovery window before hard training, protecting sleep, and using naps and caffeine after arrival. For jet lag, light is the main tool: timed exposure to and avoidance of bright light helps the clock shift, while badly timed light can make it worse.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `The evidence is thin: no trials exist for travel fatigue remedies and the jet lag evidence is low quality, so these are expert recommendations. A guide for a travelling user is to keep the first days lighter, train at times that feel good locally and protect sleep. The panel cautions that jet lag apps are unvalidated. Melatonin and sleep medicines are discussed in the statement, but whether to use them is for a doctor.`,
      },
    ],
  },
];
