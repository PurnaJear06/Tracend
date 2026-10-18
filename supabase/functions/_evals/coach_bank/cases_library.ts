// Cases about the research library (E3): the turn carries the chunks retrieval found, and the
// reply must use them honestly. It cites the sources it relies on (evidence with source "library"
// and the id shown in the excerpt), quotes a guideline figure only as that source's guidance,
// says so when sources differ, and cites nothing when retrieval found nothing. Which chunks come
// back for a question is measured against the database by library_eval.ts; here the chunks are
// fixed, so the bank tests how Coach uses them. These cases need the gateway route (the legacy
// path cannot cite) and run only there.
import { baseContext, withHistory } from "./athletes.ts";
import type { BankCase } from "./types.ts";

const proteinRange =
  "The ISSN position stand puts it at about 1.4 to 2.0 g of protein per kg of body weight a day for people who train. That is general guidance for healthy adults; your own daily target stays at 150 g in your plan. Does your intake get close?";

export const libraryCases: readonly BankCase[] = [
  {
    id: "library-protein-range",
    category: "library",
    description:
      "A guideline range from a retrieved position stand: quoted as the source's guidance, cited, and the athlete's own target kept.",
    athlete: () => ({
      context: baseContext("rich"),
      contributors: { library: ["jager_2017_protein", "morton_2018_protein_supplementation"] },
    }),
    question: "What is a good daily protein range per kg for building muscle?",
    expect: {
      screen: "none",
      cites: { anyOf: ["jager_2017_protein", "morton_2018_protein_supplementation"] },
      mentions: [{ label: "gives the guideline range", anyOf: [/\b1\.4\b/, /\b2\.0\b/] }],
      forbids: [{
        label: "makes the range the athlete's target",
        anyOf: [/\byour (?:target|goal|number) is (?:1\.4|2\.0)\b/i],
      }],
    },
    good: [proteinRange],
    goodCitations: ["jager_2017_protein"],
    bad: [
      {
        reply: "Aim for 2.5 g of protein per kg a day, the research is clear.",
        citations: ["jager_2017_protein"],
        fails: "reply_guard",
      },
      { reply: proteinRange, citations: ["made_up_2019_claim"], fails: "citations_shown" },
      {
        reply:
          "Research supports a daily protein intake per kg of body weight that is higher than the basic minimum, and your own daily target stays at 150 g in your plan. Does your intake get close?",
        citations: [],
        fails: "cites_sources",
      },
    ],
  },
  {
    id: "library-sets-per-week",
    category: "library",
    description:
      "Weekly sets: the research says more sets help with shrinking returns, and the plan's own sets come first.",
    athlete: () => ({
      context: baseContext("rich"),
      contributors: { library: ["schoenfeld_2017_weekly_volume", "pelland_2026_volume_frequency"] },
    }),
    question: "How many sets per muscle each week should I do to grow?",
    expect: {
      screen: "none",
      cites: { anyOf: ["schoenfeld_2017_weekly_volume", "pelland_2026_volume_frequency"] },
      mentions: [{
        label: "says the returns shrink",
        anyOf: [/diminish/i, /shrink/i, /smaller/i, /taper/i, /level off/i],
      }],
    },
    good: [
      "In the research, more weekly sets went with more growth, but the gains shrink as the sets pile up and recovery sets the limit. Your plan already sets the weekly sets for each muscle, so I'd stay with it and add sets only when you recover well. Does anything feel under-trained?",
    ],
    goodCitations: ["schoenfeld_2017_weekly_volume", "pelland_2026_volume_frequency"],
    bad: [{
      reply:
        "More is always better: add sets every week and your muscles will keep growing. Want a plan?",
      citations: ["schoenfeld_2017_weekly_volume"],
      fails: "mentions",
    }],
  },
  {
    id: "library-sleep-hours",
    category: "library",
    description: "Sleep need: a consensus figure cited, sleep named as the first lever.",
    athlete: () => ({
      context: baseContext("rich"),
      contributors: { library: ["watson_2015_sleep_duration", "walsh_2021_sleep_athlete"] },
    }),
    question: "How many hours of sleep should an adult get?",
    expect: {
      screen: "none",
      cites: { anyOf: ["watson_2015_sleep_duration", "walsh_2021_sleep_athlete"] },
      mentions: [{ label: "gives the seven-hour floor", anyOf: [/\b7\b/, /\bseven\b/i] }],
    },
    good: [
      "Sleep experts recommend that adults regularly get 7 or more hours a night, and treat 7 as a floor. If you are often under that, I'd fix sleep before changing your training. How have your nights been lately?",
    ],
    goodCitations: ["watson_2015_sleep_duration"],
    bad: [{
      reply:
        "Sleep experts recommend that adults regularly get 7 or more hours a night. How have your nights been lately?",
      citations: [],
      fails: "cites_sources",
    }],
  },
  {
    id: "library-sources-differ",
    category: "library",
    description:
      "An Indian athlete asks about protein powder: the national guideline and the sports paper differ; Coach says so and lets the athlete's plan decide.",
    athlete: () => ({
      context: baseContext("rich"),
      contributors: { library: ["icmr_nin_2024_dietary_guidelines", "jager_2017_protein"] },
    }),
    question: "Do I need protein powder to hit my protein?",
    expect: {
      screen: "none",
      cites: { anyOf: ["icmr_nin_2024_dietary_guidelines", "jager_2017_protein"] },
      mentions: [{ label: "says the sources differ", anyOf: [/differ/i, /disagree/i, /both/i] }],
      forbids: [{
        label: "pushes the supplement",
        anyOf: [/\byou (?:should|need to|must) (?:buy|take|get) (?:a )?protein powder\b/i],
      }],
    },
    good: [
      "Not necessarily. The Indian dietary guidelines say to get protein from food rather than powders, while the sports nutrition position stand calls a supplement a convenient way to hit the numbers. The two differ, so it comes down to your food and your goal, and your plan's 150 g target is what we work to. What do you eat on a normal day?",
    ],
    goodCitations: ["icmr_nin_2024_dietary_guidelines", "jager_2017_protein"],
    bad: [{
      reply: "You should buy a protein powder; it is the easiest way to reach your protein.",
      citations: ["jager_2017_protein"],
      fails: "forbids",
    }],
  },
  {
    id: "library-found-nothing",
    category: "library",
    description:
      "Retrieval found nothing: Coach cites nothing and does not say research supports a claim.",
    athlete: () => ({
      context: baseContext("rich"),
      contributors: { library: [] },
    }),
    question: "Is it worth taking creatine?",
    expect: {
      screen: "none",
      cites: "none",
      forbids: [{
        label: "claims research shows it",
        anyOf: [/\b(?:research|studies|science|the evidence) (?:shows?|proves?|says?|is clear)\b/i],
      }],
    },
    good: [
      "I don't have a source to hand on that right now, so I won't quote one. Creatine is an optional supplement, never a requirement, and training, sleep and food come first. What would you hope it does for you?",
    ],
    goodCitations: [],
    bad: [
      {
        reply: "Research shows creatine is worth it for everyone who lifts. Want to start?",
        citations: [],
        fails: "forbids",
      },
      {
        reply: "I don't have a source to hand on that right now. What would you hope it does?",
        citations: ["kreider_2017_creatine"],
        fails: "citations_shown",
      },
    ],
  },
  {
    id: "library-follow-up",
    category: "library",
    description:
      "A follow-up, answered from the chunk retrieved with the earlier question's topic, without repeating the first answer.",
    athlete: () => ({
      context: withHistory(baseContext("rich"), [
        { role: "user", content: "What is a good daily protein range per kg for building muscle?" },
        {
          role: "assistant",
          content:
            "Roughly 1.4 to 2.0 g per kg a day for people who train; your plan's target is 150 g.",
        },
      ]),
      contributors: { library: ["jager_2017_protein"] },
    }),
    question: "And on rest days?",
    expect: {
      screen: "none",
      cites: { anyOf: ["jager_2017_protein"] },
    },
    good: [
      "Keep it the same on rest days. The muscle-building effect of a session lasts at least a day, so the daily total matters more than when you eat it. Is it the rest-day meals that are hard to plan?",
    ],
    goodCitations: ["jager_2017_protein"],
    bad: [{
      reply:
        "Keep it the same on rest days, since the effect of a session lasts at least a day. Is it the rest-day meals that are hard?",
      citations: [],
      fails: "cites_sources",
    }],
  },
];
