# Tracend UX Flows

## Train Truth and Recovery

Train uses the 4/8-point spacing rhythm and 44-point interactive rows. Active logging reports Saved,
Syncing, Offline, or Needs attention; resumes entered sets after reopen; and requires explicit skip
actions. Historical corrections and HealthKit conflicts use review cards with confirmation actions.

The Train tab (2026-10-03 redesign, `lib/features/train/train_screen.dart`) reads top to bottom:

- **Header.** The large title "Train", today's date ("Friday 2 October") and the plan pill ("Week 3
  of 6"). The pill opens the plan sheet: title, block weeks and sessions a week, week pips, the plan
  rule when the plan has one, and "You approved this plan on 15 September. Changes always need your
  approval." At large text the pill moves under the title.
- **Day boxes.** Seven boxes for the week: a check for a done day, a dot for a planned day, a lime
  ring for today and a raised fill for the selected day. A tap plays the selection haptic and slides
  the day's content in from the side it came from (a crossfade under Reduce Motion). A horizontal
  swipe pages back up to three weeks (VoiceOver: "Previous week" and "Next week" actions); "Week of
  21 September" with a **This week** button shows while another week is open.
- **Readiness line.** Today's recovery sentence (data rules below) with Today's decision verdict as
  "Today: …" when the latest decision is for today. It opens **Recovery today**: sleep, heart rate
  variability (its ln baseline shown as `exp(ewma)`, "usually 55 ms"), resting heart rate and
  training load, each in plain words ("Normal for you", "More than usual", "Building your
  baseline", "Not enough data yet"). Without Apple Health it reads "Connect Apple Health to see
  recovery" and explains where to connect, with **Open Account** when the host passes one.
- **Needs your attention.** Apple Health repairs and workout matches share one group above the hero.
  A repair asks with a native confirm (**Confirm correction** / **Not now**); a match offers
  **Confirm match**, **Not the same workout** and, for another day, **Switch to that day**. Results
  are toasts.
- **Workout hero.** A kicker ("Today", a weekday, "Done on Tuesday", "Tuesday, not logged"), the
  name, "6 exercises, about 48 min" (a done day shows its logged minutes), the worked muscles as
  chips and on the turnable `MuscleMap` with a Front/Back control. The title area opens the
  **workout overview** sheet (objective, warm-up, exercises, cooldown, then **Start workout** or
  **View summary**); the map opens the **muscles sheet** (front and back side by side, a row per
  muscle with its sets and exercises, rows and muscles selecting each other, and the note that muscles
  come from the exercise catalog or Tracend's reviewed exercise list). When exercises with known
  muscles carry less than three quarters of the workout's planned sets, the map and chips are left out (a partial map would misdescribe the
  session) and the card says "Muscle map appears with your next plan." The one action is **Start workout** (heavy haptic), **Log this
  workout** for a past day with nothing logged, or **View summary** for a done day, whose sheet shows
  time, sets logged of planned, the athlete's own effort ("Not rated" for app defaults) and each
  exercise as logged. "Auto-completed from Apple Health" shows only when `completion_source` is
  `healthkit`. A rest day names the week's next workout with "See Sunday's workout".
- **Exercises.** One grouped list; every row opens the exercise sheet: today's target (load, sets ×
  reps, rest, reps in reserve), **Last time** and **Your best** from `get_my_exercise_history`, the
  heaviest set of each logged session as a chart (two sessions minimum, else "Not enough data yet";
  planned values are never charted) and a tip labelled **From your plan** (the exercise note) or
  **Plan rule** (the plan's progression rule). A first-ever exercise reads "First time. Pick a
  weight you can lift for every rep with good form." Offline without a saved copy it reads "Last
  time loads when you're online."; a saved copy says it is from this phone.
- **This week.** "2 of 4 done" with pips, then **Training load** (opens the load sheet below) and
  **History** ("6 workouts in 4 weeks", a sheet with friendly dates; a row opens its summary when its
  workout is known).
- **States.** Skeletons while the hub loads; "Your plan could not load" with the beta diagnostic and
  **Try again**; after a failed refresh the loaded plan stays with "Offline. Showing your plan from
  earlier."; "No active plan" with **Check again**; a cached 1.5 hub shows no pill and an
  unclassified load. Pull to refresh reloads the hub, the readiness line and the Apple Health
  candidate.

Train redesign data rules (2026-10-03, `lib/features/train/train_view_models.dart`), read by the
new Train screen:

- **Plan pill.** "Week N of M" counts 7-day weeks from `active_plan.effective_date` to
  `local_today`; after the block it reads "Week N" alone. A cached 1.5 hub (no dates) or a plan that
  has not started shows no pill.
- **Readiness line.** One sentence about state, never advice: Excellent ≥80 "Recovery is
  excellent.", Good ≥65 "Recovery is good.", Moderate ≥50 "Recovery is moderate.", Low ≥35
  "Recovery is low today.", Poor "Recovery is poor today.", no score "Building your baseline.",
  Apple Health not connected "Connect Apple Health to see recovery".
- **Training load sheet.** The verdict comes first, from the ACWR bands: "Lighter than normal for
  you" (< 0.8), "About normal for you" (0.8–1.3), "Heavier than normal for you" (to 1.5), "Much
  heavier than normal for you" (above 1.5); the "You" marker sits on a 0.5–1.8 scale. Day bars are
  the last 7 days of `daily_load`: easy, moderate or hard from the server's day level, a socket for
  rest, and "Calibrating" when the level is null (default effort). While any day in the 28-day
  window holds a default effort, the row reads "…, calibrating" and the sheet explains why. With no
  ACWR, or fewer than four sessions in the window, the sheet reads "Your load reading builds as you
  train" with no ratio or marker. One advice line, chosen only from the ACWR band and the monotony
  rule (> 2.0 means the days are too similar). "How this is calculated" gives the strain rule, the
  ratio with its 0.8–1.3 normal range, how a day is classed (fixed cut-offs until 8 rated days,
  then the athlete's own last 4 weeks) and the monotony line. Footnote: "Calculated from your logged
  workouts. No AI estimates."

Today's Action Stage contains one instruction, one reason, and one CTA with a sync chip
that refreshes Apple Health (when connected), the daily brief, and today's coaching
decision together, followed by the readiness readouts (Chunk 6): a full-width recovery
score with its five drivers (HRV, RHR, sleep, respiratory rate, prior strain), a real
7-day health trend from Apple Health, and training load (ACWR) folded into the session
plan card. Evidence is shown inline in these readouts (Chunk 7): drivers list their true
z-scores, missing signals say No data, and a recovery score appears only when at least
one component is usable. Apple Health connect/refresh controls and the sync status card
live in the profile only — Today never prompts for Health access. Progress uses
one date-ordered effective measurement timeline for its headline, raw chart, and recent
history; smoothing is never shown as the current weight.

**Status:** Authoritative MVP navigation, screen, and interaction behavior\
**Platform:** iOS-first Flutter app\
**Related authority:** [PRD.md](./PRD.md), [DESIGN_SYSTEM.md](./DESIGN_SYSTEM.md),
[AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md), and [SECURITY_PRIVACY.md](./SECURITY_PRIVACY.md)

## 1. UX Objective

Every core flow should answer without requiring chat:

1. What should I do now?
2. What evidence supports it?
3. What can I review or change?

The interface progressively reveals detail. It never hides uncertainty, consent, AI estimation, or
persistent plan changes.

### Sheets, confirmations and toasts

These rules apply to every flow; the components are specified in
[DESIGN_SYSTEM.md](./DESIGN_SYSTEM.md) §5.1.

- **Sheet** (`showTracendSheet`): a focused, self-contained task that can be abandoned, such as a
  check-in, a detail view or a picker. It always closes with a swipe down, a tap outside or the
  close button. A sheet holding unsaved input asks before discarding it.
- **Confirmation** (`showTracendConfirm`): one consequential step, named by its outcome (**Discard
  workout**, **Delete thread**). Deleting or discarding anything is always confirmed, with Cancel as
  the default choice.
- **Action sheet** (`showTracendActionSheet`): two or more related choices, such as leaving a
  workout (save or discard), with a separate Cancel.
- **Toast** (`TracendToast`): a short confirmation that something already happened ("Check-in
  saved"). It never asks for a decision, never carries the only copy of an error, and never
  announces a persistent plan or nutrition change (those are reviewed on dedicated screens, §10).

## 2. Information Architecture

```text
Today
├── Daily decision and evidence
├── Quick check-in
├── Scheduled action
└── Pending proposal

Train
├── Active plan
├── Workout execution
├── HealthKit quick-complete
└── History and amendments

Coach
├── Unified Tracend Coach conversation
├── Current decision explanation
├── Evidence and perspective expansion
└── Proposal review entry points

Nutrition
├── Current targets
├── Confirmed totals
├── Capture or enter meal
└── Meal history

Progress
├── Measurements and trends
├── Standardized photo sets
└── Weekly and monthly reviews

Account
├── Plan: Profile and goals
├── Health: Apple Health
├── Appearance
├── Notifications (reminders, rest timer alerts)
├── AI coach: AI coaching, AI usage this month, Coach conversations
└── Privacy: Export data, Consent history, Delete account
```

## 3. App Entry and Restoration

### New user

`Launch → Brand statement → Configured Supabase sign-in → Age/eligibility → Terms/privacy → Onboarding choice`

External private-beta builds use Sign in with Apple. Owner-only development builds may show email
and password fields under ADR 0002. Both routes establish a real Supabase session before protected
data is shown; neither route bypasses authentication.

The first launch says: **Your plan, explained by your data.** It does not show pricing or request
optional permissions before explaining their purpose.

The sign-in screen (2026-10 redesign) shows the brand mark (drawn with a dark T on light
surfaces), **Sign in to Tracend** (**Create your Tracend account** in that mode), the brand line,
a **Sign in / Create account** segmented control, filled email and password fields and one pill
button. The development copy is a single small line: **Private beta: email sign-in**.

### Returning user

`Launch → Restore session → Today`

- Restore selected tab, scroll position, and safe in-progress drafts.
- Restoring asks Auth whether the account and session still exist; an access token alone stays
  valid for up to an hour after its account is deleted.
- If Auth refuses the session (deleted account, revoked session, or a refused refresh token), the
  app signs out on this device and shows sign-in, never a connection error. A lost connection
  keeps the session and offers **Retry**.
- A refused session for an account that may still exist keeps that athlete's unsent check-in and
  Apple Health sync state, stored per athlete so no other account can read them, for their next
  sign-in. When Auth says the account no longer exists, its local data is removed.
- Resolve deep links only after authentication and authorization.

## 4. Onboarding

### 4.1 Shared eligibility and consent

1. Confirm age 18+.
2. Show the supported healthy-adult boundary.
3. Ask only eligibility questions required by the PRD.
4. If excluded, stop plan generation and show appropriate professional guidance.
5. Accept terms and privacy notice. The two checkboxes are check rows in a grouped list. They
   are **not linked** to any hosted text yet; that is acceptable only for the owner-only beta
   and is a public-release blocker (SECURITY_PRIVACY.md §15). No legal text lives in the app.
6. Choose whether to allow AI coaching. The disclosure names the provider (DeepSeek, operated by
   Hangzhou DeepSeek Artificial Intelligence Co., Ltd., on servers in China), the data it receives,
   and what works without it. **Allow AI coaching** and **Not now** are both valid answers.
   - Since 2026-10 the text is the server's current notice (`get_current_ai_notice`). The app
     records that notice's version, and the built-in text is shown only if it cannot load.
   - Without AI coaching, Tracend's rules build the starting plan.
7. Choose **Guide me** or **I know my current plan**.

An account that has not answered the current AI coaching notice (created before the question
existed, or asked again after the notice changed) answers it once before the app opens. While AI
coaching is off, Coach shows **AI coaching is off** with **Review AI coaching**, its composer is
disabled, and Today generates no AI decision. **Account › AI coaching** turns it on or off.

Meal-photo AI and progress-photo AI consent occur separately when their value is visible. Apple
Health is offered once, as the optional onboarding step below, and otherwise from the profile.

The first Apple Health sync on an account reads 31 dates (today−30), so the onboarding summary
and the baselines have four weeks behind them; later refreshes read the last 8 dates. The UI keeps
the partial/unknown states and never claims an empty result means permission was denied. Apple
Health state on the phone belongs to the signed-in athlete: another account on the same phone
starts as not connected.

### 4.2 Beginner: Guide me

The app since 2026-10:

```text
Eligibility → AI coaching → Path → Goal
  → Apple Health (optional: Connect, or Skip for now)
  → About you (sex, birth year, height, weight, optional target weight, daily activity)
  → Schedule (weekday chips, up to six; session length)
  → Equipment (chips; none = bodyweight)
  → Food & limits (diet; movements to avoid as chips; other limitations)
  → Your training (experienced: years trained, current plan, what has worked and stalled)
  → Current lifts (experienced, optional: barbell top sets — weight on the bar, reps, reps left)
  → Focus (optional: up to two muscles to bring up, up to three already strong)
  → Review → Continue to your coach
  → Coach questions (0–3 questions; skip any time) → Build my plan
  → Plan (approve, request changes, or reject)
```

- **Coach questions:** the coach reads the answers (usually under 30 seconds) and may ask up to
  three short questions with quick answers or a written one. **Skip and build my plan** is there
  while it reads; with no questions the plan builds straight away. Editing any earlier answer
  clears the follow-up answers, because they were asked for the old answers.
- **Apple Health** also shows the athlete's usual months next to the last weeks once it connects
  ("Strength: 3.4× a week usually · 1× a week lately", "Sleep: 6 h 50 min usually"), or says the
  plan uses the last 4 weeks when there are fewer than three earlier months.
- **The proposal** shows **Start at ‹kg›** on exercises Tracend set a starting load for, a
  **Focus** line under Training, and the usual months in **How we calculated this**. Train
  pre-fills the kg field with the starting load.

- **Apple Health** reads the last four weeks when the athlete taps **Connect Apple Health**, then
  shows what it found (days and categories). Nothing found explains Settings › Health › Data Access
  & Devices and offers **Try again**; the athlete can always continue. A failed read can be retried
  or skipped. Reopened after a sync that finished, the step shows it as connected. About you then
  starts the weight at the newest Apple Health weight from the last 14 days (labelled with its
  date, until the athlete moves it, and never over an answered weight) and shows average steps
  with a **Matches your steps** tag on the daily-activity answer they point to. The athlete's own
  answers are what count. Review shows what Apple Health contributed, and the proposal's **How
  we calculated this** adds the summary the plan used.
- **Build my plan** starts a server generation and shows **Building your plan**. The app polls the
  generation, so the athlete can leave and come back:
  - a running generation keeps waiting;
  - a finished proposal opens;
  - a failed one offers **Try again**;
  - an answered one returns to Review;
  - an expired one (proposals last seven days), or one that expires while the athlete answers it,
    shows **This plan proposal expired.** with **Build a new plan** and **Back to review**.
- **Movements to avoid** never appear in the plan. An athlete who wrote a limitation in an older
  build is asked to choose them (or none) before building.
- **Answers no safe plan fits** (for example, bodyweight only while avoiding every pushing and
  pulling movement) open the step to change, with what to change; nothing is built.
- **Request changes** asks "What should change?" and sends the note with the next build; it
  needs a note.
- **Sign out** stays available on every step, including while saved answers load.
- **Saved answers that fail to load** show **Your answers did not load.** with **Try again**;
  nothing is saved until they load, so defaults never overwrite them.
- **Goal:** nothing is preselected; each goal has a one-line description.
- **Inputs:** height, weight, target weight and session length are sliders with − and +
  buttons for exact values, read aloud with their unit. The birth-year number pad closes after
  four digits or a tap outside. Choice cards (AI coaching, path, goal, daily activity) show their
  selected state with a lime ring, a lime wash and a filled check. Fields are filled, buttons are
  pills, and multi-select answers (days, equipment, movements, muscles) are pill chips. Sex and
  the reps left on a top set are segmented controls; at large text sizes Sex becomes a list of
  rows so no label breaks mid-word.
- **Review** lists every answer (Apple Health, daily activity, equipment and its note, diet,
  movements to avoid, limitations, focus, and for an experienced athlete their training and top
  sets). Each row has
  **Edit**, which opens its step; that step's button reads **Save and return to review**. At
  large text sizes labels sit above their values.
- **Building your plan** says it usually takes under a minute and can take up to two.
- A draft from an older build continues at **About you**.
- The header reads **Step N of M · ‹section›**: 15 steps for an experienced athlete, 13 for a
  beginner, who skips Your training and Current lifts. Under it a thin segmented line has one
  segment per step: done steps solid, the current step lime. The step text is what VoiceOver reads.
- **Reject proposal** asks with a destructive confirm (**Reject plan** / **Keep reviewing**);
  **Request changes** opens a sheet titled **What should change?**.

The original target flow:

```text
Goal → Experience → Schedule → Equipment → Preferences
     → Nutrition context → Body baseline → Constraints
     → Optional HealthKit → Review → Generate proposal
     → Review assumptions → Approve plan
```

- Show section progress, not an inaccurate percentage.
- Autosave each completed section.
- Use visible labels and a short rationale for sensitive fields.
- Offer **I don’t know** where exact knowledge is unnecessary.
- Plan generation is an asynchronous named state; users may leave and return.

### 4.3 Experienced: Preserve what works

Add current plan, performance history, targets, observed strengths/weaknesses, adherence, and
plateau context. Final review separates **Kept**, **Adjusted**, and **Unknown**, preventing
arbitrary replacement of valid practices.

### 4.4 Initial plan approval

Show goal, assumptions, weekly structure, exercise prescription, nutrition targets, confidence,
missing information, and safety boundaries. Actions are **Approve plan**, **Request changes**
(with a note) and **Reject proposal** (after a confirmation; answers stay saved). Answers are
edited from Review. Generation never activates a plan.

The 2026-10 proposal screen shows:

- **Provenance:** **Proposed by AI (DeepSeek) · checked by Tracend**, or **Built by Tracend's
  rules**. The provider name comes from the shared display-name map
  (`lib/shared/ai_provider_names.dart`, matched by the model id's provider prefix), never the raw
  model id; an id outside the map reads **Proposed by AI · checked by Tracend**.
- **Confidence.**
- **The assessment.**
- **Training:** every training day with its exercises (sets × reps, RPE with the reps left in
  plain words, for example "RPE 7.5 (about 2–3 reps left)", rest).
- **Nutrition:** the targets, with the formula (resting energy × activity plus training, and the
  goal range) behind the collapsed **How we calculated this** disclosure.
- **For an experienced athlete:** what was kept and what changed.
- **The plan's reasoning:** why, benefit, downside, assumptions, and what is not known yet.

Approval activates exactly those workouts, then shows **You're set.** once: the plan, the next
session and its weekday, the daily calories and protein, and the Apple Health status, with **Go
to Today**. **Account › Profile and goals** lists the onboarding answers approval kept (sex, birth
year, daily activity, equipment and its note, movements to avoid, limitations, diet), read-only.

## 5. Today and Daily Coaching

```text
┌─────────────────────────────────────┐
│ Good morning                    (●) │  large title, date, account
│ Sunday 4 October                    │
│ Well recovered        [✓ Checked in]│  verdict + check-in chip
│ Sleep less than usual. Everything   │  what pulls the score down
│ else is normal for you.             │
│        ╱ ' ' ' ' ' ' ' ╲            │  tick ring: lit ticks split by
│       '    Recovery     '           │  driver (lime fine, amber down)
│       '       71        '           │
│       '    [ Good ]     '           │
│        ╲ +6 from yesterday╱         │
│ 61 ms                      52 bpm   │  HRV / resting HR vs normal
│ (HRV) (Resting HR) (Sleep short)    │  driver chips → drivers card
│ Strength foundation      Week 3 of 20│  plan progress
│ ┌ Sleep ─────┐ ┌ Load ── Normal ┐   │  bento tiles; tap opens the
│ │ 6h 48m     │ └────────────────┘   │  sleep card, the week's load
│ │ 1h 12m debt│ ┌ Fuel ── 92 g ──┐   │  or the fuel rail
│ │ ▬▬▬▬ stages│ └────────────────┘   │
│ └────────────┘                      │
│ ┌ Today's session ─────────────────┐│
│ │ Upper body A    4 of 15 sets     ││  one block per set, lime when
│ │ ▮▮▮▯ ▮▯▯ ▯▯▯ ▯▯▯ ▯▯              ││  logged in Train
│ │ ⚙ Coach · drop the last bench set││  advice, never applied
│ │ Open in Train ›                  ││
│ └──────────────────────────────────┘│
│ ┌ Your week ── 3 of 5 sessions ────┐│  recovery tick stacks + marks
│ │ ┋ ┋ ┋ no ┋ ┋                     ││
│ │ ● ● – ○  ● ○  –                  ││
│ └──────────────────────────────────┘│
│ [ Check in to start your day   (→) ]│  gate bar, until checked in;
│              Not today              │  then the tab bar returns
└─────────────────────────────────────┘
```

Hierarchy:

1. current decision and timestamp;
2. one primary next action;
3. freshness or missing input;
4. coach perspectives and evidence;
5. secondary history.

If no valid decision exists, show the approved plan and explain whether a check-in, sync, or retry
can improve guidance. AI availability never blocks the workout.

Reading order (rebuilt 2026-10-04 from the owner's chosen prototype: one recovery ring that
explains itself, then the day in tiles, the session and the week; the earlier dial, check-in bar,
workout card, coach note, 7-day trend, drivers and sleep cards fold into these):

1. **Large title**: a time-of-day greeting with the full date and the account avatar ("Open
   account"). At the largest text sizes the title is "Today" and the greeting joins the date. Pull
   to refresh runs the same sync as the hero's sync row.
2. **Hero**: the recovery band in words ("Fully / Well / Partly recovered", "Under-recovered",
   "Very under-recovered"; "Recovery not scored yet" without a score) and one line naming any
   driver a spread or more on the wrong side of normal ("Sleep less than usual. Everything else is
   normal for you."). Beside the verdict, **Checked in** once today's check-in is saved (tap to
   update it), or a lime-edged **Check in** chip after "Not today" or when Today has no gate.
   - **Tick ring**: 112 ticks; the lit ticks run to the score and are split between the drivers
     that counted, in proportion to their weights, lime when a driver is normal or better and
     amber when it pulls the score down, with a one-tick gap between drivers and a taller head
     tick with a dot. Inside: "Recovery", the score counting up, the band pill and "+6 from
     yesterday" (left out when yesterday was not scored). Tapping the ring opens the drivers card
     in place.
   - **HRV and resting heart rate** under the ring, each against your normal ("HRV · higher than
     usual"): the HRV the score used (last night's, or this morning's) and yesterday's resting
     heart rate; a missing reading is left out.
   - **Driver chips** (HRV, Resting HR, Sleep, Breathing, plus Training when it pulls down; a
     morning estimate shows Check-in once it counts and no Breathing):
     "Sleep short", "HRV low"; grey "… no data" when a driver did not count. A chip lights only
     its driver's ticks and opens the drivers card (`RecoveryReadoutCard`, with "How this is
     calculated").
   - The source and confidence line: "From last night · High confidence", or "Morning estimate,
     no night recorded · Medium confidence · Settles at 12:00" until noon (recovery modes,
     ALGORITHMS.md §1). Then the sync row, and any sync issue, as before.
3. **Plan progress**: the plan's title and "Week 3 of 20" with a thin bar; past the block, "Week
   22 · block of 20 done".
4. **Tiles**: Sleep (tall: duration, sleep debt or quality, a deep/REM share bar from Apple
   Health), Load ("Normal", "Lighter", "Heavier", "Much heavier", or "Building"; this week's
   strain bars) and Fuel (protein to go and a bar; without a target, what was eaten). Tapping a
   tile opens its card under the tiles, one at a time: the sleep card, the week's load with its
   ratio, or the fuel rail with **Log a meal** → Nutrition. All three stack from 1.3× text.
5. **Today's session**: the workout name, its summary, and a strip with one block per prescribed
   set grouped by exercise, filling lime as sets are logged in Train ("4 of 15 sets logged",
   "Done · 15 sets logged"). The coach's note sits under it: today's first training adjustment,
   else today's training summary, as advice in its own words; a decision from another day is not
   shown, and with AI coaching off or no decision the panel says so. **Open in Train** (and the
   header) goes to Train when the shell wires it, otherwise it opens the workout. With no workout
   it reads **Rest day** and names the next planned session.
6. **Your week**: "3 of 5 sessions done" and "Recovery averaged 62 this week" (scored days only),
   then Monday to Sunday as stacks of ten ticks lit to each day's recovery (lime from 50, amber
   below; "no data" without a score; later days empty) with a mark: filled dot trained, ring
   planned and still ahead, hollow grey ring planned but not logged, dash rest. Tapping a day
   names it below ("Tuesday · recovery 48 · planned, not logged").
7. A closing line: "Calculated from Apple Health and your logs. No AI in the numbers."

**Morning check-in gate** (owner, 2026-10-04): until today's check-in is saved, the tab bar gives
way to one lime bar, **Check in to start your day** ("About a minute · sharpens today's call") with
an arrow, and **Not today** under it. Saving the check-in (delivered or queued offline) or "Not
today" brings the tab bar back for the rest of the day; both are remembered on the phone for that
date. The gate never locks the plan: "Not today" always lets the athlete through.

Loading shows skeletons in the shape of these sections (one VoiceOver label, "Loading Today"),
never a spinner. Transient results (sync, check-in saved) are toasts.

### Quick check-in

A sheet collects sleep quality, energy, soreness, hunger, mood, pain, availability, and an optional
note. Each 1–5 question is a vertical list of labelled answers, full-width rows of at least 48pt
with a check on the chosen one, so it fits a 320pt screen at the largest text sizes:

| Question      | Answers, shown top to bottom                                | Stored |
| ------------- | ----------------------------------------------------------- | ------ |
| Sleep quality | Very poor, Poor, OK, Good, Great                            | 1 → 5  |
| Energy        | Very low, Low, OK, Good, Great                              | 1 → 5  |
| Soreness      | Very sore, Sore, A bit sore, Good, Great, not sore          | 5 → 1  |
| Hunger        | Not hungry, A little hungry, Normal, Hungry, Very hungry    | 1 → 5  |
| Mood          | Very low, Low, OK, Good, Great                              | 1 → 5  |

Soreness is reversed so the best answer always sits last: "Great, not sore" is stored as 1. Every
question starts at 3, as before. Pain is **No pain** (0) or **Some pain**, which asks "How strong,
from 1 to 10?" and will not save until a strength is chosen; it is stored as `pain_severity` 0–10.
The note's counter appears only in its last 100 characters. **Save check-in** is pinned below the
questions, so it is always on screen. The stored values and the `save_daily_check_in` payload are
unchanged. Pain location questions and the safety boundary remain future work. Save updates Today
and recomputes only when necessary.

### Evidence detail

Readiness evidence is shown inline, not hidden behind a tap. The recovery drivers are plain rows
in the composite's weight order: "Heart rate variability: normal for you, 58 ms", then resting
heart rate, sleep, breathing rate and recent training. The words come from the true z-score
against the athlete's own baseline: within one spread reads "normal for you", one spread or more
"higher/lower than usual" (sleep and training say "more/less"), two or more "much …". Resting
heart rate and breathing rate read the measurement, not the z sign, because their z-scores are
negated in the composite. An unusable component reads "not enough data yet" and never shows a
number; a valid sleep reading whose baseline is still maturing shows the measurement with
"baseline still building".

The z-scores sit behind **ⓘ How this is calculated** (authority-doc change 1, 2026-10-03): it
explains the baseline comparison in plain words, lists each driver's weight and true z-score ("Not
used today" for an excluded component), and ends "Calculated from your Apple Health data and logged
workouts. No AI." Under the method it says which mode scored today: last night's HRV against
your nights, or a morning estimate from the HRV taken 4:00–12:00 against your mornings plus the
check-in, settling at noon. A morning estimate's rows read "Morning HRV", "Morning check-in"
("feeling good", "feeling about OK", "feeling rough") and "61 bpm yesterday", with no breathing
row. The disclosure is a VoiceOver button with an expanded state. The confidence word
stays visible on the verdict card.

**Evidence visualization.** The 7-day trend plots one metric (heart rate variability, then sleep,
then resting heart rate; the first with four recorded days) as one column per calendar day:
graphite columns, the latest recorded day in lime with a lime outline and the single idle pulse,
and an empty socket for a day with no data. Columns are scaled between the series' own minimum and
maximum, marked by hairline rails, and the caption states it: "Range 49–58 ms · 6 of 7 days
recorded · As of 3 Oct, Apple Health". Day labels are 12pt day-of-month numbers, the latest in lime
ink. The change since the first recorded day is neutral ("Up 6 ms since 27 Sep"). Fewer than four
recorded days reads "Not enough data yet". VoiceOver reads one summary of the range, the latest
value, the recorded-day count and the change. Full motion grows the columns west to east, Reduce
Motion fades the chart in, and nothing moves under static motion.

Sync source and freshness live in the profile's Apple Health status card and on the verdict card's
sync row (last health sync time), in ordinary coaching language. Deterministic calculation and AI interpretation are
labeled separately. Training and Nutrition remain perspectives in one controlled decision
pipeline, not independent agents. The Coach tab provides direct user questions through the
same workflow and never behaves like three separate autonomous chatbots. A live assistant
message carries the small label **AI answer · DeepSeek**, naming the provider by its display name
from the app's provider map (never a raw id such as `deepseek`; an unlisted provider reads **AI
answer**). A provider or validation failure never substitutes generic coaching text. Replies display bold, italic, and bullet or numbered lists, so they read as formatted
text rather than raw Markdown.

When the model cannot answer, Coach shows a labeled reply in its place, always visible and never
with a provider label:
- "Data summary · not an AI answer": what the athlete's data shows.
- "Safety note · not an AI answer": for a message that may concern a health risk.

A live labeled reply also shows a beta diagnostic line (failure code and rule names) as small
secondary text, inside **Evidence used and data gaps** when the reply has one and under the reply
otherwise; a stored one keeps only its label, because the diagnostic is not stored. Retry appears
when the reply ends the conversation, and it keeps whatever the user is typing.

Other failures (sign-in, database, limits, network) show one inline message under the question
that failed, in place of the reply: what happened in plain words, then the raw diagnostic as a
small second line, and **Retry**. A toast ("Coach couldn’t answer") marks the moment; it never
carries the only copy of the error (redesign doc change 2, replacing the inline alert card and
Snackbar). A timeout says the Coach took too long. During the private beta the diagnostic line
shows the raw text, including the HTTP status and the server's stable code, so the owner can see
where a failure comes from (owner decision, 2026-09-27). The server never sends parser messages,
provider bodies, prompts, or health context.

Today uses a real timeline for check-in, workout, meal, and review actions. The primary
decision always uses **Do this next** and remains actionable when AI is offline. A missing
readiness signal becomes a direct recovery action (sync Apple Health or add a check-in).

Coach shows an expandable **Your coaching context** card on a new conversation, before its first
message; an ongoing conversation shows no cards above it. It lists approved
plan, goal/profile, Apple Health, check-ins, confirmed nutrition, completed Tracend workouts,
measurements, and conversation history with honest availability/count/latest-date metadata. Its
summary counts connected sources ("4 of 6 sources connected") and dates read as words ("latest
yesterday", "latest Thu 24 Sep"), never ISO dates.
Model-cited evidence and actual data gaps use **Evidence used and data gaps**: the cited evidence
with its source in words ("Calculated from your health data"), the data gaps in words
(`recovery_check_in` reads **Morning check-in**), the reasoning steps without their evidence ids,
and the beta diagnostic. Generated follow-up ideas use the separate **Suggested next actions**
heading.

## 6. Workout Execution

`Train → Workout preview → Start → Focus logging → Finish (session effort) → Summary`

Logging is a full-screen cover (`ActiveWorkoutScreen`, redesign PR 3, 2026-10-03) in focus mode:
one exercise per page.

**Header.** A chevron-down (leave), the workout name over the elapsed time (ticks every second;
amber past 3 hours, when a banner says the workout saves as 3 hours), and the lime **Finish** pill.
Under it, a segmented bar with one segment per set (done segments are good green) and the sync
state as a small icon plus a word: **Saved** (good), **Syncing** (neutral), **Offline** (caution;
the draft is on the phone) or **Needs attention** (low; the server refused the draft).

**Focus page.** Swipe sideways between exercises (selection haptic); the screen opens on the first
exercise with sets left.

- "Exercise N of M", the name, "4 sets of 6–8 · RPE 8", the exercise's muscles as text, and a small
  front and back `MuscleMapPair` when its muscles are known (catalog or reviewed list). Otherwise
  there is no map and no muscles; nothing is inferred at run time.
- Set dots: done sets green, the current set lime.
- The set card: "Set 2 of 4", the rest after it, and big kg × reps readouts with −/+ (2.5 kg, one
  rep; kg can be emptied for no added weight) that can also be typed. The starting values are the
  set's own entry, else the set done before it today, else the same set last time, else the plan's
  starting load and lowest rep target, and a quiet caption names the source (**From your last
  set**, **From last time**, **From your plan**). Nothing is logged until **Done set N**.
- The strip under the readouts: **Last time** and **Your best** from `get_my_exercise_history`
  (**Not enough data yet** for a missing half); a **First log** tag and "No earlier sets for this
  exercise." the first time; "Last time and best need a connection." when neither the server nor
  the phone's copy has the history; a skeleton line while it loads.
- **Done set N** (60 pt) logs the kg and reps shown with a light haptic. When every set is done the
  card reads "All N sets done" with **Next exercise**, or tells the athlete to tap Finish on the
  last exercise.
- **Logged**: each done set with its number, "62.5 kg × 8" (or "12 reps"), a **New best** or
  **First log** mark, its effort (**RPE 8** or **Add effort**) and undo. Undo clears that set's
  effort.
- Tools: **Pain or discomfort** stays a visible chip (**Pain noted** in caution when on). **Fill
  effort** and a ⋯ menu whose only action is **Mark as skipped** (an action sheet with **Keep
  logging**). Logging a set on a skipped exercise unmarks it.

**Set effort (RPE).** Optional on every set: a compact 1–10 picker with plain words (5 "5 or more
reps left", 6 "4 reps left", 7 "3 reps left", 8 "2 reps left", 9 "1 rep left", 10 "Nothing left";
1–4 "Very light"/"Light"). Blank is allowed (**Not now**, **Clear**). **Fill effort** gives one
value to the logged sets of that exercise that have none, leaves the others alone, and says how
many it filled; each set stays adjustable afterwards. Set effort is separate from session effort
and never feeds it.

**Rest.** Done set starts the exercise's rest (`rest_seconds`) when something follows it:

- A full-screen lime ring with the time left, "Next: Set 3 of Bench press" (or the next
  exercise), −15, +15, Skip, and the effort picker for the set just done. It covers the page, not
  the header, so Finish and leave stay reachable.
- A swipe down, a pull past the top or **Hide** shrinks it to a floating pill (ring, "Next: Set
  3", ±15 at normal sizes, Skip) above the page; a tap on the pill opens the ring again. The rest
  never blocks editing.
- The end time is stored in the draft (`rest_timer`), so a relaunch brings the rest back as the
  pill; an expired one is cleared.
- The end plays the success haptic and the toast "Rest is over. Next: …".
- The lock-screen alert ("Rest timer finished") is scheduled through `RestTimerController` only
  when **Rest timer alerts** is on and allowed. Skip, the in-app end, finishing, discarding and
  leaving all cancel it.

**New best.** A done set is a new best only when it beats the history's best set and every
earlier set of that exercise today, by the history's rule (`newBestSetIndexes`). The moment: a
medium haptic, a lime burst from the Done button and a large "New best" stamp on the set card
(about 2.8 s), then the small mark on the logged set. Reduce Motion fades the stamp in with no
burst; without motion only the mark shows. Unknown history never announces one; a first-ever
exercise shows **First log** instead. Undo recomputes it.

**Leave.** The chevron, the system back and the edge swipe (`PopScope`) open an action sheet:
"Leave this workout?" with how many sets are saved on the phone, **Save and leave** (the draft is
kept; toast "Workout paused"), **Discard workout** (destructive, then a confirm "Discard this
workout?" naming that the logged sets are deleted; calls `abandon_workout`, toast "Workout
discarded") and **Keep logging**.

**Finish.** With no set done, Finish plays the warning haptic and the toast "Tick at least one set
first." Otherwise a sheet asks "How hard was this workout overall?" on a required 1–10 scale with
nothing preselected (1–2 very easy, 3–4 easy, 5–6 moderate, 7–8 hard, 9 very hard, 10 max).
**Finish workout** without a number shows "Pick a number from 1 to 10 first." The sheet says "N
sets are not logged. They stay unlogged, not skipped." (the server keeps an untouched exercise
`unknown`, PRD; only an exercise marked skipped is saved as skipped) and that this number sets the
training load. Finishing
syncs the draft, then calls `complete_workout_v2` with the athlete's `session_effort`
(`completeWithEffort`) and the duration capped at 3 hours.

- If the finish cannot reach the server, a banner "Finish not sent yet" keeps the effort and the
  duration on the phone with **Send finish**; reopening the workout offers the same banner from
  `loadPendingFinish`. A server refusal adds its message as small secondary text.
- On success: the success haptic and the summary sheet: a check, "Workout complete", a card with
  the date, the workout name, Time, Sets and **Weight lifted** counting up (`weightLiftedKg`, with
  "Counts sets with added weight, as you logged them."), the new bests stamped on with their
  previous best, and "How hard it felt". **Done** closes it, the toast "Workout saved" shows, and
  the cover closes back to Train, which refreshes.

**A finished workout** opens read-only: "Completed · 45 min", **Done**, and each exercise's logged
sets. "Marked complete from Apple Health" shows only when the session's `completion_source` is
`healthkit`.

Other rules: prefill is only ever an unconfirmed starting point; autosave keeps a local draft
(250 ms after a change) and syncs it, retrying a workout that started offline; substitution
requires a reason and shows whether the objective is preserved; later corrections to a completed
session create audited amendments.

## 7. HealthKit Quick-Complete

When Apple Health records a workout on a day the user has a scheduled Tracend workout but no
completed session, Train presents a prompt card instead of the normal **Start workout** button:

- Kicker: **Apple Health detected workout** with `heart_fill` icon.
- Workout name.
- Explanation: _Apple Health recorded a [N] min workout [today / yesterday / on Mon D]. Did you
  complete [workout name]?_
- Two inline buttons: **Yes, mark complete** (filled) completes the session with HealthKit-backed
  duration, creates an audit event, and refreshes adherence. **Log manually** (outlined) opens the
  standard workout execution flow.
- After either action, the hub refreshes and the prompt is absent on subsequent loads (the
  already-completed guard prevents duplicate prompts).

The candidate is queried per selected weekday via the lightweight
`get_healthkit_completion_candidate` RPC. Tapping any weekday in the strip (past or today) fetches
the candidate for that date's most recent occurrence. Future weekdays are never queried.

This is a deterministic check (HealthKit data exists, no completed session exists) combined with
explicit user approval. The auto-completed session records
`'Marked complete from Apple Health
evidence'` in its notes and writes an `audit_events` row with
`action_code='workout.auto_completed'`.

The prompt sits inside the workout hero in place of **Start workout**, under the kicker **Apple
Health detected workout**. The day boxes show a check for completed days and a dot for planned
days; a completed day's hero reads "Done on Tuesday" with **View summary**.

## 8. Nutrition and Meal Confirmation

The active schedule places **Next meal** first with local time, planned foods, quantities, status,
and **Log meal**. Macro totals come next, labeled **From confirmed meals**, and count confirmed
consumption only.

The totals card shows calories, protein, carbs and fat in sentence case, with numbers in the
numeric face. Protein, carbs and fat each carry a small colour key that matches the meal split bars;
the words, not the colours, name them.

Below them, **Today's meals** is one vertical day timeline in time order, in one card with hairline
separators. It merges the schedule and the logged meals: a confirmed meal logged from a slot
replaces that slot's planned row. Every row has a time, a marker, and a state word, so color is
never the only signal:
- Logged meals read **Lunch · 691 kcal**, then **Logged** and their foods from `meal_items`, then a
  protein / carbs / fat split bar, with a **⋯** control that opens an action sheet holding **Delete
  meal**.
- A draft shows **Needs review** and a **Review foods** action.
- Unlogged slots show **Due now**, **Planned**, **Optional**, or **Not logged** with their planned
  foods and a **Log** action.

One **Log a meal** button follows the timeline. It opens the **Log a meal** sheet, which first picks
the meal type with chips (preselected by time of day: Breakfast before 10:30, Lunch before 15:00,
Snack before 17:30, then Dinner) and then offers **Take a photo**, **Choose from Photo Library**, or
**Enter manually** as one grouped list. A photo meal is saved under the chosen type. The coach's
nutrition guidance sits at the end of the screen under a sentence-case **Coach** label, with its
confidence in words.

Nutrition uses the large title with the selected day as its subtitle, and pull to refresh reloads
the day and the coach's guidance. Below the title, a week strip shows the week's date range with
previous and next week chevrons, then seven day boxes. Today carries the lime ring; the selected
day sits on a surface box; days after today are disabled; the next-week chevron stops at the
current week. Changing the day plays the `selection` haptic. Previous dates visibly identify a
saved daily log and reload confirmed totals and meals. While a day loads, skeletons stand in for
the totals and the timeline: another day's data never shows under the selected day. A day
boundary never implies deletion.

Feedback: confirming a meal (manual entry or reviewed candidates) plays the `success` haptic and
shows a **Meal logged** toast; a deleted meal shows **Meal deleted**. Failures stay on the page in
words, never only in a toast.

`Nutrition → Capture or enter manually → Analyze → Review candidates → Resolve catalog → Confirm meal → Totals`

```text
AI observation                 Confirmed meal
┌────────────────────┐        ┌────────────────────┐
│ Chicken?  medium   │  edit  │ Chicken breast     │
│ Rice?     high     │  ───›  │ 160 g              │
│ Oil       unknown  │        │ Basmati rice 220 g │
│ [Add missing item] │        │ Cooking oil 10 g   │
└────────────────────┘        │ [ Confirm meal ]   │
                              └────────────────────┘
```

- Explain that portions and hidden ingredients are estimates.
- Processing may continue in the background.
- Candidates remain visibly unconfirmed and editable.
- Low-confidence portions require correction or confirmation.
- Totals include only confirmed items.
- Editing a candidate uses visible labels and inline validation; changes and selection are applied
  together only by **Confirm selected foods**.
- A draft meal remains visible in the timeline as **Needs review** with a **Review** action that
  restores its candidates; users never need to create a second analysis to resume unfinished review.
- Meal forms dismiss the keyboard by dragging, tapping outside a field, or an explicit **Hide
  keyboard** control. This control is required for iOS numeric keyboards that do not provide a
  native Done key.
- Each timeline meal's **⋯** control opens an action sheet with a labeled **Delete meal** action.
  Deletion then requires a destructive confirmation (**Delete this meal?**, Cancel as the default)
  explaining that the meal leaves the day's totals.
- **Enter meal** and **Review candidates** are sheets. Each candidate shows its serving, calories
  and confidence in sentence case (**Medium confidence**).
- Failure offers **Retry**, **Enter manually**, and **Delete photo**.
- While a photo is analyzed, the brand loader and **Analyzing meal photo…** appear under **Log a
  meal**. A failure is shown in
  the same place, never only at the top of the screen, out of view. A refused camera or photo
  permission names the iOS setting to change. Four outcomes say what happened in plain words: a
  library photo iOS could not load (`invalid_image`, usually an iCloud photo that did not
  download), no food in the photo (422 `meal_no_food_found`), the provider's free tier being busy
  (429 `meal_vision_busy`, about one photo a minute), and the AI budget being reached (429
  `ai_usage_limit`). Any other failure says the analysis did not work and keeps the beta
  diagnostic on a smaller second line naming the step (`picker`, `upload`, `draft`, `analysis`) and
  its error code, for example `Beta diagnostic · analysis: 503 meal_analysis_unavailable`.

## 9. Progress Review

### Measurements

Show protocol, date, unit, source, confirmation, trend, and correction path. Manual and HealthKit
values never silently overwrite each other.

The first confirmed entry is a baseline, not a trend. At least two dated entries are required before
showing a calculated delta. Manual entry uses visible units, inline validation, keyboard dismissal,
and clear save feedback.

Progress provides period selection for measurements, comparable strength, workout adherence,
confirmed-nutrition coverage, weekly review, and private photos. A chart appears only after two real
dated comparable observations.

The screen reads top to bottom as one answer, then detail:
1. A **4W · 12W · 6M** segmented control (default 12W) that scopes the weight change, chart, and
   workout count. The header **+** records a measurement.
2. The weight hero (`WeightHeroCard`): a sentence-case **Weight** label, the latest weigh-in in the
   numeric face and its date, change since the first weigh-in in the period, the weekly rate, a
   plain-word trend steadiness, and the chart. The change chip takes the lime signal only when it
   moves toward the active goal (`fat_loss` down, `muscle_gain` up); the arrow and the spoken
   "toward your goal" carry the same meaning. With no weigh-in it asks for the first one; with one
   in the period it asks for another before drawing a trend.
3. **This week:** the weekly review card (§11).
4. **Recent weigh-ins:** the newest three in one grouped list, each with its change from the one
   before; **See all** opens every weigh-in in a sheet. A row opens the read-only detail sheet.
5. **Strength:** workouts done of planned in the period, then a horizontal row of best confirmed
   lifts (**Best · 6 workouts**). A lift tile shows a lime **New best** chip only when
   `get_my_exercise_history` dates the lift's all-time best set to its latest completed session,
   that session is the one the hub reports as the lift's latest, and an earlier session existed to
   beat. Ties keep the earlier date, so repeating a record is never new; unknown history shows no
   chip.
6. **Progress photos:** one card with the last set's date, **Take progress photos**, and **View past
   sets**.

Progress uses the large title, and pull to refresh reloads the page and the physique check. The
first load shows skeletons in the shape of the hero and sections; a period change keeps the last
answer on screen, dimmed, until the new one arrives. Record measurement, all weigh-ins, the
weigh-in detail, the weekly review, photo capture, past sets and the private viewer are sheets.
A saved weigh-in plays the `success` haptic and shows **Weigh-in saved**; a requested review and a
deleted photo set also confirm with a toast. A failed action shows a dismissible notice in words
beside the control that started it (the top of the page, the weekly review card, or the photo
card), never only in a toast.

### Coach conversation

Coach opens a familiar saved-thread conversation. The daily Head Coach decision is on Today, not
pinned above every conversation (owner report, 2026-09-30):
- It reopens the conversation last opened on this device, otherwise the one with the newest
  message. With no saved conversation, it starts a new one.
- A new conversation, from launch or from New, is saved only when its first message is sent.
- Saved conversations lists only conversations that contain a message, newest first, and
  refreshes after every send.

Layout (redesign, 2026-10-03):
- **Header:** the iOS large title **Coach**. The saved-conversations button stays pinned at the
  top right, where the inline title bar appears once the title scrolls away, so it is in reach at
  the end of a long conversation.
- **Saved conversations** is a sheet: **New conversation**, then one grouped list (title and
  friendly date; the open one reads **Open now**). Swiping a conversation left asks **Delete this
  conversation?** with **Delete conversation** as the destructive choice and Cancel as the default;
  VoiceOver offers the same delete as an action. Deleting the open conversation starts a new one.
  A delete that fails puts the row back and says so.
- **Messages:** the athlete's own messages are filled bubbles on the right; Coach replies are
  plain text on the canvas, with their labels, evidence disclosure and follow-ups below.
- **Waiting:** "Coach is thinking" with three dots in the place the reply will appear; the dots
  rest under Reduce Motion.
- **Composer:** a filled pill field and a round lime send button, which turns lime once there is
  something to send. Sending plays the light haptic. A rate-limit cooldown shows its countdown in
  the field.

The composer supports multiline input, keyboard-safe positioning,
sending/typing/cancel states, selectable long answers, suggested questions, and expandable
evidence/limits. Persistent suggestions route to the existing proposal approval screen and never
apply in chat.

### Progress photos

`Explain purpose → Separate consent → Capture guide → Validate front/side/back → Review → Save private set`

Guide distance, pose, framing, lighting, clothing consistency, and timing. Retake remains available.
Physique photos never appear in general dashboard surfaces or notifications.

Capture requires explicit storage consent, then opens a capture sheet that lists front, side, back,
and lower body with framing guidance, a check per finished pose, and how many are done. The user
explicitly opens the camera or library for a pose; the native camera is never launched without this
in-app context. Errors stay inline in the sheet, and **Finish later** keeps a partial set open.
Completed and partial sets are listed under **View past sets** with labeled view and delete
controls. Deleting a set asks first with a destructive confirmation (**Delete this photo set?**,
Cancel as the default). Viewing uses short-lived authorization. Storage consent is an alert with
**I agree and continue** and Cancel.

**Physique check (2026-10, owner-only experiment).** Only for accounts the `physique-check`
function serves; everyone else sees no change and the card still says photos are never sent to AI.
For a served account, the card says photos are sent to Groq only when a check is started, and
offers **Physique check** on the newest complete set:
`Consent sheet (server notice, first time or after a new notice) → Checking (usually under 30 s) →
Result: "AI visual estimate, not a measurement", muscles with confidence and reason, observations,
photo tips, limitations → choose up to two → Use as my focus`.
The newest set is the one taken last (`captured_on`, then `created_at`). A stored check stays
visible after the feature is switched off for the account, and the card then says a set was sent
to AI only for a check the athlete started, never "never". Deleting a set removes its checks from
the card at once. Nothing changes without that confirmation; the Coach uses the focus at once and
the plan at its next review. Errors (consent, today's AI limit, Groq busy, photos that cannot be checked, photos
that show no physique to judge, an unusable answer) stay inline in the sheet. **Turn off photo checks** records a withdrawal.

### Comparison

The user selects two standardized sets. Show photos privately, measurement/performance trends,
confidence-qualified visual observations, and **AI visual estimate, not a body-composition
measurement**. Facial recognition, medical inference, and unrelated trait inference are prohibited.

## 10. Persistent Change Approval

`Decision indicates proposal → Proposal diff → Evidence → Accept / Reject / Request revision → Result`

- Open proposals as dedicated screens, never chat suggestions or toasts.
- Keep current and proposed versions visible together.
- Accept requires an explicit final action and displays effective date.
- Reject changes nothing and may collect an optional reason.
- Request revision preserves the active plan.
- Stale proposals cannot be accepted; explain what changed.

## 11. Weekly Review

Use an editorial sequence rather than a dashboard wall:

1. outcome summary;
2. execution and adherence;
3. recovery context;
4. training and nutrition evidence;
5. what remains unchanged;
6. any proposed adjustment; and
7. next-week focus.

Every claim links to source data. Charts include units, direct labels or legends, accessible
summaries, and large touch targets.

Before a review exists, Progress offers a labeled generation action. Queued, processing, retryable,
failed, and ready states remain explicit while the approved plan stays usable. A ready review shows
the week, deterministic/no-AI label, evidence counts, missing categories, unchanged plan/targets,
next focus, and a **Mark reviewed** acknowledgement action.

## 12. HealthKit and Permissions

`Contextual prompt → Explain exact value/types → iOS permission sheet → Sync → Data status`

- Ask in context and by supported type.
- Do not interpret missing read data as proof of denial.
- Distinguish connected, partial, stale, unavailable, and manual-only.
- A partial label counts data categories with samples in the sync window; it does not claim that an
  empty category proves permission denial. Show found and missing categories in plain language.
- Today's health evidence is inline: the recovery readout's five driver rows and the
  7-day trend. The trend draws only when at least four real recorded days exist inside
  its window; otherwise it shows the missing-data action ("Building baseline"). Apple
  Health connect/refresh controls and the sync status card live in the profile only.
- Revocation keeps manual features usable and explains iOS settings.
- Sync shows date range and last success instead of an indefinite spinner.

## 13. Privacy, Export, and Deletion

### Account and AI usage

Account opens as a native detail destination from the Today account control. Since the 2026-10
redesign it is one iOS inset-grouped settings page:

- **Identity:** the name from the email local-part, a **Private beta** chip and **Current goal**
  when the active-goal query returns one. There is no separate Edit control; **Profile and goals**
  is the edit entry.
- **Plan:** **Profile and goals** opens the read-only screen of that title (goal, training
  profile, onboarding answers, approved plan) as grouped label/value rows.
- **Health:** **Apple Health** with its status in plain words ("Updated today at 14:05",
  "· needs a refresh", "· some signals missing", or "Not connected · manual logging works"). It
  opens a sheet with the full status card and **Connect** or **Refresh Apple Health**.
- **Appearance:** a **System / Dark / Light** segmented control that applies at once.
- **Notifications:** switch rows that apply at once: **Daily check-in reminder** (every day at
  7:00 PM), **Weekly review reminder** (Sunday at 6:00 PM) and **Rest timer alerts**. The footnote
  says lock-screen text stays generic. The rest-timer row names its lock-screen text, "Rest timer
  finished"; when iOS has not been asked yet, turning it on first shows that text in a confirm,
  and only **Continue** leads to the iOS permission request. **Not now**, off or a denied
  permission keeps the rest timer in the app only, and a denial points to iOS Settings. There is
  no in-app haptics toggle; the iOS setting governs haptics.
- **AI coach:** **AI coaching** (on with the provider name from the server notice, or off),
  **AI usage this month**, and **Coach conversations** (a sheet; deleting a conversation asks
  with a destructive confirm). The footnote says provider keys stay on the server.
- **Privacy:** **Export data**, **Consent history** and **Delete account**, then **Sign out** at
  the foot.

Sheets use the Tracend sheet, confirmations the destructive confirm, transient results a toast,
and loading the brand loader.

**AI usage** shows only the authenticated user's sanitized current-period request count, token or
image usage where meaningful, estimated cost, and service availability. It never reveals API keys,
prompts, provider request identifiers, raw errors, or another user's aggregate. Values are
operational estimates, not invoices or subscription quotas. This month's cost is shown against
the warning and stop limits **from the server budget state only** (never hard-coded), as a meter
with a tick at the warning threshold and in the Account row ("$0.42 of $2.00 · warning at $1.00").
Dollars show two decimals; a cost above zero that would round to nothing reads **<$0.01**, never
**$0.00**. Refresh usage refetches the live summary. When budget fields are unavailable the screen
degrades to run counts and estimates without threshold claims.

Provider setup is not a mobile flow. If the owner has not configured a server-side provider secret,
Account shows **AI service not configured** and explains that approved plans and manual logging
remain available.

Privacy screens show consent by purpose, provider disclosure, photo retention controls, connected
data, export, and deletion.

**Consent history** (formerly the consent ledger) is read-only: the latest `consent_records` entry
per purpose (terms, privacy, AI coaching, progress photo storage, progress photo AI,
notifications). Each row leads with the choice and its date ("Granted 2 Sep 2026"); the notice
version and where it was made ("Version ai-coaching-v1 · iOS app", or "Set up during testing" for
owner-development records) are secondary text. Purposes without a record say "No choice recorded
yet". The screen never edits records; withdrawal happens through the flow that owns each purpose.

- Export and deletion require recent authentication.
- Export asks for the account password and a separate 12-character export password, explains media
  inclusion and expiry, and exposes download only when ready. Tracend cannot recover that password.
- Deletion explains complete irreversible scope, requires the password and exact `DELETE`, then
  a destructive confirm (**Delete your account?** with **Delete account** and a bold **Cancel**)
  before anything is sent, and returns to signed-out state only after the server confirms it (its
  reply, or Auth reporting the account gone). A toast then says the account was deleted.
- The wait is bounded: the app stops waiting for the reply after 60 seconds, then asks the server
  where the deletion stands a few more times. If it is still running, the sheet says it has not
  been confirmed yet and offers **Check again**. A failed deletion says the account remains.
- Reopening the app after an interrupted deletion that finished lands on sign-in; deleting again
  never asks for the password of an account that is already gone.
- Withdrawing photo-AI consent stops new processing and applies
  [SECURITY_PRIVACY.md](./SECURITY_PRIVACY.md).

## 14. Degraded and Edge States

| State             | Required behavior                                                             |
| ----------------- | ----------------------------------------------------------------------------- |
| Offline           | Keep approved plan and workout logging; queue safe writes and show sync state |
| AI unavailable    | Show last valid timestamped decision and approved plan; allow retry           |
| Partial HealthKit | Label available/missing types and reduce confidence                           |
| Stale evidence    | Show age and block proposals when policy requires                             |
| Conflicting data  | Explain conflict and request confirmation                                     |
| Media failure     | Preserve a safe local draft; retry or delete                                  |
| Permission denied | Explain reduced capability and manual alternative                             |
| Empty history     | Show the first useful action, not an empty chart                              |
| Safety escalation | Stop normal coaching and provide the appropriate next step                    |

An expired persisted owner session is refreshed before account restoration and before weekly-review
generation. If refresh is no longer valid, the app asks the owner to sign out and sign in again
instead of presenting a generic queue failure.

## 15. Screen Acceptance Checklist

Every screen must:

- match a documented route and preserve predictable back behavior;
- expose one primary action and a visible escape route;
- define applicable loading, empty, partial, offline, failed, and denied states;
- identify AI-estimated, user-confirmed, and deterministic content;
- meet [DESIGN_SYSTEM.md](./DESIGN_SYSTEM.md); and
- preserve approved plans and user data during interruption or provider failure.
