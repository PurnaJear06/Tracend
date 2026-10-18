import type { LibrarySource } from "../../functions/_shared/library/types.ts";

// Resistance-training programming: periodisation, effort ratings (RPE and repetitions in
// reserve) and autoregulation, proximity to failure, deloads, and tapering or peaking before a
// competition or a maximum test. Summaries are written in Tracend's own words from each
// source's abstract (and, for the open-access ones, its full text); no source text is copied.

export const programmingSources: readonly LibrarySource[] = [
  {
    slug: "williams_2017_periodised_strength",
    label: "Williams et al. 2017",
    title:
      "Comparison of periodized and non-periodized resistance training on maximal strength: a meta-analysis",
    authors: ["Williams TD", "Tolusso DV", "Fedewa MV", "Esco MR"],
    year: 2017,
    doi: "10.1007/s40279-017-0734-y",
    url: "https://doi.org/10.1007/s40279-017-0734-y",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["training", "periodisation", "strength", "progression"],
    evidenceLevel: "meta-analysis (18 studies, 81 effects)",
    kind: "paper",
    chosenBecause:
      "Answers whether a planned, varied programme beats repeating the same training every week for strength; read with the volume-equated Moesgaard 2022 entry. Summarised from the abstract only.",
    sections: [
      {
        title: "What the review did",
        body:
          `Periodisation means arranging training into planned phases in which load, repetitions and volume change over time. The authors pooled 18 studies, published between 1988 and 2015, that compared a periodised resistance programme with a non-periodised one and measured one-repetition maximum strength in the squat, bench press or leg press. The studies supplied 81 effect estimates, combined with a random-effects model.`,
      },
      {
        title: "Findings",
        body:
          `Periodised programmes raised one-repetition maximum more than non-periodised ones, by a moderate standardised effect of 0.43 (95 percent confidence interval 0.27 to 0.58). Four factors were linked to the size of that advantage: undulating models (where load and repetition targets change often) did better than other models, and the effect was larger in untrained participants, in longer studies and with more frequent training. The authors concluded that variation in the training stimulus looks important for building maximal strength.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `Planned variation in load and repetitions is a reasonable way to keep strength moving over months. The abstract does not describe matching total training volume between groups as an entry rule, so some of the advantage may reflect differences in the amount of work. The Moesgaard 2022 entry, which kept volume equal, found a smaller strength advantage, and the ACSM 2026 overview in this library found no consistent effect of periodisation across reviews. Coach should present periodisation as a useful structure, not a requirement; the plan's rules set the actual progression. This summary was written from the abstract only, so study quality and populations are not described here.`,
      },
    ],
  },
  {
    slug: "moesgaard_2022_periodisation_volume_equated",
    label: "Moesgaard et al. 2022",
    title:
      "Effects of periodization on strength and muscle hypertrophy in volume-equated resistance training programs: a systematic review and meta-analysis",
    authors: ["Moesgaard L", "Beck MM", "Christiansen L", "Aagaard P", "Lundbye-Jensen J"],
    year: 2022,
    doi: "10.1007/s40279-021-01636-1",
    url: "https://doi.org/10.1007/s40279-021-01636-1",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["training", "periodisation", "strength", "hypertrophy", "volume"],
    evidenceLevel: "systematic review and meta-analysis (35 studies)",
    kind: "paper",
    chosenBecause:
      "Separates the effect of how training is arranged from how much is done, which is the fair test of whether periodisation matters for strength and muscle. Summarised from the abstract only.",
    sections: [
      {
        title: "What the review did",
        body:
          `The authors kept only studies in which total training volume was the same in the programmes being compared, so any difference could be put down to how the work was arranged rather than how much there was. Thirty-five studies qualified. The two main comparisons were non-periodised against periodised training, and linear periodisation (gradual changes over weeks) against undulating periodisation (frequent daily or weekly changes in volume and intensity). Results were also split by training status. Other model comparisons had too few studies to analyse.`,
      },
      {
        title: "Findings",
        body:
          `For one-repetition maximum strength, periodised training beat non-periodised training by a small effect of 0.31 (95 percent confidence interval 0.04 to 0.57), and undulating beat linear by a similar 0.31 (0.02 to 0.61). The undulating advantage was seen in trained participants (0.61, with an interval starting at 0.00) but not in untrained ones (0.06).

For muscle size there was no clear difference, either between periodised and non-periodised training (0.13, interval minus 0.10 to 0.36) or between linear and undulating models (0.05). The authors suggest periodisation helps strength mainly through nervous-system adaptations rather than extra muscle.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `When the amount of work is equal, the way it is organised seems to matter a little for strength in trained lifters and not for muscle size. For someone chasing muscle, enough hard sets and steady progression count for more than the choice of model; a trained lifter aiming for a bigger one-repetition maximum may gain a small edge from regular variation in load and repetitions. The trained-lifter result is borderline, and the ACSM 2026 entry in this library did not find a consistent periodisation effect across reviews. This summary was written from the abstract only.`,
      },
    ],
  },
  {
    slug: "grgic_2017_linear_undulating_hypertrophy",
    label: "Grgic et al. 2017",
    title:
      "Effects of linear and daily undulating periodized resistance training programs on measures of muscle hypertrophy: a systematic review and meta-analysis",
    authors: ["Grgic J", "Mikulic P", "Podnar H", "Pedisic Z"],
    year: 2017,
    doi: "10.7717/peerj.3695",
    url: "https://doi.org/10.7717/peerj.3695",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["training", "periodisation", "hypertrophy", "volume", "progression"],
    evidenceLevel: "systematic review and meta-analysis (13 studies, 417 participants)",
    kind: "paper",
    chosenBecause:
      "Gives a plain answer to whether linear or daily undulating plans build more muscle, and its full text explains why volume and progression matter more than the model. Summarised from the full text.",
    sections: [
      {
        title: "What the review did",
        body:
          `The authors compared two common ways of organising training for muscle growth. Linear periodisation moves gradually, typically about every four weeks, towards heavier loads and less volume. Daily undulating periodisation changes the load and repetition target from one session to the next. They included 13 studies (417 participants, 303 of them in the two periodised groups) that matched volume between models, lasted at least six weeks and measured muscle size, either directly with imaging or indirectly through body composition. Studies averaged about 12 weeks.`,
      },
      {
        title: "Findings",
        body:
          `The pooled difference between models was essentially zero (standardised difference minus 0.02, 95 percent confidence interval minus 0.25 to 0.21). The result held when studies were removed one at a time, when the two studies that added aerobic training were dropped, and when results were split by measurement method or by study length. Methodological quality was moderate to high.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `For muscle growth, the choice between a linear and a daily undulating layout looks like a matter of preference; the authors point to training volume and progressive overload as what counts. Someone who likes watching the same lift climb week to week may prefer a linear plan, and someone who needs variety to stay consistent may prefer frequent changes. All but one study used untrained people, studies were short, and few used sensitive imaging such as ultrasound or MRI, so this says little about experienced lifters over a full year. The Moesgaard 2022 entry, which included later studies, also found no difference for muscle size.`,
      },
    ],
  },
  {
    slug: "helms_2018_rpe_vs_percentage",
    label: "Helms et al. 2018",
    title: "RPE vs. percentage 1RM loading in periodized programs matched for sets and repetitions",
    authors: ["Helms ER", "Byrnes RK", "Cooke DM", "Haischer MH", "Carzoli JP", "Johnson TK"],
    year: 2018,
    doi: "10.3389/fphys.2018.00247",
    url: "https://doi.org/10.3389/fphys.2018.00247",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["training", "autoregulation", "rpe", "rir", "strength", "intensity"],
    evidenceLevel: "randomised trial (21 trained men, 8 weeks)",
    kind: "paper",
    chosenBecause:
      "The first trial to compare choosing loads by effort rating with fixed percentages of a tested maximum, the core question behind effort-based plans. Summarised from the full text.",
    sections: [
      {
        title: "What the study did",
        body:
          `Twenty-one men aged 19 to 35, each with at least two years of lifting and a squat of at least 1.5 times and a bench press of at least 1.25 times body weight, squatted and bench pressed three times a week for eight weeks. Both groups followed the same daily undulating programme with identical exercises, sets, repetitions and rest. One group (11 men) lifted set percentages of their pre-study one-repetition maximum. The other (10 men) picked loads to land in a target range on the repetitions-in-reserve effort scale, adjusting by about 2 percent for each half-point outside the range. Everyone took the same protein and amino acid supplement around sessions.`,
      },
      {
        title: "Findings",
        body:
          `Both groups gained strength and muscle thickness (chest and thigh, by ultrasound), with no statistically significant difference between them. Strength gains were a little larger with effort-based loading (squat about 17 against 14 kg, bench press about 11 against 10 kg), which the authors described as a small, probable but uncertain advantage; muscle growth was effectively equal. The effort group ended up training at a higher average rating and, on the bench press, with heavier relative loads and slightly more volume. Most sets in both groups finished roughly 3 to 4 repetitions short of failure.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `Letting the lifter set the day's load from a target effort works at least as well as fixed percentages, and may help strength slightly because loads can rise as the person improves. Worthwhile gains also came without training to failure. The trial was small and short, in strong young men, and covered only two lifts, so the strength edge is a possibility rather than a firm result. The Hickmott 2022 entry pools this and similar trials.`,
      },
    ],
  },
  {
    slug: "hickmott_2022_autoregulation",
    label: "Hickmott et al. 2022",
    title:
      "The effect of load and volume autoregulation on muscular strength and hypertrophy: a systematic review and meta-analysis",
    authors: ["Hickmott LM", "Chilibeck PD", "Shaw KA", "Butcher SJ"],
    year: 2022,
    doi: "10.1186/s40798-021-00404-9",
    url: "https://doi.org/10.1186/s40798-021-00404-9",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["training", "autoregulation", "rpe", "rir", "strength", "hypertrophy"],
    evidenceLevel: "systematic review and meta-analysis (18 studies reviewed, 15 pooled)",
    kind: "paper",
    chosenBecause:
      "Pools the trials on adjusting load or set length to daily performance, so Coach can say how much autoregulation adds over fixed percentages. Summarised from the full text.",
    sections: [
      {
        title: "What the review did",
        body:
          `Autoregulation means adjusting training to how the person is performing on the day. The review covered two kinds. Load autoregulation sets the weight from effort ratings (repetitions in reserve) or bar speed rather than a fixed percentage of a tested maximum. Volume autoregulation ends a set once bar speed has fallen by a chosen percentage, so a larger allowed drop means more repetitions and a set closer to failure. Of 18 studies reviewed, 15 were pooled: 6 on load and 9 on volume, lasting 5 to 12 weeks. Participants were resistance trained and mostly young men; one load study was of adolescent girls.`,
      },
      {
        title: "Findings",
        body:
          `Autoregulated and percentage-based loading gave similar one-repetition maximum gains (about 2 kg more with autoregulation, not statistically significant; standardised difference 0.21). Effort-rating methods leaned towards a small benefit (about 3 kg, borderline) while bar-speed methods showed none, but the two did not differ significantly. Only one load study measured muscle size, so no pooled answer was possible there.

For set length, stopping at 25 percent bar-speed loss or less gave slightly more strength (about 2.3 kg), mainly in studies where participants also did other training. Allowing more than 25 percent loss gave slightly more growth (about 0.6 square centimetres of muscle cross-section), though a 20 to 25 percent loss grew muscle about as well.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `Effort-based load selection is a sound alternative to fixed percentages rather than a clear upgrade; its main value may be letting loads rise when the lifter is ready and ease back on a poor day. Stopping sets a bit further from failure suits strength, and going a bit closer suits size, but both differences were small. Most people have no bar-speed device, so repetitions in reserve is the practical tool; the Halperin 2022 entry describes how accurate those estimates are. Studies were short and mostly in young trained men.`,
      },
    ],
  },
  {
    slug: "halperin_2022_rir_prediction_accuracy",
    label: "Halperin et al. 2022",
    title:
      "Accuracy in predicting repetitions to task failure in resistance exercise: a scoping review and exploratory meta-analysis",
    authors: [
      "Halperin I",
      "Malleron T",
      "Har-Nir I",
      "Androulakis-Korakakis P",
      "Wolf M",
      "Fisher J",
    ],
    year: 2022,
    doi: "10.1007/s40279-021-01559-x",
    url: "https://doi.org/10.1007/s40279-021-01559-x",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["training", "rir", "rpe", "autoregulation", "intensity"],
    evidenceLevel: "scoping review and exploratory meta-analysis (12 studies, 414 participants)",
    kind: "paper",
    chosenBecause:
      "Tracend plans use repetitions in reserve, so Coach needs to know how accurate people's estimates of reps left in the tank really are. Summarised from the abstract only.",
    sections: [
      {
        title: "What the review did",
        body:
          `Training by repetitions in reserve relies on people judging how many more repetitions they could manage before failure. This review collected studies in which healthy participants made that judgement, before or during a set, and then kept going to failure so the guess could be checked. Sixteen publications qualified, and 12 studies with 414 participants went into a multilevel meta-analysis of 262 effect estimates. The search ran to January 2021.`,
      },
      {
        title: "Findings",
        body:
          `On average, people guessed close to one repetition fewer than they could actually do (0.95 repetitions, 95 percent confidence interval 0.17 to 1.73), with very large differences between studies. Guesses became slightly more accurate when made nearer to failure, in sets of 12 repetitions or fewer rather than longer sets, and in later sets. Training experience made no clear difference, nor did upper versus lower body exercises, and accuracy varied little from person to person.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `A target such as two reps in reserve is a useful guide, not a precise measurement: people tend to be about a repetition out, and usually have a little more left than they think. Estimates are least reliable in light, high-repetition sets and early sets, so effort targets work best as ranges and are best judged across several sessions. The authors left open whether this much error matters in practice, and studies explained and confirmed failure in different ways. This summary was written from the abstract only.`,
      },
    ],
  },
  {
    slug: "refalo_2023_failure_hypertrophy",
    label: "Refalo et al. 2023",
    title:
      "Influence of resistance training proximity-to-failure on skeletal muscle hypertrophy: a systematic review with meta-analysis",
    authors: ["Refalo MC", "Helms ER", "Trexler ET", "Hamilton DL", "Fyfe JJ"],
    year: 2023,
    doi: "10.1007/s40279-022-01784-y",
    url: "https://doi.org/10.1007/s40279-022-01784-y",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["training", "hypertrophy", "rir", "intensity", "volume"],
    evidenceLevel: "systematic review and meta-analysis (15 studies)",
    kind: "paper",
    chosenBecause:
      "Asks whether sets must reach failure to build muscle; read with the Robinson 2024 entry, it explains why close to failure, not all the way, is the sensible target. Summarised from the full text.",
    sections: [
      {
        title: "What the review did",
        body:
          `The authors found 15 studies in healthy adults that measured muscle growth and compared how close to failure sets were taken. They grouped them three ways: momentary muscular failure (no further repetition possible) against stopping short; other definitions of failure against stopping short; and studies that ended sets at different amounts of bar-speed loss, where a bigger loss means finishing nearer failure. Seven of the nine failure-versus-non-failure studies used untrained people, while all six bar-speed studies used trained people and heavier loads.`,
      },
      {
        title: "Findings",
        body:
          `Pooling every definition of failure gave a statistically significant but trivial advantage for failure (effect size 0.19, 95 percent confidence interval 0.00 to 0.37), not changed by whether volume load was matched or by the load used. The authors warn this result is fragile: it lost significance under slightly different statistical assumptions. Comparing only true momentary failure with stopping short showed no clear difference (0.12), and larger bar-speed losses did not reliably beat moderate ones (0.08). Within-group growth was similar whether sets went to failure, near failure or to moderate or large speed loss. The advantage for failure looked somewhat larger with light loads.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `The authors propose that the benefit flattens out: getting reasonably close to failure matters, but going all the way adds little and brings more fatigue. They suggest stopping most sets close to failure and keeping true failure mainly for simpler, safer exercises such as machines and single-joint lifts, the last set of an exercise, and lighter loads. This fits the Robinson 2024 entry, which found more growth as sets end nearer failure but an uncertain shape; both say close is good and the best distance is not settled. Studies were few and small, and how close the non-failure sets really got was often unclear.`,
      },
    ],
  },
  {
    slug: "coleman_2024_deload_trial",
    label: "Coleman et al. 2024",
    title:
      "Gaining more from doing less? The effects of a one-week deload period during supervised resistance training on muscular adaptations",
    authors: ["Coleman M", "Burke R", "Augustin F", "Piñero A", "Maldonado J", "Fisher JP"],
    year: 2024,
    doi: "10.7717/peerj.16777",
    url: "https://doi.org/10.7717/peerj.16777",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["training", "deload", "recovery", "strength", "hypertrophy", "time-off"],
    evidenceLevel: "randomised controlled trial (39 trained adults, 9 weeks)",
    kind: "paper",
    chosenBecause:
      "The first trial to test a deload week directly, so Coach can say what a week off does and does not do for muscle and strength. Summarised from the full text.",
    sections: [
      {
        title: "What the study did",
        body:
          `Thirty-nine resistance-trained young adults (29 men and 10 women, all with at least a year of regular lifting) followed a high-volume nine-week programme: upper and lower body sessions, each twice a week, with sets taken to volitional failure. The lower body work (Smith machine squat, leg extension, toe press and seated calf raise, five sets of 8 to 12 repetitions each) was supervised; the upper body sessions were done alone. One group took the fifth week completely off resistance training, while the other trained straight through. The team measured muscle thickness, lower body strength, local endurance and jump power.`,
      },
      {
        title: "Findings",
        body:
          `Gains in thigh and calf muscle thickness, leg extension endurance and jump height were similar in both groups. Strength was the exception: continuous training gave somewhat larger gains in squat one-repetition maximum and isometric knee extension strength, with probabilities of about 85 and 92 percent in its favour, although the size of the difference was uncertain. The week-off group later reported slightly more soreness and lower motivation, and participants often said informally that they felt out of practice, not refreshed, after the break.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `A one-week break did not cost muscle, but it did not boost growth either, and it may cost a little strength. Here the deload was complete rest; the authors note that coaches usually deload by cutting volume or load instead, which this trial did not test. Results apply to young trained adults, the lower body and a nine-week block. This fits the Bell 2023 entry: a deload is a coaching practice with a sensible purpose, not a proven requirement, and whether one applies is for the plan's rules and the athlete's own data to decide.`,
      },
    ],
  },
  {
    slug: "travis_2020_powerlifting_taper",
    label: "Travis et al. 2020",
    title: "Tapering and peaking maximal strength for powerlifting performance: a review",
    authors: ["Travis SK", "Mujika I", "Gentles JA", "Stone MH", "Bazyler CD"],
    year: 2020,
    doi: "10.3390/sports8090125",
    url: "https://doi.org/10.3390/sports8090125",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["training", "tapering", "peaking", "strength", "performance", "detraining"],
    evidenceLevel: "systematic review (16 studies)",
    kind: "paper",
    chosenBecause:
      "Answers how a lifter should ease off before a meet or a maximum test, using data from strength athletes rather than endurance sport. Summarised from the full text.",
    sections: [
      {
        title: "What the review did",
        body:
          `Most tapering research comes from endurance sport. This review gathered 16 studies of strength and power athletes (powerlifters, weightlifters, throwers and strongman competitors) and well-trained lifters who cut back or stopped training before a competition or a one-repetition maximum test. It also drew on surveys of national powerlifting teams and of strongman athletes. Apart from one large survey, samples ranged from 5 to 44 people.`,
      },
      {
        title: "Findings",
        body:
          `Tapers of 1 to 4 weeks that cut volume by roughly a third to about 70 percent were followed by better squat (about 2 to 10 percent) and bench press (about 1 to 6 percent) results. Moderate cuts of about 30 to 50 percent over two weeks seemed to work better than larger ones, and cuts above about 70 percent sometimes left performance flat or worse. Changes in volume appeared to matter more than changes in intensity. Two to seven days of complete rest before testing kept or improved performance, whereas two weeks or more off began to lower maximums slightly.`,
      },
      {
        title: "The authors' recommendation",
        body:
          `To peak maximal strength, they suggest cutting volume by about 30 to 70 percent over one to two weeks, keeping loads heavy (about 85 percent of maximum or more) or trimming them near the end, reducing work either progressively (an exponential taper) or in a single step, and finishing with 2 to 7 days of complete rest.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `A taper only makes sense for someone with a real target day, such as a meet or a planned maximum test; most people training for health or muscle do not need one, and a short planned easing is a different thing from a routine deload. The evidence is thin: few, small studies with varied methods, and the authors could not account for drug use or outside activity. The numbers are a guide for planning, and the plan's rules decide the actual reduction.`,
      },
    ],
  },
  {
    slug: "bosquet_2007_tapering",
    label: "Bosquet et al. 2007",
    title: "Effects of tapering on performance: a meta-analysis",
    authors: ["Bosquet L", "Montpetit J", "Arvisais D", "Mujika I"],
    year: 2007,
    doi: "10.1249/mss.0b013e31806010e0",
    url: "https://doi.org/10.1249/mss.0b013e31806010e0",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["tapering", "peaking", "performance", "cardio", "training"],
    evidenceLevel: "meta-analysis (27 studies of competitive athletes)",
    kind: "paper",
    chosenBecause:
      "The classic pooled analysis of how to taper before an event, which still shapes taper advice for races and competitions. Summarised from the abstract only.",
    sections: [
      {
        title: "What the review did",
        body:
          `The authors searched six databases and kept 27 of 182 candidate studies in which competitive athletes cut their training before a competition or a field-based performance test, with enough detail about how training was reduced to calculate effects. They then asked which features of the taper (reductions in intensity, volume or frequency, the pattern of the reduction and how long it lasted) went with the biggest gains in performance.`,
      },
      {
        title: "Findings",
        body:
          `The best results came from a taper of about two weeks (overall effect 0.59), in which training volume was reduced by 41 to 60 percent (effect 0.72) following an exponential, progressive pattern rather than a single step, while training intensity and the number of sessions stayed the same. The authors offered this as the most efficient way to bring performance to a peak.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `A taper is a short, planned cut in training volume, keeping sessions and intensity, before an event that matters. It belongs to people with a target day, such as a race or a competition, not to everyday training. The abstract does not list the sports; the Travis 2020 entry in this library describes this analysis as evidence from endurance athletes and finds broadly similar volume cuts work for strength athletes. This summary was written from the abstract only, so the size and quality of the pooled studies are not described here.`,
      },
    ],
  },
];
