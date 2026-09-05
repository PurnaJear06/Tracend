# Security review: working-tree changes — 2026-09-02

Scope: focused security review of the uncommitted working-tree state on `main`
(no new commits; HEAD `2458bbf`). Three changes under review: the one-line
`pubspec.lock` SDK pin (`flutter: ">=3.41.7"` → `"3.41.7"`), the new review doc
`2026-09-02-post-deploy-verification-and-findings.md`, and the untracked
session-transcript export `session-ses_fcef.md` (~957KB, repo root). Methodology:
pattern battery for embedded credential values across every secret class relevant
to this stack (Supabase service/publishable keys, Postgres connection strings,
JWTs, API keys, private-key blocks, DSNs, authorization headers, passwords),
cross-checked against the project's secret-handling rules (AGENTS.md key policy,
`.env` discipline, `RETENTION_WORKER_SECRET` never in committed files) and the
CI/hook pipeline that would catch a leak. Read-only; no files modified.

Verdict: **PASS — no vulnerabilities found**

The review bar was high-confidence (>80%), exploitable, newly-added findings
only. Nothing on this branch meets it.

## What was checked and cleared

### `pubspec.lock` (1 line)

SDK constraint pin only. Every package entry unchanged — no new dependency code
enters the build. CI (`ci.yml`, `deploy.yml`) already pins
`flutter-version: "3.41.7"` explicitly, so resolution behavior is identical.
No security relevance.

### `2026-09-02-post-deploy-verification-and-findings.md` (183 lines)

No live credential value is embedded. The service key used during the
verification session is referenced textually only ("used from a temp file and
deleted afterward; it never entered the transcript") — the scan confirmed zero
literal values for: `sb_secret_`, `sb_publishable_`, `sbp_`, JWT bodies (`eyJ`),
`postgres://`, `Bearer`, `Authorization`, `-----BEGIN` private-key blocks,
`sk-`, `apikey`, `password`. Owner production user id is explicitly masked in
the doc ("mask id in notes; fetch fresh via the REST route if needed"). Other
identifiers present are public-by-design: the Apple Team ID is already in
tracked files (`ios/Runner.xcodeproj/project.pbxproj`, `docs/PROGRESS_CONTEXT.md`),
and owner health values in review docs follow the pattern of three already-
tracked chunk review docs (single-owner app; not a new exposure class).

### `session-ses_fcef.md` (untracked, 957KB, repo root — highest-risk candidate)

This was the primary risk hypothesis: a session-transcript export sitting in a
public repo root, not gitignored, one `git add -A` away from being pushed to
`github.com/PurnaJear06/Tracend`. Exhaustive pattern battery returned **zero
live credential values**: no Supabase service/publishable keys, no Postgres
connection strings, no JWTs, no API keys (`sk-`, `ghp_`, `AKIA`, `AIza`, `xoxb`,
`github_pat_`), no private keys, no passwords, no `SENTRY_DSN`/
`RETENTION_WORKER_SECRET`, no `Authorization`/`Bearer` headers, no emails, no
hook-tampering traces (`no-verify`, `core.hooksPath` overrides). Near-misses
triaged as false positives: 89 `token` hits are all Flutter design-system color
tokens (`tracend_tokens.dart`, `accentAmber`), 36 `anon` hits are Dart
`<anonymous closure>` stack frames, 2 `sentry` hits are `pub outdated` output.
The transcript is an Aug 24 coding session (weight-trend regression work) and
contains no owner PII, health values, or Supabase project refs.

Why it is clean: the Claude Code environment redacts literal secret values
from tool calls before they enter the transcript (documented behavior — this is
the same reason the "environment redacts literal secret values typed into tool
calls" note exists in AGENTS.md). The export captured the session, not the
secrets.

## Control-gap observation (not a finding — preventive action item)

While verifying defense-in-depth, the review confirmed a real gap in the
secret-scanning pipeline, excluded from findings per review-scope rules
(hardening measure, not a concrete vulnerability — no live secret exists
today):

1. `git config core.hooksPath` → `.githooks`, which contains **only a
   `pre-push` hook** (Deno fmt/lint, Flutter analyze, migration-timestamp
   check — no secret scanning). With `core.hooksPath` set, git uses only that
   directory, so **the gitleaks hook declared in `.pre-commit-config.yaml`
   never runs anywhere** — not on commit, not on push.
2. `.git/hooks/` contains only `.sample` templates — no pre-commit hook fires.
3. No CI workflow (`ci.yml`, `deploy.yml`, `hotfix.yml`) contains a
   gitleaks/secret-scan step (grep for `gitleaks|secret.scan|trufflehog|detect-secrets`
   across `.github/workflows/` returns zero hits).

Net effect: if a future session export ever captures a redaction miss, it
ships to the public repo undetected at every stage. The project's documented
secret discipline is enforced purely by convention, not by the scanner the
repo config implies it has.

**Recommended preventive fixes** (small, contained):

- Add `session-*.md` to `.gitignore` (transcript-type artifacts clearly
  intended to stay out — `.gitignore` already excludes `.claude/`, `*.log`,
  `local-data/`).
- Wire gitleaks in for real: either drop the `core.hooksPath` override and let
  pre-commit manage `.git/hooks`, or port the gitleaks invocation into
  `.githooks/pre-push`.
- Add a gitleaks step to `ci.yml` so a leak is caught post-push as a backstop.

## Why the result is "stable" — honest context

The clean result reflects real, layered controls working, not luck:

1. **Keys never entered the client or the repo by design.** Service-role and
   provider keys live server-side only (Edge Function secrets + Vault);
   `RETENTION_WORKER_SECRET` has an explicit never-in-Flutter rule; the
   publishable key that does ship in the app binary is public-by-design.
2. **The transcript-redaction behavior** of the agent environment held — the
   one artifact that could have carried a secret out came out clean.
3. **The workflow discipline** (read keys via `.env`/CLI, temp file deleted,
   values piped not typed) was followed during the verification session.

The residual risk is the dormant scanner (observation above): the convention
layer is strong but unmonitored. Fixing the three preventive items closes that.
