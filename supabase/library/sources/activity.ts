import type { LibrarySource } from "../../functions/_shared/library/types.ts";

// Cardio and everyday activity guidelines for adults.

export const activitySources: readonly LibrarySource[] = [
  {
    slug: "acsm_2011_exercise_quantity",
    label: "Garber et al. 2011 (ACSM)",
    title:
      "American College of Sports Medicine position stand: quantity and quality of exercise for developing and maintaining cardiorespiratory, musculoskeletal, and neuromotor fitness in apparently healthy adults",
    authors: ["Garber CE", "Blissmer B", "Deschenes MR", "Franklin BA", "Lamonte MJ", "Lee IM"],
    year: 2011,
    doi: "10.1249/MSS.0b013e318213fefb",
    url: "https://doi.org/10.1249/MSS.0b013e318213fefb",
    licence: "Publisher copyright (no open licence); stored as an own-words summary with citation",
    region: ["global"],
    topics: ["cardio", "activity", "strength", "flexibility", "training", "guidelines"],
    evidenceLevel: "position stand",
    kind: "position_stand",
    chosenBecause:
      "A complete weekly template covering cardio, strength, balance and flexibility, plus the point that something is better than nothing; Tracend's standard cites it.",
    sections: [
      {
        title: "Weekly amounts",
        body: `For healthy adults this position stand recommends moderate-intensity cardio of at least 30 minutes on 5 or more days a week (150 minutes or more), or vigorous-intensity cardio of at least 20 minutes on 3 or more days (75 minutes or more), or a mix of the two, reaching about 500 to 1000 MET-minutes a week (a MET-minute is a unit that scales time by how hard the activity is).

Resistance exercise for each major muscle group is recommended on 2 to 3 days a week, along with balance, agility and coordination (neuromotor) work. Flexibility exercises for the main muscle-tendon groups, a total of 60 seconds each, on at least 2 days a week help maintain joint range of movement.`,
      },
      {
        title: "Individualising and doing less",
        body: `The programme should be changed to suit a person's usual activity, physical function, health, response to exercise and own goals. Adults who cannot or do not want to reach these targets still gain from smaller amounts. There are also health benefits from sitting less and breaking up long periods of sitting with short bouts of activity.`,
      },
      {
        title: "Practical reading and limits",
        body: `Use these amounts as a weekly frame: a mix of cardio, strength, balance and flexibility, adapted to the person. The benefits of exercise clearly outweigh the risks for most adults. The document is from 2011 and is for apparently healthy adults; it does not replace medical advice for people with conditions.`,
      },
    ],
  },
  {
    slug: "who_2020_activity_guidelines",
    label: "Bull et al. 2020 (WHO)",
    title: "World Health Organization 2020 guidelines on physical activity and sedentary behaviour",
    authors: ["Bull FC", "Al-Ansari SS", "Biddle S", "Borodulin K", "Buman MP", "Cardon G"],
    year: 2020,
    doi: "10.1136/bjsports-2020-102955",
    url: "https://doi.org/10.1136/bjsports-2020-102955",
    licence: "CC BY 4.0 (open access); own-words summary",
    region: ["global"],
    topics: ["cardio", "activity", "strength", "sedentary", "guidelines"],
    evidenceLevel: "public health guideline",
    kind: "guideline",
    chosenBecause:
      "The international reference on how much activity adults need, and the safest public baseline for any country; free to read.",
    sections: [
      {
        title: "What adults should do",
        body: `The World Health Organization advises all adults to do 150 to 300 minutes of moderate-intensity aerobic activity a week, or 75 to 150 minutes of vigorous-intensity activity, or an equivalent mix of the two. It also recommends regular muscle-strengthening activity for every age group, and for adults that means working the major muscle groups on two or more days a week.`,
      },
      {
        title: "Core messages",
        body: `Some activity is better than none, and more activity is better for health outcomes. The guidelines also recommend reducing sedentary behaviour, although the evidence was not strong enough to put a number on how much sitting is too much. Both aerobic and muscle-strengthening activity matter.`,
      },
      {
        title: "What is new",
        body: `Compared with the 2010 version, the 2020 guidelines add specific recommendations for pregnant and postpartum women and for people living with chronic conditions or disability, and they give a first recommendation to limit sedentary time.`,
      },
      {
        title: "Practical reading and limits",
        body: `These are population-level minimums for health, not training targets for performance or physique goals. Gym users who lift and walk regularly usually meet them easily; people starting from low activity benefit most from small steady increases. Tracend's scope excludes pregnancy and medical conditions, so the special-population recommendations are context, not something Coach applies.`,
      },
    ],
  },
  {
    slug: "piercy_2018_us_guidelines",
    label: "Piercy et al. 2018 (US guidelines)",
    title: "The Physical Activity Guidelines for Americans",
    authors: ["Piercy KL", "Troiano RP", "Ballard RM", "Carlson SA", "Fulton JE", "Galuska DA"],
    year: 2018,
    doi: "10.1001/jama.2018.14854",
    url: "https://doi.org/10.1001/jama.2018.14854",
    licence:
      "Publisher copyright (JAMA summary of a US government publication); stored as an own-words summary with citation",
    region: ["US"],
    topics: ["cardio", "activity", "strength", "guidelines"],
    evidenceLevel: "public health guideline",
    kind: "guideline",
    chosenBecause:
      "The national guideline Americans meet in practice; useful for US users and for the point that the least active people gain the most from small increases.",
    sections: [
      {
        title: "What the guidelines say for adults",
        body: `The second edition of the Physical Activity Guidelines for Americans recommends that adults do at least 150 to 300 minutes a week of moderate-intensity aerobic activity, or 75 to 150 minutes of vigorous activity, or an equivalent combination, plus muscle-strengthening activities on two or more days a week. Older adults should add balance training to a multicomponent routine.`,
      },
      {
        title: "How they were built",
        body: `An advisory committee reviewed the science, covering 38 questions and 104 sub-questions, and graded the strength of evidence. Only evidence graded strong or moderate underpinned the main guidelines.`,
      },
      {
        title: "Key messages",
        body: `Moving more and sitting less benefits nearly everyone. People who do the least physical activity gain the most from even modest increases. Both aerobic and muscle-strengthening activity are beneficial, and activity helps people feel, function and sleep better and lowers the risk of many chronic diseases.`,
      },
      {
        title: "Practical reading and limits",
        body: `The adult targets match the World Health Organization's, so they can be quoted together; for a US user, this is the national guidance. The recommendations for children, pregnancy and chronic conditions sit outside Tracend's scope.`,
      },
    ],
  },
  {
    slug: "paluch_2022_daily_steps",
    label: "Paluch et al. 2022",
    title: "Daily steps and all-cause mortality: a meta-analysis of 15 international cohorts",
    authors: ["Paluch AE", "Bajpai S", "Bassett DR", "Carnethon MR", "Ekelund U", "Evenson KR"],
    year: 2022,
    doi: "10.1016/S2468-2667(21)00302-9",
    url: "https://doi.org/10.1016/S2468-2667(21)00302-9",
    licence: "CC BY 4.0 (open access); own-words summary",
    region: ["global"],
    topics: ["activity", "steps", "cardio", "health"],
    evidenceLevel: "meta-analysis of 15 cohorts (47,471 adults)",
    kind: "paper",
    chosenBecause:
      "Gives an evidence-based answer to 'do I really need 10,000 steps?', a question the app's step data raises daily.",
    sections: [
      {
        title: "What the study did",
        body: `The researchers pooled 15 studies of adults who wore step counters, 47,471 people in all, followed for a median of about seven years during which 3,013 died. They asked how the number of steps per day, and the pace of stepping, relate to the risk of dying from any cause.`,
      },
      {
        title: "Findings",
        body: `Compared with the least active quarter (about 3,600 steps a day), the next quarter (about 5,800 steps) had roughly 40 percent lower risk of death, the third (about 7,800 steps) 45 percent lower, and the most active (about 10,900 steps) 53 percent lower. For adults aged 60 and over, risk kept falling until roughly 6,000 to 8,000 steps a day. For adults under 60 it kept falling until roughly 8,000 to 10,000 steps a day.

After steps per day were accounted for, a higher stepping pace showed a weaker link to lower mortality.`,
      },
      {
        title: "Practical reading and limits",
        body: `There is no magic at 10,000 steps: benefits rise steadily from low counts, so adding a couple of thousand steps is worthwhile for someone who does little. These are observational results, linking steps and long-term health, not proof that adding steps causes the change, and fitter or healthier people may walk more. The outcome studied was death from any cause, not fat loss or muscle gain.`,
      },
    ],
  },
];
