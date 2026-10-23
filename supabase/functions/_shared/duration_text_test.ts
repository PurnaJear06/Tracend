import { assertEquals } from "jsr:@std/assert@1.0.14";
import { renderCoachContextParts, replyCheckInputsFor } from "./providers/coach_chat_provider.ts";
import { renderLookup } from "./coach_lookups/render.ts";
import { recoveryPayload, request } from "./coach_lookups/lookup_fixtures.ts";
import { coachReplyCheckFor } from "./providers/coach_chat_provider.ts";
import { hoursNote, minutesCell, minutesText } from "./duration_text.ts";

// The whole hours and the rest are the app's split (recovery_readout_card.dart `_formatMinutes`:
// hours = minutes ~/ 60, rest = minutes % 60; nothing but minutes under an hour; no rest, no
// minutes). The hours to one decimal is the one rounding the numbers check allows a reply.
Deno.test("a duration in minutes is shown with the hours and minutes the app shows and the hours to one decimal", () => {
  const cases: readonly [number, string, string][] = [
    [0, "0 min", "0"],
    [45, "45 min", "45"],
    [59, "59 min", "59"],
    [60, "60 min (1 h)", "60 (1 h)"],
    [341, "341 min (5 h 41 min; 5.7 h)", "341 (5 h 41 min; 5.7 h)"],
    [355, "355 min (5 h 55 min; 5.9 h)", "355 (5 h 55 min; 5.9 h)"],
    [420, "420 min (7 h)", "420 (7 h)"],
    [425, "425 min (7 h 5 min; 7.1 h)", "425 (7 h 5 min; 7.1 h)"],
    [412.4, "412.4 min (6 h 52 min; 6.9 h)", "412.4 (6 h 52 min; 6.9 h)"],
    [1560, "1560 min (26 h)", "1560 (26 h)"],
  ];
  for (const [minutes, text, cell] of cases) {
    assertEquals(minutesText(minutes), text, String(minutes));
    assertEquals(minutesCell(minutes), cell, String(minutes));
  }
  // Not a number: the stored text is kept as it was.
  assertEquals(hoursNote(null), null);
  assertEquals(minutesText(null, "—"), "— min");
  assertEquals(minutesCell("n/a", "n/a"), "n/a");
});

Deno.test('"you slept 5.7 h" rests on a 341-minute row, in the file and in a lookup', () => {
  const ctx = {
    coaching_date: "2026-10-17",
    permitted_evidence: [],
    health_daily_28d: [{
      local_date: "2026-10-16",
      sleep_minutes: 341,
      resting_heart_rate_bpm: 52,
    }],
    health_averages: {
      last_7_days: { days_synced: 1, avg_sleep_minutes: 341, days_with_sleep: 1 },
    },
  };
  const file = renderCoachContextParts(ctx, 100_000).file;
  assertEquals(file.includes("| 2026-10-16 | 341 (5 h 41 min; 5.7 h) | 52 |"), true);
  assertEquals(file.includes("sleep 341 min (5 h 41 min; 5.7 h) over 1 day measured"), true);
  for (
    const answer of [
      "On 2026-10-16 you slept 5.7 h.",
      "On 2026-10-16 you slept 5 h 41 min.",
      "On 2026-10-16 you slept 341 min.",
    ]
  ) {
    assertEquals(coachReplyCheckFor(ctx, "How did I sleep?", null)(answer, [], answer), null);
  }
  // A figure the row does not hold is still refused.
  const wrong = "On 2026-10-16 you slept 6.4 h.";
  assertEquals(
    coachReplyCheckFor(ctx, "How did I sleep?", null)(wrong, [], wrong) === null,
    false,
  );
  const lookup = renderLookup(request("recovery", "2026-10-10", "2026-10-17"), recoveryPayload);
  assertEquals(lookup.text.includes("sleep 355 min (5 h 55 min; 5.9 h)"), true);
  const inputs = replyCheckInputsFor(ctx, "q", null, lookup.grounds as string[]);
  assertEquals(inputs.athleteGround!.values.some((v) => v.value === 5.9 && v.unit === "h"), true);
});
