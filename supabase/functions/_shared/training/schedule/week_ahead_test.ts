import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { minimumDaysBetweenSessionsPerMuscle } from "../standard/volume.ts";
import {
  addDays,
  buildWeekAhead,
  consecutiveOverlaps,
  overlapAheadDays,
  overlapFactLine,
  renderOverlapFact,
  renderWeekAhead,
  type SchedulePoint,
  weekAheadDays,
} from "./week_ahead.ts";

const chest = [
  { slug: "barbell-bench-press", sets: 4 },
  { slug: "cable-lateral-raise", sets: 3 },
];
const legs = [{ slug: "barbell-back-squat", sets: 4 }, { slug: "leg-press", sets: 3 }];
const pull = [{ slug: "lat-pulldown", sets: 4 }, { slug: "barbell-row", sets: 3 }];

const at = (date: string, name: string, exercises: SchedulePoint["exercises"], kind = "planned") =>
  ({ date, name, exercises, kind }) as SchedulePoint;

// 2026-10-18 is a Sunday (weekday 7).
const sunday = "2026-10-18";

Deno.test("the gap rule is a day between sessions, from the coaching standard", () => {
  assertEquals(minimumDaysBetweenSessionsPerMuscle.value, 1);
});

Deno.test("a Sunday with Monday tomorrow: Monday is listed and the shared muscles are flagged", () => {
  const schedule = buildWeekAhead(sunday, 7, [
    at(sunday, "Chest volume", chest, "make_up"),
    at("2026-10-19", "Chest priority", chest),
    at("2026-10-20", "Legs A", legs),
  ]);
  assertEquals(schedule.days.length, weekAheadDays);
  assertEquals(schedule.days[0].offset, 0);
  assertEquals(schedule.days[1].date, "2026-10-19");
  assertEquals(schedule.overlaps.length, 1);
  assertEquals(schedule.overlaps[0].from.date, sunday);
  assertEquals(schedule.overlaps[0].to.date, "2026-10-19");
  assertEquals(schedule.overlaps[0].muscles, ["chest", "triceps", "front and side delts"]);
  const text = renderWeekAhead(schedule).join("\n");
  assertStringIncludes(text, "- Mon 2026-10-19 (tomorrow): Chest priority");
  assertStringIncludes(
    overlapFactLine(schedule.overlaps)!,
    "Sun 2026-10-18 then Mon 2026-10-19: ",
  );
  // The schedule block does not state the fact: the watch-outs block does.
  assert(!text.includes("Same muscles on consecutive days"));
  assertStringIncludes(text, "undone earlier this week: Chest volume");
});

Deno.test("mid-week: a heavy day after a rest day is not an overlap, and a pair ahead is found", () => {
  const wednesday = "2026-10-14";
  const schedule = buildWeekAhead(wednesday, 3, [
    at("2026-10-12", "Chest priority", chest),
    at(wednesday, "Pull", pull),
    at("2026-10-15", "Chest volume", chest),
    at("2026-10-16", "Chest again", chest),
  ]);
  // Monday's chest is not a day to compare (it is before yesterday); Wednesday and Thursday train
  // different muscles; Thursday and Friday share chest, one and two days ahead.
  assertEquals(schedule.overlaps.map((o) => [o.from.date, o.to.date]), [[
    "2026-10-15",
    "2026-10-16",
  ]]);
});

Deno.test("a rest day between two sessions that share muscles is no overlap", () => {
  const schedule = buildWeekAhead(sunday, 7, [
    at(sunday, "Chest volume", chest),
    at("2026-10-20", "Chest priority", chest),
  ]);
  assertEquals(schedule.overlaps, []);
  assertEquals(renderOverlapFact(schedule.overlaps), null);
  const text = renderWeekAhead(schedule).join("\n");
  assert(!text.includes("consecutive"));
  assertStringIncludes(text, "- Mon 2026-10-19 (tomorrow): no session");
});

Deno.test("yesterday's finished session counts against today's: done and planned alike", () => {
  const schedule = buildWeekAhead("2026-10-19", 1, [
    at(sunday, "Chest volume", chest, "done"),
    at("2026-10-19", "Chest priority", chest),
  ]);
  assertEquals(schedule.days[0].offset, -1);
  assertEquals(schedule.overlaps.length, 1);
  assertStringIncludes(renderWeekAhead(schedule).join("\n"), "done: Chest volume");
});

Deno.test("two sessions that share no muscle on consecutive days give no fact", () => {
  const schedule = buildWeekAhead(sunday, 7, [
    at(sunday, "Legs A", legs),
    at("2026-10-19", "Pull", pull),
  ]);
  assertEquals(schedule.overlaps, []);
  assert(!renderWeekAhead(schedule).join("\n").includes("consecutive"));
});

Deno.test("an overlap more than two days ahead is not raised; the pair must reach into the next 2 days", () => {
  assertEquals(overlapAheadDays, 2);
  const schedule = buildWeekAhead(sunday, 7, [
    at("2026-10-21", "Chest volume", chest),
    at("2026-10-22", "Chest priority", chest),
  ]);
  assertEquals(schedule.overlaps, []);
});

Deno.test("a plan with no upcoming sessions lists seven rest days and no overlap", () => {
  const schedule = buildWeekAhead(sunday, 7, []);
  assertEquals(schedule.days.length, weekAheadDays);
  assertEquals(schedule.overlaps, []);
  const lines = renderWeekAhead(schedule);
  assertEquals(lines.length, weekAheadDays + 1);
  assert(lines.slice(1).every((line) => line.endsWith("no session")));
});

Deno.test("the schedule follows the athlete's date: late Sunday night local is Sunday, though UTC says Monday", () => {
  // 23:30 on Sunday 2026-10-18 in Los Angeles is already Monday 06:30 UTC. The coaching date is
  // the athlete's local one, and the schedule uses nothing else (no clock).
  const schedule = buildWeekAhead(sunday, 7, [
    at(sunday, "Chest volume", chest, "make_up"),
    at("2026-10-19", "Chest priority", chest),
  ]);
  assertEquals(schedule.days[0].date, sunday);
  assertEquals(schedule.days[0].weekday, 7);
  assertEquals(schedule.days[1].weekday, 1);
  assertStringIncludes(renderWeekAhead(schedule)[2], "(tomorrow)");
  // The same plan seen from the UTC date would call Monday today and drop the pair.
  const utcView = buildWeekAhead("2026-10-19", 1, [at("2026-10-19", "Chest priority", chest)]);
  assertEquals(utcView.overlaps, []);
});

Deno.test("date arithmetic crosses month and year ends", () => {
  assertEquals(addDays("2026-12-30", 3), "2027-01-02");
  assertEquals(addDays("2026-03-01", -1), "2026-02-28");
  const schedule = buildWeekAhead("2026-12-31", 4, [at("2027-01-01", "Legs A", legs)]);
  assertEquals(schedule.days[1].date, "2027-01-01");
  assertEquals(schedule.days[1].weekday, 5);
});

Deno.test("sessions with unknown exercises say so instead of hiding the gap", () => {
  const schedule = buildWeekAhead(sunday, 7, [
    at(sunday, "Custom day", [{ slug: null, sets: 4 }, ...legs]),
  ]);
  assertStringIncludes(renderWeekAhead(schedule).join("\n"), "[muscles of 1 exercises unknown]");
});

Deno.test("the overlap fact is a structured value with its own one-line rendering", () => {
  const days = buildWeekAhead(sunday, 7, [
    at(sunday, "Chest volume", chest),
    at("2026-10-19", "Chest priority", chest),
  ]);
  const overlaps = consecutiveOverlaps(days.days);
  assertEquals(overlaps.length, 1);
  const line = renderOverlapFact(overlaps)!;
  assert(!line.includes("\n"));
  assertStringIncludes(line, "Same muscles on consecutive days");
  // The lookup result carries the advice after the fact; the watch-outs block states it once.
  assertStringIncludes(line, "A change of day or exercise is a proposal the athlete approves.");
  assert(!overlapFactLine(overlaps)!.includes("proposal"));
  assertEquals(overlapFactLine([]), null);
});

Deno.test("face pulls the day before a press day are not a back-to-back shoulder day", () => {
  const pullWithFacePulls = [
    { slug: "lat-pulldown", sets: 4 },
    { slug: "face-pull", sets: 3 },
  ];
  const press = [{ slug: "barbell-overhead-press", sets: 3 }, {
    slug: "cable-lateral-raise",
    sets: 3,
  }];
  const apart = buildWeekAhead(sunday, 7, [
    at(sunday, "Pull", pullWithFacePulls),
    at("2026-10-19", "Press", press),
  ]);
  assertEquals(apart.overlaps, []);
});

Deno.test("side and front delts on consecutive days, and rear delts on consecutive days, are flagged", () => {
  const press = [{ slug: "dumbbell-shoulder-press", sets: 3 }, {
    slug: "cable-lateral-raise",
    sets: 3,
  }];
  const raises = [{ slug: "dumbbell-lateral-raise", sets: 4 }];
  const sideAndFront = buildWeekAhead(sunday, 7, [
    at(sunday, "Raises", raises),
    at("2026-10-19", "Press", press),
  ]);
  assertEquals(sideAndFront.overlaps.map((o) => o.muscles), [["front and side delts"]]);
  const rear = buildWeekAhead(sunday, 7, [
    at(sunday, "Pull A", [{ slug: "face-pull", sets: 3 }]),
    at("2026-10-19", "Pull B", [{ slug: "dumbbell-rear-delt-fly", sets: 3 }]),
  ]);
  assertEquals(rear.overlaps.map((o) => o.muscles), [["rear delts"]]);
});

Deno.test("a day with a note and no session reads as the note, not as a session", () => {
  const schedule = buildWeekAhead(sunday, 7, [], [{
    date: "2026-10-19",
    text: "Legs A was already done this week, on 2026-10-13",
  }]);
  assertEquals(schedule.days[1].sessions, []);
  assertStringIncludes(
    renderWeekAhead(schedule)[2],
    "(tomorrow): no session; Legs A was already done this week, on 2026-10-13",
  );
});

Deno.test("the overlap line speaks in dates, not hours: no claim finer than a day", () => {
  const schedule = buildWeekAhead(sunday, 7, [
    at(sunday, "Chest volume", chest),
    at("2026-10-19", "Chest priority", chest),
  ]);
  const text = overlapFactLine(schedule.overlaps)!;
  assertStringIncludes(text, "Same muscles on consecutive days, with no rest day between");
  assert(!/hour|under a day|48/i.test(text));
  assert(!/hour|under a day|48/i.test(renderOverlapFact(schedule.overlaps)!));
});
