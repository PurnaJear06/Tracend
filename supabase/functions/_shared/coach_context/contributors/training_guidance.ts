// Contract 7 contributor: the training guidance Tracend's rules give for today, read-only. It reads
// get_training_guidance_for_v1 (service role) and tells Coach whether a lighter week (a deload) is
// running, waiting for the athlete's answer, suggested or not due and why, and how the week's
// cardio stands against the guideline dose and what intensity is open today. Coach explains these
// facts; it never starts a lighter week, never answers a proposal for the athlete and never applies
// anything. The next-session load targets are in the training plan block, not repeated here.
//
// The figures are the rules' own and the athlete's Apple Health minutes, each marked as a record
// (`../../recorded_text.ts`) so a reply may repeat them; nothing else in the text states a number.
// A reason for a suggestion is told in words, not counted. Heart rate never decides anything here:
// the easy-cardio line names the share of heart-rate reserve and the talk test only as wording.
//
// On a day with a safety route, or under a health check that asks for a professional first, the
// guidance gives no training line at all (the same rule as the readiness card): the block says so
// and points to the referral. The read has its own deadline, shorter than the host's. A guidance
// that could not be read renders a short "could not be read" block instead of nothing, so the model
// never reads silence as "no lighter week is due" or "the cardio is done". It is the only thing a
// slow or failed read costs: the turn goes on.
import { blockOf, type CoachContextContributor, type RenderedBlock } from "../host.ts";
import { record } from "../../recorded_text.ts";
import { type ReadStatus, readWithin } from "../read_within.ts";
import { coachServiceRpc, type ServiceRpc } from "../service_source.ts";
import {
  type DeloadGuidance,
  type DeloadReason,
  type DeloadSuppression,
  parseTrainingGuidance,
  type TrainingGuidance,
} from "../../training/guidance/payload.ts";
import { deloadRpeCap } from "../../training/standard/deload.ts";

export const trainingGuidanceContributorId = "training_guidance";
export const trainingGuidanceBudgetChars = 2_000;
export const trainingGuidanceRpc = "get_training_guidance_for_v1";

/** How long the turn waits for the guidance before it goes on without it. */
export const trainingGuidanceDeadlineMs = 1_500;

/** The athlete's guidance for a coaching date; null when it cannot be read as exactly that shape. */
export type TrainingGuidanceSource = (
  userId: string,
  localDate: string,
) => Promise<TrainingGuidance | null>;

/** Reads the guidance through `rpc`; null when the read fails or the payload is not the guidance. */
export function trainingGuidanceSourceFromRpc(rpc: ServiceRpc): TrainingGuidanceSource {
  return async (userId, localDate) => {
    const { data, error } = await rpc(trainingGuidanceRpc, {
      p_user_id: userId,
      p_local_date: localDate,
    });
    if (error) return null;
    const guidance = parseTrainingGuidance(data);
    // A day other than the one asked for is not today's guidance.
    return guidance !== null && guidance.localDate === localDate ? guidance : null;
  };
}

/** The guidance over the service-role caller every context contributor shares. */
export const trainingGuidanceFromService: TrainingGuidanceSource = trainingGuidanceSourceFromRpc(
  coachServiceRpc,
);

const reasonWords: Readonly<Record<DeloadReason, string>> = Object.freeze({
  performance_drop: "several lifts are heading down in the athlete's own logged sets",
  run_down: "most of the athlete's recent check-ins read amber or red",
  block_done: "the training block has run its length and was trained as planned",
});

const notDueWords: Readonly<Record<DeloadSuppression, string>> = Object.freeze({
  screening: "the health check asks for a professional's view first",
  block_running: "another change to the plan is running",
  recent_deload: "a lighter week ended recently",
  declined_recently: "the athlete said no to one, or let its card lapse, recently",
  not_enough_training:
    "there has been too little training lately for there to be anything to recover from",
  no_plan: "there is no plan to ease",
  safety_route: "a safety route applies today",
});

const fixedRules =
  "Rules: this is what Tracend's rules say today; never contradict it. The athlete decides, you explain: never start, accept, decline or change a lighter week or a plan yourself, and never say you did. A lighter week is a widely used coaching practice, not a proven requirement. Heart rate may colour the wording about easy effort and never decides a load or an intensity.";

function deloadLines(deload: DeloadGuidance): string[] {
  const origin = deload.proposalOrigin === "tracend"
    ? "Tracend's rules suggested it."
    : deload.proposalOrigin === "coach"
    ? "It came from a Coach proposal."
    : null;
  if (deload.status === "running") {
    return [
      `Lighter week (deload): running${
        deload.endsOn === null ? "" : ` until ${record(deload.endsOn)}`
      }. The athlete approved it. It keeps the same exercises with half the sets, loads held and effort ${
        record(deloadRpeCap.value)
      } or lower, and the regular plan returns by itself; the athlete can undo it on Train.${
        origin === null ? "" : ` ${origin}`
      }`,
    ];
  }
  if (deload.status === "pending") {
    return [
      `Lighter week (deload): a proposal is waiting for the athlete's answer. ${
        origin === null ? "" : `${origin} `
      }Do not answer it for them: they approve or decline it on its card.`,
    ];
  }
  if (deload.status === "suggested") {
    return [
      `Lighter week (deload): Tracend's rules suggest one could help, because ${
        deload.reasons.map((reason) => reasonWords[reason]).join("; and ")
      }. It is only a suggestion: the athlete sees it on Train and decides there. You never start one.`,
    ];
  }
  const ended = deload.lastEndedOn === null
    ? ""
    : ` The last lighter week ended on ${record(deload.lastEndedOn)}.`;
  return [
    deload.suppressedBy === null
      ? `Lighter week (deload): none is due; nothing in the athlete's logs points to one.${ended}`
      : `Lighter week (deload): none is offered, because ${
        notDueWords[deload.suppressedBy]
      }.${ended} The athlete can still ask Coach for one; it would be a proposal they approve.`,
  ];
}

function cardioLines(guidance: TrainingGuidance): string[] {
  const week = guidance.cardioWeek;
  if (week === null) return [];
  const lines: string[] = [];
  const window = `${record(week.windowFrom)} to ${record(week.windowTo)}`;
  if (week.doneMin === null) {
    lines.push(
      `Cardio this week (${window}): not countable yet, because too few of those days have Apple Health data. The guideline dose is ${
        record(week.targetMin)
      } minutes of moderate cardio a week. Do not state minutes done; if asked, say Apple Health needs to be connected and synced.`,
    );
  } else {
    const upper = week.stretchMax === null
      ? ""
      : ` (up to ${record(week.stretchMax)} minutes for the athlete's goal)`;
    lines.push(
      `Cardio this week (${window}): ${record(week.doneMin)} minutes done of ${
        record(week.targetMin)
      } minutes of moderate cardio${upper}, counted from Apple Health workouts${
        week.intensityKnown
          ? ""
          : "; every counted minute is read as moderate, because a workout has no intensity"
      }.${
        week.doneMin === 0
          ? " Zero minutes can also mean the athlete does not share workouts with Tracend: do not conclude they did no cardio."
          : ""
      }`,
    );
  }
  lines.push(
    week.vigorousAllowed
      ? `Hard cardio is open today, up to ${
        record(week.vigorousSessionsMax)
      } sessions a week, and a hard minute counts as ${
        record(week.vigorousCountsAs)
      } moderate minutes. Keep it at least ${
        record(week.liftSeparationHours)
      } hours from lifting when explosive strength matters.`
      : `Today is an easy-cardio day: hard cardio is not open (the health check, today's readiness or a sore joint decides). Easy means below ${
        record(week.easyHrReserveMax)
      }% of heart-rate reserve, or able to keep a conversation going.`,
  );
  return lines;
}

/** Why a day gives no training guidance at all: a safety route first, then the health check. */
function withheldBy(guidance: TrainingGuidance): "safety_route" | "screening" | null {
  if (guidance.safetyRoute !== null) return "safety_route";
  return guidance.cardioWithheld;
}

function guidanceLines(guidance: TrainingGuidance): string[] {
  const withheld = withheldBy(guidance);
  const head = `Training guidance for ${
    record(guidance.localDate)
  }, as Tracend's rules work it out.`;
  if (withheld === "safety_route") {
    return [
      head,
      "A safety route applies today, so training is not the topic: give no lighter-week, cardio or training advice, and never say it is fine to train. Point to the referral the app shows on Today; never diagnose or name a cause.",
    ];
  }
  if (withheld === "screening") {
    return [
      head,
      "The health check asks the athlete to see a professional first, so give no lighter-week, cardio or training advice. Point to the professional guidance the app shows; never diagnose or name a cause.",
    ];
  }
  return [head, ...deloadLines(guidance.deload), ...cardioLines(guidance), fixedRules];
}

/** The block's text for a guidance, its dates and figures marked as records. */
export function trainingGuidanceMarked(guidance: TrainingGuidance): string {
  return guidanceLines(guidance).join("\n");
}

/** The block's text when the guidance could not be read: a gap is never read as "nothing due". */
export function trainingGuidanceUnknownText(): string {
  return [
    "Today's training guidance (a lighter week, the week's cardio) could not be read just now, so whether a lighter week is due, waiting or running, and how much cardio is done, are unknown.",
    "Do not say a lighter week is due, is not due or has started, and do not state cardio minutes or say the cardio target is met. If the athlete asks, say it could not be read this time and that Train shows it. Never start a lighter week or change a plan yourself.",
  ].join("\n");
}

export function createTrainingGuidanceContributor(
  source: TrainingGuidanceSource,
  deadlineMs: number = trainingGuidanceDeadlineMs,
): CoachContextContributor {
  return Object.freeze({
    id: trainingGuidanceContributorId,
    slot: "volatile",
    budgetChars: trainingGuidanceBudgetChars,
    async render(input): Promise<RenderedBlock> {
      const { value: guidance, status } = await readWithin(
        () => source(input.userId, input.localDate),
        deadlineMs,
      );
      const trace: { training_guidance: ReadStatus } = { training_guidance: status };
      return guidance === null
        ? blockOf(trainingGuidanceUnknownText(), { trace })
        : blockOf(trainingGuidanceMarked(guidance), { trace });
    },
  });
}

export const trainingGuidanceContributor: CoachContextContributor =
  createTrainingGuidanceContributor(trainingGuidanceFromService);
