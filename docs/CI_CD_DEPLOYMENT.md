# Tracend CI/CD and Release Controls

**Status:** Implemented

**Last verified design update:** 2026-11-02 (the TestFlight, rollback and nightly-backup parts are
new and unrun; the rest is as of 2026-10-15, when the deploy of `90a3b96` passed the restore drill,
including the privilege comparison that skips event trigger functions)

**Production project:** `qsfzzsjenopqqqhvpyaw` (Singapore)

## Release path

Production changes follow one path:

1. Open a pull request into `main`.
2. Pass every required CI check. Branch protection also asks for one approving review, which a
   single-account repository cannot give its own pull request, so the owner merges with the
   administrator option after checking the results. Agents never merge.
3. Merge the pull request.
4. CI runs again on the resulting `main` commit.
5. `deploy.yml` starts only after that exact `main` CI run succeeds.
6. The deploy workflow dry-runs migrations and independently backs up production by calling
   `database-backup.yml`, the one copy of the backup job that `nightly-backup.yml` also runs.
7. The backup job rejects failed or empty dumps, verifies SHA-256 checksums, and restores the
   schema and data into an isolated local Supabase database.
8. Only after the dry-run and restore drill pass may migrations deploy, followed by the Edge
   Functions one at a time.
9. Each function deploy is confirmed live against the commit, and a final job checks every function
   again (see [Live-code verification](#live-code-verification)).
10. The website (`site-deploy.yml`) is built from the same commit and published to Cloudflare
    Pages only after the functions are live. It writes the commit to `/version.txt` and waits until
    https://tracend.pages.dev serves it, so a published-but-stale site fails the run.
11. The health smoke test, the live-code check and the website check must pass before the exact
    deployed commit receives a release tag.

Until the owner sets the `CONTACT_EMAIL` repository variable, the website job fails at its
settings check, `Tag Release` is skipped, and the Deploy run is marked failed. Migrations and
functions still deploy and are verified live before that job, as on `90a3b96` (2026-10-15).
See [Required CI checks](#required-ci-checks) for the website settings.

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
- `Retire Removed Functions` runs `scripts/retire-functions.sh` after all deploys (in `deploy.yml`
  and `hotfix.yml`). A function removed from the repository stays deployed until deleted, so its
  name goes into `scripts/retired-functions.txt` in the same pull request. The job reads
  `supabase functions list` and deletes exactly the listed names that are still deployed; a name
  already gone is a no-op, and nothing outside the list is ever deleted. It refuses a listed name
  that still has a directory.
- `Verify Live Functions` runs `scripts/verify-live-function.sh --all` after the retire job, so a
  function missing from the deploy matrix also fails, and so does a deployed function that has no
  directory and is not in the retired list.

Changing an Edge secret (`supabase secrets set`) also creates a new version of every function, with
an unchanged `UPDATED_AT`:

- Change a secret that only new code accepts only after that code has passed the live-code check.
- Afterwards, from the checkout of the deployed commit, run
  `./scripts/verify-live-function.sh --all` and require every check to pass (fourteen functions since the website waitlist, 2026-10-13). Repeat after any
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
- `Migration Collision Check` (also validates release version metadata). On a pull request it
  also runs `scripts/check-migration-order.sh`: every migration the branch adds must be newer than
  the base branch's newest, named `<14-digit version>_<snake_case>.sql`, and no migration already
  on the base may be edited, renamed or deleted. `supabase db push` refuses an older version at deploy time, so an
  out-of-order branch is re-stamped before merge instead.

`Website Build` (every page of `site/` builds) also runs on every pull request; the owner can add it
to the required checks.

Website deploy settings (GitHub > Settings > Secrets and variables > Actions): secrets
`CLOUDFLARE_API_TOKEN` (Account > Cloudflare Pages > Edit) and `CLOUDFLARE_ACCOUNT_ID`, variables
`TURNSTILE_SITE_KEY` and `CONTACT_EMAIL`. The run stops with the missing names if any is unset.

CI uses the pinned versions in the workflow. Local development uses repository wrappers from
`scripts/`.

## Backup contract

The production backup contains separate role, schema, and data SQL files. The data dump uses COPY,
matching Supabase's documented logical-backup flow. A backup is valid only when:

- every expected file exists and is non-empty;
- the generated SHA-256 manifest verifies;
- schema and data restore with `ON_ERROR_STOP=1` inside the isolated database;
- the restored database contains public tables; and
- the restored privileges match the migrations (see [Restored privileges](#restored-privileges)).

The isolated database starts with every migration applied (`supabase start`), so the drill first
drops the `public` and `private` schemas that the snapshot recreates. Before 2026-10-14 it dropped
only `public`, and the first deploy after production gained `private` tables (2026-10-09) failed at
`ALTER TABLE ONLY "private"."ai_budget_limits" ADD CONSTRAINT ... PRIMARY KEY` ("multiple primary
keys"). A new schema created by a migration must be added to that reset. The recreated `public`
gets the grants the old one had; until 2026-10-15 the drill granted ALL on it to anon and
authenticated, which gave both CREATE there, and the privilege comparison flagged it.

The deploy log is public, and on an error psql prints the failing statement, which for the data
file holds production rows. Every restore psql call therefore runs through `restore_psql`: its
output goes to a temporary file that is always removed, and a failure prints only the step and the
failing `/tmp/<file>.sql:<line>`.

### Restored privileges

`supabase db dump` (CLI 2.101.0) pipes pg_dump through a `sed` that comments out every `GRANT` and
`REVOKE` line naming a schema the dump excludes (`auth`, `extensions`, `net`, `pgmq`, `storage`,
`vault`, and the rest; `./scripts/supabase.sh db dump --dry-run --db-url <any>` prints the list).
A function whose signature uses a type from such a schema therefore comes back from a restore with
default privileges, EXECUTE for PUBLIC, anon and authenticated, and the drill's table count cannot
see it. `scripts/restore-privileges.sh` closes that gap:

- the dump step records production's applied migration versions from
  `supabase migration list --linked`, because the data dump leaves out `supabase_migrations`;
- right after `supabase start` applies this commit's migrations, the drill snapshots the
  privileges;
- after the backup is stored, the last backup step snapshots the restored database and compares.
  When this commit adds migrations, it first resets the drill database to production's latest
  with `supabase db reset --last <pending>` (CLI 2.101.0 reads `--version` as its own version
  flag) and compares with that state instead. It
  fails if production's history is not a prefix of the local migrations.

A snapshot covers `public` and `private`: schema USAGE and CREATE, function EXECUTE
(`has_function_privilege`), table, view and sequence privileges for `anon` and `authenticated`,
and each table's RLS enabled and forced flags. Extension members are skipped, and so are event
trigger functions: no role can call one directly, and Supabase's "enable RLS on new tables" option
adds one (`public.rls_auto_enable()`) to the project outside the migrations (first seen
2026-10-15, deploy of `b5f8b63`). The queries read the
catalogs only, so the log names objects and never rows, as
`function private.f(p auth.users): anon EXECUTE (migrations: no, restored: yes)`. Any difference
fails the backup job, so migrations and functions do not deploy; the encrypted backup is already
stored by then. A failure means a restore of that backup needs the listed grants or flags put back
by hand, or that production has drifted from the migrations. Fix the migration (a signature that
uses a type from an excluded schema needs a `public` or `private` type instead; E1, PR #109, does
this for its function and adds a pgTAP rule against such signatures) or the drift, then rerun the
deploy.
`scripts/test-restore-privileges.sh` covers the parsing, history and report logic in CI.

Only an AES-256 encrypted archive is kept; its passphrase exists as the `BACKUP_ARCHIVE_PASSPHRASE`
Actions secret. Plaintext dumps are removed from the runner after the encrypted archive is
validated. The archive is stored in the separate **private** repository named by the `BACKUP_REPO`
Actions variable (`PurnaJear06/Tracend-backups`), never as a workflow artifact: artifacts of a
public repository can be downloaded by any signed-in GitHub user. `scripts/store-backup.sh`
pushes it with `BACKUP_REPO_DEPLOY_KEY`, a deploy key with write access to that one repository,
keeps the newest 30 backups, rewrites the branch as one orphan commit so history does not grow,
and refuses to push unless the only changes are the new file and retention pruning. Backups must
never be committed or uploaded unencrypted anywhere, and the backups repository must stay private.
`scripts/test-store-backup.sh` covers the script in CI.

### One backup workflow, run on every merge and every night

`database-backup.yml` is a reusable workflow (`workflow_call` only) holding the whole backup:
dump, integrity check, isolated restore drill, encryption (`scripts/encrypt-backup.sh`), storage
in the backups repository, and the restored-privilege comparison. `deploy.yml` calls it with the
merged commit before any migration. `nightly-backup.yml` (cron `17 19 * * *`, also
`workflow_dispatch`, `main` only) calls it, so a quiet week still has a restore point less than a
day old. The nightly workflow has its own concurrency group, `nightly-backup`: sharing
`production-deploy` would let a queued nightly replace a queued deploy. Instead the two check each
other with `gh run list`: the nightly's first job skips the night (with a notice) when `deploy.yml`
or `hotfix.yml` is running or queued, since a deploy takes its own backup, and the migration job of
each waits up to 20 minutes for a running nightly backup before it migrates, then fails before changing
production (rerun it once the backup ends), so a dump is never taken across a migration. When a nightly
run and a deploy reach the backups repository together, the loser's push is refused, so the store
steps fetch again and retry up to three times. Both workflows pass
`scripts/check-workflow-credentials.sh`: their triggers (`workflow_call`, `schedule`,
`workflow_dispatch`, and a `workflow_run` limited to `main`) are not untrusted ones.

### Progress photos are not backed up yet

Storage object bytes are outside PostgreSQL logical dumps, so the `progress-photos` bucket is in
no backup (the database backups cover Storage metadata only). A photo backup into the private
backups repository was built and dropped: its history is force-pushed but GitHub keeps old
objects, so a deleted account's photos could not be guaranteed to leave within 30 nights. The
follow-up is an encrypted photo backup (`scripts/encrypt-backup.sh`) to a store with lifecycle
deletion: Cloudflare R2 with a 30-day lifecycle rule, in a bucket and with a bucket-scoped key
that the owner creates and adds as GitHub secrets. Meal photos are deleted about 7 days after
capture and `account-exports` are short-lived, so neither needs a backup. Artifacts are not an
option: they are downloadable by any signed-in GitHub user on a public repository.

Any backup, restore-drill or restored-privilege failure stops the deployment before production
mutation.

## Version and build numbers

`pubspec.yaml` owns the semantic app version. `scripts/app-version.sh` validates it and produces the
release metadata:

- the default build number is the commit count up to the newest `origin/main` commit the checkout
  contains. On `main` that is the plain commit count; a branch with more commits than `main` takes
  `main`'s number instead of a higher one, which later `main` builds (and TestFlight uploads) would
  have to beat. Without `origin/main` (a shallow CI clone) the checkout's own commit count is used;
- `scripts/build-testflight.sh` builds only the `origin/main` tip, so every TestFlight build number
  is a first-parent commit count, which grows with every merge, and it refuses a number that is
  not higher than the last one it built (`.tooling/testflight-builds.txt`);
- CI iOS builds use the GitHub run number as the monotonic build number; and
- an intentional release can override both with `TRACEND_BUILD_NAME` and
  `TRACEND_BUILD_NUMBER` (or the equivalent `install-device.sh` flags). TestFlight builds refuse
  the override.

Examples:

```sh
./scripts/app-version.sh version
./scripts/install-device.sh --build-name 1.1.0 --build-number 200
```

## TestFlight builds

`scripts/build-testflight.sh` produces the signed App Store `.ipa` and stops before uploading:

1. It refuses a dirty tree, a `HEAD` that is not the `origin/main` tip, a manual build number, an
   empty `SUPABASE_URL` or `SUPABASE_PUBLISHABLE_KEY` in `.env` (a release build without them
   would run as a local demo) or one that is not `https://`, and a project that names more than
   one `DEVELOPMENT_TEAM`. `--check` runs these guards and builds nothing.
2. It writes `build/ios/ExportOptions.plist` (method `app-store-connect`, automatic signing, the
   team ID read from `ios/Runner.xcodeproj`) and runs `flutter build ipa` through the wrapper.
   Flutter exits 0 even when the export step fails, so the script removes the old output first and
   fails when no `.ipa` appears.
3. It unpacks the `.ipa` and runs `scripts/verify-app-bundle.sh` on the bundle inside, then checks
   the privacy manifest, the build number and version, `ITSAppUsesNonExemptEncryption`, and the
   widget extension.
4. It prints the `xcrun altool --upload-app` command. Uploading needs the owner's App Store Connect
   API key, kept outside the repository (`docs/BETA_OPERATIONS.md`).

In Dart, a release build without Supabase settings shows "This build is missing its server
settings" instead of the local demo data (`Phase2Gate`, `releaseBuild`), and sends a Sentry message
when a DSN exists. Debug and test builds keep the demo.
`scripts/test-build-testflight.sh` covers the guards and the build-number rule in CI; the signed
build itself runs only on the owner's Mac.

## Device installs

`scripts/install-device.sh` builds the signed release from its own checkout and installs it on the
owner's iPhone. Before installing, `scripts/verify-app-bundle.sh` checks that the bundle holds
`AssetManifest.bin`, `FontManifest.json`, and every font file the manifest lists, including both
icon fonts. A bundle without them still installs and launches, but draws every icon as a "?" box.
CI runs the same check on its unsigned build. It also checks the compiled asset catalog for the
app icon (any, dark and tinted) and the launch screen artwork.

iOS caches an app's launch screen. After a build changes the launch screen, the old one can keep
showing until the app is deleted from the iPhone and installed again; deleting it also removes its
local data, such as the signed-in session.

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

- Edge Function rollback uses `scripts/rollback-function.sh <function>`. It deploys from the
  previous **release tag** (`v…` from `deploy.yml`, `hf-v…` from `hotfix.yml`), not from a
  commit found through the function's folder history: on merge history that picks the pull
  request's own commit. The default target is the newest release tag whose bundle of that function
  differs from `origin/main`'s: the function's entrypoint (`index.ts`, or the entrypoint named in
  `supabase/config.toml`) followed through relative imports into `_shared` (tests excluded; JSON
  is included only when imported), `deno.json`, and the function's `[functions.<name>]` stanza of
  `supabase/config.toml`, so a config-only regression such as `verify_jwt` can be rolled back.
  Files in the folder that nothing imports (golden data, harnesses) are not part of the bundle. A release that changed only another function
  is skipped, and with no differing release the script refuses and asks for `--to`. `--to <tag>`
  picks a release, and refuses one with an identical bundle unless `--force`. `--list [function]`
  shows the recent tags and whether their code matches `origin/main`. The tag's whole `supabase/functions` tree is checked out in a temporary worktree, so
  `_shared` goes back with the function and the rest of your checkout is untouched. The function is
  deployed from there with `scripts/deploy-function.sh` (`--use-api`, 5xx retries), then
  `scripts/verify-live-function.sh` compares what is live with that tree. `--dry-run` prints the
  target and a diff summary and deploys nothing. `scripts/test-rollback-function.sh` covers the
  tag choice in CI.
- A rollback puts old code back only until the next `deploy.yml` run, which deploys `main` again.
  Revert the bad pull request on `main` straight after (a revert PR, merged by the owner).
  `hotfix.yml` is a separate manual deploy of `main`'s head and does not use this script.
- Database migrations are forward-only. Correct a bad migration with a new additive migration.
- Never edit, delete, or rewrite an applied migration.

## Repository security controls

The GitHub repository requires pull requests, one approving review, passing status checks, resolved
conversations, linear history protection against force-push/deletion, secret scanning, push
protection, and Dependabot security updates. Administrators retain emergency bypass capability so a
single-owner repository cannot be permanently deadlocked.

## Workflow supply chain (2026-10-09)

- Every `uses:` is pinned to a full commit SHA with the release in a comment
  (`actions/checkout@<sha> # v5.1.0`). Dependabot's `github-actions` entry proposes new pins.
- Each workflow's default token is read-only (`permissions: contents: read`). Only the
  `tag-release` jobs, which push the release tag, get `contents: write`, and they are the only
  checkouts that keep credentials (`persist-credentials: false` everywhere else).
- No event a stranger can influence starts a job with a repository secret (2026-10-31). A pull
  request runs the branch's own code, so a workflow that any `pull_request*` event (including
  `pull_request_target`, `pull_request_review` and its comments), `issues`, `issue_comment`,
  `discussion`, `discussion_comment`, `fork`, `watch`, `gollum` or `workflow_run` triggers may not mention `secrets` anywhere (the raw file, comments included) except the exact
  token `secrets.GITHUB_TOKEN`, and may not call a local reusable workflow. The one allowed
  `workflow_run` is the one limited to `branches: [main]` (`deploy.yml`). The trigger is read with
  `yq`, which GitHub's ubuntu runners have; `scripts/check-workflow-credentials.sh` enforces it in
  the `Deno` job of `ci.yml`, its fixtures are in `scripts/test-check-workflow-credentials.sh`, and
  `pre-deploy.sh` runs both when `yq` is installed (`brew install yq`) and warns when it is not.
  The live AI evaluations (`coach-eval.yml`, `onboarding-eval.yml`) are `workflow_dispatch` only:
  Actions, pick the workflow, Run workflow on the branch to evaluate (a pull request's branch before
  it merges). Starting a run needs write access, so only the owner can; a fork's pull request never
  receives secrets. They no longer start from a pull request label. The library retrieval evaluation
  (`library-eval.yml`) holds no secret and still runs on library pull requests.
- Jobs that use production secrets run in the `production` environment, and a hotfix runs only
  from `main`. Once the secrets move into that environment, a workflow on another branch cannot
  read them.

