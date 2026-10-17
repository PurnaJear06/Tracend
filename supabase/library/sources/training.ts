import type { LibrarySource } from "../../functions/_shared/library/types.ts";

// Resistance and general training: volume, intensity, frequency, rest, progression, deloads,
// time-efficient training. Summaries are written in Tracend's own words from each source's
// abstract (and, for the open-access ones, its full text); no source text is copied.

export const trainingSources: readonly LibrarySource[] = [
  {
    slug: "acsm_2009_progression",
    label: "ACSM 2009",
    title: "Progression models in resistance training for healthy adults",
    authors: ["American College of Sports Medicine"],
    year: 2009,
    doi: "10.1249/MSS.0b013e3181915670",
    url: "https://doi.org/10.1249/MSS.0b013e3181915670",
    licence: "Publisher copyright (no open licence); stored as an own-words summary with citation",
    region: ["global"],
    topics: ["training", "strength", "hypertrophy", "progression", "frequency", "rest", "intensity"],
    evidenceLevel: "position stand",
    kind: "position_stand",
    chosenBecause:
      "The long-standing reference for how a lifter's training should progress with experience; Tracend's standard cites it, and Coach needs to explain where beginner and advanced advice differ.",
    sections: [
      {
        title: "What the position stand covers",
        body: `This American College of Sports Medicine position stand lays out how resistance training should change as a healthy adult gets more experienced. Its core idea is that adaptation needs a stimulus that keeps moving upward, so a programme has to progress instead of repeating the same work.

For exercise choice it favours a mix: single-joint and multi-joint lifts, work on both sides together and one side at a time, and lifting and lowering phases as well as holds. When ordering exercises inside a session it suggests protecting the quality of the hard work: big muscle groups before small ones, multi-joint lifts before single-joint lifts, and heavier work before lighter work.`,
      },
      {
        title: "Loads, rest and lifting speed",
        body: `For beginners (people new to lifting, or back after several years away) it recommends loads that allow roughly 8 to 12 repetitions to failure. For intermediate lifters (about six months of steady training) and advanced lifters (years of training) it recommends a wider span, from 1 to 12 repetitions, varied over time in a planned way, with heavy work in the 1 to 6 range gaining emphasis for strength. Strength work uses long rests of about 3 to 5 minutes and a moderate lifting speed of roughly one to two seconds up and one to two seconds down.

For muscle size it keeps the same exercise choices and frequency advice, but puts the emphasis on loads in the 6 to 12 repetition range with shorter rests of about 1 to 2 minutes, and it calls for higher-volume, multiple-set work to maximise growth.`,
      },
      {
        title: "When to add load, and how often to train",
        body: `The progression rule is simple: when a lifter can do one or two repetitions more than the target at the current load, increase the load by about 2 to 10 percent.

Suggested training frequency rises with experience: 2 to 3 days a week for beginners, 3 to 4 for intermediate lifters and 4 to 5 for advanced lifters.`,
      },
      {
        title: "Practical reading and limits",
        body: `This is a 2009 document and the college has since published an updated overview (see the ACSM 2026 entry), which found that many programme details matter less than once thought. Use this entry for the shape of progression by experience level and the double-progression style rule, not as proof that one rep range or one rest length is the only good choice. Tracend's own rules set the actual numbers in a plan.`,
      },
    ],
  },
  {
    slug: "acsm_2026_resistance_prescription",
    label: "Currier et al. 2026 (ACSM)",
    title:
      "American College of Sports Medicine position stand: resistance training prescription for muscle function, hypertrophy, and physical performance in healthy adults: an overview of reviews",
    authors: ["Currier BS", "D'Souza AC", "Singh MAF", "Lowisz CV", "Rawson ES", "Schoenfeld BJ"],
    year: 2026,
    doi: "10.1249/MSS.0000000000003897",
    url: "https://doi.org/10.1249/MSS.0000000000003897",
    licence: "CC BY-NC-ND (open access); own-words summary, no text copied",
    region: ["global"],
    topics: ["training", "strength", "hypertrophy", "volume", "intensity", "progression", "frequency"],
    evidenceLevel: "position stand; overview of 137 systematic reviews",
    kind: "position_stand",
    chosenBecause:
      "The newest and broadest synthesis of what actually changes results in resistance training; it updates the 2009 stand and is the best single reference for the question 'what matters and what does not'.",
    sections: [
      {
        title: "What this position stand is",
        body: `This 2026 American College of Sports Medicine position stand replaces its 2009 progression-models stand. Instead of reviewing individual trials it pooled 137 systematic reviews covering more than 30,000 healthy adults aged 18 and over. The reviews it used each compared resistance training lasting at least six weeks against either no exercise or a different training programme. The literature search ran to October 2024.`,
      },
      {
        title: "What resistance training does",
        body: `Compared with doing no exercise, resistance training clearly improved strength, muscle size, power and endurance, and it also improved contraction speed, walking speed, balance and several measures of everyday physical function. The headline conclusion is that healthy adults should do progressive resistance training, with the details varied in line with the findings below.`,
      },
      {
        title: "Variables that did change results",
        body: `Strength improved more with heavier loads (80 percent of the one-repetition maximum or more), with a full range of motion, with 2 to 3 sets, with strength work placed early in the session, and with at least two sessions a week.

Muscle size improved more with higher weekly volume (10 or more sets per week for the muscle) and with eccentric overload, meaning extra emphasis on the lowering phase.

Power improved more with moderate loads (30 to 70 percent of the one-repetition maximum), low to moderate volume, Olympic-style lifts and deliberately fast lifting. Power training also improved physical function.`,
      },
      {
        title: "Variables that did not consistently matter",
        body: `Across the reviews, these did not reliably change outcomes: training to momentary muscle failure, the type of equipment, how complex the exercise is, how sets are structured, time under tension, blood flow restriction, and periodisation.

Read this carefully: it says the effect was not consistent across reviews, not that these things never help. More detailed analyses, such as the proximity-to-failure meta-regression elsewhere in this library, can still find small effects.`,
      },
      {
        title: "Practical reading",
        body: `The main message for coaching is reassuring: a progressive plan that trains each muscle at least twice across the week, uses a mix of load ranges, keeps weekly volume at roughly ten or more hard sets for muscles the person wants to grow, and uses the lowering phase well covers most of what the evidence supports. Fine details such as exact tempo or equipment brand rarely deserve worry. This is an overview of reviews of mostly young, healthy adults, so it says less about older adults, people with health conditions or very advanced lifters.`,
      },
    ],
  },
  {
    slug: "schoenfeld_2017_weekly_volume",
    label: "Schoenfeld et al. 2017",
    title:
      "Dose-response relationship between weekly resistance training volume and increases in muscle mass: a systematic review and meta-analysis",
    authors: ["Schoenfeld BJ", "Ogborn D", "Krieger JW"],
    year: 2017,
    doi: "10.1080/02640414.2016.1210197",
    url: "https://doi.org/10.1080/02640414.2016.1210197",
    licence: "Publisher copyright (no open licence); stored as an own-words summary with citation",
    region: ["global"],
    topics: ["training", "hypertrophy", "volume"],
    evidenceLevel: "systematic review and meta-analysis (15 studies)",
    kind: "paper",
    chosenBecause:
      "The classic answer to 'how many sets per week?'; Tracend's volume ranges cite it, so Coach needs a plain explanation of the dose-response finding and its limits.",
    sections: [
      {
        title: "What the review did",
        body: `The authors pooled 15 studies (34 training groups) that compared different weekly amounts of resistance training and measured changes in muscle size. They used meta-regression, a method that checks whether more sets per week goes with more growth, instead of only comparing a high group with a low group.`,
      },
      {
        title: "What it found",
        body: `More weekly sets went with more growth. Each extra set per muscle per week was linked to a small gain in effect size, which the authors translated to roughly 0.4 percentage points more muscle gain. Comparing the higher-volume and lower-volume groups within each study, the higher groups gained about 4 percentage points more. When sets per week were sorted into fewer than 5, 5 to 9, and 10 or more, the trend pointed the same way but did not quite reach conventional statistical significance.

The authors described this as a graded dose-response relationship: more volume tends to produce more growth.`,
      },
      {
        title: "Practical reading and limits",
        body: `The review supports the idea that doing more hard sets per week helps muscle growth, but it does not say that more is always better without limit, that one number fits everyone, or that very high volumes are practical or recoverable. Newer analyses (see the Pelland 2026 entry) find diminishing returns as volume climbs. Studies were mostly of young, healthy people over weeks to months. Coach should present volume as a lever with diminishing returns that is limited by recovery, time and joint tolerance.`,
      },
    ],
  },
  {
    slug: "schoenfeld_2021_loading_continuum",
    label: "Schoenfeld et al. 2021",
    title:
      "Loading recommendations for muscle strength, hypertrophy, and local endurance: a re-examination of the repetition continuum",
    authors: ["Schoenfeld BJ", "Grgic J", "Van Every DW", "Plotkin DL"],
    year: 2021,
    doi: "10.3390/sports9020032",
    url: "https://doi.org/10.3390/sports9020032",
    licence: "CC BY 4.0 (open access); own-words summary",
    region: ["global"],
    topics: ["training", "strength", "hypertrophy", "intensity"],
    evidenceLevel: "narrative review",
    kind: "paper",
    chosenBecause:
      "Explains why a wide span of rep ranges works, which is the evidence behind letting people train with loads they enjoy and tolerate; Tracend's rep-range rules cite it.",
    sections: [
      {
        title: "The old rule and the challenge to it",
        body: `A common teaching, called the repetition continuum, says heavy loads are best for maximal strength, moderate loads for muscle size, and light loads for muscular endurance. This review looks at the evidence behind that idea and finds that parts of it do not hold up.`,
      },
      {
        title: "The proposed view",
        body: `The authors propose a new view in which muscle adaptations can be obtained, and in some cases optimised, across a wide spectrum of loading zones instead of one zone per goal. They argue that the sharp boundaries in the old model are not supported by current research, and they discuss the nuances and what they imply for programming.`,
      },
      {
        title: "Practical reading",
        body: `For coaching this means a lifter does not need to force a single rep range. Someone with sore joints can build muscle with lighter loads taken close to hard effort, while someone chasing a strength number should still spend time with heavy loads (the Lopez 2021 network meta-analysis in this library found strength gains were larger with heavier loads). Choosing loads the person can perform with good technique and tolerate week after week is a legitimate way to keep training consistent. The article is a narrative review, so it argues from the evidence and does not give a numeric dose.`,
      },
    ],
  },
  {
    slug: "pelland_2026_volume_frequency",
    label: "Pelland et al. 2026",
    title:
      "The resistance training dose response: meta-regressions exploring the effects of weekly volume and frequency on muscle hypertrophy and strength gains",
    authors: ["Pelland JC", "Remmert JF", "Robinson ZP", "Hinson SR", "Zourdos MC"],
    year: 2026,
    doi: "10.1007/s40279-025-02344-w",
    url: "https://doi.org/10.1007/s40279-025-02344-w",
    licence: "Publisher copyright (no open licence found); stored as an own-words summary with citation",
    region: ["global"],
    topics: ["training", "hypertrophy", "strength", "volume", "frequency"],
    evidenceLevel: "meta-regression of 67 studies",
    kind: "paper",
    chosenBecause:
      "The most recent and detailed analysis of weekly volume and frequency together, showing diminishing returns; it keeps Coach from overselling 'more sets'.",
    sections: [
      {
        title: "What the analysis did",
        body: `The authors combined 67 studies with 2,058 participants (about four in five men, average age about 25). Their key step was classifying sets as direct or indirect for each muscle: a bench press is a direct set for the chest but only partly counts for the triceps. They counted such indirect sets as half a set, a method that fit the data best, then asked how weekly set volume and training frequency relate to muscle growth and strength gains.`,
      },
      {
        title: "Volume",
        body: `For both muscle size and strength, more weekly sets meant more gains, but with diminishing returns: each additional set added less than the one before. The flattening was much more pronounced for strength than for muscle size.`,
      },
      {
        title: "Frequency",
        body: `For muscle size, the data were compatible with training frequency having little or no effect once volume is accounted for. For strength, higher frequency was linked to greater gains, again with diminishing returns.`,
      },
      {
        title: "Practical reading and limits",
        body: `Weekly hard sets are the main lever; frequency is mostly a way to spread that volume so each session stays productive and manageable. Because returns diminish, going from a small amount of training to a moderate amount usually pays off far more than going from a high amount to a very high one. Participants were mostly young and male, so applying the numbers to older adults or women needs more caution.`,
      },
    ],
  },
  {
    slug: "singer_2024_rest_intervals",
    label: "Singer et al. 2024",
    title:
      "Give it a rest: a systematic review with Bayesian meta-analysis on the effect of inter-set rest interval duration on muscle hypertrophy",
    authors: ["Singer A", "Wolf M", "Generoso L", "Arias E", "Delcastillo K", "Echevarria E"],
    year: 2024,
    doi: "10.3389/fspor.2024.1429789",
    url: "https://doi.org/10.3389/fspor.2024.1429789",
    licence: "CC BY 4.0 (open access); own-words summary",
    region: ["global"],
    topics: ["training", "hypertrophy", "rest", "time-efficient"],
    evidenceLevel: "systematic review and Bayesian meta-analysis (9 studies)",
    kind: "paper",
    chosenBecause:
      "Gives a practical, evidence-based answer to 'how long should I rest between sets?', which matters for time-pressed users.",
    sections: [
      {
        title: "What the review did",
        body: `The authors looked for randomised trials in healthy adults that changed only the rest period between sets and measured muscle or lean mass. Nine studies qualified, and a Bayesian analysis estimated how rest length affects growth in the thigh, the arm and the whole body.`,
      },
      {
        title: "Findings",
        body: `Muscle gains were similar across short, intermediate, long and very long rests, and results varied a lot between studies. When short rests were compared directly with longer ones, estimates leaned slightly towards longer rests for the arm and thigh, and were close to zero for whole-body measures. Whether people trained to failure did not change the picture.

The authors concluded that resting longer than about 60 seconds may give a small benefit, possibly because it protects the amount of work done in later sets, and that they found no clear difference beyond roughly 90 seconds. This fits evidence that lost work from short rests stops growing once rests pass about that length.`,
      },
      {
        title: "Practical reading",
        body: `Rest about one to two minutes between most sets for muscle growth is well supported, and there is no need to wait three to five minutes unless heavy, strength-focused lifts call for it. For a time-pressed person, shortening rests to save time is a reasonable trade and costs little, as long as the load or repetitions do not collapse in later sets; when they do, a slightly longer rest is a better fix than stopping early. Results are about muscle size, not maximal strength.`,
      },
    ],
  },
  {
    slug: "zourdos_2016_rir_scale",
    label: "Zourdos et al. 2016",
    title:
      "Novel resistance training-specific rating of perceived exertion scale measuring repetitions in reserve",
    authors: ["Zourdos MC", "Klemp A", "Dolan C", "Quiles JM", "Schau KA", "Jo E"],
    year: 2016,
    doi: "10.1519/JSC.0000000000001049",
    url: "https://doi.org/10.1519/JSC.0000000000001049",
    licence: "Publisher copyright (no open licence); stored as an own-words summary with citation",
    region: ["global"],
    topics: ["training", "intensity", "rir", "progression"],
    evidenceLevel: "experimental study (29 lifters)",
    kind: "paper",
    chosenBecause:
      "The origin of the repetitions-in-reserve effort scale that Tracend's plans use; Coach needs to explain what 'reps in reserve' means and how reliable it is.",
    sections: [
      {
        title: "What the study did",
        body: `The researchers compared how 15 experienced squatters (about five years of training) and 14 novices (a few months) rated effort on a scale built around repetitions in reserve: the number of repetitions a lifter believes they could still do when the set ends. Each person did a one-repetition maximum squat, then single repetitions at 60, 75 and 90 percent of that maximum and a set of eight at 70 percent. Bar speed was measured and each lifter gave an effort rating that mapped onto repetitions in reserve (a rating of 10 meant none left, 9 meant one left, and so on).`,
      },
      {
        title: "Findings",
        body: `Bar speed and effort rating moved in opposite directions: the slower the bar, the higher the rating, and the relationship was strong in both groups. Experienced lifters were slower at the heaviest loads, rated their maximum lift as harder, and so seemed more efficient at high intensities; the two groups looked similar at lighter loads.`,
      },
      {
        title: "Practical reading and limits",
        body: `Repetitions in reserve is a practical way to set and adjust effort from day to day, because the load that feels like two reps from failure changes with fatigue, sleep and stress. It is a self-rating, so it can be off. This study tested the squat only, in a small group, and checks how the scale lines up with bar speed rather than proving it improves results.`,
      },
    ],
  },
  {
    slug: "robinson_2024_proximity_to_failure",
    label: "Robinson et al. 2024",
    title:
      "Exploring the dose-response relationship between estimated resistance training proximity to failure, strength gain, and muscle hypertrophy: a series of meta-regressions",
    authors: ["Robinson ZP", "Pelland JC", "Remmert JF", "Refalo MC", "Jukic I", "Steele J"],
    year: 2024,
    doi: "10.1007/s40279-024-02069-2",
    url: "https://doi.org/10.1007/s40279-024-02069-2",
    licence: "Publisher copyright (no open licence found); stored as an own-words summary with citation",
    region: ["global"],
    topics: ["training", "hypertrophy", "strength", "intensity", "rir"],
    evidenceLevel: "series of meta-regressions",
    kind: "paper",
    chosenBecause:
      "The best available analysis of how close to failure to train, the basis for Tracend's reps-in-reserve targets.",
    sections: [
      {
        title: "What the analysis did",
        body: `Earlier reviews compared training to failure against stopping short as a yes-or-no question. These authors instead treated closeness to failure as a sliding scale, measured as estimated repetitions in reserve, and fitted models after adjusting for load, how volume was matched, how long the study lasted and the lifters' experience. The reserve for each study was estimated from the training description, so it is approximate.`,
      },
      {
        title: "Findings",
        body: `For strength, the link between repetitions in reserve and gains was negligible: strength rose similarly across a wide range of reserve.

For muscle size, the models agreed that growth increased as sets finished closer to failure. The authors note that the exact shape of this relationship is uncertain, given the way reserve had to be estimated.`,
      },
      {
        title: "Practical reading and limits",
        body: `Strength work does not need to be pushed to failure; leaving a few reps in reserve is fine and keeps technique and recovery in better shape. For muscle growth, sets taken fairly close to failure appear to be more productive, but how close is best is not settled and the benefit is a trade against more fatigue and joint stress. A large overview of reviews (ACSM 2026 in this library) found no consistent effect of training to failure, so Coach should describe the effect for growth as modest and uncertain, not as a rule.`,
      },
    ],
  },
  {
    slug: "iversen_2021_time_efficient",
    label: "Iversen et al. 2021",
    title:
      "No time to lift? Designing time-efficient training programs for strength and hypertrophy: a narrative review",
    authors: ["Iversen VM", "Norum M", "Schoenfeld BJ", "Fimland MS"],
    year: 2021,
    doi: "10.1007/s40279-021-01490-1",
    url: "https://doi.org/10.1007/s40279-021-01490-1",
    licence: "CC BY 4.0 (open access); own-words summary",
    region: ["global"],
    topics: ["training", "time-efficient", "volume", "strength", "hypertrophy", "frequency"],
    evidenceLevel: "narrative review",
    kind: "paper",
    chosenBecause:
      "Directly answers the most common barrier, lack of time, with concrete choices on exercises, sets, warm-ups and techniques that save minutes.",
    sections: [
      {
        title: "Exercise choice",
        body: `When time is short, the authors recommend building sessions around multi-joint exercises done with both sides together and through a full movement (lifting and lowering). At minimum, cover one leg-pressing movement such as a squat, one upper-body pull such as a pull-up, and one upper-body push such as a bench press. Machines or free weights both work; pick what suits the person's goals, access and preferences.`,
      },
      {
        title: "Sets, reps and frequency",
        body: `Weekly volume matters more than how it is split across days. The review recommends at least four weekly sets per muscle group, using a load that allows 6 to 15 repetitions to failure. If sets are taken to volitional failure, lighter loads of roughly 15 to 40 repetitions can also be used.`,
      },
      {
        title: "Saving time inside a session",
        body: `Techniques such as supersets (pairing exercises back to back), drop sets and rest-pause sets can cut session time to about half while keeping the same volume. They are probably better at building muscle than at building maximal strength, and long-term evidence is still thin. The authors suggest limiting warm-ups to exercise-specific ones and doing stretching only when improving flexibility is a goal.`,
      },
      {
        title: "Practical reading and limits",
        body: `A short, well-chosen programme can deliver much of the benefit, so a person short on time can still progress. Four sets a week is a floor for progress, not the best amount; the review is about efficiency, not maximum results. It is a narrative review, so its advice rests on the authors' reading of studies, not a single pooled calculation.`,
      },
    ],
  },
  {
    slug: "schoenfeld_2016_frequency_hypertrophy",
    label: "Schoenfeld et al. 2016",
    title:
      "Effects of resistance training frequency on measures of muscle hypertrophy: a systematic review and meta-analysis",
    authors: ["Schoenfeld BJ", "Ogborn D", "Krieger JW"],
    year: 2016,
    doi: "10.1007/s40279-016-0543-8",
    url: "https://doi.org/10.1007/s40279-016-0543-8",
    licence: "Publisher copyright (no open licence); stored as an own-words summary with citation",
    region: ["global"],
    topics: ["training", "hypertrophy", "frequency"],
    evidenceLevel: "systematic review and meta-analysis (10 studies)",
    kind: "paper",
    chosenBecause:
      "The reason Coach can say each muscle is best trained at least twice a week when volume is equal, a core split-design rule.",
    sections: [
      {
        title: "What the review did",
        body: `The authors pooled ten experimental trials in healthy adults that compared different weekly training frequencies and measured muscle size changes over at least four weeks. They looked at how often each muscle group was trained, not just how many gym days a week there were.`,
      },
      {
        title: "Findings",
        body: `Higher frequency was linked to larger growth than lower frequency (effect sizes of about 0.49 against 0.30). In the studies that kept total weekly volume equal, training a muscle twice a week gave better results than once a week. Whether three times a week beats twice a week could not be answered from the data.`,
      },
      {
        title: "Practical reading and limits",
        body: `The practical lesson is to train major muscles at least twice a week, for example with an upper and lower split or full-body sessions, when the plan allows it. A once-a-week bodybuilding split is not wrong, but it asks more of each session. Only ten studies qualified and they covered one to three sessions a week, so the review cannot say how much frequency helps beyond three. A later analysis (Pelland 2026 in this library) found frequency matters little for growth once volume is counted.`,
      },
    ],
  },
  {
    slug: "grgic_2018_frequency_strength",
    label: "Grgic et al. 2018",
    title:
      "Effect of resistance training frequency on gains in muscular strength: a systematic review and meta-analysis",
    authors: ["Grgic J", "Schoenfeld BJ", "Davies TB", "Lazinica B", "Krieger JW", "Pedisic Z"],
    year: 2018,
    doi: "10.1007/s40279-018-0872-x",
    url: "https://doi.org/10.1007/s40279-018-0872-x",
    licence: "Publisher copyright (no open licence); stored as an own-words summary with citation",
    region: ["global"],
    topics: ["training", "strength", "frequency", "volume"],
    evidenceLevel: "systematic review and meta-analysis (22 studies)",
    kind: "paper",
    chosenBecause:
      "Shows that for strength the benefit of training more often comes mostly from the extra volume, helping Coach advise people with limited gym days.",
    sections: [
      {
        title: "What the review did",
        body: `The authors pooled 22 studies that compared strength gains at different weekly training frequencies. They grouped frequency as 1, 2, 3 or 4 or more sessions per muscle per week and checked many moderators, including total volume, age, sex and whether sets were taken to failure.`,
      },
      {
        title: "Findings",
        body: `Overall, higher frequency went with larger strength gains, with effect sizes rising from 0.74 at once a week to 0.82, 0.93 and 1.08 at two, three and four or more times a week. But when studies matched total weekly volume, frequency made no significant difference. The effect looked stronger for multi-joint upper-body lifts and in women, and younger people responded better to higher frequency than older adults did.`,
      },
      {
        title: "Practical reading and limits",
        body: `Training more days is mainly a way to fit in more volume. A person who can only train twice a week can still gain strength if the weekly volume is adequate, and a person who trains more often should not expect extra benefit without extra work. Most studies used untrained participants, so evidence for experienced lifters is thinner.`,
      },
    ],
  },
  {
    slug: "bell_2023_deloading",
    label: "Bell et al. 2023",
    title:
      "Integrating deloading into strength and physique sports training programmes: an international Delphi consensus approach",
    authors: ["Bell L", "Strafford BW", "Coleman M", "Androulakis Korakakis P", "Nolan D"],
    year: 2023,
    doi: "10.1186/s40798-023-00633-0",
    url: "https://doi.org/10.1186/s40798-023-00633-0",
    licence: "CC BY 4.0 (open access); own-words summary",
    region: ["global"],
    topics: ["training", "deload", "recovery", "progression"],
    evidenceLevel: "expert consensus (Delphi, 34 coaches)",
    kind: "paper",
    chosenBecause:
      "Deloading is widely used but lightly researched; this is the only structured consensus, so it lets Coach describe deloads honestly as expert practice.",
    sections: [
      {
        title: "What the study was",
        body: `Deloading is a common habit in strength and bodybuilding training but has barely been tested in trials. The authors ran a three-round Delphi process with expert coaches (34 in round one, 21 by round three) to build a consensus on how deloads should be designed, using open questions first and then rating 138 statements on a four-point scale.`,
      },
      {
        title: "The consensus definition",
        body: `The panel agreed on this idea: a deload is a period of reduced training stress meant to ease physical and mental fatigue, help recovery and leave the person better prepared for the next block of training.`,
      },
      {
        title: "Practical reading and limits",
        body: `A deload is a planned, temporary reduction in load, volume or effort, used to manage fatigue instead of stopping training. The evidence is expert opinion, not a controlled trial, so Coach should say that deloads are a widely used coaching practice with consensus on their purpose, not a proven requirement. When a reduction applies is a decision for the plan's rules and the athlete's own data, not for the model.`,
      },
    ],
  },
  {
    slug: "lopez_2021_load_network",
    label: "Lopez et al. 2021",
    title:
      "Resistance training load effects on muscle hypertrophy and strength gain: systematic review and network meta-analysis",
    authors: ["Lopez P", "Radaelli R", "Taaffe DR", "Newton RU", "Galvão DA", "Trajano GS"],
    year: 2021,
    doi: "10.1249/MSS.0000000000002585",
    url: "https://doi.org/10.1249/MSS.0000000000002585",
    licence: "CC BY-NC-ND (open access); own-words summary, no text copied",
    region: ["global"],
    topics: ["training", "hypertrophy", "strength", "intensity", "joint-friendly"],
    evidenceLevel: "systematic review and network meta-analysis (28 studies)",
    kind: "paper",
    chosenBecause:
      "Backs the advice that lighter loads still build muscle when taken to failure, important for people who need joint-friendlier training.",
    sections: [
      {
        title: "What the review did",
        body: `The authors compared low loads (more than 15 repetitions to failure), moderate loads (9 to 15) and high loads (8 or fewer) in 28 studies with 747 healthy adults. Every set in the included studies was taken to failure, which makes the loads comparable in effort. A network meta-analysis compared all three at once.`,
      },
      {
        title: "Findings",
        body: `Muscle growth did not differ between low, moderate and high loads. Strength improved more with high and moderate loads than with low loads. Untrained people gained more muscle, and people with some training experience gained more when they did more sessions.`,
      },
      {
        title: "Practical reading and limits",
        body: `If a joint, tendon or injury history makes heavy lifting uncomfortable, lighter loads taken close to failure can still build muscle, though maximal strength will improve less than with heavier loads. Taking light sets to failure is hard work and tiring, so the trade is comfort for joints against effort for the lifter. All studies were in healthy adults; this is not guidance for rehabilitating an injury.`,
      },
    ],
  },
  {
    slug: "schumann_2022_concurrent_training",
    label: "Schumann et al. 2022",
    title:
      "Compatibility of concurrent aerobic and strength training for skeletal muscle size and function: an updated systematic review and meta-analysis",
    authors: ["Schumann M", "Feuerbacher JF", "Sünkeler M", "Freitag N", "Rønnestad BR", "Doma K"],
    year: 2022,
    doi: "10.1007/s40279-021-01587-7",
    url: "https://doi.org/10.1007/s40279-021-01587-7",
    licence: "CC BY 4.0 (open access); own-words summary",
    region: ["global"],
    topics: ["training", "cardio", "strength", "hypertrophy", "concurrent-training"],
    evidenceLevel: "systematic review and meta-analysis (43 studies)",
    kind: "paper",
    chosenBecause:
      "Settles the common worry that cardio kills muscle gains, so Coach can advise people who want both.",
    sections: [
      {
        title: "What the review did",
        body: `The authors pooled 43 supervised trials in healthy adults that compared strength training plus aerobic training against the same strength training alone, for at least four weeks. They looked at maximal strength, explosive strength and muscle size, and checked effects of exercise order, cycling versus running, weekly frequency, age and training status.`,
      },
      {
        title: "Findings",
        body: `Adding aerobic training did not hurt muscle size or maximal strength. Explosive strength (how fast force is produced) was somewhat lower with concurrent training, especially when the cardio and the lifting were in the same session instead of separated by at least three hours. Running and cycling, frequency and age did not clearly change the result.`,
      },
      {
        title: "Practical reading",
        body: `For most people, doing both cardio and lifting is fine for building muscle and strength. When explosive power matters, keeping them in separate sessions helps. Studies were mostly short to medium term, so very high cardio volumes alongside heavy lifting remain a case for more care.`,
      },
    ],
  },
];
