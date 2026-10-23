import type { LibrarySource } from "../functions/_shared/library/types.ts";
import { activitySources } from "./sources/activity.ts";
import { behaviourChangeSources } from "./sources/behaviour_change.ts";
import { bodyCompositionSources } from "./sources/body_composition.ts";
import { cardioRecoverySources } from "./sources/cardio_recovery.ts";
import { energyBalanceSources } from "./sources/energy_balance.ts";
import { exerciseSelectionSources } from "./sources/exercise_selection.ts";
import { guidelineSources } from "./sources/guidelines.ts";
import { indiaSources } from "./sources/india.ts";
import { jointFriendlySources } from "./sources/joint_friendly.ts";
import { nutritionSources } from "./sources/nutrition.ts";
import { populationSources } from "./sources/populations.ts";
import { programmingSources } from "./sources/programming.ts";
import { recoverySources, screeningSources } from "./sources/recovery_screening.ts";
import { regionalSources } from "./sources/regional.ts";
import { specialCaseSources } from "./sources/special_cases.ts";
import { supplementSources } from "./sources/supplements.ts";
import { trainingSources } from "./sources/training.ts";

/** Every source in the library, in the order a migration loads them. */
export const librarySources: readonly LibrarySource[] = [
  ...trainingSources,
  ...jointFriendlySources,
  ...nutritionSources,
  ...activitySources,
  ...recoverySources,
  ...screeningSources,
  ...energyBalanceSources,
  ...behaviourChangeSources,
  ...specialCaseSources,
  ...programmingSources,
  ...exerciseSelectionSources,
  ...bodyCompositionSources,
  ...supplementSources,
  ...cardioRecoverySources,
  ...populationSources,
  ...guidelineSources,
  ...indiaSources,
  ...regionalSources,
];
