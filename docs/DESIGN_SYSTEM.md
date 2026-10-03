# Tracend Design System

**Status:** Authoritative MVP experience and visual direction\
**Direction:** Graphite + signal lime (owner-approved 2026-10-03, palette A)\
**Platform:** Flutter for iOS, private TestFlight beta\
**Working brand:** Tracend, pending trademark and App Store name clearance

This document translates [PRD.md](./PRD.md) into a coherent interface system. Screen behavior is
defined in [UX_FLOWS.md](./UX_FLOWS.md). Safety and uncertainty language remains governed by
[AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md). The previous "Precision Pro" direction is archived in
[archive/DESIGN_SYSTEM-precision-pro.md](./archive/DESIGN_SYSTEM-precision-pro.md).

## 1. Thesis: Graphite + signal lime

Tracend feels like a native iOS training instrument: quiet graphite surfaces, one bright signal,
and big honest numbers. The interface steps back so the athlete's plan, sets and evidence lead.

- **Graphite** carries the structure. Canvas, surface and raised fills separate content by tone,
  not by borders or shadows.
- **Signal lime** marks the one thing that is _now_: today, the selected state, the active tab, a
  new best, the primary progress ring. It is never a status color and never means "good".
- **Archivo** sets titles and numbers with weight and tight tracking. Everything else is the system
  font, so it reads like iOS.
- **Native behavior** comes first: large titles that collapse, sheets that swipe away, action
  sheets and alerts, haptics with a fixed vocabulary.
- Confidence, freshness and missing data are first-class content. Nothing is invented to fill a
  surface.

It is not a motivational chatbot, a neon gym app, a generic wellness dashboard or a science-fiction
control panel.

Today's data moment remains the 7-day trend (`TrajectoryTrend`, §5.2). Other surfaces stay quiet
so it keeps its meaning.

## 2. Color tokens

Implementation uses the semantic roles in `lib/app/theme/tracend_tokens.dart` (`TracendColors`).
Raw color values never appear in feature widgets.

| Role               | Light         | Dark          | Use                                                      |
| ------------------ | ------------- | ------------- | -------------------------------------------------------- |
| `canvas`           | `#F4F4F1`     | `#0C0D0E`     | Page background                                          |
| `surface`          | `#FFFFFF`     | `#18191B`     | Cards and grouped rows                                   |
| `surfaceRaised`    | `#EDEDE9`     | `#232427`     | Controls, chips, nested fills, segmented track           |
| `sheet`            | `#F9F9F7`     | `#1A1B1D`     | Bottom sheets, dialogs, menus                            |
| `textPrimary`      | `#121311`     | `#F4F4F1`     | Primary text and icons                                   |
| `textSecondary`    | `#61635D`     | `#9C9D98`     | Secondary text                                           |
| `textTertiary`     | `#8A8B86`     | `#6E6F6A`     | Placeholders, disabled text, chevrons; never needed info |
| `borderSubtle`     | `#E3E3DE`     | `#2A2B2F`     | Drag handle, control outlines                            |
| `borderHairline`   | `#ECECE8`     | `#222326`     | Row separators and bar edges                             |
| `actionPrimary`    | `#121311`     | `#F4F4F1`     | Primary pill fill (near-black / off-white)               |
| `actionOnPrimary`  | `#F9F9F7`     | `#0C0D0E`     | Text on the primary pill                                 |
| `accentSignal`     | `#C8F05A`     | `#C8F05A`     | Lime as a fill (switch track, selected chip, ring)       |
| `onAccentSignal`   | `#141A05`     | `#141A05`     | Text and icons on a lime fill                            |
| `accentSignalInk`  | `#4E6A00`     | `#C8F05A`     | Lime as text or an icon on canvas and surface            |
| `accentSignalRing` | `#6B8F0E`     | `#C8F05A`     | Lime rings and strokes (3:1 or better)                   |
| `accentSignalTint` | lime 16%      | lime 14%      | Wash behind selected or new-best content                 |
| `stateStable`      | `#087A5A`     | `#4FD1A5`     | Good: recovered, done, synced                            |
| `stateGoodTint`    | good 12%      | good 14%      | Wash behind good status                                  |
| `accentAmber`      | `#A86A00`     | `#F2B544`     | Caution: pending, partial, needs review                  |
| `stateAttention`   | `#C24A3A`     | `#F07F6E`     | Low: needs attention                                     |
| `stateDanger`      | `#B3392B`     | `#F07F6E`     | Destructive actions and errors                           |
| `focusRing`        | `#4E6A00`     | `#C8F05A`     | Keyboard focus                                           |
| `scrim`            | ink 28%       | black 45%     | Modal scrim (blurred, §3.4)                              |
| `glass`            | white 74%     | `#1E1F21` 72% | Chrome fill over a blur (§3.4)                           |
| `glassEdge`        | black 6%      | white 8%      | Chrome hairline                                          |
| `shimmer`          | black 5%      | white 6%      | Skeleton highlight                                       |

Rules:

- **Color roles stay separate.** Lime is brand and action signal only. Good (`stateStable`),
  caution (`accentAmber`), low (`stateAttention`) and danger (`stateDanger`) keep their own colors.
- Lime as text uses `accentSignalInk`; lime as a stroke uses `accentSignalRing`; anything on a lime
  fill uses `onAccentSignal`. Plain `accentSignal` text on a light surface fails contrast.
- Body text meets WCAG AA 4.5:1; large text and meaningful graphics meet 3:1. `test/theme_test.dart`
  asserts it in both themes.
- Color is never the only signal: state always has a word or an icon.
- Gradients appear only inside data visuals where they encode direction.

## 3. Type, shape and surfaces

### 3.1 Typography

| Theme role       | Face        | Size / weight                   | Use                                  |
| ---------------- | ----------- | ------------------------------- | ------------------------------------ |
| `displayLarge`   | Archivo     | 56 / 800                        | Hero numbers                         |
| `displayMedium`  | Archivo     | 44 / 800                        | Large readouts                       |
| `displaySmall`   | Archivo     | 34 / 800                        | iOS large title, decision headline   |
| `headlineMedium` | Archivo     | 28 / 800                        | Headings inside content              |
| `headlineSmall`  | Archivo     | 24 / 700 (800 in sheet headers) | Sheet titles                         |
| `titleLarge`     | Archivo     | 20 / 700                        | Section labels, card titles          |
| `titleMedium`    | Archivo     | 17 / 600                        | Emphasized lines                     |
| `titleSmall`     | System (SF) | 15 / 600                        | List-row titles, toast text          |
| `bodyLarge`      | System      | 17 / 400                        | Primary reading text                 |
| `bodyMedium`     | System      | 15 / 400                        | Secondary text, subtitles            |
| `bodySmall`      | System      | 13 / 400                        | Row details, footnotes, trailing values |
| `labelLarge`     | System      | 16 / 600                        | Buttons, inline bar title            |
| `labelMedium`    | System      | 13 / 600, tabular               | Chips, small data labels             |
| `labelSmall`     | System      | 13 / 600                        | Small labels (sentence case)         |

- **Archivo** (display) and **Archivo SemiCondensed** (numbers) ship as static OFL fonts
  (`TracendFonts.displayFamily`, `TracendFonts.numericFamily`). Body text is the system font.
- Numbers in rows and readouts use `TracendTheme.numeric(...)`: Archivo SemiCondensed with tabular
  figures, so digits line up and never jitter while they change.
- **11pt floor.** No text renders below 11pt.
- **Sentence case.** Labels, section titles and buttons are written as they read. Caps appear only
  where they encode something real, such as weekday letters.
- Every style follows Dynamic Type, wraps before truncating, and is tested at the largest
  accessibility sizes.

### 3.2 Layout and spacing

- Base unit 4pt; rhythm 8, 12, 16, 20, 24, 32, 48 (`TracendSpacing`).
- Phone gutter 20pt; compact phone (under 375pt) 16pt; content is width-constrained to 720pt.
- Minimum touch target 44×44pt with at least 8pt between adjacent targets.
- One 8pt gap between stacked cards and one 24pt boundary before a section label. Never stack a
  trailing card spacer onto a section label's leading space.
- One primary action per screen. Bottom actions clear the safe area and never cover content.
- No nested scrolling, edge controls that fight system gestures, or dense edge-to-edge charts.
- Repeated items of one kind (weigh-ins, photo sets, meals) share one grouped list (§5.1), never a
  card per row. A main screen shows at most three recent items; the rest open from **See all**.

### 3.3 Shape

| Element                          | Radius         |
| -------------------------------- | -------------- |
| Inputs and small controls        | 12 (`control`) |
| Cards and grouped lists          | 20 (`card`)    |
| Sheets (top corners) and dialogs | 28 (`sheet`)   |
| Buttons, chips, segmented, toast | pill (`pill`)  |
| Row icon tiles                   | 10             |

Documented exception: Coach chat bubbles use an asymmetric 18pt bubble (4pt on the tail corner).

### 3.4 Elevation and glass

- Three levels: canvas, surface, sheet. Separation comes from tone. Cards have no border, no
  gradient and no shadow (`PremiumGradientCard` is a flat `surface`).
- The only shadows are the small lift under the selected segment of a segmented control and the
  soft lift under the toast, which separates it from the glass bar beneath it.
- **Glass** (`TracendGlass`: the `glass` fill over a 20σ blur with a `glassEdge` hairline) is chrome
  only: the tab bar, the toast and the collapsed large-title bar. The sheet scrim is blurred too
  (6σ), growing with the sheet. Nothing else uses `BackdropFilter`.
- Glass is built only while visible (the inline bar exists only once collapsed) and sits in a
  `RepaintBoundary`. `reduceTransparency` swaps it for an opaque `sheet` fill.

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

The five destinations sit in one safe-area-aware graphite glass capsule. The active icon is lime
ink, selection plays the `selection` haptic, and the indicator moves in 160–240ms interruptible
motion. Tab labels clamp to 1.3× text scale so they never overflow the bar. The bar never hides
scroll content and preserves all tab state.

Top-level screens use the iOS large title (`TracendScrollView`, §5.1). Pushed detail screens keep
an inline title. Native back behavior, swipe-back, tab-state preservation, deep links, and
restoration after interruption are mandatory.

Account uses the grouped-list grammar (§5.1): an identity block (display name from the signed-in
email local-part, a compact **Private beta** pill, the current goal only when the active-goal RPC
returns one, and an **Edit** affordance), then grouped lists under sentence-case section labels,
with sign-out separated at the foot.

## 5. Components

### 5.1 Shared components

All live in `lib/shared/widgets/` and appear in the component gallery
(`./scripts/flutter.sh run -t lib/component_gallery.dart`) in light and dark.

#### Large title: `TracendScrollView`

The page frame for top-level tabs. The large title is `displaySmall` Archivo with an optional
subtitle and trailing control. Content scrolls up under the status bar; once most of the title has
passed under it, a glass inline bar with the title (`labelLarge`) fades in, and it fades out when
the title returns. The inline bar repeats the title visually only; the large title stays the page's
VoiceOver header. `onRefresh` adds iOS pull to refresh (`CupertinoSliverRefreshControl`) that
reruns the screen's existing reload.

#### Sheet: `showTracendSheet`

The standard bottom sheet for a focused, dismissible sub-task.

- It rises over a blurred scrim with its own 36×5 drag handle, and it closes on a swipe down, a scrim
  tap or the round close button.
- With a title it gets the standard header (`TracendSheetHeader`): a 24pt Archivo 800 title, an
  optional subtitle and a 32pt round close button in a 44pt target.
- It clears the home indicator and lifts with the keyboard. The body never pads for the keyboard
  itself.
- `detents` (for example `[0.5, 0.92]`) open a sheet at the first size and snap between sizes.
- Inside a sheet, grouped content sits on `surface` against the `sheet` fill.
- A sheet that holds unsaved input asks before discarding it (§7).

#### Action sheet and confirm: `showTracendActionSheet`, `showTracendConfirm`

Native `CupertinoActionSheet` and `CupertinoAlertDialog` with token text colors.

- **Action sheet**: two or more related choices with a separate **Cancel**; completes with the
  chosen value or null.
- **Confirm**: one consequential step; completes `true` only on the confirm button.
- **Destructive** choices render in `stateDanger`, play the `warning` haptic as they appear, and
  make **Cancel** the bold default so the safe choice is the obvious one.
- Confirm labels name the outcome (**Discard workout**, **Delete thread**), never "OK".

#### Toast: `TracendToast.show(context, message, icon:)`

A glass pill that springs in at the top for transient, non-blocking feedback ("Check-in saved").
It leaves after 2.3s, or earlier on a tap or an upward swipe. One toast shows at a time. VoiceOver
reads it through a live region. Anything the athlete must act on is a confirm or a sheet, never a
toast. The Material `SnackBar` stays only as a fallback.

#### `Pressable`

Cards, rows and pills that open something scale to 0.97 over 120ms while pressed, with no ripple
or highlight. A pressable is a button to VoiceOver; pass a semantic label when the visible text does
not say what the tap does. An optional haptic role plays on tap.

#### Skeleton: `TracendSkeleton.line`, `.block`, `.row`

Placeholders in the shape of the content that is loading. They replace page-level spinners and
progress bars. A soft highlight sweeps across while the skeleton is visible; it pauses when its
ticker is muted (an off-screen tab) and never starts under Reduce Motion. Skeletons are hidden from
VoiceOver; the loading region carries one label, such as "Loading Train".

#### Status chip: `StatusChip(label:, icon:, tone:)`

A pill with a tone-colored icon on a tone wash and the label in primary text.

| Tone      | Color            | Use                                     |
| --------- | ---------------- | --------------------------------------- |
| `good`    | `stateStable`    | Done, recovered, saved and synced       |
| `caution` | `accentAmber`    | Pending, partial, offline, needs review |
| `low`     | `stateAttention` | Failed, below the floor                 |
| `neutral` | `textSecondary`  | Information with no judgement (default) |
| `signal`  | lime ink         | New, now, selected                      |

A warning never renders green.

#### Section label: `SectionLabel(label, value:, actionLabel:, onAction:)`

A sentence-case 20pt Archivo section title (a VoiceOver header), with an optional quiet trailing
value ("16 sets") or text action ("See all").

#### Grouped list: `TracendGroupedList`, `TracendListRow`, `TracendRowIcon`

An inset grouped list: rows share one `surface` with 20pt corners. Rows are at least 60pt tall,
with a 15pt semibold title, an optional 13pt detail line, an optional trailing value, and a
chevron plus a pressed `surfaceRaised` fill only when the row opens something. Hairline separators
start past the leading 30pt icon tile, as on iOS.

#### Segmented control: `TracendSegmentedControl`

Pill segments: a `surfaceRaised` track, with the selected segment as a `surface` pill with a slight
shadow that slides between options. The control is 44pt tall and a change plays the `selection`
haptic.

#### Buttons, inputs and chips

Material buttons are themed, not replaced: `FilledButton` is the 52pt primary pill
(`actionPrimary`), `OutlinedButton` is the tonal pill (`surfaceRaised`, no outline), `TextButton` is
a quiet pill. Inputs are filled (`surfaceRaised`) with no outline and a lime focus ring. Chips are
pills; a selected chip is a lime fill with `onAccentSignal` text.

### 5.2 Data components

#### `RecoveryReadoutCard`

Full-width recovery readout on Today: tabular score with `/ 100`, a band chip
(Excellent/Good/Moderate/Low/Poor), and five driver rows (HRV, RHR, Sleep, Resp, Strain) with
horizontal z-score bars and signed z values. Bar fill clamps z to ±2 for layout; labels and
semantics always report the true z-score. Cold start shows `--` with honest next-step copy; low
confidence adds "Building baseline". Unusable drivers (no value today or no usable baseline) render
a No data row instead of a zero bar, and a fully unusable recovery shows `--` rather than a
fabricated score. One gated exception: a sleep row whose value is proven valid (non-null sleep
quality, the backend's 1–960-minute gate) but whose baseline is immature (< 3 observations) shows
the measurement with a "Building baseline" note instead of No data. Training load (ACWR) is not
part of this card; it renders as a display-only row inside `SessionPlanCard`.

#### `SleepArchitectureCard`

Full-width sleep quality readout on Today: a band chip (Restorative ≥80 / Adequate ≥60 / Light ≥40
/ Disrupted), a tabular score with count-up (deliberately secondary to the recovery readout), and
four reflowing sub-score rows (Duration, Efficiency, Restorative, Consistency) with 0–100 bars and
no fixed-width columns. Cold start or low confidence adds "Building baseline"; a null quality
renders "No data". Sleep debt renders as a semantic pill (`sleep_debt_minutes` is `480 − 7-day
average`: positive is debt, negative is surplus, 0 reads "Sleep target met"). Baselines are not
repeated here; the recovery readout carries them. Every data element exposes a semantics label.

#### `TrajectoryTrend`

Today's data moment: a real 7-day column chart from `daily_health_summaries` for one metric
(priority HRV → sleep → resting HR; first with ≥4 recorded days in the window wins). The window is
the 7 days ending at the latest stored day. A recorded day grows a rounded column toward its value
(the latest recorded day carries the signal); an unrecorded day leaves a dim socket on the
baseline. Hairline rails bound the series' own min/max, a day-tick row shows month rollover, and a
calibration strip reports the range, the recorded-day count and the as-of stamp. Missing days are
never interpolated; fewer than four recorded days renders the "Building baseline" card. Direction
is reported neutrally: up or down is fact, not good or bad.

#### `EvidenceTrendChart` and weight charts

Linear segments, actual date spacing, a visible numeric scale, the current value and an optional
average line. Curved interpolation, unlabeled auto-scaling and spreadsheet-style equal metric grids
are prohibited. Weight charts show confirmed raw weigh-ins as dots that are never smoothed.
Computed trend overlays are only labeled regression segments from the server OLS slopes
(`ALGORITHMS.md` §5), anchored to real measurements (no invented intercept, no extrapolation),
distinguished from the dots by a legend, and dashed and labeled "low confidence" when the 28-day R²
is under 0.3 or missing. The 7-day line carries no R² and is never confidence-gated.

#### `WeekRailCard`

Train's week instrument: day slots select the day, and the chart below speaks `TrajectoryTrend`'s
grammar. A session day grows a column sized by real training minutes (summed
`recent_sessions[].duration_seconds / 60`); a session-less day leaves a dim socket; a
planned-but-untrained day carries a small caution dot. The verdict uses the app-wide ACWR
convention: Low load < 0.8 caution · Optimal 0.8–1.3 good · High load > 1.3 low (above 1.5 the
copy escalates, never a fourth label). Fewer than four sessions in the 28-day payload renders
"Building baseline", never a ratio verdict. A session without a duration never invents height;
the chart speaks training minutes, never "strain".

#### `WeightHeroCard`

The Progress hero: latest weigh-in, the change across the selected period, the server's weekly
rate (`weightTrend28d`, else `weightTrend7d`, × 7), a plain word for the 28-day R² (**Steady
trend** ≥ 0.6, **Some day-to-day variation** ≥ 0.3, **Too noisy to call yet** below), and the
`EvidenceTrendChart`. The change is tinted good only when it moves toward the active goal
(`fat_loss` down, `muscle_gain` up); otherwise it stays neutral, and the arrow and spoken label
carry the direction.

#### `DecisionSurface`, `CoachPerspectiveCard`, `EvidenceRow`, `ProposalDiff`

- `DecisionSurface`: one direct headline, one reason, timestamp, confidence wording, primary action
  and **See evidence**. It never hides a pending persistent change inside normal advice.
- `CoachPerspectiveCard`: training and nutrition perspectives collapsed below the final decision;
  opening one reveals evidence and limits, not simulated chat personas.
- `EvidenceRow`: label, value, unit, source, time window, freshness and status. Missing data reads
  **Not enough data** with a recovery action, never a fabricated zero.
- `ProposalDiff`: current and proposed values, effective date, evidence, downside, uncertainty, and
  separate Accept, Reject and Request revision actions. Accept is never preselected.

#### `WorkoutSetRow` and `MealCandidateEditor`

- `WorkoutSetRow`: one-handed set number, load, reps, RPE, completion and pain access, with the
  right keyboard, the previous set as an unconfirmed reference, and offline support.
- `MealCandidateEditor`: separates AI-observed foods from confirmed catalog items; every candidate
  shows an editable amount, preparation assumption, confidence and open questions. Totals update
  only after confirmation.

#### `MetricTrend` and `UsageSummary`

- `MetricTrend`: a line for a time trend, a range band for uncertainty where applicable, explicit
  units, direct labels for small sets and a text summary for VoiceOver. Never red versus green
  alone. Planned values, fixtures and unrelated metrics never appear as an observed trend; two real
  dated observations are the minimum.
- `UsageSummary`: a named window, request count, token or image usage when meaningful, estimated
  cost and service state, labeled **Estimate**. It never exposes keys, prompts, request identifiers
  or raw provider errors.

#### `CoachMessage` and `NutritionTimeline`

Coach messages use a restrained bubble, selectable text and an expandable evidence drawer. A reply
renders a small Markdown subset (bold, italic, bullet and numbered lists; headings as bold lines; a
link as its label followed by its destination in plain text). The athlete's own messages show
exactly as typed. A labeled reply that stands in for a failed model answer is a variant of the same
bubble: **Data summary · not an AI answer** (attention border, no provider pill) or **Safety note ·
not an AI answer** (neutral border), with a muted, selectable beta diagnostic line on a live reply
and **Retry** when the reply ends the conversation. The pill text, not the color, carries the
meaning.

`NutritionTimeline` lists meals in time order, each with a tabular time, a status glyph (good check
logged, caution spark draft, caution ring due, neutral ring planned, faint ring optional, dash not
logged) and a title carrying the calories of a logged meal (**Lunch · 691 kcal**). The second line
opens with the status word followed by the foods. A logged meal ends with `MacroSplitBar`, with the
grams spoken to screen readers. At large text sizes the time joins the title line and actions move
under the row.

## 6. Motion and haptics

Motion explains hierarchy and causality. Nothing animates idle except the skeleton sweep while
loading and the single pulse on the 7-day trend's latest day.

| Token (`TracendMotion`) | Duration | Use                                                      |
| ----------------------- | -------: | -------------------------------------------------------- |
| `quick`                 |    160ms | Selection, inline bar fade                               |
| `standard`              |    240ms | Segment slide, expand and collapse, crossfade            |
| `emphasized`            |    360ms | Larger reveals                                           |
| `settle` (curve)        |        — | Spring-like overshoot for things that land (toast entry) |

- Press: 0.97 scale over 120ms (`Pressable`).
- Sheets rise and reverse on dismiss; the scrim blur grows with them. Toasts spring in (420ms) and
  leave faster (220ms).
- Exits are shorter than entries. Motion never delays input.
- Card entrances may stagger 60ms per index (`MicroMotionEntrance`, capped at 8). Scores count up
  only on change (`MicroMotionCountUp`).

**Motion levels** (`TracendMotionScope`): `full`, `reduced`, `static`. The effective level is the
stricter of the nearest scope and the system Reduce Motion setting. Reduced keeps fades and drops
scale, slides and loops (no skeleton sweep). Static removes animation entirely; the test suite runs
static (`test/flutter_test_config.dart`), and a test that checks motion sets a scope.

**Haptics** (`TracendHaptics`; never call `HapticFeedback` directly, never await a haptic):

| Role        | iOS feedback         | Use                                                     |
| ----------- | -------------------- | ------------------------------------------------------- |
| `selection` | selection click      | Tabs, segmented controls, the day strip                 |
| `light`     | light impact         | Checking a set, flipping a toggle                       |
| `medium`    | medium impact        | Starting rest, finishing, a new best                    |
| `heavy`     | heavy impact         | **Start workout** only                                  |
| `success`   | success notification | A task completed and saved                              |
| `warning`   | warning notification | A destructive confirm or action sheet, a blocked action |

## 7. States and feedback

Every data-driven component defines loading, ready, empty, partial, stale, offline, failed, and
permission-denied states.

- Loading uses skeletons in the shape of the content (§5.1). Waits under 300ms show nothing; long
  AI or media work shows named progress and permits leaving.
- Errors state what happened and the recovery action.
- Empty states contain one useful next step, not motivational filler.
- Destructive actions are separated and confirmed with a destructive confirm or action sheet.
- Dismissing unsaved input asks first; long forms autosave drafts.
- Transient success is a toast; anything that needs a decision is a confirm or a sheet.
- Pending, confirmed, AI-estimated and user-entered data are visually and verbally distinct.
- Press feedback appears within 100ms and never shifts neighboring layout.

## 8. Accessibility baseline

- VoiceOver order matches visual order; charts and the 7-day trend expose concise summaries.
- All controls have labels, hints where useful, and selected, disabled and expanded traits. Large
  titles, section labels and sheet titles are headers. Toasts are live regions.
- Dynamic Type works through accessibility sizes without losing actions or values; screens are
  regression-tested at 1.3× and about 2.0× at 320pt.
- Bold Text, Button Shapes, Increase Contrast, Differentiate Without Color and Reduce Motion are
  supported.
- Touch targets are at least 44pt, including the sheet close button and segmented control.
- Contrast is asserted in tests for both themes.
- Progress photos never receive automated appearance labels in general navigation.

## 9. Writing style

Tracend is direct, calm, specific, and nonjudgmental.

- **Keep today's plan** instead of "You're crushing it."
- **Sleep data is missing. Add a check-in to improve this decision** instead of "Insufficient
  context."
- **Review proposed calorie target** instead of "AI optimized your diet."
- Buttons use outcome verbs: **Start workout**, **Confirm meal**, **Accept change**, **Delete
  account**.
- Never use shame, physique ranking, fake urgency, streak loss, or medical certainty.
- Format for people, not databases: **Today**, **Yesterday**, or **Mon 28 Sep** for dates
  (`lib/shared/formatting.dart`); weight rates per week; stored codes as words (`healthkit` →
  **Apple Health**, `lunch` → **Lunch**).
- Say an honesty label once per surface in plain words (**Calculated from your logs · no AI**).

## 10. Anti-patterns

Do not use:

- generic activity rings, meaningless readiness scores, or dashboard walls;
- lime as a status color: it never means "good", "safe" or "on track";
- glow, neon edges, or colored shadows;
- ALL-CAPS labels or wide letter-spaced caps (weekday letters are the exception);
- borders, gradients or shadows on content cards;
- glass or blur anywhere but the tab bar, the toast, the collapsed large-title bar and the sheet
  scrim;
- black-and-neon gym styling, chrome textures, flames, or aggressive bodybuilding motifs;
- animated AI sparkles, robot imagery, or chat bubbles as the primary coaching interface;
- ripples or Material splash feedback;
- fabricated metrics, fake-precise numbers, or values that do not trace to a repository, model or
  RPC field;
- dead affordances: no-op chevrons, buttons, or rows that neither navigate nor act;
- hardcoded confidence strings or model-version labels not sourced from `CoachDecision`;
- emoji as icons, mixed icon families, or unlabeled icon-only navigation;
- confetti for health behavior, manipulative streaks, or red failure states for missed workouts;
- motion that delays input, hides loading, or cannot be disabled.

## 11. Design review gate

Before a screen is implementation-complete:

- compare it to [UX_FLOWS.md](./UX_FLOWS.md);
- use only semantic tokens and the shared components above;
- verify light and dark contrast, 44pt targets, safe areas, keyboard behavior, VoiceOver, Dynamic
  Type, and Reduce Motion;
- test loading, empty, partial, stale, offline, error, and permission-denied states;
- confirm one clear primary action; and
- remove treatments that do not communicate structure, evidence, state, or action.
