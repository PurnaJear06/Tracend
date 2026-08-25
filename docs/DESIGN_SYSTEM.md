# Tracend Design System

## Train Spacing Rule

Do not combine a trailing card spacer with the next section label's leading spacer. Use one 8-point
inter-card gap and one 24-point section boundary, with minimum 44-point hit targets for interactive
exercise rows.

### Evidence visualization

Today leads with two evidence surfaces (Chunk 6): the full-width `RecoveryReadoutCard`
(tabular recovery score, band chip, and five driver rows with z-score bars — fill clamps
z to ±2 for layout while labels and semantics report the true z) and `TrajectoryTrend`, a
real 7-day line chart from `daily_health_summaries` (HRV → sleep → resting HR priority,
≥4 recorded days required, window anchored to the latest stored day, gaps left visible,
never interpolated). They replace the earlier centered recovery ring, three-tile
readiness strip, and today-only trajectory lens. The shared `EvidenceTrendChart` uses
linear segments, actual date spacing, visible numeric scale, current value and optional
average line; within it, curved interpolation, unlabeled auto-scaling, and
spreadsheet-style equal metric grids are prohibited. (`TrajectoryTrend` is the one
sanctioned bezier surface — it smooths only between real recorded days, never across
missing ones.)
Weight charts show confirmed raw weigh-ins as dots; the raw dots are never smoothed. Computed
trend overlays are permitted only as labeled regression line segments derived from the server
OLS slopes (`ALGORITHMS.md` §5): they must be anchored to real measurements (no invented
intercept, no extrapolation), distinguished from the dots by a legend ("Measured" vs computed
lines), and render low-confidence fits (28-day R² < 0.3 or missing R²) dashed and labeled
"low confidence". The 7-day line carries no R² and is never confidence-gated.

**Status:** Authoritative MVP experience and visual direction\
**Platform:** Flutter for iOS, private TestFlight beta\
**Working brand:** Tracend, pending trademark and App Store name clearance

This document translates [PRD.md](./PRD.md) into a coherent interface system. Screen behavior is
defined in [UX_FLOWS.md](./UX_FLOWS.md). Safety and uncertainty language remains governed by
[AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md).

## 1. Experience Thesis

Tracend should feel like a precise coaching instrument that becomes calm when the next action is
clear. It is not a motivational chatbot, bodybuilding game, generic wellness dashboard, or
science-fiction control panel.

“Modern 2027” means:

- anticipatory hierarchy that puts the next useful action first;
- data that explains a decision instead of competing for attention;
- fluid, interruptible transitions with spatial continuity;
- polished light and dark themes;
- confidence, freshness, and missing-data states as first-class content; and
- personalization through real plans and evidence, not decorative AI effects.

## 2. Visual Direction: Kinetic Precision

The visual language combines the discipline of a training log, the accuracy of an instrument
readout, and the physical momentum implied by the Tracend name.

### Signature element: the 7-day trend

The signature data moment on Today is `TrajectoryTrend` (Chunk 6): a luminous bezier
through the last seven stored days of one real HealthKit metric (HRV preferred, then
sleep duration, then resting heart rate), with an area fill, real point dots, restrained
min/max/date labels, a draw-on reveal, and a pulsing marker on the latest recorded day.
It plots only recorded days — gaps stay visible, missing days are never interpolated —
and when fewer than four recorded days exist it degrades to an honest "Building baseline"
card rather than drawing a fabricated curve.

The trend never shows invented metrics or smoothed-away gaps. The recovery readout and
readiness factors remain authoritative and accessible.

The trend is the one deliberate aesthetic risk. Other surfaces remain quiet so it retains
meaning. (It supersedes the earlier hero "trajectory lens", which plotted only today's
computed signals.)

## 3. Brand Tokens

Implementation uses semantic tokens. Raw color values must not appear in feature widgets.

### 3.1 Core palette

| Token name        | Light reference | Dark reference | Purpose                     |
| ----------------- | --------------: | -------------: | --------------------------- |
| Polar canvas      |       `#F3F6F8` |      `#080B10` | App background              |
| Lifted surface    |       `#FFFFFF` |      `#111827` | Cards and sheets            |
| Carbon ink        |       `#10151D` |      `#F4F7FB` | Primary text and icons      |
| Slate signal      |       `#556170` |      `#8894A8` | Secondary text              |
| Trajectory indigo |       `#4A57E8` |      `#8A94F5` | Brand action and selection  |
| Recovery teal     |       `#00796B` |      `#45C4B5` | Stable/recovered state      |
| Effort coral      |       `#C43C31` |      `#FF887D` | Warning, pain, or attention |

Dark references follow the approved "Precision Pro" Stitch direction
(`design/stitch/screens/`); light theme keeps the Phase-4 baseline. Additional dark-only
tokens: `borderHairline` `#2D3748` (decorative 0.5–1px borders, never the sole affordance
signal), `accentAmber` `#E2A45C` (nutrition domain accent), `accentNow` `#BCE85D` (NOW
indicator dot only). `borderSubtle` stays `#293446` in dark — the Stitch `#1F2937` measures
≈1.2:1 against canvas and is rejected as invisible.

Semantic roles include `canvas`, `surface`, `surfaceRaised`, `textPrimary`, `textSecondary`,
`borderSubtle`, `borderHairline`, `actionPrimary`, `actionOnPrimary`, `accentAmber`,
`accentNow`, `stateStable`, `stateAttention`, `stateDanger`, `focusRing`, and `scrim`.

- Body text must meet WCAG AA 4.5:1 contrast; large text and meaningful graphics must meet 3:1.
- Stable, attention, danger, confidence, and selection always include text or iconography; color is
  never the only signal.
- Gradients may appear inside the 7-day trend and data visuals when they encode direction or
  improve native-text contrast.
- Blur is reserved for modal separation and camera overlays, never ambient decoration.

### 3.2 Typography

| Role           | Preferred face                                | Use                                                |
| -------------- | --------------------------------------------- | -------------------------------------------------- |
| Brand/display  | Spline Sans, 500–700                          | Screen titles, section titles, decision headlines  |
| Interface/body | iOS system San Francisco                      | Controls, forms, explanations, long text, labels   |
| Data/utility   | IBM Plex Mono with tabular figures            | Loads, reps, macros, dates, confidence and sources |

Custom fonts (Phase 5 v2, "Precision Pro"): Spline Sans (SIL OFL 1.1, SorkinType) is used
for display/headline roles only; IBM Plex Mono (SIL OFL 1.1 with Reserved Font Name "Plex",
IBM) is used for data values only. Body text and labels remain iOS system San Francisco.
Both OFL license texts ship in `assets/fonts/` and are registered via `LicenseRegistry`.

Stitch type-scale mapping: screen-title 24/32 w600 · section-title 18/24 w600 ·
decision-headline 42, line-height 1.05, letter-spacing −0.03em, w600 · body-base 17/25 w300 ·
body-compact 14/20 w300 · data-utility 13/18 w400 (mono) · label-caps 11/16, letter-spacing
0.08em, w500.

Every text style maps to Dynamic Type, wraps before truncating, and is tested at the largest
accessibility sizes. Tabular figures are required for changing values and timers.

### 3.3 Layout, spacing, and shape

- Base spacing unit: 4pt; normal rhythm: 8, 12, 16, 24, 32, and 48pt.
- Phone gutter: 20pt; compact phone: 16pt; tablet content is width-constrained.
- Minimum touch target: 44×44pt with at least 8pt between adjacent targets.
- Corner radii (shape lock): 12pt controls, 24pt cards, 28pt primary decision surfaces;
  capsules (full radius) only for compact status pills and chips. No mixing outside this rule.
  Documented exception: Coach chat bubbles use an asymmetric 18pt bubble (4pt on the tail
  corner) — a restrained, familiar conversational shape, not a card or control.
- Use one primary action per screen. Bottom actions include safe-area padding and never cover
  content.
- Avoid nested scrolling, edge controls that conflict with system gestures, and dense edge-to-edge
  charts.

### 3.4 Elevation and material

Hierarchy comes primarily from spacing, contrast, and borders. Use only three elevation levels:
canvas, raised card, and modal. Shadows are soft and low-opacity; dark mode uses tonal separation.

Material treatments (Phase 5 v2, "Precision Pro"):

- **Premium gradient cards** — evidence/content cards use a solid tonal gradient fill
  (surface → canvas direction, hairline border, 24pt radius) with optional paint-only corner
  glow. Zero blur. This is the default content-surface treatment.
- **Restrained glass** — permitted ONLY on chrome: the floating tab capsule, the top app bar,
  and the confidence pill. Maximum 2 visible `BackdropFilter` sites app-wide; group with
  `BackdropGroup` if adjacent; never animate blur sigma; wrap static glass in
  `RepaintBoundary`. An app-level reduce-transparency flag (no Flutter API exists) switches
  glass to an opaque `surfaceRaised` fallback.
- Content cards, charts, and data visuals NEVER use `BackdropFilter`.
- Glassmorphism and glow remain prohibited as ambient decoration; the sanctioned glass sites
  above are the complete list.

## 4. Navigation

The primary iOS tab bar has five labeled destinations:

1. **Today** — decision, check-in, schedule, and pending action;
2. **Train** — active plan, workout execution, and history;
3. **Coach** — direct user questions, current decision explanation, evidence, and proposal review
   entry points;
4. **Nutrition** — targets, confirmed meals, and meal capture;
5. **Progress** — measurements, reviews, trends, and progress photos.

Profile, current goal, connections, sanitized AI usage, privacy, export, and deletion live under the
account control on Today. Account is a native grouped detail screen, not a sixth tab. It may show AI
service status and user-scoped usage but never an API-key field. Coach is a top-level destination,
but it remains one controlled coaching workflow. Do not represent Training Coach, Nutrition Coach,
and Head Coach as separate autonomous chatbots; show them only as expandable perspectives inside a
unified Tracend Coach response.

Native back behavior, swipe-back, tab-state preservation, deep links, and restoration after
interruption are mandatory.

On iPhone, the five destinations sit in one safe-area-aware floating capsule. Selection uses a
compact tonal indicator, filled icon, label-weight change, and 160–240ms interruptible motion. The
bar never hides scroll content, preserves all tab state, and becomes a width-constrained regular
layout on larger widths.

## 5. Core Components

### `RecoveryReadoutCard`

Full-width recovery readout on Today (Chunk 6): tabular score with `/ 100`, a band chip
(Excellent/Good/Moderate/Low/Poor), and five driver rows (HRV, RHR, Sleep, Resp, Strain)
with horizontal z-score bars and signed z values. Bar fill clamps z to ±2 for layout;
labels and semantics always report the true z-score. Cold start shows `--` with honest
next-step copy; low confidence adds "Building baseline". Replaces the earlier centered
recovery ring and the recovery tile of the readiness strip. Training load (ACWR) is not
part of this card — it renders as a display-only row inside `SessionPlanCard`.

### `TrajectoryTrend`

Real 7-day health trend on Today (Chunk 6): plots recorded days from
`daily_health_summaries` for one metric (priority HRV → sleep → resting HR; first with
≥4 recorded days in the window wins). Window = the 7 days ending at the latest stored
day. Bezier curve with area fill, real point dots, restrained min/max/date labels,
draw-on reveal, and the single sanctioned idle pulse on the latest recorded day. Missing
days stay visible as gaps and are never interpolated; fewer than four recorded days
renders the "Building baseline" cold-start card. Direction deltas (vs first recorded
day) are reported neutrally — up/down is fact, not good/bad.

### `DecisionSurface`

Contains one direct headline, one reason, timestamp, confidence wording, primary action, and **See
evidence**. It never hides a pending persistent change inside normal advice.

### `CoachPerspectiveCard`

Training and nutrition perspectives are collapsed summaries below the final decision. Opening a card
reveals evidence and limits, not simulated chat personas.

### `EvidenceRow`

Displays label, value, unit, source, time window, freshness, and status. Missing data reads **Not
enough data** with a recovery action; it never displays a fabricated zero.

### `ProposalDiff`

Shows current and proposed values, effective date, evidence, downside, uncertainty, and separate
Accept, Reject, and Request revision actions. Accept is never preselected.

### `WorkoutSetRow`

Optimized for one-handed use: set number, load, reps, RPE, completion, and pain access. Numeric
entry uses the correct keyboard, retains the previous set as reference, and works offline.

### `MealCandidateEditor`

Separates AI-observed foods from confirmed catalog items. Every candidate shows editable amount,
preparation assumption, confidence, and unresolved questions. Totals update only after confirmation.

### `MetricTrend`

Uses a line for time trend, a range band for uncertainty where applicable, explicit units, direct
labels for small data sets, and a text summary for VoiceOver. Charts never use red versus green
alone. Planned values, sample fixtures, and unrelated metrics never appear as an observed trend. Two
real dated observations are the minimum rendering gate.

### `UsageSummary`

Shows a named time window, authenticated-user request count, token/image usage when meaningful,
estimated cost, and service state. Values are labeled **Estimate**, never presented as billing
authority, and never expose keys, prompts, request identifiers, or raw provider errors.

### `CoachMessage` and `MealScheduleTimeline`

Coach messages use a restrained familiar bubble shape, selectable text, and an expandable evidence
drawer; the pinned daily decision remains a separate solid surface. Meal schedule rows use time,
label, planned quantities, and explicit status. Neither component uses color as the only state
signal.

## 6. Motion and Haptics

Motion explains hierarchy and causality. It does not decorate idle screens.

| Token             |  Duration | Use                                        |
| ----------------- | --------: | ------------------------------------------ |
| `motion.quick`    |     160ms | Press, selection, compact feedback         |
| `motion.standard` |     240ms | Expand/collapse, crossfade, row changes    |
| `motion.emphasis` | 360ms max | Lens resolution, shared-element transition |

- Use interruptible spring motion and transform/opacity where possible.
- Forward navigation moves deeper; backward navigation reverses direction.
- Exit duration is shorter than entry duration.
- Loading under 300ms has no spinner; longer waits use reserved-space skeletons; long AI/media work
  shows named progress and permits leaving.
- Reduced Motion removes path morphing, parallax, and stagger while preserving immediate state
  change.
- Haptics are limited to set completion, successful confirmation, accepted proposal, and
  safety-critical warning.

Implemented motion (all gated on `MediaQuery.disableAnimationsOf`, all motivated):

- Card entrances on Today stagger 60ms per index (`MicroMotion.stagger`, capped at 8 indices) via
  `MicroMotionEntrance` (spring rise + fade, once on mount).
- The 7-day trend path draws over 1.5s; the latest-day dot carries the single sanctioned idle
  loop (`MicroMotionPulse`, gentle opacity pulse). Nothing else animates idle.
- Score values count up/down on change only (`MicroMotionCountUp`, 600ms ease-out); first render is
  static. Tabular figures keep digits from jittering during the transition.
- Tab capsule selection morphs in 160ms; tab labels clamp to 1.3× text scale (iOS tab bars keep
  labels near-fixed under Dynamic Type) so they never overflow the 70pt bar.

## 7. States and Feedback

Every data-driven component defines loading, ready, empty, partial, stale, offline, failed, and
permission-denied states.

- Errors state what happened and the recovery action.
- Empty states contain one useful next step, not motivational filler.
- Destructive actions are separated and require confirmation.
- Long forms autosave drafts; dismissing unsaved changes requires confirmation.
- Pending, confirmed, AI-estimated, and user-entered data are visually and verbally distinct.
- Press feedback appears within 100ms and never shifts neighboring layout.

## 8. Accessibility Baseline

- VoiceOver order matches visual order; custom charts and the 7-day trend expose concise summaries.
- All controls have labels, hints where useful, and selected/disabled/expanded traits.
- Dynamic Type works through accessibility sizes without losing actions or values.
- Bold Text, Button Shapes, Increase Contrast, Differentiate Without Color, and Reduce Motion are
  supported.
- Progress photos never receive automated appearance labels in general navigation.
- Landscape, small phones, large phones, and iPad-compatible layouts remain operable.

Audited implementation (Chunk 5):

- Every data viz exposes a semantics label: recovery readout and driver rows (true z-score per
  driver), sparklines, trend charts (measured vs computed distinguished), 7-day trend (metric,
  date range, first/last values, recorded-day count), intensity bar,
  targets grid, measurement deltas. Color is never the only signal — values and band names render
  as text beside every graphic.
- Touch targets are ≥44pt: IconButtons default to 48pt, date pills and week chevrons enforce 44pt,
  the tab capsule is 70pt tall, and all chips use padded tap targets (48pt).
- Dynamic Type is regression-tested at 1.3× and the largest iOS scale (~2.0×) at 320pt across all
  five tabs; layouts wrap before truncating (no overflow asserted).
- Contrast is asserted in tests: body text ≥4.5:1 on surface and canvas, graphics/state tokens
  ≥3:1 on canvas, button labels ≥4.5:1 on the primary action fill — in both themes.

## 9. Writing Style

Tracend is direct, calm, specific, and nonjudgmental.

- **Keep today’s plan** instead of “You’re crushing it.”
- **Sleep data is missing. Add a check-in to improve this decision** instead of “Insufficient
  context.”
- **Review proposed calorie target** instead of “AI optimized your diet.”
- Buttons use outcome verbs: **Start workout**, **Confirm meal**, **Accept change**, and **Delete
  account**.
- Never use shame, physique ranking, fake urgency, streak loss, or medical certainty.

## 10. Anti-Patterns

Do not use:

- black-and-neon gym styling, chrome textures, flames, or aggressive bodybuilding motifs;
- generic activity rings, meaningless readiness scores, or dashboard walls;
- animated AI sparkles, robot imagery, or chat bubbles as the primary coaching interface;
- frosted-glass cards across every screen, or any glass/blur on content cards, charts, or
  data visuals (glass is chrome-only per §3.4);
- fabricated metrics, fake-precise numbers, or values that do not trace to a
  repository/model/RPC field;
- dead affordances — no-op chevrons, buttons, or rows that neither navigate nor act; wire it
  or delete it;
- hardcoded confidence strings or model-version labels not sourced from `CoachDecision`;
- emoji as icons, mixed icon families, or unlabeled icon-only navigation;
- confetti for health behavior, manipulative streaks, or red failure states for missed workouts; or
- motion that delays input, hides loading, or cannot be disabled.

## 11. Design Review Gate

Before a screen is implementation-complete:

- compare it to [UX_FLOWS.md](./UX_FLOWS.md);
- use only semantic tokens and approved components;
- verify light/dark contrast, 44pt targets, safe areas, keyboard behavior, VoiceOver, Dynamic Type,
  and Reduced Motion;
- test loading, empty, partial, stale, offline, error, and permission-denied states;
- confirm one clear primary action; and
- remove treatments that do not communicate structure, evidence, state, or action.
