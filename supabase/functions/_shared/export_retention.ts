export type ExportRetentionCandidate = Readonly<{ storage_path: string }>;

export type ExportRetentionDependencies = Readonly<{
  claim: () => Promise<readonly ExportRetentionCandidate[]>;
  remove: (storagePath: string) => Promise<boolean>;
  complete: (storagePath: string, succeeded: boolean) => Promise<void>;
}>;

export async function cleanExpiredExports(dependencies: ExportRetentionDependencies) {
  const candidates = await dependencies.claim();
  let deleted = 0;
  let failed = 0;
  for (const candidate of candidates) {
    let succeeded = false;
    try {
      succeeded = await dependencies.remove(candidate.storage_path);
    } catch {
      succeeded = false;
    }
    await dependencies.complete(candidate.storage_path, succeeded);
    if (succeeded) deleted += 1;
    else failed += 1;
  }
  return { claimed: candidates.length, deleted, failed };
}
