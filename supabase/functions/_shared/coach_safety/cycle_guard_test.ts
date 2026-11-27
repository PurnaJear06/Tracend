// The three reply rules of cycle support: fertility and contraception claims, a condition the
// athlete did not name, and advice to eat less while no period has come for a long time. Ordinary
// cycle talk must pass; each rule names its sentences for the repair and has a repair hint.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import type { CoachChatAnswerBreak } from "../contracts/coach_chat_v1.ts";
import { coachChatValidationRules } from "../contracts/coach_chat_v1.ts";
import { weightClaimCheckFor } from "../training/goal_phase/guard.ts";
import { numberGroundOf } from "./numbers_check.ts";
import { coachReplyCheck } from "./reply_guard.ts";
import { ownerContext } from "./fixtures.ts";
import { safeRangesOf } from "./safe_ranges.ts";
import {
  renderCoachContextParts,
  repairContractText,
  replyCheckInputsFor,
} from "../providers/coach_chat_provider.ts";
import { noCoachContributions } from "../coach_context/host.ts";

const context = ownerContext();
const file = renderCoachContextParts(context, 96_000).file;

function check(
  answer: string,
  options: { question?: string; words?: readonly string[]; longGap?: boolean } = {},
) {
  const question = options.question ?? "How does my cycle affect training?";
  return coachReplyCheck({
    ranges: { ...safeRangesOf(context), painEscalated: false },
    screening: "cleared",
    ground: numberGroundOf([file, question]),
    athleteText: [question],
    ...(options.words ? { athleteWords: [question, ...options.words] } : {}),
    cycleLongGap: options.longGap ?? false,
    weightClaim: weightClaimCheckFor(context, question),
  })(answer) as CoachChatAnswerBreak | null;
}

const rules = (answer: string, options?: Parameters<typeof check>[1]) =>
  check(answer, options)?.rules ?? [];

const ordinary = [
  "Your HRV usually dips in the second half of your cycle, so a lower reading this week is expected.",
  "Period cramps are common. Train as normal if you feel fine, and go easier on days you don't.",
  "After ovulation, progesterone rises and resting heart rate tends to run a little higher.",
  "After you ovulate, resting heart rate tends to rise a little until your period.",
  "You can use the rings for dips, or take your fish oil pills with a meal.",
  "A nicotine patch or an injection your doctor gives is a question for them.",
  "The research doesn't support changing your training by cycle phase; follow how you feel.",
  "Weight often runs higher around a period because of water, so compare with the same point last cycle.",
  "On the pill, the swings of a natural cycle mostly don't apply, so your recovery reads as usual.",
  "If your period is late and that's unusual for you, it's worth talking to a doctor.",
  "Keep calories at maintenance for now and keep lifting as planned.",
  "Pain that is severe or unusual for you is worth seeing a doctor about.",
];

Deno.test("ordinary cycle talk passes every rule, with and without a long gap", () => {
  for (const answer of ordinary) {
    assertEquals(check(answer), null, answer);
  }
  for (const answer of ordinary) {
    assertEquals(rules(answer, { longGap: true }), [], answer);
  }
});

Deno.test("fertility_or_contraception_claim: fertile days, ovulation, safe days, pregnancy odds and contraception advice fail", () => {
  for (
    const answer of [
      "Your fertile window is probably days 10 to 15.",
      "You're most fertile around now, so plan around it.",
      "You probably ovulated around day 14.",
      "You'll ovulate in about three days.",
      "Your ovulation day is likely next Tuesday.",
      "These are your safe days, so there is less to worry about.",
      "Natural family planning works well with a regular cycle like yours.",
      "Your chance of getting pregnant is low this week.",
      "You're probably not pregnant; a late period is common on a cut.",
      "It's unlikely you're pregnant with a cycle like this.",
      "You can't get pregnant during your period.",
      "You can skip the pill this week since you're not training.",
      "It's fine to come off your contraception while you cut.",
      "The pill is 99% effective, so no need to worry.",
      "Your IUD is still effective after hard training.",
      "The morning-after pill won't affect your training.",
    ]
  ) {
    const broken = check(answer);
    assert(broken?.rules?.includes("fertility_or_contraception_claim"), answer);
    assertEquals(broken?.sentences, [answer]);
  }
});

Deno.test("fertility_or_contraception_claim: a refusal governed by a prohibition passes", () => {
  for (
    const answer of [
      "I can't tell you your fertile window; Tracend doesn't predict that.",
      "Tracend doesn't estimate when you ovulate, and a doctor or pharmacist can help with that.",
      "I can't say whether you're pregnant; a test or your doctor can tell you.",
      "Don't change your contraception because of anything here; ask your doctor first.",
    ]
  ) {
    assertEquals(rules(answer), [], answer);
  }
});

Deno.test("cycle_condition_named: a condition fails unless the athlete named it first", () => {
  for (
    const answer of [
      "Irregular cycles like yours can be a sign of PCOS.",
      "This doesn't mean you have endometriosis.",
      "Strong mood changes before a period could be PMDD.",
      "It may be a hormonal imbalance; a doctor can check.",
      "At 44 this could be perimenopause.",
      "Missing periods while cutting is called RED-S.",
      "Heavy periods are sometimes caused by fibroids.",
    ]
  ) {
    const broken = check(answer);
    assert(broken?.rules?.includes("cycle_condition_named"), answer);
  }
  // She named it in her message, her onboarding limitations or a confirmed fact.
  assertEquals(
    rules("With PCOS, training works the same way; lifting is well supported.", {
      question: "I have PCOS. Does that change my training?",
    }),
    [],
  );
  assertEquals(
    rules("Polycystic ovary syndrome doesn't change how strength training works.", {
      question: "Anything I should know with my pcos?",
    }),
    [],
  );
  assertEquals(
    rules("With endometriosis, go by how you feel on bad days.", {
      words: ["Limitations: endometriosis, flares some months."],
    }),
    [],
  );
  // Naming one condition does not open another.
  assertEquals(
    rules("This could be endometriosis rather than PCOS.", {
      question: "I have PCOS, why are my periods so painful?",
    }),
    ["cycle_condition_named"],
  );
});

Deno.test("deficit_advice_with_long_gap: advice to eat less fails while the flag stands, maintenance passes", () => {
  for (
    const answer of [
      "Keep your deficit going, it's working.",
      "Cut 300 kcal a day to speed up fat loss.",
      "Drop your calories a little more this week.",
      "Aim to lose about 0.5 kg a week.",
      "Eat less on rest days.",
      "Stay below maintenance until you reach your goal.",
      "Reduce your carbs at dinner.",
    ]
  ) {
    assert(rules(answer, { longGap: true }).includes("deficit_advice_with_long_gap"), answer);
    assert(!rules(answer).includes("deficit_advice_with_long_gap"), answer);
  }
  for (
    const answer of [
      "Keep calories at maintenance for now.",
      "Eat at maintenance rather than in a deficit while your period is missing.",
      "I'd pause the deficit and talk to a doctor if this isn't expected for you.",
      "Don't cut calories right now; maintenance or a little above is the safer choice.",
      "You've been in a deficit since September, and no period for 3 months is worth checking with a doctor.",
      "Hold off on a deficit until you've spoken to a doctor.",
      "No weight loss for now: keep your lifting and protein steady.",
    ]
  ) {
    assertEquals(rules(answer, { longGap: true }), [], answer);
  }
});

Deno.test("the long-gap flag comes from the cycle block only, and the athlete's words come from her own text", () => {
  const block = (text: string) => ({ ...noCoachContributions, texts: { cycle: text } });
  const ctx = { coaching_date: "2026-11-27", permitted_evidence: [] };
  assertEquals(
    replyCheckInputsFor(ctx, "q", block("Long gap without a period: yes")).cycleLongGap,
    true,
  );
  assertEquals(
    replyCheckInputsFor(ctx, "q", block("Long gap without a period: no")).cycleLongGap,
    false,
  );
  assertEquals(
    replyCheckInputsFor(ctx, "Long gap without a period: yes", null).cycleLongGap,
    false,
  );
  const words = replyCheckInputsFor(
    { ...ctx, profile_context: { limitations: "Endometriosis" } },
    "q",
    { ...noCoachContributions, texts: { confirmed_facts: "PCOS (confirmed)" } },
  ).athleteWords!;
  assert(words.includes("Endometriosis"));
  assert(words.includes("PCOS (confirmed)"));
});

Deno.test("each cycle rule is a validation rule with its own repair hint", () => {
  for (
    const [rule, words] of [
      ["fertility_or_contraception_claim", "no fertility or contraception claims"],
      ["cycle_condition_named", "has not named herself"],
      ["deficit_advice_with_long_gap", "maintenance or above"],
    ] as const
  ) {
    assert(coachChatValidationRules.includes(rule));
    assert(rule.length <= 64 && /^[a-z_]+$/.test(rule), rule);
    assertStringIncludes(repairContractText({ rule, path: "$.answer" }, []), words);
  }
});
