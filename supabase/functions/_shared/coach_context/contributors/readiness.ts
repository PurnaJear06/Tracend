// Contract 7 contributor: today's readiness card as the athlete sees it, read-only. It reads
// get_readiness_context_v1 (service role) and tells Coach the band, the adjustment the card
// offers and whether the athlete answered it, whether a safety route is on the card and how
// strict it is, and which joint areas are held, limited or watched. Coach explains the card; it
// never contradicts it, never answers it for the athlete and never applies a change.
//
// What reaches the model is what the reader already exposes and nothing it holds back: no
// red-flag code, no pain severity, no trigger list, no answer text. The text is fixed wording
// plus the date of the card; it states no figure.
//
// The read has its own short deadline. The trace reports ok, unavailable, failed or timeout, as
// the training plan does for the load signals. A card that could not be read renders a short
// "could not be read" block instead of nothing, so the model never reads silence as "nothing to
// worry about".
//
// The deload signal and the cardio week are their own contributor (`training_guidance.ts`), read in
// parallel with this one under its own deadline, so a slow guidance read costs only its own block.
import { blockOf, type CoachContextContributor, type RenderedBlock } from "../host.ts";
import { record } from "../../recorded_text.ts";
import { readWithin } from "../read_within.ts";
import { coachServiceRpc, type ServiceRpc } from "../service_source.ts";
import {
  type ContextJointArea,
  type ContextJointState,
  parseReadinessContext,
  type ReadinessContext,
  readinessContextRpc,
} from "../../training/readiness/context_payload.ts";
import type { AdjustmentKind, SafetyRoute } from "../../training/readiness/payload.ts";

export const readinessContributorId = "readiness";
export const readinessBudgetChars = 2_400;

/** How long the turn waits for the card before it goes on without it. */
export const readinessDeadlineMs = 1_500;

/** The athlete's card for a coaching date; null when it cannot be read as exactly that shape. */
export type ReadinessSource = (
  userId: string,
  localDate: string,
) => Promise<ReadinessContext | null>;

/** Reads the card through `rpc`; null when the read fails or the payload is not the card. */
export function readinessSourceFromRpc(rpc: ServiceRpc): ReadinessSource {
  return async (userId, localDate) => {
    const { data, error } = await rpc(readinessContextRpc, {
      p_user_id: userId,
      p_local_date: localDate,
    });
    return error ? null : parseReadinessContext(data, localDate);
  };
}

/** The card over the service-role caller every context contributor shares. */
export const readinessFromService: ReadinessSource = readinessSourceFromRpc(coachServiceRpc);

const kindWords: Readonly<Record<AdjustmentKind | "none", string>> = Object.freeze({
  none: "no change to today's session",
  hold_load: "hold the loads (no step up today)",
  reduce_sets: "fewer sets today",
  swap_to_easy_cardio: "swap today's lifting for easy cardio",
  joint_adjust: "swap or shorten the exercises that load a sore joint",
});

const bandWords: Readonly<Record<ReadinessContext["band"], string>> = Object.freeze({
  green: "green (no sign of a poor day)",
  amber: "amber (a lighter day may be sensible)",
  red: "red (a poor day)",
  unknown: "no reading yet",
});

const closedWords: Readonly<Record<NonNullable<ReadinessContext["unavailableReason"]>, string>> =
  Object.freeze({
    no_plan: "there is no plan to adjust",
    rest_day: "today is a rest day",
    session_started: "the session has already started",
    session_done: "today's session is done",
    coach_adjusted: "a change Coach proposed already shapes today's session",
  });

const areaWords: Readonly<Record<ContextJointArea, string>> = Object.freeze({
  knee: "knee",
  back: "lower back",
  shoulder: "shoulder",
  other: "an area reported elsewhere",
});

const routeRules: Readonly<Record<SafetyRoute, string>> = Object.freeze({
  pain_referral: "The athlete reported pain that needs a professional's look.",
  urgent: "This is urgent: tell the athlete to get medical care now, not later.",
  clinician_today: "Tell the athlete to be seen by a doctor or physio today.",
  clinician: "Tell the athlete to have it checked by a doctor or physio.",
});

const fixedRules =
  "Rules: never contradict the card. The athlete decides on the card; you explain it and never apply, accept, decline or change it, and never say you did. When the athlete asks what to do today, start from the card. A lighter week (a deload) is only ever a proposal the athlete approves: never say one has started.";

const joinAreas = (areas: readonly ContextJointArea[]) =>
  areas.map((area) => areaWords[area]).join(", ");

/** The lines of the card's block, with its date marked as a record. */
function readinessLines(card: ReadinessContext): string[] {
  const lines = [
    `Today's readiness card (${record(card.localDate)}), as Tracend worked it out.`,
    `Readiness: ${bandWords[card.band]}${
      card.confidence === null ? "" : `; Tracend's confidence in the reading: ${card.confidence}`
    }.`,
  ];
  if (card.safetyRoute !== null) {
    lines.push(
      `Safety route: ${card.safetyRoute}. The card shows a referral and no training change.`,
    );
  } else if (card.athleteUnavailable === true) {
    lines.push(
      "Rest day: the athlete said they cannot train today. Do not offer today's session.",
    );
  } else if (card.status === "none") {
    lines.push("Adjustment: none; the card changes nothing in today's session.");
  } else if (card.status === "proposed") {
    lines.push(
      `Adjustment offered: ${
        kindWords[card.kind]
      }. The athlete has not answered yet; do not answer it for them.`,
    );
  } else if (card.status === "accepted") {
    lines.push(`Adjustment accepted by the athlete: ${kindWords[card.kind]}.`);
  } else {
    lines.push(
      `Adjustment offered: ${
        kindWords[card.kind]
      }. The athlete declined it, so today's session stays as planned.`,
    );
  }
  if (card.unavailableReason !== null) {
    lines.push(`The card is closed: ${closedWords[card.unavailableReason]}.`);
  }
  lines.push(fixedRules);
  if (card.safetyRoute !== null) {
    lines.push(
      "A safety route is on the card, so training is not the topic today: suggest no training, loads, exercises or cardio, and never say it is fine to train. Point to the referral on the card; never diagnose or name a cause. " +
        routeRules[card.safetyRoute],
    );
  }
  const inState = (state: ContextJointState) =>
    card.jointStates.filter((joint) => joint.state === state).map((joint) => joint.area);
  const held = inState("held");
  const limited = inState("limited");
  const watch = inState("watch");
  if (held.length > 0) {
    lines.push(
      `Held (on hold until the athlete has had it checked): ${
        joinAreas(held)
      }. Suggest no exercise, load, stretch, range or test that works that area; never say it is healed, safe or fine, and never lift the hold yourself, only the athlete's own clearance does.`,
    );
  }
  // On a safety route the card changes no training, so no instruction about swaps, range or load
  // for a limited or watched area is given: only the referral and the holds above.
  if (card.safetyRoute === null && limited.length > 0) {
    lines.push(
      `Limited: ${
        joinAreas(limited)
      }. Keep to the card's swaps and shorter range for that area; do not push load or range there or suggest exercises that work it harder.`,
    );
  }
  if (card.safetyRoute === null && watch.length > 0) {
    lines.push(
      `Watch: ${
        joinAreas(watch)
      }. Tracend is only watching this area; do not turn it into a problem or wave it away, and let what the athlete says about it lead.`,
    );
  }
  const lasting = card.jointStates.filter((joint) => joint.persistent).map((joint) => joint.area);
  if (lasting.length > 0) {
    lines.push(
      `${
        joinAreas(lasting)
      }: this has lasted two weeks or more. Say it should be seen by a physio or doctor.`,
    );
  }
  return lines;
}

/** The block's text for a card, its date marked as a record. */
export function readinessMarked(card: ReadinessContext): string {
  return readinessLines(card).join("\n");
}

/** The block's text when the card could not be read: a gap is never read as "all clear". */
export function readinessUnknownText(): string {
  return [
    "Today's readiness card could not be read just now, so what it shows and whether a joint area is held are unknown.",
    "Do not say what the card shows, or that nothing is wrong with a joint. Do not describe an adjustment as offered, accepted or declined. If the athlete asks about the card, say it could not be read this time and that the card on Today shows it. Anything the athlete tells you about pain still counts.",
  ].join("\n");
}

export function createReadinessContributor(
  source: ReadinessSource,
  deadlineMs: number = readinessDeadlineMs,
): CoachContextContributor {
  return Object.freeze({
    id: readinessContributorId,
    slot: "volatile",
    budgetChars: readinessBudgetChars,
    async render(input): Promise<RenderedBlock> {
      const { value: card, status } = await readWithin(
        () => source(input.userId, input.localDate),
        deadlineMs,
      );
      const trace = { readiness: status };
      return card === null
        ? blockOf(readinessUnknownText(), { trace })
        : blockOf(readinessMarked(card), { trace });
    },
  });
}

export const readinessContributor: CoachContextContributor = createReadinessContributor(
  readinessFromService,
);
