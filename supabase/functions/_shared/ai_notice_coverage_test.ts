import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { firstNoticeNaming, noticeNames, noticeScopes } from "./ai_notice_coverage.ts";

Deno.test("no published notice names breathing rate or the athlete's free text in a workout yet", () => {
  assertEquals(firstNoticeNaming, { breathing_rate: null, workout_notes: null });
  for (const version of ["ai-coaching-v5", "ai-coaching-v6", "ai-coaching-v99", null, "other"]) {
    assertEquals([...noticeScopes(version)], []);
    assert(!noticeNames(version, "breathing_rate"));
    assert(!noticeNames(version, "workout_notes"));
  }
});
