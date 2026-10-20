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
import { leafPaths, resolve } from "../grounding.ts";
import { numberGroundOf, ungroundedNumbers } from "../coach_safety/numbers_check.ts";
import { changeAt, filledPaths, pathsRead, variantsOf } from "../grounding_probe.ts";
import { lookupGrounding, lookupRendererNames, rendererOf, renderLookup } from "./render.ts";

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

/** Fields that only say which request the payload answers; the heading is made from the request. */
const requestEcho = new Set(["schema_version", "lookup", "from", "to", "filter"]);

const askedFor = (lookup: string, mode: string) =>
  request(lookup as never, "2026-08-01", "2026-10-17", mode === "default" ? null : mode);

Deno.test("every field a renderer reads is declared, whether or not the fixture's value made it appear", () => {
  const problems: string[] = [];
  for (const [lookup, modes] of Object.entries(lookupGrounding)) {
    for (const [mode, declaration] of Object.entries(modes)) {
      const resolved = resolve(declaration);
      const declared = new Set(
        (["records", "figures", "modelText", "controls"] as const).flatMap((kind) => [
          ...resolved[kind],
        ]),
      );
      const read = pathsRead(fixtures[`${lookup}/${mode}`], (spied) => {
        rendererOf(lookup)(spied as never, everyScope);
      });
      assert(read.size > 3, `${lookup}/${mode} reads ${read.size} fields`);
      for (const path of read) {
        if (!requestEcho.has(path) && !declared.has(path)) {
          problems.push(`${lookup}/${mode} reads ${path}, which is not declared`);
        }
      }
    }
  }
  assertEquals(problems, []);
});

Deno.test("a fixture fills every field it has, so a conditional field cannot hide from the checks", () => {
  const problems: string[] = [];
  for (const [name, fixture] of Object.entries(fixtures)) {
    const filled = filledPaths(fixture);
    for (const path of leafPaths(fixture)) {
      if (!filled.has(path)) problems.push(`${name} ${path} is null in every row`);
    }
  }
  assertEquals(problems, []);
});

/**
 * What a change to the field at `path` does to a result: whether the text Coach reads changes (the
 * field is shown), whether the rows that ground change, and whether the proposal figures change.
 * The change keeps the field's type; the first one that changes the text is used.
 */
function effectOf(lookup: string, mode: string, fixture: unknown, path: string, seed: number) {
  const asked = askedFor(lookup, mode);
  const read = (payload: unknown) => {
    const rendered = renderLookup(asked, payload, 20_000, everyScope);
    return {
      text: rendered.text,
      grounds: rendered.grounds.join("\n"),
      figures: rendered.proposalGrounds.join("\n"),
    };
  };
  const base = read(fixture);
  for (let variant = 0; variant < 3; variant++) {
    const changed = read(
      changeAt(fixture, path, (value) => {
        const options = variantsOf(value, seed);
        return options[Math.min(variant, options.length - 1)];
      }),
    );
    if (changed.text === base.text) continue;
    return {
      shown: true,
      grounds: changed.grounds !== base.grounds,
      figures: changed.figures !== base.figures,
    };
  }
  return { shown: false, grounds: false, figures: false };
}

Deno.test("every field a lookup shows is declared, and each grounds a figure, grounds a proposal's figure, or does not, exactly as declared", () => {
  const problems: string[] = [];
  let verified = 0;
  let seed = 0;
  for (const [lookup, modes] of Object.entries(lookupGrounding)) {
    for (const [mode, declaration] of Object.entries(modes)) {
      const fixture = fixtures[`${lookup}/${mode}`];
      const resolved = resolve(declaration);
      const kinds = new Map<string, "records" | "figures" | "modelText" | "controls">();
      for (const kind of ["records", "figures", "modelText", "controls"] as const) {
        for (const path of resolved[kind]) kinds.set(path, kind);
      }
      assert(kinds.size > 0, `${lookup}/${mode} declares nothing`);
      const paths = leafPaths(fixture);
      for (const path of paths) {
        // The version of the payload decides whether it is read at all, not what it shows.
        if (path === "schema_version") continue;
        const where = `${lookup}/${mode} ${path}`;
        const effect = effectOf(lookup, mode, fixture, path, seed++);
        const kind = kinds.get(path);
        if (kind === "controls") continue;
        if (kind === undefined) {
          if (effect.shown) problems.push(`${where} is shown but not declared`);
          continue;
        }
        if (!effect.shown) {
          problems.push(`${where} is declared but changing it does not change what Coach reads`);
        } else if (effect.grounds !== (kind === "records")) {
          problems.push(`${where} (${kind}) grounds=${effect.grounds}`);
        } else if (effect.figures !== (kind === "figures")) {
          problems.push(`${where} (${kind}) grounds a proposal's figure=${effect.figures}`);
        } else verified += 1;
      }
      for (const path of kinds.keys()) {
        if (!paths.has(path)) problems.push(`${lookup}/${mode} ${path} is not in the fixture`);
      }
    }
  }
  assertEquals(problems, []);
  // The count of fields checked end to end (shown, then grounding as declared), not of fields walked.
  assert(verified >= 170, `${verified} fields verified`);
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

Deno.test("what a row shows about a set's heart rate and a goal's non-weight targets grounds a true reply", () => {
  const sets = renderLookup(
    request("workouts", "2026-10-01", "2026-10-17"),
    workoutsNotesPayload,
    20_000,
    everyScope,
  );
  const setGround = numberGroundOf(sets.grounds);
  const heart = ungroundedNumbers(
    "Your heart rate fell 24 bpm after 60 s, from a 152 bpm peak.",
    setGround,
  );
  assertEquals(heart, []);
  const goals = renderLookup(request("goals", "2026-07-01", "2026-10-17"), goalsPayload);
  const goalGround = numberGroundOf(goals.grounds);
  assertEquals(
    ungroundedNumbers(
      "Your recomposition goal asks for 12-15% body fat by 2027-01-31.",
      goalGround,
    ),
    [],
  );
  assertEquals(ungroundedNumbers("Your goal asks for 18% body fat.", goalGround), ["18"]);
});
