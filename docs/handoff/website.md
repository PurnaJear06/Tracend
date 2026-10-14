# Website and Waitlist Handoff

**As of:** 2026-10-13

## State

- `site/` is the public website: Astro 7 static, graphite + lime, Archivo, GSAP motion with app
  screen replicas carrying labelled example data. Pages: home, privacy, terms, confirm,
  unsubscribe, 404. `site/PRODUCT.md` holds the claim rules.
- Hosting: Cloudflare Pages project `tracend`, https://tracend.pages.dev (free). A custom domain
  later changes `SITE_URL` in `site-deploy.yml`, the `WAITLIST_SITE_URL` secret and the Turnstile
  widget's hostnames.
- The waitlist runs on the production Supabase project through `waitlist-join`, `waitlist-confirm`
  and `waitlist-unsubscribe` (migration `20261013100000_waitlist.sql`). Double opt-in: a signup
  counts once its email is confirmed. Invite links (`?ref=CODE`) move people up the list.
- Joining grants no app access. App sign-ups stay invite-only (`private.signup_invites`).

## Owner setup (once)

1. **Gmail for Tracend.** Create the account, turn on 2-Step Verification, then create an app
   password (Google Account > Security > App passwords). The address is the sender and the
   contact address on the privacy and terms pages.
2. **Cloudflare Turnstile.** Add a widget: hostname `tracend.pages.dev`, mode Managed. Keep the
   site key and the secret key.
3. **Cloudflare API token.** My Profile > API Tokens > Create Token > Custom: Account >
   Cloudflare Pages > Edit. Note the Account ID from the dashboard.
4. **GitHub** (Settings > Secrets and variables > Actions): secrets `CLOUDFLARE_API_TOKEN`,
   `CLOUDFLARE_ACCOUNT_ID`; variables `TURNSTILE_SITE_KEY`, `CONTACT_EMAIL`.
5. **Supabase** (Project Settings > Edge Functions > Secrets): `WAITLIST_SITE_URL` =
   `https://tracend.pages.dev`, `TURNSTILE_SECRET_KEY`, `SMTP_HOST` = `smtp.gmail.com`,
   `SMTP_USER` = the Gmail address, `SMTP_PASSWORD` = the app password, `WAITLIST_EMAIL_FROM` =
   `Tracend <the Gmail address>`. Set them before merging: a secret change makes a new version of
   every function, so after any later change run `./scripts/verify-live-function.sh --all`.

Merging the pull request then deploys the migration and functions, publishes the site and
checks that the live site serves the merged commit.

## Owner operations (SQL editor)

```sql
-- How the list is doing
select status, count(*) from private.waitlist_signups group by status;
-- Who came from where
select utm_source, count(*) from private.waitlist_signups where status = 'confirmed' group by 1;
-- Invite the next 20 confirmed signups (most confirmed referrals first); returns their emails
select * from private.invite_from_waitlist(20);
```

Invited people can then create an app account with the same email.

## Email provider

`_shared/smtp.ts` speaks SMTP over implicit TLS on port 465 (Edge Functions cannot use 25 or 587).
Gmail allows about 500 messages a day. With a custom domain, switch to a transactional provider
(for example Resend: `SMTP_HOST` = `smtp.resend.com`, `SMTP_USER` = `resend`, password = API key)
by changing the secrets, and update the processor list in `site/src/pages/privacy.astro`.

## Checks

- `supabase/tests/database/waitlist_test.sql` (45): access, join, rate limit, failed-email undo,
  confirm, expiry, referrals, unsubscribe and rejoin, invites, cleanup.
- Deno: `_shared/smtp_test.ts`, `_shared/waitlist_test.ts` (includes the consent version matching
  `site/src/config.ts`) and each function's `index_test.ts`.
- CI `Website Build` builds every page; `site-deploy.yml` verifies the live version.
- Local: `./scripts/site.sh run dev` with `site/.env.development` (Cloudflare's Turnstile test key).
  `supabase functions serve` currently fails to boot any function on the external SSD (Docker
  bind mount), so local checks call the handlers directly against the local database.

## Open

- 2026-10-13: the deploy of #99 stopped at the backup restore drill (the drill did not reset the
  `private` schema; fixed in the follow-up PR), so the migration and waitlist functions are not live
  yet. The site at https://tracend.pages.dev was published by hand with `wrangler pages deploy`.
- Joining showed nothing when Cloudflare asked for a tap: the form now says "One quick check: tap
  the box below to finish joining."

- The first live join needs the owner's own email: confirm the email arrives, the link confirms,
  and unsubscribe works.
- Add `Website Build` to the required checks if wanted.
- CLAUDE.md says "No Android" while the site says Android is in testing (owner's choice); the
  owner decides which spec wins.
