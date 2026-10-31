// Model answers for the meal vision tests. Synthetic values only.

import type { MealCandidate } from "../providers/gemini_meal_vision_provider.ts";
import type { MealAnswer, PrintedProduct } from "./contract.ts";

/** Every product field as the schema asks for a photo that is not a pack: "", 0 and false. */
export const noProduct: PrintedProduct = {
  quantity_unit: "g",
  product_name: "",
  brand: "",
  net_quantity: 0,
  servings_per_pack: 0,
  serving_size: 0,
  serving_text: "",
  has_per_100: false,
  per_100_kcal: 0,
  per_100_protein_g: 0,
  per_100_carbohydrate_g: 0,
  per_100_fat_g: 0,
  has_per_serving: false,
  per_serving_kcal: 0,
  per_serving_protein_g: 0,
  per_serving_carbohydrate_g: 0,
  per_serving_fat_g: 0,
};

export const dal: MealCandidate = {
  name: "Dal tadka",
  serving_label: "1 bowl",
  calories: 220,
  protein_g: 11,
  carbohydrate_g: 28,
  fat_g: 8,
  confidence: "medium",
  assumptions: ["Ghee on top is about 1 tsp"],
  question: "Was ghee added after cooking?",
};

/** A plate answer with these candidates (none: a photo of no food). */
export function plateAnswer(candidates: readonly MealCandidate[]): MealAnswer {
  return { image_kind: candidates.length === 0 ? "no_food" : "plate", ...noProduct, candidates };
}
