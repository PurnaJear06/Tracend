// The fixed answers to a red-flag hit (red_flags.ts). They are written once, in plain words, and
// kept out of every model prompt (AI_SAFETY_SPEC §7: localized emergency wording is maintained
// outside model prompts). An urgent answer names the emergency number; a pain answer sends the
// athlete to a doctor or physiotherapist before they train that area. None of them diagnoses,
// reassures that a symptom is harmless, or gives training or nutrition advice.
import type { CoachChatAnswerV1 } from "../contracts/coach_chat_v1.ts";
import type { RedFlagCategory, RedFlagHit } from "./red_flags.ts";

/** The model id stored with a referral; the app labels it "Tracend safety answer · not AI". */
export const safetyReferralModel = "deterministic-safety-v1";

const emergency = "call your local emergency number";

const answers: Readonly<Record<Exclude<RedFlagCategory, "check_in_pain" | "scope">, string>> = {
  chest:
    `Please stop training now. Chest pain, pressure or tightness, or a heartbeat that races, flutters or skips, can be a sign of a heart problem, and I can't tell what it is. If it is happening now, if it spreads to your arm, jaw or back, or if you feel sweaty, sick, faint or short of breath, ${emergency} straight away. If it has passed, please still see a doctor before you train again. I'll leave plans and numbers aside until you have, and I'm glad to pick things up from there.`,
  collapse:
    `Fainting or nearly fainting is a reason to stop training and be checked before you start again. If you hit your head, still feel unwell, or it came with chest pain or a racing heart, ${emergency} now. Otherwise please sit or lie down, have someone with you if you can, and see a doctor before you train. I won't give training or nutrition advice until you have.`,
  breathing:
    `Trouble breathing is not something to push through. Please stop what you're doing. If it is severe or sudden, or comes with chest pain, dizziness or blue lips, ${emergency} now. If it has eased, please see a doctor before you train again. I'll hold off on training advice until then.`,
  stroke:
    `These can be signs of a stroke or another emergency. Please ${emergency} now. Don't wait to see if it passes and don't drive yourself, and note the time it started. I can't help with this, but I hope you get seen quickly.`,
  bleeding:
    `Coughing up or vomiting blood, or blood in your stool, needs urgent medical care. Please ${emergency} or go to urgent care now. Training and nutrition advice can wait.`,
  eating:
    `Thank you for telling me. What you describe (purging, laxatives, or going days without eating) can harm your body, and it isn't something a training app can safely coach around. Please talk soon to your doctor, an eating-disorder specialist or someone you trust: people do recover with support. If you ever feel faint, have chest pain or feel unsafe, ${emergency}. I'll hold off on calorie and weight advice until you've had that support.`,
  dark_urine:
    `Dark brown, red or cola-coloured urine after hard training can be a sign of serious muscle breakdown, and blood in your urine needs a doctor too. Please get medical care today and don't train until you've been seen. If you also have severe muscle pain, weakness or very little urine, ${emergency}.`,
  dizziness:
    `Dizziness or light-headedness during or after training is a reason to stop, then sit or lie down. If it comes with chest pain, fainting, a racing heart, trouble breathing or confusion, ${emergency}. If it happens again or doesn't pass, please see a doctor before you train again. I won't plan training around it until you have.`,
  injury_pain:
    `A sharp, severe or sudden pain, or a pop or tear during a lift, is a reason to stop and not train through it. Please see a doctor or physio before you train that area again, and get seen today if you can't move it, can't put weight on it, or it is swelling quickly. Tracend can't diagnose or rehab an injury, so I'll leave sets and loads for that area until you're cleared.`,
  numbness:
    `Numbness or tingling that comes with training is worth having looked at. Please stop the lifts that bring it on and see a doctor or physio before you train that area again. If it is on one side of your body or face, or comes with weakness or trouble speaking, ${emergency} now.`,
  self_harm:
    `I'm really sorry you're feeling this way, and I'm glad you said it. You deserve support from a real person right now. If you might act on these thoughts or you are in danger, ${emergency} now. You can also reach a crisis line: in the US call or text 988, in the UK or Ireland call Samaritans on 116 123, in India call Tele-MANAS on 14416, and findahelpline.com lists lines in other countries. If you can, tell someone near you how you feel. I'm a training coach and not the right help for this, but I'm here whenever you want to talk about training again.`,
};

const checkInPain =
  "Your check-in today logged pain of 7 or more, which is too high to train through, so I won't plan or adjust a session today. Please rest the area and see a doctor or physio before you train it again, and get seen today if the pain is sharp, getting worse, or you can't move it. I'm still happy to help with food, sleep and recovery questions.";

const scope =
  "Tracend cannot provide diagnosis, treatment, rehabilitation, medication, pregnancy, or eating-disorder guidance. Use a qualified clinician for this request.";

const scopeFollowUps = [
  "Ask about the approved training plan",
  "Review current fitness evidence",
] as const;

/** The reply to a hit: `refused` for self-harm and unsupported requests, `limited` for the rest. */
export function referralFor(hit: RedFlagHit): CoachChatAnswerV1 {
  if (hit.category === "scope") {
    return {
      answer: scope,
      evidence: [],
      missing_data: [],
      safety_state: "refused",
      suggested_follow_ups: [...scopeFollowUps],
    };
  }
  return {
    answer: hit.category === "check_in_pain" ? checkInPain : answers[hit.category],
    evidence: [],
    missing_data: [],
    safety_state: hit.category === "self_harm" ? "refused" : "limited",
    suggested_follow_ups: [],
  };
}
