# Website and Waitlist Handoff

**As of:** 2026-11-27

## State

- `site/` is the public website: Astro 7 static, graphite + lime, Archivo, GSAP motion with app
  screen replicas carrying labelled example data. Pages: home, privacy, terms, beta-terms,
  confirm, unsubscribe, 404. `site/PRODUCT.md` holds the claim rules.
- Hosting: Cloudflare Pages project `tracend`, https://tracend.pages.dev (free). A custom domain
  later changes `SITE_URL` in `site-deploy.yml`, the `WAITLIST_SITE_URL` secret and the Turnstile
  widget's hostnames.
- The waitlist runs on the production Supabase project through `waitlist-join`, `waitlist-confirm`
  and `waitlist-unsubscribe` (migration `20261013100000_waitlist.sql`). Double opt-in: a signup
  counts once its email is confirmed. Invite links (`?ref=CODE`) move people up the list.
- Joining grants no app access. App sign-ups stay invite-only (`private.signup_invites`).
- 2026-10-15 (W1, coaching platform program): the privacy page covers the app as well as the
  waitlist: what the app collects, AI features only with consent per feature (including the
  physique check), the processor list with locations (Supabase, Singapore; Anthropic, United
  States; DeepSeek, China; Groq, United States; Sentry, United States, from the DSN's
  `ingest.us.sentry.io` host; GitHub for deployments and the newest 30 encrypted backups;
  Cloudflare; Google), retention and controls (export, delete, AI off). Per decision D11 no model
  name appears anywhere on the site, and AI companies are named only in that processor list.
  Owner decisions the same day: Android stays "in testing", the physique check stays shown as
  live, and the Watch wording is "For iPhone, best with Apple Watch" (never Watch-only).
  `site/PRODUCT.md` carries the claim rules. The TestFlight checklist is in
  `docs/BETA_OPERATIONS.md`.
- 2026-11-02 (`claude/beta-terms-consent`): `beta-terms.astro` holds the app's beta terms (beta
  status, 18+ and the excluded groups, not medical advice, injury risk, AI can be wrong, data,
  fair use, feedback, suspension, deletion, no warranty, liability "to the extent the law allows",
  changes re-asked in the app, Indian law, contact). It is a draft for a lawyer to review. The
  privacy page names Tracend as controller with a grievance contact (`CONTACT_EMAIL`, complaints
  settled within one month), lists workout and sleeping heart rate, adds a section on explicit
  health-data consent, says Anthropic runs Coach chat and the daily decision and that features
  can also use Groq or DeepSeek, each named in its notice, and that a change re-asks in the app.
  The website terms link to the beta terms; both footers link all three pages. **Editing
  `beta-terms.astro` or `privacy.astro` now changes a version the app asks for:** bump its date
  and `LegalNotices` together (BETA_OPERATIONS.md, "Changing the beta terms or the privacy
  notice"); `test/legal_versions_test.dart` enforces it.
- 2026-11-15 (`claude/landing-redesign`): the home page was restructured after a design review
  (people did not follow the eight-step scroll story, and phones got a long stack of screens).
  - The story is four moments of one day (train, sleep, recovery, adjust) framed by the question
    "How did it know to go lighter?". Each moment holds still for the last part of its scroll
    (`S` in `page.js`). The clock is a small label; the step rail names the four moments.
  - Phones and upright tablets now get the same pinned story as desktop (`data-lay="tall"`): copy
    on top, one phone under it running past the fold. Reduced motion, short and sideways screens
    keep the static stacked page (`data-mode="flow"`).
  - The hero copy and form are plain HTML with a CSS rise, so they never wait for a script; on a
    phone the form is on the first screen and the Coach's call is a notification on the phone's
    own screen, under the island (it scales with the phone through `--pu`).
  - Hero cards (after the owner's check on an iPhone and a laptop: they looked dropped on the page
    and lit differently from the phone). They now live inside the phone's tilt (`.dev-tilt`): the
    three inputs in one column behind its left edge, the Coach's answer in front, all lit from the
    upper right. `sizePhone()` scales them with the phone (`--fs`), keeps them clear of the copy
    and the right edge (`--hang`), and drops the inputs when the window is too narrow
    (`.fc-solo`). The outlined clock behind the phone is gone.
  - Phones: `.top-fade` dissolves content under the status bar and the menu, so nothing slides
    behind the menu or shows beside the clock; the pinned story starts 22 px below the menu.
  - Fade-ins are per block (`reveals()`, one `ScrollTrigger.batch`), so a stacked phone page does
    not get one fade for a two-screen block. The exit of a hero card uses `opacity`, not
    `autoAlpha`: the cards sit inside the phone's wrapper, which is hidden when the timeline is
    first measured, and `autoAlpha` then restores them as hidden.
  - Order after the story: demo, five apps, made for you, Coach, progress, muscle map, "Other apps
    stop at the score", "Your plan, in three steps" (the three onboarding screens, `setupStart`),
    join. "Coming next" is one labelled row at the end of the five-apps section; its Dynamic
    Island and Watch film was deleted. The meal screen left the story (the food tile and the
    hero's dinner card still show it).
  - On a phone a live readout (`.demo-mini`) docks under the menu while the sliders are on screen
    and the result ring is not, and slides in and out. It is `position:fixed`, so it must stay
    outside any element that gets a transform (it sits next to the menu in `Page.astro`).
  - One primary button style (`.btn-primary`, lime); the nav button is lime too. The closing
    heading is "Your plan starts with a goal." and the outlined clock there is gone.
  - Page length on a 390 px phone went from about 25,000 px to about 17,800 px.
  - Rules for future edits are in `site/PRODUCT.md`, "Page structure".
- 2026-11-27 (`claude/landing-v2`): rebuilt before paid Instagram traffic, after six reviews
  (cold visitors, product truth, competitors, impeccable critique 72%, technical audit, a hands-on
  teardown of WHOOP, Athlytic, Bevel, Future, Ladder and others).
  - Hero: "Know what to lift today. And why.", a 16-word lede, the form, and on phones the
    Coach's call as a notification on the phone's screen inside the first screen. `?v=sleep`,
    `?v=log`, `?v=coach` swap the headline per reel before first paint.
  - The hero copy moved outside the pinned stage. Before, it faded from the first pixel of
    scroll, so on an iPhone the keyboard's own scroll could fade the field someone was typing in.
    Now it scrolls like the page on phones; the phone rises under it and the stage pins after.
  - Sam's day has five moments: the morning check-in leads (D9), sleep 5 h 48 m, recovery 34
    Poor; the demo counts readiness points the app's way.
  - New: "Nothing changes until you say yes." (a chat plan change with Now/After, Approve, Undo)
    and "It handles the in-between." (Lock Screen logging, next targets, labels, pain check,
    memory), each mock rebuilt from the shipped code. Removed: the five-apps bento, the two
    example athletes, the muscle map, "Other apps stop at the score", the coming-next row and
    their code. About 18 phone screens, down from 23.
  - Phones get a docked "Join the beta" button after the hero form scrolls away.
  - Launch fixes: the form is wired before the motion code (`join-boot.js`) and a pre-JS submit
    does nothing instead of putting the email in the URL; a failure in `page.js` leaves a static
    page; Turnstile retries once and then points to the system browser; the waitlist allows 30
    tries per network per hour (migration `20261127120000`); `/_astro/*` is cached for a year;
    the privacy page names Cloudflare Web Analytics.
- Follow-up after the Phase 2 cutover plus its 2-week rollback window: remove DeepSeek and Groq
  from the processor list in `site/src/pages/privacy.astro`, update its date and `LegalNotices.privacyVersion`
  (athletes are asked again). A new AI company
  needs a processor-list entry before any notice names it.
- Account deletion keeps the email's `private.signup_invites` row and any
  `private.waitlist_signups` row; the privacy page says so (removed on request). A code change to
  remove them is filed separately.
- Meal photos: the privacy page says "about 7 days after you take them". The upload sets a 7-day
  deadline and confirmation only shortens it (`least(..., now() + 30 days)`), so the 30 days after
  confirmation in `docs/SECURITY_PRIVACY.md` §11 never applies in practice.

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
- The 2026-11-27 page was checked in the browser pane at phone and desktop sizes. It has not been
  tried on a real iPhone or inside the Instagram in-app browser: do that from the preview link
  before paying for ads (type in the hero form with the keyboard up; watch the pinned story while
  the address bar hides and shows).
- Owner steps after merge: turn on Cloudflare Web Analytics for the Pages project (Workers & Pages,
  tracend, Metrics), and give each reel a link like `?v=sleep&utm_source=instagram&utm_campaign=…&utm_content=sleep`.
- The physique check is shown on the page but runs only for accounts on
  `PHYSIQUE_VISION_ALLOWED_USERS` (owner-only). Widen it or relabel the page before testers expect it.
- The plan-change example uses fixed dates (13 Dec, 30 Nov, 4 Dec); refresh them after mid-December.
- The page has no founder line, tester count or testimonial, by rule. A true one-line "who built
  this" from the owner would help; it needs the owner's words.
- Add `Website Build` to the required checks if wanted.
- Decided 2026-10-15 (owner): the site keeps Android "in testing"; CLAUDE.md's "No Android"
  covers what gets built.
