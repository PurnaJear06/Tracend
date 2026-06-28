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
├── Privacy and AI processing
├── Export
└── Delete account
```

## 3. App Entry and Restoration

### New user

`Launch → Brand statement → Sign in with Apple → Age/eligibility → Terms/privacy → Onboarding choice`

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
│ Today   Train  Nutrition  Progress  │
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

Expanding the Trajectory Lens shows observation, influence, source, time window, freshness, completeness, and conflicts. Deterministic calculation and AI interpretation are labeled separately. Training and Nutrition remain perspectives in one decision, not independent agents.

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
- Failure offers **Retry**, **Enter manually**, and **Delete photo**.

## 8. Progress Review

### Measurements

Show protocol, date, unit, source, confirmation, trend, and correction path. Manual and HealthKit values never silently overwrite each other.

### Progress photos

`Explain purpose → Separate consent → Capture guide → Validate front/side/back → Review → Save private set`

Guide distance, pose, framing, lighting, clothing consistency, and timing. Retake remains available. Physique photos never appear in general dashboard surfaces or notifications.

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

## 11. HealthKit and Permissions

`Contextual prompt → Explain exact value/types → iOS permission sheet → Sync → Data status`

- Ask in context and by supported type.
- Do not interpret missing read data as proof of denial.
- Distinguish connected, partial, stale, unavailable, and manual-only.
- Revocation keeps manual features usable and explains iOS settings.
- Sync shows date range and last success instead of an indefinite spinner.

## 12. Privacy, Export, and Deletion

Privacy screens show consent by purpose, provider disclosure, photo retention controls, connected data, export, and deletion.

- Export and deletion require recent authentication.
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

## 14. Screen Acceptance Checklist

Every screen must:

- match a documented route and preserve predictable back behavior;
- expose one primary action and a visible escape route;
- define applicable loading, empty, partial, offline, failed, and denied states;
- identify AI-estimated, user-confirmed, and deterministic content;
- meet [DESIGN_SYSTEM.md](./DESIGN_SYSTEM.md); and
- preserve approved plans and user data during interruption or provider failure.
