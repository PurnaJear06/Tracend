// Progression steps: when and by how much a prescription moves forward. Rule
// data only; nothing reads it yet (B3 progresses from the sets actually logged).
import type { EquipmentItem } from "../../onboarding/catalog.ts";
import { sourced } from "./sources.ts";

/** A load increase, as a share of the current load: [min, max] percent. */
export const loadIncreasePercent = sourced(
  [2, 10] as const,
  ["acsm_2009"],
  "ACSM 2009 recommends raising the load by 2-10% once the lifter can do one to two reps " +
    "more than the target at the current load.",
);

/**
 * Double progression: reps rise inside the range first; the load rises only
 * when every working set reached the top of its range with at least the
 * target reps in reserve, then reps restart at the bottom of the range.
 */
export const addLoadWhen = sourced(
  "every_set_at_top_of_range" as const,
  ["acsm_2009", "helms_2016", "tracend_in_house"],
  "ACSM 2009's trigger is one to two reps beyond the target; with a rep range, reaching the " +
    "top of the range on every set is that signal (in-house mapping). Checking it against the " +
    "reps left in reserve keeps a grinding set from counting (Helms 2016).",
);

/** Reps added to a set from one session to the next before the load rises. */
export const repsAddedPerSession = sourced(
  1,
  ["tracend_in_house"],
  "One more rep per set per session is the smallest step a lifter can log; no open source " +
    "sets this number, so it is an in-house choice that the reps-left check keeps honest.",
);

/**
 * The smallest load increase each loading implement allows, in kg (per
 * dumbbell or kettlebell, total for a barbell or a stack). null: the exercise
 * progresses by reps, a harder variation or a stronger band, not by kg.
 */
export const loadStepKgByEquipment = sourced<
  Readonly<Record<EquipmentItem, number | null>>
>(
  Object.freeze({
    barbell: 2.5,
    dumbbells: 2.5,
    kettlebells: 4,
    machines: 5,
    cables: 2.5,
    bands: null,
    bench: null,
    pull_up_bar: null,
  }),
  ["tracend_in_house"],
  "Common commercial increments, not research findings: a pair of 1.25 kg plates on a " +
    "barbell, 2.5 kg between fixed dumbbells, 4 kg between standard kettlebells, a 5 kg plate " +
    "on a machine stack and 2.5 kg on a cable stack. The athlete's logged loads override them " +
    "when their equipment differs. Bands, benches and bars hold or resist the body, so they " +
    "have no kg step.",
);

/** Which implement sets an exercise's load step when it needs several. */
export const loadingEquipmentOrder = sourced<readonly EquipmentItem[]>(
  Object.freeze(["barbell", "dumbbells", "kettlebells", "machines", "cables"] as const),
  ["tracend_in_house"],
  "In-house rule: an exercise's load comes from its loading implement, not its bench or bar; no catalog " +
    "exercise needs two loading implements, so the order only documents the rule.",
);
