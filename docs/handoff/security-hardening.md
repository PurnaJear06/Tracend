# Security hardening batch (2026-10-09)

**Status:** PR 1 of 5 in review. A source review of `d26cf2c` raised leads that need fixing; the
details stay in the owner's private report, not in this public repository. The owner approved a
five-PR plan on 2026-10-09 and chose: an invite list for new sign-ups, a one-time meal-photo AI
notice enforced by the server, and session tokens in the iOS Keychain.

Merge in order; each PR deploys on its own. Migration timestamps increase in merge order, so a PR
that waits behind another must be re-stamped before it merges.

| # | Branch | Scope | Installed app |
|---|---|---|---|
| 1 | `security/storage-keys-and-authz` | media key grammar and ownership, service-role key guard, Coach preference caller check, restore-drill log output | no change |
| 2 | `security/account-boundary` | sign-up invites, recent sign-in for export and deletion, full Storage purge on deletion, Coach thread delete | no change |
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
