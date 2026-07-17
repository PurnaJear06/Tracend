# ADR 0008: Coach Context v5 — Nutrition Adherence, Physique Schema, and Per-Pose Photos

Date: 2026-07-16 Status: accepted

## Context

Coach Context v4 deployed query-aware selection (6 context kinds) and JSON compaction, keeping every
kind under 8000 TPM. However, five gaps were identified:

1. Progress photos UI offered only a single monolithic "capture all 3" flow; per-pose entry and
   gallery upload were missing.
2. Coach context had zero access to physique analysis observations (the `physique_analyses` table
   didn't exist).
3. Nutrition adherence tracking was shallow (only 7-day calorie/protein averages); meal schedule
   compliance was not tracked.
4. `classifyQuestion` keywords didn't cover physique, visual progress, adherence, or compliance
   queries.
5. Coach couldn't see whether meals matched the prescribed schedule.

## Decision

### Backend

- Created `physique_analyses` table with forced RLS and owner-only read. No vision AI processing
  path exists — the table is schema-readiness only until the ARCHITECTURE.md §11 evaluation gate is
  met.
- Replaced `prepare_coach_chat_v4` in-place (same name, signature) with enriched v5:
  - `plan_change`: new `nutrition_adherence` (days_with_confirmed_meals_7d, confirmed_meal_count_7d,
    schedule_slot_compliance), `data_quality.last_photo_set`
  - `explain_evidence`: new `data_quality.photo_sets_completed`,
    `data_quality.has_physique_analysis`, `evidence_freshness.last_photo_set`
  - `nutrition_focus`: extended `nutrition_compliance_7day` (avg_daily_carbohydrate_g,
    avg_daily_fat_g, days_with_meals)
  - `general`, `daily_action`, `recovery`: unchanged
- Updated `classifyQuestion` regex: added `physique`, `visual progress`, `photo comparison`,
  `body composition` to `explain_evidence`; added `adherence`, `compliance`, `sticking to`,
  `diet plan` to `nutrition_focus`
- Added 12 new TS key abbreviations for v5 fields (nutrition_adherence → na,
  schedule_slot_compliance → ssc, etc.)

### Frontend

- Replaced single `_ActionCard` ("Create a standardized photo set") with three `_PosePhotoRow`
  widgets (front/side/back), each showing capture status and Camera/Gallery buttons.
- Replaced `_captureSet` (monolithic sequential flow) with `_capturePose(pose, source)` —
  single-pose capture supporting both camera and gallery.
- Removed `_PhotoGuideSheet` (no longer needed — pose guidance is now per-row).
- Added `_hasConsent` state tracking to avoid re-prompting for consent on each per-pose capture.
- `_activeSet` draft ID and `_capturedPoses` set track in-progress multi-pose capture across
  individual captures. Set auto-completes when all 3 poses are registered.

### Token budget (plan_change, largest kind)

~4,180 tokens after additions — 48% under Groq 8000 TPM cap.

## Consequences

- Coach can now evaluate nutrition adherence (schedule compliance, carb/fat averages, meal logging
  frequency) in `plan_change` and `nutrition_focus` contexts.
- Physique analysis schema is ready; Coach will surface observations when vision AI is evaluated and
  enabled.
- Per-pose photo capture with gallery support improves UX flexibility without expanding the data
  model.
- `physique_analyses` table remains empty until vision AI evaluation passes — zero operational cost.
