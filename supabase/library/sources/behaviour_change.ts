import type { LibrarySource } from "../../functions/_shared/library/types.ts";

// How a coach helps people change behaviour and keep it up (E2.1).

export const behaviourChangeSources: readonly LibrarySource[] = [
  {
    slug: "zhu_2024_motivational_interviewing",
    label: "Zhu et al. 2024",
    title:
      "Effectiveness of behavioural interventions with motivational interviewing on physical activity outcomes in adults: systematic review and meta-analysis",
    authors: ["Zhu S", "Sinha D", "Kirk M", "Michalopoulou M", "Hajizadeh A", "Wren G"],
    year: 2024,
    doi: "10.1136/bmj-2023-078713",
    url: "https://doi.org/10.1136/bmj-2023-078713",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["behaviour-change", "coaching-communication", "activity", "adherence", "motivation"],
    evidenceLevel: "systematic review and meta-analysis (97 randomised trials)",
    kind: "paper",
    chosenBecause:
      "The strongest recent test of whether a motivational-interviewing coaching style raises activity, with a frank statement of how weak and short-lived the evidence is. Summarised from the abstract only.",
    sections: [
      {
        title: "What the review did",
        body: `Motivational interviewing is a counselling style in which the helper asks open questions, reflects back what the person says and draws out their own reasons for change. The reviewers searched seven databases up to March 2023 for randomised trials comparing a behavioural programme that included motivational interviewing with a similar programme without it, in adults, measuring physical activity or sedentary time. They found 129 papers on 97 trials with 27,811 people.`,
      },
      {
        title: "Results",
        body: `Programmes that included motivational interviewing did better than their comparators on total physical activity (about 1,323 extra steps a day, low-certainty evidence), on moderate to vigorous activity (about 95 extra minutes a week, very low certainty) and on sedentary time (about 51 minutes a day less, very low certainty). But when the comparator was a programme of similar intensity, there was no evidence of a difference. The effect faded over time, and there was no evidence of a benefit beyond one year. Most trials enrolled people with a health condition, and for the general population there was no evidence of an effect on moderate to vigorous activity or sedentary time.`,
      },
      {
        title: "Practical reading and limits",
        body: `A conversational, question-led style is a sensible way to coach, but it should not be sold as a proven way to raise activity: the benefit could not be isolated to the interviewing style itself, it fades, and the certainty is low. Coach can ask what the person wants and what gets in the way before suggesting changes, and should keep supporting them over months and not expect one chat to last. Most of the evidence is from people with health conditions, so for healthy lifters it is an extrapolation.`,
      },
    ],
  },
  {
    slug: "lally_2010_habit_formation",
    label: "Lally et al. 2010",
    title: "How are habits formed: modelling habit formation in the real world",
    authors: ["Lally P", "van Jaarsveld CHM", "Potts HWW", "Wardle J"],
    year: 2010,
    doi: "10.1002/ejsp.674",
    url: "https://doi.org/10.1002/ejsp.674",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["behaviour-change", "habits", "adherence", "consistency", "coaching-communication"],
    evidenceLevel: "observational study (96 volunteers over 12 weeks)",
    kind: "paper",
    chosenBecause:
      "The standard study of how long a new daily habit takes to feel automatic, which answers 'how long until this becomes easy?' without a made-up number. Summarised from the abstract only.",
    sections: [
      {
        title: "What the study did",
        body: `Ninety-six volunteers each picked one eating, drinking or activity behaviour and did it every day in the same situation, for example after breakfast, for 12 weeks. Every day they rated how automatic the behaviour felt and recorded whether they did it. Eighty-two gave enough data to analyse.`,
      },
      {
        title: "Results",
        body: `Automaticity rose in a curve that climbs quickly at first and then levels off. The model fitted for 62 people, and fitted well for 39 of them. Doing the behaviour more consistently went with a better fit. The time to reach 95 percent of each person's own plateau ranged from 18 to 254 days, so it can take a very long time and differs a great deal between people. Missing a single opportunity did not materially affect the process.`,
      },
      {
        title: "Practical reading and limits",
        body: `Coach should not promise a fixed number of days to form a habit. The findings support small, specific actions tied to a steady cue, repeated consistently, and treating a missed day as no reason to quit. The volunteers chose their own behaviour and rated automaticity themselves, and the study did not test complex routines such as a full training programme.`,
      },
    ],
  },
];
