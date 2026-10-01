# Tracend CI/CD and Release Controls

**Status:** Implemented

**Last verified design update:** 2026-09-29

**Production project:** `qsfzzsjenopqqqhvpyaw` (Singapore)

## Release path

Production changes follow one path:

1. Open a pull request into `main`.
2. Obtain the required review and pass every required CI check.
3. Merge the pull request.
4. CI runs again on the resulting `main` commit.
5. `deploy.yml` starts only after that exact `main` CI run succeeds.
6. The deploy workflow dry-runs migrations and independently backs up production.
7. The backup job rejects failed or empty dumps, verifies SHA-256 checksums, and restores the
   schema and data into an isolated local Supabase database.
8. Only after the dry-run and restore drill pass may migrations deploy, followed by the ten Edge
   Functions one at a time.
9. Each function deploy is confirmed live against the commit, and a final job checks every function
   again (see [Live-code verification](#live-code-verification)).
10. The health smoke test and the live-code check must pass before the exact deployed commit
    receives a release tag.

The deploy concurrency group is `production-deploy` with cancellation disabled. Deployments queue;
they do not interrupt one another.

## Live-code verification

A successful `supabase functions deploy` does not prove that the new code is live.

- On 2026-09-28, the deploy of PR #36 reported success for all nine functions, deployed in
  parallel. Supabase kept the previous version of four of them, including `coach-chat` and
  `coach-decide`.
- An Edge secret that only the new code accepted then turned the Coach off (FLUTTER-9).
- A redeploy later that day dropped one more function.

The pipeline now guards against this:

- Functions deploy one at a time (`max-parallel: 1`).
- Each deploy runs through `scripts/deploy-function.sh`. Supabase's deploy service sometimes
  answers `unexpected deploy status 500` ("Function deploy failed due to an internal error"). On
  2026-09-29 `coach-chat` and `health-sync` failed this way twice and passed on a third manual
  rerun. The script retries a 5xx answer up to three times, waiting 30 s and then 60 s. Any other
  error (bundling, token) fails at once.
- `scripts/verify-live-function.sh <function>` downloads the deployed source (read-only) and
  compares its files byte for byte with the commit. It retries while a new version propagates.
- If a function is not live after its deploy, the job deploys it once more. If it is still not live,
  the job fails and the release is not tagged.
- `Verify Live Functions` runs `scripts/verify-live-function.sh --all` after all deploys, so a
  function missing from the deploy matrix also fails.

Changing an Edge secret (`supabase secrets set`) also creates a new version of every function, with
an unchanged `UPDATED_AT`:

- Change a secret that only new code accepts only after that code has passed the live-code check.
- Afterwards, from the checkout of the deployed commit, run
  `./scripts/verify-live-function.sh --all` and require every check to pass (ten functions since 2026-10). Repeat after any
  later secret change. `UPDATED_AT` alone cannot prove the source stayed live.

## Required CI checks

Branch protection requires these pull-request checks:

- `Deno (fmt + lint + test)`
- `Flutter Analyze` (includes Dart formatting)
- `Flutter Test`
- `Flutter iOS Build (macOS)` (also checks the app bundle's assets; see
  [Device installs](#device-installs))
- `pgTAP (fresh DB + migrations + parity)`
- `Secret Scan (gitleaks)`
- `Migration Collision Check` (also validates release version metadata)

CI uses the pinned versions in the workflow. Local development uses repository wrappers from
`scripts/`.

## Backup contract

The production backup contains separate role, schema, and data SQL files. The data dump uses COPY,
matching Supabase's documented logical-backup flow. A backup is valid only when:

- every expected file exists and is non-empty;
- the generated SHA-256 manifest verifies;
- schema and data restore with `ON_ERROR_STOP=1` inside the isolated database; and
- the restored database contains public tables.

Only an AES-256 encrypted archive is kept; its passphrase exists as the `BACKUP_ARCHIVE_PASSPHRASE`
Actions secret. Plaintext dumps are removed from the runner after the encrypted archive is
validated. The archive is stored in the separate **private** repository named by the `BACKUP_REPO`
Actions variable (`PurnaJear06/Tracend-backups`), never as a workflow artifact: artifacts of a
public repository can be downloaded by any signed-in GitHub user. `scripts/store-backup.sh`
pushes it with `BACKUP_REPO_DEPLOY_KEY`, a deploy key with write access to that one repository,
keeps the newest 30 backups, rewrites the branch as one orphan commit so history does not grow,
and refuses to push unless the only changes are the new file and retention pruning. Backups must
never be committed or uploaded unencrypted anywhere, and the backups repository must stay private.
`scripts/test-store-backup.sh` covers the script in CI. Storage object bytes are outside PostgreSQL logical dumps and require their own
recovery process; database backups cover Storage metadata only.

Any backup or restore-drill failure stops the deployment before production mutation.

## Version and build numbers

`pubspec.yaml` owns the semantic app version. `scripts/app-version.sh` validates it and produces the
release metadata:

- local/device builds default to the semantic version plus the Git commit count;
- CI iOS builds use the GitHub run number as the monotonic build number; and
- an intentional release can override both with `TRACEND_BUILD_NAME` and
  `TRACEND_BUILD_NUMBER` (or the equivalent `install-device.sh` flags).

Examples:

```sh
./scripts/app-version.sh version
./scripts/install-device.sh --build-name 1.1.0 --build-number 200
```

## Device installs

`scripts/install-device.sh` builds the signed release from its own checkout and installs it on the
owner's iPhone. Before installing, `scripts/verify-app-bundle.sh` checks that the bundle holds
`AssetManifest.bin`, `FontManifest.json`, and every font file the manifest lists, including both
icon fonts. A bundle without them still installs and launches, but draws every icon as a "?" box.
CI runs the same check on its unsigned build.

On 2026-09-29, build 185 reached the iPhone without any of its assets:

- Every checkout built into one `build/` directory: the primary checkout, and each agent worktree
  whose `.tooling` links to it.
- When the build configuration changes, Flutter deletes the previous build's outputs by the paths
  that build recorded. The previous build had run in a Codex worktree, so those paths reached the
  files the new build had just written.

`scripts/flutter.sh` now keeps each worktree's `.dart_tool/`, `build/`, and `ios/Flutter/ephemeral`
in `.tooling/checkouts/<name>-<id>/`. The SDK, the dependency caches, and `ios/Pods` stay shared.
CocoaPods writes the real location of the Pods directory into the tracked Xcode project, so a
per-checkout copy would rewrite the project in every worktree. Flutter reinstalls pods whenever a
checkout's `Podfile.lock` differs from the shared one.

## Emergency path

`hotfix.yml` is a manual emergency tool, not the normal release path. Its use requires explicit
owner authorization, a recorded reason, and post-incident reconciliation through a reviewed PR. It
deploys and verifies functions exactly like `deploy.yml` and tags the commit `hf-v…`.
Agents must not deploy manually unless GitHub Actions is unavailable or the owner explicitly asks.

## Rollback

- Edge Function rollback uses `scripts/rollback-function.sh <function>`.
- Database migrations are forward-only. Correct a bad migration with a new additive migration.
- Never edit, delete, or rewrite an applied migration.

## Repository security controls

The GitHub repository requires pull requests, one approving review, passing status checks, resolved
conversations, linear history protection against force-push/deletion, secret scanning, push
protection, and Dependabot security updates. Administrators retain emergency bypass capability so a
single-owner repository cannot be permanently deadlocked.
