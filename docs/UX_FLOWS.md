# Tracend UX Flows

**Status:** Authoritative MVP navigation, screen, and interaction behavior\
**Platform:** iOS-first Flutter app\
**Related authority:** [PRD.md](./PRD.md), [DESIGN_SYSTEM.md](./DESIGN_SYSTEM.md),
[AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md), and [SECURITY_PRIVACY.md](./SECURITY_PRIVACY.md)

This document describes the screens as they are built on `main`, and the rules they must follow.
Where a rule is not met by the build yet, a **Not built yet** note says so. Work scheduled in the
coaching platform program appears as **Planned (coaching platform, chunk X)** notes; the plan is
[plans/coaching-platform-2026-10/README.md](./plans/coaching-platform-2026-10/README.md).

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
  workout**, **Delete conversation**). Deleting or discarding anything is always confirmed, with
  Cancel as the default choice.
- **Action sheet** (`showTracendActionSheet`): two or more related choices, such as leaving a
  workout (save or discard), with a separate Cancel.
- **Toast** (`TracendToast`): a short confirmation that something already happened ("Check-in
  saved"). It never asks for a decision, never carries the only copy of an error, and never
  announces a persistent plan or nutrition change (those are reviewed on dedicated screens, §10).

### AI and provider names (owner decision D11)

No model or provider name appears anywhere the athlete or the public reads. The company that
receives data is named only where disclosure is needed: one line in each AI consent notice, and the
privacy policy's processor list. The required labels are given in each flow below.

D11 is applied in the app (chunk A7). The Coach reply label is **AI answer · checked by Tracend**
(**Tracend safety answer · not AI** for a deterministic safety reply), the plan proposal reads
**Proposed by AI · checked by Tracend**, the Account AI coaching row and the Coach "AI coaching is
off" text say "AI", and the physique check card says "Sent to AI only when you start a physique
check". The app has no copy of an AI notice: it shows the notice it fetches from the server. The
notice bodies are rows the owner publishes (drafts in `docs/notices/`); until then the published
notices still name their companies.

## 2. Information Architecture

```text
Today
├── Recovery verdict, tick ring and drivers
├── Morning check-in (gate bar or chip)
├── Plan progress and the Sleep, Load and Fuel tiles
├── Today's session with the coach's note (the daily decision)
└── Your week

Train
├── Plan pill, week of day boxes, readiness line
├── Needs your attention (Apple Health repairs and matches)
├── Workout hero, exercises and workout execution
├── Apple Health quick-complete
└── This week: training load and history

Coach
├── One Tracend Coach conversation, with saved conversations
├── Coaching context and the evidence behind each reply
└── Prompts to remember a preference

Nutrition
├── Week strip, next meal, targets from confirmed meals
├── Today's meals timeline
├── Log a meal (photo or manual)
└── Coach guidance

Progress
├── Period, weight hero and chart
├── Weekly review
├── Recent weigh-ins and strength
└── Progress photos and physique check

Account
├── Plan: Profile and goals
├── Health: Apple Health
├── Appearance
├── Notifications (reminders, rest timer alerts)
├── Widgets (health numbers on the Lock Screen)
├── AI coach: AI coaching, AI usage this month, What Coach remembers, Coach conversations
├── Region: Country (optional)
└── Privacy: Export data, Consent history, Delete account
```

The daily decision appears on Today (the session card's coach note), on Train (the readiness line's
"Today: …") and on Nutrition (the coach guidance). The Coach tab shows no decision card.

The five tabs sit in a floating glass capsule above the home indicator (DESIGN_SYSTEM.md §4). A
lime-tinted pill slides behind the selected tab. Every tab's content ends above the bar. While
Today is selected and the morning check-in is due, the check-in gate bar takes the bar's exact
place (§5).

Account is a pushed screen, not a sixth tab. It opens from the avatar on Today and from Train's
**Open Account** when Apple Health is not connected.

## 3. App Entry and Restoration

### New user

`Launch intro → Sign-in → Eligibility, terms and privacy → AI coaching → Path`

The launch intro animates the mark and the "Tracend" wordmark (DESIGN_SYSTEM.md §6). While a
stored session restores, it keeps the mark with the brand loader ("Restoring your session").

External private-beta builds use Sign in with Apple. Owner-only development builds may show email
and password fields under ADR 0002. Both routes establish a real Supabase session before protected
data is shown; neither route bypasses authentication.

**Not built yet:** Sign in with Apple. Every build, including any external build, accepts only the
owner email-and-password mode; any other configured mode shows **Authentication mode unavailable**.

The first screen states: **Your plan, explained by your data.** It does not show pricing or request
optional permissions before explaining their purpose. Today that line is the subtitle on the
sign-in screen.

The sign-in screen shows the brand mark (drawn with a dark T on light surfaces), **Sign in to
Tracend** (**Create your Tracend account** in that mode), the brand line, a **Sign in / Create
account** segmented control, filled **Email** and **Password** fields and one pill button
(**Sign in** or **Create account**). The development copy is one small line: **Private beta: email
sign-in**.

### Returning user

`Launch → Restore session → Today`

- Restore selected tab, scroll position, and safe in-progress drafts. Today the app opens on Today,
  or on Train when a tapped widget asked for it (below); an unfinished workout draft and an unsent
  check-in are kept per athlete and restored.
  **Not built yet:** restoring the selected tab and scroll position.
- Restoring asks Auth whether the account and session still exist; an access token alone stays
  valid for up to an hour after its account is deleted.
- If Auth refuses the session (deleted account, revoked session, or a refused refresh token), the
  app signs out on this device and shows sign-in, never a connection error. A lost connection
  keeps the session and shows **Connection needed** with **Retry**.
- A refused session for an account that may still exist keeps that athlete's unsent check-in and
  Apple Health sync state, stored per athlete so no other account can read them, for their next
  sign-in. When Auth says the account no longer exists, its local data is removed.
- Resolve deep links only after authentication and authorization. The only links the app handles
  are the widgets' `tracend://today` and `tracend://train` (§5, Widgets): they switch to that tab and do nothing else, the request waits a minute for the app
  and then expires, and Flutter's own deep-link routing is off.

## 4. Onboarding

### 4.1 Shared eligibility and consent

1. Confirm age 18+ (**I am 18 or older**).
2. Show the supported healthy-adult boundary (**First, confirm the boundary.**).
3. Ask only eligibility questions required by the PRD.
4. If excluded, stop plan generation and show appropriate professional guidance. Today an
   excluded answer shows the inline message "Tracend cannot create a plan for clinical nutrition,
   pregnancy, acute injury, or rehabilitation needs." and nothing is built.
5. Accept terms and privacy notice: **I accept the private-beta terms** and **I have read the
   privacy notice**, as check rows in a grouped list on the same step as the age question. The
   hosted terms and privacy pages exist on the site, but the app does not link the rows to them
   yet. That is acceptable only for the owner-only beta and is a public-release blocker
   (SECURITY_PRIVACY.md §15). No legal text lives in the app.
6. **Health check** (B6), its own step right after the boundary and terms and before anything else
   is asked, so an athlete who should see a professional first learns it at once. Four plain
   yes/no questions, with no diagnosis and the note that this is not a medical check. (1) Do you exercise regularly now (about 30 minutes or more, at least 3
   days a week, for the last 3 months)? (2) Do you know you have a heart, diabetes or other
   metabolic, or kidney condition? (3) Do you notice any of these right now: chest pain or
   pressure, breathlessness at rest or with light effort, dizziness or fainting, swollen ankles, a
   racing or skipping heartbeat, or cramping leg pain when you walk? (4) Only with a known condition
   and no symptom: has a health professional said you are fine to exercise? Continue records the
   answers (`record_screening_v1`) and the server's outcome decides what follows:
   - **Cleared:** the flow goes on.
   - **Moderate effort until cleared:** the step shows "Your plan will stay at moderate effort."
     and explains that sessions stay at a comfortable effort with no all-out sets until a health
     professional says the athlete is fine to exercise; a second Continue goes on.
   - **See a professional first:** the step shows "Please see a health professional first." and
     explains that Tracend cannot build a plan until then (with a line to get medical help
     straight away for chest pain, severe breathlessness or fainting now). Continue stays closed;
     changing an answer clears the result so the athlete can answer again after being cleared.
   An old draft that passed this step's place without answers returns to it, and a plan request the
   server refuses for a malformed or professional-first screening sends the athlete back to it (the
   latter with the same guidance and Continue closed). Builds from before the
   health check never send answers; the server reads that as cleared.
7. Choose whether to allow AI coaching. **Allow AI coaching** and **Not now** are both valid
   answers.
   - The text is the server's current notice (`get_current_ai_notice`). The app records that
     notice's version. If the notice cannot load, the step shows "The AI coaching notice could not
     be loaded. Check the connection and try again." with **Try again** and no answer buttons: the
     app never shows a notice body it did not fetch and never records an answer for a version it
     did not fetch.
   - The notice says what data is sent and what works without it, and names the receiving company
     once, with no model names (D11).
   - Without AI coaching, Tracend's rules build the starting plan.
8. Choose **Guide me** or **Preserve what works**.

An account that has not answered the current AI coaching notice (created before the question
existed, or asked again after the notice changed) answers it once before the app opens. While AI
coaching is off, Coach shows **AI coaching is off** with **Review AI coaching**, its composer is
disabled, and Today generates no AI decision. **Account › AI coaching** turns it on or off. The
"off" text explains why the Coach needs permission, without a provider name (D11): "The Coach sends
your Tracend data to an AI service to answer, so it needs your permission first."

Meal-photo AI and progress-photo AI consent occur separately when their value is visible. Apple
Health is offered once, as the optional onboarding step below, and otherwise from Account.

The first Apple Health sync on an account reads 31 dates (today−30), so the onboarding summary
and the baselines have four weeks behind them; later refreshes read the last 8 dates. The UI keeps
the partial/unknown states and never claims an empty result means permission was denied. Apple
Health state on the phone belongs to the signed-in athlete: another account on the same phone
starts as not connected.

### 4.2 The onboarding flow

```text
Eligibility → AI coaching → Path → Goal
  → Apple Health (optional: Connect, or Skip for now)
  → About you (sex, birth year, height, weight, optional target weight, daily activity)
  → Schedule (weekday chips, up to six; session length)
  → Equipment (chips; none = bodyweight)
  → Food & limits (diet; movements to avoid as chips; other limitations)
  → Your training (Preserve what works: years trained, current plan, what has worked and stalled)
  → Current lifts (Preserve what works, optional: barbell top sets — weight, reps, reps left)
  → Focus (optional: up to two muscles to bring up, up to three already strong)
  → Review → Continue to your coach
  → Coach questions (0–3 questions; skip any time) → Build my plan
  → Plan (approve, request changes, or reject)
```

- **Progress:** the header reads **Step N of M · ‹section›**: 15 steps for Preserve what works,
  13 for Guide me, which skips Your training and Current lifts. Under it a thin segmented line has
  one segment per step: done steps solid, the current step lime. The step text is what VoiceOver
  reads. Section progress is shown, never an inaccurate percentage.
- **Saving:** autosave each completed section; the draft is saved on the server. A draft from an
  older build continues at **About you**. **Saved answers that fail to load** show **Your answers
  did not load.** with **Try again**; nothing is saved until they load, so defaults never overwrite
  them.
  **Sign out** stays available on every step, including while saved answers load.
- **Goal:** nothing is preselected; each goal has a one-line description.
- **Inputs:** use visible labels and a short rationale for sensitive fields. Height,
  weight, target weight and session length are sliders with − and + buttons for exact values,
  read aloud with their unit. The birth-year number pad closes after four digits or a tap outside.
  Choice cards (AI coaching, path, goal, daily activity) show their selected state with a lime
  ring, a lime wash and a filled check. Fields are filled, buttons are pills, and multi-select
  answers (days, equipment, movements, muscles) are pill chips. Sex and the reps left on a top set
  are segmented controls; at large text sizes Sex becomes a list of rows so no label breaks
  mid-word. Offer **I don't know** where exact knowledge is unnecessary. **Not built yet:** no
  step offers **I don't know**.
- **Apple Health** reads the last four weeks when the athlete taps **Connect Apple Health**, then
  shows what it found (days and categories) and the athlete's usual months next to the last weeks
  ("Strength: 3.4× a week usually · 1× a week lately", "Sleep: 6 h 50 min usually"), or says the
  plan uses the last 4 weeks when there are fewer than three earlier months. Nothing found
  explains Settings › Health › Data Access & Devices and offers **Try again**; the athlete can
  always continue. A failed read can be retried or skipped. Reopened after a sync that finished,
  the step shows it as connected.
- **About you** then starts the weight at the newest Apple Health weight from the last 14 days
  (labelled with its date, until the athlete moves it, and never over an answered weight) and shows
  average steps with a **Matches your steps** tag on the daily-activity answer they point to. The
  athlete's own answers are what count.
- **Movements to avoid** never appear in the plan. An athlete who wrote a limitation in an older
  build is asked to choose them (or none) before building.
- **Answers no safe plan fits** (for example, bodyweight only while avoiding every pushing and
  pulling movement) open the step to change, with what to change; nothing is built.
- **Review** lists every answer (Apple Health, daily activity, equipment and its note, diet,
  movements to avoid, limitations, focus, and for Preserve what works the training and top sets).
  Each row has **Edit**, which opens its step; that step's button reads **Save and return to
  review**. At large text sizes labels sit above their values. Review also shows what Apple Health
  contributed.
- **Coach questions:** the coach reads the answers (usually under 30 seconds) and may ask up to
  three short questions with quick answers or a written one. **Skip and build my plan** is there
  while it reads; with no questions the plan builds straight away. Editing any earlier answer
  clears the follow-up answers, because they were asked for the old answers.
- **Build my plan** starts a server generation and shows **Building your plan** ("usually under a
  minute; it can take up to two"). Generation is a named asynchronous state; the app polls it, so
  the athlete can leave and come back:
  - a running generation keeps waiting;
  - a finished proposal opens;
  - a failed one offers **Try again**;
  - an answered one returns to Review;
  - an expired one (proposals last seven days), or one that expires while the athlete answers it,
    shows **This plan proposal expired.** with **Build a new plan** and **Back to review**.

### 4.3 Preserve what works

Add current plan, performance history, targets, observed strengths/weaknesses, adherence, and
plateau context. Final review separates **Kept**, **Adjusted**, and **Unknown**, preventing
arbitrary replacement of valid practices. Today the proposal shows **Kept from your plan** and
**Changed from your plan**. **Not built yet:** the **Unknown** group.

### 4.4 Initial plan approval

Show goal, assumptions, weekly structure, exercise prescription, nutrition targets, confidence,
missing information, and safety boundaries. Actions are **Approve plan**, **Request changes** and
**Reject proposal**. Generation never activates a plan.

The proposal screen shows, top to bottom:

- **Provenance:** **Proposed by AI · checked by Tracend**, or **Built by Tracend's rules**. No
  provider name appears (D11), whatever model answered.
- **Confidence** and **the assessment**.
- **Training:** every training day with its exercises (sets × reps, RPE with the reps left in
  plain words, for example "RPE 7.5 (about 2–3 reps left)", rest), **Start at ‹kg› kg** on
  exercises Tracend set a starting load for, and a **Focus** line. Train pre-fills the kg field
  with the starting load.
- **Nutrition:** the targets, with the formula (resting energy × activity plus training, and the
  goal range) and the Apple Health summary the plan used behind the collapsed **How we calculated
  this** disclosure.
- **For Preserve what works:** what was kept and what changed.
- **The plan's reasoning:** **Why this plan**, **Expected benefit**, **Downside and uncertainty**,
  **Assumptions** and **Not known yet**.

**Request changes** opens a sheet titled **What should change?** ("Sent with your next plan
request."); it needs a note, which is sent with the next build. **Reject proposal** asks with a
destructive confirm, **Reject this plan?** (**Reject plan** / **Keep reviewing**); answers stay
saved and are edited from Review.

Approval activates exactly those workouts, then shows **You're set.** once: "Your plan is active.
Nothing else changes without your approval.", the plan, the next session ("Next session: ‹day› ·
‹name› · about N min"), the daily calories and protein, and the Apple Health status, with **Go to
Today**.

**Account › Profile and goals** shows, read-only: **Goal** (primary goal, status, active since),
**Training profile** (experience, height, training days, session length), **Onboarding answers**
(sex, birth year, daily activity, equipment and its note, movements to avoid, limitations, diet;
shown when the answers were kept) and **Approved plan** (plan, version, approved date).

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

Today reads as one recovery ring that explains itself, then the day in tiles, the session and the
week. AI availability never blocks the workout. Without a valid decision, the approved plan stays
on screen and the coach's note says what would produce one (a sync, or turning AI coaching on). A
missing readiness signal becomes a direct recovery action (sync Apple Health or check in). Today
never asks for Apple Health access; connecting and the full sync status live in Account.

Reading order:

1. **Large title**: a time-of-day greeting with the full date and the account avatar ("Open
   account"). At the largest text sizes the title is "Today" and the greeting joins the date. Pull
   to refresh runs the same sync as the hero's sync row.
2. **Hero**: the recovery band in words ("Fully / Well / Partly recovered", "Under-recovered",
   "Very under-recovered") and one line naming any driver a spread or more on the wrong side of
   normal ("Sleep less than usual. Everything else is normal for you."). Beside the verdict (under
   it from 1.3× text), **Checked in** once today's check-in is saved (tap to update it), or a
   lime-edged **Check in** chip after "Not today" or when Today has no gate.
   - **Tick ring**: 112 ticks; the lit ticks run to the score and are split between the drivers
     that counted, in proportion to their weights, lime when a driver is normal or better and
     amber when it pulls the score down, with a one-tick gap between drivers and a taller head
     tick with a dot. Inside: "Recovery", the score counting up, the band pill and "+6 from
     yesterday" ("Same as yesterday" when unchanged; left out when yesterday was not scored).
     Tapping the ring opens the drivers card (`RecoveryReadoutCard`) in place.
   - **HRV and resting heart rate** under the ring, each against your normal ("HRV · higher than
     usual"): the HRV the score used (last night's, or this morning's) and yesterday's resting
     heart rate; a missing reading is left out.
   - **Driver chips** (HRV, Resting HR, Sleep, Breathing, plus Training when it pulls down; a
     morning estimate shows Check-in once it counts and no Breathing): "Sleep short", "HRV low";
     grey "… no data" when a driver did not count. A chip lights only its driver's ticks and opens
     the drivers card.
   - The source and confidence line: "From last night · High confidence", or "Morning estimate,
     no night recorded · Medium confidence · Settles at 12:00" until noon (recovery modes,
     ALGORITHMS.md §1). Then the sync row ("Sync · ‹date, time›", "Syncing") and any sync issue
     ("Could not refresh … Pull down or tap Sync to try again.").
   - **Not scored yet**: the ring shows "--" with a **Not scored** pill, the verdict reads
     "Recovery not scored yet", and the lines say the score appears once Tracend has enough nights
     to compare. With no computed data at all the verdict reads "Your day" with "Sync Apple Health
     to see how recovered you are." and no ring.
3. **Plan progress**: the plan's title and "Week 3 of 20" with a thin bar; past the block, "Week
   22 · block of 20 done".
4. **Tiles**: Sleep (tall: duration, sleep debt or quality, a deep/REM share bar from Apple
   Health), Load ("Normal", "Lighter", "Heavier", "Much heavier", or "Building"; this week's
   strain bars) and Fuel (protein to go and a bar; without a target, what was eaten). Tapping a
   tile opens its card under the tiles, one at a time: the sleep card (`SleepArchitectureCard`),
   the week's load ("Training load about normal", "Last 7 days against your 4-week average · ratio
   1.05", a day-by-day strain chart), or the fuel rail with **Log a meal** → Nutrition. All three
   stack from 1.3× text.
5. **Today's session**: the workout name, its summary, and a strip with one block per prescribed
   set grouped by exercise, filling lime as sets are logged in Train ("4 of 15 sets logged",
   "Done · 15 sets logged"). The coach's note sits under it: today's first training adjustment,
   else today's training summary, as advice in its own words, labelled "Coach · ‹confidence›"; it
   never changes the prescribed sets. A decision from another day is not shown. With AI coaching
   off the note says no daily decision is generated and where to turn it on; with no decision it
   says to tap Sync. **Open in Train** (and the header) goes to Train. With no workout it reads
   **Rest day** and names the next planned session.
6. **Your week**: "3 of 5 sessions done" and "Recovery averaged 62 this week" (scored days only),
   then Monday to Sunday as stacks of ten ticks lit to each day's recovery (lime from 50, amber
   below; "no data" without a score; later days empty) with a mark: filled dot trained, ring
   planned and still ahead, hollow grey ring planned but not logged, dash rest. Tapping a day
   names it below ("Tuesday · recovery 48 · planned, not logged").
7. A closing line: "Calculated from Apple Health and your logs. No AI in the numbers."

If the daily brief cannot load, Today says so and to use the approved plan. Loading shows
skeletons (one VoiceOver label, "Loading Today"), never a spinner. Transient results (sync,
check-in saved) are toasts.

**Morning check-in gate** (owner decision, 2026-10-04): until today's check-in is saved, the tab
bar gives way, while Today is selected, to one lime bar, **Check in to start your day** ("About a
minute · sharpens today's call") with an arrow, and **Not today** under it. Saving the check-in
(delivered or queued offline) or "Not today" brings the tab bar back for the rest of the day; both
are remembered on the phone for that date. The gate never locks the plan: "Not today" always lets
the athlete through.

**Widgets (coaching platform, chunk D2).** Today also lives on the Home Screen and the Lock Screen
(`ios/TracendWidgets/`; visuals in DESIGN_SYSTEM §3.7). Each time Today's brief loads, the app writes
a compact snapshot to the app group; the widgets only read it and never call the network.

- **Small:** today's session ("Rest day" when none) with where it stands ("Not started", "6 of 14
  sets", "Done · 14 sets", "Nothing planned"), and the recovery score ("--" when not scored).
- **Medium:** the same, plus the first three exercises with their plan targets ("4 × 6–8 · 82.5
  kg"), calories and protein against the plan's targets, and "Checked in" or "Check-in due".
- **Lock Screen:** circular, the recovery score on a ring; rectangular, the session, recovery and
  protein against its target; inline, the session and recovery.
- **Age.** Home Screen widgets show how old the snapshot is. A snapshot 12 hours old or older, or
  from another day, shows no numbers and reads **Open Tracend to refresh** (from the 12-hour moment
  or midnight itself, whichever comes first); so does a widget before Today
  has ever loaded, and after sign-out. The widgets reflect the last time Today loaded, not a live
  feed: a meal logged in Nutrition shows once Today next loads (pull to refresh). A saved check-in
  is the exception: the widgets read "Checked in" at once, even when it was queued offline and the
  brief cannot reload.
- **Taps.** Every widget opens Today (`tracend://today`), except a planned or started session, which
  opens Train: the medium widget's exercise list and the Lock Screen rectangular widget
  (`tracend://train`). The circular and inline Lock Screen widgets always open Today. The app switches to that tab on launch or return; the request expires after
  a minute.
- **Lock Screen numbers are off until chosen** (**Account › Widgets**, §13). Off, the Lock Screen
  widgets show only "Tracend" and "Lock Screen numbers are off" (a lock glyph in the circular one).

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
question starts at 3. Pain is **No pain** (0) or **Some pain**, which asks "How strong, from 1 to
10?" and will not save until a strength is chosen; it is stored as `pain_severity` 0–10. The note's
counter appears only in its last 100 characters. **Save check-in** is pinned below the questions,
so it is always on screen. Saving shows "Check-in saved", or, offline, that it is saved on this
device and will sync when online. Pain location questions and the safety boundary remain future
work. Save updates Today and recomputes only when necessary.

### Evidence detail

The recovery drivers sit in the drivers card, opened from the ring or a driver chip. They are plain
rows in the composite's weight order: "Overnight HRV: normal for you, 58 ms" ("Morning HRV" for a
morning estimate), then resting heart rate, sleep, breathing rate and recent training. The words
come from the true z-score against the athlete's own baseline: within one spread reads "normal for
you", one spread or more "higher/lower than usual" (sleep and training say "more/less"), two or
more "much …". Resting heart rate and breathing rate read the measurement, not the z sign, because
their z-scores are negated in the composite. Resting heart rate is yesterday's ("61 bpm
yesterday"). An unusable component reads "not enough data yet" and never shows a number; a valid
sleep reading whose baseline is still maturing shows the measurement with "baseline still
building".

The z-scores sit behind **How this is calculated**: it explains the baseline comparison in plain
words, lists each driver's weight and true z-score ("Not used today" for an excluded component),
and ends "Calculated from your Apple Health data and logged workouts. No AI." Under the method it
says which mode scored today: last night's HRV against your nights, or a morning estimate from the
HRV taken 4:00–12:00 against your mornings plus the check-in, settling at noon. A morning
estimate's rows read "Morning HRV" and "Morning check-in" ("feeling good", "feeling about OK",
"feeling rough"), with no breathing row. The disclosure is a VoiceOver button with an expanded
state. The confidence word stays visible on the hero.

Sync freshness shows on the hero's sync row (last health sync time) and in Account's Apple Health
status card, in ordinary coaching language. Deterministic calculation and AI interpretation are
labelled separately.

### Coach replies

Training and Nutrition remain perspectives in one controlled decision pipeline, not independent
agents. The Coach tab answers direct questions through the same workflow and never behaves like
three separate autonomous chatbots.

- **AI label.** A reply a model wrote carries the small label **AI answer · checked by Tracend**,
  with no provider name (D11). A reply no model wrote (the deterministic safety boundary, stored
  with provider `mock`) reads **Tracend safety answer · not AI** and never carries the AI badge. A
  provider or validation failure never substitutes generic coaching text.
- **Formatting.** Replies display bold, italic, and bullet or numbered lists, so they read as
  formatted text rather than raw Markdown. Long answers are selectable.
- **Labeled replies.** When the model cannot answer, Coach shows a labeled reply in its place,
  always visible and never with a provider label: "Data summary · not an AI answer" (what the
  athlete's data shows) or "Safety note · not an AI answer" (a message that may concern a health
  risk). A data summary also shows a beta diagnostic line (failure code and rule names) as small
  secondary text, inside **Evidence used and data gaps** when the reply has one and under the
  reply otherwise. **Retry** appears when the reply ends the conversation, and it keeps whatever
  the user is typing.
- **Other failures** (sign-in, database, limits, network) show one inline message under the
  question that failed, in place of the reply: what happened in plain, specific words, then the raw
  diagnostic as a small second line, and **Retry** where asking again can help. The Coach function
  answers errors with a non-2xx status, and the app reads its error, code and reason (A9). Each
  has its own sentence:
  - **Limits** (429 `ai_usage_limit` with `reason` `monthly_cost_limit`, `daily_rate_limit` or
    `global_monthly_cost_limit`; the same two reasons inside a 422 context-preparation failure):
    "You’ve reached this month’s Coach limit. It resets on 1 Nov." (the first of next month,
    00:00 UTC, shown as a date in the athlete’s own clock), "You’ve used all of today’s Coach
    messages. The limit resets at 5:30 am tomorrow.", or "Coach has reached its shared limit for
    this month." An unrecognised reason says "Coach has reached its usage limit for now." No Retry.
  - **AI coaching permission** (403 `ai_consent_required`): "Coach needs your permission to use AI
    before it can answer." with **Review AI coaching** and no Retry; 503 `ai_consent_unavailable`
    says the setting could not be checked and offers Retry.
  - **Session** (401): "Your session has expired. Sign in again to keep talking to Coach."
  - **Context preparation** (422 `context_preparation_failed`, reason `thread_not_found`,
    `invalid_chat_request`, `account_not_found`, `invalid_timezone`, `chat_context_too_large`,
    anything else): each says what to do ("Start a new one", "Shorten it
    and send it again"); an unknown reason says Coach could not prepare the data and offers Retry.
  - **Provider** (503 `provider_*`): "Coach couldn’t complete that response. Please try again.",
    "Coach took too long to respond.", "Coach is busy right now." A retry delay from the server
    (`retry_after_seconds`) turns the composer into a countdown ("Coach is busy. Try again in 3s")
    and hides Retry until it ends.
  - **Timeout, lost connection, gateway timeout, a turn still running** (409): "Coach took too long
    to answer. Retry will pick up the answer if it finished in the meantime."; "Tracend can’t
    reach Coach. Check your connection, then retry."; "Coach is still working on your last
    message."; and, when the server gives up on a turn that never finished (503 `turn_lost`),
    "That message didn’t finish. Send it again." whose Retry is a new turn.
  - Anything else: "Coach couldn’t answer. Your approved plan is unchanged." with the raw text.
  A toast ("Coach couldn’t answer") marks the moment; it never carries the only copy of the error.
  During the private beta the diagnostic line shows the raw text, including the HTTP status and the
  server's stable code, reason or error ("Beta diagnostic: HTTP 422 · chat_unavailable ·
  context_preparation_failed · monthly_cost_limit"), so the owner can see where a failure comes
  from (owner decision, 2026-09-27). The server never sends parser messages, provider bodies,
  prompts, or health context.
- **Safe retry.** Each question is sent with an idempotency key. **Retry** after a timeout, a lost
  connection, a gateway timeout or a turn still running repeats that key (at most twice), so a
  server that finished after the app gave up returns its answer instead of running again and
  charging twice, and the question stays one bubble. **Retry** after the server did answer with a
  failure (or `turn_lost`), and **Retry** on a data summary, is a new turn with a new key. The server saves a question when
  its turn starts and marks a failed attempt's copy superseded when the retry arrives; the thread
  view hides superseded questions, and a retry of a failed send stands in for it on screen too.
  **Review AI coaching** reloads the
  consent first, so a grant for an older notice cannot hide the notice the server now requires.
- **Near the limit.** When the server reports `budget_warning` (this month’s spend is 80% of the
  athlete’s monthly Coach limit), a line under the newest reply says "Heads up: you’re approaching
  this month’s Coach limit. It resets on 1 Nov."
- **Without a plan.** Coach answers an athlete who has no active plan or nutrition target, including
  one told to see a professional first (screening outcome `see_professional`): the context says
  there is no plan and why, and Coach can still answer questions and suggest next steps, but not
  cite or change a plan. A new conversation then offers "What can you help me with?", "Why don’t I
  have a plan yet?" and "What should I do next?" instead of the plan questions.
- **Coaching context.** A new conversation shows an expandable **Your coaching context** card
  before its first message; an ongoing conversation shows no cards above it. It lists approved
  plan, goal/profile, Apple Health, check-ins, confirmed nutrition, completed Tracend workouts,
  measurements, and conversation history with honest availability/count/latest-date metadata. Its
  summary counts connected sources ("4 of 6 sources connected") and dates read as words ("latest
  yesterday", "latest Thu 24 Sep"), never ISO dates.
- **Evidence.** Model-cited evidence and actual data gaps use **Evidence used and data gaps**:
  the cited evidence with its source in words ("Calculated from your health data"), the data gaps
  in words (`recovery_check_in` reads **Morning check-in**), the reasoning steps without their
  evidence ids, and the beta diagnostic. Generated follow-up ideas use the separate **Suggested
  next actions** heading.

**Planned (coaching platform, chunk E3):** the research library inside Coach chat.

## 6. Workout Execution

`Train → Workout overview → Start → Focus logging → Finish (session effort) → Summary`

Logging is a full-screen cover (`ActiveWorkoutScreen`) in focus mode: one exercise per page.

**Header.** A chevron-down ("Leave workout"), the workout name over the elapsed time (ticks every
second; amber past 3 hours, when a banner says the workout saves as 3 hours), and the lime
**Finish** pill. Under it, a segmented bar with one segment per set (done segments are good green)
and the sync state as a small icon plus a word: **Saved** (good), **Syncing** (neutral),
**Offline** (caution; the draft is on the phone) or **Needs attention** (low; the server refused
the draft).

**Focus page.** Swipe sideways between exercises (selection haptic); the screen opens on the first
exercise with sets left, and a "Swipe for ‹next›" hint sits at the foot of each page.

- "Exercise N of M", the name, "4 sets of 6–8 · RPE 8", the exercise's muscles as text, and a small
  front and back `MuscleMapPair` when its muscles are known (catalog or reviewed list). Otherwise
  there is no map and no muscles; nothing is inferred at run time.
- Set dots: done sets green, the current set lime.
- The set card: "Set 2 of 4", the rest after it, and big kg × reps readouts with −/+ (2.5 kg, one
  rep; kg can be emptied for no added weight) that can also be typed. The starting values are the
  set's own entry, else the set done before it today, else the same set last time, else the plan's
  starting load and lowest rep target, and a quiet caption names the source (**From your last
  set**, **From last time**, **From your plan**). Prefill is only ever an unconfirmed starting
  point: nothing is logged until **Done set N**.
- The strip under the readouts: **Last time** and **Your best** from `get_my_exercise_history`
  (**Not enough data yet** for a missing half); a **First log** tag and "No earlier sets for this
  exercise." the first time; "Last time and best need a connection." when neither the server nor
  the phone's copy has the history; a skeleton line while it loads.
- **Done set N** (60 pt) logs the kg and reps shown with a light haptic. When every set is done the
  card reads "All N sets done" and "Swipe for ‹next›" with **Next exercise**, or tells the athlete
  to tap Finish on the last exercise.
- **Logged**: each done set with its number, "62.5 kg × 8" (or "12 reps"), a **New best** or
  **First log** mark, its reps left (**2 left**, **5+ left**, or **Reps left** to add; a set
  logged before reps left were asked shows what its RPE meant, 10 − RPE, RPE 5 or below as **5+**,
  without writing it) and undo. Undo clears that set's reps left and its times.
- Tools: **Pain or discomfort** stays a visible chip (**Pain noted** in caution when on). **Fill
  reps left**, and a ⋯ menu with **Mark as skipped** (**Unmark skipped** once skipped; an action
  sheet titled with the exercise name, with **Keep logging**). Logging a set on a skipped exercise
  unmarks it.

**Reps left (reps in reserve).** Optional on every set: "How many more reps could you do?" with
one row of 0, 1, 2, 3, 4 and 5+ and the legend "0 nothing left · 5+ five or more" (VoiceOver
reads "Nothing left", "1 rep left" … "5 or more reps left"). Blank is allowed (**Not now**,
**Clear**). The app also writes the RPE the same answer means (10 − reps left, 5+ as 5). **Fill
reps left** ("Fill reps left for sets without it", with **Cancel**) gives one value to the logged
sets of that exercise that show **Reps left** (neither reps left nor an older RPE), leaves the
others alone, and says how many it filled ("Log a set first" with none logged; "Every logged set
already has reps left" when none needed it); each set stays adjustable afterwards. Reps left are
separate from session effort and never feed it.

**Set timing.** Nothing new on screen. Each set records when it started (the end of the rest before
it, else the first edit of its kg or reps outside a rest; none when it is ticked during its rest),
when it was ticked and the rest taken since the previous tick, all from the wall clock, so a rest
that runs out while the phone sleeps ends at its stored end time. Undo clears the set's times and
re-measures any rest counted from it. Times from before the server's copy of the session began stay
on the phone. When the server refuses the times (a phone clock more than 10 minutes off), the draft
is sent again without them and the rest of that workout syncs without times.

**Planned (coaching platform, chunk C2):** a native heart-rate reader with per-set summaries.

**Rest.** Done set starts the exercise's rest (`rest_seconds`) when something follows it:

- A full-screen lime ring with the time left, "Next" with the next set or exercise under it, −15,
  +15, Skip, and the reps-left picker for the set just done. It covers the page, not the header,
  so Finish and leave stay reachable.
- A swipe down, a pull past the top or the chevron above "Swipe down to keep editing" (VoiceOver:
  "Hide rest timer") shrinks it to a floating pill (ring, "Next: Set 3", ±15 at normal sizes,
  Skip) above the page; a tap on the pill opens the ring again. The rest never blocks editing.
- The end time is stored in the draft (`rest_timer`), so a relaunch brings the rest back as the
  pill; an expired one is cleared.
- The end plays the success haptic and the toast "Rest is over. Next: …".
- The lock-screen alert ("Rest timer finished") is scheduled through `RestTimerController` only
  when **Rest timer alerts** is on and allowed. Skip, the in-app end, finishing, discarding and
  leaving all cancel it.

**Workout Live Activity.** From the moment a workout opens, the Lock Screen and the Dynamic Island
show it, unless the athlete turned Live Activities off in iOS Settings (Settings › Tracend › Live
Activities). It shows the exercise name, the set's position and the buttons; the kg and reps only
if the athlete turned on **Account › Widgets › Health numbers on the Lock Screen** (off by default,
the same choice as the Lock Screen widgets); never effort, reps left, heart rate or any other
health value (SECURITY_PRIVACY.md §10). The countdown keeps running with the app closed.

- **Set in progress (Lock Screen and expanded Dynamic Island):** a lime dumbbell glyph and "Set 2 of
  4", the exercise name, the target ("82.5 kg × 8", only with Lock Screen numbers on) in lime on the
  right, and two buttons: a lime **Log set** and **Open**. The target is what the logger pre-fills
  for that set (the same values as the in-app **Done set**); the card follows the logger, so an edit
  of kg or reps in the app, a swipe to another exercise, an undo or a skipped exercise move it.
  Compact shows the glyph and "2/4", minimal the glyph.
- **Log set** logs the set exactly as the in-app **Done set** does, at the values the logger
  pre-fills; the card never edits them (changing reps or load needs the app, whose logger the
  **Open** button and a tap on the card bring forward: from a killed app they reopen today's
  workout that was left open). A set with no reps to pre-fill gets **Open** only.
- **Rest:** after Log set, or **Done set** in the app, the card becomes the rest: "Rest", the
  exercise, "Next: …" and a big lime countdown, with **+30s** and **Skip**. When the rest ends, by
  itself (even with the phone locked and the app asleep), by Skip or by −15 past the end, the card
  turns into the next set, and after the last set of an exercise into the next exercise's first set.
- **Every set logged:** the card reads "All sets logged" with a lime check and **Open**, and the
  app removes it two minutes later; the workout is finished in the app.
- ±15 and +30s move the rest. Finishing, discarding and Save and leave end the card at once. A
  relaunch with a running rest moves the card to the stored end; with a rest that ended, or no
  rest, it shows the set in progress. Sign-out and account deletion end it. If the screen is torn
  down any other way, only the card ends and the rest stays in the draft. ActivityKit cannot
  dismiss a card without app code, so with the app away a card stays until the app runs again, the
  next launch, or a button press that finds it over (the all-sets-logged card after two minutes, any
  card the app has not moved for four hours), which removes it instead of acting.
- **Buttons** are on the Lock Screen and the expanded Dynamic Island (compact and minimal have
  none). Each press wakes the app in the background (iOS 17 App Intents) and goes through the
  workout's command sink (Contract 3): **Log set** logs the set the card names, and only if that
  set is still its exercise's current one and no rest is running, so a double tap, or a Log set
  tapped after the same set was logged in the app, logs nothing and the card is redrawn to the true
  set; Skip ends the rest now; +30s adds 30 seconds. The card never writes a set itself. A press
  waits for the set to reach the server copy (up to 5 s; offline it is logged on the phone and
  the sync state reads Offline, as in the app) and is dropped if it is more than 8 s old. A press
  that wakes the app after its rest ran out unnoticed counts that rest as ended at its stored
  end, so Skip and +30s then change nothing.
- If the app was closed (swiped away or ended by iOS) when a button is pressed, no workout can
  take it: the buttons give way to a lime **Open Tracend**, which reopens today's workout from its
  draft and moves the card to the set in progress.

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
training load. Finishing syncs the draft, then calls `complete_workout_v2` with the athlete's
`session_effort` and the duration capped at 3 hours.

- If the finish cannot reach the server, a banner "Finish not sent yet" keeps the effort and the
  duration on the phone with **Send finish**; reopening the workout offers the same banner. A
  server refusal adds its message as small secondary text.
- When the server refuses the final sync, the workout is not finished (the server would finish it
  from older sets and the phone would drop its copy): the sync state reads **Needs attention**,
  the banner says the sets are kept on this phone, and **Send finish** tries again.
- On success: the success haptic and the summary sheet: a check, "Workout complete", a card with
  the date, the workout name, Time, Sets and **Weight lifted** counting up (with "Counts sets with
  added weight, as you logged them."), the new bests stamped on with their previous best, and "How
  hard it felt". **Done** closes it, the toast "Workout saved" shows, and the cover closes back to
  Train, which refreshes.

**A finished workout** is reviewed through **View summary** on Train (§7). If **Start** finds a
session that is already complete, the cover opens read-only: "Completed · 45 min", **Done**, and
each exercise's logged sets; "Marked complete from Apple Health" shows only when the session's
`completion_source` is `healthkit`.

Autosave keeps a local draft (250 ms after a change) and syncs it, retrying a workout that started
offline. Substitution requires a reason and shows whether the objective is preserved; later
corrections to a completed session create audited amendments. **Not built yet:** substitution and
amendments.

## 7. Train

Train uses the 4/8-point spacing rhythm and 44-point interactive rows. Active logging reports
Saved, Syncing, Offline, or Needs attention; resumes entered sets after reopen; and requires
explicit skip actions. Historical corrections and Apple Health conflicts use review cards with
confirmation actions. The tab reads top to bottom:

- **Header.** The large title "Train", today's date ("Friday 2 October") and the plan pill ("Week 3
  of 6"; after the block "Week 7" alone; no pill for a plan that has not started or a cached hub
  without dates). The pill opens the plan sheet: title, block weeks and sessions a week, week
  pips, the plan rule when the plan has one, and "You approved this plan on 15 September. Changes
  always need your approval." At large text the pill moves under the title.
- **Day boxes.** Seven boxes for the week: a check for a done day, a dot for a planned day, a lime
  ring for today and a raised fill for the selected day. A tap plays the selection haptic and slides
  the day's content in from the side it came from (a crossfade under Reduce Motion). A horizontal
  swipe pages back up to three weeks, never past this week (VoiceOver: "Previous week" and "Next
  week" actions); "Week of 21 September" with a **This week** button shows while another week is
  open.
- **Readiness line.** One sentence about state, never advice: "Recovery is excellent." (80+),
  "Recovery is good." (65+), "Recovery is moderate." (50+), "Recovery is low today." (35+),
  "Recovery is poor today.", "Building your baseline." with no score, and "Connect Apple Health to
  see recovery" without Apple Health. Today's decision verdict follows as "Today: …" when the
  latest decision is for today. It opens **Recovery today**: HRV ("Overnight HRV" or "Morning
  HRV", its baseline shown as "usually 55 ms"), resting heart rate ("Resting heart rate,
  yesterday"), sleep and training load, each in plain words ("Normal for you", "Higher than usual",
  "Lower than usual", "More than usual" for sleep, "Building your baseline", "Not enough data
  yet"), ending "Calculated from your Apple Health data and logged workouts. No AI estimates."
  Without Apple Health the sheet is titled **Apple Health**, explains where to connect, and offers
  **Open Account**. A failed load reads "Recovery could not load. Pull down to try again."
- **Needs your attention.** Apple Health repairs and workout matches share one group above the hero.
  A repair ("Workout record needs review") offers **Review and correct**, which asks "Correct this
  workout record?" (**Confirm correction** / **Not now**). A match ("Match confidence N%") offers
  **Confirm match**, **Not the same workout** and, for another day, **Switch to that day**. Results
  are toasts ("Workout record corrected", "Workout match confirmed", "Match dismissed").
- **Workout hero.** A kicker ("Today", a weekday, "Done today", "Done on Tuesday", "Tuesday, not
  logged"), the name, "6 exercises, about 48 min" (a done day shows "48 min, 6 exercises"), the
  worked muscles as chips and on the turnable `MuscleMap` with a Front/Back control. When
  exercises with known muscles carry less than three quarters of the workout's planned sets, the
  map and chips are left out (a partial map would misdescribe the session) and the card says
  "Muscle map appears with your next plan."
  - The title area opens the **workout overview** sheet (objective, warm-up, exercises, cooldown,
    then **Start workout** for a day not done, or **View summary**). The map opens the **muscles
    sheet**: front and back side by side, a row per muscle with its sets and exercises, rows and
    muscles selecting each other, and a note that muscles come from the exercise catalog or
    Tracend's reviewed exercise list.
  - The one action is **Start workout** (heavy haptic), **Log this workout** for a past day with
    nothing logged, or **View summary** for a done day. The summary sheet shows "Done on ‹date›",
    time, sets logged of planned, the athlete's own effort ("N of 10", or "Not rated" for app
    defaults) and **What you logged** per exercise. "Auto-completed from Apple Health. Sets were not
    logged in Tracend." shows only when `completion_source` is `healthkit`.
  - A rest day reads **Rest day** ("You took the day off. Recovery is part of the plan.") and names
    the week's next workout with "See Sunday's workout".
- **Exercises.** One grouped list; a row reads "3 × 6 to 8 at 72.5 kg" (the plan's starting load)
  and, once the exercise has logged sets, "3 × 6 to 8 · next 75 kg × 6" ("next 11 reps" without a
  load). Every row opens the exercise sheet: today's target (load, sets ×
  reps, rest, "Aim for about N reps left on each set."), **Last time** and **Your best** from
  `get_my_exercise_history`, the heaviest set of each logged session as a chart (two sessions
  minimum, else "Not enough data yet"; planned values are never charted) and a tip labelled **From
  your plan** (the exercise note) or **Plan rule** (the plan's progression rule).
  With a next target the first tile is **Next target** ("75 kg × 6") instead of **Today**, followed
  by one sentence of why, from the sets logged ("Every set reached the top of the range last time.
  Add weight and start the reps again."; "Add one rep to your weakest set before adding weight.";
  holds and lowerings say why too; with reps left not logged: "Reps left were not logged, so check
  it feels right."). During a workout each set starts from the target ("Your next target"), ahead
  of last time's set. The target is computed by the server from weight, reps and reps in reserve,
  never from heart rate; an exercise with no logged sets keeps the plan's values. A first-ever
  exercise reads "First time. Pick a weight you can lift for every rep with good form." Offline
  without a saved copy it reads "Last time loads when you're online."; a saved copy says it is from
  this phone.
- **This week.** "2 of 4 done" with pips, then **Training load** (opens the load sheet below) and
  **History** ("6 workouts in 4 weeks", a sheet of completed workouts with friendly dates; a row
  opens its summary when its workout is known).
- **States.** Skeletons while the hub loads; "Your plan could not load" with the beta diagnostic and
  **Try again**; after a failed refresh the loaded plan stays with "Offline. Showing your plan from
  earlier."; "No active plan" with **Check again**. Pull to refresh reloads the hub, the readiness
  line and the Apple Health candidate.

**Training load sheet.** The verdict comes first, from the ACWR bands: "Lighter than normal for
you" (< 0.8), "About normal for you" (0.8–1.3), "Heavier than normal for you" (to 1.5), "Much
heavier than normal for you" (above 1.5); the "You" marker sits on a 0.5–1.8 scale. Day bars are
the last 7 days of `daily_load`: easy, moderate or hard from the server's day level, a socket for
rest, and "Calibrating" when the level is null (default effort). While any day in the 28-day
window holds a default effort, the row reads "About normal, calibrating" and the sheet explains
why. With no ACWR, or fewer than four sessions in the window, the row reads "Builds as you train"
and the sheet "Your load reading builds as you train", with no ratio or marker. One advice line,
chosen only from the ACWR band and the monotony rule (> 2.0 means the days are too similar). "How
this is calculated" gives the strain rule, the ratio with its 0.8–1.3 normal range, how a day is
classed (fixed cut-offs until 8 rated days, then the athlete's own last 4 weeks) and the monotony
line. Footnote: "Calculated from your logged workouts. No AI estimates."

**Planned (coaching platform, chunk B3):** progression from actual sets, with Train showing the
targets.

### Apple Health quick-complete

When Apple Health records a workout on a day with a scheduled Tracend workout but no completed
session, the workout hero replaces its action (**Start workout** or **Log this workout**) with a
prompt. It never shows on a done day.

- Kicker: **Apple Health detected workout** with the `heart_fill` icon.
- "Apple Health recorded a N min workout today / yesterday / on 2 October. Did you complete
  ‹workout name›?"
- **Yes, mark complete** (filled) completes the session with the Apple Health duration, creates an
  audit event, and refreshes adherence (toast "Workout marked complete from Apple Health").
  **Log manually** (outlined) opens the standard workout execution flow.
- After either action, the hub refreshes and the prompt is absent on later loads (the
  already-completed guard prevents duplicate prompts).

The candidate comes from `get_healthkit_completion_candidate` for the selected date, fetched on
load, on every day change and on refresh; the server returns one only where Apple Health has a
workout that day. This is a deterministic check (Apple Health data exists, no completed session
exists) combined with explicit user approval. The auto-completed session records `'Marked complete
from Apple Health evidence'` in its notes and writes an `audit_events` row with
`action_code='workout.auto_completed'`.

## 8. Nutrition and Meal Confirmation

Nutrition uses the large title with the selected day as its subtitle, and pull to refresh reloads
the day and the coach's guidance. Below the title, a week strip shows the week's date range with
previous and next week chevrons, then seven day boxes. Today carries the lime ring; the selected
day sits on a surface box; days after today are disabled; the next-week chevron stops at the
current week. Changing the day plays the `selection` haptic. Previous dates visibly identify a
saved daily log and reload confirmed totals and meals. While a day loads, skeletons stand in for
the totals and the timeline: another day's data never shows under the selected day. A day
boundary never implies deletion.

The active schedule places **Next meal** first with local time ("Due now · 13:00" when due),
planned foods, quantities, status, and **Log meal**. Macro totals come next, labeled **From
confirmed meals**, and count confirmed consumption only. The totals card shows calories, protein,
carbs and fat in sentence case, with numbers in the numeric face. Protein, carbs and fat each carry
a small colour key that matches the meal split bars; the words, not the colours, name them.

Below them, **Today's meals** (**Meals** on another day) is one vertical day timeline in time
order, in one card with hairline separators. It merges the schedule and the logged meals: a
confirmed meal logged from a slot replaces that slot's planned row. Every row has a time, a marker,
and a state word, so color is never the only signal:

- Logged meals read **Lunch · 691 kcal**, then **Logged** and their foods from `meal_items`, then a
  protein / carbs / fat split bar, with a **⋯** control ("Meal options") that opens an action
  sheet holding **Delete meal**. Deletion then requires a destructive confirmation (**Delete this
  meal?**, Cancel as the default) explaining that the meal leaves the day's totals.
- A draft shows **Needs review** and a **Review foods** action that restores its candidates; users
  never need to create a second analysis to resume unfinished review.
- Unlogged slots show **Due now**, **Planned**, **Optional**, or **Not logged** with their planned
  foods and a **Log** action.
- With nothing logged or planned the timeline reads "Nothing logged yet".

One **Log a meal** button follows the timeline (outlined while the Next meal card shows). It opens
the **Log a meal** sheet, which first picks the meal type with chips (preselected by time of day:
Breakfast before 10:30, Lunch before 15:00, Snack before 17:30, then Dinner) and then offers **Take
a photo**, **Choose from Photo Library**, or **Enter manually** as one grouped list. A photo meal is
saved under the chosen type. The coach's nutrition guidance sits at the end of the screen under a
sentence-case **Coach** label, with its confidence in words.

Feedback: confirming a meal (manual entry or reviewed candidates) plays the `success` haptic and
shows a **Meal logged** toast; a deleted meal shows **Meal deleted**. Failures stay on the page in
words, never only in a toast.

`Nutrition → Capture or enter manually → Analyze → Review candidates → Resolve catalog → Confirm meal → Totals`

**Not built yet:** the resolve-catalog step; confirming goes straight from the reviewed candidates
to the meal.

```text
AI observation                 Confirmed meal
┌────────────────────┐        ┌────────────────────┐
│ Chicken?  medium   │  edit  │ Chicken breast     │
│ Rice?     high     │  ───›  │ 160 g              │
│ Oil       unknown  │        │ Basmati rice 220 g │
│                    │        │ Cooking oil 10 g   │
└────────────────────┘        │ [ Confirm meal ]   │
                              └────────────────────┘
```

- Explain that portions and hidden ingredients are estimates.
- Candidates remain visibly unconfirmed and editable. Totals include only confirmed items.
- **Enter meal** (button **Confirm meal**) and **Review candidates** are sheets. Each candidate
  shows its serving, calories and confidence in sentence case (**Medium confidence**), starts
  selected, and edits behind **Edit estimate** (name, serving, calories, protein, carbs, fat) with
  visible labels and inline validation. Changes and selection are applied together only by
  **Confirm selected foods**.
- Low-confidence portions require correction or confirmation. **Not built yet:** every candidate
  starts selected and can be confirmed as is.
- Meal forms dismiss the keyboard by dragging, tapping outside a field, or an explicit **Hide
  keyboard** control. This control is required for iOS numeric keyboards that do not provide a
  native Done key.
- Before the first photo is picked, a sheet shows the meal photo AI notice (**Analyze meal photos
  with AI?**, the server's text, **Agree and continue**, **Not now**). **Not now** closes it
  without opening the camera or library; agreeing records the grant and continues to the picker.
  A new notice version asks again. While it is granted, **Log a meal** ends with **Turn off meal
  photo AI**, which records a withdrawal (the server stops sending photos at once; the next photo
  shows the notice again). Consent history lists **Meal photo AI analysis**.
- While a photo is analyzed, the brand loader and **Analyzing meal photo…** appear under **Log a
  meal**; the review sheet opens when the analysis returns. Processing may continue in the
  background. **Not built yet:** the analysis is awaited in place.
- A failure is shown in the same place, never only at the top of the screen, out of view. A refused
  camera or photo permission names the iOS setting to change. These outcomes say what happened in
  plain words: a library photo iOS could not load (`invalid_image`, usually an iCloud photo that
  did not download), a photo over 4 MB (`photo_too_large`), no food in the photo (422
  `meal_no_food_found`), the photo analysis being busy (429 `meal_vision_busy`, about one photo a
  minute), a changed notice (403 `meal_photo_ai_consent_required`), and the AI budget being
  reached (429 `ai_usage_limit`, naming the daily and monthly limits). Any other failure says the
  analysis did not work and keeps the beta diagnostic on a smaller second line naming the step
  (`notice`, `picker`, `upload`, `draft`, `analysis`, `app`) and its error code, for example `Beta
  diagnostic · analysis: 503 meal_analysis_unavailable`. No message names a provider.
- Failure offers **Retry**, **Enter manually**, and **Delete photo**. **Not built yet:** a photo
  failure is a notice in words with its diagnostic; a draft that cannot open says to retry or
  delete it and enter the meal manually.

## 9. Progress Review

Progress uses the large title ("Your body and strength over time"), and pull to refresh reloads the
page and the physique check. It reads top to bottom as one answer, then detail:

1. A **4W · 12W · 6M** segmented control (default 12W) that scopes the weight change, chart, and
   workout count. The header **+** records a measurement.
2. The weight hero (`WeightHeroCard`): a sentence-case **Weight** label, the latest weigh-in in the
   numeric face and its date, change since the first weigh-in in the period ("X kg since ‹date›"),
   the weekly rate, a plain-word trend steadiness, the chart, and an info button with **How this
   is calculated** (nothing in it is estimated by AI). The change chip takes the lime signal only
   when it moves toward the active goal (`fat_loss` down, `muscle_gain` up); the arrow and the
   spoken "toward your goal" carry the same meaning. With no weigh-in it asks for the first one;
   with one in the period it asks for another before drawing a trend.
   **Set your target (B7):** directly under the hero, a card appears only while the active goal has
   no end point: **Set your target**, one line saying only the athlete sets it, and **Set target**.
   The sheet takes one kind of target (**Weight**, **Body fat** or **Look**) and an optional date.
   Weight shows the lowest healthy target for the athlete's height and refuses anything below it;
   body fat takes a from and to percentage; **Look** offers a short list (visible abs, more
   definition, athletic build, bigger muscles, stronger, lean and toned, something else) with an
   optional note of up to 120 characters. A refusal from the server stays beside **Save target**.
   Saving plays the `success` haptic and shows **Target saved**. Once a target exists the card shows
   it with **Change target**. Without an active goal, or when the target cannot be read, nothing
   shows. Coach asks for a target in chat when there is none and points to this card.
3. **This week:** the weekly review card (§11).
4. **Recent weigh-ins:** the newest three in one grouped list, each with its change from the one
   before; **See all** opens every weigh-in in a sheet. A row opens the read-only detail sheet.
5. **Strength:** workouts done of planned in the period, then a horizontal row of best confirmed
   lifts (**Best · 6 workouts**). A lift tile shows a lime **New best** chip only when
   `get_my_exercise_history` dates the lift's all-time best set to its latest completed session,
   that session is the one the hub reports as the lift's latest, and an earlier session existed to
   beat. Ties keep the earlier date, so repeating a record is never new; unknown history shows no
   chip.
6. **Progress photos:** one card with the last set's date, **Take progress photos** (**Continue
   photo set** for a partial set), and **View past sets**.

The first load shows skeletons in the shape of the hero and sections; a period change keeps the
last answer on screen, dimmed, until the new one arrives. Record measurement, all weigh-ins, the
weigh-in detail, the weekly review, photo capture, past sets and the private viewer are sheets. A
saved weigh-in plays the `success` haptic and shows **Weigh-in saved**; a requested review and a
deleted photo set also confirm with a toast. A failed action shows a dismissible notice in words
beside the control that started it (the top of the page, the weekly review card, or the photo
card), never only in a toast.

### Measurements

**Record measurement** takes weight (required) and optional waist, chest, hip, arm and thigh in cm,
with visible units, inline validation, keyboard dismissal, and clear save feedback. Manual and Apple
Health values never silently overwrite each other ("Saved weigh-ins are never changed behind your
back."). The first confirmed entry is a baseline, not a trend. At least two dated entries are
required before showing a calculated delta, and a chart appears only after two real dated
comparable observations.

Show protocol, date, unit, source, confirmation, trend, and correction path. **Not built yet:** the
detail sheet is read-only, with no protocol and no correction path.

### Progress photos

`Explain purpose → Separate consent → Capture guide → Validate front/side/back → Review → Save private set`

Guide distance, pose, framing, lighting, clothing consistency, and timing. Retake remains available.
Physique photos never appear in general dashboard surfaces or notifications.

Capture requires explicit storage consent: an alert, **Save private progress photos?** ("They are
never sent to an AI model."), with **I agree and continue** and Cancel. It then opens a capture
sheet that lists front, side, back, and lower body with framing guidance, a check per finished
pose, and how many are done. The user explicitly opens the camera or library for a pose; the native
camera is never launched without this in-app context. Each pose uploads as soon as it is picked.
Errors stay inline in the sheet, and **Finish later** keeps a partial set open. Completed and
partial sets are listed under **View past sets** with labeled view and delete controls. Deleting a
set asks first with a destructive confirmation (**Delete this photo set?**, Cancel as the
default). Viewing uses short-lived authorization. **Not built yet:** the validate and review steps.

**Physique check (owner-only experiment).** Only for accounts the `physique-check` function serves;
everyone else sees no change and the card says "Only you can see these. Never sent to AI." For a
served account, the card says photos are sent to AI only when a check is started, and offers
**Physique check** on the newest complete set:
`Consent sheet ("Check your photos with AI?", server notice, first time or after a new notice) →
Checking (usually under 30 s) → Result: "AI visual estimate, not a measurement", muscles with
confidence and reason, observations, photo tips, limitations → choose up to two → Use as my focus`.

- The card names no provider (D11): "Sent to AI only when you start a physique check."
- The check sends the front, side and back photos. The newest set is the one taken last
  (`captured_on`, then `created_at`).
- A stored check stays visible after the feature is switched off for the account, and the card
  then says a set was sent to AI only for a check the athlete started, never "never". Deleting a
  set removes its checks from the card at once.
- Nothing changes without **Use as my focus**; the Coach uses the focus at once and the plan at its
  next review.
- Errors (consent, today's AI limit, the check being busy, checks unavailable for the account, no
  complete set, photos that cannot be checked, photos that show no physique to judge, an unusable
  answer) stay inline in the sheet, without a provider name. **Turn off photo checks** records a
  withdrawal.

### Comparison

The user selects two standardized sets. Show photos privately, measurement/performance trends,
confidence-qualified visual observations, and **AI visual estimate, not a body-composition
measurement**. Facial recognition, medical inference, and unrelated trait inference are prohibited.
**Not built yet:** comparison.

## 10. Persistent Change Approval

`Decision indicates proposal → Proposal diff → Evidence → Accept / Reject / Request revision → Result`

- Open proposals as dedicated screens, never chat suggestions or toasts. Persistent suggestions
  never apply in chat.
- Keep current and proposed versions visible together.
- Accept requires an explicit final action and displays effective date.
- Reject changes nothing and may collect an optional reason.
- Request revision preserves the active plan.
- Stale proposals cannot be accepted; explain what changed.

**Not built yet:** a proposal screen after onboarding. The only approval flows today are the
initial plan (§4.4), **Use as my focus** (§9) and the Coach's **Remember this ‹category›
preference?** prompt, which saves a durable preference only on **Save** (**Dismiss** saves nothing).
**Planned (coaching platform, chunk B4):** a same-day readiness adjustment with one-tap approval.

### 10.1 Coach proposal card (A8)

`Coach asks in chat → Proposal card → Approve / Not now / Change it → Result → Undo for 7 days`

When rules accept a change Coach asked for, the chat shows a card under the reply. It is the one
place a Coach suggestion can be applied, and only the athlete's tap applies it:

- The card says it was proposed by Coach and checked by Tracend, shows the confidence, the reason in
  plain words, **Now** and **After** side by side (calories and macros, the phase, the sessions with
  their days, exercises and minutes), the downside, what it is based on (collapsed) and when it
  expires. A temporary change states the day it ends and that the regular plan returns after it.
- **Approve** opens a confirm sheet ("Apply this change?", "You can undo it for 7 days"). Applying
  writes a new version; the Train, Nutrition and Today screens reload.
- **Not now** records the answer and changes nothing. **Change it** records the answer and sends a
  follow-up message to Coach ("I want to change this: …").
- After approval the card shows **Applied**, the undo deadline and an **Undo** button. Undo restores
  the earlier plan, targets or goal as a new version. If a later change replaced it, the card says
  it can no longer be undone from here.
- A proposal that expired, or whose plan, targets or goal changed meanwhile, is never applied: the
  card says what happened and to ask Coach again.
- A request the rules refuse (a calorie target under the floor, too little logging, a screening cap)
  gets no card; Coach replies with the plain reason.
- The card carries no model or company name (D11). It renders from a proposal the caller has or
  loads one by id (`CoachProposalLoader`); the chat connects a message to a proposal id.

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

On Progress the card moves through explicit states while the approved plan stays usable: "Create
your weekly review" with **Generate review**; "Weekly review is preparing" with **Refresh status**;
"Weekly review needs another try" with **Generate review**; and "Weekly review ready" with **Open
weekly review** and a **New** chip. Requesting one shows the toast "Preparing your weekly review.
Check back soon." The card says it is calculated from your logs, with no AI.

A ready review is a sheet: the week, "Calculated from your logs · no AI. Missing data is shown, not
guessed.", evidence counts (including meals logged on N days), missing categories, the unchanged
plan and targets, next focus, and **Mark reviewed** (then **Done**). A review never changes the
plan. **Not built yet:** links to source data, charts, and a proposed-adjustment section.

## 12. Apple Health and Permissions

`Contextual prompt → Explain exact value/types → iOS permission sheet → Sync → Data status`

- Ask in context and by supported type.
- Do not interpret missing read data as proof of denial.
- Distinguish connected, partial, stale, unavailable, and manual-only.
- A partial label counts data categories with samples in the sync window; it does not claim that an
  empty category proves permission denial. Show found and missing categories in plain language.
- Today shows health evidence through the recovery hero, its drivers card and the Sleep tile, and
  never prompts for access. Connect and refresh controls and the sync status card live in Account
  (and once in onboarding).
- Revocation keeps manual features usable and explains iOS settings.
- Sync shows date range and last success instead of an indefinite spinner.
- **Heart-rate zones (C3).** The Apple Health sheet in Account, once Apple Health is connected, ends
  with a small "Heart-rate zones" section under the signals: one line with resting heart rate and the
  maximum ("Resting 59 bpm · Max 183 bpm, estimated from your age", or "from your workouts" once a
  trusted workout peak is higher), the five zones (Z1 Easy to Z5 Maximum) as bpm ranges, one recovery
  line ("heart rate falls 28 bpm in the first minute, improving (+6 bpm against the 4 weeks
  before)") and "For information only. Heart rate never changes your loads." Missing data is said
  plainly and no zone is drawn: fewer than 3 recent days of resting heart rate, no birth year and no
  trusted workout peak, or fewer than 6 tracked sets in a window ("not enough tracked sets yet"). The
  section is hidden while the server cannot be read. Sleeping heart rate is not shown anywhere (D10).

## 13. Privacy, Export, and Deletion

### Account and AI usage

Account is one iOS inset-grouped settings page:

- **Identity:** the name from the email local-part, a **Private beta** chip and **Current goal**
  when the active-goal query returns one. There is no separate Edit control; **Profile and goals**
  is the edit entry.
- **Plan:** **Profile and goals** opens the read-only screen of that title (§4.4).
- **Health:** **Apple Health** with its status in plain words ("Updated today at 14:05",
  "· needs a refresh", "· some signals missing", or "Not connected · manual logging works"). It
  opens a sheet with the full status card and **Connect** or **Refresh Apple Health**.
- **Appearance:** a **System / Dark / Light** segmented control that applies at once.
- **Notifications:** switch rows that apply at once: **Daily check-in reminder** (every day at
  7:00 PM), **Weekly review reminder** (Sunday at 6:00 PM) and **Rest timer alerts**. The footnote
  says lock-screen text stays generic. The rest-timer row names its lock-screen text, "Rest timer
  finished"; when iOS has not been asked yet, turning it on first shows that text in a confirm
  (**Turn on rest timer alerts?**), and only **Continue** leads to the iOS permission request.
  **Not now**, off or a denied permission keeps the rest timer in the app only, and a denial
  points to iOS Settings. There is no in-app haptics toggle; the iOS setting governs haptics.
- **Widgets:** one switch row, **Health numbers on the Lock Screen**, off until chosen ("Off · Lock
  Screen widgets show Tracend and nothing else"; on: "recovery, today's session and protein show
  while the phone is locked"). Turning it off removes the numbers from what the widgets read at once.
  The choice is kept for the signed-in athlete on this phone and forgotten on sign-out, so another
  athlete signing in starts with it off.
  The footnote says anyone holding the locked phone can read Lock Screen widgets, and that Home
  Screen widgets show the day once the phone is unlocked.
- **AI coach:** **AI coaching** (on, or "Off · plans and logging still work"), **AI usage this
  month**, **What Coach remembers** (§13, memory) and **Coach conversations** (a sheet; deleting a conversation asks with a destructive
  confirm, **Delete thread**). The footnote says provider keys stay on Tracend's server. The AI
  coaching row names no provider (D11): "On · AI writes Coach answers".
- **Region:** one row, **Country**, optional. It opens a sheet with Australia, India, United
  Kingdom, United States, **Another country** and **Not set** (the countries are those whose
  national food and body-size guidance the research library holds). The subtitle says what it does:
  "Not set · Coach uses guidance that applies everywhere", or "India · Coach can cite India's
  national guidelines"; "Another country" uses guidance that applies everywhere. The footnote says it
  only picks which national guidelines Coach can cite and that the plan's numbers do not change. A
  failed save keeps the old choice and shows a toast; an unreadable country shows "Could not be read
  · open to try again". With nothing chosen the app behaves as it did before the row existed.
- **Privacy:** **Export data**, **Consent history** and **Delete account**, then **Sign out** at
  the foot.

Sheets use the Tracend sheet, confirmations the destructive confirm, transient results a toast,
and loading the brand loader.

**What Coach remembers** (A10 part 2) is a pushed screen. Facts you confirmed come first, grouped by
kind (injuries and limitations, schedule and life, equipment, foods and exercises you like or
dislike, allergies, coaching style, other preferences). Each row shows the words, the date it was
confirmed and where it came from (you typed it, Coach suggested it and you confirmed, or
onboarding); an injury or schedule limit older than 28 or 90 days says **Check that this still
applies**. Tapping a row opens a sheet with **Still true** (only for facts that lapse), **Edit** and
**Delete** (a destructive confirm; it removes every version). **Add something Coach should know** opens
the editor (a kind and your words, 200 characters). Under the facts are **Coach's notes** (date,
a template sentence and, for advice, how it turned out), each with a delete control and a confirm.
At the foot, **Forget everything** (destructive confirm; it deletes every fact and note and keeps
your conversations). A save that fails keeps what you typed and says so; at 60 facts, adding is off
with the reason.

**Don't remember this chat** is a switch on a new conversation's empty state, off by default. It is
chosen before the first message and cannot change. The conversation then shows "This chat isn't
remembered" at its top and "Not remembered" in the conversation list; Coach saves no notes or
suggested facts from it, never searches it and no other chat sees it.

When Coach suggests a fact, a card follows the reply (**Remember this?**, **Update what Coach
remembers?**, **Forget this?**, or **Check what Coach remembers** for an allergy): it shows the words
and why, with **Confirm** and **Dismiss**. Nothing is saved until Confirm.

**AI usage** shows only the authenticated user's sanitized current-period usage, estimated cost,
and service availability: requests today against the daily limit, successful and failed requests
this month, the warning and monthly limits, and the service state ("Available", "Approaching the
monthly limit", "Paused at the monthly limit", "Estimates only"). Token or image usage appears only
where meaningful and available; no RPC provides it today. It never reveals API keys, prompts,
provider request identifiers, raw errors, provider or model names, or another user's aggregate.
Values are operational estimates, not invoices or subscription quotas, and the footnote says so.
This month's cost is shown against the warning and stop limits **from the server budget state
only** (never hard-coded), as a meter with a tick at the warning threshold and in the Account row
("$0.42 of $3.00 · warning at $2.40"). Dollars show two decimals; a cost above zero that would
round to nothing reads **<$0.01**, never **$0.00**. **Refresh usage** refetches the live summary.
When budget fields are unavailable the screen degrades to run counts and estimates without
threshold claims; when usage cannot load the row reads "AI usage unavailable".

Provider setup is not a mobile flow. If the owner has not configured a server-side provider secret,
Account shows **AI service not configured** and explains that approved plans and manual logging
remain available. Today that row appears only in a build without a backend.

Privacy screens show consent by purpose, provider disclosure, photo retention controls, connected
data, export, and deletion.

**Consent history** is read-only: the latest `consent_records` entry per purpose (Terms of use,
Privacy policy, AI coaching, Progress photo storage, Progress photo AI analysis, Meal photo AI
analysis, Notifications). Each row leads with the choice and its date ("Granted 2 Sep 2026"); the
notice version and where it was made ("Version ai-coaching-v1 · iOS app", or "Set up during
testing" for owner-development records) are secondary text. Purposes without a record say "No
choice recorded yet". The screen never edits records; withdrawal happens through the flow that
owns each purpose.

- Export and deletion require recent authentication.
- Export asks for the account password and a separate export password of at least 12 characters,
  explains media inclusion and expiry, and exposes download only when ready. Tracend cannot
  recover that password.
- Deletion explains complete irreversible scope, requires the password and exact `DELETE`, then
  a destructive confirm (**Delete your account?** with **Delete account** and a bold **Cancel**)
  before anything is sent, and returns to signed-out state only after the server confirms it (its
  reply, or Auth reporting the account gone). A toast then says the account was deleted. If Auth
  refuses the session before the account can be checked, the phone signs out and the toast says to
  sign in to see whether the account remains.
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

An expired owner session is refreshed before account restoration and before weekly-review
generation. At restoration, a refused refresh signs out on this device and shows sign-in (§3).
Weekly-review generation instead says "Your session expired. Sign out, then sign in again." rather
than a generic queue failure.

## 15. Screen Acceptance Checklist

Every screen must:

- match a documented route and preserve predictable back behavior;
- expose one primary action and a visible escape route;
- define applicable loading, empty, partial, offline, failed, and denied states;
- identify AI-estimated, user-confirmed, and deterministic content;
- name no AI model or provider; only a consent notice names the receiving company (D11);
- meet [DESIGN_SYSTEM.md](./DESIGN_SYSTEM.md); and
- preserve approved plans and user data during interruption or provider failure.
