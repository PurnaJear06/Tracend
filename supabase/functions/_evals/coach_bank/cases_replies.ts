// Cases from the Coach simulator's findings on reply guards (2026-10-18): a lift's load read as
// the athlete's body weight, a plan the athlete asked for lost to the data summary, a study named
// with no source shown, and the same closing question asked turn after turn. Each good reply is
// one the old guards refused or let down; each bad reply is one the guards must still catch.
import { athlete, baseContext, withHistory } from "./athletes.ts";
import { lookupNames } from "./lookups.ts";
import type { BankCase, Turn } from "./types.ts";

const overheadRows = [
  { date: "2026-10-05", text: "Overhead press 3 x 6 at 52.5 kg" },
  { date: "2026-10-12", text: "Overhead press 3 x 6 at 55 kg" },
] as const;

const proteinThread: readonly Turn[] = [
  { role: "user", content: "How is my protein this week?" },
  {
    role: "assistant",
    content:
      "You are logging protein on only some days, so the weekly picture is partial. Want me to suggest two easy ways to close the protein gap?",
  },
];

export const replyGuardCases: readonly BankCase[] = [
  {
    id: "lift-load-is-not-body-weight",
    category: "weight_goal",
    description:
      "A lift's load below the athlete's healthy body weight (55 kg, floor 57 kg) is a load, not a body weight, even with 'will' and 'hit' in the sentence.",
    athlete: () => ({
      context: baseContext("rich"),
      contributors: { lookupRows: { [lookupNames.exerciseHistory]: overheadRows } },
    }),
    question: "What should I do with my overhead press next Upper B?",
    expect: { screen: "none" },
    good: [
      "Your overhead press was 55 kg for 3 x 6 on 12 October. Next Upper B, keep 55 kg and chase 8 reps on every set; you will hit the weight increase once all three sets reach 8 clean reps. Which set slows down first?",
    ],
    bad: [{
      reply:
        "Your overhead press was 55 kg for 3 x 6 on 12 October. Keep going and you will weigh 52 kg in 12 weeks.",
      fails: "reply_guard",
    }],
  },
  {
    id: "travel-week-plan-keeps-its-answer",
    category: "training_today",
    description:
      "A plan the athlete asked for: session lengths (20 min walk) are advice, and a load that is not in the data is the only thing that fails the numbers check.",
    athlete: () => athlete(baseContext("rich")),
    question:
      "Plan my training for a travel week with only a hotel room and one pair of dumbbells.",
    expect: { screen: "none", length: "routine", routine: { exercises: 3 } },
    good: [
      "Here is a simple travel week:\n- Day 1: 20 min brisk walk, then push-ups 3 x 12 and bodyweight squats 3 x 15\n- Day 2: 15 min easy jog and 10 min of mobility\n- Day 3: dumbbell rows 3 x 10 each side and reverse lunges 3 x 10 each leg\n- Day 4: rest, with a 30 min walk\n- Day 5: repeat Day 1 and add a rep or two\nKeep your protein steady while you travel.",
    ],
    bad: [{
      reply:
        "Day 1: push-ups 3 x 12 and squats 3 x 15. Day 2: dumbbell rows 3 x 10 at 32.5 kg and reverse lunges 3 x 10 at 27.5 kg.",
      fails: "reply_guard",
    }],
  },
  {
    id: "named-study-is-cited",
    category: "library",
    description:
      "A shown study named in the text ('Kreider 2017') is cited for the reply; a study that was not shown is refused.",
    athlete: () => ({
      context: baseContext("rich"),
      contributors: { library: ["kreider_2017_creatine", "maughan_2018_ioc_supplements"] },
    }),
    question: "Is creatine worth taking?",
    expect: {
      screen: "none",
      cites: { anyOf: ["kreider_2017_creatine", "maughan_2018_ioc_supplements"] },
      mentions: [{ label: "names the source", anyOf: [/\bKreider\b/, /\bMaughan\b/] }],
    },
    good: [
      "Kreider 2017, the ISSN position stand, treats creatine monohydrate as one of the best studied supplements for strength and lean mass in healthy adults. It is general guidance, not advice for your own health. Check with a doctor first if you have kidney problems. Are you training for strength or for size?",
    ],
    goodCitations: [],
    bad: [{
      reply:
        "Schoenfeld 2017 found that creatine is the best studied supplement for strength. Are you training for strength or for size?",
      citations: [],
      fails: "reply_guard",
    }],
  },
  {
    id: "closing-question-not-repeated",
    category: "phrasing",
    description:
      "The previous reply ended with the protein-gap question: a new answer asks something new, or nothing.",
    athlete: () => athlete(withHistory(baseContext("rich"), proteinThread)),
    question: "How has my sleep been?",
    expect: { screen: "none" },
    good: [
      "Your sleep has been steady, and your recovery score sits in your usual range, so there is no reason to change anything this week. Do you want to look at how your last two sessions felt?",
    ],
    bad: [{
      reply:
        "Your sleep has been steady, and your recovery score sits in your usual range. Should I suggest two simple ways to close your protein gap?",
      fails: "reply_guard",
    }],
  },
];
