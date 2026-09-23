# Tracend CI/CD and Release Controls

**Status:** Implemented

**Last verified design update:** 2026-09-23

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
8. Only after the dry-run and restore drill pass may migrations and the nine Edge Functions deploy.
9. The health smoke test must pass before the exact deployed commit receives a release tag.

The deploy concurrency group is `production-deploy` with cancellation disabled. Deployments queue;
they do not interrupt one another.

## Required CI checks

Branch protection requires these pull-request checks:

- `Deno (fmt + lint + test)`
- `Flutter Analyze` (includes Dart formatting)
- `Flutter Test`
- `Flutter iOS Build (macOS)`
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

Only an AES-256 encrypted GitHub Actions artifact is retained for 14 days; its passphrase exists as
the `BACKUP_ARCHIVE_PASSPHRASE` Actions secret. Plaintext dumps are removed from the runner after
the encrypted archive is validated. Backups must never be committed or uploaded unencrypted to this
public repository. Storage object bytes are outside PostgreSQL logical dumps and require their own
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

## Emergency path

`hotfix.yml` is a manual emergency tool, not the normal release path. Its use requires explicit
owner authorization, a recorded reason, and post-incident reconciliation through a reviewed PR.
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
