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

    await dependencies.complete(candidate.media_object_id, succeeded);
    if (succeeded) {
      deleted += 1;
    } else {
      failed += 1;
    }
  }

  return { claimed: candidates.length, deleted, failed, unsafe };
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
