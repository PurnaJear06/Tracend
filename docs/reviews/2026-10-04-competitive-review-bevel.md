# Competitive review: how Bevel works, flow by flow, and the AI-trainer field — 2026-10-04

**Scope:** the owner found Bevel (bevel.health) during the first week of device testing. They
asked for a focus on *how things work*, not the core idea: how it takes food photos, how a
workout is logged, how the home screen and coach behave. Each flow gets the steps in Bevel,
the steps in Tracend today, and what to build. Positioning and the wider market follow in
Part 2.

**Method:** read-only. No product code was changed.

- **Bevel's flows:** from its help centre (step-by-step articles), App Store listing (v3.2.2),
  feature-by-version table, and reviews. Bevel was not installed. Its photo-review screens come
  from a screen capture of an older build (ScreensDesign) and are marked as such.
- **Tracend's flows:** traced through the code at `1da7ea2`, with tap counts estimated from the
  code.
- **Spot checks in this session:** the claims this review leans on were re-checked against
  primary sources:
  - the App Store listing (version, ratings, prices)
  - Bevel's pricing article
  - the court docket for the WHOOP lawsuit
  - Future's AI shutdown
  - WHOOP's AI hallucination reports
  - Apple's Mulberry change
  - in Tracend's code: the missing plan-change path, the meal-photo consent gap, and the
    absent widget, Watch and Live Activity targets

This review builds on the market section of
[2026-09-04-full-project-review.md](./2026-09-04-full-project-review.md).

## Verdict

1. **Bevel's mechanics are worth studying; its breadth is not.** Its best ideas are about
   speed and shortcuts:
   - one "+" button that can log anything from anywhere;
   - several ways to log food (photo, describe, barcode, label scan, favourites, history), and
     the AI fills a cart you review;
   - corrections in plain words ("I only ate half of that");
   - prefill everywhere: auto-fill sets, update the routine from today's session, copy
     yesterday;
   - a timeline where tapping a time logs at that time;
   - a status chip for sick or travelling.

   Most of these fit Tracend's "AI proposes, you confirm" rule exactly.
2. **Tracend's flows are close on workouts and behind on food and shortcuts.**
   - **Workout logging** is already strong: one tap per set when the prefill is right, last
     time and best, rest timer, a new-best moment.
   - **Food is slow:**
     - Today's "Log a meal" only switches tabs.
     - A planned meal opens an empty form.
     - Changing a photo estimate's portion means retyping every number.
     - A manual meal holds one food.
     - There is no describe, barcode, favourites or copy option.
     - A logged meal can't be edited.
   - **Today's buttons** ("View workout", "Log a meal") switch tabs instead of starting the
     action, and Today's cards barely open into more detail.
3. **The cheapest wins are food speed and direct actions.** Most of them reuse what exists:
   - `meal-analyze` can take text as well as a photo;
   - `user_foods` exists for favourites;
   - the confirm sheet exists for portion scaling.
4. **The deepest gap is still the coaching loop.** The coach can propose plan changes only in
   onboarding; after that, the server rejects a daily decision that carries one. Bevel lets its
   AI draft a plan you review and schedule. Tracend's version, a diff you approve that becomes
   a new version, is the moat and isn't built yet (Part 2).
5. **Meal-photo consent is not a blocker now.** The owner is the only user. Add the consent
   check before any second account.

# Part 1 — How things work, flow by flow

## Flow 1: logging food

**Bevel**
- **Entry points:**
  - a global "+" button (Log Food → capture, barcode, describe, search, import)
  - Nutrition → Timeline → +
  - tapping a time on the Timeline, which sets the meal time
  - the Nutrition widget
  - the AI chat
  - Camera Control on iPhone 16 and later opens Capture Food directly
- **Ways in:**
  - **Capture:** a meal photo; tips ask for about 45°, a fork or hand for scale, good light.
  - **Import** a photo, with an optional description.
  - **Barcode:** multi-scan and manual code; if a scan fails, photograph the label.
  - **Describe** in words ("grilled chicken salad with avocado").
  - **Search** a database of 6M+ foods.
  - **My Foods:** Favourites, Recipes, Custom, History.
- **AI review:**
  - Analysis runs in the background; you can leave and come back with "Go to food log".
  - Detected items appear as rows. Tap one for a serving-size stepper, editable ingredients,
    swap via search, and a time.
  - Then Add to log. Nothing is logged without confirmation.
  - In chat, the AI fills a Food Cart → Review Cart → Add to log. Plain-word edits work ("this
    burger without the bun", "I only ate half").
- **After logging:**
  - edit name, macros or ingredients;
  - long-press to multi-select, then copy to other days, move, delete or make a recipe;
  - swipe to delete;
  - foods in the same hour group with a subtotal;
  - a custom food can be made by photographing a nutrition label.
- **Honest gating:** the Nutrition Score unlocks only after about a third of the day's calories
  are logged.

**Tracend today**
- **Entry points:**
  - **Nutrition → Log a meal:** a sheet with meal-type chips preselected by the clock, then
    Take a photo, Photo Library or Enter manually.
  - **Today's "Log a meal":** only switches to the Nutrition tab, so it costs one extra tap.
  - **The next-meal card's "Log meal":** opens the *empty* manual form, not the planned foods.
- **Photo path:**
  1. Picker, then upload and analysis with a loader ("Analyzing meal photo…"). There is no
     progress, no cancel and no client timeout.
  2. "Review candidates": checkbox rows (name, serving, kcal, confidence), all ticked; "Edit
     estimate" opens six plain text fields. **No portion stepper**, so half a portion means
     retyping kcal and three macros.
  3. Confirm: haptic and a "Meal logged" toast.
  4. About 5–6 taps from the Nutrition tab, about 7 from Today.
- **Failures:** clear messages (permission, too large, no food found, provider busy, budget),
  but **no Retry button**. A 503 may leave a "Needs review" draft with no candidates.
- **Manual:** six required fields and **one food per meal**.
- **After logging:** delete only, with no edit. No barcode, search, favourites, recents,
  copy-meal or quick-add calories.

**What to build (AI proposes, you confirm, so it stays inside our rules)**

| # | Change | Reuses | Cost |
|---|---|---|---|
| F1 | Today's "Log a meal" opens the log sheet directly, preselected to the next planned slot | `LogMealSheet` | S |
| F2 | **Portion stepper** on each AI candidate (½, ¾, 1, 1¼, 1½, 2, or a slider) scaling kcal and macros together | `CandidateSheet` | S |
| F3 | **Describe a meal**: a text box sent through the same analyse → candidates → confirm path | `meal-analyze` contract, a text provider | M |
| F4 | **Retry and background analysis**: Retry on failure; leaving the sheet keeps the draft, which reappears as "Ready to review" | draft meals | S |
| F5 | **Edit a logged meal** (name, serving, macros) and **multi-food manual meals** | `save_manual_meal` item array | S–M |
| F6 | **Favourites and recents**: star a confirmed food; "Log again" from history; "Copy yesterday's breakfast" | `user_foods` table (exists, unused) | M |
| F7 | **Planned meal → prefilled log**: the next-meal card opens with the planned foods listed. It needs macros on schedule foods, so first store kcal and macros per planned food, then add one-tap "Ate as planned" | schedule foods, `save_scheduled_manual_meal` | M |
| F8 | **Barcode** (Open Food Facts) plus **nutrition-label photo** for packaged food, both feeding the same confirm sheet | confirm sheet | M |
| F9 | Plain-word correction on the confirm sheet ("half the rice", "no sauce"), re-run as a new estimate the user confirms | F3 path | M |

Skip Camera Control: the owner's iPhone 12 has no Camera Control button. A "+" shortcut and a
widget (Flow 6) cover the same need.

## Flow 2: logging a strength workout

**Bevel**
- **Routines:** built by hand, by photo of a written workout, from text, or generated from saved
  preferences (experience, goal, equipment, warm-up, failure, drop sets, supersets, excluded
  exercises).
- **Start:** from Fitness → Routines or Today's Activity. Choose iPhone only (an HR strap or
  AirPods Pro 3 as the heart-rate source) or iPhone + Watch.
- **During the workout:**
  - **Sets:** Play starts a set; a checkmark completes it. Tap any weight, rep or set number to
    edit.
  - **Exercises:** ⋯ to replace, delete or edit; add exercises at the bottom; reorder;
    supersets.
  - **Set types:** warm-up, cool-down, failure, drop set.
  - **Plate calculator:** tap the weight; bar and plates are configurable.
  - **Rest:** a default rest and interval haptics.
  - **Settings:** Auto-Fill Sets (fill the rest from the last set) and set-by-set confirmation.
  - **Live Sync:** the phone and Watch mirror each other.
  - **Watch:** hands-free completion by Double Tap or the Action Button.
  - **Effort:** RPE estimated from the Watch accelerometer, adjustable.
- **Finish:** a summary, then **Update Routine** saves today's weights and reps as next time's
  prefill (or Auto-Update). An activity screen splits cardio and muscular strain, PRs,
  muscular load, per-set effort and HR zones.
- **Weak spots reviewers name:** muscle attribution, e.g. upper back credited only 3%. No AMRAP
  or EMOM; a freestyle workout needs an empty routine first.

**Tracend today**
- **Start:**
  - **Today's "View workout":** only switches to Train.
  - **Train's "Start workout":** one tap; the overview sheet also has Start.
- **Focus page per exercise** (swipe between exercises):
  - "Set N of M" and the rest length.
  - Big kg × reps with ± steppers.
  - **Prefill:** typed value → earlier set → last time → plan, with a caption saying which.
  - Last time and Your best.
  - **"Done set N"**: one tap when the prefill is right.
  - A new-best stamp with haptics.
  - Tap a logged set for RPE or undo.
  - Pain chip, "Fill effort", Mark as skipped.
- **Rest timer:** full-screen ring with −15, +15 and Skip, plus an RPE picker inside the rest
  screen. It shrinks to a pill, survives relaunch, and has an optional lock-screen alert.
- **Finish:**
  - leave with Save and leave or Discard;
  - **Finish requires a 1–10 session effort**;
  - a summary with new bests;
  - finishing offline queues it.
- **Missing:**
  - **automatic move to the next exercise** (you swipe or tap Next);
  - **add or remove a set**, **swap or add an exercise**, per-set notes;
  - set types, plate calculator;
  - Watch, Live Activity.

**What to build**

| # | Change | Reuses | Cost |
|---|---|---|---|
| W1 | Today's workout button **opens the workout overview** (or starts it), instead of switching tabs | `startWorkout` | S |
| W2 | **Auto-advance**: after the last set of an exercise and its rest, slide to the next exercise | `PageView` controller | S |
| W3 | **Add or remove a set** mid-workout (logged as a deviation, not a plan change) | draft model | M |
| W4 | **Swap an exercise** from the catalog with a reason; the server already supports substitution | slug trigger, truth repair | M |
| W5 | **Warm-up set type**: warm-ups excluded from volume and bests | set row | S–M |
| W6 | **Plate calculator** from the weight field (bar and plate settings in Account) | — | S |
| W7 | **"Use today's loads next time"** at finish, Tracend's version of Update Routine. It becomes a load proposal the athlete approves (the G1 loop), not a silent overwrite | G1 | after G1 |
| W8 | **Live Activity** for the rest timer and current set on the lock screen | rest timer state | M |
| W9 | Watch logging | — | L, later |

Keep session effort required. It feeds training load, and the PRD treats an unknown effort
honestly instead of guessing.

## Flow 3: the morning check (Today vs Bevel Home)

**Bevel**
- **Home cards:** Strain, Recovery, Sleep, Stress, Energy Bank, Nutrition, vitals and a
  Timeline preview.
- **Edit Home:** hide, add, drag to reorder, reset.
- **Status chip:** the activity status sits top-left.
- **Dates:** swipe left for past days; the day rolls over at wake-up time.
- **Drill-downs:**
  - Recovery → contributors (sleep, HRV, RHR, temperature, breathing, SpO₂) plus a guidance
    line.
  - Strain → a personal Target Strain moving with recovery, active vs passive, strain per
    activity.
  - View Insights → correlations labelled "not causal".
  - Values are tagged above, normal or below a 60-day baseline; blue means better, orange means
    worse.
  - Missing overnight HRV or RHR means no score.
- **Sickness detector:** prompts you to set a status when HR, HRV or sleep fall outside your
  normal range.
- **Weak spot:** reviewers say it gives numbers but rarely a prescription. It has no workout
  suggestion for the target strain.

**Tracend today**
- **Order:** greeting, then the hero (recovery dial, verdict, vitals, sync), check-in bar,
  workout card, fuel rail, coach note, last 7 days, recovery drivers, sleep.
- **Drill-downs are minimal:**
  - the hero only offers sync;
  - the drivers card has an inline "How this is calculated";
  - the sleep card is display-only;
  - the coach note doesn't open the Coach.
- **Check-in:** one scrolling form with five 1–5 scales, pain, available to train, and a note.
  It works offline.
- **Strength over Bevel:** the verdict and coach decision *are* a prescription.

**What to build**

| # | Change | Reuses | Cost |
|---|---|---|---|
| T1 | **Tick-ring hero** (owner prototype, 2026-10-04). The lit ticks split by recovery driver, lime when a driver is fine, amber when it pulls the score down, grey for no data; driver chips name them. Below: HRV and resting HR, three tiles (Sleep, Load, Fuel). The only bottom button is the morning **Check in**, shown until the day's check-in is done and then gone; it is never reused for other actions, since the tab bar handles navigation (owner, 2026-10-04). It folds the vitals list and check-in bar into the hero, so Today gets shorter | today hero, breakdown data | M |
| T2 | **Tap to drill down**: tiles and driver chips open their detail (driver sheet, sleep sheet, load sheet); the coach note opens Coach chat with that decision as context | existing sheets | S–M |
| T3 | **Activity status chip** (Active, Sick, Injured, Travelling, On a break, with a duration) in the hero. It lowers confidence and is passed to coach-decide | new small table | S–M |
| T4 | **Above / normal / below baseline** words on every vital ("HRV 61 ms, above your normal") | baselines | S |
| T5 | Swipe to past days on Today | brief by date | M |

Avoid Bevel's and WHOOP's three-ring layout, the trade dress in their lawsuit. The single tick
ring is distinct.

## Flow 4: the coach (chat, check-ins, plans)

**Bevel**
- **Chat:** suggested prompts above the keyboard lead into guided flows ("Check-in with me").
- **Screen Context:** attaches the screen you were viewing, so you can ask "what does this
  mean?" about a metric.
- **Other chat controls:**
  - dictation;
  - Fast, Thinking or Adaptive modes;
  - four personalities plus free-text instructions;
  - Ghost Mode for temporary chats.
- **Actions:** when the AI acts, a dropdown says what it is doing.
- **Check-ins:** created by asking ("send me a recovery summary at 8am") or by form (title,
  instructions, frequency, time). They arrive as notifications that open a check-ins thread.
- **Plans:** the AI drafts a plan → you review → you schedule. Drafts schedule nothing until
  approved. A Training Calendar marks planned, skipped, done and rest. A scheduled item's ⋯
  offers Edit, Log, Skip, Save as routine, Delete.

**Tracend today**
- **Entry:** the Coach tab only.
- **New conversation:** a context card and three starter chips.
- **Answers:** not streamed (thinking indicator, 45 s timeout); markdown with a provider label,
  "Evidence used and data gaps", follow-up chips, preference chips you confirm.
- **Errors and limits:** an error card with Retry; a rate-limit cooldown.
- **Proactive messages:** none in chat, and no push. The daily decision appears on Today.
- **Plan changes after onboarding:** not possible (Part 2, G1).

**What to build**

| # | Change | Reuses | Cost |
|---|---|---|---|
| C1 | **"Ask about this"** on Today cards and sheets: opens Coach with that card's numbers attached as context (Tracend's version of Screen Context) | chat context builder | S–M |
| C2 | **Morning summary notification** when the brief is ready ("Recovery 71 · Upper body A as planned · 92 g protein to go"). Deterministic, no AI; local notification | brief, `TracendNotifications.swift` | S |
| C3 | **Plan drafts you approve** (G1): the coach drafts a bounded change → diff → approve → new version | `change_proposals`, onboarding proposal view | M–L |
| C4 | **Week calendar actions**: Move or Skip a workout from the week view, logged honestly | week view | M |
| C5 | Streamed answers | coach-chat | M |
| C6 | Tone preference (direct or encouraging), wording only, through confirmed preference chips | preference chips | S, only if asked |

## Flow 5: timeline, journal, status

- **Bevel:**
  - **Timeline:** one day of sleep, workouts and food in time order; tap + at a time to log;
    pins at the top ("1,500 kcal left").
  - **Journal:** yes / neutral / no toggles, mood, caffeine, water, supplements, "Copy
    yesterday", default entries. Insights need at least 5 yes and 5 no entries.
- **Tracend:**
  - **Timeline:** Nutrition's meal timeline plus Today's fuel rail.
  - **Journal:** the check-in covers mood, energy, soreness, hunger and pain.
- **Build:**
  - **T3 activity status** (Flow 3).
  - **"Same as yesterday"** on the check-in: prefill yesterday's answers, then adjust. S.
  - Skip the journal, caffeine and water: breadth outside the trainer.

## Flow 6: shortcuts outside the screen you're on

- **Bevel:**
  - **"+" button:** an in-app floating button with a customisable menu (Log Food, Log Activity,
    View Routines, Ask Bevel, Hydration, and more).
  - **Widgets:** about a dozen home-screen widgets (overview, nutrition with logging, macros)
    plus lock-screen widgets.
  - **Live Activity:** a strength workout Live Activity.
  - **Watch:** complications and a Watch app.
- **Tracend:** none. Every action starts from its own tab.
- **Build:**

| # | Change | Cost |
|---|---|---|
| S1 | **Quick-action "+"** in the tab bar (Log a meal, Start workout, Check in, Ask Coach) | S–M |
| S2 | **Home-screen widget**: recovery, today's workout, protein to go; taps open the matching action | M |
| S3 | Home-screen quick actions (long-press the app icon): Log a meal, Start workout | S |
| S4 | Live Activity (W8), then Watch (W9) | M / L |

## Flow 7: onboarding

- **Bevel:**
  - **Show, don't ask:** picking a goal immediately shows a sample of what the app will do
    (a sample recovery score, a sample nutrition gauge).
  - **Soft paywall** at the end.
  - Scores take 2–6 weeks to calibrate.
- **Tracend:**
  - **Fifteen steps**, ending in an AI-proposed plan the athlete approves (stronger: a real
    plan, not a demo).
  - **What it lacks:** previews of what each step leads to.
- **Build:** at the goal step, a small preview of the first week ("3 strength days, about 50
  minutes, protein 150 g") that updates as the athlete answers. It uses the deterministic
  calculators, so no AI is needed. M. Not urgent while the owner is the only user.

## Build batches (PR-sized, fastest value first)

Each batch is one PR, after the test week unless testing turns up a bug.

1. **Batch 1, "Direct actions and faster food" (S–M, mostly Flutter):**
   - F1 log sheet from Today, W1 workout from Today
   - F2 portion stepper, F4 Retry and background review, F5 edit and multi-food meals
   - W2 auto-advance, W6 plate calculator, T4 baseline words
2. **Batch 2, "Today hero" (M):** T1 tick-ring hero, T2 drill-downs, C1 "Ask about this", T3
   activity status.
3. **Batch 3, "Close the loop" (M–L, the moat):**
   - G2 (show today's adjustments on the workout)
   - C3 / G1 plan drafts with diff and approval
   - W7 loads as proposals
4. **Batch 4, "Food sources" (M):**
   - F3 describe a meal, F6 favourites, recents and copy
   - F7 planned meals with macros and "Ate as planned"
   - F8 barcode and label photo, F9 plain-word corrections
5. **Batch 5, "Outside the app" (M):** S1 "+", S3 icon quick actions, C2 morning summary, S2
   widget, W8 Live Activity.
6. **Later:** W3 add or remove a set, W4 swap, W5 warm-ups; C4 move or skip; C5 streaming;
   onboarding preview; Watch.

# Part 2 — Positioning and the field

## Bevel at a glance (verified)

| Fact | Detail | Source |
|---|---|---|
| Name on store | "Bevel: AI Health Coach – Exercise, Sleep & Nutrition", v3.2.2 (2026-10-03), iOS 18+ | App Store |
| Ratings | 4.8★, 17K US ratings (#142 Health & Fitness); site claims 49.1K global | App Store, bevel.health |
| Company | Finerpoint, Inc., New York; founded late 2023; ~20 people; $4M seed + $10M Series A (General Catalyst) | TechCrunch 2025-10-30, the5krunner |
| Users | 100K+ DAU and 80%+ 90-day retention (Oct 2025, company-reported); ~500K MAU (Apr 2026); "2.5M members" on site (likely cumulative) | TechCrunch, Fitt |
| Free | Recovery, Sleep, Strain, Stress, Energy Bank, nutrition (barcode, photo, text, 6M+ foods, recipes), Strength Builder (700+ exercises, Watch app), cycle, journal, widgets | Bevel pricing article, App Store |
| Pro | $14.99/mo or $99.99/yr: Bevel Intelligence (chat, check-ins, plans), Health Records, Biological Age, training plans; weekly AI allowance plus credit packs $4.99–$49.99 | App Store, Bevel pricing article |
| AI | Chat with memory, scheduled check-ins (daily, weekly, monthly), multi-week plans it can "create, review, and schedule or migrate", meal plans, lab analysis, web search; four personalities (Commander, Friend, Guardian, Data Nerd); LLM sub-processors Google, Anthropic, OpenAI, Baseten | App Store, help centre, privacy policy |
| Scores | Recovery 1–100% (sleep score, HRV during sleep, RHR, wrist temp, resp rate, SpO₂); Strain 0–100%+ logarithmic; 60-day rolling baselines; inputs published, **weights not published** | Help centre |
| Lawsuit | Whoop, Inc. v. Finerpoint, Inc., D. Del. 1:26-cv-00289, filed 2026-03-17: trade dress, copyright, four patents on physiological data → exercise and sleep recommendations; jury trial set for September 2028 | Court docket, law.com, the5krunner |

**What reviewers praise:**
- a polished design and a "ten-second morning check";
- the free tier is a real product;
- food logging, especially photo and barcode;
- it replaces several apps;
- it is cheaper than WHOOP.

**What they complain about:**
- **Black-box scores:** it does not show which input moved them.
- **Data without guidance:** "big on data, but falls short on guidance" (Lifehacker).
- **Shallow depth:** strength and nutrition are shallower than specialist apps.
- **Battery drain.**
- **Sync:** needs the app opened.
- **3.0 redesign:** it alienated some users.
- **Price:** Pro is the most expensive in its category, plus credit metering.
- **Overnight wear:** the Watch must be worn overnight.

**Top requests on its feedback board:**
- sync with MacroFactor or Lose It
- dynamic calorie targets (TDEE)
- supplement tracking
- fewer taps to log food
- background sync

## Side by side: Bevel vs Tracend

✅ built · ◐ partial · ✗ not built · — out of scope by decision

| Area | Bevel | Tracend (verified at `1da7ea2`) |
|---|---|---|
| Recovery score | ✅ black box (inputs listed, weights hidden) | ✅ **explained**: five driver rows, weights and z-scores in "How this is calculated", "No AI" (`recovery_readout_card.dart`, `ALGORITHMS.md`) |
| Missing data | Scores shown daily; reviewers say they look more precise than they are | ✅ null instead of invention; confidence tiers; "No data" rows |
| Strain | ✅ headline ring, Target Strain range | ◐ calculated (daily strain, ACWR, monotony), shown only in a driver row and the Train load sheet; no Today readout |
| Sleep | ✅ score, need, sleep bank, smart alarm | ✅ quality score with four sub-scores and debt; ✗ hypnogram, ✗ alarm |
| Stress / Energy Bank | ✅ | ✗ (not planned) |
| HealthKit inputs | HRV, RHR, sleep, resp, SpO₂, wrist temp, HR zones, steps | HRV (SDNN), RHR, sleep stages, resp, steps, active energy, weight, workouts; ✗ SpO₂, ✗ wrist temp, ✗ HR samples |
| Background sync | ✗ (users ask for it) | ✗ sync only when Today opens or on pull to refresh |
| Training plan | ✅ AI-generated multi-week plans (Pro) | ✅ AI plan proposed at onboarding, checked by deterministic policy, **approved by the athlete**, versioned |
| Changing the plan later | ✅ AI can create and "schedule or migrate" plans | ✗ **not built**: `persist_daily_coaching_result_v2` rejects any daily decision with change proposals; no in-season proposal or diff screen |
| Daily decision | ✗ (scores plus chat) | ✅ coach-decide: proceed / adjust / gather data / review / escalate, with evidence, risk flags and missing data |
| Today's adjustments shown | n/a | ◐ produced on the server; the Flutter model does not parse `today_adjustments`; the coach note shows only text and reason |
| Workout logging | ✅ Strength Builder, Watch live sync, plate calculator, supersets, videos, Live Activity | ✅ focus logging, prefill, last time and best, RPE, pain chip, rest timer, new-best moment, offline draft; ✗ Watch, ✗ Live Activity, ✗ add/remove set, ✗ substitution UI (the server supports it) |
| Muscle view | ✅ Muscular Load, Muscle Freshness | ✅ 2.5D muscle map (shown at ≥75% coverage) |
| Progression | ✅ AI progressive-overload suggestions | ◐ plan rule text plus prefill; no load-progression engine |
| Exercise library | ✅ 900+ with videos | ◐ 72-exercise catalog (onboarding allowlist) plus reviewed muscle names; no browser or videos |
| Food logging | ✅ photo, barcode, text, 6M+ database, recipes, CGM | ◐ photo AI with confirm step, plus manual entry; ✗ barcode, ✗ database, ✗ saved foods UI (the `user_foods` table exists) |
| Targets | Static goals (dynamic TDEE is a top request) | ✅ from the approved plan; ◐ not editable; macro adherence calculated but not shown |
| Meal schedule | ✗ | ✅ timeline, next meal, fuel rail on Today; ✗ editor, ✗ reminders (`reminder_enabled` column unused) |
| AI chat | ✅ memory, web search, personalities, credits | ✅ full athlete context, "Calculated by Tracend" block, evidence, data gaps and "How the Coach reasoned" per answer, fallback when the model fails, preference chips you confirm |
| AI honesty architecture | LLM over data | ✅ deterministic calculations; the model only interprets; numbers come from SQL |
| Weekly review | ✅ AI check-ins (Pro) | ✅ deterministic weekly review (free of AI) |
| Progress | ✅ trends, body projections | ✅ weight trend, measurements, strength bests, private photos, physique check (owner only) |
| Widgets / Watch / Live Activity | ✅ / ✅ / ✅ | ✗ / ✗ / ✗ (only Runner and RunnerTests targets) |
| Notifications | ✅ check-ins, reminders | ◐ local only: check-in 19:00, weekly review, rest timer |
| Activity status (sick, travel, injured) | ✅ | ✗ |
| Health records / bio age | ✅ (Pro) | — excluded (medical-report analysis) |
| Cycle / caffeine / water / journal | ✅ | — not planned; check-in covers mood, energy, soreness, pain |
| Privacy | Pseudonymised prompts, 3-day retention at providers, not HIPAA-covered | ✅ RLS everywhere; per-purpose AI notices; encrypted export; delete account; ◐ meal-photo consent missing |
| Sign-in | Sign in with Apple | ✗ email and password only (owner beta) |
| Price | Free core; Pro $99.99/yr plus credits | — no subscriptions in MVP |

## Where Tracend is genuinely different, and should stay that way

1. **Explainable scores.** Bevel's most-cited weakness is that it never says why recovery is
   62. Tracend's drivers card and "How this is calculated" panel do exactly that. Publishing the
   method (from `ALGORITHMS.md`) also meets Apple's health-score disclosure expectations, and
   competitors cannot match it without exposing their IP.
2. **Honesty about missing data.** Bevel and WHOOP show a score every day. Tracend shows "No
   data", lowers its confidence and says what is missing. That is a trust feature: market it,
   don't apologise for it.
3. **The AI never calculates.** WHOOP's documented failures ("I invented 'more awake last
   night' without data", Gear Patrol, Jul 2026) cannot happen by design. The numbers come from
   SQL, and the model is limited to the evidence it is given.
4. **One decision a day, not a wall of numbers.** Reviewers fault Bevel for "data without
   guidance". Tracend's coach-decide gives one action with evidence. This is the product.
5. **AI proposes, you confirm.** It already applies to onboarding plans, meal photos and coach
   preferences. Photo calorie apps are criticised for accuracy, so the confirm step is a selling
   point, not friction.
6. **A plan with an ending.** Everyone sells endless tracking. Tracend sells a 5–6 month plan
   (from the 2026-09-04 review). Keep it.
7. **Meal timing.** Bevel has no meal schedule. Tracend's schedule, next meal and fuel rail
   are rare in the field.

## Where Tracend is behind (prioritised)

Each gap shows the cost (S, M or L), with notes on existing plumbing that makes it cheap.

| # | Gap | Why it matters | Cost |
|---|---|---|---|
| G1 | **No plan changes after onboarding** (the coach cannot propose; no diff or approval screen) | It is the differentiator, and it isn't live. A coach that can never change your plan isn't a trainer. | **M–L.** Reuse `change_proposals`, the onboarding proposal view, plan versions and audit events; this is also the planned calibration / re-plan PR |
| G2 | **Today doesn't show the coach's adjustments or evidence** | The daily decision is the product, but Today shows only its text. "Reduce to 3 sets today" should appear on the workout. | **S–M.** The server already produces `today_adjustments` and evidence; parse and show them |
| G3 | **Meal-photo AI has no consent check** (`meal-analyze`) | Not a blocker while the owner is the only user (owner, 2026-10-04); required before any second account (Apple 5.1.2(i)) | **S.** The per-purpose notice system exists; add a `meal_photo` purpose naming the provider |
| G4 | **No widget** | The category's main cause of churn is low usage; Today has to escape the app. Bevel, Athlytic and Fitbod all ship widgets. | **M.** A WidgetKit extension reading a small JSON the app writes (recovery, today's workout, protein to go) |
| G5 | **No barcode, food database or saved foods** | Logging food is the most frequent action; photo alone is slow for packaged food | **M.** Barcode via a scanner plugin plus Open Food Facts (free); `user_foods` already exists for saved foods |
| G6 | **No background HealthKit sync** | Scores go stale until the app opens. It is one of Bevel's top complaints too, so it's a chance to beat them. | **M.** HealthKit background delivery plus an observer query calling `health-sync` |
| G7 | **No mid-workout edits** (add or remove a set, substitute an exercise) | Hevy and Strong set the bar for fast logging; real sessions deviate | **M.** The server supports substitution (slug trigger, truth repair); the UI is missing |
| G8 | **Strain not on Today; no activity status** | Bevel's three-number morning check; travelling or sick days currently look like bad recovery | **S** each. Strain is already calculated; status is one table plus a check-in option feeding confidence and coach-decide |
| G9 | **No meal reminders** | The meal schedule exists but never nudges | **S.** `reminder_enabled` plus the existing `TracendNotifications.swift` |
| G10 | **No load-progression engine** | JuggernautAI and Dr. Muscle charge $350–400/yr for automatic progression | **M.** Deterministic double progression from logged reps and RPE, offered as a proposal (it fits G1) |
| G11 | **No Watch app or Live Activity** | Table stakes for strength apps (Bevel, Fitbod, SensAI) | **L** for Watch, **M** for Live Activity; do after G1–G9 |
| G12 | **Smaller gaps** | Plan-version history screen; macro adherence not shown; targets not editable; no hypnogram; no exercise videos or browser; Sign in with Apple; Terms and Privacy links | S–M each |

## What to learn from Bevel

**Adopt (fits Tracend, cheap):**
- **The ten-second morning check.** Recovery, sleep and strain at a glance on Today. Our hero
  already has recovery and vitals; add a strain readout (G8). *Do not copy WHOOP's or Bevel's
  three-ring layout:* that layout is the trade dress in the lawsuit.
- **Activity status:** travelling, sick, injured or on a break (G8). It feeds confidence and
  coach-decide, so a bad-data day isn't read as bad recovery.
- **Proactive check-ins.** Tracend has the deterministic weekly review. Add a short morning
  push ("Recovery 71, Upper body A as planned, 92 g protein to go") when the brief is ready,
  using local notifications. No AI needed.
- **Widgets** (G4) and **barcode, database and saved foods** (G5): table stakes Bevel gives
  away for free.

**Adapt (good idea, Tracend-shaped):**
- **Coach personality.** Bevel offers four tones. Tracend could offer a tone preference
  (direct or encouraging) through the existing confirmed preference chips, affecting wording
  only, never the decision or evidence. Low cost; do it only if testers ask.
- **AI-built plans you can "schedule or migrate".** Bevel lets the AI create and move plans.
  Tracend's version is G1: the AI proposes and you see the diff, approve, and get a new version
  you can roll back. It is the same capability, made trustworthy.
- **Muscle freshness.** Bevel and Fitbod show per-muscle readiness. Tracend's muscle map could
  later colour by days since each muscle was trained, using deterministic logged volume (no AI).

**Avoid:**
- **Health records and biological age:** excluded (medical-report analysis), with liability.
- **Caffeine, water, cycle, journal, CGM:** breadth that dilutes the trainer and that Bevel
  already does free.
- **Metered AI credits:** users dislike them. If Tracend charges later, the coach should be
  effectively unlimited for normal use.
- **The three-ring score layout, and copying WHOOP's or Bevel's visuals:** active litigation.
- **Big-bang redesigns after launch:** Bevel's 3.0 lost some loyal users. Ship changes in small
  steps once there are real users.

## Other apps like Tracend

| App | What it is | AI model of work | Price | Signal | Relevance to Tracend |
|---|---|---|---|---|---|
| **Bevel** | Software health dashboard + AI coach | Chat, check-ins, AI plans you schedule or migrate | Free; $99.99/yr Pro | 4.8★ 17K US; $14M raised | **Closest overall** |
| **WHOOP** | Strap + subscription | OpenAI chat; builds workouts from a prompt; suggests a de-load when recovery is low | $199–359/yr | 2.5M+ members; $10.1B valuation | Same score thinking; **AI caught inventing data**; no real nutrition |
| **Oura** | Ring + membership | Advisor chat with charts; photo meals rated for quality | $69.99/yr + ring | 5M paid members; IPO filed | Sleep authority; no training plans |
| **Google Health Coach** | Gemini fitness, sleep and wellness coach | Conversational plans; photo and voice meals | $9.99/mo | Bundled with Google AI Pro | Matches on paper; **not available for Apple Watch** |
| **Vora** | All-in-one AI coach, any wearable | Chat (capped) plus a daily plan from readiness | $89.99/yr | ~108 ratings | Same concept, early and very broad |
| **SensAI** | LLM coach writing training from HealthKit | Generates programmes from recovery | $69.99/yr | ~30 ratings | Same concept, no traction |
| **Athlytic** | Low-cost WHOOP alternative | Mostly deterministic scores; small Q&A | $29.99/yr | 4.8★ 11K | Price anchor for scores alone |
| **Gentler Streak** | Recovery-aware activity guidance | Deterministic suggestions | $39.99/yr | Apple Design Award 2024 | Validates the "no drill sergeant" tone |
| **Fitbod** | Algorithmic gym sessions | Auto-generates each session from logged volume | $95.99/yr | 4.8★ 287K | Muscle-map benchmark; ignores sleep, HRV and food |
| **JuggernautAI / Dr. Muscle** | Algorithmic strength | Daily readiness → auto-adjusted programming, deloads | $350–400/yr | Niche, high price | Proves people pay for progression (G10) |
| **Hevy / Strong** | Set loggers | Hevy Trainer auto-progresses, "not AI" | $24–30/yr | 4.9★ ~100K | Logging-speed bar (G7) |
| **MacroFactor / Cal AI** | Nutrition | Adaptive targets / photo logging | $72/yr / — | Cal AI acquired by MyFitnessPal | Photo logging is commodity; accuracy and confirming are where apps differ |
| **Future / Ladder** | Human coaches / coach-led teams | Humans write plans | $149–199/mo / $180–480/yr | Future dropped AI (June 2026); Ladder ~150K paid | Ceiling for paid judgment; trust beats automation |
| **Apple** | Workout Buddy (watchOS 26) | Spoken in-workout feedback, generated on device | Free | Mulberry coach scaled back (Feb 2026) | No Apple coach for at least 6–12 months (inference) |
| **Runna, Garmin Connect+, Welltory, Rise** | Running plans / Garmin AI / HRV / sleep | Various | $70–150/yr | — | Adjacent, not direct |

**Synthesis:**
- **Closest to Tracend's exact combination:** Bevel, then WHOOP (hardware, no real nutrition).
  Vora and SensAI match the concept but are tiny.
- **Not credibly done by anyone:**
  - a proposed plan change shown as a diff, with its evidence, as a new version you approve
    and can roll back;
  - one daily decision applied to today's actual prescribed sets and meals;
  - scores whose method you can read.

**Table stakes in 2026:**
- recovery, sleep and strain scores
- an AI chat with memory
- photo, barcode and text food logging
- AI workout generation
- per-exercise history and PRs with a muscle view
- a Watch logging app
- fast set logging
- widgets
- a free tracking tier

**Pricing norms:**
- **All-in-one AI coach:** $70–100/yr.
- **Strength specialists:** up to $400/yr.
- **Human coaches:** $1,800+/yr.

Not relevant during the MVP (no subscriptions).

## Recommended plan

The build order is in Part 1, "Build batches". Two notes:
- **Meal-photo consent (G3)** waits until a second account is planned; the owner is the only
  user.
- **Terms and Privacy links** remain a public-release blocker, not a test-week task.

The coaching loop (G1, G2) sits in Batch 3, after the quick Batch 1 and 2 wins the owner sees
every day, because it is the larger build.

## Risks

- **IP.** WHOOP's four asserted patents cover analysing physiological data to give automated
  exercise and sleep recommendations, which describes Tracend's core loop too.
  - The WHOOP v. Bevel trial is set for September 2028.
  - Tracend's deterministic, published, evidence-traceable approach is a philosophical hedge,
    not a legal one.
  - **Get a real IP review before any commercial launch** (repeats 2026-09-04).
- **Trade dress.** Avoid three-ring score layouts and WHOOP or Bevel visual idioms. Tracend's
  single 270° dial with graphite and lime is distinct; keep it that way.
- **AI consent and provider disclosure.** Fix G3 before any second account. Keep per-purpose notices for
  every new AI use, including tone and proposals.
- **Breadth temptation.** Bevel's feature list is long because its business is engagement
  with a dashboard. Tracend's is outcomes against a plan; every feature should serve the
  daily decision or the plan.

## Not verified

- Bevel's score weights (not published); which LLM powers which Bevel feature.
- Bevel 3.0 details beyond the help centre and App Store, and the exact homepage wording of
  "HIPAA and SOC 2".
- ScreensDesign's estimate of about $750K a month in revenue (third-party, method unknown).
- What "2.5M members" counts.
- Reddit sentiment (r/bevelhealth could not be fetched).
- Competitor-sourced figures: SensAI and Vora traction, Future's rating, the Cal AI accuracy
  study, the prices for Dr. Muscle and Ladder tiers.
- WHOOP feature details: WHOOP's own pages returned 403, so these come from secondary coverage.
- The 6–12 month window before an Apple coach is an inference from Bloomberg's report, not a
  fact.

## Sources

**Bevel**
- https://www.bevel.health
- https://apps.apple.com/us/app/bevel-ai-health-coach/id6456176249
- https://help.bevel.health/en/articles/11583937 (pricing)
- https://help.bevel.health/en/articles/11194113 (features by version)
- https://help.bevel.health/en/articles/11251073 (key terms)
- https://help.bevel.health/en/articles/11258177 (recovery)
- https://help.bevel.health/en/articles/11586817 (Intelligence)
- https://www.bevel.health/privacy-policy
- https://feedback.bevel.health
- https://techcrunch.com/2025/10/30/bevel-raises-10m-series-a-from-general-catalyst-for-its-ai-health-companion/
- https://gadgetsandwearables.com/2025/12/21/bevel-app-free/
- https://gadgetsandwearables.com/2026/05/16/bevel-3/
- https://www.healthappinsider.com/en/reviews/bevel-review
- https://australianapplenews.com/2026/01/07/review-bevel-a-health-app-that-ticks-almost-all-the-boxes/
- https://www.autonomous.ai/ourblog/bevel-app-review
- https://neura.health/insight/bevel-health-app-in-depth-review
- https://tech.yahoo.com/wearables/articles/bevel-sort-makes-apple-watch-230000160.html

**WHOOP v. Bevel**
- https://www.pacermonitor.com/public/case/63631790/Whoop,_Inc_v_Finerpoint,_Inc
- https://www.law.com/radar/card/pm-63631790-whoop-inc-v-finerpoint-inc/
- https://the5krunner.com/2026/04/04/whoop-sues-bevel/

**Market signals**
- https://athletechnews.com/future-pulls-the-plug-on-ai-personal-training-commits-to-human-coaches/
- https://www.gearpatrol.com/fitness/whoop-ai-reddit-user-feedback-pros-cons/
- https://9to5mac.com/2026/02/05/apple-reportedly-scales-back-plans-for-ai-powered-health-coach/
- https://techcrunch.com/2026/05/07/googles-9-99-per-month-ai-health-coach-launches-may-19/
- https://ouraring.com/membership
- https://techcrunch.com/2026/09/21/ouras-2-2b-ipo-is-mostly-a-payday-for-existing-shareholders/
- https://hlth.com/insights/news/whoop-secures-575m-series-g-round-reaching-10-1b-valuation-2026-04-01

**Competitors**
- https://askvora.com/features
- https://apps.apple.com/us/app/athlytic-ai-fitness-coach/id1543571755
- https://www.healthappinsider.com/en/reviews/gentler-streak-review
- https://apps.apple.com/us/app/fitbod-gym-fitness-planner/id1041517543
- https://www.garagegymreviews.com/juggernautai-review
- https://insider.fitt.co/ladder-raises-105m-for-strength-training-app/
- https://arvo.guru/vs/macrofactor
- https://www.apple.com/newsroom/2025/06/watchos-26-delivers-more-personalized-ways-to-stay-active-and-connected/
