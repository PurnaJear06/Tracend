# Phase 5 v2 — "Precision Pro" Production UI

**Created:** 2026-08-22
**Status:** In progress (Chunk 0)
**Branch:** `feature/feature-engine-phase-5-v2` → merge `feature/feature-engine`
**Backup tag:** `backup/pre-phase-5-v2` at `93fa49e`
**DB changes:** NONE — pure UI phase, all data already exists in RPCs

## Owner Rulings (2026-08-22)

1. **Visual direction:** Stitch "Precision Pro" production-grade look. Owner loved the Stitch
   designs; the previous agent's execution was rejected.
2. **Authority docs:** DESIGN_SYSTEM.md is outdated relative to the new design direction →
   amend it properly (in the same change as the code, per AGENTS.md), never silently override.
3. **Scope:** All 5 tabs, executed in chunks, each chunk gated + reviewed before the next.
4. **Features:** Every already-implemented repo feature must be surfaced beautifully and
   actually work — no no-op controls, no orphaned widgets.
5. **AI Usage screen:** real RPC fields only. The Stitch mock's token counts and per-feature
   breakdown rows do NOT exist in `get_my_ai_usage` → omitted, never fabricated.
6. **Fonts:** Spline Sans (display) + IBM Plex Mono (data values) — exact Stitch pairing.
7. **Colors:** Stitch hexes, contrast-guarded.
8. **Process:** tests configured first, nothing breaks at any step, research agents for
   market/framework grounding.

## Research Findings (baked into this plan)

### Fonts (research agent, 2026-08-22)
- Previous attempt shipped FAKE files: `SplineSans-SemiBold.ttf` byte-identical to Bold
  (51,468 B each). Genuine upstream sizes: SemiBold **78,232 B**, Bold **77,396 B**
  (different SHA-1s) — the old pair was a corrupted/subset duplicate. Discard pattern.
- **Spline Sans:** `github.com/SorkinType/SplineSans`, SIL OFL 1.1, no Reserved Font Names.
  Statics: Light 75,504 / Regular 74,548 / Medium 76,672 / SemiBold 78,232 / Bold 77,396 B.
  Weights 300–700, no italic. Google Fonts ships variable-only → use SorkinType statics.
- **IBM Plex Mono:** `github.com/IBM/plex` v2.5.0 (2026-04-21), OFL 1.1 WITH Reserved Font
  Name "Plex" → never subset/modify (subsetting = modification = RFN violation). Statics
  v2.5: Regular 173,052 / Medium 174,008 / SemiBold 174,608 B.
- Stitch HTML itself loads: Spline Sans + Inter + IBM Plex Mono. Inter maps to iOS system SF.
- Flutter: static TTFs with explicit `weight:` in pubspec (no filename inference, no
  fake-bold synthesis). ~0.8 MB total bundle cost — negligible. OFL-FAQ 1.20: include
  copyright statement + license text in-app (LicenseRegistry).
- Verify on intake: byte size + `shasum` + internal `usWeightClass` (600 vs 700).

### Glass performance (research agent, iPhone 12 / A14 / Impeller)
- Budget: **1–2 visible BackdropFilter sites** for 60fps. Blur cost = area × sigma,
  re-runs every frame content beneath changes.
- Never nest/stack independent BackdropFilters → use `BackdropGroup` + grouped filters.
- Never animate sigma; animate opacity/position instead. Wrap static glass in
  `RepaintBoundary`.
- Reduce Motion: `MediaQuery.accessibilityFeaturesOf(context).reduceMotion` —
  `MediaQueryData.disableAnimations` maps Android, NOT iOS.
- Reduce Transparency: **no Flutter API** (issue #190318, open) → ship opaque fallback
  theme path; set `BackdropFilter.enabled: false` in that mode.
- Skip glassmorphism pub packages (all abandoned or gradient-only). Mature alternative
  for static frost = pre-rendered assets; not needed here (premium-gradient is solid).

### Market / design trends (research agent, 2025–2026)
- "One big thing first" (Oura 2025 redesign): Today leads with exactly one decision;
  everything else one tap deeper.
- Baseline-deviation coloring (Whoop/Oura): color = deviation from personal baseline,
  never absolute values. Ranges over point values.
- Apple's own Liquid Glass guidance: glass on navigation/controls only, never content
  cards; NN/g concurs ("spectacle over usability" when overused). Apple walked back
  default transparency in iOS 26.1/26.2.
- Dark-mode data-viz: elevation via lightness steps (not shadows), desaturated accents,
  tabular figures for all changing numbers, one foreground hue at multiple opacities.
- Motion norms: 160ms micro / 240ms standard / ≤360ms emphasis (matches existing
  TracendMotion tokens); exits faster than entries; nothing animates idle; Reduce Motion
  swaps to crossfade/instant.
- AI trust: Whoop Coach hallucination backlash — AI output must be visually distinct from
  measured data, confidence wording mandatory, never invent numbers.
- Anti-patterns to avoid: data overload (≤5–7 elements default view), dead buttons,
  glass overuse, shame mechanics, correlation sold as insight.

### Repo mechanics (explore agent)
- Data flow: constructor-injected repository interfaces + `FutureBuilder`; `Supabase*`
  real / `Fixture*` fallback; futures in `initState`, re-assigned on refresh. Backend
  failure → degraded fallback card (architecture rule 4).
- 36 RPCs consumed from Flutter; 9 Edge Functions for AI keys/external APIs/privileged ops.
- Theme: `TracendColors extends ThemeExtension` read via `context.tracendColors`;
  `TracendSpacing/Radii/Motion` static token classes.
- Tests: plain flutter_test, hand-written fake repos, fixed viewport 390×844,
  `test/contract/` fixture-based shape verification.
- CI: deno fmt/lint/test + flutter analyze/test + iOS build + migration collision check.
  Deploy auto-triggers on push to `feature/feature-engine`.

### Feature audit (explore agent) — what v2 must surface
**Orphaned widgets to WIRE:**
- `TrajectoryLens` (lib/shared/widgets/trajectory_lens.dart) — gallery/test only
- `MetricSparkline` (lib/shared/widgets/metric_sparkline.dart) — test only

**Orphaned widgets to DELETE:**
- `ComingSoonButton` (tracend_scaffold.dart:239) — zero usages
- `MiniTrendChart` (tracend_scaffold.dart:389) — zero usages
- `MetricRow` — gallery-only (keep in gallery, no production wiring needed)

**Display-only ListTiles to wire or justify (7):**
- account_screen.dart:263 (conversation row in delete sheet — trailing delete is the action; justify)
- coach_screen.dart:601 (evidence item row)
- coach_screen.dart:668 (coach context source row)
- train_screen.dart:400 (recent session row → WorkoutDetailScreen)
- train_screen.dart:836 (_ProgressionRow)
- progress_screen.dart:190 (progression row)
- today_screen.dart:694 (_BriefEvidence row)

**Phase-4 widgets already wired (restyle, don't rebuild):**
- RecoveryRing → today_screen.dart:141
- SleepArchitectureCard → today_screen.dart:268
- TrainingLoadGauge → train_screen.dart:268
- WeightTrendIndicator → progress_screen.dart:125
- EvidenceTrendChart → today_screen.dart:950, progress_screen.dart:608

**AI Usage RPC reality** (`get_my_ai_usage`, migration 20260702090000):
returns ONLY `period, successful_runs, failed_runs, estimated_cost_usd` (+ budget state:
`today_requests, daily_limit, warning_threshold_usd, hard_stop_usd`). No token counts,
no per-feature breakdown → Stitch mock rows omitted.

---

## Chunk 0 — Foundation (docs + tokens + fonts + glass + motion)

### 0.1 Authority docs FIRST (same commit as tokens)
- `docs/DESIGN_SYSTEM.md §3.2`: permit Spline Sans (display/headlines only) +
  IBM Plex Mono (data values only); body/labels remain system SF. Document OFL inclusion.
- `docs/DESIGN_SYSTEM.md §3.4`: permit (a) premium-gradient SOLID fills on evidence cards
  (tonal separation, zero blur); (b) restrained glass on: top app bar, confidence pill,
  tab capsule (existing exception). Max 2 BackdropFilter sites app-wide. Content cards
  and charts never use BackdropFilter.
- `docs/DESIGN_SYSTEM.md §10`: update anti-pattern list (remove contradiction, add
  "glass on content cards" and "fabricated metrics" as explicit anti-patterns).
- `docs/handoff/design.md` + `docs/PROGRESS_CONTEXT.md`: active change = Phase 5 v2.

### 0.2 Tokens (`tracend_tokens.dart`) — Stitch hexes, contrast-guarded

| Token | Current | New | Rationale |
|---|---|---|---|
| canvas | `#090D14` | `#080B10` | Stitch canvas |
| surface | `#121925` | `#111827` | Stitch base-surface |
| surfaceRaised | `#182130` | `#1A222F` | Stitch elevated-surface |
| textSecondary | `#AAB5C5` | `#8894A8` | Stitch; 6.4:1 on canvas ✓ AA (documented) |
| actionPrimary | `#9BA5FF` | `#8A94F5` | Stitch trajectory-indigo |
| stateStable | `#59D6C7` | `#45C4B5` | Stitch stable-teal |
| borderSubtle | `#293446` | **KEEP** | Stitch `#1F2937` = 1.21:1 invisible → rejected |
| NEW borderHairline | — | `#2D3748` | 0.5px decorative borders only |
| NEW accentAmber | — | `#E2A45C` | nutrition accent (kills 13× duplicate) |
| NEW accentNow | — | `#BCE85D` | NOW indicator only |

Light theme: keep current values (Stitch is dark-only; light stays Phase-4 baseline).
Update `theme_test.dart` contrast assertions for new pairings.

### 0.3 Fonts
1. Download genuine statics:
   - `https://raw.githubusercontent.com/SorkinType/SplineSans/main/fonts/ttf/SplineSans-{Regular,Medium,SemiBold,Bold}.ttf`
   - IBM Plex Mono v2.5.0 release zip → `IBMPlexMono-{Regular,Medium,SemiBold}.ttf`
2. Verify: byte sizes match research table; `shasum`; no two files byte-identical;
   internal weight class 600 vs 700 for SemiBold/Bold.
3. `assets/fonts/` + `pubspec.yaml` explicit weights:
   ```yaml
   flutter:
     fonts:
       - family: Spline Sans
         fonts:
           - asset: assets/fonts/SplineSans-Regular.ttf
           - asset: assets/fonts/SplineSans-Medium.ttf
             weight: 500
           - asset: assets/fonts/SplineSans-SemiBold.ttf
             weight: 600
           - asset: assets/fonts/SplineSans-Bold.ttf
             weight: 700
       - family: IBM Plex Mono
         fonts:
           - asset: assets/fonts/IBMPlexMono-Regular.ttf
           - asset: assets/fonts/IBMPlexMono-Medium.ttf
             weight: 500
           - asset: assets/fonts/IBMPlexMono-SemiBold.ttf
             weight: 600
   ```
4. OFL texts → `assets/fonts/OFL-SplineSans.txt` + `assets/fonts/OFL-IBMPlex.txt`,
   registered via `LicenseRegistry.addLicense` in main.dart.
5. Theme wiring (`tracend_theme.dart`):
   - Remove hardcoded `fontFamily: '.SF Pro Text'` base override
   - displayLarge→titleMedium: `fontFamily: 'Spline Sans'`
   - body/label styles: NO fontFamily (system SF)
   - `TracendFonts.monoFamily = 'IBM Plex Mono'` constant for data call sites only
   - Keep `tabularFigures()` on labelMedium + all mono data styles

### 0.4 Shared widgets
- `lib/shared/widgets/tracend_glass.dart` — `TracendGlass`: ClipRRect → BackdropFilter
  (σ24) → 72% surface fill + 1px 10% white inner border + 8% top-highlight gradient.
  `RepaintBoundary` wrapped. Opaque fallback when reduce-transparency mode active
  (app-level flag, since no Flutter API) or when `enabled: false`.
  Used ONLY at: top app bar, confidence pill, tab capsule.
- `lib/shared/widgets/premium_gradient_card.dart` — `PremiumGradientCard`: solid 145°
  LinearGradient (surface@80% → canvas@90%), hairline border, 24pt radius, optional
  decorative corner glow (paint-only radial gradient, zero blur). The Stitch
  evidence-card surface. NO BackdropFilter.
- `lib/shared/widgets/micro_motion.dart` — `MicroMotion`: spring entrance
  (stiffness 100, damping 20), scroll-stagger helper, pulse loop. ALL gated on
  `MediaQuery.accessibilityFeaturesOf(context).reduceMotion` (iOS-correct API).

### 0.5 Tests FIRST
- `test/theme_test.dart` update: new token contrast pairs pass AA
- `test/fonts_test.dart` (new): font families load (loadFontFromList or
  fontFamily presence in TextTheme), weights distinct
- `test/widgets/tracend_glass_test.dart` (new): renders, fallback mode opaque,
  respects enabled flag
- `test/widgets/premium_gradient_card_test.dart` (new): renders, no BackdropFilter
  in tree (assert via find.byType)
- `test/widgets/micro_motion_test.dart` (new): reduce-motion → no animation controllers
  running

### 0.6 Gate
```sh
./scripts/flutter.sh analyze
./scripts/flutter.sh format --set-exit-if-changed lib test
./scripts/flutter.sh test
```
→ commit → `/review`

---

## Chunk 1 — Today Screen (hero)

### Data-binding contract (every number traces to a repo field)

| Stitch element | Real data source | Cold-start/null state |
|---|---|---|
| Confidence pill | `brief.computed.dataConfidence` | "Building baseline" (cold_start) |
| Decision headline | `brief.nextAction` | "Keep the approved plan." |
| Reason text | `brief.reason` | deterministic fallback text |
| Sync timestamp | `brief.health['local_date']` / decision `createdAt` | hidden |
| TrajectoryLens bezier | `computed.scores` (sleep/strain/recovery normalized) | decorative static path, labeled as such |
| Sleep Architecture card | `SleepArchitectureCard` (existing, real) restyled into PremiumGradientCard; `sleep_breakdown.*`, baselines HRV/RHR z-scores | "Not enough data" |
| Session Plan card | `brief.workout` name/objective; set/movement counts from workout exercises fold (pattern: train_screen.dart:629) | "No session planned" |
| Metabolic Target card | `brief.nutrition` + NutritionSummary/Targets (kcal, protein, remaining — computed) | targets only, no consumed |
| T-Coach / N-Coach toggle | REAL: switches `CoachDecision.trainingSummary` ↔ `nutritionSummary` | hidden if no decision |
| Coach insight card | `CoachDecision.finalDecision/reason/confidence` + `modelProvider` | hidden; NEVER fake "v2.4" |
| Check-in bar | → `showCheckInSheet` (exists) | — |
| Start session | → active workout flow (exists) | disabled if no workout |
| View analytics | → Progress tab (real navigation) | — |
| RecoveryRing | kept (Phase 4, real) | existing cold-start state |

### TrajectoryLens rewrite spec
- `CustomPainter` bezier path + `PathMetric` draw-on (1.5s, easeOutCubic)
- `AnimatedBuilder` — NO setState-per-frame
- Precompute bezier constants; ≤200 samples
- Data dots: Sleep→Train→Fuel→Now from `computed.scores`; NOW dot = accentNow + glow pulse
- reduceMotion → static full path, no draw animation
- Labels: 9px caps, system font, 0.2em tracking; Semantics label describes values
- Values passed explicitly (`bezierValues` param actually consumed this time)

### Layout (Stitch today.html, top to bottom)
1. Top bar: "Tracend" + date + account avatar (TracendGlass)
2. Hero: confidence pill (TracendGlass) + sync timestamp · headline (Spline Sans 32–42pt)
   · reason · TrajectoryLens (280pt) · [Start session] [View analytics]
3. "PRECISION READOUTS" stylized divider
4. Sleep Architecture (PremiumGradientCard)
5. Session Plan (PremiumGradientCard)
6. Metabolic Target (PremiumGradientCard)
7. Coach perspective: T-Coach/N-Coach segmented + insight card
8. Check-in prompt bar
9. Existing health evidence section kept below (real data, restyled)

### Rules
- State table per widget BEFORE code (full / cold_start / null / low-confidence)
- No `onPressed: () {}` anywhere; every chevron navigates or is deleted
- Flexible/FittedBox chip rows — no Row overflow at 320pt
- Tests: per-widget state tables + smoke 320/375pt + a11y scaling

### Gate
analyze + format + test (incl. frontend_smoke_test at both widths) → commit → `/review`

---

## Chunk 2 — Train + Nutrition

### Train
- `DatePillStrip` (new, lib/shared/widgets/): week navigation with REAL chevron offset
  state, normalized-date Set lookup, const constructors, Dynamic-Type-safe widths
- TrainingLoadGauge (exists, real ACWR) restyled into PremiumGradientCard context
- Session bars from real workout data (no `clamp(3,6)` fabrication)
- Recent session row (train_screen.dart:400) → wire to WorkoutDetailScreen
- _ProgressionRow (train_screen.dart:836) → wire or convert to non-interactive text

### Nutrition
- `TargetsGrid` (new, lib/shared/widgets/): real NutritionTargets (kcal/protein/carb/fat)
  with consumed from NutritionSummary; NO nested glass cells (solid cells)
- Meal cards restyled (PremiumGradientCard), metabolic bar gradient
- DatePillStrip reuse
- Macro bars keep readable `X / Yg` text + a11y role

### Gate → commit → `/review`

---

## Chunk 3 — Progress + Coach

### Progress
- WeightTrendIndicator (exists, real) restyled
- Body measurements section (real save_body_measurement RPC)
- Evidence rows with EvidenceTrendChart (exists, real)
- Progression row (progress_screen.dart:190) → wire or justify as display-only
- "Tap a history row" instruction → make rows tappable or remove instruction

### Coach
- CoachInsightCard: stroke inset by width/2, no per-frame rebuild, expansion for >6 lines
- Evidence accordion: fix collapse bug (animate height BEFORE removing content,
  evidence_accordion pattern rebuilt correctly)
- Evidence item row (coach_screen.dart:601) + context source row (:668) → wire or justify
- Styled composer + suggestion pills (PreferencePromptChip exists)
- Confidence always from `CoachDecision.confidence` — never hardcoded "medium"

### Gate → commit → `/review`

---

## Chunk 4 — AI Usage + Shell + Account

### My AI Usage screen (from Account)
- REAL fields only: successful_runs, failed_runs, estimated_cost_usd, today_requests,
  daily_limit, warning_threshold_usd, hard_stop_usd
- Cost labeled "operational estimate" (per AI_USAGE_PROMPT.md)
- OMITTED (don't exist in RPC): token counts, per-feature breakdown rows
- Period selector: only if RPC supports it (current_month only → single period, no
  dead toggle)
- States: loading / empty / stale / unavailable
- Budget text reconciled with server values (fixes $3/$5 vs $1/$2 mismatch)
- "Refresh usage" → real refetch (re-assign future)
- Never display API keys, prompts, raw errors, cross-user totals

### Shell
- Tab bar: KEEP 5 TABS (DESIGN_SYSTEM.md §4 mandates 5; Stitch's 4-tab rejected),
  restyle capsule with TracendGlass, tab motion via TracendMotion tokens (kill 350ms
  easeOutBack bypass)

### Account
- "Privacy and AI processing" row → wire to real destination or delete
- Conversation row in delete sheet (:263) → justify as display (trailing delete is action)
- DELETE: ComingSoonButton, MiniTrendChart (zero usages)

### Gate → commit → `/review`

---

## Chunk 5 — Motion + A11y + Final

### Animation pass (all reduceMotion-gated)
- Stagger entrances (cards), path draw (TrajectoryLens 1.5s), pulse dots, count-up on
  score changes, tab morph
- Exits ~15–30% faster than entries; nothing animates idle; press feedback <100ms

### A11y pass
- Dynamic Type 1.0 / 1.3 / largest — no truncation, wraps before truncating
- VoiceOver labels on all data viz (rings, gauges, sparklines, bezier)
- 44×44pt touch targets, 8pt between adjacent
- Contrast audit: every new token pairing ≥4.5:1 body / ≥3:1 large+graphics
- Bubble semantics restored ('Coach said' labels, color+semantics distinction)
- Color never the only signal (icons/text accompany state colors)

### Final gate
```sh
./scripts/flutter.sh analyze
./scripts/flutter.sh format --set-exit-if-changed lib test
./scripts/flutter.sh test
./scripts/deno.sh fmt --check supabase/functions
./scripts/deno.sh lint supabase/functions
./scripts/deno.sh test supabase/functions
./scripts/flutter.sh build ios --release --no-codesign
```
- iPhone manual pass: dark+light, reduce motion, Dynamic Type, 60fps scroll
- Docs final: PROGRESS_CONTEXT.md, handoff/frontend.md, UX_FLOWS.md (if nav changed)
- `/review` → `/test` → merge → auto-deploy

---

## Explicitly OUT of v2
- Welcome/onboarding screens (post-MVP — needs Apple Sign-in; 16 Stitch refs preserved)
- WorkoutModeSheet (would fabricate data — no real session-tracking backend yet)
- Any DB migration
- MetricRow production wiring (gallery specimen only)

## Anti-failure rules (from the 2026-08-18 audit — the ones that bit Phase 5 v1)
1. Authority docs amended FIRST in Chunk 0, never after, never silently overridden
2. Every number on screen traces to a repository/model field — binding tables above
   are the contract
3. State table per widget BEFORE code (full / cold_start / null / low-confidence)
4. No orphans, no no-ops, no dead affordances — wire it or delete it
5. Max 2 BackdropFilter sites app-wide; BackdropGroup if grouped
6. Tests written from code, never from plan
7. Per-chunk gate + `/review` before next chunk starts
8. Missing/conflicting data lowers confidence; never silently invented
