import type { LibrarySource } from "../../functions/_shared/library/types.ts";

// Joint-friendly training and injury prevention for healthy adults. Nothing here is rehab or
// diagnosis; Tracend excludes both.

export const jointFriendlySources: readonly LibrarySource[] = [
  {
    slug: "schoenfeld_2020_range_of_motion",
    label: "Schoenfeld and Grgic 2020",
    title:
      "Effects of range of motion on muscle development during resistance training interventions: a systematic review",
    authors: ["Schoenfeld BJ", "Grgic J"],
    year: 2020,
    doi: "10.1177/2050312120901559",
    url: "https://doi.org/10.1177/2050312120901559",
    licence: "CC-BY-NC-4.0",
    verbatimAllowed: false,
    lastReviewed: "2026-10-17",
    region: ["global"],
    topics: ["training", "hypertrophy", "joint-friendly", "exercise-selection"],
    evidenceLevel: "systematic review (6 studies)",
    kind: "paper",
    chosenBecause:
      "Answers whether partial range of motion is a fair swap when a full range bothers a joint, using the best controlled evidence available. Summarised from the abstract only.",
    sections: [
      {
        title: "What the review did",
        body: `The authors reviewed six controlled studies (135 participants, mostly men) that compared training through a full range of motion with a partial range over several weeks and measured changes in muscle size. Four studies trained the legs and two trained the arms. The studies were of high methodological quality, but there are few of them.`,
      },
      {
        title: "Findings",
        body: `For the lower body, a full range of motion built more muscle than a partial range. For the upper body, results were limited and conflicting, so no firm conclusion was possible. No study had looked at the trunk muscles. There were hints that the best range may depend on the muscle, which still needs testing.`,
      },
      {
        title: "Practical reading and limits",
        body: `Taking the full range that the person can control comfortably is a good default for the legs. If a position at the end of the range bothers a joint, using a slightly shorter range that stays pain-free is a reasonable adjustment, particularly for the arms, where the evidence does not favour either choice. This does not tell anyone how to train around an injury; persistent pain is a reason to stop and see a professional. The evidence base is small and mostly in healthy young men.`,
      },
    ],
  },
  {
    slug: "lauersen_2014_injury_prevention",
    label: "Lauersen et al. 2014",
    title:
      "The effectiveness of exercise interventions to prevent sports injuries: a systematic review and meta-analysis of randomised controlled trials",
    authors: ["Lauersen JB", "Bertelsen DM", "Andersen LB"],
    year: 2014,
    doi: "10.1136/bjsports-2013-092538",
    url: "https://doi.org/10.1136/bjsports-2013-092538",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-17",
    region: ["global"],
    topics: ["injury-prevention", "joint-friendly", "strength", "training"],
    evidenceLevel: "systematic review and meta-analysis (25 trials)",
    kind: "paper",
    chosenBecause:
      "The strongest evidence that regular strength training itself lowers injury risk, which supports telling users that building strength protects joints. Summarised from the abstract only.",
    sections: [
      {
        title: "What the review did",
        body: `The authors pooled 25 randomised trials with 26,610 participants and 3,464 injuries to see whether exercise programmes prevent sports injuries. They split the programmes into strength training, stretching, balance and coordination (proprioception) training and combinations, and counted sudden injuries and overuse injuries separately.`,
      },
      {
        title: "Findings",
        body: `Strength training cut sports injuries to less than a third of the control rate (risk ratio about 0.32). Balance training roughly halved injuries (about 0.55), and programmes that combined several exercise types lowered them by about a third (about 0.66). Stretching alone showed no clear benefit (about 0.96). Overall, exercise programmes reduced both sudden injuries and overuse injuries, with overuse injuries almost halved.`,
      },
      {
        title: "Practical reading and limits",
        body: `Regular strength work, and for some people balance work, is a sensible part of staying injury-free, while stretching on its own is not a good bet for preventing injuries. Most trials involved athletes in organised sport and tested injury prevention in healthy people. The review does not cover treating an existing injury, and Coach should not use it to promise that a person will not get hurt.`,
      },
    ],
  },
  {
    slug: "gabbett_2016_training_load",
    label: "Gabbett 2016",
    title: "The training-injury prevention paradox: should athletes be training smarter and harder?",
    authors: ["Gabbett TJ"],
    year: 2016,
    doi: "10.1136/bjsports-2015-095788",
    url: "https://doi.org/10.1136/bjsports-2015-095788",
    licence: "CC-BY-NC-4.0",
    verbatimAllowed: false,
    lastReviewed: "2026-10-17",
    region: ["global"],
    topics: ["injury-prevention", "joint-friendly", "training", "progression", "load-management"],
    evidenceLevel: "narrative review and model",
    kind: "paper",
    chosenBecause:
      "Explains why gradual load increases protect against injury and why too little training is also a risk, the logic behind Tracend's progression caps. Summarised from the abstract only.",
    sections: [
      {
        title: "The idea",
        body: `It is common to assume that more training means more injuries. This paper argues the picture is more subtle. People who are used to high training loads tend to have fewer injuries than people who train less, because regular hard training builds the physical qualities that protect the body. The author calls this the training-injury prevention paradox.`,
      },
      {
        title: "What causes the damage",
        body: `The central claim is that non-contact injuries are less likely to be caused by training itself than by a poorly planned programme. Large and fast jumps in training load are likely to be behind many soft-tissue injuries, and under-training can raise risk too, because the body is not prepared for what is asked of it.`,
      },
      {
        title: "Monitoring load",
        body: `To manage this, the paper recommends tracking both recent (acute) load and longer-term (chronic) load, using internal measures such as effort and external measures such as the work done. It describes the acute-to-chronic workload ratio, which compares a recent week with the average of recent weeks, as a useful way to spot sudden spikes.`,
      },
      {
        title: "Practical reading and limits",
        body: `For coaching, the message is to build load gradually, avoid sharp jumps in volume or intensity, and not to fear training hard once the body has been prepared. The paper is a model drawn mostly from team-sport research, so Coach should treat the acute-to-chronic ratio as one useful heuristic rather than a precise injury predictor.`,
      },
    ],
  },
];
