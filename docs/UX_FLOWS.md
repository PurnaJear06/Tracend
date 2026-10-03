# Tracend UX Flows

## Train Truth and Recovery

Train uses the 4/8-point spacing rhythm and 44-point interactive rows. Active logging reports Saved,
Syncing, Offline, or Needs attention; resumes entered sets after reopen; and requires explicit skip
actions. Historical corrections and HealthKit conflicts use review cards with confirmation actions.

The Train tab (2026-09-04 redesign) opens with the week rail — one fused card where the day slots
select the day and the 7-day training-minutes chart below speaks the same visual grammar as Today's
trend (indigo day columns, accent-NOW latest session day, dim sockets, amber dots for planned-but-
untrained days). Its verdict is one plain sentence with a band chip (Low load / Optimal / High load);
the raw ratio and day load sit in one quiet mono strip — the only place jargon lives on Train.
Honesty gates: fewer than four sessions renders "Building baseline" and never a ratio verdict;
sessions without a duration stay present without inventing magnitude. Below the rail: the workout
hero (facts + coach insight + Start/View), today's exercises as one merged list (prescription stats
and the planned/recorded effort bar per row — the same movement no longer appears twice), one
execution card (adherence count + progression rows or its honest empty copy), and recent sessions.

Train redesign data rules (2026-10-03, `lib/features/train/train_view_models.dart`), read by the
new Train screen:

- **Plan pill.** "Week N of M" counts 7-day weeks from `active_plan.effective_date` to
  `local_today`; after the block it reads "Week N" alone. A cached 1.5 hub (no dates) or a plan that
  has not started shows no pill.
- **Readiness line.** One sentence about state, never advice: Excellent ≥80 "Recovery is
  excellent.", Good ≥65 "Recovered. Good to train.", Moderate ≥50 "Recovery is moderate.", Low ≥35
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
├── Profile and goals
├── HealthKit and notifications
├── AI service status and my usage
├── Privacy and AI processing
├── Export
└── Delete account
```

## 3. App Entry and Restoration

### New user

`Launch → Brand statement → Configured Supabase sign-in → Age/eligibility → Terms/privacy → Onboarding choice`

External private-beta builds use Sign in with Apple. Owner-only development builds may show email
and password fields under ADR 0002. Both routes establish a real Supabase session before protected
data is shown; neither route bypasses authentication.

The first launch says: **Your plan, explained by your data.** It does not show pricing or request
optional permissions before explaining their purpose.

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
5. Accept terms and privacy notice.
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
  **Focus** line under Training, and the usual months in **How this was calculated**. Train
  pre-fills the kg field with the starting load.

- **Apple Health** reads the last four weeks when the athlete taps **Connect Apple Health**, then
  shows what it found (days and categories). Nothing found explains Settings › Health › Data Access
  & Devices and offers **Try again**; the athlete can always continue. A failed read can be retried
  or skipped. Reopened after a sync that finished, the step shows it as connected. About you then
  starts the weight at the newest Apple Health weight from the last 14 days (labelled with its
  date, until the athlete moves it, and never over an answered weight) and shows average steps
  with a **Matches your steps** tag on the daily-activity answer they point to. The athlete's own
  answers are what count. Review shows what Apple Health contributed, and the proposal's **How
  this was calculated** adds the summary the plan used.
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
  four digits or a tap outside. Choice cards show their selected state with a border and tint.
- **Review** lists every answer (Apple Health, daily activity, equipment and its note, diet,
  movements to avoid, limitations, focus, and for an experienced athlete their training and top
  sets). Each row has
  **Edit**, which opens its step; that step's button reads **Save and return to review**. At
  large text sizes labels sit above their values.
- **Building your plan** says it usually takes under a minute and can take up to two.
- A draft from an older build continues at **About you**.
- The header reads **Step N of M · ‹section›**: 15 steps for an experienced athlete, 13 for a
  beginner, who skips Your training and Current lifts.

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

- **Provenance:** **Proposed by AI (‹model›) · checked by Tracend**, or **Built by Tracend's rules**.
- **Confidence.**
- **The assessment.**
- **Training:** every training day with its exercises (sets × reps, RPE with the reps left in
  plain words, for example "RPE 7.5 (about 2–3 reps left)", rest).
- **Nutrition:** the targets and **How this was calculated** (resting energy × activity plus
  training, and the goal range).
- **For an experienced athlete:** what was kept and what changed.
- **The plan's reasoning:** why, benefit, downside, assumptions, and what is not known yet.

Approval activates exactly those workouts, then shows **You're set.** once: the plan, the next
session and its weekday, the daily calories and protein, and the Apple Health status, with **Go
to Today**. **Account › Profile and goals** lists the onboarding answers approval kept (sex, birth
year, daily activity, equipment and its note, movements to avoid, limitations, diet), read-only.

## 5. Today and Daily Coaching

```text
┌─────────────────────────────────────┐
│ Today                     Account   │
│                                     │
│ RECOVERY              [Good]        │
│ 72 / 100 · five driver rows         │
│ 7-DAY TREND        HRV · ms         │
│ ~~~~ real recorded days ~~~~        │
│ TRAIN: Push · LOAD 1.05 Optimal     │
│ [ Start workout ]  [ View analytics ]│
│                                     │
│ Check-in needed · 1 min             │
│ Training perspective         ›      │
│ Nutrition perspective        ›      │
│                                     │
│ Today  Train  Coach Nutrition Progress │
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

### Quick check-in

A focused sheet collects sleep quality, energy, soreness, hunger, mood, pain, availability, and an
optional note. Pain reveals location/severity questions and may invoke the safety boundary. Save
updates Today and recomputes only when necessary.

### Evidence detail

Readiness evidence is shown inline, not hidden behind a tap: the recovery readout lists
each driver's true z-score next to its bar and shows No data for unusable components
(a valid sleep reading whose baseline is still maturing shows the measurement with
"Building baseline" instead), the sleep architecture card carries the quality score
with its four sub-scores (Duration, Efficiency, Restorative, Consistency) and the
debt/surplus pill (positive = debt, negative = surplus, 0 = target met), the 7-day
trend plots only recorded days with its date range and recorded-day count, and the
session plan card states the real ACWR and zone. Sync source and freshness live in
the profile's Apple Health status card and beside the hero sync chip (last health sync
time), in ordinary coaching language. Deterministic calculation and AI interpretation are
labeled separately. Training and Nutrition remain perspectives in one controlled decision
pipeline, not independent agents. The Coach tab provides direct user questions through the
same workflow and never behaves like three separate autonomous chatbots. A live assistant
message is labeled with its provider; a provider or validation failure never substitutes generic
coaching text. Replies display bold, italic, and bullet or numbered lists, so they read as formatted
text rather than raw Markdown.

When the model cannot answer, Coach shows a labeled reply in its place:
- "Data summary · not an AI answer": what the athlete's data shows.
- "Safety note · not an AI answer": for a message that may concern a health risk.

A live labeled reply also shows a beta diagnostic line (failure code and rule names); a stored one
keeps only its label, because the diagnostic is not stored. Retry appears when the reply ends the
conversation, and it keeps whatever the user is typing.

Other failures (sign-in, database, limits, network) keep the visible inline alert and Snackbar. A
timeout says the Coach took too long. During the private beta, other errors show their raw text,
including the HTTP status and the server's stable code, so the owner can see where they come from
(owner decision, 2026-09-27). The server never sends parser messages, provider bodies, prompts, or
health context.

Today uses a real timeline for check-in, workout, meal, and review actions. The primary
decision always uses **Do this next** and remains actionable when AI is offline. A missing
readiness signal becomes a direct recovery action (sync Apple Health or add a check-in).

Coach shows an expandable **Your coaching context** card on a new conversation, before its first
message; an ongoing conversation shows no cards above it. It lists approved
plan, goal/profile, Apple Health, check-ins, confirmed nutrition, completed Tracend workouts,
measurements, and conversation history with honest availability/count/latest-date metadata.
Model-cited evidence and actual data gaps use **Evidence used and data gaps**; generated follow-up
ideas use the separate **Suggested next actions** heading.

## 6. Workout Execution

`Train → Workout preview → Start → Exercise/set logging → Complete → Summary`

- Preview shows objective, duration, exercises, warm-up, adjustment, and substitutions.
- Keep current exercise and set controls within thumb reach.
- Prefill prior load/reps only as an unconfirmed reference.
- Set completion gives immediate feedback and one light haptic.
- Rest timer never blocks editing or navigation.
- Substitution requires a reason and shows whether the objective is preserved.
- Pain is reachable without an overflow menu.
- Autosave locally and expose offline/sync state without interruption.
- Later corrections to a completed session create audited amendments.
- Completing a workout pops back to the Train tab and refreshes the approved plan, adherence count,
  and recent sessions without manual reload.

## 7. HealthKit Quick-Complete

When Apple Health records a workout on a day the user has a scheduled Tracend workout but no
completed session, Train presents a prompt card instead of the normal **Start workout** button:

- Status chip: **Apple Health detected workout** with `heart_fill` icon.
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

The weekday strip shows a green checkmark circle for completed days and a gray dot for planned-only
days. The workout hero card displays a "Completed" pill and "View workout" (outlined) button for
days with a completed session.

## 8. Nutrition and Meal Confirmation

The active schedule places **Next meal** first with local time, planned foods, quantities, status,
and **Log meal**. Macro totals come next, labeled **From confirmed meals**, and count confirmed
consumption only.

Below them, **Today's meals** is one vertical day timeline in time order. It merges the schedule and
the logged meals: a confirmed meal logged from a slot replaces that slot's planned row. Every row
has a time, a marker, and a state word, so color is never the only signal:
- Logged meals read **Lunch · 691 kcal**, then **logged** and their foods from `meal_items`, then a
  protein / carbs / fat split bar, with a **⋯** menu that holds **Delete meal**.
- A draft shows **needs review** and a **Review foods** action.
- Unlogged slots show **Due now**, **Planned**, **Optional**, or **Not logged** with their planned
  foods and a **Log** action.

One **Log a meal** button follows the timeline. It opens a sheet that first picks the meal type
(preselected by time of day: Breakfast before 10:30, Lunch before 15:00, Snack before 17:30, then
Dinner) and then **Take a photo**, **Choose from Photo Library**, or **Enter manually**. A photo
meal is saved under the chosen type. The coach's nutrition guidance sits at the end of the screen,
with its confidence in words.

Nutrition opens on Today and provides previous/next-day controls. Previous dates visibly identify a
saved daily log and reload confirmed totals and meals; the next-day control stops at Today. A day
boundary never implies deletion.

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
- Each timeline meal's **⋯** menu holds a labeled **Delete meal** action. Deletion requires a
  destructive confirmation explaining that the meal leaves daily totals.
- Failure offers **Retry**, **Enter manually**, and **Delete photo**.
- While a photo is analyzed, a progress line appears under **Log a meal**. A failure is shown in
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
2. The weight hero (`WeightHeroCard`): latest weigh-in and its date, change since the first weigh-in
   in the period, the weekly rate, a plain-word trend steadiness, and the chart. With no weigh-in it
   asks for the first one; with one in the period it asks for another before drawing a trend.
3. **This week:** the weekly review card (§11).
4. **Recent weigh-ins:** the newest three in one grouped list, each with its change from the one
   before; **See all** opens every weigh-in. A row opens the read-only detail.
5. **Strength:** workouts done of planned in the period, then a horizontal row of best confirmed
   lifts.
6. **Progress photos:** one card with the last set's date, **Take progress photos**, and **View past
   sets**.

### Coach conversation

Coach opens a familiar saved-thread conversation. The daily Head Coach decision is on Today, not
pinned above every conversation (owner report, 2026-09-30):
- It reopens the conversation last opened on this device, otherwise the one with the newest
  message. With no saved conversation, it starts a new one.
- A new conversation, from launch or from New, is saved only when its first message is sent.
- Saved conversations lists only conversations that contain a message, newest first, and
  refreshes after every send.

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
controls. Viewing uses short-lived authorization.

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

Account opens as a native detail destination from the Today account control. It shows the signed-in
identity, current goal, HealthKit and notification status, privacy controls, export, deletion, and
sign out.

**Notifications** opens a native bottom sheet with daily check-in at 7:00 PM and weekly review on
Sunday at 6:00 PM. Permission is requested only after the owner enables a reminder and saves. The
sheet discloses generic lock-screen copy before permission; denial points to iOS Settings and leaves
the app usable. Saved choices survive app termination. If iOS loses a pending request while
authorization remains active, Tracend recreates it from the local choice.

**AI usage** shows only the authenticated user's sanitized current-period request count, token or
image usage where meaningful, estimated cost, and service availability. It never reveals API keys,
prompts, provider request identifiers, raw errors, or another user's aggregate. Values are
operational estimates, not invoices or subscription quotas. Budget thresholds (warning, hard stop,
daily limit) render from the server budget state rather than hardcoded copy, and Refresh usage
refetches the live summary. When budget fields are unavailable the screen degrades to run counts
and estimates without threshold claims.

Provider setup is not a mobile flow. If the owner has not configured a server-side provider secret,
Account shows **AI service not configured** and explains that approved plans and manual logging
remain available.

Privacy screens show consent by purpose, provider disclosure, photo retention controls, connected
data, export, and deletion.

**Privacy and AI processing** opens a read-only consent ledger: the latest append-only
`consent_records` entry per purpose (terms, privacy, AI coaching, progress photo storage, progress
photo AI, notifications) with its grant/withdrawal state, date, and notice version. Purposes without a record
say so. The ledger never edits records; withdrawal happens through the flow that owns each purpose.

- Export and deletion require recent authentication.
- Export asks for the account password and a separate 12-character export password, explains media
  inclusion and expiry, and exposes download only when ready. Tracend cannot recover that password.
- Deletion explains complete irreversible scope, requires the password and exact `DELETE`, and
  returns to signed-out state only after the server confirms it (its reply, or Auth reporting the
  account gone).
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
