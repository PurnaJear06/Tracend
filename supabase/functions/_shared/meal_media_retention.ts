import { isSafeStorageKey } from "./storage_keys.ts";

export type RetentionCandidate = Readonly<{
  media_object_id: string;
  object_key: string;
}>;

export type RetentionDependencies = Readonly<{
  claim: (batchSize: number) => Promise<readonly RetentionCandidate[]>;
  remove: (objectKey: string) => Promise<boolean>;
  complete: (mediaObjectId: string, succeeded: boolean) => Promise<void>;
}>;

export type RetentionResult = Readonly<{
  claimed: number;
  deleted: number;
  failed: number;
  unsafe: number;
  // Rows whose result could not be written back. They stay claimed until the database hands them out
  // again after the claim goes stale.
  unfinalized: number;
}>;

export async function cleanExpiredMealMedia(
  dependencies: RetentionDependencies,
  batchSize = 50,
): Promise<RetentionResult> {
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > 100) {
    throw new Error("invalid_batch_size");
  }

  const candidates = await dependencies.claim(batchSize);
  let deleted = 0;
  let failed = 0;
  let unsafe = 0;
  let unfinalized = 0;

  for (const candidate of candidates) {
    let succeeded = false;
    // An unsafe key is never sent to Storage; it stays failed for review.
    if (!isSafeStorageKey(candidate.object_key)) {
      unsafe += 1;
    } else {
      try {
        succeeded = await dependencies.remove(candidate.object_key);
      } catch {
        succeeded = false;
      }
    }

    // One row's failed write-back must not strand the rest of the batch in pending_deletion.
    try {
      await dependencies.complete(candidate.media_object_id, succeeded);
    } catch {
      unfinalized += 1;
    }
    if (succeeded) {
      deleted += 1;
    } else {
      failed += 1;
    }
  }

  return { claimed: candidates.length, deleted, failed, unsafe, unfinalized };
}

export type OrphanObject = Readonly<{ bucket_id: string; name: string }>;

export type OrphanSweepDependencies = Readonly<{
  list: (batchSize: number) => Promise<readonly OrphanObject[]>;
  remove: (bucket: string, name: string) => Promise<boolean>;
}>;

export type OrphanSweepResult = Readonly<{
  listed: number;
  removed: number;
  failed: number;
  unsafe: number;
}>;

const sweptBuckets = new Set(["meal-images", "progress-photos", "account-exports"]);

// Removes Storage objects that have no database row (an upload whose RPC never
// ran, or an export that never completed). A name that is not a safe key is
// never sent to Storage; it is counted for review instead.
export async function sweepOrphanObjects(
  dependencies: OrphanSweepDependencies,
  batchSize = 100,
): Promise<OrphanSweepResult> {
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > 500) {
    throw new Error("invalid_batch_size");
  }
  const objects = await dependencies.list(batchSize);
  let removed = 0;
  let failed = 0;
  let unsafe = 0;
  for (const object of objects) {
    if (!sweptBuckets.has(object.bucket_id) || !isSafeStorageKey(object.name)) {
      unsafe += 1;
      continue;
    }
    let succeeded = false;
    try {
      succeeded = await dependencies.remove(object.bucket_id, object.name);
    } catch {
      succeeded = false;
    }
    if (succeeded) removed += 1;
    else failed += 1;
  }
  return { listed: objects.length, removed, failed, unsafe };
}

export type FailureReporter = (message: string, failureCode: string) => void;

// What a retention run reports to Sentry: codes and counts only, never a key, path or URL.
export function reportRetentionOutcome(
  outcome: Readonly<{
    meals: RetentionResult | null;
    orphans: OrphanSweepResult | null;
    exportFailures: number;
    exportUnfinalized: number;
  }>,
  report: FailureReporter,
): void {
  const { meals, orphans } = outcome;
  if (meals && meals.unsafe > 0) {
    report(`meal_media_unsafe_keys_${meals.unsafe}`, "unsafe_storage_key");
  }
  if (meals && meals.failed - meals.unsafe > 0) {
    report(`meal_media_removal_failed_${meals.failed - meals.unsafe}`, "storage_removal_failed");
  }
  if (meals && meals.unfinalized > 0) {
    report(`meal_media_unfinalized_${meals.unfinalized}`, "retention_completion_failed");
  }
  if (outcome.exportFailures > 0) {
    report(`export_removal_failed_${outcome.exportFailures}`, "storage_removal_failed");
  }
  if (outcome.exportUnfinalized > 0) {
    report(`export_unfinalized_${outcome.exportUnfinalized}`, "retention_completion_failed");
  }
  if (orphans && orphans.unsafe > 0) {
    report(`orphan_unsafe_keys_${orphans.unsafe}`, "unsafe_storage_key");
  }
  if (orphans && orphans.failed > 0) {
    report(`orphan_removal_failed_${orphans.failed}`, "storage_removal_failed");
  }
}

export type RetentionStage = readonly [name: string, run: () => Promise<unknown>];

// Runs each stage on its own, so a stage that throws (a claim that errors, a Storage outage) does not
// stop the stages after it. A failure is reported by stage name and error code only.
export async function runRetentionStages(
  stages: readonly RetentionStage[],
  report: FailureReporter,
): Promise<{ results: Record<string, unknown>; failedStages: string[] }> {
  const results: Record<string, unknown> = {};
  const failedStages: string[] = [];
  for (const [name, run] of stages) {
    try {
      results[name] = await run();
    } catch (error) {
      failedStages.push(name);
      const code = error instanceof Error && /^[a-z0-9_]{1,64}$/.test(error.message)
        ? error.message
        : "unknown";
      report(`retention_stage_failed_${name}_${code}`, "retention_stage_failed");
    }
  }
  return { results, failedStages };
}
