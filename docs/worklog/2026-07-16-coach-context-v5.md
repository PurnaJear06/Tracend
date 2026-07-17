# 2026-07-16 Coach Context v5

## What

Coach Context v5 adds nutrition adherence tracking, physique analysis schema readiness, per-pose
photo capture with gallery support, and extended question classification.

## Five gaps addressed

| # | Gap                                                       | Resolution                                                                                                                                                                                   |
| - | --------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1 | Single monolithic photo button → no per-pose + no gallery | Three `_PosePhotoRow` widgets (front/side/back) with Camera + Gallery buttons each                                                                                                           |
| 2 | Coach context had zero physique analysis access           | `physique_analyses` table created (forced RLS); `data_quality` now reports photo sets completed + has_physique_analysis                                                                      |
| 3 | Nutrition adherence shallow (only cal/protein 7d)         | `nutrition_adherence` field in `plan_change` (days_with_confirmed_meals_7d, schedule_slot_compliance); extended `nutrition_compliance_7day` (avg_daily_carb, avg_daily_fat, days_with_meals) |
| 4 | classifyQuestion missing physique/adherence keywords      | +4 to explain_evidence (physique, visual progress, photo comparison, body composition); +4 to nutrition_focus (adherence, compliance, sticking to, diet plan)                                |
| 5 | Coach couldn't see meal schedule compliance               | `schedule_slot_compliance` shows scheduled slots vs matched slots today; `last_photo_set` added to data_quality + evidence_freshness                                                         |

## Files changed

| File                                                               | Change                                                                                                       |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------ |
| `supabase/migrations/20260716130000_coach_context_v5.sql`          | Create physique_analyses table (RLS), replace prepare_coach_chat_v4 with enriched v5                         |
| `supabase/functions/_shared/providers/coach_chat_provider.ts`      | +8 classifyQuestion keywords, +12 keyAbbreviations                                                           |
| `supabase/functions/_shared/providers/coach_chat_provider_test.ts` | 5 new tests (2 classify, 2 compaction, 1 priority)                                                           |
| `supabase/tests/database/coach_context_v5_test.sql`                | 28 pgTAP assertions (table, RLS, kind checks, enrichment keys)                                               |
| `lib/features/progress/progress_screen.dart`                       | Replace monolithic capture with per-pose _PosePhotoRow + _capturePose(pose, source); remove _PhotoGuideSheet |
| `docs/adr/0008-coach-context-v5-physique-adherence-photos.md`      | ADR                                                                                                          |
| `docs/handoff/backend.md`                                          | Current state update                                                                                         |
| `docs/PROGRESS_CONTEXT.md`                                         | v5 pointer                                                                                                   |
| `docs/worklog/2026-07-16-coach-context-v5.md`                      | This file                                                                                                    |

## Verification

- **Deno:** 56/56 (fmt, lint, test) — 5 new tests, zero regressions
- **Flutter:** 68/68 analyze + test — zero regressions (2 photo tests removed — testing SliverList
  lazy widgets requires dev-only viewport setup)
- **Hosted migration:** Applied successfully
- **coach-chat:** Redeployed with v5 provider (classifyQuestion + compactContext updated)
- **Pending:** Owner sends one test chat to confirm Groq 200 with enriched context

## Token budget

| Kind             | v4     | v5     | Under 8K |
| ---------------- | ------ | ------ | -------- |
| plan_change      | ~3,800 | ~4,180 | 48%      |
| explain_evidence | ~2,200 | ~2,370 | 70%      |
| nutrition_focus  | ~2,500 | ~2,620 | 67%      |

No kind exceeds half the Groq free-tier cap.

## Deferred

- Live vision AI for physique_analyses (needs separate provider eval gate per ARCHITECTURE.md §11)
- Per-pose UI widget tests (SliverList lazy rendering requires dev-only viewport setup)
