# Supabase API key migration (prepared 2026-10-31)

**Status:** code is ready and changes nothing today; the owner's dashboard steps below have not been
done. Supabase retires the legacy `anon` and `service_role` JWT keys by the end of 2026. This is the
plan to move the Edge Functions to the new publishable and secret keys without an outage.

## What reads a key (code inventory)

Every Edge Function reads its two keys through `supabase/functions/_shared/supabase_keys.ts`:

| Helper | Reads first | Falls back to | Used by |
|---|---|---|---|
| `supabaseSecretKey()` | Edge secret `TRACEND_SUPABASE_SECRET_KEY` | `SUPABASE_SERVICE_ROLE_KEY` | `_shared/auth.ts` (every authenticated function's `serviceClient`), `coach_context/service_source.ts`, `coach_context/contributors/screening.ts`, `health-check`, `library-embed`, `meal-media-retention`, `_shared/waitlist.ts` (waitlist join, confirm, unsubscribe) |
| `supabasePublishableKey()` | Edge secret `TRACEND_SUPABASE_PUBLISHABLE_KEY` | `SUPABASE_ANON_KEY` | `_shared/auth.ts` (the `userClient` that calls `auth.getUser()` with the athlete's token) |

A blank or unset secret falls back to the legacy key, so merging this changes nothing. The names carry
no `SUPABASE_` prefix because `supabase secrets set` refuses that prefix.

Not changed on purpose:

- **The Flutter app** already sends the publishable key (`SUPABASE_PUBLISHABLE_KEY`, an
  `sb_publishable_` value, set in `.env` and `--dart-define`). It never held the legacy keys.
- **CI and scripts** hold no Supabase API key. The local stack's keys come from `supabase status -o env`
  (coach-eval and library-eval) and `pre-deploy.sh` derives `CONTRACT_ANON_KEY` locally; both are the
  CLI's own local keys. Deploys use `SUPABASE_ACCESS_TOKEN` and `SUPABASE_DB_PASSWORD`, which are not
  API keys. `verify-live-function.sh` uses the access token.
- **The database** does not use a service key: the library worker and retention worker use Vault
  secrets of their own (`library_worker_secret`, `retention_worker_secret`).

## What I could not confirm

Whether the Edge runtime injects the new keys under a name of its own (for example a
`SUPABASE_PUBLISHABLE_KEYS` or `SUPABASE_SECRET_KEYS` variable) could not be confirmed from the repository
or the CLI (the Supabase docs search was not available to the builder), so no platform name is guessed
in code. If the dashboard's Edge Functions page lists such a variable, change the first name in
`supabase_keys.ts` and skip step 2; everything else is the same. Also unconfirmed:

- `@supabase/supabase-js@2.49.8` (pinned in 11 files) with an `sb_secret_` key in `createClient`. It
  sends the key as `apikey` and as a Bearer token; the platform is documented to accept the new keys
  that way, but step 3 proves it on this project before anything depends on it. If it fails, raise
  the pin in a separate PR first.
- Functions with `verify_jwt = true` in `supabase/config.toml` check the athlete's access token, not
  the API key. Moving the project's JWT signing keys (a different dashboard setting) is out of scope
  here and needs its own check of these functions.

## Read-only state of production (2026-10-31)

`supabase projects api-keys` lists four keys: legacy `anon`, legacy `service_role`, a `default`
publishable key and a `default` secret key. So the new keys already exist; nothing needs creating.

## Steps (owner)

1. **Merge this change and let the deploy finish.** Then, from the deployed commit, run
   `./scripts/verify-live-function.sh --all`. Setting a secret creates a new version of every function,
   so prove the code is live first (see "Verify live Edge Functions" in `docs/CI_CD_DEPLOYMENT.md`).
2. **Set the secret key.** Dashboard, Project Settings, API Keys: copy the `default` secret key to the
   clipboard, then
   `./scripts/supabase.sh secrets set TRACEND_SUPABASE_SECRET_KEY="$(pbpaste)" --project-ref qsfzzsjenopqqqhvpyaw`
   (never paste the value into a chat, file or command history). Clear the clipboard afterwards.
3. **Verify the secret key.** Wait a minute, then:
   - `./scripts/supabase.sh secrets list --project-ref qsfzzsjenopqqqhvpyaw` shows the name with a digest.
   - `./scripts/verify-live-function.sh --all` still passes.
   - `curl https://qsfzzsjenopqqqhvpyaw.supabase.co/functions/v1/health-check` answers 200 with the
     database reachable (it builds its service client from `supabaseSecretKey()`).
   - Send one Coach chat message from the device (`auth.ts` `serviceClient` and the Coach context RPCs),
     and open the Home tab. A 401 or `permission denied` in the function logs means the key is not
     accepted: go to Rollback.
   - Read-only SQL (dashboard SQL editor): the newest `cron.job_run_details` rows for the library-embed
     and meal-media-retention jobs show `succeeded` after their next run; `select count(*) from
     public.model_runs where created_at > now() - interval '1 hour'` keeps growing during use.
   - **Storage (meal photos and signed export URLs).** In the app, take a meal photo and let it be
     analysed (meal-analyze reads the stored photo from `meal-images` with the secret key), then request a
     data export from Settings (privacy-export uploads to `account-exports` and creates the signed link
     with `createSignedUrl`). Open the export link once: it must download. A 401 or "invalid signature"
     on either is a key failure.
   - **Waitlist functions.** Submit the website waitlist form with a throwaway address you control
     (waitlist-join), open the confirmation link (waitlist-confirm), then the unsubscribe link
     (waitlist-unsubscribe). They read the key through `readSettings()`, so a missing or rejected
     key shows as `not_configured` in Sentry or a 5xx on the form.
   - **Account deletion (`auth.admin.deleteUser` and Storage deletion).** privacy-delete-account is the
     one function that deletes the auth user and every stored object with the secret key. Test it
     only with a throwaway test account created for this (sign up on a build pointed at production
     is switched off, so create it from the dashboard's Authentication page, give it one meal photo
     and one export), never the owner's account. Delete it from Settings and confirm in the
     dashboard that the user and its Storage objects are gone. If a throwaway account cannot be
     made, leave this check for the cutover and keep the legacy key in place until it passes.
4. **Set the publishable key** the same way (`TRACEND_SUPABASE_PUBLISHABLE_KEY`, the `default`
   publishable key), then repeat step 3's Coach chat check: it is the only path that uses it.
5. **Watch for a day.** Sentry (`function` and `failure_code` tags) and the Edge Function logs show no
   new `authentication_required`, `invalid_session` or 401s beyond the usual.
6. **Only then retire the legacy keys** in the dashboard (API Keys, Legacy tab). Before pressing it,
   read the page to see whether disabling can be undone; if it cannot, keep the legacy keys until the
   end of 2026 deadline. Also confirm no installed build still sends a legacy key (the app has only
   ever sent the publishable key).

## Rollback

`./scripts/supabase.sh secrets unset TRACEND_SUPABASE_SECRET_KEY TRACEND_SUPABASE_PUBLISHABLE_KEY --project-ref qsfzzsjenopqqqhvpyaw`
makes every function read the legacy keys again (this too creates a new version of every function, so
re-run `verify-live-function.sh --all`). If the legacy keys were already disabled, re-enable them in the
dashboard first. No code revert is needed. To drop the helper after the migration is final, replace
its two calls with the new variables in a cleanup PR.

## Tests

`supabase/functions/_shared/supabase_keys_test.ts` (legacy default, new key wins, blank falls back,
each key switches on its own, nothing set) and the waitlist settings test.
