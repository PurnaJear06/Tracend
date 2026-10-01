// Shared fixtures for the onboarding plan tests.
import type { OnboardingAnswers } from "./answers.ts";
import { type EquipmentItem, exerciseCatalogV1 } from "./catalog.ts";
import type { PlanPolicies } from "./plan_contract.ts";
import { nutritionPolicy, trainingPolicy } from "./policy.ts";

export const equipmentSets: Record<string, EquipmentItem[]> = {
  bodyweight: [],
  dumbbells: ["dumbbells"],
  home: ["dumbbells", "bench", "pull_up_bar", "bands"],
  gym: ["dumbbells", "barbell", "bench", "cables", "machines", "pull_up_bar", "kettlebells"],
};

export const weekdaysFor: Record<number, number[]> = {
  1: [3],
  2: [2, 5],
  3: [1, 3, 5],
  4: [1, 2, 4, 5],
  5: [1, 2, 3, 5, 6],
  6: [1, 2, 3, 4, 5, 6],
};

export function answersFor(overrides: Partial<OnboardingAnswers> = {}): OnboardingAnswers {
  return {
    path: "beginner",
    experience: "beginner",
    goal: "recomposition",
    sex: "male",
    birthYear: 1994,
    age: 32,
    heightCm: 176,
    weightKg: 78,
    targetWeightKg: null,
    dailyActivity: "mostly_sitting",
    trainingWeekdays: [1, 3, 5],
    sessionMinutes: 60,
    equipment: equipmentSets.gym,
    equipmentNote: "",
    nutritionContext: "",
    limitations: "",
    currentPlan: "",
    revisionNote: "",
    ...overrides,
  };
}

export function policiesFor(answers: OnboardingAnswers): PlanPolicies {
  return {
    answers,
    nutrition: nutritionPolicy(answers),
    training: trainingPolicy(answers),
    catalog: exerciseCatalogV1,
  };
}
