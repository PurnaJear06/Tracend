# Tracend Design System

**Status:** Authoritative MVP experience and visual direction  
**Platform:** Flutter for iOS, private TestFlight beta  
**Working brand:** Tracend, pending trademark and App Store name clearance

This document translates [PRD.md](./PRD.md) into a coherent interface system. Screen behavior is defined in [UX_FLOWS.md](./UX_FLOWS.md). Safety and uncertainty language remains governed by [AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md).

## 1. Experience Thesis

Tracend should feel like a precise coaching instrument that becomes calm when the next action is clear. It is not a motivational chatbot, bodybuilding game, generic wellness dashboard, or science-fiction control panel.

“Modern 2027” means:

- anticipatory hierarchy that puts the next useful action first;
- data that explains a decision instead of competing for attention;
- fluid, interruptible transitions with spatial continuity;
- polished light and dark themes;
- confidence, freshness, and missing-data states as first-class content; and
- personalization through real plans and evidence, not decorative AI effects.

## 2. Visual Direction: Kinetic Precision

The visual language combines the discipline of a training log, the accuracy of an instrument readout, and the physical momentum implied by the Tracend name.

### Signature element: the Trajectory Lens

The Trajectory Lens is a narrow continuous path connecting recent evidence to the current coaching decision. It appears on Today, expands into decision evidence, and can continue into a proposed plan change.

It is not a readiness score or decorative progress ring. Each marked point represents real evidence such as recovery, recent execution, nutrition adherence, or trend data. Tapping a point reveals its source, freshness, window, and influence. The final segment terminates at one labeled action: maintain, adjust today, gather data, or review proposal.

The lens is the one deliberate aesthetic risk. Other surfaces remain quiet so it retains meaning.

## 3. Brand Tokens

Implementation uses semantic tokens. Raw color values must not appear in feature widgets.

### 3.1 Core palette

| Token name | Light reference | Dark reference | Purpose |
|---|---:|---:|---|
| Polar canvas | `#F3F6F8` | `#090D14` | App background |
| Lifted surface | `#FFFFFF` | `#121925` | Cards and sheets |
| Carbon ink | `#10151D` | `#F4F7FB` | Primary text and icons |
| Slate signal | `#556170` | `#AAB5C5` | Secondary text |
| Trajectory indigo | `#4A57E8` | `#9BA5FF` | Brand action and selection |
| Recovery teal | `#00796B` | `#59D6C7` | Stable/recovered state |
| Effort coral | `#C43C31` | `#FF887D` | Warning, pain, or attention |

Semantic roles include `canvas`, `surface`, `surfaceRaised`, `textPrimary`, `textSecondary`, `borderSubtle`, `actionPrimary`, `actionOnPrimary`, `stateStable`, `stateAttention`, `stateDanger`, `focusRing`, and `scrim`.

- Body text must meet WCAG AA 4.5:1 contrast; large text and meaningful graphics must meet 3:1.
- Stable, attention, danger, confidence, and selection always include text or iconography; color is never the only signal.
- Gradients may appear only inside the Trajectory Lens and must encode direction or transition.
- Blur is reserved for modal separation and camera overlays, never ambient decoration.

### 3.2 Typography

| Role | Preferred face | Use |
|---|---|---|
| Brand/display | iOS system San Francisco, 600–700 | Short titles and decision statements |
| Interface/body | iOS system San Francisco | Controls, forms, explanations, long text |
| Data/utility | iOS system San Francisco with tabular figures | Loads, reps, macros, dates, confidence and sources |

No production custom font is required. Every text style maps to Dynamic Type,
wraps before truncating, and is tested at the largest accessibility sizes.
Tabular figures are required for changing values and timers.

### 3.3 Layout, spacing, and shape

- Base spacing unit: 4pt; normal rhythm: 8, 12, 16, 24, 32, and 48pt.
- Phone gutter: 20pt; compact phone: 16pt; tablet content is width-constrained.
- Minimum touch target: 44×44pt with at least 8pt between adjacent targets.
- Corner radii: 12pt controls, 18pt cards, 26pt primary decision surfaces; capsules only for compact status.
- Use one primary action per screen. Bottom actions include safe-area padding and never cover content.
- Avoid nested scrolling, edge controls that conflict with system gestures, and dense edge-to-edge charts.

### 3.4 Elevation and material

Hierarchy comes primarily from spacing, contrast, and borders. Use only three elevation levels: canvas, raised card, and modal. Shadows are soft and low-opacity; dark mode uses tonal separation. Glassmorphism and glow are prohibited as default content-surface treatments. The primary iPhone tab bar is the sole exception: it may use a restrained floating capsule material so navigation remains visually separate from scrolling content. Content cards remain solid and evidence-focused.

## 4. Navigation

The primary iOS tab bar has five labeled destinations:

1. **Today** — decision, check-in, schedule, and pending action;
2. **Train** — active plan, workout execution, and history;
3. **Coach** — direct user questions, current decision explanation, evidence, and proposal review entry points;
4. **Nutrition** — targets, confirmed meals, and meal capture;
5. **Progress** — measurements, reviews, trends, and progress photos.

Profile, current goal, connections, sanitized AI usage, privacy, export, and
deletion live under the account control on Today. Account is a native grouped
detail screen, not a sixth tab. It may show AI service status and user-scoped
usage but never an API-key field. Coach is a top-level destination, but it
remains one controlled coaching workflow. Do not represent Training Coach,
Nutrition Coach, and Head Coach as separate autonomous chatbots; show them only
as expandable perspectives inside a unified Tracend Coach response.

Native back behavior, swipe-back, tab-state preservation, deep links, and restoration after interruption are mandatory.

On iPhone, the five destinations sit in one safe-area-aware floating capsule.
Selection uses a compact tonal indicator, filled icon, label-weight change, and
160–240ms interruptible motion. The bar never hides scroll content, preserves
all tab state, and becomes a width-constrained regular layout on larger widths.

## 5. Core Components

### `TrajectoryLens`

Shows evidence groups, freshness, confidence, and final decision class. It expands by tap, supports VoiceOver as an ordered evidence summary, and has a static reduced-motion form.

### `DecisionSurface`

Contains one direct headline, one reason, timestamp, confidence wording, primary action, and **See evidence**. It never hides a pending persistent change inside normal advice.

### `CoachPerspectiveCard`

Training and nutrition perspectives are collapsed summaries below the final decision. Opening a card reveals evidence and limits, not simulated chat personas.

### `EvidenceRow`

Displays label, value, unit, source, time window, freshness, and status. Missing data reads **Not enough data** with a recovery action; it never displays a fabricated zero.

### `ProposalDiff`

Shows current and proposed values, effective date, evidence, downside, uncertainty, and separate Accept, Reject, and Request revision actions. Accept is never preselected.

### `WorkoutSetRow`

Optimized for one-handed use: set number, load, reps, RPE, completion, and pain access. Numeric entry uses the correct keyboard, retains the previous set as reference, and works offline.

### `MealCandidateEditor`

Separates AI-observed foods from confirmed catalog items. Every candidate shows editable amount, preparation assumption, confidence, and unresolved questions. Totals update only after confirmation.

### `MetricTrend`

Uses a line for time trend, a range band for uncertainty where applicable, explicit units, direct labels for small data sets, and a text summary for VoiceOver. Charts never use red versus green alone.
Planned values, sample fixtures, and unrelated metrics never appear as an
observed trend. Two real dated observations are the minimum rendering gate.

### `UsageSummary`

Shows a named time window, authenticated-user request count, token/image usage
when meaningful, estimated cost, and service state. Values are labeled
**Estimate**, never presented as billing authority, and never expose keys,
prompts, request identifiers, or raw provider errors.

### `CoachMessage` and `MealScheduleTimeline`

Coach messages use a restrained familiar bubble shape, selectable text, and an
expandable evidence drawer; the pinned daily decision remains a separate solid
surface. Meal schedule rows use time, label, planned quantities, and explicit
status. Neither component uses color as the only state signal.

## 6. Motion and Haptics

Motion explains hierarchy and causality. It does not decorate idle screens.

| Token | Duration | Use |
|---|---:|---|
| `motion.quick` | 160ms | Press, selection, compact feedback |
| `motion.standard` | 240ms | Expand/collapse, crossfade, row changes |
| `motion.emphasis` | 360ms max | Lens resolution, shared-element transition |

- Use interruptible spring motion and transform/opacity where possible.
- Forward navigation moves deeper; backward navigation reverses direction.
- Exit duration is shorter than entry duration.
- Loading under 300ms has no spinner; longer waits use reserved-space skeletons; long AI/media work shows named progress and permits leaving.
- Reduced Motion removes path morphing, parallax, and stagger while preserving immediate state change.
- Haptics are limited to set completion, successful confirmation, accepted proposal, and safety-critical warning.

## 7. States and Feedback

Every data-driven component defines loading, ready, empty, partial, stale, offline, failed, and permission-denied states.

- Errors state what happened and the recovery action.
- Empty states contain one useful next step, not motivational filler.
- Destructive actions are separated and require confirmation.
- Long forms autosave drafts; dismissing unsaved changes requires confirmation.
- Pending, confirmed, AI-estimated, and user-entered data are visually and verbally distinct.
- Press feedback appears within 100ms and never shifts neighboring layout.

## 8. Accessibility Baseline

- VoiceOver order matches visual order; custom charts and the lens expose concise summaries.
- All controls have labels, hints where useful, and selected/disabled/expanded traits.
- Dynamic Type works through accessibility sizes without losing actions or values.
- Bold Text, Button Shapes, Increase Contrast, Differentiate Without Color, and Reduce Motion are supported.
- Progress photos never receive automated appearance labels in general navigation.
- Landscape, small phones, large phones, and iPad-compatible layouts remain operable.

## 9. Writing Style

Tracend is direct, calm, specific, and nonjudgmental.

- **Keep today’s plan** instead of “You’re crushing it.”
- **Sleep data is missing. Add a check-in to improve this decision** instead of “Insufficient context.”
- **Review proposed calorie target** instead of “AI optimized your diet.”
- Buttons use outcome verbs: **Start workout**, **Confirm meal**, **Accept change**, and **Delete account**.
- Never use shame, physique ranking, fake urgency, streak loss, or medical certainty.

## 10. Anti-Patterns

Do not use:

- black-and-neon gym styling, chrome textures, flames, or aggressive bodybuilding motifs;
- generic activity rings, meaningless readiness scores, or dashboard walls;
- animated AI sparkles, robot imagery, or chat bubbles as the primary coaching interface;
- frosted-glass cards across every screen;
- emoji as icons, mixed icon families, or unlabeled icon-only navigation;
- confetti for health behavior, manipulative streaks, or red failure states for missed workouts; or
- motion that delays input, hides loading, or cannot be disabled.

## 11. Design Review Gate

Before a screen is implementation-complete:

- compare it to [UX_FLOWS.md](./UX_FLOWS.md);
- use only semantic tokens and approved components;
- verify light/dark contrast, 44pt targets, safe areas, keyboard behavior, VoiceOver, Dynamic Type, and Reduced Motion;
- test loading, empty, partial, stale, offline, error, and permission-denied states;
- confirm one clear primary action; and
- remove treatments that do not communicate structure, evidence, state, or action.
