# Security hardening batch (2026-10-09)

**Status:** PR 1 (#88), PR 2 (#89) and PR 3 in review, each stacked on the one before; merge in order. A source review of `d26cf2c` raised leads that need fixing; the
details stay in the owner's private report, not in this public repository. The owner approved a
five-PR plan on 2026-10-09 and chose: an invite list for new sign-ups, a one-time meal-photo AI
notice enforced by the server, and session tokens in the iOS Keychain.

Merge in order; each PR deploys on its own. Migration timestamps increase in merge order, so a PR
that waits behind another must be re-stamped before it merges.

| # | Branch | Scope | Installed app |
|---|---|---|---|
| 1 | `security/storage-keys-and-authz` | media key grammar and ownership, service-role key guard, Coach preference caller check, restore-drill log output | no change |
| 2 | `security/account-boundary` | sign-up invites, recent sign-in for export and deletion, full Storage purge on deletion, Coach thread delete | server works with the old build; reinstall for the invite message and delete reporting |
| 3 | `security/abuse-limits` | time zone writes, consent records, health sync bounds, upload quotas and orphan sweep, content caps | no change |
| 4 | `security/ai-spend-and-consent` | AI budget reservations, failed-call cost, provider price defaults, meal-photo notice, AI notice v5 | needs the new build |
| 5 | `security/keychain-and-ci` | Keychain session storage, pinned actions, workflow permissions | needs the new build |

## PR 1: media keys and caller checks

- Migration `20261009120000_storage_object_key_hardening.sql`:
  - `private.is_owned_media_key` accepts only the app's upload grammar.
  - `create_meal_photo_draft` binds the key to the request id and requires an uploaded object the
    caller owns (as `register_progress_photo` already did).
  - `register_progress_photo` requires the exact key instead of a prefix.
  - `media_objects_object_key_safe` (`NOT VALID`) keeps new keys inside the owner's folder.
  - `persist_coach_preference` refuses any athlete but the caller unless the caller is the service
    role.
- `_shared/storage_keys.ts` guards every service-role Storage call: meal-analyze, physique-check,
  privacy-export (unsafe keys listed under `skipped_media`), privacy-delete-account (an unsafe key
  fails the deletion before anything is deleted, so it never reports success with a private object
  left) and both retention workers (unsafe keys never sent, counted and reported to Sentry).
- deploy.yml: restore-drill psql output goes to a removed temporary file; a failure prints only the
  step and the failing line.

**Owner steps before merging PR 1** (read-only, dashboard SQL editor; keep the results private):

```sql
-- 1. Media keys outside the app's upload grammar (expect none).
select id, user_id, purpose, created_at from public.media_objects
where object_key !~ ('^' || user_id || '/(meal/[0-9a-f-]{36}|progress/[0-9a-f-]{36}/(front|side|back|lower))\.(jpg|jpeg|png|heic)$');
-- 2. Storage names with dot segments or encoded characters (expect none).
select bucket_id, owner_id, created_at from storage.objects
where name ~ '(^|/)\.\.?(/|$)|//|\\|%';
-- 3. Coach preferences: every row should be one you confirmed.
select user_id, category, key, provenance, created_at from public.user_preferences order by created_at;
```

If query 1 returns rows you recognise as your own older photos, say so before merging: the export
and deletion still handle them (they only need a safe key in your folder), but a new draft will not
accept that shape.

**After the deploy:** `gh run list --workflow deploy.yml --status failure`, and delete any run that
failed in "Restore schema + data into isolated database" (`gh run delete <id>`).

**Device check (no reinstall):** analyze a meal photo, add a progress photo, run the physique check,
confirm a Coach preference, and request a privacy export.

## PR 2: account boundary

- Migration `20261009130000_account_boundary.sql`:
  - `private.signup_invites`, seeded from every existing account, so your account needs no step.
    `private.handle_new_auth_user` refuses an email, phone or anonymous sign-up that is not
    invited; the Auth insert rolls back and no email is sent. The app says "This email isn't on
    the invite list yet."
  - `private.has_recent_sign_in` reads the JWT `amr` claim. `request_my_data_export` and
    `request_my_account_deletion` use it instead of `iat`. The app already signs in with your
    password right before both, so nothing changes for you.
  - An export neither starts nor completes while an account deletion is pending.
  - `list_account_storage_objects` (service role) lists every object in an account's folders;
    account deletion removes them along with the recorded keys.
  - Coach context snapshots now cascade with their conversation, and `delete_coach_thread` also
    removes the conversation's summaries, so deleting a conversation works again.
- privacy-export removes a package that failed after upload. Failed conversation deletes are
  reported to Sentry.

**Owner steps before merging PR 2** (dashboard, read-only):
1. `select email, created_at, last_sign_in_at from auth.users order by created_at;` and remove any
   account you don't recognise.
2. Authentication settings: anonymous sign-ins, phone and Apple off; "Confirm email" on; no other
   before-user-created hook.

**After the deploy:** the server changes work with the installed app, but the invite-only message
and the Sentry report for a failed conversation delete arrive only with a new build, so install
from merged main (`./scripts/install-device.sh`), then:
1. `select email, claimed_by is not null as claimed from private.signup_invites;` shows your email.
2. On the device, sign out and back in, then request a privacy export (it checks the new recent
   sign-in rule). Don't test with account deletion.
3. Delete a Coach conversation.
4. Invite someone with
   `insert into private.signup_invites(email, note) values (lower('<email>'), 'beta');`.

## PR 3: abuse limits

- Migration `20261009140000_abuse_limits.sql`:
  - **Time zones:** clients lose the direct column grants (`set_my_timezone` stays). Stored names
    Postgres doesn't know become `UTC`, and `private.safe_timezone` keeps one bad value from
    stopping the weekly-review scheduler.
  - **Consent records:** a column-level insert grant (no client `created_at`), a recency index, and
    100 a day.
  - **Row caps:** 200 goals, 50 Coach conversations a day and 1,000 in all, 10 photo sets a day
    (`private.enforce_user_row_limit`, SQLSTATE 54000).
  - **JSON size:** onboarding drafts up to 128 KB, goal details up to 16 KB (`NOT VALID`).
  - **Health sync:** a replay skips the workouts. The window may end at most 2 days ahead, a
    summary holds up to 20,000 source references, workouts fall within the window ±1 day, and
    there are 120 syncs an hour. Reconciliation covers only the workouts in the payload (the
    7-day refresh resends recent ones).
  - **Uploads:** `user_media_upload_quota` allows 100 meal photos a day (3,000 kept) and 60
    progress photos a day (2,000 kept).
  - **Orphans:** `list_orphan_storage_objects` lists objects with no row. The retention worker
    removes them, never sends an unsafe name, and reports `orphan_sweep` counts.
- `health_sync_v1.ts` mirrors the limits (`healthSyncLimits`), with a test that compares them to
  the migration.

**Before merging PR 3**, check the limits against your real data (read-only):

```sql
select max(jsonb_array_length(source_refs)) from public.daily_health_summaries;
select max(octet_length(payload::text)) from public.onboarding_drafts;
select max(octet_length(details::text)) from public.user_goals;
select user_id, count(*) from public.user_goals group by 1 order by 2 desc limit 3;
select user_id, count(*) from public.coach_threads group by 1 order by 2 desc limit 3;
select user_id, date_trunc('day', created_at) d, count(*) from public.consent_records
  group by 1, 2 order by 3 desc limit 3;
select user_id, date_trunc('hour', created_at) h, count(*) from public.health_sync_runs
  group by 1, 2 order by 3 desc limit 3;
select bucket_id, owner_id, count(*) from storage.objects group by 1, 2 order by 3 desc limit 5;
select count(*) from public.user_accounts a
  where not exists (select 1 from pg_timezone_names z where z.name = a.timezone);
select jobname, schedule, active from cron.job;
```

Each limit should be at least 4× the largest value. Send me the maxima if any comes close, and I'll
raise that limit before you merge.

**After the deploy (no reinstall):** open the app and let Health sync run, then pull to refresh;
change nothing else. If a sync fails, the health-sync logs show the reason.
