import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { firstNoticeNaming, noticeNames, noticeScopes } from "./ai_notice_coverage.ts";

Deno.test("ai-coaching-v7 is the first notice that names breathing rate, workout notes and cycle data", () => {
  assertEquals(firstNoticeNaming, { breathing_rate: 7, workout_notes: 7, cycle_data: 7 });
  for (const version of ["ai-coaching-v7", "ai-coaching-v8", "ai-coaching-v12"]) {
    assertEquals([...noticeScopes(version)].sort(), [
      "breathing_rate",
      "cycle_data",
      "workout_notes",
    ]);
  }
});

Deno.test("the live notice (v6) and every earlier or unknown version name none of them", () => {
  for (
    const version of [
      "ai-coaching-v6",
      "ai-coaching-v5",
      "ai-coaching-v1",
      null,
      "other",
      "ai-coaching-v",
      "ai-coaching-v7-draft",
      "AI-COACHING-V7",
      " ai-coaching-v7",
    ]
  ) {
    assertEquals([...noticeScopes(version)], [], String(version));
    assert(!noticeNames(version, "breathing_rate"));
    assert(!noticeNames(version, "workout_notes"));
    assert(!noticeNames(version, "cycle_data"));
  }
});
