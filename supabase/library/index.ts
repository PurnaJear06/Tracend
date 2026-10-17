import type { LibrarySource } from "../functions/_shared/library/types.ts";
import { activitySources } from "./sources/activity.ts";
import { jointFriendlySources } from "./sources/joint_friendly.ts";
import { nutritionSources } from "./sources/nutrition.ts";
import { recoverySources, screeningSources } from "./sources/recovery_screening.ts";
import { trainingSources } from "./sources/training.ts";

/** Every source in the library, in the order a migration loads them. */
export const librarySources: readonly LibrarySource[] = [
  ...trainingSources,
  ...jointFriendlySources,
  ...nutritionSources,
  ...activitySources,
  ...recoverySources,
  ...screeningSources,
];
