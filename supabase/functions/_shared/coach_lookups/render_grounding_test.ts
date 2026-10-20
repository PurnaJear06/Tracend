// What grounds a figure in a reply, lookup by lookup and field by field (`lookupGrounding` in
// render.ts). A model's words (a decision's summary, the reason on a plan, a nutrition target or a
// proposal, Coach's own earlier reply) are shown to Coach and never count as evidence that a figure
// is true; the athlete's records and Tracend's calculations do. The table is the declaration and
// this test is the check: it fails for a lookup or mode with no entry, an entry with no fixture, and
// a field that grounds when it should not, or the reverse.
import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { coachLookupCatalogue } from "./catalogue.ts";
import {
  bodyPayload,
  checkInsPayload,
  decisionsPayload,
  exerciseHistoryPayload,
  goalsPayload,
  healthMonthsPayload,
  mealsPayload,
  pastMessagesCoachPayload,
  planVersionsPayload,
  proposalsLookupPayload,
  recoveryPayload,
  request,
  scheduleLookupPayload,
  watchWorkoutsPayload,
  weeklyReviewsPayload,
  workoutsNotesPayload,
} from "./lookup_fixtures.ts";
import { lookupGrounding, lookupRendererNames, renderLookup } from "./render.ts";

const fixtures: Readonly<Record<string, unknown>> = {
  "workouts/default": workoutsNotesPayload,
  "exercise_history/default": exerciseHistoryPayload,
  "meals/default": mealsPayload,
  "body/default": bodyPayload,
  "check_ins/default": checkInsPayload,
  "recovery/default": recoveryPayload,
  "plan_history/default": planVersionsPayload,
  "plan_history/schedule": scheduleLookupPayload,
  "plan_history/proposals": proposalsLookupPayload,
  "goals/default": goalsPayload,
  "weekly_reviews/default": weeklyReviewsPayload,
  "weekly_reviews/decisions": decisionsPayload,
  "health_history/default": healthMonthsPayload,
  "health_history/workouts": watchWorkoutsPayload,
  "past_messages/default": pastMessagesCoachPayload,
};

/** A copy of the payload with `marker` in the field at `path` of every element on the way. */
function mark(payload: unknown, path: string, marker: string): unknown {
  const copy = structuredClone(payload) as Record<string, unknown>;
  const put = (node: unknown, steps: string[]): void => {
    const [step, ...rest] = steps;
    if (Array.isArray(node)) {
      for (const item of node) put(item, steps);
      return;
    }
    if (node === null || typeof node !== "object") return;
    const object = node as Record<string, unknown>;
    const list = step.endsWith("[]");
    const key = list ? step.slice(0, -2) : step;
    if (rest.length === 0) {
      if (list) return;
      object[key] = marker;
    } else {
      put(object[key], rest);
    }
  };
  put(copy, path.split("."));
  return copy;
}

const everyScope = new Set(["breathing_rate", "workout_notes"] as const);

Deno.test("every lookup and every mode declares what grounds, and has a fixture", () => {
  const declared = Object.keys(lookupGrounding).sort();
  assertEquals(declared, coachLookupCatalogue.map((spec) => spec.name).sort());
  assertEquals([...lookupRendererNames].sort(), declared);
  for (const spec of coachLookupCatalogue) {
    const modes = ["default", ...("filterModes" in spec ? spec.filterModes : [])].sort();
    assertEquals(Object.keys(lookupGrounding[spec.name]).sort(), modes, spec.name);
    for (const mode of modes) assert(`${spec.name}/${mode}` in fixtures, `${spec.name}/${mode}`);
  }
  assertEquals(Object.keys(fixtures).length, 15);
});

Deno.test("each declared field grounds a figure or does not, exactly as declared", () => {
  let checked = 0;
  for (const [lookup, modes] of Object.entries(lookupGrounding)) {
    for (const [mode, fields] of Object.entries(modes)) {
      const fixture = fixtures[`${lookup}/${mode}`];
      const asked = request(
        lookup as never,
        "2026-08-01",
        "2026-10-17",
        mode === "default" ? null : mode,
      );
      const all = [
        ...fields.grounds.map((path) => ({ path, grounds: true })),
        ...fields.modelText.map((path) => ({ path, grounds: false })),
      ];
      assert(all.length > 0, `${lookup}/${mode} declares nothing`);
      for (const { path, grounds } of all) {
        const marker = `MK${100000 + checked}Z`;
        checked += 1;
        const rendered = renderLookup(asked, mark(fixture, path, marker), 20_000, everyScope);
        const where = `${lookup}/${mode} ${path}`;
        // Coach reads it either way...
        assert(rendered.text.includes(marker), `${where} is not shown`);
        // ...and it is evidence only when the field is a record.
        assertEquals(rendered.grounds.join("\n").includes(marker), grounds, where);
      }
    }
  }
  assert(checked >= 50, `${checked} fields checked`);
});

Deno.test("a figure written by a model in a lookup row is not a ground, and the record around it is", () => {
  const rendered = renderLookup(
    request("weekly_reviews", "2026-10-01", "2026-10-17", "decisions"),
    decisionsPayload,
  );
  const grounds = rendered.grounds.join("\n");
  // The decision's own words are shown...
  assert(rendered.text.includes("Reduce training intensity today."));
  assert(rendered.text.includes("Reduce intensity"));
  // ...but ground nothing, while its date, its codes and its flags do.
  assert(!grounds.includes("Reduce"));
  assert(grounds.includes("- 2026-10-16: ADJUST TODAY; nutrition MAINTAIN TARGETS;"));
  assert(grounds.includes("Confidence high; flags elevated_load"));
  const plan = renderLookup(
    request("plan_history", "2026-08-01", "2026-10-17"),
    planVersionsPayload,
  );
  assert(plan.text.includes("A split that fits four days"));
  assert(!plan.grounds.join("\n").includes("A split that fits four days"));
  assert(plan.grounds.join("\n").includes("2300 kcal, protein 160 g"));
});
