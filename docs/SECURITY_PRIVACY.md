# Tracend Security and Privacy Specification

**Status:** Authoritative private-beta security and privacy requirements\
**Data profile:** Health, fitness, nutrition, body measurements, and private photos

This document states the rules and how the current build meets them. Work scheduled by the coaching
platform program ([`plans/coaching-platform-2026-10/README.md`](./plans/coaching-platform-2026-10/README.md))
is marked **Planned** with its phase and chunk.

## 1. Commitments

Tracend collects sensitive information to provide user-requested fitness coaching. It must:

- collect the minimum data required for enabled features;
- explain each sensitive use before collection or provider processing;
- use health data only for fitness coaching requested by the user;
- never sell health data or use it for advertising, profiling, or data brokerage;
- keep photos and health records private by default;
- provide access, export, consent withdrawal, and deletion controls;
- keep AI suggestions subordinate to deterministic safety and user approval; and
- disclose that Tracend is coaching support, not medical advice.

This document is an engineering specification, not a substitute for jurisdiction-specific legal
review. Tracend remains a working brand pending trademark and App Store clearance.

## 2. Data Classification

### Restricted

- HealthKit summaries, workout references and source metadata;
- workout performance, check-ins, pain, hunger, mood, and notes;
- same-day readiness adjustments (`day_adjustments`: the answer, its reasons and the sleep and recovery
  values the rules read);
- pain checks (`pain_reports`: the area, severity, pattern, the red-flag answers and the outcome) and
  the joint states and swaps computed from them;
- nutrition logs, meal photos, allergies, and dietary constraints;
- body measurements, progress photos, and physique analyses;
- goals, limitations, plan decisions, and coaching history;
- the account's optional country (`user_accounts.country_code`; set only through
  `set_my_country_v1`, exported and deleted with the account; it picks the regional library sources
  inside the database and is not sent to an AI provider, which receives only the chunks chosen);
- authentication tokens and encrypted contact information; and
- account exports.

Restricted data requires authenticated, user-scoped access, encryption in transit and at rest,
purpose limitation, retention control, and audit coverage.

### Confidential operational

- prompts, schemas, evaluation fixtures, feature definitions, provider configuration;
- provider request IDs, usage, cost, and validation results; and
- security and operational audit metadata.

### Public

- approved product copy, privacy notice, terms, nonsensitive exercise catalog content, and public
  support information; and
- research library sources and chunks (`private.library_*`, D3): open papers, guidelines, position
  stands and in-house summaries in our own words, with their embeddings. Paid course material is
  never stored. The library holds no user data, so it is outside export and account deletion. It
  still sits in the `private` schema with forced RLS and no API grants, and only the service-role
  search functions (`search_library_v3`, and `search_library_v2` until the deployed build moves to
  v3) read it. A Coach answer records only the library version it was shown
  (`coach_messages.library_version`, 16 hex characters, no content). library-embed remembers the last
  accepted worker secret by its SHA-256 for 5 minutes per isolate, never a refused one.

Classification is inherited by derived data. A summary of health data remains restricted. A Coach
question used as a library search query (or its `gte-small` embedding, computed by the
`library-embed` Edge Function, which Coach chat calls with the worker secret and the question only) keeps the question's classification: it is used for that request only and is never
written to the library or logged. Coach chat searches with it on every turn (E3); the query may
carry the athlete's previous question's topic, built in the function and not stored. The search
reads the athlete's chosen country (or, with none, the account locale and time zone) to pick
regional sources (inside the security definer function; nothing leaves the database), and the chunks it returns go to the AI provider
the athlete's notice names, like the rest of the Coach context.

## 3. Consent and Transparency

Consent choices are separate and versioned for:

- private-beta terms and privacy notice (`terms`, `privacy`), each versioned by its hosted page's
  "Last updated" date (`LegalNotices` in the app); an onboarded athlete whose grant is older is
  asked again at launch before the app opens, and a failed lookup never locks them out;
- explicit consent to processing health data: Apple Health data, check-ins, pain reports, body
  measurements and photos (`health_data`, its own unticked onboarding row, versioned with the
  privacy notice), as GDPR Art. 9(2)(a) and India's SPDI Rules 2011 Rule 5 expect;
- AI coaching: sending the athlete's Tracend data to the AI provider for Coach chat answers, daily
  decisions and the onboarding plan (`ai_coaching`; a decline is stored as `withdrawn`, and a grant
  of an older notice version is asked again);
- HealthKit read/sync by requested data type;
- meal-photo storage and AI analysis (`meal_photo_ai`);
- progress-photo storage and progress-photo AI analysis as separate choices
  (`progress_photo_storage`, `progress_photo_ai`);
- notifications; and
- optional future research or product-improvement use, which is off by default and outside MVP.

Requirements:

- Purpose text is specific, plain-language, and shown in context.
- Denying an optional permission preserves unaffected features.
- Withdrawal stops new processing immediately and initiates purpose-specific deletion where
  required.
- Consent records store notice version, choice, source, and time. **Account › Consent history**
  shows each purpose's current choice with its date first and the notice version as secondary
  text; records made during owner testing read "Set up during testing".
- HealthKit permission state is not inferred from an empty query result.
- Provider names or categories, data sent, purpose, and relevant retention behavior are disclosed
  before AI photo processing.
- No model name appears anywhere the athlete or the public reads: the app, notices, the website
  and the privacy policy (D11). The receiving company is named only where disclosure is needed:
  one line in each AI consent notice and the privacy policy's processor list.

AI consent is enforced on the server, per purpose:

- **Notices are server data.** `ai_consent_notices` holds the Coach chat, daily decision and
  onboarding plan notices, and `ai_notice_current` names the current one for each purpose. Meal
  photos (`meal_photo_ai_notices`) and the physique check (`photo_ai_notices`) have their own
  notices. Notices are never edited.
- **A grant counts only for a current notice.** It counts for a purpose only while it names that
  purpose's current notice, so publishing a new notice (for example after a provider change) asks
  every athlete again.
- **Each feature checks before sending.** `coach-chat` refuses and `coach-decide` falls back to
  the deterministic decision without a current grant (`has_ai_coaching_consent`, service role
  only). `onboarding-plan` uses the rules plan, `meal-analyze` checks the meal photo grant before
  any download, and `physique-check` checks the photo grant before any download.
- **Notices name a vendor.** A notice records the company that receives the data (`anthropic`,
  `deepseek`, `groq` or `gemini`), and its publisher refuses a label that names a different
  company. The AI gateway compares that vendor with its route (`get_ai_consent_v2`) and sends
  nothing on a mismatch, so a grant for one company never covers another.

> **D11 status.** The app wording is done (A7): screens say "AI" and name no model or company
> outside a consent notice. The notice bodies are rows the owner publishes: the drafts that name
> Anthropic once and no model are in [`docs/notices/`](./notices/) (`ai-coaching-v6`,
> `meal-photo-ai-v2`, `progress-photo-ai-v2`). Until they are published, the current notices still
> name DeepSeek, Groq and a model. This is a beta exit criterion.

## 4. HealthKit

- Request only steps, active energy, sleep, workouts, weight, resting heart rate, HRV and
  breathing rate needed for enabled coaching, and heart rate during workouts (per-set summaries,
  below).
- Request access near the relevant feature rather than at unexplained launch time. Onboarding may
  ask for Apple Health access as an optional step; skipping it never blocks a plan.
- Provide accurate iOS purpose strings for every read/write capability; MVP is read-oriented unless
  a documented requirement adds writing.
- Normalize and upload required summaries; do not copy every raw sample by default.
- Workout-level sync keeps only type, time, duration, optional energy, and hashed source and sample
  references needed for reconciliation. It does not copy routes, heart-rate series, or unrelated
  raw samples.
- The onboarding plan receives only a 28-day summary (average steps, active energy and sleep,
  workouts found, latest weight and trend), never raw samples, heart rate, HRV or breathing rate.
- After Apple Health connects, the app reads workouts, sleep and weight for the 11 completed months
  before this one and sends only monthly totals with their coverage (`save_health_history`, table
  `health_history_months`, owner-read RLS; refreshed at most once a month). No sample, heart rate,
  HRV, breathing rate or step history is sent. The plan uses them to compare the athlete's usual
  months with the last 28 days.
- Preserve source and freshness needed to explain data quality and prevent duplicates.
- Never write false or model-invented values to HealthKit.
- HealthKit auto-completion is a user-initiated action: the app presents detected workout evidence,
  the user explicitly confirms, and the completed session is written with an audit trail. No
  background service-role or automated mutation occurs without the user's tap.
- Never store personal health information in iCloud containers.
- Never use HealthKit-derived data for advertising, marketing profiles, or sale.
- A disconnected or partially authorized user can continue through manual logging.

- **Per-set heart rate (C2, Contract 4).** After the athlete finishes a workout, the app asks Apple
  Health for read access to heart rate (the sheet shows only while the choice is undecided; the
  purpose string names workout and overnight (sleeping) heart-rate data) and reads the Apple Watch's heart-rate samples for
  the minutes around the sets, through a HealthKit anchored query on the phone. It works out one
  summary per set from the set's stored start and end plus the following 60 seconds (start, peak and
  end beats per minute, the drop 30 and 60 seconds after the end, coverage, sample count, and
  `watch_workout` or `background` as the source) and sends only that summary with
  `persist_set_heart_rate_v1`, stored in `exercise_set_heart_rate` (owner-read RLS, writes only
  through the RPC, exported by `privacy-export`, deleted with the account). Raw samples, sample
  times and Watch device details never leave the phone and are never logged; Sentry breadcrumbs
  carry only the number of sets saved. A waiting list of finished workouts (session id and set
  times, no heart-rate values) is kept in the phone's preferences for up to two days so the read
  can run after the Watch has synced. Heart rate never sets a load or a prescription (D9). The Coach
  reads these summaries only through the heart-rate profile contributor described next, once it is registered.

- **Heart-rate profile and sleeping heart rate (C3, D9, D10).** The profile (resting heart rate,
  an estimated maximum, heart-rate zones and recovery after sets) is computed from values the app
  already stores: the resting heart rate Apple Health sync sends (no new metric), the birth year in
  the profile, and the per-set summaries above. It is not stored; it is worked out on demand by
  deterministic code from `get_my_heart_rate_inputs_v1` (own data) and, for the Coach's contributor
  (not registered until E3), `get_heart_rate_inputs_v1` (service role only). Sleeping heart rate is
  new: after an Apple Health sync the phone reads the heart-rate samples taken asleep for the last
  7 nights (the sleep samples the sync already read give the nights; the same heart-rate read access
  is used and the Health sheet asks for it only when the athlete taps Connect or Refresh) and sends
  one summary per night with `persist_sleeping_heart_rate_v1`: the median, the lowest 10-minute mean (slots with at least 2 readings),
  the number of readings, the minutes asleep and the share of the night covered. The save is bound to the athlete signed in when the sync
  began: if another account signs in during the reads, nothing is sent. Raw samples and
  their times never leave the phone and are never logged; the Sentry breadcrumb carries only the
  number of nights saved. The rows live in `sleeping_heart_rate_nights` (owner-read RLS, writes only
  through the RPC, exported by `privacy-export`, deleted with the account). **They are in shadow
  mode (D10): no recovery score, readiness line, baseline, brief or Coach context reads them**, and
  a pgTAP test proves the recovery score does not move when nights are stored. Using them in a
  score is a later reviewed change that must update this section. The heart-rate profile informs
  rest, cardio and recovery talk; it never sets a load or a prescription (D9).

- **Watch-workout suggestion and load signals (C4, D9).** No new metric is collected and no table is
  added. `get_my_watch_workout_status_v1` (own data) returns, for the last three finished workouts,
  how many sets were finished and how many had Watch heart rate; the app uses it to decide whether to
  suggest starting a Watch workout, and keeps the athlete's answer ("Not now", "I don't use a Watch") in
  the phone's preferences only. `get_workout_load_inputs_v1` (service role only; revoked from `anon`
  and `authenticated`, pgTAP-checked) gives the training engine the finished workouts of the last 28
  days with the rest and the per-set heart-rate summary of each tracked set: no load, repetitions,
  reps in reserve, effort, notes or raw samples. The load signals worked out from it are not stored
  and read by the Coach's plan context only as fixed sentences with no figure (a step "less certain",
  "rest a little longer"); no heart-rate value, set summary or signal number reaches the AI provider, only
  the conclusion in fixed words. That conclusion is derived from the same heart-rate summaries the
  registered `heart_rate_profile` contributor already sends, so it adds no data category. They lower confidence and suggest a longer rest; they never set a load or a prescription (D9).

## 5. Photos and Media

### Storage

- Use separate private Supabase Storage buckets for meal images, progress photos, and temporary
  exports; public buckets are prohibited for restricted data.
- Enable operation-specific Storage RLS policies scoped to `auth.uid()`, bucket, owner, and purpose.
- Separate meal and progress-photo paths, permissions, processing, and retention policies.
- Encrypt at rest with managed keys; use TLS for transfer.
- Permit authenticated uploads only under the user's purpose-bound path with bucket limits for size
  and content type.
- Issue short-lived signed reads only after authenticated authorization; never create permanent
  public URLs.
- Validate magic bytes, size, dimensions, checksum, and supported image type after upload.
- Strip unnecessary EXIF, location, and device metadata before long-term storage or provider
  transfer.
- Use opaque object identifiers; never expose storage keys as authorization.
- A media row records only the exact key the app uploaded: `<uid>/meal/<request id>.<ext>` (bound
  to the meal's idempotency key) or `<uid>/progress/<set id>/<pose>.<ext>`, and the RPC that
  records it requires an uploaded object the caller owns (`private.is_owned_media_key`). Stored keys
  stay inside their owner's folder with no `.`/`..` segment, `//`, `\`, `%` or control character
  (`media_objects_object_key_safe`).
- Service-role code ignores Storage RLS, so every key it reads from the database passes
  `_shared/storage_keys.ts` (a safe key in the user's own folder) before any download or removal.
  A key that fails is never sent to Storage: meal analysis answers `meal_not_found`, the export
  lists it under `skipped_media`, and retention leaves it and reports a count to Sentry. Account
  deletion stops before deleting anything and fails the request (Sentry
  `account_deletion_unsafe_keys_<n>`), so it never reports success while a private object remains;
  the owner removes that object in the dashboard and the athlete retries.

### Access

- Only the owning user under Storage RLS and narrowly authorized Edge Function/Queue jobs can access
  media.
- Progress photos never appear in notifications, analytics tools, support dashboards, or general
  logs.
- Administrative access is disabled by default; exceptional access requires explicit purpose, least
  privilege, time limitation, and audit.
- Provider access uses bytes or short-lived references restricted to the selected task.

### Purpose limits

- Meal images are used only to propose foods/portions and are deleted after confirmation plus the
  documented short correction window, unless the user explicitly saves the image.
- Meal-photo requests use private Storage bytes only after explicit photo consent (the
  `meal_photo_ai` grant of the current meal photo notice, checked by `meal-analyze` before any
  download). The provider receives a minimized image and fixed instruction with no identity, object
  key, or unrelated history. Visible text in an image is untrusted input. Analysis candidates are
  unconfirmed restricted data and follow meal-media retention even when the provider or validation
  fails.
- Progress images are retained while the account and relevant consent remain active or until the
  user deletes a set.
- Progress-photo viewing uses owner-authorized signed URLs that expire after 60 seconds. Set
  deletion removes Storage bytes before relational metadata; a failed byte deletion leaves the set
  visible for safe retry.
- Progress photos are included only in user-requested comparison jobs, never routine text coaching.
- A physique check (owner-only experiment, AI_SAFETY_SPEC §9) sends the front, side and back photos
  of one set to the physique provider only when the athlete starts it (Groq today; Anthropic after
  the cutover), under its own notice and consent (`progress_photo_ai`), with metadata stripped on
  the server. Groq's Zero Data Retention is on for the Groq route; Anthropic's standard commercial
  terms (deleted within 30 days, not used for training) apply to the Claude route and are stated in
  the notice.
  Results (`physique_analyses`) are owner-read, exported, and deleted with their set (analyses go
  first, `delete_my_progress_photo_set`) or the account.
- Face recognition, identity matching, sensitive-trait inference, and unrelated reuse are
  prohibited.

## 6. AI Provider Processing

- AI requests originate only from Supabase Edge Functions; provider keys and Supabase
  secret/service-role keys never enter Flutter.
- Each route is server-only, purpose-bound and kill-switchable by its server settings
  (ARCHITECTURE §3.7). Progress-photo processing is limited to the owner-only physique check
  (`PHYSIQUE_VISION_ALLOWED_USERS`) pending separate evaluation.
- Flutter never presents a provider-key entry field or transmits a provider credential supplied by a
  user. The owner configures provider credentials in environment-specific Supabase secret
  management.
- Send the minimum feature snapshot or selected image required for the task.
- Remove direct identifiers, email, tokens, storage keys, and unrelated history.
- Maintain a provider inventory covering purpose, data types, regions, retention, training-use
  controls, subprocessors, security posture, and deletion capabilities.
- Configure available no-training and retention controls before production use.
- Do not opt restricted user data into provider model improvement.
- Do not use a new provider until privacy review and the evaluation requirements in
  [AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md) pass. New providers require privacy review and
  evaluation parity before use with restricted data.
- Do not send restricted Tracend data through unpaid Gemini API service. Current unpaid-service
  terms permit product-improvement use and human review and instruct developers not to submit
  sensitive or personal information.
- Provider failure or policy change must degrade safely without changing the approved plan.
- Provider-side persistent conversation state is disabled unless documented, consented, deletable,
  and required.

Current AI processors (internal names; athlete-facing text follows D11):

| Company | Features | Basis |
| --- | --- | --- |
| DeepSeek | Coach chat and daily decision (DeepSeek V4.1 Flash), onboarding plan and follow-up questions | ADR 0011, `ai_coaching` notice |
| Groq | Meal-photo candidates and the owner-only physique check (`qwen/qwen3.8-27b`) | ADR 0006, meal photo and photo notices |
| Anthropic | None until the cutover; the gateway routes and SQL accept it. Planned: Coach chat and meal photos (Haiku 5.5), daily decision and physique check (Sonnet 5.5), onboarding later | Plan D1, Contract 1 v2; notices `ai-coaching-v6`, `meal-photo-ai-v2`, `progress-photo-ai-v2` (drafts) |

Anthropic's standard commercial terms (checked 2026-10-16, privacy.claude.com): inputs and outputs
are deleted within 30 days and are not used for model training; they may be kept longer where the
law requires or to enforce Anthropic's usage rules (up to 2 years if its safety systems flag an
input). No Zero Data Retention agreement is arranged. Re-read the policy when the notices are
published and when the processor list changes.

Gemini remains coded but gated by `GEMINI_PAID_DATA_TERMS_ACCEPTED`; it is not in use. The
website's privacy policy lists Anthropic, DeepSeek and Groq as AI processors.

> **Cutover (Phase 2, D1), not yet done:** every feature moves to Anthropic before the external
> TestFlight group opens, following
> [`docs/runbooks/phase2-claude-cutover.md`](./runbooks/phase2-claude-cutover.md). Health data
> must not go to DeepSeek once external testers join (beta exit criterion, plan decisions log,
> 2026-10-15). Once the Anthropic coaching notice is current, DeepSeek receives nothing: onboarding,
> which has no Claude route until after chunk B2, uses the rules plan (no AI) until then. The
> DeepSeek and Groq routes stay as a settings-only rollback for two weeks; after that window the
> owner removes them from the privacy policy's processor list (runbook, "After the window").

## 7. Authentication and Authorization

- Use native Sign in with Apple through Supabase Auth with a cryptographically secure nonce.
  **Not built yet:** owner-only builds sign in with the ADR 0002 email/password development mode.
- Supabase Auth validates the Apple identity exchange and manages JWT access/refresh sessions;
  Tracend must not issue a parallel token system.
- Store Supabase sessions only through platform-protected storage supported by `supabase_flutter`;
  never general preferences or logs. The session lives in the iOS Keychain
  (`KeychainSessionStorage`, `first_unlock_this_device`, never synced or backed up). A build that
  finds a session in preferences moves it, checks it reads back, then deletes the old copy; a fresh
  install clears anything a deleted install left in the Keychain.
- Capture an Apple-provided name only on first authorization when present; do not require or infer a
  legal name.
- Store secrets in environment-specific secret management, never source control, mobile bundles,
  logs, or documentation examples containing real values.
- The Supabase project URL and publishable key may ship in Flutter; they are identifiers, not
  authorization. Secret/service-role keys remain in Edge Function secrets and trusted administration
  only.
- Derive `user_id` from `auth.uid()`; ignore or reject ownership identifiers supplied for
  authorization.
- Enable RLS on every exposed user-owned table and private Storage bucket before client access.
- Enforce ownership again in transactional RPC and privileged Edge Functions.
- Use generic not-found/forbidden behavior that does not reveal another user's resource existence.
- Rate-limit authentication, Edge Functions, media operations, AI jobs, export, and deletion.
  Database caps (SQLSTATE 54000, `private.enforce_user_row_limit`): 100 consent records a day, 200
  goals, 50 Coach conversations a day and 1,000 in all, 10 progress photo sets a day, and 120 health
  syncs an hour. Uploads (restrictive policy `user_media_upload_quota`): 100 meal photos a day and
  3,000 kept; 60 progress photos a day and 2,000 kept. Onboarding drafts are capped at 128 KB and
  goal details at 16 KB. The meal-media-retention worker removes Storage objects that have no
  database row after a day (exports after an hour).
- Clients write only the columns they need: consent records take `user_id`, `consent_type`,
  `notice_version`, `action` and `source` (never `created_at`); the account time zone changes only
  through `set_my_timezone`; and the onboarding profile fields (sex, birth year, daily activity,
  equipment, limitations and diet notes) are written only by plan approval, with client column
  grants for the step-0 fields alone.
- Require recent authentication for export, account deletion, or sensitive session changes.
  "Recent" is read from the JWT `amr` claim (`private.has_recent_sign_in`): a password, OTP or TOTP
  sign-in within 10 minutes. `iat` is not used, because a token refresh resets it while `amr`
  keeps the time of the sign-in that started the session.
- Sign-ups are invite-only during the beta. `private.handle_new_auth_user` refuses an email that is
  not in `private.signup_invites` (reachable only from the SQL editor), so the Auth insert rolls
  back and no account or email is created. Production Auth sign-ups are also switched off in the
  dashboard. Invite with
  `insert into private.signup_invites(email, note) values (lower('<email>'), 'beta');` or move
  confirmed waitlist signups with `private.invite_from_waitlist(n)`.
- Deleting an account removes its email from the invite list and the waitlist. The
  `auth_user_forget_invite` trigger runs in the same transaction as the Auth delete
  (`privacy-delete-account`'s `auth.admin.deleteUser`, or the dashboard) and deletes the invite the
  account claimed, an unclaimed invite for its current email, and the waitlist signups for both
  emails. If it fails, the account stays and the deletion can be retried. A signup the person
  referred keeps its row without the link to them. Coming back takes a new waitlist signup and a
  new invite. `private.forget_deleted_account_invites` clears rows left by earlier deletions; the
  owner can rerun it from the SQL editor.
- The website waitlist functions take no session. `waitlist-join` requires a Cloudflare Turnstile
  token (checked server-side with `TURNSTILE_SECRET_KEY`), refuses common throwaway domains, and
  the database allows 5 joins an hour per hashed IP. New and existing addresses get the same
  answer. Confirm and unsubscribe links carry a 256-bit token in the URL fragment (never sent to a
  server or kept in history); only its SHA-256 hash is stored. Responses allow only the site's
  origin (`WAITLIST_SITE_URL`). A waitlist signup grants no app access.
- `meal-media-retention` validates a dedicated `RETENTION_WORKER_SECRET` (not JWT). Store the same
  generated value in Edge Function secrets and Supabase Vault; Cron reads Vault. Never place it in
  Flutter, shell history, logs, or committed files.
  The worker compares the bearer value in constant time. It runs its stages (meal photos, expired
  exports, orphan sweep, deletion receipts) one by one, so a failing stage does not stop the next;
  one row whose result cannot be written back does not strand the rest of its batch; and a photo
  claimed by a worker that stopped before finishing (`pending_deletion` for 30 minutes) is handed out
  again (photos pending at the migration count as claimed then). Failures reach Sentry as codes and
  counts only, never a key, path, URL or user id. The daily job `meal-media-retention-daily` (02:15
  UTC) is created by migration and calls `private.meal_media_retention_kick()`, which posts only when
  Vault holds both `meal_media_retention_url` (set by the deploy and hotfix workflows after the migrations; the step fails when
  `retention_worker_secret` is missing from Vault, so a deploy cannot leave the job doing nothing) and
  `retention_worker_secret` (set by the owner, the same value as the Edge secret); a local, CI or
  restored database sends nothing.
- `library-embed` (research library embeddings) validates a bearer secret that the database
  generates itself in Vault (`library_worker_secret`, created by `private.library_worker_secret()`);
  there is no Edge Function secret. The cron job is inert until the deploy workflow stores the
  function's URL in the Vault secret `library_embed_url` after the migrations (it runs
  `select private.library_set_embed_url('https://<project ref>.supabase.co/functions/v1/library-embed')`,
  a function executable by `service_role` only that accepts nothing but that URL shape), so a local
  or CI database never posts anywhere, least of all to production. Once set, the cron job reads Vault
  and calls the function through `pg_net`; the function checks the bearer through the service-role
  `library_worker_authorized_v1` and never accepts a user session. It reads only library chunks and
  holds no user data. Its optional `{"texts": [...]}` mode (at most 8 short texts, same secret)
  exists for the retrieval evaluation.

## 8. Encryption and Secret Management

- TLS is mandatory for app, Supabase APIs/Functions, Storage, database, and provider traffic.
- Supabase PostgreSQL, Storage, supported backups, and export packages are encrypted at rest.
- Highly sensitive optional fields may use application-level envelope encryption.
- Keys and provider credentials are separated between local development and every hosted Supabase
  project; staging receives independent keys if later created.
- Rotate credentials after exposure, staff change, or scheduled policy interval.
- Never place secrets or production data in test fixtures.

## 9. Multi-User Isolation

- RLS is the mandatory default-deny authorization boundary for every exposed user-owned table and
  private Storage bucket.
- Policies use `auth.uid()`, explicit operation roles, and ownership predicates; anonymous access to
  restricted data is denied.
- Cross-table foreign-key ownership is validated in constraints or transactional functions.
- Storage paths and policies are user/purpose bound.
- Edge Functions validate the JWT and requested resource even when using secret/service-role access.
- An RPC granted to `authenticated` that takes a target user id refuses any id but the caller's
  unless the caller is the service role. None remains: `persist_coach_preference` is service role
  only since 2026-10-31.
- The first-generation onboarding approval and the fixture-meal functions are closed to the app
  roles, and `user_accounts.onboarding_state` cannot be written by the signed-in role: approval
  sets `completed` inside `respond_to_onboarding_proposal_v2` (which enforces the health check) and
  the database moves `not_started` to `in_progress` with the first draft.
- Tables in the `private` schema (invites, waitlist, AI budget limits, research library) are not
  exposed by the Data API and have no client grants.
- Queue messages carry opaque resource IDs and workers reauthorize ownership and consent at
  execution.
- Weekly-review messages contain only schema version and an opaque job ID. The worker rechecks
  active-account eligibility, reads structured user evidence inside PostgreSQL, and never places
  notes, health values, prompts, or model inputs in the queue.
- Caches include user scope and never serve restricted shared-cache responses.
- Automated tests attempt anonymous, horizontal, vertical, RPC, Storage, and secret-key privilege
  escalation for every resource family.

## 10. Logging, Analytics, and Observability

Allowed telemetry includes correlation ID, Edge Function/RPC name, status, duration,
feature/policy/prompt versions, provider/model, usage, cost estimate, validation state, Queue/Cron
state, and sanitized error code.

General logs and third-party analytics must not contain:

- health values, meal descriptions, measurements, check-in notes, prompts, or model prose;
- photos, signed URLs, object keys, export links, or filenames revealing content;
- Apple identity tokens, access/refresh tokens, API keys, email, or exact date of birth; or
- unrestricted request/response bodies.

Mobile analytics are minimized and disabled for sensitive-screen content. Crash reporting scrubs
navigation parameters, text fields, and network bodies. Sentry is active in Flutter and Edge
Functions. The app scrubs events with `beforeSend` (health values, meal content, photo URLs, prompts).
The Edge Function reporter (`_shared/sentry.ts`) fails closed instead: an event carries finite codes
and numbers only. The exception value is the call site's failure code (every `captureException` must
pass one; the class name stands in when it is not a short code), the type is the error's class name,
and `error.message`, causes, provider response bodies, parse errors quoting model text and stack
source text are never sent. Tags and extra fields are short codes (letters, digits, `_ . : / -`, no
spaces) or numbers (HTTP status, latency, counts). The stack keeps function, file and line of at
most 30 frames: the header (the message, even over several lines) is cut off first, a function name
has no spaces except a leading `async ` or `new `, and a frame whose file is not a URL of a loaded
module (`file:`, `ext:`, `https:`, `node:`, `jsr:`, `npm:`) is dropped; if the header cannot be
located no frame is sent. A provider failure keeps its short code and HTTP status (for example
`meal_vision_request_failed:503:overloaded`) only when the text is a code. Reporting never throws. A report may carry the account ID and device and app details, never name or email.
In Flutter (`lib/app/sentry_scrubber.dart`) the scrubber also covers exception values, `extra`,
contexts and breadcrumbs; the app's prints are not breadcrumbs (`enablePrintBreadcrumbs` is off);
a `beforeBreadcrumb` drops console crumbs and cuts HTTP crumbs to method, status and address
with the URL reduced to its origin and a route template (ids, numbers, filenames and everything
after `/object/` are placeholders); an exception value is reduced to its type and code
(`network` for a lost connection), never forwarded as text; an event that cannot be scrubbed is dropped. The app logs a handled failure
with `logNonCritical` (type and code only, never `$e`: a Postgres error carries the failing row),
and `reportNonCritical` sends such a failure to Sentry by type and code. A test forbids
interpolating an exception into `debugPrint`.

Audit events record access and changes using opaque IDs and action codes, not copies of sensitive
content.
`day_adjustment_answered` carries the kind, whether it was accepted, the band, the origin and the rules
version only; the check-in, sleep and recovery values stay in the Restricted `day_adjustments` row.
`pain_check_recorded` carries the source, the area and the outcome only: never the severity, the
pattern or a red-flag answer. Neither widgets nor the Live Activity show a readiness adjustment,
a pain check or a joint state. Logs and Sentry carry codes and counts, never a pain severity, area
or red-flag answer; the Edge Functions and the database write none of them to a log, and the app's
`beforeSend` and `beforeBreadcrumb` scrubber drops the `pain_*` and `joint_*` keys, the red-flag codes, areas,
severities and routes from events and breadcrumbs (built in B5-2, tested in `test/sentry_scrubber_test.dart`). On
the phone a pain report that cannot be sent waits per athlete in local storage (kept apart from other athletes and removed with the
other local data when the account is deleted) and is sent again for at most a day, because the server records a pain report
only for today or yesterday; the referral acknowledgements are kept per athlete the same way.
The Coach context view `get_readiness_context_v1` returns band, kind, status, route and each joint's
area, state and lasting flag only (service role); the red-flag codes behind a route and the
severity are not in it.

Local reminders are scheduled by iOS and use only the generic title `Tracend reminder` and body
`Open Tracend when convenient.` Lock-screen content never names health, nutrition, workouts,
photos, measurements, or coaching decisions, with two exceptions below (the workout Live Activity, and
the Lock Screen widgets, which show nothing until the athlete turns them on).
The server stores toggles and coarse permission state, not delivery history or notification
content. iOS stores only the local boolean choices and repairs missing pending requests after
reopen; no notification payload or delivery history is added to local preference storage.

The workout rest alert is a third local notification type with the fixed identifier
`tracend.rest-timer` and the title `Rest timer finished` only: no workout, exercise, load, or
effort is ever in it. It is off until the athlete turns on "Rest timer alerts", a device-only
choice kept in `UserDefaults` next to the two reminder toggles (the server stores no copy). It is
scheduled only while that toggle is on and iOS allows alerts; scheduling again replaces the one
alert, and skip, finish, discard, leaving the workout, turning the toggle off, and a rest that
ended while the app was closed all cancel it. Reminder reconciliation removes only the daily and
weekly identifiers and never removes all pending requests, so it cannot drop a running rest alert.
The toggle in **Account › Notifications** names the lock-screen text ("Rest timer finished") in
its row, and when iOS has not been asked yet, turning it on first shows that text in a confirm;
only **Continue** leads to the iOS permission request. Off, **Not now** or a denied permission
keeps the rest timer in the app only.

**Exception: the workout Live Activity (owner decision, 2026-10-15; extended from the rest to the set
in progress by the owner's set-logging request of 2026-10-23, owner to confirm the wording).** While a workout is open, the Lock Screen and Dynamic Island Live Activity may show
the exercise name and the set's position ("Set 2 of 4") with a **Log set** button; during a rest it
shows the countdown, the exercise name and the next-set label (for example "Bench press · Next: Set 3
of Bench press"). Nothing else from the workout appears in it: never effort, reps left, heart rate or
any health value, and never the workout's name.

- **The set's kg and reps are the athlete's choice and start off.** The target the logger pre-fills for
  the set ("82.5 kg × 8") is on the card only while **Account › Widgets › Health numbers on the Lock
  Screen** (D2's setting below, per athlete, device-only) is on. Off, the numbers never leave the app:
  the card carries the exercise, the set's position and nothing else, and **Log set** still logs
  exactly what the logger pre-fills. Turning the choice off removes the numbers from a card that is
  showing at once (`hideNumbers` on the channel). Anyone holding a locked phone can read what the
  card shows; the Account row says so.
- **Local only.** ActivityKit started by the app; no push, the Live Activity itself uses no App Group,
  and nothing is sent to the server or to Apple's push service. The athlete removes it with iOS
  **Settings › Tracend › Live Activities**.
- **Lifetime.** It appears when the workout opens (or a set is logged) and stays through the whole
  workout, however long a set takes: when a rest ends the card turns into the next set by itself
  (the system re-draws it at the rest's end), and the next logged set starts the next rest in place.
  Finishing, discarding and leaving the workout (Save and leave) remove it at once. After the last
  set it says "All sets logged" with **Open**, for two minutes. ActivityKit has no timer of its own
  and no push is used, so only app code can dismiss it: with the app away it stays until the app
  next runs, and a launch or a button press removes a card that is over (the all-sets-logged card two
  minutes after it appeared, or any card the app has not moved for four hours, since a workout lasts
  three at most); failing all of those, iOS ends it at its own limit (8 hours after it started). It
  carries nothing beyond the exercise name, the labels, the set's position (exercise order, set number
  and how many sets), whether the app can log the set, and the target while numbers are on. Sign-out,
  account deletion and a session Auth refused end it, and the next launch ends any card that is over.
- **Buttons act through the workout.** **Log set**, Skip and +30s run in the app's process (iOS 17
  App Intents) and go to the open workout screen's command sink: logging is the in-app "Done set"
  code, with the same draft, sync, set-timing, heart-rate and audit paths. **Open** and a tap on the
  card open `tracend://workout`, which only brings the workout in progress forward (no data in the
  link; with no workout started it opens nothing).

**Exception: Today and Lock Screen widgets (chunk D2; owner approved 2026-10-18).** This is the second
exception to the rule above, made because the D2 brief asks for Lock Screen widgets, and bounded by an
off-by-default choice. The
`TracendWidgets` extension draws Home Screen and Lock Screen widgets from a snapshot the app writes
to the app group `group.com.tracend.app` as one file (`today_widget_snapshot.json` in the group's
container) each time Today loads. The app group is how the widget process reads it. The file is
excluded from iCloud and Finder backups (`isExcludedFromBackup`: set on a temporary file that is then
renamed into place, so the snapshot's path never holds a file without it; a write that cannot be
excluded is removed and reported as failed) and protected until first unlock
(the Lock Screen widgets read it while the phone is locked), so the snapshot never leaves the
phone; the widgets never call the network and hold no token.

- **What it holds.** The brief's local date; the session's state, plan name and set counts; up to
  three plan exercises with their targets ("4 × 6–8 · 82.5 kg"); the recovery score; calories and
  protein eaten and their plan targets; whether the check-in is done; and a time stamp with a
  12-hour stale limit. No free text: no check-in or meal notes, meal names, coach wording, decisions,
  photos, measurements, heart-rate, sleep or weight values. The plan's own names are shown as the
  plan has them.
- **Lock Screen numbers are the athlete's choice and start off** (**Account › Widgets › Health
  numbers on the Lock Screen**, a device-only setting in app preferences, kept per athlete; the server
  stores no copy). Sign-out, account deletion and a session Auth refused forget it, and another
  athlete on the same phone never reads it, so each starts with numbers off.
  While off, the snapshot has no `lock` section at all, so the Lock Screen widgets read nothing but
  show "Tracend" and "Lock Screen numbers are off". On adds the recovery score, the session name
  and protein, which anyone holding the locked phone can read; the row and its footnote say so.
  Turning it off rewrites the snapshot at once; with no Today loaded to rebuild from, or when the
  rewrite fails, it removes the snapshot instead (twice if the first removal fails), so the
  opt-out never leaves Lock Screen numbers readable.
- **Home Screen widgets** show the full snapshot (session, recovery, exercises, calories, protein,
  check-in) once the phone is unlocked, and are marked `privacySensitive` so iOS redacts them where
  it hides sensitive content on a locked phone (StandBy). Removing the widget removes the exposure.
- **Lifetime.** The snapshot is removed on sign-out, account deletion, a session Auth refused and
  when the app's screens go away, on every signed-out transition whichever screen ended the
  session (a deletion that settles after its sheet was closed included); widgets then read "Open Tracend to refresh". Deleting the
  account also removes the Lock Screen choice from the phone. Coming back to the app after half an
  hour, or on a new local day, reloads Today and writes a new snapshot; an old one is never
  written again. It is also treated as
  stale after 12 hours or on another day: no number is drawn from it. A removal the system refuses
  empties the file instead (an empty file is no snapshot) and is tried twice. A clear that fails
  both times is remembered on the phone and tried again on every launch and resume, until it works
  or a new snapshot is written over the old file. An opt-out is always saved as Off, so no snapshot
  written later has numbers; if the numbers already in the file could not be removed, the switch
  still reads Off, a message says the app is retrying, and the retry removes them (the widgets
  then get a fresh snapshot without numbers). Leftover temporary files of an interrupted write are
  deleted on every write and clear.
- **Deep links.** `tracend://today` and `tracend://train` only switch tab; the native side accepts
  nothing else, and Flutter's own deep-link routing is off (`FlutterDeepLinkingEnabled` = NO). A
  request waits a minute for the app and then expires.
- **Telemetry.** Sentry breadcrumbs (`home_widgets`) carry the method name only, never the
  snapshot.

## 11. Retention

Initial private-beta defaults:

- account/profile/plans/logs/measurements/decisions: retained until user deletion or explicit record
  deletion where supported; same-day readiness answers are retained like check-ins;
- confirmed meal records: retained until user deletion; source meal image deleted after 30 days
  unless explicitly saved (in practice the upload sets a 7-day deadline and confirmation never
  extends it, so images go about 7 days after upload);
- discarded or failed meal images: deleted within 7 days;
- progress photos: retained until photo-set or account deletion, consent withdrawal requiring
  deletion, or beta shutdown;
- temporary signed URLs: minutes, never permanent;
- export packages: deleted within 7 days or after the configured download limit;
- refresh sessions: deleted or tombstoned after expiry/revocation according to security policy;
- application logs: 30 days by default;
- sanitized security audit metadata: 180 days by default;
- Coach threads/messages: retained until the owner deletes the thread, deletes the account, or the
  private beta shuts down; provider-side conversation state remains disabled;
- invite-list and waitlist rows: until account deletion (both removed with the account), a request
  to the owner, or for an unconfirmed waitlist signup, 30 days after its last email;
- Free Plan database: encrypted off-site logical export at least weekly during active beta and
  before migrations; Supabase does not provide the Pro daily-backup guarantee;
- Pro Plan database: Supabase daily backups with the plan's current seven-day availability, plus an
  independent pre-release logical export where permitted;
- Storage objects: separate encrypted inventory/export procedure because database backups contain
  metadata but not Storage bytes; and
- provider content: shortest available approved retention, documented per provider.

Every production deploy takes an AES-256 encrypted logical backup before migrating, restores it in
a drill that also compares privileges, and stores it in a private repository that keeps the newest
30 (CI_CD_DEPLOYMENT.md). A deleted account's data leaves the backups as newer ones replace them.

Retention jobs are idempotent, observable, and tested. Changing a default requires updating this
document, user notice where applicable, and implementation tests.

Owner-supplied historical context used for an administrative import remains in ignored,
permission-restricted `.tooling/private-imports/` files on the external SSD. Raw reports and import
payloads are never committed or copied into handoff, progress, audit, or application logs.

## 12. User Rights and Controls

### Access and correction

Users can view active profile, goals, plans, targets, logs, measurements, photos, decisions,
proposals, consents, and data-source status. Confirmed data corrections preserve necessary audit
history.

### Export

- Export is requested after recent authentication, and neither starts nor completes while an
  account deletion is pending. A package that fails after upload is removed from Storage.
- The package contains user-readable JSON/CSV and media organized by purpose, with units,
  provenance, and timestamps. It includes the onboarding profile fields, `onboarding_generations`,
  `onboarding_questions`, `onboarding_screenings` (the pre-plan health check answers),
  `health_history_months`, `day_adjustments` (the athlete's readiness answers),
  `pain_reports` (the athlete's pain checks),
  `ai_usage_events`, physique analyses and every
  set-timing column. `coach_facts` (what the athlete confirmed for Coach) and `coach_notes` (Coach's own
  notes) are included, and so are the Coach conversation (`coach_threads` and `coach_messages`,
  including threads the athlete asked Coach not to remember: they are the athlete's own words),
  `coach_narrative_entries`, `coach_session_summaries`, `coach_context_snapshots`, `user_preferences`,
  the nutrition schedules, HealthKit workout references and reconciliations, the feature-engine
  tables (`daily_computed_metrics`, `metric_baseline_history`, `user_baselines`), and the athlete's own
  export and deletion request rows. Rows tied to the account without a `user_id` are included too:
  the sign-up invite the account claimed (`signup_invites`: address and dates only; the owner's
  private note about the invitee is not the athlete's data) and the waitlist signup under the
  account email (`waitlist_signups`, without its token hashes and referral link), read through
  `export_linked_account_rows_v1`. A table is read in keyset pages of 1000 (rows after the last key,
  in key order), so rows that appear or go while the export runs neither repeat nor skip a row, and
  a server cap below the page size does not end a table early.
- Left out of the package, each with a reason in `omittedColumns` / `exportExclusions` in
  `privacy-export`: the `context` body of Coach context snapshots (a derived copy of exported
  tables, up to about 40 KB per Coach turn; the snapshot's id, thread, trigger, date and checksum
  stay), Coach message diagnostics (`search_vector`, `guard_faults`, `lookups`, `lookup_rounds`,
  `library_version`), internal Storage paths and queue numbers on export and deletion requests,
  `ai_budget_reservations` (internal spend ledger; the settled cost of each call is in
  `ai_usage_events`) and `private.day_adjustment_metric_attempts` (a rate-limit counter with no
  athlete content). A JSON value over 2000 characters appears once, in `data/all-data.json`, and the
  CSV points to it. The package is built in memory, so an account whose rows pass 16 MiB of JSON or
  whose media passes 32 MiB fails with the code `export_too_large` (recorded on the request) instead
  of running the function out of memory: the budget is counted page by page while the tables are
  read, the function answers 413 `export_too_large`, and the app says the data is too large to
  prepare in the app (the app has no support address; it points to whoever invited the athlete).
  A table with omitted columns selects an explicit column list, so an omitted column such as a
  snapshot's `context` is never downloaded; a test fails when the list drifts from the migrations. Meal photos that retention is deleting, or that are already
  gone from Storage, are listed under `skipped_media`. A Deno test reads the migrations and fails
  when a table with a `user_id` is in neither the export list nor the exclusion list, when a table
  has no unique key to page by, or when a column that points at the account (or is named `*_by`)
  has no line saying how its rows reach the export.
- An export stuck in `processing` is claimed again after 15 minutes, so it never blocks the next
  request. A `ready` export that has expired or used its three downloads is marked expired when the
  athlete asks for a new one, and a fresh export is queued in its place.
- It is encrypted, delivered through a short-lived authorization, and deleted within seven days.
- Export jobs and downloads are audited without logging content.
- The owner supplies an export-only password of at least 12 characters after reauthentication.
  PBKDF2-HMAC-SHA256 derives an AES-256-GCM key; neither the password nor key is persisted or
  queued.
- A package permits three downloads through 60-second signed authorization. Daily retention deletes
  it after the limit or seven days and retries failures.
- The research library is not exported: it holds no user data.

### Deletion

- Fresh password authentication and the exact phrase `DELETE` are required.
- Account deletion requires explicit confirmation and revokes active sessions promptly.
- Meal images, progress photos, and export packages are removed before the Auth user: every object
  recorded for the account plus every object in the account's folders
  (`list_account_storage_objects`), so an upload that never got a database row goes too. Every list
  is read in keyset pages of 1000 (after the last id, or name within a bucket), so an account with more files than the Data API returns at once leaves
  none behind. Auth
  deletion cascades through user-owned PostgreSQL records and removes the invite and waitlist rows
  (section 7); a content-free completion receipt remains for 180 days.
- Deleting from the app removes that athlete's local data (Apple Health sync state, an unsent
  check-in, the open Coach thread, the saved plan) once the server confirms. The saved plan (the
  last training hub, so the app opens with no connection) is tagged with the athlete's id, is
  never read for another account, and is also removed on sign-out and when a session is refused. Any device still holding a deleted
  account's session signs out at its next launch or refresh. Within the access token's hour Auth
  reports `user_not_found` and the local data goes too; after it only a refused refresh token is
  known, so the per-athlete data stays on the device, readable by no other account.
- New processing stops while deletion is pending.
- Delete relational user data, media, queued jobs, caches, exports, and supported provider
  application state.
- Backups age out within the documented window and cannot be restored selectively into production
  without reapplying deletion records.
- Retain only a minimal non-content tombstone when required for security or legal proof.
- Provide completion status without claiming deletion from systems not under Tracend's control;
  document such limitations beforehand.
- Destructive verification uses synthetic accounts only. Failure never reports completion to the
  app.
- The research library has nothing to delete for an account: it holds no user data.

### Consent withdrawal

Withdrawal is narrower than account deletion. Health-data consent (`health_data`) is withdrawn by
deleting the account or by email, since Tracend cannot coach without it. HealthKit withdrawal stops sync; photo-AI withdrawal
stops new analysis and removes provider-processing eligibility. Existing source records are handled
according to the notice and user deletion controls.

## 13. Threats and Required Controls

| Threat                            | Required controls                                                                            |
| --------------------------------- | -------------------------------------------------------------------------------------------- |
| Cross-user Data API/RPC access    | Supabase Auth JWT, default-deny RLS, scoped functions, foreign-key checks, adversarial tests |
| Leaked media URL                  | short-lived signed access, opaque IDs, private bucket, no logs                               |
| Malicious upload                  | type/size verification, metadata stripping, quarantine, image decode checks                  |
| Prompt injection in notes/imports | delimit untrusted text, no tools, fixed schema, policy outside model                         |
| Model hallucination mutates plan  | semantic validation, proposal-only output, explicit approval, version transaction            |
| Duplicate HealthKit sync          | idempotency keys, source checksum, daily unique constraints                                  |
| Secret/service-role exposure      | Edge Function secrets only, least privilege, log redaction, rotation, repository scanning    |
| Excessive provider sharing        | data minimization, task-specific context, provider inventory and consent                     |
| Stolen device/session             | short token lifetime, rotating refresh token, revocation, OS-protected storage               |
| Accidental support access         | no default admin media access, just-in-time approval and audit                               |

## 14. Incident Handling

1. Detect and classify the event without expanding exposure through logs.
2. Contain it: revoke credentials/sessions, disable affected endpoint/provider, and preserve
   necessary evidence.
3. Determine affected data, users, Supabase tables/buckets/functions, time window, and provider
   systems.
4. Eradicate the cause and validate isolation, deletion, and key rotation.
5. Notify users, providers, Apple, or authorities when applicable after legal assessment.
6. Restore cautiously and monitor recurrence.
7. Record corrective actions and add regression tests.

An emergency kill switch must disable AI/photo Edge Functions and Queue consumption while preserving
approved plans, logging, export, and deletion where safe.

## 15. TestFlight and Release Requirements

Before inviting testers:

- privacy policy and support URL are reachable;
- App Store Connect privacy disclosures match actual collection and providers;
- HealthKit capability and purpose strings match requested types;
- TestFlight notes state healthy-adult scope and non-medical limitation;
- local and hosted private-beta data/secrets are isolated; staging is separately isolated if later
  created;
- Supabase RLS and Storage policies pass anonymous and cross-user tests;
- secret/service-role and AI-provider keys are absent from the Flutter bundle;
- account export and deletion work end to end;
- media is private and signed URLs expire;
- cross-user authorization tests pass;
- logs and crash reports pass sensitive-data inspection; a meal-photo failure reaches Sentry as
  its step and error code only, because the error message can contain the photo's storage path;
- provider data controls are recorded and configured;
- athlete- and public-facing AI wording follows D11 (Planned, Phase 2 / A7);
- the hosted beta terms and privacy notice are linked from the onboarding rows and from Account
  (`site/src/pages/beta-terms.astro`, `privacy.astro`); health data has its own explicit consent
  (`health_data`); each page's version is its "Last updated" date, kept equal to `LegalNotices` in
  the app by `test/legal_versions_test.dart`, and a newer version asks onboarded athletes again
  at launch. The beta terms are a draft: have a lawyer review them before outside testers; and
- the owner completes at least two weeks of dogfooding before broader invitations.

The full TestFlight checklist is in [BETA_OPERATIONS.md](./BETA_OPERATIONS.md). Public App Store
release, minors, medical workflows, advertising, and subscriptions require a new privacy/legal
review and are outside MVP.

## 16. Related Authority

- [VISION.md](./VISION.md)
- [PRD.md](./PRD.md)
- [ARCHITECTURE.md](./ARCHITECTURE.md)
- [DATA_MODEL.md](./DATA_MODEL.md)
- [AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md)
- [COST_MODEL.md](./COST_MODEL.md)
