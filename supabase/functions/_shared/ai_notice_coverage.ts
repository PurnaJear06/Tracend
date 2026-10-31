// What the accepted AI coaching notice names, for data that reached Coach after the notice was
// written. A new kind of the athlete's data reaches the AI provider only under a notice that names
// it (AI_SAFETY_SPEC §10.3); a notice is published by the owner and never edited, so the text of
// each version is the record of what it covers. The Coach chat sends what the notice lists:
// "training plan and workout logs, check-ins, Apple Health summaries (sleep, heart rate, HRV, steps
// and workouts), meals and nutrition targets, body measurements, goals, focus muscles and
// preferences, and the messages you send the Coach" (ai-coaching-v5 and v6, the same list).
//
// Of the fields the Coach lookups grew on 2026-10-20, these two are not in that list and are held
// back until a version that names them is published (the wording is an owner decision, see
// docs/handoff/ai-gateway.md):
//   breathing_rate  Apple Health breathing rate (the list names sleep, heart rate, HRV, steps, workouts)
//   workout_notes   the athlete's free text in a workout: the session note, an exercise's note and
//                   the reason for a swap (the list names workout logs, not what the athlete wrote in them)
// Covered by the list, so not gated: sleep stages (sleep), night and morning HRV (HRV), workout
// minutes (workouts), the watch's workouts (workouts), proposals and daily decisions (Tracend's own
// text about the plan, targets and goals the list names), and Coach's own earlier replies (the
// conversation memory already sends them).

export type NoticeScope = "breathing_rate" | "workout_notes";

/**
 * The first `ai-coaching-vN` version whose text names the data, or null when no published version
 * does. To open a scope, publish the notice, then set its number here in the same change.
 */
export const firstNoticeNaming: Readonly<Record<NoticeScope, number | null>> = Object.freeze({
  breathing_rate: null,
  workout_notes: null,
});

const versionPattern = /^ai-coaching-v(\d+)$/;

/** Whether the athlete's accepted notice version names the data. An unknown version names nothing. */
export function noticeNames(noticeVersion: string | null, scope: NoticeScope): boolean {
  const first = firstNoticeNaming[scope];
  const found = noticeVersion === null ? null : versionPattern.exec(noticeVersion)?.[1];
  return first !== null && found !== null && found !== undefined && Number(found) >= first;
}

/** The scopes a notice version opens. */
export function noticeScopes(noticeVersion: string | null): ReadonlySet<NoticeScope> {
  return new Set(
    (Object.keys(firstNoticeNaming) as NoticeScope[]).filter((scope) =>
      noticeNames(noticeVersion, scope)
    ),
  );
}
