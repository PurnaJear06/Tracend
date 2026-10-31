import {
  type MealCandidate,
  mealCandidateMaximums,
} from "../providers/gemini_meal_vision_provider.ts";
import type { MealAnswer } from "./contract.ts";

// What meal-analyze stores for review, worked out by code from the model's answer (CLAUDE.md
// rule 1: the model reads and proposes, deterministic code calculates).
//
// - A nutrition label is checked: energy against protein, carbohydrate and fat (4/4/9 kcal per
//   gram), the per-serving column against the per 100 g column, servings x serving size against
//   the net weight. A label that passes is "label" with high confidence; one that does not is
//   "label_unverified" with low confidence, its values kept and each failed check named.
// - Every portion comes from one set of per-gram values: one serving, the whole pack, or any
//   grams the athlete types. The app recalculates from the same stored values.
// - A front-of-pack photo or a plate is an "estimate": never high confidence. A front of pack is
//   low unless its net weight is printed, and medium at most.
// The model's own confidence is never more than an upper bound for an estimate.

export const labelIssues = [
  /** Energy is not 4 x protein + 4 x carbohydrate + 9 x fat within the tolerance. */
  "energy_mismatch",
  /** The per-serving column is not the per 100 g column scaled to the serving size. */
  "basis_mismatch",
  /** Servings x serving size is not the net weight. */
  "pack_mismatch",
  /** No energy printed: it was calculated from protein, carbohydrate and fat. */
  "energy_not_printed",
  /** A per-serving column without a serving weight: no per-gram values. */
  "serving_size_missing",
  /** More energy or nutrients per gram than any food has. */
  "values_implausible",
  /** No nutrition column could be read: the values are the model's estimate. */
  "values_not_printed",
] as const;
export type LabelIssue = typeof labelIssues[number];

export type MealSource = "label" | "label_unverified" | "estimate";
export type Confidence = MealCandidate["confidence"];

export type Nutrients = Readonly<{
  kcal: number;
  protein_g: number;
  carbohydrate_g: number;
  fat_g: number;
}>;

/** One row of meal_analysis_candidates as persist_meal_photo_candidates takes it. */
export type StoredMealCandidate = Readonly<{
  name: string;
  serving_label: string;
  calories: number;
  protein_g: number;
  carbohydrate_g: number;
  fat_g: number;
  confidence: Confidence;
  source: MealSource;
  image_kind: "plate" | "pack_front" | "nutrition_label";
  brand: string;
  /** Per gram of food, rounded to 4 decimals; all four or none. */
  kcal_per_g: number | null;
  protein_per_g: number | null;
  carbohydrate_per_g: number | null;
  fat_per_g: number | null;
  serving_g: number | null;
  servings_per_pack: number | null;
  pack_g: number | null;
  /** The grams the stored values are for, when they come from per-gram values. */
  portion_g: number | null;
  assumptions: readonly string[];
  question: string;
  label_issues: readonly LabelIssue[];
}>;

const confidenceOrder: readonly Confidence[] = ["low", "medium", "high"];

/** The lower of two confidences. */
export function atMost(confidence: Confidence, cap: Confidence): Confidence {
  return confidenceOrder.indexOf(confidence) <= confidenceOrder.indexOf(cap) ? confidence : cap;
}

/** Energy from the macronutrients at 4, 4 and 9 kcal per gram. */
export function atwaterKcal(n: Nutrients): number {
  return 4 * n.protein_g + 4 * n.carbohydrate_g + 9 * n.fat_g;
}

/**
 * Whether printed energy agrees with its macronutrients: within 15% of the larger, or 8 kcal on
 * a small serving. Labels round each value and some count fibre or polyols, so a tighter check
 * would flag honest labels; 85 kcal printed for 102 kcal of macronutrients does not pass.
 */
export function energyAddsUp(n: Nutrients): boolean {
  const atwater = atwaterKcal(n);
  return Math.abs(n.kcal - atwater) <= Math.max(8, 0.15 * Math.max(n.kcal, atwater));
}

/**
 * Whether the per-serving column is the per 100 g column scaled to the serving: within 10% for
 * each value, or 5 kcal and 1 g for label rounding.
 */
export function basesAgree(per100g: Nutrients, perServing: Nutrients, servingG: number): boolean {
  const close = (printed: number, expected: number, floor: number) =>
    Math.abs(printed - expected) <= Math.max(floor, 0.1 * expected);
  const scaled = (value: number) => value * servingG / 100;
  return close(perServing.kcal, scaled(per100g.kcal), 5) &&
    close(perServing.protein_g, scaled(per100g.protein_g), 1) &&
    close(perServing.carbohydrate_g, scaled(per100g.carbohydrate_g), 1) &&
    close(perServing.fat_g, scaled(per100g.fat_g), 1);
}

/** Whether servings x serving size is the net weight, within 5% or 2 g. */
export function packAgrees(servings: number, servingG: number, netG: number): boolean {
  return Math.abs(servings * servingG - netG) <= Math.max(2, 0.05 * netG);
}

/** No food has more than 9.5 kcal or more than 1 g of nutrients in a gram. */
export function plausiblePerGram(n: Nutrients): boolean {
  return n.kcal <= 9.5 && n.protein_g <= 1 && n.carbohydrate_g <= 1 && n.fat_g <= 1 &&
    n.protein_g + n.carbohydrate_g + n.fat_g <= 1.02;
}

const round = (value: number, places: number) => {
  const factor = 10 ** places;
  return Math.round(value * factor) / factor;
};

/** Per-gram values rounded the way the table stores them (4 decimals). */
export function perGram(n: Nutrients, grams: number): Nutrients {
  return {
    kcal: round(n.kcal / grams, 4),
    protein_g: round(n.protein_g / grams, 4),
    carbohydrate_g: round(n.carbohydrate_g / grams, 4),
    fat_g: round(n.fat_g / grams, 4),
  };
}

/** A portion's values from per-gram values, to one decimal (the app computes the same). */
export function scale(perGramValues: Nutrients, grams: number): Nutrients {
  return {
    kcal: round(perGramValues.kcal * grams, 1),
    protein_g: round(perGramValues.protein_g * grams, 1),
    carbohydrate_g: round(perGramValues.carbohydrate_g * grams, 1),
    fat_g: round(perGramValues.fat_g * grams, 1),
  };
}

/** Grams as a label shows them: up to one decimal, no trailing ".0". */
export function gramsText(grams: number): string {
  return String(round(grams, 1));
}

export type PortionKind = "serving" | "pack" | "grams";

export type PortionOption = Readonly<{
  kind: PortionKind;
  grams: number;
  label: string;
  nutrients: Nutrients;
}>;

/** The label of a portion; the app builds the same text. */
export function portionLabel(kind: PortionKind, grams: number): string {
  switch (kind) {
    case "serving":
      return `1 serving (${gramsText(grams)} g)`;
    case "pack":
      return `Whole pack (${gramsText(grams)} g)`;
    case "grams":
      return `${gramsText(grams)} g`;
  }
}

/** One serving and the whole pack, where their weights are known. Any grams are also offered. */
export function portionOptions(
  perGramValues: Nutrients,
  servingG: number | null,
  packG: number | null,
): PortionOption[] {
  const options: PortionOption[] = [];
  if (servingG !== null) {
    options.push({
      kind: "serving",
      grams: servingG,
      label: portionLabel("serving", servingG),
      nutrients: scale(perGramValues, servingG),
    });
  }
  if (packG !== null && packG !== servingG) {
    options.push({
      kind: "pack",
      grams: packG,
      label: portionLabel("pack", packG),
      nutrients: scale(perGramValues, packG),
    });
  }
  return options;
}

/** Whether every value fits the candidate table's checks. */
export function storable(n: Nutrients): boolean {
  return n.kcal <= mealCandidateMaximums.calories &&
    n.protein_g <= mealCandidateMaximums.protein_g &&
    n.carbohydrate_g <= mealCandidateMaximums.carbohydrate_g &&
    n.fat_g <= mealCandidateMaximums.fat_g;
}

/**
 * The portion shown first. A small pack meant for one sitting (at most two servings and 60 g,
 * like a chocolate bar) is the whole pack; otherwise one serving, else the pack, else 100 g. A
 * portion whose values the table cannot hold is skipped.
 */
export function defaultPortion(
  perGramValues: Nutrients,
  servingG: number | null,
  packG: number | null,
  servings: number | null,
): PortionOption {
  const options = portionOptions(perGramValues, servingG, packG);
  const pack = options.find((option) => option.kind === "pack");
  const serving = options.find((option) => option.kind === "serving");
  const singleSitting = pack !== undefined && pack.grams <= 60 &&
    (servings === null || servings <= 2);
  const ordered = singleSitting ? [pack, serving] : [serving, pack];
  const chosen = ordered.find((option) => option !== undefined && storable(option.nutrients));
  return chosen ?? {
    kind: "grams",
    grams: 100,
    label: portionLabel("grams", 100),
    nutrients: scale(perGramValues, 100),
  };
}

export type LabelReading = Readonly<{
  perGram: Nutrients | null;
  /** The per-serving column, energy filled from the macronutrients when not printed. */
  perServing: Nutrients | null;
  servingG: number | null;
  servingsPerPack: number | null;
  packG: number | null;
  issues: readonly LabelIssue[];
}>;

// The candidate table's limits on sizes: a larger reading is not a food pack.
export const sizeMaximums = { servingG: 5_000, packG: 10_000, servings: 1_000 } as const;

/** A printed size above zero and within its limit; null otherwise (too large marks the label). */
function size(value: number, maximum: number, issues?: Set<LabelIssue>): number | null {
  if (value > maximum) issues?.add("values_implausible");
  return value > 0 && value <= maximum ? value : null;
}

/** Energy as printed, or from the macronutrients when the label prints none. */
function withEnergy(n: Nutrients, issues: Set<LabelIssue>): Nutrients {
  if (n.kcal > 0 || atwaterKcal(n) === 0) return n;
  issues.add("energy_not_printed");
  return { ...n, kcal: round(atwaterKcal(n), 1) };
}

/** Checks a nutrition label's arithmetic and derives its per-gram values. */
export function readLabel(answer: MealAnswer): LabelReading {
  const issues = new Set<LabelIssue>();
  const per100Printed: Nutrients | null = answer.has_per_100g
    ? {
      kcal: answer.per_100g_kcal,
      protein_g: answer.per_100g_protein_g,
      carbohydrate_g: answer.per_100g_carbohydrate_g,
      fat_g: answer.per_100g_fat_g,
    }
    : null;
  const servingPrinted: Nutrients | null = answer.has_per_serving
    ? {
      kcal: answer.per_serving_kcal,
      protein_g: answer.per_serving_protein_g,
      carbohydrate_g: answer.per_serving_carbohydrate_g,
      fat_g: answer.per_serving_fat_g,
    }
    : null;
  const servingG = size(answer.serving_size_g, sizeMaximums.servingG, issues);
  const servingsPerPack = size(answer.servings_per_pack, sizeMaximums.servings, issues);
  const netG = size(answer.net_weight_g, sizeMaximums.packG, issues);
  if (!per100Printed && !servingPrinted) issues.add("values_not_printed");
  for (const basis of [per100Printed, servingPrinted]) {
    if (basis && basis.kcal > 0 && !energyAddsUp(basis)) issues.add("energy_mismatch");
  }
  const per100 = per100Printed && withEnergy(per100Printed, issues);
  const perServing = servingPrinted && withEnergy(servingPrinted, issues);
  if (per100 && perServing && servingG !== null && !basesAgree(per100, perServing, servingG)) {
    issues.add("basis_mismatch");
  }
  if (
    servingsPerPack !== null && servingG !== null && netG !== null &&
    !packAgrees(servingsPerPack, servingG, netG)
  ) {
    issues.add("pack_mismatch");
  }
  if (perServing && !per100 && servingG === null) issues.add("serving_size_missing");
  let perGramValues = per100
    ? perGram(per100, 100)
    : perServing && servingG !== null
    ? perGram(perServing, servingG)
    : null;
  if (perGramValues && !plausiblePerGram(perGramValues)) {
    issues.add("values_implausible");
    perGramValues = null;
  }
  const derivedPackG = servingsPerPack !== null && servingG !== null
    ? round(servingsPerPack * servingG, 1)
    : null;
  const packG = netG ??
    (derivedPackG !== null && derivedPackG <= sizeMaximums.packG ? derivedPackG : null);
  return {
    perGram: perGramValues,
    perServing,
    servingG,
    servingsPerPack,
    packG,
    issues: labelIssues.filter((issue) => issues.has(issue)),
  };
}

/** The product's name as printed, with its brand when the name leaves it out. */
export function productName(answer: MealAnswer, fallback: string): string {
  const name = answer.product_name.trim();
  const brand = answer.brand.trim();
  if (!name) return fallback;
  const full = brand && !name.toLowerCase().includes(brand.toLowerCase())
    ? `${brand} ${name}`
    : name;
  return full.slice(0, 120);
}

const notes = (candidate: MealCandidate) => ({
  assumptions: candidate.assumptions.map((entry) => entry.trim().slice(0, 200))
    .filter((entry) => entry.length > 0).slice(0, 8),
  question: candidate.question.trim().slice(0, 500),
});

const noPortions = {
  kcal_per_g: null,
  protein_per_g: null,
  carbohydrate_per_g: null,
  fat_per_g: null,
  serving_g: null,
  servings_per_pack: null,
  pack_g: null,
  portion_g: null,
} as const;

const values = (n: Nutrients) => ({
  calories: n.kcal,
  protein_g: n.protein_g,
  carbohydrate_g: n.carbohydrate_g,
  fat_g: n.fat_g,
});

const perGramColumns = (n: Nutrients) => ({
  kcal_per_g: n.kcal,
  protein_per_g: n.protein_g,
  carbohydrate_per_g: n.carbohydrate_g,
  fat_per_g: n.fat_g,
});

const nutrientsOf = (candidate: MealCandidate): Nutrients => ({
  kcal: candidate.calories,
  protein_g: candidate.protein_g,
  carbohydrate_g: candidate.carbohydrate_g,
  fat_g: candidate.fat_g,
});

/** A food on a plate, from any provider: an estimate, never high confidence. */
export function plateCandidate(candidate: MealCandidate): StoredMealCandidate {
  return {
    name: candidate.name,
    serving_label: candidate.serving_label,
    ...values(nutrientsOf(candidate)),
    confidence: atMost(candidate.confidence, "medium"),
    source: "estimate",
    image_kind: "plate",
    brand: "",
    ...noPortions,
    ...notes(candidate),
    label_issues: [],
  };
}

/** The front of a pack: the model's estimate for the whole pack, scaled by its printed weight. */
function packFrontCandidate(answer: MealAnswer, candidate: MealCandidate): StoredMealCandidate {
  const netG = size(answer.net_weight_g, sizeMaximums.packG);
  const estimate = nutrientsOf(candidate);
  const perGramValues = netG !== null ? perGram(estimate, netG) : null;
  const usable = perGramValues !== null && plausiblePerGram(perGramValues) &&
    storable(scale(perGramValues, netG!));
  const base = {
    name: productName(answer, candidate.name),
    source: "estimate" as const,
    image_kind: "pack_front" as const,
    brand: answer.brand.trim().slice(0, 80),
    ...notes(candidate),
    label_issues: [],
  };
  if (!usable) {
    return {
      ...base,
      serving_label: candidate.serving_label,
      ...values(estimate),
      confidence: "low",
      ...noPortions,
      pack_g: netG,
    };
  }
  return {
    ...base,
    serving_label: portionLabel("pack", netG!),
    ...values(scale(perGramValues, netG!)),
    confidence: atMost(candidate.confidence, "medium"),
    ...noPortions,
    ...perGramColumns(perGramValues),
    pack_g: netG,
    portion_g: netG,
  };
}

/** A nutrition label: printed values, checked, at the portion shown first. */
function labelCandidate(answer: MealAnswer, candidate: MealCandidate): StoredMealCandidate {
  const reading = readLabel(answer);
  const base = {
    name: productName(answer, candidate.name),
    image_kind: "nutrition_label" as const,
    brand: answer.brand.trim().slice(0, 80),
    ...notes(candidate),
    label_issues: reading.issues,
  };
  const sizes = {
    serving_g: reading.servingG,
    servings_per_pack: reading.servingsPerPack,
    pack_g: reading.packG,
  };
  if (reading.perGram) {
    const portion = defaultPortion(
      reading.perGram,
      reading.servingG,
      reading.packG,
      reading.servingsPerPack,
    );
    const checked = reading.issues.length === 0;
    return {
      ...base,
      serving_label: portion.label,
      ...values(portion.nutrients),
      confidence: checked ? "high" : "low",
      source: checked ? "label" : "label_unverified",
      ...noPortions,
      ...perGramColumns(reading.perGram),
      ...sizes,
      portion_g: portion.grams,
    };
  }
  if (reading.perServing && storable(reading.perServing)) {
    // A serving with no weight: one serving as printed, and nothing to scale.
    return {
      ...base,
      serving_label: "1 serving",
      ...values(reading.perServing),
      confidence: "low",
      source: "label_unverified",
      ...noPortions,
      ...sizes,
    };
  }
  // Nothing on the label could be used: the model's estimate, said to be one.
  return {
    ...base,
    serving_label: candidate.serving_label,
    ...values(nutrientsOf(candidate)),
    confidence: "low",
    source: "estimate",
    ...noPortions,
    ...sizes,
  };
}

/** The rows to store for review; none for a photo of no food. */
export function storedCandidates(answer: MealAnswer): StoredMealCandidate[] {
  switch (answer.image_kind) {
    case "no_food":
      return [];
    case "plate":
      return answer.candidates.map(plateCandidate);
    case "pack_front":
      return [packFrontCandidate(answer, answer.candidates[0])];
    case "nutrition_label":
      return [labelCandidate(answer, answer.candidates[0])];
  }
}
