import type { LibrarySource } from "../../functions/_shared/library/types.ts";

// Exercise selection and injury risk for healthy adults: free weights against machines, range
// of motion, exercise variation and substitution, how often lifters get hurt, strength training
// as injury prevention, and the debate over the acute-to-chronic workload ratio. Nothing here
// is rehab or diagnosis. Summaries are written in Tracend's own words from each source's
// abstract (and, for the open-access ones, its full text); no source text is copied.

export const exerciseSelectionSources: readonly LibrarySource[] = [
  {
    slug: "haugen_2023_free_weights_machines",
    label: "Haugen et al. 2023",
    title:
      "Effect of free-weight vs. machine-based strength training on maximal strength, hypertrophy and jump performance: a systematic review and meta-analysis",
    authors: ["Haugen ME", "Vårvik FT", "Larsen S", "Haugen AS", "van den Tillaar R", "Bjørnsen T"],
    year: 2023,
    doi: "10.1186/s13102-023-00713-4",
    url: "https://doi.org/10.1186/s13102-023-00713-4",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: [
      "training",
      "exercise-selection",
      "free-weights",
      "machines",
      "equipment",
      "strength",
      "hypertrophy",
    ],
    evidenceLevel: "systematic review and meta-analysis (13 studies, 1,016 participants)",
    kind: "paper",
    chosenBecause:
      "Answers whether machines are as good as free weights, a frequent question when equipment, confidence or joints limit exercise choice. Summarised from the full text.",
    sections: [
      {
        title: "What the review did",
        body:
          `The authors pooled 13 studies that directly compared free-weight training (barbell squat, bench press and similar) with machine training (leg press, chest press, Smith machine and similar) for at least six weeks in adults aged 18 to 60. There were 1,016 participants (789 men and 219 women); six studies used trained and seven untrained people, and none used competitive athletes. Studies lasted about nine weeks on average, with two to four sessions a week. Twelve studies measured maximal strength, five jump height and five muscle size.`,
      },
      {
        title: "Findings",
        body:
          `Strength gains followed the equipment. Tested on free weights, the free-weight groups gained a little more (standardised difference about 0.21); tested on machines, the machine groups tended to gain more (about 0.29, short of significance). When each group was tested on the equipment it trained with, gains were similar (0.08), and so were isometric strength, jump height and muscle growth (minus 0.06). Training status did not change these results, and both kinds of training improved every outcome measured.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `For general strength and muscle, free weights and machines both work, so the choice can rest on preference, access, comfort and goals. Strength is partly specific to the tool: someone who wants a bigger barbell squat should practise the barbell squat, and the same goes for machine lifts. The authors speculate that a mix of both may suit total muscle growth best, which the data did not test. Muscle-size results came from few studies, several using indirect measures, and the analysis did not adjust for differences in volume, effort or range of motion.`,
      },
    ],
  },
  {
    slug: "wolf_2023_partial_full_rom",
    label: "Wolf et al. 2023",
    title:
      "Partial vs full range of motion resistance training: a systematic review and meta-analysis",
    authors: ["Wolf M", "Androulakis-Korakakis P", "Fisher JP", "Schoenfeld BJ", "Steele J"],
    year: 2023,
    doi: "10.47206/ijsc.v3i1.182",
    url: "https://doi.org/10.47206/ijsc.v3i1.182",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: [
      "training",
      "range-of-motion",
      "exercise-selection",
      "hypertrophy",
      "strength",
      "joint-friendly",
    ],
    evidenceLevel: "systematic review and Bayesian meta-analysis (23 studies analysed)",
    kind: "paper",
    chosenBecause:
      "The broadest pooled comparison of partial and full range of motion across strength, size and power; it updates the Schoenfeld and Grgic 2020 entry. Summarised from the full text.",
    sections: [
      {
        title: "What the review did",
        body:
          `The authors searched to August 2022 and included 24 studies, published papers and some university theses, that compared training through a full range of motion with a partial range; 23 had usable data. They pooled strength, muscle size, power, sport-type and body-fat outcomes, and explored sub-groups: whether the partial range kept the muscle short or long, upper against lower body, machines against free weights, and whether the outcome test resembled one of the training styles.`,
      },
      {
        title: "Findings",
        body:
          `Full range came out ahead overall, but only trivially (standardised difference 0.12, 95 percent interval minus 0.02 to 0.26). Every outcome type leaned the same way by small amounts, for example about 0.14 for strength, 0.04 for muscle size and 0.19 for power, and upper and lower body looked alike. Strength was specific to the range trained: full range won by a small margin (0.32) on tests that resembled full-range training, while partial range did trivially better on tests that resembled partials. In an exploratory analysis, partials done with the muscle in a lengthened position tended to grow muscle more than full range (minus 0.28, with a wide interval crossing zero); partials at short muscle lengths did not.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `Full range of motion is a sensible default, but the gap is small enough that a shorter range is a fair choice when a joint, equipment or preference calls for it; for muscle growth, keeping the stretched part of the movement looks wiser than keeping the top. This is broader than the Schoenfeld and Grgic 2020 entry, which favoured full range for the legs; the authors credit newer studies and say an earlier four-study, legs-only meta-analysis may have overstated the full-range benefit. Sub-group findings are exploratory and underpowered, theses may not have had full peer review, and the lead author's doctoral funding came from a commercial coaching company.`,
      },
    ],
  },
  {
    slug: "kassiano_2022_exercise_variation",
    label: "Kassiano et al. 2022",
    title:
      "Does varying resistance exercises promote superior muscle hypertrophy and strength gains? A systematic review",
    authors: ["Kassiano W", "Nunes JP", "Costa B", "Ribeiro AS", "Schoenfeld BJ", "Cyrino ES"],
    year: 2022,
    doi: "10.1519/JSC.0000000000004258",
    url: "https://doi.org/10.1519/JSC.0000000000004258",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["training", "exercise-selection", "exercise-substitution", "hypertrophy", "strength"],
    evidenceLevel: "systematic review (8 studies, 241 young men)",
    kind: "paper",
    chosenBecause:
      "Answers whether lifters should keep changing exercises, and frames sensible substitutions when an exercise does not suit someone. Summarised from the abstract only.",
    sections: [
      {
        title: "What the review did",
        body:
          `Coaches often rotate exercises to keep training fresh or to work a muscle from different angles, but it was unclear whether that beats sticking with a fixed selection. This systematic review searched three databases and found eight trials that compared varied with fixed exercise selection for muscle growth and strength. All 241 participants were young men. Study quality was rated good to excellent on a standard physiotherapy trial scale. The results were described study by study rather than pooled into a single estimate.`,
      },
      {
        title: "Findings",
        body:
          `Exercise variation did make a difference, in both directions. Some planned, systematic variation appeared to improve growth across different regions of a muscle and to help maximise dynamic strength. Excessive or random variation, changing exercises very often, and swapping between exercises that give much the same stimulus appeared able to reduce gains. The authors recommend choosing variations deliberately, based on anatomy and how each exercise loads the muscle.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `Rotating exercises for its own sake is not needed. A modest set of well-chosen exercises that load a muscle in genuinely different ways, each kept long enough to progress, fits this evidence. Replacing an exercise that does not suit a person's joints or equipment with another that trains the same muscles is a considered, one-off swap rather than frequent rotation, which is in keeping with the review's idea of systematic variation. The evidence is eight small studies in young men, and this summary was written from the abstract only, so effect sizes and study details are not given.`,
      },
    ],
  },
  {
    slug: "keogh_2017_weight_training_injuries",
    label: "Keogh and Winwood 2017",
    title: "The epidemiology of injuries across the weight-training sports",
    authors: ["Keogh JWL", "Winwood PW"],
    year: 2017,
    doi: "10.1007/s40279-016-0575-0",
    url: "https://doi.org/10.1007/s40279-016-0575-0",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["injury-risk", "safety", "training", "strength"],
    evidenceLevel: "systematic review (20 studies of competitive weight-training athletes)",
    kind: "paper",
    chosenBecause:
      "Gives honest context for the question 'is lifting dangerous?', with injury rates across the lifting sports set against team sports. Summarised from the abstract only.",
    sections: [
      {
        title: "What the review did",
        body:
          `The authors searched four databases for studies of injury in competitive weight-training sports: weightlifting, powerlifting, bodybuilding, strongman, Highland Games and CrossFit. They found 20 eligible studies and rated each for risk of bias. Only five had a low risk of bias, and only four followed athletes forward in time; most asked athletes to recall injuries after the fact. Fourteen studies had more than 100 participants.`,
      },
      {
        title: "Findings",
        body:
          `Bodybuilding had the lowest injury rates, about 0.12 to 0.7 injuries per lifter per year, or about 0.24 to 1 per 1,000 hours of training. Strongman (about 4.5 to 6.1 per 1,000 hours) and Highland Games (about 7.5 per 1,000 hours) had the highest. The shoulder, lower back, knee, elbow and wrist or hand were injured most often, mostly as strains, tendon irritation and sprains. Age, sex, competitive level and bodyweight class made few clear differences. The authors concluded that these sports seem to have relatively low injury rates compared with common team sports.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `Lifting carries some risk, as any sport does, but the rate is low; the highest figures came from strongman and Highland Games, which involve unusual implements and events, and bodybuilding-style training was lowest. The body parts that come up most, shoulders, lower back, knees and elbows, deserve care with progression and technique. The data are mostly competitors recalling injuries, which is less reliable than tracking them, and recreational gym-goers were not the subject. This does not cover treating an injury; persistent pain is a reason to see a professional.`,
      },
    ],
  },
  {
    slug: "lauersen_2018_strength_dose_injury",
    label: "Lauersen et al. 2018",
    title:
      "Strength training as superior, dose-dependent and safe prevention of acute and overuse sports injuries: a systematic review, qualitative analysis and meta-analysis",
    authors: ["Lauersen JB", "Andersen TE", "Andersen LB"],
    year: 2018,
    doi: "10.1136/bjsports-2018-099078",
    url: "https://doi.org/10.1136/bjsports-2018-099078",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["injury-prevention", "injury-risk", "strength", "training", "volume"],
    evidenceLevel: "systematic review and meta-analysis (6 randomised trials, 7,738 participants)",
    kind: "paper",
    chosenBecause:
      "Adds dose-response evidence to the Lauersen 2014 entry: more strength training went with fewer sports injuries, which supports encouraging consistent lifting. Summarised from the abstract only.",
    sections: [
      {
        title: "What the review did",
        body:
          `Two of the authors of the Lauersen 2014 entry narrowed their focus to randomised trials that used strength training to prevent sports injuries in people who were not injured. Searching four databases to July 2017, they found six trials testing five programmes, with 7,738 participants aged 12 to 40 who had 177 sudden or overuse injuries between them. The trials were published from 2003 to 2016, five in Europe and one in Africa.`,
      },
      {
        title: "Findings",
        body:
          `Strength training cut injury risk to about a third of the control rate (risk ratio 0.338, 95 percent confidence interval 0.238 to 0.480). The result held across robustness checks, the strength of evidence was rated high, and there was no sign of publication bias. In a follow-up regression, a 10 percent increase in strength training volume went with an injury risk more than four percentage points lower, and both more volume and higher intensity were linked to lower risk. The trials were judged well run, with high compliance and no safety concerns.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `Regular, progressive strength training is one of the best-supported ways to lower sports injury risk, and within the range studied more of it seemed to help further. The evidence is only six trials in organised sport, some including teenagers, with programmes aimed at particular injuries, so it does not set a dose for gym-goers and cannot promise that anyone will avoid injury. This summary was written from the abstract only.`,
      },
    ],
  },
  {
    slug: "impellizzeri_2020_acwr_pitfalls",
    label: "Impellizzeri et al. 2020",
    title: "Acute:chronic workload ratio: conceptual issues and fundamental pitfalls",
    authors: ["Impellizzeri FM", "Tenan MS", "Kempton T", "Novak A", "Coutts AJ"],
    year: 2020,
    doi: "10.1123/ijspp.2019-0864",
    url: "https://doi.org/10.1123/ijspp.2019-0864",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["acwr", "load-management", "injury-risk", "injury-prevention", "progression"],
    evidenceLevel: "methodological critique",
    kind: "paper",
    chosenBecause:
      "The main critique of the acute-to-chronic workload ratio, needed so Coach presents the Gabbett 2016 entry's ratio fairly and never as an injury predictor. Summarised from the abstract only.",
    sections: [
      {
        title: "What the paper argues",
        body:
          `The acute-to-chronic workload ratio compares a recent week of training load with the average of several recent weeks, and it became the most popular load-based injury warning sign in sport. These authors point out that advising people to change their ratio in order to change their injury risk assumes the ratio causes injuries, and that no study had even tried to estimate that cause and effect properly. In their view, managing the ratio to prevent injuries is therefore a conjecture that reads too much into the available data.`,
      },
      {
        title: "The specific problems",
        body:
          `They give several reasons. A causal link with injury has not been shown. Ratios like this behave poorly as statistics, so the measure is inaccurate even in the version where the recent week is left out of the longer average. There is little theory explaining why the ratio itself should matter, the measure is ambiguous, and its relationship with injury is neither consistent nor one-directional. They conclude that no evidence supports using the ratio in load-management systems or in training advice meant to reduce injuries, and that it adds noise and can create statistical artefacts.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `This directly challenges one part of the Gabbett 2016 entry in this library, which proposed the ratio as a useful way to spot spikes in load. Coach should present both sides: Gabbett's wider point, that well-prepared hard training is protective and large sudden jumps are a plausible risk, remains a sensible coaching habit, but the ratio's numbers should not be quoted as safe zones or used to forecast injury. A 2021 follow-up led by the same author reanalysed published data and recommended dropping the ratio altogether. The research behind the ratio comes mostly from team sport, and this summary was written from the abstract only.`,
      },
    ],
  },
];
