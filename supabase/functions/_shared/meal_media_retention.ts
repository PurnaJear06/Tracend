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
