# Phase 5 — Liquid Glass Production UI

**Created:** 2026-07-26
**Status:** Not started
**Branch:** `feature/feature-engine-phase-5` → `feature/feature-engine`
**Dials:** VARIANCE 7, MOTION 7, DENSITY 3

## Agentic Orchestration Strategy

**Pattern:** Wave-based parallel delegation using OpenCode's Task subagents.
**Branch:** `feature/feature-engine-phase-5` (created)
**Verification gate per wave:** `./scripts/flutter.sh analyze && ./scripts/flutter.sh test`

```
WAVE 1 ─── Foundation (4 agents in parallel)
│  Agent A: fonts + tokens + theme     → pubspec.yaml, tracend_tokens.dart, tracend_theme.dart
│  Agent B: LiquidGlass widget         → lib/shared/widgets/liquid_glass.dart
│  Agent C: MicroMotion utility        → lib/shared/widgets/micro_motion.dart
│  Agent D: asset cleanup              → delete JPG + pubspec entry
│  ══ VERIFY: analyze + pub get + test ══
│
WAVE 2 ─── TrajectoryLens (2 agents in parallel)
│  Agent E: TrajectoryLens rewrite     → lib/shared/widgets/trajectory_lens.dart
│  Agent F: Today hero integration     → lib/features/today/today_screen.dart
│  ══ VERIFY: analyze + test ══
│
WAVE 3 ─── New Components (5 agents in FULL parallel)
│  Agent G: EvidenceAccordion
│  Agent H: CoachInsightCard
│  Agent I: DatePillStrip
│  Agent J: TargetsGrid
│  Agent K: WorkoutModeSheet
│  ══ VERIFY: analyze + test ══
│
WAVE 4 ─── Screen Reflow (5 agents in parallel)
│  Agent L: Today reflow               → today_screen.dart
│  Agent M: Train reflow               → train_screen.dart
│  Agent N: Nutrition reflow           → nutrition_screen.dart
│  Agent O: Progress reflow            → progress_screen.dart
│  Agent P: Coach reflow               → coach_screen.dart
│  ══ VERIFY: analyze + test ══
│
WAVE 5 ─── New Screens (2 agents in parallel)
│  Agent Q: My AI Usage screen
│  Agent R: Welcome screens
│  ══ VERIFY: analyze + test ══
│
WAVE 6 ─── Polish (4 agents in parallel)
│  Agent S: Animation pass             → stagger, path draw, pulse, count-up, tab morph
│  Agent T: Audit pass                 → Dynamic Type, VoiceOver, contrast, fallbacks, 44pt
│  Agent U: Bug fix                    → 180 min cap + July 22 DB correction
│  Agent V: Tests                      → all new component + animation tests
│  ══ VERIFY: full analyze + test + build ══
│
FINAL ─── Build + Gate
│  ./scripts/flutter.sh analyze
│  ./scripts/flutter.sh test
│  ./scripts/flutter.sh build ios --release --no-codesign
```

**Agent loop (internal per agent):** read existing code → apply skill rules → build → self-check → report back. Main agent integrates, runs gate, advances to next wave.

---

## Skills Pipeline

| Phase | Primary Skill | Guard Skill |
|-------|-------------|------------|
| 5A | `design-system` (tokens) | `impeccable` (audit) |
| 5B | `stitch-design-taste` (Stitch→Flutter) | `design-taste-frontend` (anti-slop) |
| 5C | `redesign-existing-projects` (audit) | `impeccable` (polish) |
| 5D | `design-taste-frontend` (components) | `impeccable` (shape) |
| 5E | `brand` (voice) | `impeccable` (onboard) |
| 5F | `impeccable` (animate+audit.native) | `redesign-existing-projects` (checklist) |

---

## 5A — Foundation: Fonts + Apple Glass Token

| Agent | File | What |
|-------|------|------|
| A | `pubspec.yaml` | Import Spline Sans (300/400/500/600/700) + IBM Plex Mono (400/500/600) |
| A | `lib/app/theme/tracend_tokens.dart` | Add `displayFamily`, `monoFamily` constants; add `LiquidGlass` config |
| A | `lib/app/theme/tracend_theme.dart` | Wire new fonts into `TextTheme` |
| B | `lib/shared/widgets/liquid_glass.dart` | Apple Liquid Glass: `BackdropFilter(sigma:24)` + 72% fill + 1px 10% inner border + 8% top highlight. `prefers-reduced-transparency` fallback. |
| C | `lib/shared/widgets/micro_motion.dart` | Spring entrance (stiffness:100, damping:20), scroll-stagger, pulse loop |
| D | `assets/visuals/tracend-coaching-horizon-v1.jpg` + pubspec | Delete both |

## 5B — TrajectoryLens: Animated Bezier Hero

| Agent | File | What |
|-------|------|------|
| E | `lib/shared/widgets/trajectory_lens.dart` | Full rewrite: `CustomPainter` Bezier path + `PathMetric` animation (1.5s draw). Data dots: Sleep→Train→Fuel→Now (glow pulse). Respects `ReduceMotion`. |
| F | `lib/features/today/today_screen.dart` | Replace `_TodayHeroBackdrop` with TrajectoryLens in LiquidGlass. Remove all JPG code. Spline Sans 32pt headline. |

## 5C — Screen Reflow (parallel per screen)

| Agent | Screen | Scope |
|-------|--------|-------|
| L | Today | Glass tiles, EvidenceAccordion, glass timeline rows |
| M | Train | DatePillStrip, glass TrainingLoadGauge, Session bars |
| N | Nutrition | Glass meal cards, TargetsGrid, gradient metabolic bar |
| O | Progress | Glass WeightTrendIndicator, Body Measurements section |
| P | Coach | CoachInsightCard, glass accordion, perspective toggle |

## 5D — New Components (all 5 parallel)

| Agent | Widget | File |
|-------|--------|------|
| G | `EvidenceAccordion` | `lib/shared/widgets/evidence_accordion.dart` |
| H | `CoachInsightCard` | `lib/features/coach/widgets/coach_insight_card.dart` |
| I | `DatePillStrip` | `lib/shared/widgets/date_pill_strip.dart` |
| J | `TargetsGrid` | `lib/shared/widgets/targets_grid.dart` |
| K | `WorkoutModeSheet` | `lib/features/train/workout_mode_sheet.dart` |

## 5E — New Screens

| Agent | Screen | Source |
|-------|--------|------|
| Q | My AI Usage | `design/stitch/account/AI_USAGE_PROMPT.md` |
| R | Welcome screens | 16 Stitch onboarding refs |

## 5F — Polish + Motion + Bug Fix (parallel)

| Agent | Task |
|-------|------|
| S | Animation: stagger entrance, path draw, pulse, count-up, tab morph |
| T | Audit: Dynamic Type, VoiceOver, contrast, fallbacks, 44pt targets |
| U | Bug fix: 180 min cap + July 22 DB correction |
| V | Tests: widgets + animations. Full `./scripts/flutter.sh test`. |

---

## Key Design Decisions

- **Apple Liquid Glass** = `BackdropFilter(sigmaX:24, sigmaY:24)` + 72% surface fill + 1px 10% white inner border + 8% white top-gradient highlight. Falls back to solid `#121925` (dark) / `#FFFFFF` (light) under `prefers-reduced-transparency`.
- **Motion thesis:** Focal moment = TrajectoryLens path draw (1.5s). Continuity = card entrance stagger. Feedback = pulse dot, tab icon morph.
- **Design system update:** `DESIGN_SYSTEM.md` §3.4 updated to permit Liquid Glass on Today hero, Coach cards, and metric readouts (matching Stitch visual language).
- **One PR:** `feature/feature-engine-phase-5` → `feature/feature-engine`. CI/CD triggers deploy on merge.

## Skills Loaded

| Skill | Phase | Status |
|-------|-------|--------|
| `impeccable` (critique/shape/animate/polish/audit.native) | All | Loaded |
| `design-taste-frontend` (V7 M7 D3) | 5B/5C/5D | Loaded |
| `stitch-design-taste` (Stitch→Flutter) | 5B/5C | Loaded |
| `redesign-existing-projects` (audit) | 5C/5D | Loaded |
| `design-system` (tokens) | 5A | Loaded |
| `brand` (voice) | 5E | Loaded |
