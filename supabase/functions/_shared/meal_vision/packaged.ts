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
// - Every portion comes from one set of per-unit values, the unit being the one the label prints
//   (g, or ml for a drink): one serving, the whole pack, or (by weight only) any grams the athlete
//   types. The app recalculates from the same stored values. Millilitres are never treated as
//   grams: a label printed per ml is "label_unverified" (volume_basis) and offers only its printed
//   serving and pack, never a custom amount.
// - A front-of-pack photo or a plate is an "estimate": never high confidence. A front of pack is
//   low unless its net quantity is printed, and medium at most.
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
  /** A per-serving column without a serving size: no per-unit values. */
  "serving_size_missing",
  /** More energy or nutrients per gram than any food has. */
  "values_implausible",
  /** No nutrition column could be read: the values are the model's estimate. */
  "values_not_printed",
  /** The label prints per ml: not checked against a weight; only printed portions are offered. */
  "volume_basis",
  /**
   * No product name was readable: the row is named "Packaged food" (with the printed brand), never
   * the model's guess. It says nothing about the values, so it does not lower their source.
   */
  "name_not_printed",
] as const;
export type LabelIssue = typeof labelIssues[number];

export type MealSource = "label" | "label_unverified" | "estimate";
export type QuantityUnit = "g" | "ml";
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
  /** The unit of every size and per-unit value; null when there are none (a plate). */
  quantity_unit: QuantityUnit | null;
  /** Per gram (or per ml) of food, rounded to 4 decimals; all four or none. */
  kcal_per_unit: number | null;
  protein_per_unit: number | null;
  carbohydrate_per_unit: number | null;
  fat_per_unit: number | null;
  serving_size: number | null;
  servings_per_pack: number | null;
  pack_size: number | null;
  /** The amount the stored values are for, when they come from per-unit values. */
  portion_size: number | null;
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
export function basesAgree(
  per100g: Nutrients,
  perServing: Nutrients,
  servingSize: number,
): boolean {
  const close = (printed: number, expected: number, floor: number) =>
    Math.abs(printed - expected) <= Math.max(floor, 0.1 * expected);
  const scaled = (value: number) => value * servingSize / 100;
  return close(perServing.kcal, scaled(per100g.kcal), 5) &&
    close(perServing.protein_g, scaled(per100g.protein_g), 1) &&
    close(perServing.carbohydrate_g, scaled(per100g.carbohydrate_g), 1) &&
    close(perServing.fat_g, scaled(per100g.fat_g), 1);
}

/** Whether servings x serving size is the net weight, within 5% or 2 g. */
export function packAgrees(servings: number, servingSize: number, netSize: number): boolean {
  return Math.abs(servings * servingSize - netSize) <= Math.max(2, 0.05 * netSize);
}

/** No food has more than 9.5 kcal or more than 1 g of nutrients in a gram (or a millilitre). */
export function plausiblePerUnit(n: Nutrients): boolean {
  return n.kcal <= 9.5 && n.protein_g <= 1 && n.carbohydrate_g <= 1 && n.fat_g <= 1 &&
    n.protein_g + n.carbohydrate_g + n.fat_g <= 1.02;
}

const round = (value: number, places: number) => {
  const factor = 10 ** places;
  return Math.round(value * factor) / factor;
};

/** Per-unit values rounded the way the table stores them (4 decimals). */
export function perUnit(n: Nutrients, amount: number): Nutrients {
  return {
    kcal: round(n.kcal / amount, 4),
    protein_g: round(n.protein_g / amount, 4),
    carbohydrate_g: round(n.carbohydrate_g / amount, 4),
    fat_g: round(n.fat_g / amount, 4),
  };
}

/** A portion's values from per-unit values, to one decimal (the app computes the same). */
export function scale(perUnitValues: Nutrients, amount: number): Nutrients {
  return {
    kcal: round(perUnitValues.kcal * amount, 1),
    protein_g: round(perUnitValues.protein_g * amount, 1),
    carbohydrate_g: round(perUnitValues.carbohydrate_g * amount, 1),
    fat_g: round(perUnitValues.fat_g * amount, 1),
  };
}

/** An amount as a label shows it: up to one decimal, no trailing ".0". */
export function amountText(amount: number): string {
  return String(round(amount, 1));
}

/** "amount" is any weight the athlete types; it is never offered for ml. */
export type PortionKind = "serving" | "pack" | "amount";

export type PortionOption = Readonly<{
  kind: PortionKind;
  size: number;
  label: string;
  nutrients: Nutrients;
}>;

/** The label of a portion in its unit; the app builds the same text. */
export function portionLabel(kind: PortionKind, size: number, unit: QuantityUnit): string {
  const amount = `${amountText(size)} ${unit}`;
  switch (kind) {
    case "serving":
      return `1 serving (${amount})`;
    case "pack":
      return `Whole pack (${amount})`;
    case "amount":
      return amount;
  }
}

/** One serving and the whole pack, where their sizes are known. */
export function portionOptions(
  perUnitValues: Nutrients,
  servingSize: number | null,
  packSize: number | null,
  unit: QuantityUnit,
): PortionOption[] {
  const options: PortionOption[] = [];
  if (servingSize !== null) {
    options.push({
      kind: "serving",
      size: servingSize,
      label: portionLabel("serving", servingSize, unit),
      nutrients: scale(perUnitValues, servingSize),
    });
  }
  if (packSize !== null && packSize !== servingSize) {
    options.push({
      kind: "pack",
      size: packSize,
      label: portionLabel("pack", packSize, unit),
      nutrients: scale(perUnitValues, packSize),
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
 * The portion shown first. A small pack meant for one sitting (by weight, at most two servings
 * and 60 g, like a chocolate bar) is the whole pack; otherwise one serving, else the pack, else
 * 100 g or 100 ml (the printed column). A portion whose values the table cannot hold is skipped.
 */
export function defaultPortion(
  perUnitValues: Nutrients,
  servingSize: number | null,
  packSize: number | null,
  servings: number | null,
  unit: QuantityUnit,
): PortionOption {
  const options = portionOptions(perUnitValues, servingSize, packSize, unit);
  const pack = options.find((option) => option.kind === "pack");
  const serving = options.find((option) => option.kind === "serving");
  const singleSitting = unit === "g" && pack !== undefined && pack.size <= 60 &&
    (servings === null || servings <= 2);
  const ordered = singleSitting ? [pack, serving] : [serving, pack];
  const chosen = ordered.find((option) => option !== undefined && storable(option.nutrients));
  return chosen ?? {
    kind: "amount",
    size: 100,
    label: portionLabel("amount", 100, unit),
    nutrients: scale(perUnitValues, 100),
  };
}

export type LabelReading = Readonly<{
  unit: QuantityUnit;
  perUnit: Nutrients | null;
  /** The per-serving column, energy filled from the macronutrients when not printed. */
  perServing: Nutrients | null;
  servingSize: number | null;
  servingsPerPack: number | null;
  packSize: number | null;
  issues: readonly LabelIssue[];
}>;

// The candidate table's limits on sizes: a larger reading is not a food pack.
export const sizeMaximums = { servingSize: 5_000, packSize: 10_000, servings: 1_000 } as const;

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

/** Checks a nutrition label's arithmetic and derives its per-unit values. */
export function readLabel(answer: MealAnswer): LabelReading {
  const issues = new Set<LabelIssue>();
  const unit = answer.quantity_unit;
  if (unit === "ml") issues.add("volume_basis");
  const per100Printed: Nutrients | null = answer.has_per_100
    ? {
      kcal: answer.per_100_kcal,
      protein_g: answer.per_100_protein_g,
      carbohydrate_g: answer.per_100_carbohydrate_g,
      fat_g: answer.per_100_fat_g,
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
  const servingSize = size(answer.serving_size, sizeMaximums.servingSize, issues);
  const servingsPerPack = size(answer.servings_per_pack, sizeMaximums.servings, issues);
  const netSize = size(answer.net_quantity, sizeMaximums.packSize, issues);
  if (!per100Printed && !servingPrinted) issues.add("values_not_printed");
  for (const basis of [per100Printed, servingPrinted]) {
    if (basis && basis.kcal > 0 && !energyAddsUp(basis)) issues.add("energy_mismatch");
  }
  const per100 = per100Printed && withEnergy(per100Printed, issues);
  const perServing = servingPrinted && withEnergy(servingPrinted, issues);
  if (
    per100 && perServing && servingSize !== null && !basesAgree(per100, perServing, servingSize)
  ) {
    issues.add("basis_mismatch");
  }
  if (
    servingsPerPack !== null && servingSize !== null && netSize !== null &&
    !packAgrees(servingsPerPack, servingSize, netSize)
  ) {
    issues.add("pack_mismatch");
  }
  if (perServing && !per100 && servingSize === null) issues.add("serving_size_missing");
  let perUnitValues = per100
    ? perUnit(per100, 100)
    : perServing && servingSize !== null
    ? perUnit(perServing, servingSize)
    : null;
  if (perUnitValues && !plausiblePerUnit(perUnitValues)) {
    issues.add("values_implausible");
    perUnitValues = null;
  }
  const derivedPackSize = servingsPerPack !== null && servingSize !== null
    ? round(servingsPerPack * servingSize, 1)
    : null;
  const packSize = netSize ??
    (derivedPackSize !== null && derivedPackSize <= sizeMaximums.packSize ? derivedPackSize : null);
  return {
    unit,
    perUnit: perUnitValues,
    perServing,
    servingSize,
    servingsPerPack,
    packSize,
    issues: labelIssues.filter((issue) => issues.has(issue)),
  };
}

/** The neutral name of a pack whose name is not readable. */
export const unreadableProductName = "Packaged food";

/**
 * The product's name as printed, with its brand when the name leaves it out. With no readable name
 * it is "Packaged food", after the brand when one is printed: never the model's guess.
 */
export function productName(answer: MealAnswer): string {
  const name = answer.product_name.trim();
  const brand = answer.brand.trim();
  if (!name) {
    return (brand ? `${brand} ${unreadableProductName.toLowerCase()}` : unreadableProductName)
      .slice(0, 120);
  }
  const full = brand && !name.toLowerCase().includes(brand.toLowerCase())
    ? `${brand} ${name}`
    : name;
  return full.slice(0, 120);
}

/** name_not_printed when no product name was readable. */
const nameIssues = (answer: MealAnswer): LabelIssue[] =>
  answer.product_name.trim() ? [] : ["name_not_printed"];

const notes = (candidate: MealCandidate) => ({
  assumptions: candidate.assumptions.map((entry) => entry.trim().slice(0, 200))
    .filter((entry) => entry.length > 0).slice(0, 8),
  question: candidate.question.trim().slice(0, 500),
});

const noPortions = {
  quantity_unit: null,
  kcal_per_unit: null,
  protein_per_unit: null,
  carbohydrate_per_unit: null,
  fat_per_unit: null,
  serving_size: null,
  servings_per_pack: null,
  pack_size: null,
  portion_size: null,
} as const;

const values = (n: Nutrients) => ({
  calories: n.kcal,
  protein_g: n.protein_g,
  carbohydrate_g: n.carbohydrate_g,
  fat_g: n.fat_g,
});

const perUnitColumns = (n: Nutrients) => ({
  kcal_per_unit: n.kcal,
  protein_per_unit: n.protein_g,
  carbohydrate_per_unit: n.carbohydrate_g,
  fat_per_unit: n.fat_g,
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
  const unit = answer.quantity_unit;
  const netSize = size(answer.net_quantity, sizeMaximums.packSize);
  const estimate = nutrientsOf(candidate);
  const perUnitValues = netSize !== null ? perUnit(estimate, netSize) : null;
  const usable = perUnitValues !== null && plausiblePerUnit(perUnitValues) &&
    storable(scale(perUnitValues, netSize!));
  const base = {
    name: productName(answer),
    source: "estimate" as const,
    image_kind: "pack_front" as const,
    brand: answer.brand.trim().slice(0, 80),
    ...notes(candidate),
    label_issues: nameIssues(answer),
  };
  if (!usable) {
    return {
      ...base,
      serving_label: candidate.serving_label,
      ...values(estimate),
      confidence: "low",
      ...noPortions,
      quantity_unit: netSize === null ? null : unit,
      pack_size: netSize,
    };
  }
  return {
    ...base,
    serving_label: portionLabel("pack", netSize!, unit),
    ...values(scale(perUnitValues, netSize!)),
    confidence: atMost(candidate.confidence, "medium"),
    ...noPortions,
    ...perUnitColumns(perUnitValues),
    quantity_unit: unit,
    pack_size: netSize,
    portion_size: netSize,
  };
}

/** A nutrition label: printed values, checked, at the portion shown first. */
function labelCandidate(answer: MealAnswer, candidate: MealCandidate): StoredMealCandidate {
  const reading = readLabel(answer);
  const base = {
    name: productName(answer),
    image_kind: "nutrition_label" as const,
    brand: answer.brand.trim().slice(0, 80),
    ...notes(candidate),
    label_issues: [...reading.issues, ...nameIssues(answer)],
  };
  const sizes = {
    quantity_unit: reading.unit,
    serving_size: reading.servingSize,
    servings_per_pack: reading.servingsPerPack,
    pack_size: reading.packSize,
  };
  if (reading.perUnit) {
    const portion = defaultPortion(
      reading.perUnit,
      reading.servingSize,
      reading.packSize,
      reading.servingsPerPack,
      reading.unit,
    );
    // The name says nothing about the values: only the value checks set the source.
    const checked = reading.issues.length === 0;
    return {
      ...base,
      serving_label: portion.label,
      ...values(portion.nutrients),
      confidence: checked ? "high" : "low",
      source: checked ? "label" : "label_unverified",
      ...noPortions,
      ...perUnitColumns(reading.perUnit),
      ...sizes,
      portion_size: portion.size,
    };
  }
  if (reading.perServing && storable(reading.perServing)) {
    // A serving with no size: one serving as printed ("2 biscuits", "1 bar"), nothing to scale.
    return {
      ...base,
      serving_label: answer.serving_text.trim().slice(0, 80) || "1 serving",
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
