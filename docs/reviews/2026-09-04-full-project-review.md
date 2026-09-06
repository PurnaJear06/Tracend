# Full project review: noop cross-verification + market landscape — 2026-09-04

**Scope:** owner-requested complete project review. Three questions: (1) did anything get
missed or done wrong in the port of the noop (github.com/ryanbr/noop, the WHOOP-companion
reference Tracend's algorithm rigor derives from); (2) what should be fixed or improved;
(3) how does the product compare against the 2026 market of comparable apps.

**Method:** read-only. No code changed, no data modified beyond a temporary shallow clone of
noop under `.tooling/review/` (deleted after analysis). Inputs: full Tracend docs pass
(PROGRESS_CONTEXT, all handoffs, PRD, ALGORITHMS, AI_SAFETY_SPEC, prior reviews), first-hand
read of noop's `docs/ANALYTICS.md` + `CLAUDE.md`, three parallel deep-dives (noop algorithm
inventory from Swift sources, Tracend implementation audit with file:line evidence, market
research over primary sources), plus local gate verification run in this session.

**Local gates verified in this session (not trusted from docs):** `flutter analyze` — 0
issues; `flutter test` — **344/344 pass** on the uncommitted working tree. CI/Deploy all
green (last deploy 2026-08-26).

## Verdict

The noop port is faithful where it counts and deliberately better in one respect. The
remaining gaps are mostly *process rigor* (spread tracking, staleness, null semantics, a
reference implementation), not the core math. Three real bugs are open (one new from this
review), one dormant security control, and a handful of doc/governance debts. The market
research confirms the positioning is genuinely differentiated and yields concrete patterns
worth adopting.

## What was done right (verified)

- **Formula family correctly ported.** Recovery composite weights (HRV 0.55 / RHR 0.20 /
  sleep 0.15 / resp 0.05), weight-renormalization over joined components only, logistic
  slope k=1.6, Winsorized EWMA baselines with the early-life anti-anchoring schedule
  (half-life 3d for observations ≤8, then 14d), cold-start NULL gating, and
  `recovery_breakdown.missing_components` all match noop's RecoveryScorer/Baselines design.
- **Deliberate divergences are sound.** (a) Tracend anchors z=0 → exactly 50; noop anchors
  ~58 to match WHOOP's published population mean — Tracend's choice is *more* honest for the
  "no fabricated numbers" positioning. (b) noop's skin-temp driver (0.05) was replaced by
  prev_strain (0.05) because HealthKit exposes no skin temperature — the right adaptation.
- **Test discipline mirrors noop's best pattern.** pgTAP `recovery_honesty_test.sql`
  reproduces the owner's exact production day (old formula → 69, honest → 62) — the same
  synthetic user-reported-bug reproduction technique noop uses (their test headers cite
  issue numbers and reporter field values).
- **Coach-decide diagnosability verified in production.** 7.1 evidence-whitelist sync +
  7.2 DeepSeek thinking-mode disable + `error_code='decision_rejected'` failed-run telemetry:
  every `daily_coaching` run since 2026-08-26 has succeeded (per 2026-09-02 verification).
- **Security posture held.** 2026-09-02 working-tree security review: PASS, no live
  credentials anywhere.

## Findings

### P0 — real bugs / broken promises

1. **[NEW] Respiratory rate is dead code — and it silently caps the confidence tier.**
   The pipeline computes a resp-rate baseline and 0.05-weight z-score server-side and the
   Today screen renders a "Resp" driver row, but no HealthKit read for respiratory rate
   exists anywhere: `lib/features/health/health_data_source.dart:31-41` requests no
   respiratory type, and `supabase/functions/_shared/contracts/health_sync_v1.ts` has no
   `resp` type — the DB column `respiratory_rate_bpm` can never receive data from the
   shipped sync path. Consequences: the "Resp" driver row shows "No data" every day forever;
   `data_confidence` requires all four HealthKit components present for `high`
   (`20260825120000` compute_daily_metrics), so **confidence can never exceed `medium`**;
   and the `DATA_CONFIDENCE_HIGH` evidence code taught to the DeepSeek prompt can never
   fire. noop treats respiration as a live core signal (per-metric floorSpread 0.5, 8–25
   bpm plausibility band). Apple Watch records respiratory rate nightly during sleep, so
   the signal is available — the fix is one read type + contract type + present_types
   plumbing (plus the sync insert path). Alternatively drop the component and fix the
   confidence ceiling; adding it is the better product call.
2. **Check-in offline fallback is a dead letter** (known since 2026-09-02, still open).
   `lib/features/today/check_in_sheet.dart:39,58` writes
   `daily_check_in_pending` to SharedPreferences on RPC failure and shows "will need a
   connection to sync" — but nothing in the repo ever reads the key back. Failed check-ins
   are silently lost and the snackbar's promise is false. The save is also a single
   un-retried RPC call (health-sync retries 3×). Fix: replay queue on app start / brief
   reload. This is plausibly the root of the owner's "check-in not updating" experience
   during the Aug 26–Sep 2 off week.
3. **Future-dated `daily_computed_metrics` rows** (known since 2026-09-02, still open).
   `compute_daily_metrics` has no `target_date > current_date` guard
   (`20260825120000:443`); selecting future weekday pills on Train drives
   `get_my_daily_brief(target_date=…)` which upserts rows for future dates AND calls
   `compute_user_baselines(target_user_id, target_date)` anchoring baselines to future
   dates. Production evidence: rows for 2026-09-03..09-06 written 2026-09-02. Fix: skip the
   side-effect upsert (and baseline fold) when target_date > current_date.
4. **Secret scanning still dormant** (known since 2026-09-02, still open). `core.hooksPath`
   → `.githooks` (Deno fmt/lint, Flutter analyze, migration-timestamp check only) bypasses
   the gitleaks pre-commit declared in `.pre-commit-config.yaml`; no gitleaks step exists in
   ci.yml/deploy.yml/hotfix.yml; `session-*.md` is not in `.gitignore`; a ~957KB transcript
   export sits untracked in the repo root — one `git add -A` from a public push. Three
   small preventive fixes from the security review: gitignore the pattern, port gitleaks
   into `.githooks/pre-push`, add a CI backstop step.

### P1 — hygiene / governance debt

5. **Nine days of owner-approved work sits uncommitted on `main`.** The Train week-rail
   redesign, Account flow redesign, and TrajectoryTrend day-columns (~1,070 insertions,
   incl. `week_rail_card.dart` ~1,087 lines + 36 tests, `exercise_list_card.dart`), the
   `.agents/skills` deletions, `pubspec.lock` SDK pin, and the 2026-09-02 review docs.
   Verified committable this session: 344/344 tests, 0 analyze issues.
   Also `Claude.md` (untracked, repo root): byte-identical duplicate of tracked `AGENTS.md`
   that loads as `CLAUDE.md` only via macOS case-insensitivity. Either commit it as the
   intentional `CLAUDE.md` (correct case) or delete it — as-is it is invisible to git and
   would confuse a case-sensitive clone (Linux CI).
6. **PRD §5.8 provider drift — authority-doc conflict.** PRD §5.8 still names
   `gemini-3.5-flash` as the live coach and Groq Qwen as the owner-test route; AI_SAFETY_SPEC
   §10, COST_MODEL, and ARCHITECTURE all correctly record DeepSeek V4 Flash as active since
   2026-07-26. PRD needs the same update (Gemini/Qwen explicitly marked prior/superseded).
7. **No ADR records the DeepSeek activation.** The roadmap records "DeepSeek was rejected
   for restricted data after official privacy review" (2026-07-04 entry), then DeepSeek
   became the active production provider on 2026-07-26 with no decision record reversing
   the rejection. Write ADR 0011 (provider selection, the restricted-data reconsideration,
   and the all-or-nothing secret gate).
8. **ACWR is a three-way mismatch.** `docs/ALGORITHMS.md` §4 says ACWR is null with <7
   days of strain history; the SQL (`20260825120000:310-339`) guards only `avg28 != 0` — a
   single strain day reports ACWR 1.0; the new Train week-rail's ≥4-session gate is
   client-side only (the RPC still returns the thin-history value). noop's ReadinessEngine
   requires **minChronic = 14 days** for ACWR and ≥4 days + SD>0 for monotony. Recommended:
   server-side gate (adopt noop's 14-day chronic floor), align the doc, add pgTAP cases.
   Related production symptom: monotony 5.57 on zero-variance windows (2026-09-02 finding #6).

### P2 — noop rigor follow-ups (deferred list, all confirmed still open)

All six items in `docs/handoff/backend.md:69-78` remain open (only the vacuous-`ok(true)`
test cleanup was done):

- ACWR thin-history gate (see finding 8).
- Sleep sub-component imputation: efficiency assumes 100% when awake minutes are missing;
  restorative scores 0 when stages are missing — both should drop + renormalize (currently
  *actively misleading* scores, worse than missing).
- Baseline spread/Winsor bounds are static over full history (noop tracks spread with a
  21-day EWMA, separate from the 14-day center half-life).
- No baseline staleness tracking (noop: `staleDays = 14` + `nightsSinceNewestValidNight`;
  vital-carry bounded to 7 days so a stale number is never presented as current — the same
  class as the 2026-09-02 finding where coach chat presented an Aug 26 check-in as "today").
- No per-metric physiological sanity gates at fold time (noop: per-metric min/max,
  e.g. HRV 5–250 ms, RHR 30–120, resp 8–25 bpm plausibility banding).
- No independent reference implementation of the pure math (noop's Android twin validates
  against an independent numpy replication, pinning all 11 constants + null semantics —
  their highest-value rigor artifact; backend.md already calls this the highest-leverage
  next investment).
- Cold-start edge: the first-ever logged sleep night scores duration 100 (baseline folds
  to tonight itself; `20260725000000:160` sets baseline_value = first value). noop's fix
  shape: below minNeedNights (7) nights, personal need falls back to the population floor.

### P2.5 — new noop patterns not on the deferred list (add them)

9. **Log-domain z for HRV.** noop's readiness path z-scores HRV in ln-space (config
   `readiness_hrv_ln`, bounds ln(8)..ln(250)) — "a raw-ms z over-weights the long upper tail
   and misstates tail rarity" (Plews/Altini). Tracend z-scores raw SDNN ms in
   `compute_recovery_score`. Adopt ln-space for the HRV z (Apple reports SDNN; the same
   right-skew argument applies).
10. **AI-context null semantics.** noop's AI coach contract states twice: "a dash means
    that value was NOT MEASURED that day — say so rather than treating it as a zero," and
    context fields are schema-stable ("always emitted, '—' when absent... the alternative —
    only appending fields when present — gives the model a schema that changes shape
    between days and invites it to read a missing field as a zero"). Tracend's
    `compactContext` **strips nulls** — exactly the anti-pattern. Cheap fix with real
    payoff: stop stripping nulls in the coach context (or emit explicit sentinels) and
    teach the DeepSeek prompts the "null = not measured, never zero" contract. Also adopt
    noop's date discipline: the prompt should forbid asserting "today/recent" without
    comparing the context date to the actual current date (2026-09-02 finding #3).

## noop cross-verification summary

| noop pattern | Tracend state |
| --- | --- |
| Weighted z-composite → logistic (k=1.6), weight renorm on dropped terms | ✅ Matched (k=1.6, renormalized weight_total, nil-when-nothing-usable) |
| Baseline anchor ~58 (WHOOP population mean) | ✅ Deliberately improved: exactly 50 |
| Skin-temp driver 0.05 | ➡️ Swapped for prev_strain 0.05 (HealthKit adaptation) |
| Winsorized EWMA, early-life half-life 3d→14d, hard-reject 5σ / clamp 3σ | ✅ Matched (3d ≤8 obs → 14d; ±3σ clamp / ±5σ reject via 1.4826·MAD) |
| Spread tracked by 21-day EWMA + floorSpread per metric | ❌ Static full-history MAD (deferred) |
| Baseline staleness (staleDays 14) + stale-carry bounds | ❌ None (deferred) |
| ln-domain z for right-skewed HRV | ❌ Raw-ms z (new finding) |
| "Missing ≠ zero" everywhere (load, debt, nights, caffeine) | ◐ Mostly (prev_strain + monotony + weight-trend min-3 done; ACWR thin-history + sleep sub-scores open) |
| Confidence tiers + quality downgrades (never change the score) | ◐ data_confidence counts components only; no input-quality downgrades |
| Refusal logging so nil ≠ 0 is distinguishable | ✅ missing_components + persist_failed_coaching_run_v2 + decision_rejected |
| AI "dash = not measured" contract, schema-stable fields, date discipline | ❌ compactContext strips nulls (new finding) |
| Reference implementation + oracle tests | ❌ None (deferred — highest leverage) |
| User-reported-bug synthetic reproduction tests | ✅ Matched (owner's production-day pgTAP case) |
| Fitness age / caffeine decay / n-of-1 behavior insights / correlation engine | N/A — product features, not rigor gaps; n-of-1 behavior→outcome effects is a future opportunity (see market) |

## Market comparison (2026-09)

**Closest philosophical rival: MacroFactor** ($11.99/mo · $71.99/yr, 4.84★). Adaptive TDEE
learned from the user's own logged data; weekly check-in review adjusts targets from what
was *actually logged*; deviates gracefully ("doesn't function any worse if you deviate");
markets "no warnings, red numbers, or shaming." Gap: no biometrics, no chat layer — exactly
where Tracend is strong. **Adopt its check-in contract as the spec language.**

Key players (fetched from primary sources; search-derived details flagged in the research
notes): WHOOP (score wall + tier-gating backlash 2025; WHOOP Coach praised for sleep Q&A,
criticized for hedging and contradicting its own scores), Athlytic ($29.99/yr — budget
anchor; Target Exertion as a range; 11 widgets + 8 complications), Bevel ($99.99/yr Pro +
AI credit packs; five-score wall + Energy Bank rollup), Oura ($69.99/yr + $349 ring;
Health Radar illness signals; Advisor praised for data references, criticized as generic),
RISE (radical reduction: sleep debt + circadian only — proof that "fewer, defensible
numbers" sells), JuggernautAI ($34.99/mo; graded multi-timescale adaptation ladder from
pre-session readiness inputs — the most complete deterministic adaptivity spec in the
field), TrainerRoad (auto-rest on outside-load spikes; "predicted feel"), Trainwell
($149/mo human tier — the price ceiling for judgment), Gentler Streak (Apple Design Award
2024 for the anti-drill-sergeant stance — validation of Tracend's anti-streak position),
Strava acquired Runna (Apr 2025 — consolidation signal).

**2026 table stakes Tracend currently lacks:** watch complications + home/lock-screen
widgets (highest-leverage: category #1 churn reason is "not enough usage" — the Today tab
needs to escape the app); an AI chat over your own data (Tracend has Coach chat ✅);
photo/barcode food logging (has meal-photo ✅); progress photos (has, consent-gated ✅);
behavior journaling (WHOOP 160+ tags — opportunity via check-ins); privacy positioning as
marketing (asset already: deterministic + explainable).

**Apple Review constraints to design for now:** 5.1.2(i) — explicit disclosure + permission
for third-party AI sharing (build the "your data is sent to our AI provider" consent gate
into onboarding before TestFlight grows); 5.1.3 — never write derived/inferred values to
HealthKit as if measured; 1.4.1 — health-score methodology disclosure (Tracend's
ALGORITHMS.md is an asset: it can be published and competitors can't explain their scores);
5.1.1(ix) — legal-entity developer account before paid launch.

**Patent caution:** recovery-score pipelines are contested IP (reported Bevel v. WHOOP and
Athlytic v. Apple suits, Nov 2025 — medium confidence, verify independently). Tracend's
framing — deterministic, explainable, evidence-traceable trend analysis rather than a
proprietary composite score — is both a philosophical and a legal hedge; get a real IP check
before commercial launch.

**Pricing when subscriptions launch:** annual-first at ~$99.99 with a 7-day trial
(RevenueCat 2025: 67% of H&F subs are yearly; cheap-annual retains 5.4× high-priced monthly
at one year; median trial→paid conversion 39.9% — highest of any category). Ladder: free
beta → $71.99–99.99/yr, between MacroFactor and Bevel.

**Genuinely differentiated (do not dilute):** data lineage as architecture (competitors
interpolate sparse HRV and render scores daily; Tracend shows "No data"); approval-gated
plan changes with versioning + audit events (nobody does this); the deterministic/LLM
split (the failure modes reviewers cite in every wearable AI coach — hedging, contradicting
the app's own scores — are prevented by architecture, not copy); no hardware, no
tier-gating (the exact trust-breakers of WHOOP's 2025 backlash); the 5–6 month completion
narrative (everyone else sells infinite tracking; nobody sells an ending).

## Recommended order

1. Commit the working tree (verified green: 344/344, 0 analyze); decide `Claude.md`
   (commit as intentional CLAUDE.md or delete).
2. Wire gitleaks + gitignore `session-*.md` (three small security-review items).
3. Resp-rate decision — add the HealthKit read (also fixes the confidence ceiling and
   unblocks `DATA_CONFIDENCE_HIGH`), or drop the component.
4. Check-in replay queue + future-date upsert guard (both small, both user-facing trust
   bugs).
5. Docs/governance: PRD §5.8 provider fix, ADR 0011 DeepSeek activation, ACWR server-side
   gate (recommend noop's 14-day chronic floor) + doc/test alignment.
6. Rigor backlog per backend.md order, adding: log-domain HRV z, AI-context null contract
   + prompt date discipline.
7. Product (post-beta): Today widget/complication surface; MacroFactor-style check-in
   review language; ranges-not-points daily targets; "predicted feel" framing for ACWR;
   AI-consent gate before TestFlight grows.

## Session facts for future agents

- The noop clone used for this review was deleted afterward per owner instruction
  (`.tooling/review/` removed). Re-clone shallow if needed; the two analysis reports'
  content is preserved in this doc.
- 344/344 Flutter tests + 0 analyzer issues verified on the working tree 2026-09-04
  (uncommitted redesigns are genuinely committable).
- The market-research deep-dive relied on primary sources (App Store listings, official
  pricing pages, RevenueCat 2025) because web search was unreliable in that session; items
  flagged medium confidence (patent suits, WHOOP Peak pricing, RISE price) need independent
  verification before being cited externally.
- Repo doc-count note: backend.md's "33 assertions" for recovery_honesty_test.sql counts
  bundled `is()` checks; raw top-level `ok(` lines differ (25). Numbers approximate either
  way.
