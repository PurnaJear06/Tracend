# Tracend UX Flows

**Status:** Authoritative MVP navigation, screen, and interaction behavior  
**Platform:** iOS-first Flutter app  
**Related authority:** [PRD.md](./PRD.md), [DESIGN_SYSTEM.md](./DESIGN_SYSTEM.md), [AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md), and [SECURITY_PRIVACY.md](./SECURITY_PRIVACY.md)

## 1. UX Objective

Every core flow should answer without requiring chat:

1. What should I do now?
2. What evidence supports it?
3. What can I review or change?

The interface progressively reveals detail. It never hides uncertainty, consent, AI estimation, or persistent plan changes.

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

External private-beta builds use Sign in with Apple. Owner-only development
builds may show email and password fields under ADR 0002. Both routes establish
a real Supabase session before protected data is shown; neither route bypasses
authentication.

The first launch says: **Your plan, explained by your data.** It does not show pricing or request optional permissions before explaining their purpose.

### Returning user

`Launch → Restore session → Today`

- Restore selected tab, scroll position, and safe in-progress drafts.
- If token refresh fails, preserve local workout data and request sign-in without deleting it.
- Resolve deep links only after authentication and authorization.

## 4. Onboarding

### 4.1 Shared eligibility and consent

1. Confirm age 18+.
2. Show the supported healthy-adult boundary.
3. Ask only eligibility questions required by the PRD.
4. If excluded, stop plan generation and show appropriate professional guidance.
5. Accept terms and privacy notice.
6. Choose **Guide me** or **I know my current plan**.

HealthKit, meal-photo AI, and progress-photo AI consent occur separately when their value is visible.

After an owner restores an existing training history, the first explicit Apple
Health refresh may backfill up to 31 days. The UI continues to use the existing
partial/unknown states and does not claim an empty result means permission was
denied. Later refreshes use the normal seven-day overlap.

### 4.2 Beginner: Guide me

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

Add current plan, performance history, targets, observed strengths/weaknesses, adherence, and plateau context. Final review separates **Kept**, **Adjusted**, and **Unknown**, preventing arbitrary replacement of valid practices.

### 4.4 Initial plan approval

Show goal, assumptions, weekly structure, exercise prescription, nutrition targets, confidence, missing information, and safety boundaries. Actions are **Approve plan**, **Edit answers**, and **Request revision**. Generation never activates a plan.

## 5. Today and Daily Coaching

```text
┌─────────────────────────────────────┐
│ Today                     Account   │
│                                     │
│ Evidence ── Trajectory ── Next move │
│ Sleep    Training    Nutrition      │
│                         TRAIN: Push │
│ Keep the planned session.           │
│ [ Start workout ]    See evidence   │
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

If no valid decision exists, show the approved plan and explain whether a check-in, sync, or retry can improve guidance. AI availability never blocks the workout.

### Quick check-in

A focused sheet collects sleep quality, energy, soreness, hunger, mood, pain, availability, and an optional note. Pain reveals location/severity questions and may invoke the safety boundary. Save updates Today and recomputes only when necessary.

### Evidence detail

Expanding the Trajectory Lens shows observation, influence, source, time window, freshness, completeness, and conflicts. Deterministic calculation and AI interpretation are labeled separately. Training and Nutrition remain perspectives in one controlled decision pipeline, not independent agents. The Coach tab provides direct user questions through the same workflow and never behaves like three separate autonomous chatbots.

Today uses a real timeline for check-in, workout, meal, and review actions. The
primary decision always uses **Do this next** and remains actionable when AI is
offline. Each Trajectory Lens point opens its source, date/freshness, and
influence; a missing point becomes a recovery action.

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

## 7. Nutrition and Meal Confirmation

The active schedule places **Next meal** first with local time, planned foods,
quantities, status, and **Log meal**. A vertical day timeline distinguishes
upcoming, due, logged, skipped, and optional items. Macro totals remain
secondary and include confirmed consumption only.

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
- Editing a candidate uses visible labels and inline validation; changes and
  selection are applied together only by **Confirm selected foods**.
- A draft meal remains visible in the timeline with a labeled **Review & edit
  draft** action that restores its candidates; users never need to create a
  second analysis to resume unfinished review.
- Meal forms dismiss the keyboard by dragging, tapping outside a field, or an
  explicit **Hide keyboard** control. This control is required for iOS numeric
  keyboards that do not provide a native Done key.
- Each timeline meal exposes a labeled delete control. Deletion requires a
  destructive confirmation explaining that the meal leaves daily totals.
- Failure offers **Retry**, **Enter manually**, and **Delete photo**.

## 8. Progress Review

### Measurements

Show protocol, date, unit, source, confirmation, trend, and correction path. Manual and HealthKit values never silently overwrite each other.

The first confirmed entry is a baseline, not a trend. At least two dated
entries are required before showing a calculated delta. Manual entry uses
visible units, inline validation, keyboard dismissal, and clear save feedback.

Progress provides period selection for measurements, comparable strength,
workout adherence, confirmed-nutrition coverage, weekly review, and private
photos. A chart appears only after two real dated comparable observations.

### Coach conversation

Coach opens with the latest daily Head Coach decision pinned above a familiar
saved-thread conversation. The composer supports multiline input, keyboard-safe
positioning, sending/typing/cancel states, selectable long answers, suggested
questions, and expandable evidence/limits. Persistent suggestions route to the
existing proposal approval screen and never apply in chat.

### Progress photos

`Explain purpose → Separate consent → Capture guide → Validate front/side/back → Review → Save private set`

Guide distance, pose, framing, lighting, clothing consistency, and timing. Retake remains available. Physique photos never appear in general dashboard surfaces or notifications.

Capture requires explicit storage consent, then guides front, side, and back in
order. Before each native camera launch, Tracend names the required pose,
displays its position in the three-photo sequence, and provides concise framing
guidance. The user explicitly opens the camera or cancels the set; the native
camera is never launched without this in-app context.
Completed and partial sets remain visible with labeled view and delete
controls. Viewing uses short-lived authorization. No photo is sent to Gemini or
analyzed until separate AI consent and evaluation gates are implemented.

### Comparison

The user selects two standardized sets. Show photos privately, measurement/performance trends, confidence-qualified visual observations, and **AI visual estimate, not a body-composition measurement**. Facial recognition, medical inference, and unrelated trait inference are prohibited.

## 9. Persistent Change Approval

`Decision indicates proposal → Proposal diff → Evidence → Accept / Reject / Request revision → Result`

- Open proposals as dedicated screens, never chat suggestions or toasts.
- Keep current and proposed versions visible together.
- Accept requires an explicit final action and displays effective date.
- Reject changes nothing and may collect an optional reason.
- Request revision preserves the active plan.
- Stale proposals cannot be accepted; explain what changed.

## 10. Weekly Review

Use an editorial sequence rather than a dashboard wall:

1. outcome summary;
2. execution and adherence;
3. recovery context;
4. training and nutrition evidence;
5. what remains unchanged;
6. any proposed adjustment; and
7. next-week focus.

Every claim links to source data. Charts include units, direct labels or legends, accessible summaries, and large touch targets.

Before a review exists, Progress offers a labeled generation action. Queued,
processing, retryable, failed, and ready states remain explicit while the
approved plan stays usable. A ready review shows the week, deterministic/no-AI
label, evidence counts, missing categories, unchanged plan/targets, next focus,
and a **Mark reviewed** acknowledgement action.

## 11. HealthKit and Permissions

`Contextual prompt → Explain exact value/types → iOS permission sheet → Sync → Data status`

- Ask in context and by supported type.
- Do not interpret missing read data as proof of denial.
- Distinguish connected, partial, stale, unavailable, and manual-only.
- A partial label counts data categories with samples in the sync window; it
  does not claim that an empty category proves permission denial. Show found
  and missing categories in plain language.
- Today reads stored daily summaries back into dated sleep, steps, energy,
  workout, resting-heart-rate, and HRV evidence. Draw a trend only when at
  least two real dated values exist; otherwise show the missing-data action.
- Revocation keeps manual features usable and explains iOS settings.
- Sync shows date range and last success instead of an indefinite spinner.

## 12. Privacy, Export, and Deletion

### Account and AI usage

Account opens as a native detail destination from the Today account control.
It shows the signed-in identity, current goal, HealthKit and notification
status, privacy controls, export, deletion, and sign out.

**Notifications** opens a native bottom sheet with daily check-in at 7:00 PM
and weekly review on Sunday at 6:00 PM. Permission is requested only after the
owner enables a reminder and saves. The sheet discloses generic lock-screen
copy before permission; denial points to iOS Settings and leaves the app usable.
Saved choices survive app termination. If iOS loses a pending request while
authorization remains active, Tracend recreates it from the local choice.

**AI usage** shows only the authenticated user's sanitized current-period
request count, token or image usage where meaningful, estimated cost, and
service availability. It never reveals API keys, prompts, provider request
identifiers, raw errors, or another user's aggregate. Values are operational
estimates, not invoices or subscription quotas.

Provider setup is not a mobile flow. If the owner has not configured a
server-side provider secret, Account shows **AI service not configured** and
explains that approved plans and manual logging remain available.

Privacy screens show consent by purpose, provider disclosure, photo retention controls, connected data, export, and deletion.

- Export and deletion require recent authentication.
- Export asks for the account password and a separate 12-character export
  password, explains media inclusion and expiry, and exposes download only when
  ready. Tracend cannot recover that password.
- Deletion explains complete irreversible scope, requires the password and
  exact `DELETE`, and returns to signed-out state only after server completion.
- Deletion explains scope and irreversibility and shows pending/completed state.
- Withdrawing photo-AI consent stops new processing and applies [SECURITY_PRIVACY.md](./SECURITY_PRIVACY.md).

## 13. Degraded and Edge States

| State | Required behavior |
|---|---|
| Offline | Keep approved plan and workout logging; queue safe writes and show sync state |
| AI unavailable | Show last valid timestamped decision and approved plan; allow retry |
| Partial HealthKit | Label available/missing types and reduce confidence |
| Stale evidence | Show age and block proposals when policy requires |
| Conflicting data | Explain conflict and request confirmation |
| Media failure | Preserve a safe local draft; retry or delete |
| Permission denied | Explain reduced capability and manual alternative |
| Empty history | Show the first useful action, not an empty chart |
| Safety escalation | Stop normal coaching and provide the appropriate next step |

An expired persisted owner session is refreshed before account restoration and
before weekly-review generation. If refresh is no longer valid, the app asks
the owner to sign out and sign in again instead of presenting a generic queue
failure.

## 14. Screen Acceptance Checklist

Every screen must:

- match a documented route and preserve predictable back behavior;
- expose one primary action and a visible escape route;
- define applicable loading, empty, partial, offline, failed, and denied states;
- identify AI-estimated, user-confirmed, and deterministic content;
- meet [DESIGN_SYSTEM.md](./DESIGN_SYSTEM.md); and
- preserve approved plans and user data during interruption or provider failure.
