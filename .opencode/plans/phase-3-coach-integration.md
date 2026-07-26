# Phase 3 — Feature Engine: Coach Integration (Computed Scores → AI)

**Parent plan:** `feature-engine-and-ui-alignment.md`
**Created:** 2026-07-25
**Branch:** `feature/feature-engine-phase-3` (off `feature/feature-engine`)
**Effort:** 2-3 days

---

## Objective

Wire the computed feature engine scores (recovery, sleep quality, ACWR, weight trends, macro adherence, data confidence) into the coaching Edge Functions so the AI receives structured, scored context instead of raw values and subjective check-in flags.

## What Changes

```
BEFORE: Evidence codes = subjective check-in flags (energy ≥ 3, soreness ≤ 3)
        Coach-chat context = raw HealthKit values only, no computed scores
        Mock provider = binary "RECOVERY_WITHIN_BASELINE present or not?"

AFTER:  Evidence codes = computed-score thresholds (recovery ≥ 50, ACWR > 1.5, etc.)
        Coach-chat context = includes computed_metrics section (recovery, sleep, ACWR, weight, adherence)
        Mock provider = multi-branch (recovery, load, nutrition, confidence)
        AI system instruction = evidence code reference table
```

---

## Branch Setup

```sh
git checkout feature/feature-engine
git pull origin feature/feature-engine
git checkout -b feature/feature-engine-phase-3
```

---

## 1. Migration — Enriched Evidence Codes + Coach-chat v6

**File:** `supabase/migrations/20260726000000_feature_engine_coach_integration.sql`

### 1A: Update `prepare_daily_coaching` — Computed-score evidence codes

Replace the current check-in-based evidence logic (lines 52–66 of `20260724000002`) with
computed-score-based evidence. Outcome rules stay conservative (pain ≥ 7 → escalate, missing
check-in → request_data, else maintain_only). The new codes are for AI context only.

Add this block after `metrics_jsonb := public.compute_daily_metrics(...)`:

```sql
declare
  recovery_score integer := (metrics_jsonb->'scores'->>'recovery')::integer;
  sleep_quality integer := (metrics_jsonb->'scores'->>'sleep_quality')::integer;
  acwr_val numeric := (metrics_jsonb->'scores'->>'acwr')::numeric;
  weight_trend numeric := (metrics_jsonb->'scores'->>'weight_trend_7d_kg_per_day')::numeric;
  adherence numeric := (metrics_jsonb->'scores'->>'macro_adherence_pct')::numeric;
  confidence text := metrics_jsonb->>'data_confidence';
begin
  -- Recovery evidence
  if recovery_score is not null and recovery_score >= 50 then
    evidence := evidence || array['RECOVERY_WITHIN_BASELINE'];
  elsif recovery_score is not null and recovery_score < 40 then
    evidence := evidence || array['RECOVERY_BELOW_BASELINE'];
  else
    evidence := evidence || array['CHECK_IN_RECOVERY_MIXED'];
  end if;

  -- Sleep quality evidence
  if sleep_quality is not null then
    if sleep_quality >= 50 then
      evidence := evidence || array['SLEEP_QUALITY_GOOD'];
    else
      evidence := evidence || array['SLEEP_QUALITY_POOR'];
    end if;
  end if;

  -- Training load evidence
  if acwr_val is not null then
    if acwr_val > 1.5 then
      evidence := evidence || array['TRAINING_LOAD_ELEVATED'];
    elsif acwr_val between 0.8 and 1.3 then
      evidence := evidence || array['TRAINING_LOAD_OPTIMAL'];
    end if;
  end if;

  -- Weight trend evidence
  if weight_trend is not null then
    if weight_trend < -0.1 then
      evidence := evidence || array['WEIGHT_TRENDING_DOWN'];
    elsif weight_trend > 0.1 then
      evidence := evidence || array['WEIGHT_TRENDING_UP'];
    else
      evidence := evidence || array['WEIGHT_STABLE'];
    end if;
  end if;

  -- Nutrition adherence evidence
  if adherence is not null then
    if adherence >= 80 then
      evidence := evidence || array['NUTRITION_ON_TRACK'];
    elsif adherence < 50 then
      evidence := evidence || array['NUTRITION_BEHIND'];
    end if;
  end if;

  -- Data confidence evidence
  if confidence is not null then
    if confidence = 'high' then
      evidence := evidence || array['DATA_CONFIDENCE_HIGH'];
    elsif confidence = 'low' or confidence = 'cold_start' then
      evidence := evidence || array['DATA_CONFIDENCE_LOW'];
    end if;
  end if;
end;
```

**Evidence code catalog (14 total):**

| Code | Source | Threshold |
|------|--------|-----------|
| `APPROVED_PLAN_ACTIVE` | kept | Always |
| `CHECK_IN_SAFETY_ESCALATION` | kept | pain ≥ 7 |
| `CHECK_IN_RECOVERY_MIXED` | kept (fallback) | recovery 40-49 or null |
| `HEALTH_CONTEXT_AVAILABLE` | kept | HealthKit data present |
| `RECOVERY_WITHIN_BASELINE` | **changed** | recovery_score ≥ 50 |
| `RECOVERY_BELOW_BASELINE` | **new** | recovery_score < 40 |
| `SLEEP_QUALITY_GOOD` | **new** | sleep ≥ 50 |
| `SLEEP_QUALITY_POOR` | **new** | sleep < 50 |
| `TRAINING_LOAD_OPTIMAL` | **new** | 0.8 ≤ ACWR ≤ 1.3 |
| `TRAINING_LOAD_ELEVATED` | **new** | ACWR > 1.5 |
| `WEIGHT_TRENDING_DOWN` | **new** | 7d slope < -0.1 kg/day |
| `WEIGHT_TRENDING_UP` | **new** | 7d slope > 0.1 kg/day |
| `WEIGHT_STABLE` | **new** | else |
| `NUTRITION_ON_TRACK` | **new** | adherence ≥ 80% |
| `NUTRITION_BEHIND` | **new** | adherence < 50% |
| `DATA_CONFIDENCE_HIGH` | **new** | 14+ evidence points |
| `DATA_CONFIDENCE_LOW` | **new** | < 7 points or cold_start |

### 1B: Add `prepare_coach_chat_v6`

Wraps v5. Reads the latest `daily_computed_metrics` row for the user and adds
a `computed_metrics` section to the context. Adds ~500 chars (well within the
40K v5 budget guard). Falls back to `{ "unavailable": true }` if no row exists.

```sql
create or replace function public.prepare_coach_chat_v6(
  target_user_id uuid, target_thread_id uuid, question text,
  coaching_timezone text, request_idempotency_key uuid, context_kind text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  prepared jsonb; c jsonb;
  metrics_row public.daily_computed_metrics%rowtype;
  computed_metrics jsonb;
begin
  prepared := public.prepare_coach_chat_v5(target_user_id, target_thread_id,
    question, coaching_timezone, request_idempotency_key, context_kind);
  if coalesce((prepared->>'replayed')::boolean, false) then return prepared; end if;

  c := prepared->'context';

  select * into metrics_row from public.daily_computed_metrics
    where user_id = target_user_id
    order by computed_at desc limit 1;

  if metrics_row.id is not null then
    computed_metrics := jsonb_build_object(
      'recovery', jsonb_build_object(
        'score', metrics_row.recovery_score,
        'breakdown', metrics_row.scores_jsonb->'recovery_breakdown'),
      'sleep', case when metrics_row.sleep_quality_score is not null
        then jsonb_build_object('quality', metrics_row.sleep_quality_score,
          'debt_minutes', metrics_row.sleep_debt_minutes)
        else null end,
      'training_load', case when metrics_row.acwr is not null
        then jsonb_build_object('acwr', metrics_row.acwr,
          'monotony', metrics_row.training_monotony,
          'strain', metrics_row.daily_strain)
        else null end,
      'weight', case when metrics_row.weight_trend_7d_kg_per_day is not null
        then jsonb_build_object('trend_7d_kg_per_day', metrics_row.weight_trend_7d_kg_per_day,
          'trend_28d_kg_per_day', metrics_row.weight_trend_28d_kg_per_day)
        else null end,
      'nutrition', case when metrics_row.macro_adherence_pct is not null
        then jsonb_build_object('adherence_pct', metrics_row.macro_adherence_pct)
        else null end,
      'data_confidence', metrics_row.data_confidence,
      'computed_at', metrics_row.computed_at
    );
  else
    computed_metrics := jsonb_build_object('unavailable', true,
      'reason', 'Feature engine not yet computed for this user');
  end if;

  c := c || jsonb_build_object('computed_metrics', computed_metrics);

  return prepared || jsonb_build_object('context', c);
end $$;

grant execute on function public.prepare_coach_chat_v6(uuid,uuid,text,text,uuid,text)
  to service_role;
```

---

## 2. Edge Function Changes

### 2A: `coach-chat/index.ts` — Switch to v6

**File:** `supabase/functions/coach-chat/index.ts`
**Change:** One line — replace `prepare_coach_chat_v5` with `prepare_coach_chat_v6`

```diff
-    prepared = await auth.serviceClient.rpc("prepare_coach_chat_v5", {
+    prepared = await auth.serviceClient.rpc("prepare_coach_chat_v6", {
```

### 2B: `coach_chat_provider.ts` — Add computed metrics to markdown context

**File:** `supabase/functions/_shared/providers/coach_chat_provider.ts`

Add section 20 in `formatContextAsMarkdown()` after section 19 (line 703), before return:

```typescript
  // 20. Computed Metrics (feature engine scores)
  const computed = obj(ctx.computed_metrics);
  if (Object.keys(computed).length && !computed.unavailable) {
    let s = "## Computed Scores\n";
    const rec = obj(computed.recovery);
    if (Object.keys(rec).length) s += `- recovery: ${str(rec.score)}/100\n`;
    const slp = obj(computed.sleep);
    if (Object.keys(slp).length) {
      s += `- sleep quality: ${str(slp.quality)}/100`;
      if (slp.debt_minutes != null) s += `, debt: ${str(slp.debt_minutes)} min`;
      s += "\n";
    }
    const tl = obj(computed.training_load);
    if (Object.keys(tl).length) {
      s += `- training load: ACWR ${str(tl.acwr)}`;
      if (tl.monotony != null) s += `, monotony ${str(tl.monotony)}`;
      s += `\n`;
    }
    const wt = obj(computed.weight);
    if (Object.keys(wt).length) {
      s += `- weight trend: 7d ${str(wt.trend_7d_kg_per_day)} kg/day`;
      if (wt.trend_28d_kg_per_day != null) {
        s += `, 28d ${str(wt.trend_28d_kg_per_day)} kg/day`;
      }
      s += "\n";
    }
    const nut = obj(computed.nutrition);
    if (Object.keys(nut).length) {
      s += `- nutrition adherence: ${str(nut.adherence_pct)}%\n`;
    }
    if (computed.data_confidence) {
      s += `- data confidence: ${str(computed.data_confidence)}\n`;
    }
    push(s);
  }
```

Also update `compactContext()` to add the abbreviation `cm` for `computed_metrics` in the compact
key map (around line 950). Any new long-text keys under `computed_metrics` should be registered in
`longTextKeys` in `fitContextToLimit`'s Tier 1.

### 2C: `mock_coach_model_provider.ts` — Enriched decision branches

**File:** `supabase/functions/_shared/providers/mock_coach_model_provider.ts`

Replace the binary `RECOVERY_WITHIN_BASELINE` check (lines 56–80) with multi-branch logic:

```typescript
  const recoveryOk = request.permittedEvidence.includes("RECOVERY_WITHIN_BASELINE");
  const recoveryBad = request.permittedEvidence.includes("RECOVERY_BELOW_BASELINE");
  const loadElevated = request.permittedEvidence.includes("TRAINING_LOAD_ELEVATED");
  const nutritionBehind = request.permittedEvidence.includes("NUTRITION_BEHIND");
  const dataLow = request.permittedEvidence.includes("DATA_CONFIDENCE_LOW");

  if (recoveryBad) {
    return Promise.resolve({
      schema_version: coachDecisionSchemaVersion,
      decision_kind: request.decisionKind,
      training: {
        action: "GATHER_DATA",
        summary: "Recovery score is below baseline. Consider a lighter session.",
        today_adjustments: [],
      },
      nutrition: { action: "MAINTAIN_TARGETS",
        summary: "Keep approved nutrition targets while recovery recovers.",
        today_adjustments: [] },
      head_coach: {
        final_decision: "Take it easy today.",
        reason: "Recovery score is below the recent baseline (< 40).",
      },
      evidence: [{
        code: "RECOVERY_BELOW_BASELINE",
        label: "Recovery score is below the baseline threshold",
        source: "feature_snapshot",
      }],
      confidence: "high",
      missing_data: [],
      risk_flags: [],
      change_proposals: [],
    });
  }

  if (loadElevated) {
    return Promise.resolve({
      schema_version: coachDecisionSchemaVersion,
      decision_kind: request.decisionKind,
      training: {
        action: "ADJUST_TODAY",
        summary: "Training load is elevated. Reduce volume or intensity today.",
        today_adjustments: [{ field: "intensity", direction: "decrease", reason: "ACWR > 1.5" }],
      },
      nutrition: { action: "MAINTAIN_TARGETS",
        summary: "Keep approved nutrition targets.",
        today_adjustments: [] },
      head_coach: {
        final_decision: "Reduce training intensity today.",
        reason: "Acute-to-chronic workload ratio is elevated (> 1.5).",
      },
      evidence: [{
        code: "TRAINING_LOAD_ELEVATED",
        label: "Training load is above the safe zone",
        source: "feature_snapshot",
      }],
      confidence: "high",
      missing_data: [],
      risk_flags: ["elevated_load"],
      change_proposals: [],
    });
  }

  if (dataLow) {
    return Promise.resolve({
      schema_version: coachDecisionSchemaVersion,
      decision_kind: request.decisionKind,
      training: { action: "GATHER_DATA",
        summary: "Insufficient health data for confident decision.",
        today_adjustments: [] },
      nutrition: { action: "GATHER_DATA",
        summary: "Insufficient nutrition data for confident decision.",
        today_adjustments: [] },
      head_coach: {
        final_decision: "Sync HealthKit and log meals regularly.",
        reason: "Not enough data points for confident scoring.",
      },
      evidence: [],
      confidence: "low",
      missing_data: ["health_context", "nutrition_data"],
      risk_flags: [],
      change_proposals: [],
    });
  }

  if (!recoveryOk) {
    return Promise.resolve({
      // Existing GATHER_DATA fallback (unchanged from current code)
    });
  }

  // Default: PROCEED_AS_PLANNED (unchanged from current code)
```

### 2D: Provider system instructions — Evidence code reference

Add evidence code definitions to all three providers' system instructions:

**File:** `supabase/functions/_shared/providers/gemini_coach_model_provider.ts`
**File:** `supabase/functions/_shared/providers/deepseek_coach_model_provider.ts`
**File:** `supabase/functions/_shared/providers/groq_coach_model_provider.ts`

Append to system instruction string:

```
"Evidence code reference: "
"RECOVERY_WITHIN_BASELINE = recovery score ≥ 50, "
"RECOVERY_BELOW_BASELINE = recovery score < 40, "
"SLEEP_QUALITY_GOOD = sleep quality score ≥ 50, "
"SLEEP_QUALITY_POOR = sleep quality score < 50, "
"TRAINING_LOAD_OPTIMAL = ACWR 0.8–1.3, "
"TRAINING_LOAD_ELEVATED = ACWR > 1.5, "
"WEIGHT_TRENDING_DOWN = 7-day slope < -0.1 kg/day, "
"WEIGHT_TRENDING_UP = 7-day slope > +0.1 kg/day, "
"WEIGHT_STABLE = 7-day slope between ±0.1 kg/day, "
"NUTRITION_ON_TRACK = adherence ≥ 80%, "
"NUTRITION_BEHIND = adherence < 50%, "
"DATA_CONFIDENCE_HIGH = 14+ evidence points, "
"DATA_CONFIDENCE_LOW = < 7 evidence points."
```

---

## 3. pgTAP Tests

**File:** `supabase/tests/database/feature_engine_phase_3_coach_test.sql`

Target: **20 tests**

| # | Topic | Tests |
|---|-------|-------|
| 1-2 | Recovery evidence | score ≥ 50 → WITHIN_BASELINE, score < 40 → BELOW_BASELINE |
| 3 | Recovery edge | 40 ≤ score ≤ 49 → CHECK_IN_RECOVERY_MIXED |
| 4 | Recovery edge | null score → CHECK_IN_RECOVERY_MIXED |
| 5-6 | Sleep evidence | quality ≥ 50 → GOOD, quality < 50 or null → POOR |
| 7-8 | ACWR evidence | 0.8 ≤ ACWR ≤ 1.3 → OPTIMAL, ACWR > 1.5 → ELEVATED |
| 9 | ACWR edge | ACWR null → neither OPTIMAL nor ELEVATED |
| 10-11 | Weight evidence | slope < -0.1 → DOWN, slope > 0.1 → UP |
| 12 | Weight edge | slope between ±0.1 → STABLE |
| 13-14 | Nutrition evidence | adherence ≥ 80 → ON_TRACK, adherence < 50 → BEHIND |
| 15-16 | Confidence evidence | high → HIGH, cold_start → LOW |
| 17 | Regression | Existing codes still produced alongside new ones |
| 18-19 | Coach-chat v6 | Context includes `computed_metrics`, v6 wraps v5 without breaking |
| 20 | Budget | v6 adds under 1K chars to v5 context |

---

## 4. Contract Fixtures

| Fixture | Action |
|---------|--------|
| `test/contract/fixtures/coach_decision_v1.json` | Update `permitted_evidence` with enriched codes |
| `test/contract/fixtures/coach_chat_context_v5_0.json` | **New** — v6 context with `computed_metrics` section |
| `test/contract/fixtures/daily_brief_v1_1.json` | Verify new evidence codes appear in output |

---

## 5. Deployment Order

```
1. backup-db.sh
2. supabase db push --linked --dry-run
3. supabase db push --linked
4. supabase functions deploy coach-decide --use-api
5. supabase functions deploy coach-chat --use-api
6. Colima start + ./scripts/test-db.sh supabase/tests/database/feature_engine_phase_3_coach_test.sql
7. ./scripts/pre-deploy.sh (full gate)
8. Hosted smoke test — verify evidence codes
9. Ask coach in app: "how's my recovery today?" — verify AI references computed scores
```

---

## 6. Hosted Smoke Test

```sql
-- Verify enriched evidence codes
SELECT prepare_daily_coaching(
  'd59f99e6-aa2d-40df-8077-18935b8260df',
  CURRENT_DATE, 'UTC',
  gen_random_uuid()::uuid
);

-- Verify coach-chat v6 context includes computed_metrics
SELECT prepare_coach_chat_v6(
  'd59f99e6-aa2d-40df-8077-18935b8260df',
  gen_random_uuid()::uuid, 'how is my recovery?', 'UTC',
  gen_random_uuid()::uuid, 'recovery'
);
-- Expected: context->computed_metrics.recovery.score = 49
-- Expected: context->computed_metrics.training_load.acwr = 1.00
-- Expected: context->computed_metrics.data_confidence = 'medium'
```

---

## 7. Files Changed

| File | Change |
|------|--------|
| `supabase/migrations/20260726000000_feature_engine_coach_integration.sql` | **New migration** — enriched evidence + v6 |
| `supabase/functions/coach-chat/index.ts` | 1 line: v5 → v6 |
| `supabase/functions/_shared/providers/coach_chat_provider.ts` | Add section 20, update compactContext |
| `supabase/functions/_shared/providers/mock_coach_model_provider.ts` | Multi-branch evidence logic |
| `supabase/functions/_shared/providers/gemini_coach_model_provider.ts` | Evidence code reference in system instruction |
| `supabase/functions/_shared/providers/deepseek_coach_model_provider.ts` | Evidence code reference in system instruction |
| `supabase/functions/_shared/providers/groq_coach_model_provider.ts` | Evidence code reference in system instruction |
| `supabase/tests/database/feature_engine_phase_3_coach_test.sql` | **New** — 20 pgTAP tests |
| `test/contract/fixtures/coach_chat_context_v5_0.json` | **New** — v6 contract fixture |

---

## 8. What Does NOT Change

- No Flutter UI changes (Phase 4)
- No new tables or columns
- No schema renames/drops (forward-compatible migration)
- Change proposals remain disabled
- Policy outcome gating: still pain-based + check-in presence
- `coach-decide/index.ts` — no change (uses `prepare_daily_coaching` internally)
- All v1–v5 context layers untouched
- `get_my_daily_brief` and `get_my_training_hub` — already include computed scores (Phase 2)

---

## 9. Architecture Rule Compliance

All 12 AGENTS.md rules verified:
- Deterministic evidence codes computed from feature engine scores (not model output)
- Model output never activates a plan, confirms a meal, or writes durable state
- Evidence codes inform AI context only; policy outcome remains safety-gated
- Forward-compatible migration (additive SQL, no drops/renames)
- RLS and multi-user isolation unchanged
- No secrets in Flutter
- Context budget: v6 adds ~500 chars, well under 40K guard
