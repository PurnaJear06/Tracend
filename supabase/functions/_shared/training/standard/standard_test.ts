import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import * as cardio from "./cardio.ts";
import * as deload from "./deload.ts";
import * as jointStress from "./joint_stress.ts";
import * as joints from "../joints/rules.ts";
import * as prescription from "./prescription.ts";
import * as readiness from "../readiness/rules.ts";
import * as progression from "./progression.ts";
import { type Sourced, sources } from "./sources.ts";
import * as volume from "./volume.ts";

const ruleModules = {
  cardio,
  deload,
  jointStress,
  joints,
  prescription,
  progression,
  readiness,
  volume,
};

const isSourced = (value: unknown): value is Sourced<unknown> =>
  typeof value === "object" && value !== null && "value" in value && "sources" in value &&
  "basis" in value;

// Every rule value in the standard, with its path. A number, string or list
// outside a Sourced wrapper is an unsourced value and fails the walk.
function ruleValues(): { path: string; rule: Sourced<unknown> }[] {
  const found: { path: string; rule: Sourced<unknown> }[] = [];
  const walk = (value: unknown, path: string) => {
    if (typeof value === "function") return;
    if (isSourced(value)) {
      found.push({ path, rule: value });
      return;
    }
    if (typeof value === "object" && value !== null && !Array.isArray(value)) {
      for (const [key, child] of Object.entries(value)) walk(child, `${path}.${key}`);
      return;
    }
    throw new Error(`${path} is a rule value without a source`);
  };
  for (const [name, module] of Object.entries(ruleModules)) {
    for (const [key, value] of Object.entries(module)) {
      // Vocabularies (joint names, stress levels) are labels, not rule values.
      if (name === "jointStress" && (key === "joints" || key === "jointStressLevels")) continue;
      walk(value, `${name}.${key}`);
    }
  }
  return found;
}

Deno.test("every rule value has a known source and a basis in our own words", () => {
  const rules = ruleValues();
  assert(rules.length >= 20, `only ${rules.length} rule values found`);
  for (const { path, rule } of rules) {
    assert(rule.sources.length > 0, `${path} has no source`);
    for (const id of rule.sources) assert(id in sources, `${path} cites unknown ${id}`);
    assertEquals(new Set(rule.sources).size, rule.sources.length, `${path} repeats a source`);
    assert(rule.basis.trim().length >= 40, `${path} needs a basis`);
    if (rule.sources.length === 1 && rule.sources[0] === "tracend_in_house") {
      assert(/in-house|no open source|not research/i.test(rule.basis), `${path}: say why`);
    }
  }
});

Deno.test("every source is cited, and published sources carry a DOI and PubMed id", () => {
  const cited = new Set(ruleValues().flatMap(({ rule }) => rule.sources));
  for (const [id, source] of Object.entries(sources)) {
    assertEquals(source.id, id);
    assert(cited.has(id as keyof typeof sources), `${id} is never cited`);
    if (source.access === "in_house") {
      assertEquals([source.doi, source.pmid, source.pmcid], [null, null, null]);
      continue;
    }
    assert(/^10\.\d{4,}\/\S+$/.test(source.doi ?? ""), `${id} DOI`);
    assert(/^\d{6,9}$/.test(source.pmid ?? ""), `${id} PMID`);
    assertEquals(source.access === "full_text", source.pmcid !== null, `${id} access`);
    if (source.pmcid) assert(/^PMC\d+$/.test(source.pmcid), `${id} PMCID`);
  }
});

Deno.test("ranges are ordered and inside today's onboarding policy limits", () => {
  for (const { path, rule } of ruleValues()) {
    const value = rule.value;
    if (Array.isArray(value) && value.length === 2 && value.every(Number.isFinite)) {
      assert(value[0] <= value[1], `${path} is reversed`);
    }
  }
  for (const emphasis of ["strength", "hypertrophy"] as const) {
    for (const experience of ["beginner", "intermediate", "advanced"] as const) {
      for (const kind of ["compound", "isolation"] as const) {
        const [min, max] = prescription.repRanges[emphasis][experience][kind].value;
        assert(min >= (emphasis === "strength" ? 3 : 6) && max <= 20, `${emphasis} reps`);
      }
    }
    for (const kind of ["compound", "isolation"] as const) {
      const [min] = prescription.restSeconds[emphasis][kind].value;
      assert(min >= 60, `${emphasis} ${kind} rest`);
    }
  }
  const sets = volume.weeklySetsPerMuscle;
  assert(sets.minimum.value < sets.growth.value);
  assert(sets.growth.value <= sets.maximum.beginner.value);
  assert(sets.maximum.beginner.value <= sets.maximum.intermediate.value);
  assert(sets.maximum.intermediate.value <= sets.maximum.advanced.value);
  // An advanced lifter starts the climb at the bottom of Baz-Valle's 12-20 range, inside the maximum.
  assert(sets.growth.value <= sets.advancedGrowth.value);
  assert(sets.advancedGrowth.value < sets.maximum.advanced.value);
  for (const experience of ["beginner", "intermediate", "advanced"] as const) {
    const [low, high] = volume.trainingDaysPerWeek[experience].value;
    assert(low <= high && high <= 6);
  }
});

Deno.test("every experience level has its own rule value for each prescription", () => {
  for (const experience of ["beginner", "intermediate", "advanced"] as const) {
    assert(prescription.targetRepsInReserve[experience].sources.length > 0, experience);
    for (const emphasis of ["strength", "hypertrophy"] as const) {
      for (const kind of ["compound", "isolation"] as const) {
        assert(prescription.repRanges[emphasis][experience][kind].basis.length > 0, experience);
      }
    }
  }
  // Advanced and intermediate share the cited ranges: no source separates them.
  assertEquals(
    prescription.repRanges.strength.advanced.compound.value,
    prescription.repRanges.strength.intermediate.compound.value,
  );
  assertEquals(
    prescription.targetRepsInReserve.advanced.value,
    prescription.targetRepsInReserve.intermediate.value,
  );
});

Deno.test("undulation splits a compound range into a heavy and a light part that cover it exactly", () => {
  for (const emphasis of ["strength", "hypertrophy"] as const) {
    const range = prescription.repRanges[emphasis].advanced.compound.value;
    const heavy = prescription.undulatedRepRange(range, "heavy");
    const light = prescription.undulatedRepRange(range, "light");
    assertEquals(heavy[0], range[0]);
    assertEquals(light[1], range[1]);
    assertEquals(light[0], heavy[1] + 1);
    assert(
      heavy[1] > heavy[0] && light[1] > light[0],
      `${emphasis}: each part keeps room to progress`,
    );
  }
  assert(prescription.undulation.sources.includes("moesgaard_2022"));
});
