import {
  type MealCandidate,
  mealCandidatesSchema,
} from "../providers/gemini_meal_vision_provider.ts";
import { validMealCandidates } from "../providers/groq_meal_vision_provider.ts";

// The answer a meal photo gets on the AI gateway path (Claude): what kind of photo it is, what a
// pack or its nutrition table prints, and the candidate foods. The model copies printed values
// and estimates plates; deterministic code (packaged.ts) checks the label arithmetic, works out
// the portions and sets the confidence. The athlete edits and confirms every value.
//
// Claude compiles a grammar per schema and caches it, and the compile grows with every optional
// property and every union (see coach_chat_schema_test.ts). So the schema is flat, every property
// is required and nothing is a union: a value that is not printed is "" or 0, and a nutrition
// column that is not printed has its has_* flag false. meal_vision_schema_test.ts guards it.

export const imageKinds = ["plate", "pack_front", "nutrition_label", "no_food"] as const;
export type ImageKind = typeof imageKinds[number];

/** What a pack or its nutrition table prints. "" and 0 when not printed or not packaged. */
export type PrintedProduct = Readonly<{
  product_name: string;
  brand: string;
  net_weight_g: number;
  servings_per_pack: number;
  serving_size_g: number;
  /** The serving as printed, e.g. "1/2 bar (18.7 g)". */
  serving_text: string;
  has_per_100g: boolean;
  per_100g_kcal: number;
  per_100g_protein_g: number;
  per_100g_carbohydrate_g: number;
  per_100g_fat_g: number;
  has_per_serving: boolean;
  per_serving_kcal: number;
  per_serving_protein_g: number;
  per_serving_carbohydrate_g: number;
  per_serving_fat_g: number;
}>;

export type MealAnswer =
  & PrintedProduct
  & Readonly<{ image_kind: ImageKind; candidates: readonly MealCandidate[] }>;

const textFields = { product_name: 120, brand: 80, serving_text: 80 } as const;

// Generous limits: a value this far out is not a reading of a label. Plausibility (a kcal per
// gram no food reaches, macros above the weight) is judged in packaged.ts, which keeps the
// values and marks the label unclear instead of refusing the photo.
const numberFields = {
  net_weight_g: 100_000,
  servings_per_pack: 10_000,
  serving_size_g: 100_000,
  per_100g_kcal: 100_000,
  per_100g_protein_g: 10_000,
  per_100g_carbohydrate_g: 10_000,
  per_100g_fat_g: 10_000,
  per_serving_kcal: 100_000,
  per_serving_protein_g: 10_000,
  per_serving_carbohydrate_g: 10_000,
  per_serving_fat_g: 10_000,
} as const;

const flagFields = ["has_per_100g", "has_per_serving"] as const;

const number = { type: "number" } as const;
const text = { type: "string" } as const;

/** The structured output the meal photo request asks for. */
export const mealAnswerSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    image_kind: { type: "string", enum: [...imageKinds] },
    product_name: text,
    brand: text,
    net_weight_g: number,
    servings_per_pack: number,
    serving_size_g: number,
    serving_text: text,
    has_per_100g: { type: "boolean" },
    per_100g_kcal: number,
    per_100g_protein_g: number,
    per_100g_carbohydrate_g: number,
    per_100g_fat_g: number,
    has_per_serving: { type: "boolean" },
    per_serving_kcal: number,
    per_serving_protein_g: number,
    per_serving_carbohydrate_g: number,
    per_serving_fat_g: number,
    candidates: mealCandidatesSchema.properties.candidates,
  },
  required: [
    "image_kind",
    ...Object.keys(textFields),
    ...Object.keys(numberFields),
    ...flagFields,
    "candidates",
  ],
} as const;

const invalid = () => new Error("meal_vision_response_invalid");

/**
 * The answer when it is complete and consistent with its kind; throws
 * meal_vision_response_invalid otherwise. A photo of no food has no candidate, a plate has at
 * least one, and a pack or a label exactly one: the product.
 */
export function parseMealAnswer(value: unknown): MealAnswer {
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw invalid();
  const answer = value as Record<string, unknown>;
  if (!(imageKinds as readonly unknown[]).includes(answer.image_kind)) throw invalid();
  for (const [field, limit] of Object.entries(textFields)) {
    const item = answer[field];
    if (typeof item !== "string" || item.length > limit) throw invalid();
  }
  for (const [field, limit] of Object.entries(numberFields)) {
    const item = answer[field];
    if (typeof item !== "number" || !Number.isFinite(item) || item < 0 || item > limit) {
      throw invalid();
    }
  }
  for (const field of flagFields) {
    if (typeof answer[field] !== "boolean") throw invalid();
  }
  const candidates = validMealCandidates(answer);
  const kind = answer.image_kind as ImageKind;
  const expected = kind === "no_food"
    ? candidates.length === 0
    : kind === "plate"
    ? candidates.length >= 1
    : candidates.length === 1;
  if (!expected) throw invalid();
  // Only the schema's fields go on, whatever else the object carried.
  const picked: Record<string, unknown> = { image_kind: kind, candidates };
  for (const field of [...Object.keys(textFields), ...Object.keys(numberFields), ...flagFields]) {
    picked[field] = answer[field];
  }
  return picked as MealAnswer;
}
