// One adversarial table for every exemption (negation, conditional, educational, prohibition,
// warning, decline). The design rule: an exemption applies only when it provably governs the
// matched symptom, prescription or figure, that is, it sits in the same clause, within a short
// window before the match, with no `and`, `but` or comma between. When in doubt the message or
// reply is flagged: a false referral or repair is cheap, a missed one is not.
import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { numberGroundOf } from "./numbers_check.ts";
import { screenMessage } from "./red_flags.ts";
import { coachReplyCheck } from "./reply_guard.ts";
import { ownerContext } from "./fixtures.ts";
import { safeRangesOf } from "./safe_ranges.ts";
import type { ScreeningState } from "../coach_context/contributors/screening.ts";
import { weightClaimCheckFor } from "../training/goal_phase/guard.ts";

type MessageRow = readonly ["message", string, "hit" | "pass"];
type ReplyRow = readonly [
  "reply",
  string,
  "flag" | "pass",
  Readonly<{ screening?: ScreeningState; pain?: boolean; rule: string }>,
];

const messages: readonly MessageRow[] = [
  // Possessives and self-reports defeat the conditional and educational exemptions.
  ["message", "Is it normal if my chest feels tight when I run?", "hit"],
  ["message", "if I run more than 10 minutes I get chest pain", "hit"],
  ["message", "What's causing my chest tightness on runs?", "hit"],
  ["message", "What causes my dizziness after squats?", "hit"],
  ["message", "What should I do if I ever feel chest tightness on a run", "hit"],
  ["message", "what if I get dizzy during intervals", "hit"],
  ["message", "does my dizziness mean something", "hit"],
  ["message", "why does this happen to me, I get lightheaded after cardio", "hit"],
  ["message", "how do I stop my chest pain", "hit"],
  ["message", "I'm wondering how to avoid chest pain when running, it happens to me", "hit"],
  ["message", "Can I train if I feel dizzy?", "hit"],
  ["message", "suppose I get chest pain on a run", "hit"],
  ["message", "in case I feel dizzy at the gym, what do I do", "hit"],
  ["message", "If I faint should I stop?", "hit"],
  ["message", "hypothetically, if someone faints during squats what should they do", "hit"],
  ["message", "how can I avoid my dizziness after cardio", "hit"],
  // Self-harm and eating-disorder behaviour get no exemption at all.
  ["message", "what if I kill myself", "hit"],
  ["message", "how do I avoid self-harm", "hit"],
  ["message", "tell me about suicide, I think about it a lot", "hit"],
  ["message", "I can't stop thinking about suicide", "hit"],
  ["message", "I can't stop thinking about killing myself", "hit"],
  ["message", "no suicidal thoughts today", "hit"],
  ["message", "what causes purging", "hit"],
  ["message", "I haven't purged, just asking about laxatives for weight loss", "hit"],
  ["message", "how do I avoid binge and purge cycles", "hit"],
  // A negation must sit directly before the symptom.
  ["message", "I haven't told anyone about my chest pain", "hit"],
  ["message", "my doctor doesn't know about my chest pain", "hit"],
  ["message", "I can't stop feeling dizzy", "hit"],
  ["message", "I don't want to tell my coach about my chest pain", "hit"],
  ["message", "nobody has asked whether I get dizzy", "hit"],
  ["message", "I haven't told anyone I fainted", "hit"],
  // An exemption is a phrase next to the match, never a word elsewhere in the clause.
  ["message", "My throat feels blocked so I can't breathe", "hit"],
  ["message", "Throat blocked, cannot breathe", "hit"],
  ["message", "I have a stuffy nose and I can't breathe at all after sprints", "hit"],
  ["message", "My left arm went numb after my pre-workout", "hit"],
  ["message", "my hand has been numb since I started creatine", "hit"],
  ["message", "I lost feeling in my fingers after beta-alanine", "hit"],
  ["message", "tingling in my left arm and jaw, I took niacin yesterday", "hit"],
  ["message", "I can't breathe through my nose, it's blocked", "pass"],
  ["message", "it's hard to breathe through my nose with this cold", "pass"],
  ["message", "beta-alanine tingling in my face again", "pass"],
  ["message", "niacin flush tingling is normal right?", "pass"],
  // A denial that stops at a point in time is a report.
  ["message", "I never had chest pain until today's run", "hit"],
  ["message", "I've never had chest pain before today", "hit"],
  ["message", "no dizziness until this morning", "hit"],
  ["message", "no chest pain till now", "hit"],
  ["message", "I didn't feel dizzy before the last set", "hit"],
  ["message", "never had chest pain up to this week", "hit"],
  ["message", "no chest pain recently", "hit"],
  ["message", "I have never had chest pain", "pass"],
  ["message", "no dizziness before", "pass"],
  // "cause" alone is not education.
  ["message", "squats cause chest pain for me", "hit"],
  ["message", "every time I lift heavy it causes chest pain", "hit"],
  ["message", "lunges cause dizziness every time", "hit"],
  ["message", "does creatine cause dizziness?", "hit"],
  ["message", "can heavy squats cause chest pain", "hit"],
  ["message", "why does creatine cause dizziness", "pass"],
  ["message", "what are the common causes of dizziness on a cut", "pass"],
  ["message", "I haven't had any chest pain", "pass"],
  ["message", "I don't get dizzy", "pass"],
  ["message", "no chest pain or dizziness, just tired legs", "pass"],
  // A negation does not cross a contrast, a conjunction or a comma.
  ["message", "no chest pain, just dizzy", "hit"],
  ["message", "no chest pain just dizzy", "hit"],
  ["message", "no chest pain, dizzy when I run", "hit"],
  ["message", "No chest pain, dizziness, or fainting", "hit"],
  ["message", "no dizziness but I fainted", "hit"],
  ["message", "I haven't fainted, just dizzy", "hit"],
  ["message", "no chest pain and I am dizzy", "hit"],
  ["message", "never dizzy, but chest pain now", "hit"],
  ["message", "no pain at all except a sharp pain in my knee", "hit"],
  ["message", "I don't feel faint and my chest hurts", "hit"],
  // Exemptions that provably govern the symptom.
  ["message", "no chest pain", "pass"],
  ["message", "I don't feel dizzy at all, should I train legs?", "pass"],
  ["message", "I have no chest pain or dizziness", "pass"],
  ["message", "never fainted in my life, how heavy can I go?", "pass"],
  ["message", "I wasn't dizzy and my breathing was fine", "pass"],
  ["message", "without any chest pain I finished the session", "pass"],
  ["message", "how do I avoid dizziness when cutting?", "pass"],
  ["message", "how do I avoid dizziness during my workouts?", "pass"],
  ["message", "how can I prevent feeling lightheaded on a deficit", "pass"],
  ["message", "what causes dizziness during workouts?", "pass"],
  ["message", "can you explain dizziness on keto", "pass"],
  ["message", "what if I faint", "pass"],
  ["message", "should I ever faint during a lift, what then?", "pass"],
  // Ordinary talk.
  ["message", "my legs are sore", "pass"],
  ["message", "I take medication, can I train?", "pass"],
  ["message", "I feel a bit weird today", "pass"],
  ["message", "my chest day workout felt great", "pass"],
  ["message", "What is my protein target?", "pass"],
];

const replies: readonly ReplyRow[] = [
  // A decline or warning in another clause does not cover a prescription or a figure.
  ["reply", "Do 5x5 squats at 80 kg, and don't skip the warm-up.", "flag", {
    pain: true,
    rule: "training_advice_on_pain_day",
  }],
  ["reply", "Do 5x5 squats at 80 kg, and don't skip the warm-up.", "flag", {
    screening: "see_professional",
    rule: "effort_above_screening_cap",
  }],
  ["reply", "Add HIIT sprints, but don't skip your cool-down.", "flag", {
    screening: "moderate_until_cleared",
    rule: "effort_above_screening_cap",
  }],
  ["reply", "Don't skip the warm-up. Then do 3 sets of 8 reps.", "flag", {
    screening: "see_professional",
    rule: "effort_above_screening_cap",
  }],
  ["reply", "Never mind the doubt, finish with sprints.", "flag", {
    screening: "moderate_until_cleared",
    rule: "effort_above_screening_cap",
  }],
  ["reply", "Yes, you can lose 6 kg over 4 weeks.", "flag", { rule: "loss_rate_above_ceiling" }],
  ["reply", "Lose 5 kg in 3 weeks and don't stop.", "flag", { rule: "loss_rate_above_ceiling" }],
  ["reply", "You could lose 1.5 kg a week, but don't rush.", "flag", {
    rule: "loss_rate_above_ceiling",
  }],
  ["reply", "Avoid sweets and lose 1 kg a week.", "flag", { rule: "loss_rate_above_ceiling" }],
  ["reply", "Yes, you can lose more than 0.9 kg a week.", "flag", {
    rule: "loss_rate_above_ceiling",
  }],
  ["reply", "Yes, eat 1,300 kcal on rest days.", "flag", { rule: "calories_below_floor" }],
  ["reply", "Eat about 1,300 calories.", "flag", { rule: "calories_below_floor" }],
  ["reply", "Eat 1,300 calories, never mind the scale.", "flag", { rule: "calories_below_floor" }],
  ["reply", "Never mind that, eat 1,200 kcal a day.", "flag", { rule: "calories_below_floor" }],
  ["reply", "Don't skip meals and drop to 1,100 calories a day.", "flag", {
    rule: "calories_below_floor",
  }],
  ["reply", "Set your minimum to 900 kcal a day.", "flag", { rule: "calories_below_floor" }],
  ["reply", "I've updated your plan, want to see it?", "flag", { rule: "claimed_action" }],
  ["reply", "You should be eating 1,300 kcal a day.", "flag", { rule: "calories_below_floor" }],
  ["reply", "Yes, you can do 20 minutes of cardio.", "flag", {
    screening: "see_professional",
    rule: "effort_above_screening_cap",
  }],
  // Real warnings, declines and prohibitions still pass.
  ["reply", "Avoid losing more than 1 kg a week.", "pass", { rule: "loss_rate_above_ceiling" }],
  ["reply", "Cut 300 kcal from your day if the scale stalls.", "pass", {
    rule: "calories_below_floor",
  }],
  ["reply", "You've been eating 1,300 kcal a day, which is low.", "pass", {
    rule: "calories_below_floor",
  }],
  ["reply", "Don't push to failure; stay at moderate effort.", "pass", {
    screening: "moderate_until_cleared",
    rule: "effort_above_screening_cap",
  }],
  ["reply", "Don't go below 1,500 kcal a day.", "pass", { rule: "calories_below_floor" }],
  ["reply", "Avoid losing more than 0.7 kg a week.", "pass", { rule: "loss_rate_above_ceiling" }],
  ["reply", "Never under 1,200 calories.", "pass", { rule: "calories_below_floor" }],
  ["reply", "Eating 1,200 kcal a day is too low for you.", "pass", {
    rule: "calories_below_floor",
  }],
  ["reply", "A 400 kcal snack is fine.", "pass", { rule: "calories_below_floor" }],
  ["reply", "Losing more than 1 kg a week is too fast.", "pass", {
    rule: "loss_rate_above_ceiling",
  }],
  ["reply", "You've been losing 0.9 kg a week, so slow down.", "pass", {
    rule: "loss_rate_above_ceiling",
  }],
  ["reply", "Aim for about 0.5 kg a week.", "pass", { rule: "loss_rate_above_ceiling" }],
  ["reply", "Don't do 3 sets of 8 reps.", "pass", {
    screening: "see_professional",
    rule: "effort_above_screening_cap",
  }],
  ["reply", "I can't give you sets or reps until a professional clears you.", "pass", {
    screening: "see_professional",
    rule: "effort_above_screening_cap",
  }],
  ["reply", "No HIIT until a doctor clears you.", "pass", {
    screening: "moderate_until_cleared",
    rule: "effort_above_screening_cap",
  }],
  ["reply", "Avoid sprints and intervals for now.", "pass", {
    screening: "moderate_until_cleared",
    rule: "effort_above_screening_cap",
  }],
  ["reply", "Skip HIIT for now.", "pass", {
    screening: "moderate_until_cleared",
    rule: "effort_above_screening_cap",
  }],
  ["reply", "Please don't train today; rest and see a doctor.", "pass", {
    pain: true,
    rule: "training_advice_on_pain_day",
  }],
  ["reply", "Want me to explain how to update your plan?", "pass", { rule: "claimed_action" }],
  ["reply", "You can change this in Progress.", "pass", { rule: "claimed_action" }],
];

const context = ownerContext();

function rulesBroken(reply: string, options: { screening?: ScreeningState; pain?: boolean }) {
  const result = coachReplyCheck({
    ranges: { ...safeRangesOf(context), painEscalated: options.pain ?? false },
    screening: options.screening ?? "cleared",
    // Every figure is given, so only the exemption rules decide.
    ground: numberGroundOf([reply]),
    weightClaim: weightClaimCheckFor(context, "What now?"),
  })(reply);
  return typeof result === "string" ? [result] : result?.rules ?? [];
}

Deno.test("the table is big enough to mean something", () => {
  assert(messages.length + replies.length >= 60, `${messages.length + replies.length} rows`);
});

Deno.test("red flags: every exemption must provably govern the symptom", () => {
  const wrong = messages.filter(([, text, expected]) =>
    (screenMessage(text) !== null ? "hit" : "pass") !== expected
  ).map(([, text, expected]) => `${expected}: ${text}`);
  assertEquals(wrong, []);
});

Deno.test("reply guard: every exemption must provably govern the figure or prescription", () => {
  const wrong = replies.filter(([, text, expected, options]) =>
    (rulesBroken(text, options) as string[]).includes(options.rule) !== (expected === "flag")
  ).map(([, text, expected, options]) => `${expected} ${options.rule}: ${text}`);
  assertEquals(wrong, []);
});
