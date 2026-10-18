import type { LibrarySource } from "../../functions/_shared/library/types.ts";

// Cardio and fitness (interval versus steady training, cardiorespiratory fitness), cold-water
// immersion and training adaptations, and acute sleep loss. Summaries are written in Tracend's
// own words from each source's abstract or, for the open-access ones, its full text; no source
// text is copied.

export const cardioRecoverySources: readonly LibrarySource[] = [
  {
    slug: "wewege_2017_hiit_body_composition",
    label: "Wewege et al. 2017",
    title:
      "The effects of high-intensity interval training vs. moderate-intensity continuous training on body composition in overweight and obese adults: a systematic review and meta-analysis",
    authors: ["Wewege M", "van den Berg R", "Ward RE", "Keech A"],
    year: 2017,
    doi: "10.1111/obr.12532",
    url: "https://doi.org/10.1111/obr.12532",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["cardio", "hiit", "fat-loss", "body-composition", "time-efficient"],
    evidenceLevel: "systematic review and meta-analysis (13 trials)",
    kind: "paper",
    chosenBecause:
      "Answers the common question 'is interval training better than steady cardio for losing fat?' for people carrying extra weight, with a clear time-cost comparison. Summarised from the abstract only.",
    sections: [
      {
        title: "What the review did",
        body:
          `The authors pooled 13 trials that compared high-intensity interval training (HIIT) with moderate-intensity continuous training, such as steady jogging or cycling, in overweight or obese adults aged 18 to 45. Training lasted about 10 weeks on average, at roughly three sessions a week. They looked at direct measures of body fat, such as whole-body fat mass, and indirect ones, such as waist circumference.`,
      },
      {
        title: "Findings",
        body:
          `Both kinds of training reduced whole-body fat mass and waist circumference, and no body-composition measure differed between them. The interval programmes needed about 40 percent less training time. When the trials were split by exercise type, running-based training produced large reductions in fat mass for both styles, while cycling-based training did not reduce fat in these studies.

The authors note that the body-composition changes were modest and happened without much change in body weight.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `Interval and steady cardio did about the same job for fat loss here, so the choice can rest on preference, joints and time available: intervals are a time saver, not a shortcut. Fat can fall while scale weight barely moves, which is worth explaining to someone discouraged by the scale. The trials were short and in younger overweight adults, the running versus cycling split is a subgroup finding, and this summary is from the abstract only. Diet and energy balance still drive most fat loss. A later, widely shared meta-analysis claiming larger fat loss from intervals (Viana 2019) was retracted, so it is not in this library.`,
      },
    ],
  },
  {
    slug: "milanovic_2015_hiit_vo2max",
    label: "Milanović et al. 2015",
    title:
      "Effectiveness of high-intensity interval training (HIT) and continuous endurance training for VO2max improvements: a systematic review and meta-analysis of controlled trials",
    authors: ["Milanović Z", "Sporiš G", "Weston M"],
    year: 2015,
    doi: "10.1007/s40279-015-0365-0",
    url: "https://doi.org/10.1007/s40279-015-0365-0",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["cardio", "hiit", "vo2max", "cardio-fitness", "intensity"],
    evidenceLevel: "systematic review and meta-analysis (28 controlled trials, 723 adults)",
    kind: "paper",
    chosenBecause:
      "The standard comparison of interval and steady endurance training for raising aerobic fitness (VO2max), so Coach can say how much each helps and how small the gap is. Summarised from the abstract only.",
    sections: [
      {
        title: "What the review did",
        body:
          `The authors pooled 28 controlled trials with 723 healthy adults aged 18 to 45 (average age about 25, average starting VO2max about 41 mL per kg per minute). Programmes lasted at least two weeks and measured VO2max, the maximum rate at which the body can use oxygen, before and after. They compared continuous endurance training and high-intensity interval training (HIT) with no exercise, and with each other.`,
      },
      {
        title: "Findings",
        body:
          `Against no exercise, continuous endurance training raised VO2max by about 4.9 mL per kg per minute and interval training by about 5.5, both large improvements. Gains tended to be bigger in people who started less fit and in longer programmes.

Compared head to head, interval training came out slightly ahead, by about 1.2 mL per kg per minute, a possibly small benefit. The edge was a little larger with longer intervals, a higher work to rest ratio, longer programmes, older participants and lower starting fitness.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `Both styles build aerobic fitness well, and intervals give a modest extra lift for the time spent, so a mix that the person enjoys and can recover from is a sensible default. The studies were of young adults of about average starting fitness over short periods. The authors rated the head-to-head advantage only as possibly small, so it should be read as uncertain. This summary is from the abstract only. VO2max is one fitness marker; it does not by itself show health outcomes (see the Mandsager 2018 entry for the link between fitness and survival).`,
      },
    ],
  },
  {
    slug: "mandsager_2018_cardiorespiratory_fitness_mortality",
    label: "Mandsager et al. 2018",
    title:
      "Association of cardiorespiratory fitness with long-term mortality among adults undergoing exercise treadmill testing",
    authors: ["Mandsager K", "Harb S", "Cremer P", "Phelan D", "Nissen SE", "Jaber W"],
    year: 2018,
    doi: "10.1001/jamanetworkopen.2018.3605",
    url: "https://doi.org/10.1001/jamanetworkopen.2018.3605",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["cardio-fitness", "vo2max", "health", "cardio", "older-adults"],
    evidenceLevel: "retrospective cohort study (122,007 adults; observational)",
    kind: "paper",
    chosenBecause:
      "A very large study linking measured aerobic fitness with survival, which helps Coach explain why building cardio fitness matters for health and not only for looks or sport. Summarised from the full text.",
    sections: [
      {
        title: "What the study did",
        body:
          `Researchers at one US academic medical centre looked back at 122,007 adults (average age 53, 59 percent men) who did a symptom-limited treadmill test between 1991 and 2014. Fitness was estimated from the peak workload reached and ranked against people of the same age and sex: low (bottom quarter), below average, above average, high, and elite (top 2.3 percent). Deaths from any cause were tracked for a median of 8.4 years, and 13,637 people died. The analysis adjusted for age, sex, body mass index, heart disease, diabetes, smoking, other conditions and medicines.`,
      },
      {
        title: "Findings",
        body:
          `Each step up in fitness went with lower risk of death, with no point where the benefit stopped. Compared with the least fit group, the elite group had about one fifth of the adjusted risk. Being in the least fit group carried a risk similar to or larger than smoking, diabetes or known coronary disease. Elite fitness was linked with lower risk than high fitness overall, and this difference held in people aged 70 and over and in those with high blood pressure, but not in younger groups.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `This is an association, not proof that getting fitter causes longer life: fitter people may differ in genes, habits and health in ways the study could not measure, as the authors say. Participants were people referred for a clinical treadmill test, not a random sample of the public, and fitness was measured once. Coach can use it to explain that aerobic fitness is a strong, changeable health marker and that moving up from low fitness is linked with the biggest change, without promising a longer life or a specific risk reduction to any individual.`,
      },
    ],
  },
  {
    slug: "roberts_2015_cold_water_strength_adaptation",
    label: "Roberts et al. 2015",
    title:
      "Post-exercise cold water immersion attenuates acute anabolic signalling and long-term adaptations in muscle to strength training",
    authors: ["Roberts LA", "Raastad T", "Markworth JF", "Figueiredo VC", "Egner IM", "Shield A"],
    year: 2015,
    doi: "10.1113/JP270570",
    url: "https://doi.org/10.1113/JP270570",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["cold-water-immersion", "recovery", "hypertrophy", "strength", "training"],
    evidenceLevel:
      "randomised controlled trial (21 men) plus a mechanistic crossover study (9 men)",
    kind: "paper",
    chosenBecause:
      "The best-known trial showing that routine ice baths after lifting can reduce strength and muscle gains, which Coach needs when someone asks whether to plunge after every session. Summarised from the full text.",
    sections: [
      {
        title: "What the study did",
        body:
          `The paper reports two studies. In the training study, 21 physically active men with at least a year of strength-training experience did mainly lower-body lifting twice a week for 12 weeks and spent 10 minutes after every session either sitting waist-deep in water at about 10 °C or cycling easily. In the mechanistic study, nine active men did single-leg strength exercise on separate days followed by either cold water or active recovery, with muscle samples taken before and 2, 24 and 48 hours after.`,
      },
      {
        title: "Findings",
        body:
          `Strength and muscle mass rose more with active recovery than with cold water. In the active recovery group, isokinetic work rose by about 19 percent, the size of fast-twitch (type II) fibres by about 17 percent and the number of nuclei per fibre by about 26 percent; none of these rose significantly with cold water.

In the muscle samples, markers of satellite cells (the stem cells that help muscle grow and repair) and of a key growth signalling enzyme rose less after cold water than after active recovery. The authors suggest that regular cold water after lifting may blunt the processes behind long-term gains, so it may be worth dropping as an after-every-session habit.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `For someone whose goal is strength or muscle, plunging after every lifting session may cost some of the gains, so it is better kept for times when feeling fresh soon matters more than adaptation. The trial was small, only young men took part, the water was about 10 °C up to the waist, and training was mainly lower body. Later work found the strength cost is small and may be limited to immersing only the trained limbs (Fyfe 2019; Grgic 2022 meta-analysis). It does not say cold water is harmful in general: the Dupuy 2018 entry shows it can ease soreness for a day or two, and the Malta 2021 entry pools the training studies.`,
      },
    ],
  },
  {
    slug: "malta_2021_cold_water_training_adaptations",
    label: "Malta et al. 2021",
    title:
      "The effects of regular cold-water immersion use on training-induced changes in strength and endurance performance: a systematic review with meta-analysis",
    authors: ["Malta ES", "Dutra YM", "Broatch JR", "Bishop DJ", "Zagatto AM"],
    year: 2021,
    doi: "10.1007/s40279-020-01362-0",
    url: "https://doi.org/10.1007/s40279-020-01362-0",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["cold-water-immersion", "recovery", "strength", "cardio", "training"],
    evidenceLevel: "systematic review and meta-analysis (8 studies)",
    kind: "paper",
    chosenBecause:
      "Pools the training studies on regular cold-water immersion, so Coach can separate the short-term soreness benefit from the longer-term cost to strength gains and the apparent lack of effect on endurance. Summarised from the abstract only.",
    sections: [
      {
        title: "What the review did",
        body:
          `The authors searched three databases to November 2019 for controlled human studies in which people used cold-water immersion at 15 degrees C or colder regularly alongside a training programme, with performance tested before and after. Eight studies were included, covering both resistance training and endurance training.`,
      },
      {
        title: "Findings",
        body:
          `With resistance training, regular cold-water immersion reduced gains in one-repetition maximum, maximal isometric strength and strength endurance (pooled standardised difference about minus 0.6, a moderate effect), and also in ballistic, explosive efforts by a similar amount.

With endurance training, it made no clear difference to maximal aerobic power in a graded test or to time-trial performance. In short, regular cold water after lifting cost some strength gains, while endurance results were unchanged.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `This sits alongside the Dupuy 2018 entry, which found cold and other methods ease soreness for a day or two: both can be true. Cold water may help someone feel better between closely spaced sessions or events, but used after most lifting sessions it can cost strength. For endurance work it looks roughly neutral. Only eight studies were pooled. A later meta-analysis of ten studies (Grgic 2022) found a smaller cost to strength, and no clear cost when the whole body rather than only the trained limbs was immersed, so the size of the effect is uncertain. The summary is from the abstract only, and the paper does not test occasional use or brief cold showers. Coach should present cold water as optional and timed to the goal, not as a recovery requirement.`,
      },
    ],
  },
  {
    slug: "craven_2022_sleep_loss_performance",
    label: "Craven et al. 2022",
    title:
      "Effects of acute sleep loss on physical performance: a systematic and meta-analytical review",
    authors: ["Craven J", "McCartney D", "Desbrow B", "Sabapathy S", "Bellinger P", "Roberts L"],
    year: 2022,
    doi: "10.1007/s40279-022-01706-y",
    url: "https://doi.org/10.1007/s40279-022-01706-y",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["sleep-loss", "sleep", "performance", "recovery", "strength"],
    evidenceLevel: "systematic review and meta-analysis (69 publications, 959 participants)",
    kind: "paper",
    chosenBecause:
      "Quantifies how much one short night hurts training and which kind of short night matters most, so Coach can give sensible advice after poor sleep. Summarised from the full text.",
    sections: [
      {
        title: "What the review did",
        body:
          `The authors pooled 69 publications (959 participants, 89 percent men) that compared exercise performance after normal sleep (more than 6 hours) with performance after sleep loss (6 hours or less in 24 hours). Sleep loss was split into total deprivation (no sleep), restriction, early restriction (going to bed late) and late restriction (waking early). Tasks covered strength, power, sprints, intervals, endurance and sport skills, 227 outcomes in all.`,
      },
      {
        title: "Findings",
        body:
          `Overall, performance fell by about 7.6 percent after sleep loss, and every exercise type was affected: skill tasks the most (about 21 percent), then anaerobic power and interval work (about 6 percent), endurance (about 5.5 percent) and strength (about 3 percent). For strength, lower-body tasks suffered while upper-body tasks did not.

Total deprivation and waking early hurt consistently; going to bed late mostly did not, except for skill and endurance tasks. Performance dropped by roughly 0.4 percent for each extra hour awake before the task. Afternoon and evening sessions were consistently affected, while morning sessions were largely spared.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `After a short night, a guide is to train earlier in the day if possible and to expect skill, power and heavy leg work to feel harder. When a short night cannot be avoided, the authors suggest that going to bed late beats waking very early, for example travelling the night before instead of at dawn. Results varied widely between studies, almost all participants were men, sleep quality and repeated short nights were not tested, and training status was not analysed. This is about one or two bad nights, not long-term sleep habits (see the Watson 2015 and Walsh 2021 entries).`,
      },
    ],
  },
  {
    slug: "lamon_2021_sleep_deprivation_muscle_protein",
    label: "Lamon et al. 2021",
    title:
      "The effect of acute sleep deprivation on skeletal muscle protein synthesis and the hormonal environment",
    authors: ["Lamon S", "Morabito A", "Arentson-Lantz E", "Knowles O", "Vincent GE", "Condo D"],
    year: 2021,
    doi: "10.14814/phy2.14660",
    url: "https://doi.org/10.14814/phy2.14660",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["sleep-loss", "sleep", "recovery", "hypertrophy", "protein"],
    evidenceLevel: "randomised crossover trial (13 healthy young adults)",
    kind: "paper",
    chosenBecause:
      "A controlled test of what one sleepless night does to muscle building after a meal, which helps Coach explain why sleep matters for muscle without overstating it. Summarised from the full text.",
    sections: [
      {
        title: "What the study did",
        body:
          `Thirteen healthy young adults (seven men, six women) who normally slept at least seven hours each did two trials in random order, at least four weeks apart: one night of normal sleep at home and one night kept fully awake in a laboratory. Meals were standardised, no strenuous exercise was done, and the next day the researchers measured the rate of muscle protein synthesis after meals (from 13:00 to 15:00), hormone levels across the day and markers of muscle protein breakdown.`,
      },
      {
        title: "Findings",
        body:
          `After the sleepless night, muscle protein synthesis after eating was about 18 percent lower. Across the day, cortisol (a hormone that favours breakdown) was about 21 percent higher and testosterone about 24 percent lower. Gene markers of muscle protein breakdown did not change.

All the men, but not all the women, showed lower protein synthesis after the sleepless night, and the fall in testosterone looked mostly like a male pattern. The study was not designed to compare the sexes, so the authors treat this as a lead for future work.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `One night without sleep made muscle less responsive to food the next day, which is one reason Coach treats sleep as part of training. The study measured short-term markers in a small group, without exercise, and did not measure muscle size, so it does not show that one bad night costs muscle. Total sleep loss is more extreme than a short night. A reasonable reading is that repeated poor sleep may hold back progress, and that protecting sleep matters more than any supplement.`,
      },
    ],
  },
];
