# Coach Decision Persistence — Evidence Whitelist Fix

## Context (read-only investigation findings)

User reported after today's deploy:
1. Today sync shows **"Synced, but unavailable: coach decision."**
2. Recovery shows **62** with many missing records (user did not wear watch while sleeping).

### Finding 1 — Recovery 62 + missing records: WORKING AS DESIGNED, no fix
- Chunk 7 recovery honesty (deployed today) does exactly this: watch not worn →
  no sleep/HRV/RHR/respiratory-rate data → the 4 health components are listed as
  missing instead of fabricated; recovery computed from training strain alone → 62;
  `data_confidence=low`. Pre-deploy this same day would have shown a fabricated 69.
- Wearing the watch while sleeping populates the components. No code change.

### Finding 2 — Coach decision unavailable: layered bug, Layer 2 newly discovered
- **Layer 1 (FIXED + DEPLOYED TODAY):** persist RPC provider whitelist lacked
  `deepseek` → 'invalid provider metadata'. Migration 20260825000000 fixed it.
- **Layer 2 (NEW, UNFIXED — deterministic):** evidence-code whitelist mismatch.
  - `prepare_daily_coaching` (20260726000000) permits up to 17 evidence codes
    (APPROVED_PLAN_ACTIVE, HEALTH_CONTEXT_AVAILABLE, CHECK_IN_SAFETY_ESCALATION,
    RECOVERY_WITHIN_BASELINE, RECOVERY_BELOW_BASELINE, CHECK_IN_RECOVERY_MIXED,
    SLEEP_QUALITY_GOOD/POOR, TRAINING_LOAD_OPTIMAL/ELEVATED,
    WEIGHT_TRENDING_DOWN/UP, WEIGHT_STABLE, NUTRITION_ON_TRACK/BEHIND,
    DATA_CONFIDENCE_HIGH/LOW).
  - The DeepSeek prompt teaches the model all of these codes and passes the
    permitted list; `parseCoachDecision` validates against the full permitted list.
  - BUT `persist_daily_coaching_result_v2` hardcodes a narrow whitelist:
    maintain_only → only APPROVED_PLAN_ACTIVE, RECOVERY_WITHIN_BASELINE,
    CHECK_IN_RECOVERY_MIXED, HEALTH_CONTEXT_AVAILABLE; request_data → 2 codes;
    escalate → 3 codes. Any other cited code → 'unsupported evidence' → 422
    `decision_rejected` → Flutter shows "coach decision" unavailable.
  - Today's state makes rejection near-certain: check-in exists (pain=1 →
    maintain_only), health row exists (steps only), recovery 62, confidence LOW →
    permitted_evidence includes DATA_CONFIDENCE_LOW (+ likely TRAINING_LOAD_*,
    WEIGHT_*), and the model is instructed to use those codes.
  - The 422 path has NO failure telemetry (persist_failed_coaching_run_v2 only
    called on exceptions) → silent rejections.
- **Layer 3 (probabilistic):** DeepSeek decision JSON occasionally fails strict
  contract parsing / API call (yesterday's 15.4s failed run; Jul 20 gemini 20.3s).
  Cannot be eliminated; becomes visible once Layer 2 telemetry gap is closed.

### Evidence from production backup (2026-08-26T07:48Z, pre-migration)
- `model_runs`: 88 rows; daily_coaching = 2 runs, BOTH FAILED, zero successes ever.
  - 2026-07-20 gemini failed (provider_or_validation_failed, 20.3s)
  - 2026-08-25 "mock" failed (15.4s) — actually DeepSeek mislabeled (telemetry fix
    23c0330 landed after this run).
- `coach_decisions`: only 5 rows, all from 2026-07-02..07-19 (early mock era),
  all with empty or trivially-whitelisted evidence. Nothing persisted since.
- `coach_chat` with deepseek: consistently succeeding (Jul 22–Aug 25) → DeepSeek
  key/connectivity are fine; the decision contract path is what fails.
- Today's inputs: check-in 2026-08-26 (pain=1, available=true), health summary
  2026-08-26 (steps=66, everything else NULL — watch not worn at night).
- Live probes: health-check 200 (DB connected), coach-decide 401 without auth →
  deployed functions are up.

## Goal
Make daily coach decisions persist reliably for live DeepSeek runs.

## Non-goals
- No changes to recovery honesty behavior (it is correct).
- No provider/model changes; DeepSeek V4 Flash stays.
- No persist RPC signature change (keep additive CREATE OR REPLACE).

## Steps

### 1. Additive migration: widen persist evidence whitelist
New file `supabase/migrations/20260826120000_sync_persist_evidence_whitelist.sql`:
- `CREATE OR REPLACE public.persist_daily_coaching_result_v2(...)` — identical
  signature and all existing validations (policy lookup, provider metadata,
  payload shape), but the evidence whitelist accepts the full 17-code set that
  `prepare_daily_coaching` can permit, for every policy outcome:
  APPROVED_PLAN_ACTIVE, CHECK_IN_SAFETY_ESCALATION, HEALTH_CONTEXT_AVAILABLE,
  RECOVERY_WITHIN_BASELINE, RECOVERY_BELOW_BASELINE, CHECK_IN_RECOVERY_MIXED,
  SLEEP_QUALITY_GOOD, SLEEP_QUALITY_POOR, TRAINING_LOAD_OPTIMAL,
  TRAINING_LOAD_ELEVATED, WEIGHT_TRENDING_DOWN, WEIGHT_TRENDING_UP,
  WEIGHT_STABLE, NUTRITION_ON_TRACK, NUTRITION_BEHIND, DATA_CONFIDENCE_HIGH,
  DATA_CONFIDENCE_LOW.
- Rationale: prepare controls which codes are permitted per day;
  parseCoachDecision enforces that per run; persist remains the backstop against
  fabricated codes, so it must accept the full known code universe.
- Forward-only, additive, safe for deployed app + functions (no signature change).
- Apply locally via repo wrapper (delete local schema_migrations row if re-applying).

### 2. coach-decide: close telemetry gap on decision_rejected
`supabase/functions/coach-decide/index.ts`:
- When `persist_daily_coaching_result_v2` returns error (422 path), call
  `persist_failed_coaching_run_v2` with sanitized error_code derived from the
  PostgREST error message (e.g. 'decision_rejected_unsupported_evidence',
  'decision_rejected_invalid_decision', fallback 'decision_rejected'; ≤80 chars),
  provider/model from the generated run (not env re-read).
- Keep response shape unchanged (422 decision_rejected).

### 3. pgTAP coverage
New `supabase/tests/database/coach_decision_persist_whitelist_test.sql`:
- Persist accepts a decision citing each of the 17 codes (maintain_only policy).
- Persist still rejects a fabricated code (e.g. 'NOT_A_REAL_CODE').
- Persist still rejects invalid provider metadata / malformed payload.
- Run via scripts/test-db.sh (recovery_honesty 33/33 + phase2 72/72 stay green).

### 4. Docs same-change
- `docs/handoff/backend.md`: Layer 2 root cause, fix, deferred Layer 3 note.
- `docs/ALGORITHMS.md` coaching section: persist whitelist = full code set.
- `docs/PROGRESS_CONTEXT.md` + plan tracker.

### 5. Gates + commit + deploy
- `./scripts/flutter.sh format/analyze/test` (no Flutter changes expected)
- `./scripts/deno.sh fmt --check` + `lint`
- pgTAP suites
- Commit on `feature/feature-engine-phase-5-v2`, ff-merge into
  `feature/feature-engine`; user pushes feature/feature-engine → deploy.yml runs
  (dry-run → backup → migrate → functions → smoke → tag).

## Verification (post-deploy)
1. User taps sync on Today → expect "Everything is up to date."
2. Today's decision card appears (dated today, DeepSeek provider).
3. Next backup or AI-usage screen shows a `succeeded` daily_coaching model_run
   with provider=deepseek.
4. If it still fails, the new telemetry records WHY (failed model_run row with
   sanitized error code) → Layer 3 becomes diagnosable.

## Deferred / known issues (not this fix)
- Layer 3: DeepSeek occasionally produces contract-invalid JSON → 503. Mitigation
  later if telemetry shows it's frequent (retry-once or stricter prompt).
- `git push origin main` still pending (user action) to sync origin/main with
  deployed code.
- Recovery honesty deferred follow-ups (ACWR doc mismatch, imputation, rolling
  baselines) remain in docs/handoff/backend.md.
