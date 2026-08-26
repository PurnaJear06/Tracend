# Today Page — Stitch 1:1 Match Plan

**Design Read:** iOS personal trainer dashboard (Operate mode), Stitch "Precision Pro" editorial language, dark canvas, restrained glass accents only where Stitch uses them, SplineSans headings + system body, IBM Plex Mono data only.

**Rule:** Stitch HTML wins over authority docs when they conflict. User directive: "exact stitch design for today page."

---

## Color Alignment (Stitch tokens → Flutter tokens)

| Stitch CSS | Hex | Flutter token | Fix needed? |
|---|---|---|---|
| `canvas` | `#080B10` | `#090D14` | YES — too light |
| `base-surface` | `#111827` | `#121925` | Close, keep |
| `elevated-surface` | `#1A222F` | `#182130` | Close, keep |
| `primary-text` | `#F4F7FB` | `#F4F7FB` | OK |
| `secondary-text` | `#8894A8` | `#AAB5C5` | YES — too light |
| `trajectory-indigo` | `#8A94F5` | `#9BA5FF` | YES — fix actionPrimary |
| `stable-teal` | `#45C4B5` | `#59D6C7` | YES — fix stateStable |
| `nutrition-amber` | `#E2A45C` | — | YES — add token |
| `chartreuse` | `#BCE85D` | — | YES — add token |
| `border-hairline` | `#2D3748` | — | YES — add token |
| `border-subtle` | `#1F2937` | `#293446` | YES — too light |

**Action:** Update `tracend_tokens.dart` dark palette to match Stitch hex values exactly.

---

## Font Fix (Step 1)

**Before (wrong):**
- bodyLarge/bodyMedium/bodySmall → SplineSans ❌
- labelLarge/labelMedium/labelSmall → IBMPlexMono ❌
- ThemeData base fontFamily → SplineSans ❌

**After (Stitch-correct):**
- displayLarge → headlineSmall → SplineSans (headings) ✓
- titleLarge/titleMedium → SplineSans (section titles) ✓
- bodyLarge/bodyMedium/bodySmall → **null (San Francisco system)** — Stitch body is Inter, iOS = SF
- labelLarge/labelMedium/labelSmall → **null (San Francisco system)** — Stitch labels are Inter
- ThemeData base fontFamily → **null (system default)**
- Data values (inline): explicit `fontFamily: TracendFonts.monoFamily` only at call site, NOT in theme

**Action:** Edit `tracend_theme.dart`:
1. Remove `fontFamily: TracendFonts.displayFamily` from ThemeData base
2. Remove `fontFamily: TracendFonts.monoFamily` from labelLarge/labelMedium/labelSmall
3. Remove `fontFamily: TracendFonts.displayFamily` from bodyLarge/bodyMedium/bodySmall
4. Keep `fontFamily: TracendFonts.displayFamily` only on displayLarge → titleMedium

---

## LiquidGlass Fix (Step 2)

**Before:** `blurSigma=24`, `surfaceAlpha=0.72`, inner border, top highlight gradient
**After:** `blurSigma=12`, `surfaceAlpha=0.40`, no border, no highlight, no gradient overlay

Match Stitch `.glass-panel`: `background: rgba(17,24,39,0.4); backdrop-filter: blur(12px)`

Only use LiquidGlass where Stitch uses `.glass-panel`:
1. Confidence pill (in hero header row)
2. T-Coach / N-Coach perspective toggle (segmented control wrapper)
3. Check-in prompt bar at bottom
4. Tab bar capsule (the one exception from DESIGN_SYSTEM.md)

Everything else → **solid `TracendCard`** (surface/surfaceRaised).

**Action:** Edit `tracend_tokens.dart` + `liquid_glass.dart`:
- `glassBlurSigma = 12.0`
- `glassSurfaceAlpha = 0.40`
- Remove `glassBorderAlpha`, `glassHighlightAlpha`
- Simplify widget: `ClipRRect` → `BackdropFilter(sigma:12)` → `DecoratedBox(fill 40%)` → child
- No border, no highlight, no gradient layers

---

## Today Screen Rebuild (Step 3)

### Layout (top to bottom, matching Stitch HTML exactly)

```
┌─ Status Bar (system, no custom) ──────────────────────────────┐
│ TopAppBar: "Tracend" (screen-title) + "Today · Sat, 28 Jun"   │
│   [favorite button] [profile avatar]                           │
├────────────────────────────────────────────────────────────────┤
│ HERO SECTION                                                   │
│ ┌──────────────────────┐                    ┌────────────────┐ │
│ │ Confidence pill      │  ← Spacer →        │ Sync timestamp │ │
│ │ (glass, green dot)   │                    │ (clock + time)  │ │
│ └──────────────────────┘                    └────────────────┘ │
│                                                                │
│ Decision headline (42px SplineSans 600, -0.03em)              │
│ "Push day is on. Keep the volume clean."                      │
│                                                                │
│ Reason text (16px system, secondary)                          │
│ "Recovery is steady..."                                        │
│                                                                │
│ TRAJECTORY LENS (280px, bezier graph)                         │
│  SLEEP          TRAIN          FUEL          NOW (chartreuse) │
│  ●───────────────●───────────────●──────────────◉ (glow)      │
│  ┃               ┃               ┃               ┃            │
│  Bezier path draw animation (1.5s)                            │
│                                                                │
│ [Start session]           [View analytics]                     │
│ (filled indigo, glow)     (glass outline)                     │
├────────────────────────────────────────────────────────────────┤
│ EVIDENCE: PRECISION READOUTS (stylized divider)                │
│ ─────────────── PRECISION READOUTS ───────────────             │
│                                                                │
│ ┌─ Sleep Architecture (premium-gradient card) ─────────────┐  │
│ │ 🌙 SLEEP ARCHITECTURE                      [chevron →]    │  │
│ │ 7h 42m                                                     │  │
│ │ [wave bar visualization]                                   │  │
│ │ HRV BASELINE: 58ms ↑    RESTING HR: 54bpm →               │  │
│ └────────────────────────────────────────────────────────────┘  │
│                                                                │
│ ┌─ Session Plan (premium-gradient card) ───────────────────┐  │
│ │ 🏋 SESSION PLAN                              [chevron →]   │  │
│ │ Push Protocol                                               │  │
│ │ 6 MVMT · 14 SETS · VOL +2%                                 │  │
│ │ [session map bars: 6 columns]                              │  │
│ └────────────────────────────────────────────────────────────┘  │
│                                                                │
│ ┌─ Metabolic Target (premium-gradient card) ───────────────┐  │
│ │ 🍽 METABOLIC TARGET                          [Log button]  │  │
│ │ 2,380 kcal                                                  │  │
│ │ [linear track: 65% filled]                                 │  │
│ │ 126g PRO                        24g REMAINING              │  │
│ └────────────────────────────────────────────────────────────┘  │
│                                                                │
│ COACH PERSPECTIVE                                              │
│ ┌──────────────────────────────────┐                           │
│ │ [T-COACH] [N-COACH]              │  (glass segmented control)│
│ └──────────────────────────────────┘                           │
│                                                                │
│ ┌─ Coach Insight (premium-gradient card) ──────────────────┐  │
│ │ "Volume is optimized for your recovery baseline..."        │  │
│ │ 🧠 Model: Recovery Index v2.4                              │  │
│ └────────────────────────────────────────────────────────────┘  │
│                                                                │
│ CHECK-IN PROMPT (glass panel)                                  │
│ ┌──────────────────────────────────────────────────────────┐  │
│ │ 💬 Update morning status?              CHECK-IN →         │  │
│ └──────────────────────────────────────────────────────────┘  │
├────────────────────────────────────────────────────────────────┤
│ BottomTabBar: [TODAY] [TRAIN] [FUEL] [DATA]                   │
│ (glass capsule, 4 tabs matching Stitch)                       │
└────────────────────────────────────────────────────────────────┘
```

### Component mapping (existing widgets → Stitch)

| Stitch element | Existing Flutter widget | Action |
|---|---|---|
| Confidence pill (glass) | `LiquidGlass` + green dot + text | **Keep,** fix glass params |
| Decision headline | `Text` with custom style | **New:** custom 42px TextStyle |
| Trajectory Lens SVG | `TrajectoryLens(showBezier: true)` | **Fix:** pass `showBezier: true` + fix colors |
| "Start session" button | `FilledButton` with indigo bg | **Keep** |
| "View analytics" button | `OutlinedButton` or glass button | **New** |
| Sleep card | `TracendCard` + `SleepArchitectureCard` | **New** premium-gradient card widget |
| Training card | `TracendCard` + workout data | **New** premium-gradient card widget |
| Nutrition card | `TracendCard` + nutrition data | **New** premium-gradient card widget |
| Coach toggle | `CupertinoSegmentedControl` in glass | **Move** from coach_screen to today_screen |
| Coach insight | `CoachInsightCard` | **Integrate** |
| Check-in bar | `LiquidGlass` + tap → `showCheckInSheet` | **New** |
| Bottom nav | `_FloatingTabBar` in `app_shell.dart` | **Fix:** match 4-tab Stitch layout |

### Delete today_screen.dart classes to remove:
- `_ReadinessStrip` + `_ScoredTile` (replaced by 3 Stitch evidence cards)
- `_TimelineRow` (not in Stitch)
- `_BriefEvidence` (replaced)
- Health evidence section (moved/removed from Today — Stitch doesn't show it inline)
- `_HeroSection` (rewrite to match Stitch layout)
- All LiquidGlass wrappers on content cards (replace with premium-gradient `TracendCard`)

### Keep:
- `RecoveryRing` widget (the Stitch Sleep card shows HRV/RHR instead of a ring, but ring is a good PRD feature)
- `showCheckInSheet` (Stitch check-in bar calls it)
- `FutureBuilder<DailyBrief>` pattern (data loading)
- `FutureBuilder<CoachDecision?>` (coach insight data)

---

## New Widget: StitchEvidenceCard (Step 4)

A reusable widget matching `.premium-gradient .hairline-border p-6 rounded-3xl`:

```dart
class StitchEvidenceCard extends StatelessWidget {
  // gradient: linear-gradient(145deg, rgba(17,24,39,0.8) 0%, rgba(8,11,16,0.9) 100%)
  // 24px radius (rounded-3xl)
  // 0.5px border-subtle border
  // Optional decorative top-right blur sphere
}
```

Used for: Sleep card, Training card, Nutrition card.

---

## TrajectoryLens Fixes (Step 5)

1. Pass `showBezier: true` in `_HeroSection`/replacement
2. Fix chartreuse color: `#BCE85D` (Stitch) not `#A8FF50` (current)
3. Fix path color: `#8A94F5` (Stitch indigo) → use token or hardcode
4. Labels: 9px label-caps style (system font, uppercase, 0.2em tracking)
5. NOW label: chartreuse color, w600
6. 280px height (match Stitch h-36 = 144px but we have more generous space)
7. Terminal dot: canvas fill ring + chartreuse stroke + chartreuse inner dot + glow

---

## Implementation Order

1. **Colors** — fix `tracend_tokens.dart` to match Stitch hex values
2. **Fonts** — fix `tracend_theme.dart` font assignments
3. **LiquidGlass** — fix params to match Stitch glass (12px/40%)
4. **TrajectoryLens** — fix showBezier, colors, labels
5. **StitchEvidenceCard** — new widget for the 3 evidence cards
6. **Today screen rebuild** — rewrite `build()` to match Stitch layout
7. **Remove dead code** — delete `_ReadinessStrip`, `_ScoredTile`, `_TimelineRow`, etc.
8. **Add missing elements** — secondary button, coach toggle, check-in bar
9. **Bottom nav** — ensure glass capsule matches 4-tab layout
10. **Verify** — analyze + tests
