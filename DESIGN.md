# Tracend Product Design Brief

**Purpose:** Portable design context for Google Stitch and UI implementation agents  
**Platform:** iOS-first Flutter app, designed at 390 × 844pt and validated from 375pt upward  
**Product:** Tracend — an evidence-driven AI personal trainer  
**Tagline:** Your body. Your data. Your next move.  
**Brand status:** Working name pending trademark and App Store clearance

This is a design handoff, not a new source of product truth. Resolve behavior against [`docs/UX_FLOWS.md`](./docs/UX_FLOWS.md), visual tokens against [`docs/DESIGN_SYSTEM.md`](./docs/DESIGN_SYSTEM.md), scope against [`docs/PRD.md`](./docs/PRD.md), and AI language against [`docs/AI_SAFETY_SPEC.md`](./docs/AI_SAFETY_SPEC.md).

## Product and Audience

Tracend helps healthy adults aged 18+ follow a personalized training and nutrition plan. It combines approved plans, workout execution, confirmed meals, check-ins, optional HealthKit summaries, measurements, and progress evidence into one clear next action.

The app serves beginners who need guidance and experienced lifters who want valid current practices respected. It should feel credible throughout a five-to-six-month transformation and remain understandable when evidence is incomplete.

It is not a chatbot, medical service, bodybuilding game, generic activity tracker, or wall of analytics.

## Experience Thesis

Design Tracend as a **precise coaching instrument that becomes calm when the next action is clear**.

Every core screen answers, in this order:

1. What should I do now?
2. Why is that the right action?
3. What can I review or change?

Use progressive disclosure. The initial view is decisive and quiet; evidence expands on demand. Never hide missing data, stale evidence, AI estimation, or a persistent plan change.

### Visual direction: Kinetic Precision

Combine the discipline and compact notation of a training log, the calibration and traceability of an instrument readout, and the forward physical momentum implied by the Tracend name.

“Modern 2027” comes from anticipatory hierarchy, responsive transitions, and useful data—not science-fiction decoration.

## Signature Element: Trajectory Lens

The **Trajectory Lens** is a narrow continuous path connecting recent evidence to the current coaching decision.

Each point represents real evidence, such as sleep, workout execution, nutrition adherence, recovery check-in, or weight trend. The final segment terminates at one labeled action:

- Maintain plan
- Adjust today
- Gather data
- Review proposal

The Lens is not a score, activity ring, decorative graph, or glowing AI effect. Tapping a point reveals its source, freshness, window, and influence. Expanded, the path may continue into a proposal diff. Under Reduced Motion it becomes a static ordered evidence line.

Spend visual boldness here. Keep all surrounding surfaces disciplined.

## Color System

Use semantic tokens only. Do not invent screen-specific colors.

### Light theme

| Semantic role | Value | Use |
|---|---:|---|
| `canvas` | `#F3F6F8` | App background |
| `surface` | `#FFFFFF` | Cards, inputs, sheets |
| `textPrimary` | `#10151D` | Primary copy and icons |
| `textSecondary` | `#556170` | Supporting copy |
| `actionPrimary` | `#4A57E8` | Primary actions and selection |
| `stateStable` | `#00796B` | Stable or recovered state |
| `stateAttention` | `#C43C31` | Pain, warning, or attention |

### Dark theme

| Semantic role | Value | Use |
|---|---:|---|
| `canvas` | `#090D14` | App background |
| `surface` | `#121925` | Cards, inputs, sheets |
| `textPrimary` | `#F4F7FB` | Primary copy and icons |
| `textSecondary` | `#AAB5C5` | Supporting copy |
| `actionPrimary` | `#9BA5FF` | Primary actions and selection |
| `stateStable` | `#59D6C7` | Stable or recovered state |
| `stateAttention` | `#FF887D` | Pain, warning, or attention |

Derive `borderSubtle`, `surfaceRaised`, `actionOnPrimary`, `stateDanger`, `focusRing`, and `scrim` from these themes while preserving WCAG AA contrast. Color never carries meaning alone. Gradients are permitted only inside the Trajectory Lens when they encode direction.

## Typography

| Role | Typeface | Treatment |
|---|---|---|
| Brand and decision display | San Francisco / iOS system | 600–700, short lines only |
| Interface and body | San Francisco / iOS system | Dynamic Type, regular and semibold |
| Data and utility | San Francisco / iOS system | 500, tabular figures |

- Decision headline: 28–32pt, compact leading, maximum three lines.
- Screen title: 24–28pt.
- Section title: 18–20pt semibold.
- Body: 16–17pt with at least 1.45 line height.
- Label and metadata: 13–15pt; never below 12pt.
- Loads, reps, timers, macros, and changing data use tabular figures.
- Wrap before truncating and support all accessibility text sizes.
- Use the iOS system font; never use a production font CDN.

## Layout and Shape

- Base spacing: 4pt; preferred rhythm: 8, 12, 16, 24, 32, and 48pt.
- Phone gutter: 20pt; compact phone gutter: 16pt.
- Touch targets: at least 44 × 44pt with 8pt between adjacent targets.
- Radii: 12pt controls, 18pt cards, 26pt primary decision surface.
- Capsules are reserved for small statuses, never major containers.
- One primary action per screen.
- Respect the Dynamic Island, safe areas, home indicator, keyboard, and system back-swipe region.

Hierarchy comes from spacing, type, contrast, and subtle borders. Use only canvas, raised-card, and modal elevation. Dark mode uses tonal separation, not heavier shadows.

## Navigation

Use a native-feeling iOS tab bar with five labeled destinations:

1. **Today** — decision, check-in, schedule, pending proposal
2. **Train** — active plan, workout execution, history
3. **Coach** — direct questions, evidence explanation, and proposal review entry points
4. **Nutrition** — targets, confirmed meals, meal capture
5. **Progress** — measurements, reviews, trends, progress photos

Account and settings open from Today. Coach is a real center tab, but it is one unified Tracend Coach workflow, not separate agent personas or autonomous chatbots. Preserve native back behavior, swipe-back, selected-tab state, scroll position, drafts, and deep-link restoration.

## Core Components

### Trajectory Lens

Compact evidence-to-action trace. Supports collapsed, expanded, partial, stale, loading, and static Reduced Motion states. VoiceOver reads it as an ordered evidence summary followed by the decision.

### Decision Surface

One direct headline, one concise reason, timestamp, confidence wording, primary action, and **See evidence**. A pending persistent change opens a dedicated proposal screen.

### Coach Perspective Card

Collapsed Training and Nutrition summaries below the final decision. Expansion reveals evidence and limits. Never use fictional avatars, chat bubbles, or agent-to-agent conversation.

### Evidence Row

Label, value, unit, source, time window, freshness, and status. Missing values read **Not enough data** with a recovery action; never show a fabricated zero.

### Proposal Diff

Current versus proposed values, effective date, evidence, benefit, downside, missing data, and confidence. Actions: **Accept change**, **Keep current plan**, and **Request revision**. Acceptance is never preselected.

### Workout Set Row

One-handed layout with set number, load, reps, RPE, completion, and visible pain access. Use a numeric keyboard. Previous values remain unconfirmed references until saved.

### Meal Candidate Editor

Separates AI-observed candidates from confirmed catalog items. Every candidate shows editable amount, preparation assumption, confidence, and unresolved questions. Totals update only after confirmation.

### Metric Trend

Use a line for time trends and a range band only for genuine uncertainty. Show units, direct labels or legends, 44pt interactive points, and a VoiceOver text summary.

## Primary Screen Briefs

### Today — design this first

Single job: make the next coaching action obvious and trustworthy.

```text
┌─────────────────────────────────────┐
│ Today                     Account   │
│ Sat, 28 Jun · Updated 7:40 AM       │
│                                     │
│ Evidence ── Trajectory ── Next move │
│ Sleep    Training    Nutrition      │
│                         TRAIN: Push │
│ Keep the planned Push session.      │
│ Recovery supports the planned work. │
│ [ Start workout ]    See evidence   │
│                                     │
│ Check-in needed · about 1 min       │
│ Training perspective             ›  │
│ Nutrition perspective            ›  │
│                                     │
│ Today  Train  Coach Nutrition Progress │
└─────────────────────────────────────┘
```

Content order:

1. timestamped Head Coach decision;
2. one primary action;
3. Trajectory Lens and confidence/freshness;
4. missing input or check-in;
5. Training and Nutrition perspectives.

Sample copy:

- **Keep the planned Push session.**
- **Recovery supports your normal working sets. Skip extra volume today.**
- Primary: **Start workout**
- Secondary: **See evidence**

Create ready, partial-data, stale-data, offline, AI-unavailable, and pending-proposal variants without changing the core hierarchy.

### Active Workout

Single job: log the current set with minimum friction. Use a quiet exercise-progress header, compact objective, large current-set row, visible rest timer, **Pain or discomfort** action, and bottom-safe completion control. Preserve offline input. Avoid dense tables and tiny steppers.

### Meal Confirmation

Single job: turn an uncertain visual estimate into confirmed food data. Keep the photo secondary to the editable candidate list. Label **AI estimate** and **Confirmed**. Surface oil, sauces, and portion assumptions inline. Offer **Enter manually** and **Delete photo** recovery paths.

### Plan Change Proposal

Single job: support an explicit persistence decision. Show current plan beside the proposed diff, why now, evidence windows, confidence, benefit, downside, and effective date. A stale proposal is disabled with a concrete explanation.

### Weekly Review

Single job: explain what happened and what remains unchanged. Use an editorial sequence: outcome, execution, recovery, training evidence, nutrition evidence, maintained decisions, proposed adjustment, next-week focus. Every claim links to its source.

### Onboarding and Plan Approval

Single job: gather enough information to propose a safe plan without overwhelming the user. Use section progress, autosave, visible labels, reasons for sensitive questions, and **I don’t know** where appropriate. Separate **Guide me** and **I know my current plan** paths. Generated plans remain proposals until **Approve plan**.

## Interaction and Motion

| Token | Duration | Use |
|---|---:|---|
| `motion.quick` | 160ms | Press and compact feedback |
| `motion.standard` | 240ms | Expand, crossfade, row change |
| `motion.emphasis` | 360ms maximum | Lens resolution or shared transition |

- Motion communicates cause and hierarchy; it never decorates idle screens.
- Use interruptible springs and transform/opacity instead of layout animation.
- Entering eases out; exiting is faster.
- Limit each view to one or two meaningful animated moments.
- Press feedback appears within 100ms and never shifts nearby layout.
- Use light haptics only for set completion, meal confirmation, accepted proposals, and safety-critical warnings.
- Reduced Motion removes path morphing, parallax, and stagger.
- Reserve skeleton space for waits over 300ms. Long AI/image work names the task and lets the user leave.

## Content Voice

Write like a careful trainer: direct, calm, specific, evidence-aware, and nonjudgmental.

Use:

- **Keep today’s plan.**
- **Sleep data is missing. Add a check-in to improve this decision.**
- **Review proposed calorie target.**
- **The meal estimate needs your confirmation.**

Avoid “You’re crushing it,” “AI optimized your diet,” fake urgency, medical certainty, shame, and motivational filler.

Buttons use outcome verbs consistently: **Start workout**, **Save check-in**, **Confirm meal**, **Accept change**, **Keep current plan**, **Delete account**.

## Required States

Every data-driven screen or component accounts for loading, ready, empty, partial, stale, offline, failed, permission denied, and safety escalation where relevant.

Errors explain what happened and how to recover. Empty states offer one useful action. AI-estimated, deterministic, user-entered, and user-confirmed information remain visibly distinct.

## Accessibility

- WCAG AA: 4.5:1 for normal text; 3:1 for large text and meaningful graphics.
- Logical VoiceOver order with labels, hints, and traits on custom controls.
- Dynamic Type through the largest accessibility sizes without losing actions.
- Support Bold Text, Button Shapes, Increase Contrast, Differentiate Without Color, and Reduce Motion.
- Test compact and large phones, landscape, keyboard appearance, and iPad-compatible layouts.
- Progress photos never receive automated appearance labels in navigation.

## Explicit Anti-Patterns

Do not generate:

- black-and-neon gym styling, chrome, flames, or aggressive bodybuilding motifs;
- activity rings, readiness scores, radial dashboards, or KPI-card walls;
- generic cream-and-serif wellness branding or acid-green AI styling;
- robots, AI sparkles, glowing orbs, or chat-first coaching;
- frosted glass, floating pills, gradients, or glow across every surface;
- emoji icons, mixed icon families, or unlabeled icon-only navigation;
- fictional trainer portraits or autonomous-agent conversations;
- confetti, streak anxiety, punitive missed-workout states, or gamified shame; or
- visual precision implying meal, physique, or body-fat estimates are exact.

## Google Stitch Generation Direction

1. Start with **Today** at 390 × 844pt in light and dark themes.
2. Produce three materially different compositions that preserve the same information hierarchy and Trajectory Lens concept.
3. Use realistic Tracend copy and data, never lorem ipsum.
4. Keep native iOS status, safe-area, navigation, sheet, keyboard, and back behavior.
5. Do not treat generated web code as production code; implementation is Flutter.
6. After choosing Today, extend the system to Active Workout, Meal Confirmation, Plan Change Proposal, Weekly Review, and Onboarding.
7. Include ready, partial, offline, and failure variants before considering a screen complete.

The result must remain recognizable as an evidence-driven training instrument even with the logo removed.
