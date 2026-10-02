# Account Session and Deletion Handoff

**Status:** fix in review (branch `claude/account-deletion-recovery`). Needs a reinstall after merge,
and the migration deploys with it.

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
