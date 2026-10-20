import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { scheduleLookupPayload } from "../../coach_lookups/lookup_fixtures.ts";
import { readScheduleBody } from "./lookup_body.ts";

Deno.test("the schedule payload reads as days with their finished sessions and the planned ones nobody answered", () => {
  const body = readScheduleBody(scheduleLookupPayload);
  assertEquals(body.today, "2026-10-18");
  assertEquals(body.planId, "v-3");
  assertEquals(body.days.map((day) => day.date), [
    "2026-10-15",
    "2026-10-18",
    "2026-10-19",
    "2026-10-20",
  ]);
  // Thursday's chest session was planned and not logged; Sunday's was logged under the same id.
  assertEquals(body.days[0].unlogged, [{ id: "w-chest-b", name: "Chest volume" }]);
  assertEquals(body.days[1].done.map((item) => item.name), ["Chest volume"]);
  assertEquals(body.days[1].unlogged, []);
  assertEquals(body.exercisesByWorkout.get("w-legs")?.length, 2);
});

Deno.test("a session logged under another version's workout is matched by name; one of the day's own version is matched by id only", () => {
  const day = {
    date: "2026-10-07",
    weekday: 3,
    version_id: "v-3",
    version: 3,
    block: false,
    planned: [{ id: "w-pull", name: "Pull day" }],
  };
  const payload = (done: unknown[]) => ({
    to: "2026-10-13",
    plan: { id: "v-3", version: 3 },
    sessions: [{ id: "w-pull", version_id: "v-3", name: "Pull day", exercises: [] }],
    days: [{ ...day, done }],
  });
  // Logged under an id the day's version does not hold: the name answers it.
  assertEquals(
    readScheduleBody(payload([{ planned_workout_id: "w-old", name: "Pull day", exercises: [] }]))
      .days[0].unlogged,
    [],
  );
  // Logged under another workout of the same version with the same name: not the planned one.
  const sameVersion = {
    ...payload([{ planned_workout_id: "w-other", name: "Pull day", exercises: [] }]),
    sessions: [
      { id: "w-pull", version_id: "v-3", name: "Pull day", exercises: [] },
      { id: "w-other", version_id: "v-3", name: "Pull day", exercises: [] },
    ],
  };
  assertEquals(readScheduleBody(sameVersion).days[0].unlogged.length, 1);
  assertEquals(
    readScheduleBody(payload([{ planned_workout_id: "w-pull", name: "Pull day", exercises: [] }]))
      .days[0].unlogged,
    [],
  );
});

Deno.test("a missing or foreign payload reads as an empty schedule, and today falls back to the range's end", () => {
  const empty = readScheduleBody(null);
  assertEquals(empty.days, []);
  assertEquals(empty.planId, null);
  assertEquals(readScheduleBody({ to: "2026-10-13", days: [] }).today, "2026-10-13");
  assert(readScheduleBody({ today: "2026-10-18", to: "2026-10-13" }).today === "2026-10-18");
});

Deno.test("each planned session carries its id and whether it was logged; two workouts with one name stay two", () => {
  const body = readScheduleBody({
    to: "2026-10-13",
    plan: { id: "v-3", version: 3 },
    sessions: [
      { id: "w-a", version_id: "v-3", name: "Pull day", exercises: [] },
      { id: "w-b", version_id: "v-3", name: "Pull day", exercises: [] },
    ],
    days: [{
      date: "2026-10-07",
      weekday: 3,
      version_id: "v-3",
      version: 3,
      block: false,
      planned: [{ id: "w-a", name: "Pull day" }, { id: "w-b", name: "Pull day" }],
      done: [{ planned_workout_id: "w-a", name: "Pull day", exercises: [] }],
    }],
  });
  assertEquals(body.days[0].planned, [
    { id: "w-a", name: "Pull day", logged: true },
    { id: "w-b", name: "Pull day", logged: false },
  ]);
  assertEquals(body.days[0].unlogged, [{ id: "w-b", name: "Pull day" }]);
  assertEquals([...body.currentWorkoutIds].sort(), ["w-a", "w-b"]);
});
