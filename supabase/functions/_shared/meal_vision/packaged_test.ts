import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1.0.14";
import type { MealAnswer } from "./contract.ts";
import { parseMealAnswer } from "./contract.ts";
import golden from "./munch_label_golden.json" with { type: "json" };
import {
  atMost,
  atwaterKcal,
  basesAgree,
  defaultPortion,
  energyAddsUp,
  type LabelIssue,
  packAgrees,
  plateCandidate,
  plausiblePerUnit,
  portionLabel,
  portionOptions,
  productName,
  readLabel,
  scale,
  storedCandidates,
} from "./packaged.ts";
import { dal, noProduct, plateAnswer } from "./test_fixtures.ts";

const munch = () => parseMealAnswer(structuredClone(golden.answer));
const label = (overrides: Partial<MealAnswer>): MealAnswer => ({ ...munch(), ...overrides });

// The label arithmetic -------------------------------------------------------------------------

Deno.test("energy adds up at 4/4/9 within 15%, or 8 kcal on a small serving", () => {
  assertEquals(atwaterKcal({ kcal: 0, protein_g: 1.5, carbohydrate_g: 8.7, fat_g: 6.8 }), 102);
  // The live answer of 31 Oct: 85 kcal printed for 102 kcal of macronutrients is refused.
  assertFalse(energyAddsUp({ kcal: 85, protein_g: 1.5, carbohydrate_g: 8.7, fat_g: 6.8 }));
  assert(energyAddsUp({ kcal: 98, protein_g: 1.5, carbohydrate_g: 10.8, fat_g: 5.4 }));
  assert(energyAddsUp({ kcal: 523, protein_g: 8.2, carbohydrate_g: 57.6, fat_g: 28.9 }));
  // A fibre-rich label 12% under its macronutrients still passes; 20% over does not.
  assert(energyAddsUp({ kcal: 352, protein_g: 10, carbohydrate_g: 80, fat_g: 0 }));
  assertFalse(energyAddsUp({ kcal: 480, protein_g: 10, carbohydrate_g: 80, fat_g: 0 }));
  // A tiny serving: 3 kcal printed for 9 kcal of rounded macronutrients is within 8 kcal.
  assert(energyAddsUp({ kcal: 3, protein_g: 0, carbohydrate_g: 0, fat_g: 1 }));
});

Deno.test("the per-serving column must be the per 100 g column at the serving size", () => {
  const per100 = { kcal: 523, protein_g: 8.2, carbohydrate_g: 57.6, fat_g: 28.9 };
  assert(basesAgree(per100, { kcal: 98, protein_g: 1.5, carbohydrate_g: 10.8, fat_g: 5.4 }, 18.7));
  // The per 100 g row read as one serving is not the serving.
  assertFalse(basesAgree(per100, per100, 18.7));
  // A serving size misread as 37.4 g doubles every expected value.
  assertFalse(
    basesAgree(per100, { kcal: 98, protein_g: 1.5, carbohydrate_g: 10.8, fat_g: 5.4 }, 37.4),
  );
});

Deno.test("servings x serving size must be the net weight, within 5% or 2 g", () => {
  assert(packAgrees(2, 18.7, 37.4));
  assert(packAgrees(4, 25, 102));
  assertFalse(packAgrees(2, 25, 37.4));
  assertFalse(packAgrees(10, 30, 330));
});

Deno.test("no food has more than 9.5 kcal or 1 g of nutrients in a gram", () => {
  assert(plausiblePerUnit({ kcal: 9, protein_g: 0, carbohydrate_g: 0, fat_g: 1 }));
  assertFalse(plausiblePerUnit({ kcal: 25, protein_g: 0.1, carbohydrate_g: 0.5, fat_g: 0.3 }));
  assertFalse(plausiblePerUnit({ kcal: 5, protein_g: 0.5, carbohydrate_g: 0.5, fat_g: 0.3 }));
});

// Portions -------------------------------------------------------------------------------------

Deno.test("golden: the Munch label gives one serving and the whole pack, both right", () => {
  const reading = readLabel(munch());
  assertEquals(reading.issues, []);
  assertEquals(reading.perUnit, {
    kcal: 5.23,
    protein_g: 0.082,
    carbohydrate_g: 0.576,
    fat_g: 0.289,
  });
  assertEquals(
    portionOptions(reading.perUnit!, reading.servingSize, reading.packSize, "g"),
    golden.portion_options,
  );
  // The whole bar is twice the printed serving, not the serving the live path stored.
  const pack = golden.portion_options[1].nutrients;
  assertEquals(pack, { kcal: 195.6, protein_g: 3.1, carbohydrate_g: 21.5, fat_g: 10.8 });
});

Deno.test("golden: the Munch label is stored as the whole pack, from the label, high", () => {
  assertEquals(storedCandidates(munch()) as unknown[], [golden.stored]);
});

Deno.test("golden: the live answer's per-serving reading is kept, marked unclear and low", () => {
  const [stored] = storedCandidates(parseMealAnswer(structuredClone(golden.live_answer)));
  assertEquals(stored.source, "label_unverified");
  assertEquals(stored.confidence, "low");
  assertEquals(stored.label_issues, ["energy_mismatch"]);
  // One printed serving, scaled from its own per-gram values: the printed numbers stay.
  assertEquals(stored.serving_label, "1 serving (18.7 g)");
  assertEquals(
    [stored.calories, stored.protein_g, stored.carbohydrate_g, stored.fat_g],
    [85, 1.5, 8.7, 6.8],
  );
  assertEquals([stored.serving_size, stored.pack_size, stored.portion_size], [18.7, null, 18.7]);
});

Deno.test("a small pack for one sitting starts at the whole pack; a big one at a serving", () => {
  const perGram = { kcal: 5, protein_g: 0.1, carbohydrate_g: 0.6, fat_g: 0.25 };
  assertEquals(defaultPortion(perGram, 18.7, 37.4, 2, "g").kind, "pack");
  assertEquals(defaultPortion(perGram, 30, 200, 6.7, "g").kind, "serving");
  assertEquals(defaultPortion(perGram, 20, 80, 4, "g").kind, "serving");
  // Only a pack weight: the pack. Only a serving: the serving. Neither: 100 g.
  assertEquals(defaultPortion(perGram, null, 500, null, "g").kind, "pack");
  assertEquals(defaultPortion(perGram, 30, null, null, "g").kind, "serving");
  assertEquals(defaultPortion(perGram, null, null, null, "g"), {
    kind: "amount",
    size: 100,
    label: "100 g",
    nutrients: { kcal: 500, protein_g: 10, carbohydrate_g: 60, fat_g: 25 },
  });
  // A pack the table cannot hold (over 5,000 kcal) is skipped for the serving.
  assertEquals(defaultPortion({ ...perGram, kcal: 5.4 }, 30, 1000, 33, "g").kind, "serving");
});

Deno.test("portion labels and scaling match the app's", () => {
  assertEquals(portionLabel("serving", 18.7, "g"), "1 serving (18.7 g)");
  assertEquals(portionLabel("pack", 40, "g"), "Whole pack (40 g)");
  assertEquals(portionLabel("amount", 125.25, "g"), "125.3 g");
  assertEquals(
    scale({ kcal: 5.23, protein_g: 0.082, carbohydrate_g: 0.576, fat_g: 0.289 }, 50),
    { kcal: 261.5, protein_g: 4.1, carbohydrate_g: 28.8, fat_g: 14.5 },
  );
  // A serving that is the whole pack is offered once.
  assertEquals(
    portionOptions({ kcal: 5, protein_g: 0, carbohydrate_g: 1, fat_g: 0 }, 30, 30, "g").length,
    1,
  );
});

// Label checks that fail -----------------------------------------------------------------------

Deno.test("each failed check is named and makes the label unclear and low", () => {
  const cases: [Partial<MealAnswer>, LabelIssue[]][] = [
    [{ per_100_kcal: 400, per_serving_kcal: 75 }, ["energy_mismatch"]],
    [{
      per_serving_protein_g: 8.2,
      per_serving_carbohydrate_g: 57.6,
      per_serving_fat_g: 28.9,
      per_serving_kcal: 523,
    }, [
      "basis_mismatch",
    ]],
    [{ servings_per_pack: 3 }, ["pack_mismatch"]],
    [{ per_100_kcal: 0 }, ["energy_not_printed"]],
  ];
  for (const [overrides, issues] of cases) {
    const [stored] = storedCandidates(label(overrides));
    assertEquals(stored.label_issues, issues, JSON.stringify(overrides));
    assertEquals([stored.source, stored.confidence], ["label_unverified", "low"]);
  }
});

Deno.test("energy that is not printed is calculated from the macronutrients and said so", () => {
  const reading = readLabel(label({ per_100_kcal: 0, per_serving_kcal: 0 }));
  assertEquals(reading.issues, ["energy_not_printed"]);
  assertEquals(reading.perUnit?.kcal, 5.233);
});

Deno.test("a per-serving column without a weight is one serving, with nothing to scale", () => {
  const [stored] = storedCandidates(label({
    has_per_100: false,
    per_100_kcal: 0,
    per_100_protein_g: 0,
    per_100_carbohydrate_g: 0,
    per_100_fat_g: 0,
    serving_size: 0,
  }));
  assertEquals(stored.label_issues, ["serving_size_missing"]);
  assertEquals([stored.serving_label, stored.calories, stored.kcal_per_unit], [
    "1 serving",
    98,
    null,
  ]);
  assertEquals([stored.source, stored.confidence], ["label_unverified", "low"]);
  // Servings and net weight are still shown.
  assertEquals([stored.servings_per_pack, stored.pack_size], [2, 37.4]);
});

Deno.test("a label with no readable column falls back to the estimate, said to be one", () => {
  const [stored] = storedCandidates(label({ ...noProduct, product_name: "Munch Max Nuts" }));
  assertEquals(stored.label_issues, ["values_not_printed"]);
  assertEquals([stored.source, stored.confidence, stored.calories], ["estimate", "low", 98]);
});

Deno.test("impossible values and sizes are marked, never stored as per-gram values", () => {
  const [dense] = storedCandidates(label({ per_100_kcal: 2_300 }));
  assert(dense.label_issues.includes("values_implausible"));
  assertEquals(dense.kcal_per_unit, null);
  const [huge] = storedCandidates(label({ net_quantity: 50_000 }));
  assert(huge.label_issues.includes("values_implausible"));
  assertEquals(huge.pack_size, 37.4, "the pack weight comes from servings x serving size");
});

// Confidence from the source -------------------------------------------------------------------

Deno.test("a plate is an estimate and never high, whatever the model says", () => {
  assertEquals(atMost("high", "medium"), "medium");
  assertEquals(atMost("low", "medium"), "low");
  const stored = plateCandidate({ ...dal, confidence: "high" });
  assertEquals([stored.source, stored.image_kind, stored.confidence], [
    "estimate",
    "plate",
    "medium",
  ]);
  assertEquals([stored.kcal_per_unit, stored.portion_size, stored.label_issues], [null, null, []]);
  assertEquals(stored.assumptions, dal.assumptions);
  assertEquals(stored.question, dal.question);
  assertEquals(storedCandidates(plateAnswer([dal, { ...dal, name: "Rice" }])).length, 2);
  assertEquals(storedCandidates(plateAnswer([])), []);
});

const front = (net: number, confidence: "low" | "medium" | "high" = "high"): MealAnswer => ({
  image_kind: "pack_front",
  ...noProduct,
  product_name: "Munch Max Nuts",
  brand: "Nestlé",
  net_quantity: net,
  candidates: [{
    name: "Chocolate wafer bar",
    serving_label: "1 bar",
    calories: 195,
    protein_g: 3,
    carbohydrate_g: 22,
    fat_g: 11,
    confidence,
    assumptions: ["Estimated from similar bars, not read from a label"],
    question: "Can you photograph the nutrition table?",
  }],
});

Deno.test("a front of pack is an estimate: medium at most with a printed weight, else low", () => {
  const [weighed] = storedCandidates(front(37.4));
  assertEquals([weighed.source, weighed.confidence], ["estimate", "medium"]);
  assertEquals(weighed.name, "Nestlé Munch Max Nuts");
  assertEquals(weighed.serving_label, "Whole pack (37.4 g)");
  assertEquals([weighed.pack_size, weighed.portion_size, weighed.serving_size], [37.4, 37.4, null]);
  // Rescaled from its per-gram values, as the app will.
  assertEquals(weighed.kcal_per_unit, 5.2139);
  assertEquals(weighed.calories, 195);
  const [unweighed] = storedCandidates(front(0));
  assertEquals([unweighed.source, unweighed.confidence], ["estimate", "low"]);
  assertEquals([unweighed.kcal_per_unit, unweighed.pack_size, unweighed.serving_label], [
    null,
    null,
    "1 bar",
  ]);
  // A weight that makes the estimate impossible keeps the estimate, low, with no per-gram values.
  const [tiny] = storedCandidates(front(5));
  assertEquals([tiny.confidence, tiny.kcal_per_unit, tiny.calories], ["low", null, 195]);
  assertEquals(storedCandidates(front(37.4, "low"))[0].confidence, "low");
});

Deno.test("the product name is the printed one, with its brand; never the model's recall", () => {
  assertEquals(productName(label({ brand: "" }), "x"), "Munch Max Nuts");
  assertEquals(productName(label({ product_name: "Nestlé Munch" }), "x"), "Nestlé Munch");
  assertEquals(productName(label({ product_name: "  " }), "Chocolate bar"), "Chocolate bar");
});

Deno.test("notes are trimmed to what the table holds", () => {
  const stored = plateCandidate({
    ...dal,
    assumptions: ["  a  ", "", "x".repeat(300), ...Array(10).fill("more")],
    question: ` ${"q".repeat(600)} `,
  });
  assertEquals(stored.assumptions.length, 8);
  assertEquals(stored.assumptions[0], "a");
  assertEquals(stored.assumptions[1].length, 200);
  assertEquals(stored.question.length, 500);
});

// Labels printed per ml ----------------------------------------------------------------------------

// A 250 ml carton of flavoured milk: per 100 ml 75 kcal, P 3.2, C 10.5, F 2.2; 1 serving of 200 ml.
const milk = (): MealAnswer => ({
  image_kind: "nutrition_label",
  ...noProduct,
  quantity_unit: "ml",
  product_name: "Chocolate Milk",
  brand: "Dairyfield",
  net_quantity: 250,
  servings_per_pack: 1.25,
  serving_size: 200,
  serving_text: "200 ml",
  has_per_100: true,
  per_100_kcal: 75,
  per_100_protein_g: 3.2,
  per_100_carbohydrate_g: 10.5,
  per_100_fat_g: 2.2,
  candidates: [{ ...dal, name: "Chocolate Milk", serving_label: "200 ml" }],
});

Deno.test("a label printed per ml is never read as grams: unclear, low, ml portions only", () => {
  const [stored] = storedCandidates(milk());
  assertEquals(stored.quantity_unit, "ml");
  assertEquals(stored.label_issues, ["volume_basis"]);
  assertEquals([stored.source, stored.confidence], ["label_unverified", "low"]);
  // The printed serving in ml, from per-ml values, labelled in ml.
  assertEquals(stored.serving_label, "1 serving (200 ml)");
  assertEquals([stored.serving_size, stored.pack_size, stored.portion_size], [200, 250, 200]);
  assertEquals(stored.calories, 150);
  assertEquals(stored.kcal_per_unit, 0.75);
  const options = portionOptions(
    { kcal: 0.75, protein_g: 0.032, carbohydrate_g: 0.105, fat_g: 0.022 },
    200,
    250,
    "ml",
  );
  assertEquals(options.map((option) => option.label), [
    "1 serving (200 ml)",
    "Whole pack (250 ml)",
  ]);
  assert(!JSON.stringify(stored).includes(" g)"), "no gram label");
});

Deno.test("a per-ml label with no printed serving or pack keeps 100 ml as stored and offers nothing else", () => {
  const [stored] = storedCandidates({
    ...milk(),
    net_quantity: 0,
    serving_size: 0,
    servings_per_pack: 0,
  });
  assertEquals([stored.serving_label, stored.portion_size], ["100 ml", 100]);
  assertEquals([stored.serving_size, stored.pack_size], [null, null]);
  assertEquals(
    portionOptions({ kcal: 0.75, protein_g: 0, carbohydrate_g: 0, fat_g: 0 }, null, null, "ml"),
    [],
  );
});

Deno.test("a single-sitting pack by volume does not jump to the whole pack", () => {
  const perMl = { kcal: 0.4, protein_g: 0, carbohydrate_g: 0.1, fat_g: 0 };
  assertEquals(defaultPortion(perMl, 30, 50, 1.7, "ml").kind, "serving");
  assertEquals(defaultPortion(perMl, 30, 50, 1.7, "g").kind, "pack");
});

Deno.test("a front of pack measured in ml says ml", () => {
  const [stored] = storedCandidates({
    ...front(500),
    quantity_unit: "ml",
    candidates: [{
      ...front(500).candidates[0],
      calories: 210,
      protein_g: 0,
      carbohydrate_g: 53,
      fat_g: 0,
    }],
  });
  assertEquals([stored.quantity_unit, stored.serving_label, stored.source], [
    "ml",
    "Whole pack (500 ml)",
    "estimate",
  ]);
});
