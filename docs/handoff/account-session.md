# Account Session and Deletion Handoff

**Status:** the deletion recovery fix below shipped (2026-10-02). Invite and waitlist removal on
deletion is live (#110); SQL only, no reinstall.

## Invite and waitlist rows on deletion (2026-10-15)

- **Gap:** deleting an account left `private.signup_invites` (email, `claimed_by` = the deleted user
  id, timestamps) and the email's `private.waitlist_signups` row. Neither has a foreign key to
  `auth.users`, so the Auth delete's cascade never reached them.
- **Owner decision (2026-10-15):** delete both, and clear what earlier deletions left. Coming back
  takes a new waitlist signup and a new invite.
- Migration `20261015160000_account_deletion_forgets_invite.sql`:
  - `private.forget_account_invite(id, email)` deletes the invite the account claimed, an unclaimed
    invite for its current email, and the waitlist signups for both emails. A signup the person
    referred keeps its row; `referred_by` clears through the existing `on delete set null`.
  - Trigger `auth_user_forget_invite` (after delete on `auth.users`) calls it, in the same
    transaction as `auth.admin.deleteUser` or a dashboard delete, so a failure keeps the account
    and the deletion can be retried. `privacy-delete-account` needs no change.
  - `private.forget_deleted_account_invites()` ran once in the migration: invites claimed by an
    account that no longer exists are removed with their waitlist rows, except one whose email
    signed up again (the insert trigger kept the old claimer), which now names the live account.
    Returns the count removed; rerunnable from the SQL editor.
  - No grants or RLS change; all three functions are owner-only.
- pgTAP: `supabase/tests/database/account_deletion_forgets_invite_test.sql` (full SQL deletion
  path, other people's rows unchanged, an email changed after sign-up, the earlier-deletion cleanup,
  grants).
- Docs: SECURITY_PRIVACY §7 and §11, DATA_MODEL, ARCHITECTURE §3, `site/src/pages/privacy.astro`
  (and the same wording on PR #108's rewrite).
- Owner check after deploy, read-only in the SQL editor (no row should come back):

  ```sql
  select i.email from private.signup_invites i
  where i.claimed_by is not null
    and not exists (select 1 from auth.users u where u.id = i.claimed_by);
  ```

## Owner report (2026-10-02, build 273, main a716afb)

1. **Delete account** sat on "Deleting account..." for a long time.
2. After a force-close the app opened on **Connection needed** ("The account state could not be
   loaded…"), and **Retry** never got past it.
3. The account was gone in the Supabase dashboard, yet the app kept the deleted email's session.

## Causes (from the code paths, reproduced in tests)

- **Connection needed after deletion.** The gate restored the stored session and, while the access
  token was unexpired, never asked Auth whether the account still existed. Access tokens stay
  valid for up to an hour (the project's JWT expiry) after their user is deleted, and the Data API
  checks only signature and expiry. The gate's first data read, `user_accounts … .single()`, found no
  row (the deletion cascaded), threw, and the generic catch showed "Connection needed". Retry repeated
  the same read. Only after the token expired did the refresh fail, and even then the gate showed the
  error once more before a further Retry reached sign-in. `test/account_session_test.dart` "a deleted
  athlete lands on sign-in" fails on the old gate and passes now.
- **Endless "Deleting account...".** The app awaited `functions.invoke('privacy-delete-account')`
  with no timeout and no follow-up, so any request that stayed open kept the sheet spinning. The
  function deletes the Auth user before it replies and keeps running when the app disconnects,
  which matches the account being gone after the force-close. **Why the request was slow is not
  proven:** Sentry has no event for it (the gate only `debugPrint`s, and functions report only
  thrown errors; the one trace is a warm app start at 2026-10-02 14:35:12 UTC). The function logs
  and the deletion receipt will show it (queries below).
- **Found while tracing it:** a deletion whose function stopped after claiming it stayed
  `processing` for good. `request_my_account_deletion` kept returning that request and
  `claim_account_deletion` refused it, so the athlete could never delete again.

## What changes

- `lib/features/auth/account_session.dart`: `isRejectedSession` (Auth's refusal codes and 401/403,
  never a lost connection or 429), `isDeletedUser` (`user_not_found`), `LocalAccountData`, and
  `endRejectedSession`.
- `Phase2Gate` refreshes an expired session, then asks Auth (`getUser`) before any data call. A
  refused session signs out locally and shows sign-in; a lost connection still shows Retry and
  keeps the session. It also listens for Auth's involuntary `signedOut` (a refresh token refused
  while open). The client is injectable for tests.
- Local data: a deleted account removes its Apple Health sync state, usual-months marker, unsent
  check-in and open Coach thread. A refused session for an account that may still exist removes only
  the Coach thread; its athlete gets the rest back on signing in. The pending check-in is now stored
  per athlete (`daily_check_in_pending.<user id>`; an older build's envelope goes to the first
  athlete to open Today), so a kept check-in is never sent under another account.
- `SupabaseAccountDeletionRepository`: checks first whether the account is already gone (no
  password asked), stops waiting after 60 s, then asks Auth and the athlete's own
  `deletion_requests` row up to six times, 5 s apart. Outcomes: `deleted`, `signedOut`,
  `unconfirmed` (sheet shows **Check again**), or `AccountDeletionFailed` (the account remains). A
  request open for more than 10 minutes counts as stopped and can be sent again.
- Migration `20261002120000_account_deletion_stale_claim.sql`: `claim_account_deletion` also claims
  a `processing` request started more than 10 minutes ago. Same signature, so the deployed function
  needs no change. pgTAP: `supabase/tests/database/account_deletion_stale_claim_test.sql`.
- Docs: UX_FLOWS §3 (returning user) and §13, ARCHITECTURE §3, SECURITY_PRIVACY deletion.

## Owner checks

Read-only, in the dashboard SQL editor — the deletion receipt (no personal data):

```sql
select status, requested_at, started_at, completed_at,
       completed_at - started_at as took, sanitized_error_code
from public.deletion_requests
order by requested_at desc
limit 5;
```

Logs Explorer — how long the function ran and what it returned:

```sql
select timestamp, event_message, response.status_code, m.execution_time_ms
from function_edge_logs
cross join unnest(metadata) as m
cross join unnest(m.response) as response
where event_message like '%privacy-delete-account%'
order by timestamp desc
limit 20;
```

Device check after install: delete a throwaway account → sign-in screen with "Your account was
deleted."; reopening lands on sign-in. To check the stale-session path, delete a throwaway account
from the dashboard while signed in to it on the phone, then reopen the app: sign-in within a few
seconds, never "Connection needed".

## Resume, day rollover and Sentry privacy (2026-10-31, branch `claude/resume-rollover-sentry`)

From the pre-beta QA audit (groups B and C; app only, no migration, needs a reinstall).

- **One place for resume.** `lib/shared/app_lifecycle.dart`: `LoadStamp` (when and for which phone
  day data loaded; stale after 10 minutes or on another day), `ResumeObserver` (resume callback)
  and `localDayKey`. Train, Meals, Progress, Coach and Today use them; a later offline-start
  change builds on the same helper.
- **Train** reloads on resume (stale or new day) and when its tab is opened again (older than one
  minute), drops a hub reply that a newer load replaced, moves the selection to the new today
  unless the athlete picked another day, and `Start` after midnight reloads instead of sending the
  old `p_local_date`. Today's "Save workout" reloads it (`WorkoutLogChanges`); Today's session card
  selects today; "This week" counts the current week whichever week the strip shows.
- **Meals** follow today across midnight unless a day was picked; a reply for a day no longer
  shown is dropped. **Progress** reloads its brief and goal with the measurements (refresh,
  weigh-in, resume, tab). **Coach** reloads its context status and starter questions, marking it fresh only once the load
  succeeded.
- **Today** resume: Apple Health auto-sync (30-minute throttle) and health history reload, and
  the check-in replay. The queue (`check_in_queue.dart`) is a list keyed by answer day; the old
  single entry (`daily_check_in_pending[.uid]`) is moved into it on first read. After the merge with
  the pain check (B5-2) it also holds the pain-check rules: an envelope with a pain check is moved to
  the `earlier` list instead of being replaced, and a replay returns `CheckInReplay` (days delivered
  or retained, refusals, and a `CheckInFate` per idempotency key). A final refusal (22023, 22P02,
  23514, or P0001 "too many pain reports") drops that day, shows a note and reports to Sentry by
  code, unless the envelope carries a pain check: that one stays, marked, until the athlete reads the
  notice (a red flag is never dropped silently). Other failures, another P0001 included, keep the day
  and stop the replay. The old single entry is moved only after the keyed list
  was written; its keys are removed after that write succeeded, so an interruption repeats safely.
  The gate stores the device time zone on resume and holds the screens' resume refresh
  (`ResumeGate`, 5 s timeout) until the sync ended, so they never read the old `local_today`. A
  sync that succeeds after the timeout refreshes the attached screens a second time (they loaded
  with the old zone); a failed one does not.
- **Sentry** (`lib/app/sentry_scrubber.dart`, `lib/shared/diagnostics.dart`): see SECURITY_PRIVACY
  §Telemetry: request and breadcrumb URLs keep an origin and a route template only (no Storage
  path, id or filename), and an exception value is its type and code (`network` for a lost
  connection), never free text. One scrubber serves both this work and the pain check
  (`scrubEvent`/`scrubBreadcrumb`/`scrubText`): the pain keys are dropped whole, the sensitive keys are
  redacted by name part, a value in text goes whole (an unquoted multi-word value to the end of the
  line, a quoted one up to its unescaped closing quote or the end of the line, a pain value too), and
  an event's tags are scrubbed. 153 `debugPrint('Non-critical error: $e')` calls now use `logNonCritical`; gate
  refresh failures reach Sentry through `reportNonCritical`.
- **Edge:** the meal-vision providers and the handler throw or log a fixed code, never a parser
  message that quotes the model. The legacy Groq and Gemini paths stay: the gateway path shares
  their candidate validation and they are the fallback when no route is set.
- Device check: background on Meals and Train overnight, resume: both show the new day; check in
  offline on two days, resume online: both arrive.

## Offline cold start (2026-10-31, branch `claude/offline-cold-start`, stacked on #184)

QA finding M-G5. Owner decision (final): a launch with no connection opens the cached approved plan
and the in-progress workout (ARCHITECTURE wins over the old "Connection needed" line in UX_FLOWS,
which is updated). App only, no migration, needs a reinstall.

- **Saved plan.** `lib/features/train/training_hub_cache.dart` keeps the last
  `get_my_training_hub` (28-day window only) as `training_hub_cache_<uid>`: version, athlete id,
  save time and the RPC's own JSON. `SupabaseWorkoutRepository.loadTrainingHub` saves it after each
  success; on any failure (or 10 s without an answer) for the default window it returns the copy as
  `TrainingHubData.cachedAt`, with the phone's today in place of the server's (and without the
  load numbers and today's workout when the copy is from another day). No copy: the failure is
  rethrown. `loadSavedTrainingHub` reads it directly. `LocalAccountData` removes it on sign-out
  (`signOutAthlete`), a refused session (`forgetSession`) and deletion (`clear`, via
  `WorkoutLocalKeys.owns`). A copy tagged with another athlete is ignored.
- **Gate.** `Phase2Gate._refresh` splits the account check into `_checkAccount`. With a session, if
  the check throws (not a refusal) or takes longer than six seconds, and a copy exists for that
  athlete, `_openSaved` opens `AppShell(offline: true)` (onboarding is taken as complete; AI
  consent is left undecided, so AI stays off). The check keeps running behind it. Resume and
  **Try again** run a quiet check (`_refresh(quiet: true)`: no loader, a failure changes nothing);
  success sets `_offline = false` and the shell announces `PlanChanges` so Train reloads. No copy
  means **Connection needed** + Retry as before; no session means sign-in. Sentry gets one
  `Account state not loaded` when the app goes offline, not one per retry.
- **Shell.** `AppShell.offline` opens on Train; Today shows `OfflineToday` (account button stays
  for sign-out), Coach, Meals and Progress show `OfflineTab` (`lib/features/shell/offline_tabs.dart`).
- **Train.** The copy shows at once while the server is tried (`_showSaved`), under the note
  `_OfflineNote` ("Offline. Showing your saved plan from 28 Oct." plus ", N days ago. It may have
  changed." from 14 days) with **Try again**; recovery and the day-adjustment card are hidden for a
  copy, and a copy is reloaded on every resume or tab return. The repair/reconciliation lists load
  beside the hub with a 5 s cap, so a bad connection does not hold the plan back.
- **Workout.** The start/log/finish queue already existed (`pending-<key>` session id, replay with
  the same idempotency key, saved finish). New: the logger sends what waited (a saved finish, else
  unsent sets and the start) when the app comes back to the front.
- **Not made offline:** Coach and AI, meals and photos, Progress, Today's brief, check-in (it
  already queues), recovery, the day adjustment, Apple Health sync.
- Device check: airplane mode, force-quit, reopen: Train opens on the saved plan with the note;
  start a workout, log a set, Finish: "Finish not sent yet"; turn the network on and come back to
  the app: the workout is saved. An expired-token launch shows the loader up to six seconds first.

### Offline cold start, round 1 review fixes (PR #185)

- **A plan copied while a workout waited (HIGH).** The hourly block end and a lighter week copy the
  plan with new workout ids, so an offline start against the saved id got P0002 and the session
  stayed `pending-` for ever. A `PostgrestException` from `start_workout` is now a server answer,
  never "offline". P0002: `SupabaseWorkoutRepository.moveToCurrentPlan` reads the live hub, finds
  the workout with the same `order` and the same exercises (exercise order and plan name;
  `WorkoutIdentity`, which the logger also writes into the local draft as `workout_identity`), moves
  the draft and the saved finish to the new id and the logger starts again with the same key. No
  match: the sets stay under the old id, the logger says "Not in your current plan", and finish says
  it cannot be finished yet. 55000: the logger opens as the completed workout and the draft goes
  (the existing completed path). Other codes: **Needs attention**, not Offline. The plan unreadable
  at that moment stays offline. Since the merge with #181, `WorkoutIdentity.sameName` is the one
  exercise-name rule for a plan copy and for #181's check of a server session against the plan.
- **Sending without the logger (MEDIUM).** `SupabaseWorkoutRepository.sendWaiting` sends this
  athlete's finished workouts (draft + saved finish) and drafts with done sets left on an earlier
  day, one at a time, through `sendLeftOverDraft` (the logger's earlier-day logic, now shared; it
  also does the P0002 move). It runs when the gate finishes an account check (leaving offline
  mode or a normal launch) and after each successful hub load; it does nothing while a logger is
  open (`loggerOpen`) or for a workout of today that is not finished, and never reads another
  athlete's keys. Repeats are harmless: the server replays.
- **Sore areas offline (MEDIUM).** `OfflineSafetyNotes` (safety route and the lines for areas on
  hold or eased, built from the day card's own wording) are saved beside the plan whenever the
  server gives an adjustment (`DayAdjustmentController.onAnswered`), cleared with it, and shown on
  an offline Train. With nothing saved Train says "Pain holds can't be checked offline. Skip any area
  on hold." A copy from another day also drops `next_targets` (a lighter week changes their loads).
- **Sign-out race (LOW).** A hub load that finishes after sign-out no longer saves (the athlete is
  checked right before the write, and the copy is cleared if they left during it); the gate's
  signed-out listener also clears the copy.
- **Progress** never shows the phone's copy: a cached hub is treated as unavailable there.

### Offline cold start, round 2 review fixes (PR #185)

- **Account switch during a hung start.** `moveToCurrentPlan` takes the draft owner's id
  (`ownerId`) and returns null when another athlete is signed in after the live plan was read;
  `sendLeftOverDraft` captures the signed-in athlete before the first start (`signedInUserId` on
  `WorkoutPlanRemapper`) and checks it again right before the retry start, and the logger does the
  same. Nothing of athlete A's is moved or started in B's account; the draft stays under A's keys.
- **55000 from a sync.** A refusal "not taking sets" now opens the finished session (since the
  merge with #181, through its `_settleFinished`/`_openFinished`): the draft goes, instead of
  "could not save your sets". Opening the logger waits for a send of waiting workouts that is on
  this workout (`WorkoutSendInFlight.sendInFlight`), so it reads the server after it (bounded since
  round 3).
- **Finish with no match in the plan.** The finish effort is kept on the phone with the draft
  (`savePendingFinish`, the same write `completeWithEffort` makes), so `sendWaiting` sends it once a
  match exists. The no-match is reported to Sentry as "workout not in current plan" (type only).
- **Sore-area notes** are saved under the athlete the shell opened for, and dropped if another
  athlete is signed in when the answer arrives (`saveSafetyNotes(adjustment, userId:)`).
- **Manual meal sheet** uses the app's clock again (`widget.clock()`), lost in a merge.
- Merged with main (#181 to #183): one start path in the logger. 22023 closes with a message and
  keeps a draft with sets; 55000 opens the finished session, clears the draft and says when sets
  were not added; P0002 moves the draft. The gate restores reminders only after a successful account
  check, through #182's reminder queue, so a restore never lands after a sign-out's cancel.

### Offline cold start, round 3 review fixes (PR #185)

- **An earlier day's unfinished sets stay on that day.** `sendLeftOverDraft` now starts a session the
  server never created whenever the draft has done sets, finished or not, on the local date the
  draft was started (`actual_started_at`), then syncs it. A draft that still cannot be sent opens in
  the logger as saved, and its start, reads and finish use that day (`_sessionDate`), never the day
  the logger opened.
- **A stalled send no longer holds the logger.** `sendInFlight(workoutId)` waits only for a send of
  the workout being opened, and opening waits at most three seconds. Past that the logger shows the
  phone's draft and logs on the phone, but its start, syncs and discard wait for that send, and it
  does not send the earlier-day draft itself. The send clears a draft only if no logger wrote a later
  revision or another session to it meanwhile.
- **Train on a saved hub shows no guidance.** The lighter-week card and the cardio row come from the
  server's last answer, which cannot be checked offline: both are hidden while the hub is a saved
  copy.
- **A move cut short keeps its finish.** When the new id already holds the same session's draft (an
  earlier move stopped after writing it), the saved finish is copied over before the old id is
  cleared.
