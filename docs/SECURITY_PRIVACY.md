# Tracend Security and Privacy Specification

## Workout Reconciliation Minimization

Workout-level HealthKit sync retains only type, time, duration, optional energy, and hashed
source/sample references needed for reconciliation. It does not copy routes, heart-rate series, or
unrelated raw samples.

**Status:** Authoritative private-beta security and privacy requirements\
**Data profile:** Health, fitness, nutrition, body measurements, and private photos

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

- HealthKit summaries and source metadata;
- workout performance, check-ins, pain, hunger, mood, and notes;
- nutrition logs, meal photos, allergies, and dietary constraints;
- body measurements, progress photos, and physique analyses;
- goals, limitations, plan decisions, and coaching history;
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
  support information.

Classification is inherited by derived data. A summary of health data remains restricted.

## 3. Consent and Transparency

Consent choices are separate and versioned for:

- private-beta terms and privacy notice;
- AI coaching: sending the athlete's Tracend data to the Coach's AI provider for chat answers and
  daily decisions (`ai_coaching`; a decline is stored as `withdrawn`, and a grant of an older notice
  version is asked again). The server enforces it: `coach-chat` refuses and `coach-decide` falls
  back to the deterministic decision without a current grant (`has_ai_coaching_consent`,
  service-role only);
- HealthKit read/sync by requested data type;
- meal-photo storage and AI analysis;
- progress-photo storage and progress-photo AI analysis as separate choices;
- notifications; and
- optional future research or product-improvement use, which is off by default and outside MVP.

Requirements:

- Purpose text is specific, plain-language, and shown in context.
- Denying an optional permission preserves unaffected features.
- Withdrawal stops new processing immediately and initiates purpose-specific deletion where
  required.
- Consent records store notice version, choice, source, and time. **Account › Consent history**
  shows each purpose's current choice with its date first and the notice version as secondary
  text (since the 2026-10 redesign); records made during owner testing read "Set up during
  testing".
- HealthKit permission state is not inferred from an empty query result.
- Provider names or categories, data sent, purpose, and relevant retention behavior are disclosed
  before AI photo processing.


AI consent is per purpose (2026-10):

- **The notice is server data.** `ai_consent_notices` holds every notice, and `ai_notice_current`
  names the current notice for the Coach chat, the daily decision and the onboarding plan.
- **A grant counts only for a current notice.** It counts for a purpose only while it names that
  purpose's current notice, so publishing a new notice (for example after a provider change) asks
  every athlete again.
- **New profile fields:**
  - The onboarding answers approval stores on `user_profiles` (sex, birth year, daily activity,
    equipment, limitations and diet notes) are writable only through approval. Clients keep column
    grants for the step-0 fields only.
  - They are exported by `privacy-export` and deleted with the account. So are
    `onboarding_generations` and `ai_usage_events`.
## 4. HealthKit

- Request only steps, active energy, sleep, workouts, weight, resting heart rate, HRV and
  breathing rate needed for enabled coaching.
- Onboarding may ask for Apple Health access as an optional step; skipping it never blocks a plan.
  The onboarding plan receives only a 28-day summary (average steps, active energy and sleep,
  workouts found, latest weight and trend), never raw samples, heart rate, HRV or breathing rate.
- After Apple Health connects, the app reads workouts, sleep and weight for the 11 completed months
  before this one and sends only monthly totals with their coverage (`save_health_history`, table
  `health_history_months`, owner-read RLS; refreshed at most once a month). No sample, heart rate,
  HRV, breathing rate or step history is sent. The plan uses them to compare the athlete's usual
  months with the last 28 days. They are in the privacy export and deleted with the account.
- The coach's follow-up questions are stored with their hash and telemetry in
  `onboarding_questions` (owner-read RLS, server-written, exported, deleted with the account); the
  athlete's answers stay in the onboarding draft.
- Request access near the relevant feature rather than at unexplained launch time.
- Provide accurate iOS purpose strings for every read/write capability; MVP is read-oriented unless
  a documented requirement adds writing.
- Normalize and upload required summaries; do not copy every raw sample by default.
- Preserve source and freshness needed to explain data quality and prevent duplicates.
- Never write false or model-invented values to HealthKit.
- HealthKit auto-completion is a user-initiated action: the app presents detected workout evidence,
  the user explicitly confirms, and the completed session is written with an audit trail. No
  background service-role or automated mutation occurs without the user's tap.
- Never store personal health information in iCloud containers.
- Never use HealthKit-derived data for advertising, marketing profiles, or sale.
- A disconnected or partially authorized user can continue through manual logging.

## 5. Photos and Media

### Storage

- Use separate private Supabase Storage buckets for meal images, progress photos, and temporary
  exports; public buckets are prohibited for restricted data.
- Enable operation-specific Storage RLS policies scoped to `auth.uid()`, bucket, owner, and purpose.
- Separate meal and progress-photo paths, permissions, processing queues, and retention policies.
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
- Progress images are retained while the account and relevant consent remain active or until the
  user deletes a set.
- Progress-photo viewing uses owner-authorized signed URLs that expire after 60 seconds. Set
  deletion removes Storage bytes before relational metadata; a failed byte deletion leaves the set
  visible for safe retry.
- Progress photos are included only in user-requested comparison jobs, never routine text coaching.
- A physique check (owner-only experiment, AI_SAFETY_SPEC §9) sends the front, side and back photos
  of one set to Groq only when the athlete starts it, under its own notice and consent
  (`progress_photo_ai`), with metadata stripped on the server and Groq's Zero Data Retention on.
  Results (`physique_analyses`) are owner-read, exported, and deleted with their set (analyses go
  first, `delete_my_progress_photo_set`) or the account.
- Face recognition, identity matching, sensitive-trait inference, and unrelated reuse are
  prohibited.

## 6. AI Provider Processing

- AI requests originate only from Supabase Edge Functions; provider keys and Supabase
  secret/service-role keys never enter Flutter.
- ADR 0006 permits Groq Qwen only for the owner’s disclosed, time-bounded Coach and meal-photo test.
  It remains server-only, purpose-bound and kill-switchable. Progress-photo processing is limited to
  the owner-only physique check (`PHYSIQUE_VISION_ALLOWED_USERS`) pending separate evaluation.
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
  [AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md) pass.
- Do not send restricted Tracend data through unpaid Gemini API service. Current unpaid-service
  terms permit product-improvement use and human review and instruct developers not to submit
  sensitive or personal information.
- Provider failure or policy change must degrade safely without changing the approved plan.
- Provider-side persistent conversation state is disabled unless documented, consented, deletable,
  and required.
- DeepSeek V4.1 Flash is the current active Coach/chat provider (`COACH_MODEL_PROVIDER=deepseek`),
  subject to the provider controls documented in [AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md). Prior
  providers (Gemini `gemini-3.5-flash`, Groq Qwen) were superseded pending evaluation. New
  providers require privacy review and evaluation parity before use with restricted data.

## 7. Authentication and Authorization

- Use native Sign in with Apple through Supabase Auth with a cryptographically secure nonce.
- Supabase Auth validates the Apple identity exchange and manages JWT access/refresh sessions;
  Tracend must not issue a parallel token system.
- Store Supabase sessions only through platform-protected storage supported by `supabase_flutter`;
  never general preferences or logs. Since 2026-10-09 the session lives in the iOS Keychain
  (`KeychainSessionStorage`, `first_unlock_this_device`, never synced or backed up). The first
  launch of that build moves a session from preferences, checks it reads back, then deletes the
  old copy; a fresh install clears anything a deleted install left in the Keychain.
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
  `notice_version`, `action` and `source` (never `created_at`), and the account time zone changes
  only through `set_my_timezone`.
- Require recent authentication for export, account deletion, or sensitive session changes.
  "Recent" is read from the JWT `amr` claim (`private.has_recent_sign_in`): a password, OTP or TOTP
  sign-in within 10 minutes. `iat` is not used, because a token refresh resets it while `amr`
  keeps the time of the sign-in that started the session.
- Sign-ups are invite-only during the beta. `private.handle_new_auth_user` refuses an email that is
  not in `private.signup_invites` (reachable only from the SQL editor), so the Auth insert rolls
  back and no account or email is created; existing accounts were seeded on 2026-10-09. Invite
  with `insert into private.signup_invites(email, note) values (lower('<email>'), 'beta');`.
- `meal-media-retention` validates a dedicated `RETENTION_WORKER_SECRET` (not JWT). Store the same
  generated value in Edge Function secrets and Supabase Vault; Cron reads Vault. Never place it in
  Flutter, shell history, logs, or committed files.

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
  unless the caller is the service role (`persist_coach_preference`).
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
navigation parameters, text fields, and network bodies.

Audit events record access and changes using opaque IDs and action codes, not copies of sensitive
content.

Phase 8 local reminders are scheduled by iOS and use only the generic title `Tracend reminder` and
body `Open Tracend when convenient.` Lock-screen content never names health, nutrition, workouts,
photos, measurements, or coaching decisions. The server stores toggles and coarse permission state,
not delivery history or notification content. iOS stores only the two local boolean choices and
repairs missing pending requests after reopen; no notification payload or delivery history is added
to local preference storage.

The workout rest alert (2026-10-03) is a third local notification type with the fixed identifier
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

## 11. Retention

Initial private-beta defaults:

- account/profile/plans/logs/measurements/decisions: retained until user deletion or explicit record
  deletion where supported;
- confirmed meal records: retained until user deletion; source meal image deleted after 30 days
  unless explicitly saved;
- discarded or failed meal images: deleted within 7 days;
- progress photos: retained until photo-set or account deletion, consent withdrawal requiring
  deletion, or beta shutdown;
- temporary signed URLs: minutes, never permanent;
- export packages: deleted within 7 days or after the configured download limit;
- refresh sessions: deleted or tombstoned after expiry/revocation according to security policy;
- application logs: 30 days by default;
- sanitized security audit metadata: 180 days by default;
- Free Plan database: encrypted off-site logical export at least weekly during active beta and
  before migrations; Supabase does not provide the Pro daily-backup guarantee;
- Pro Plan database: Supabase daily backups with the plan's current seven-day availability, plus an
  independent pre-release logical export where permitted;
- Storage objects: separate encrypted inventory/export procedure because database backups contain
  metadata but not Storage bytes; and
- provider content: shortest available approved retention, documented per provider.
- Coach threads/messages: retained until the owner deletes the thread, deletes the account, or the
  private beta shuts down; provider-side conversation state remains disabled.

Retention jobs are idempotent, observable, and tested. Changing a default requires updating this
document, user notice where applicable, and implementation tests.

Owner-supplied historical context used for an administrative import remains in ignored,
permission-restricted `.tooling/private-imports/` files on the external SSD. Raw reports and import
payloads are never committed or copied into handoff, progress, audit, or application logs.

Meal-photo requests use private Storage bytes only after explicit photo consent (the
`meal_photo_ai` grant of the current meal photo notice, checked by meal-analyze before any
download). The provider
receives a minimized image and fixed instruction with no identity, object key, or unrelated history.
Visible text in an image is untrusted input. Analysis candidates are unconfirmed restricted data and
follow meal-media retention even when the provider or validation fails.

## 12. User Rights and Controls

### Access and correction

Users can view active profile, goals, plans, targets, logs, measurements, photos, decisions,
proposals, consents, and data-source status. Confirmed data corrections preserve necessary audit
history.

### Export

- Export is requested after recent authentication, and neither starts nor completes while an
  account deletion is pending. A package that fails after upload is removed from Storage.
- The package contains user-readable JSON/CSV and media organized by purpose, with units,
  provenance, and timestamps.
- It is encrypted, delivered through a short-lived authorization, and deleted within seven days.
- Export jobs and downloads are audited without logging content.
- The owner supplies an export-only password of at least 12 characters after reauthentication.
  PBKDF2-HMAC-SHA256 derives an AES-256-GCM key; neither the password nor key is persisted or
  queued.
- A package permits three downloads through 60-second signed authorization. Daily retention deletes
  it after the limit or seven days and retries failures.

### Deletion

- Fresh password authentication and the exact phrase `DELETE` are required.
- Meal images, progress photos, and export packages are removed before the Auth user: every object
  recorded for the account plus every object in the account's folders
  (`list_account_storage_objects`), so an upload that never got a database row goes too. Auth deletion
  cascades through user-owned PostgreSQL records; a content-free completion receipt remains for 180
  days.
- Destructive verification uses synthetic accounts only. Failure never reports completion to the
  app.

- Account deletion requires explicit confirmation and revokes active sessions promptly. Deleting
  from the app removes that athlete's local data (Apple Health sync state, an unsent check-in, the
  open Coach thread) once the server confirms. Any device still holding a deleted account's
  session signs out at its next launch or refresh. Within the access token's hour Auth reports
  `user_not_found` and the local data goes too; after it only a refused refresh token is known,
  so the per-athlete data stays on the device, readable by no other account.
- New processing stops while deletion is pending.
- Delete relational user data, media, queued jobs, caches, exports, and supported provider
  application state.
- Backups age out within the documented window and cannot be restored selectively into production
  without reapplying deletion records.
- Retain only a minimal non-content tombstone when required for security or legal proof.
- Provide completion status without claiming deletion from systems not under Tracend's control;
  document such limitations beforehand.

### Consent withdrawal

Withdrawal is narrower than account deletion. HealthKit withdrawal stops sync; photo-AI withdrawal
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
- **public-release blocker:** the onboarding Terms and Privacy checkboxes are not linked to any
  hosted text yet (no notices are published). This is acceptable only for the owner-only private
  beta; the hosted terms and privacy notice must exist and be linked from those checkboxes before
  any other tester or a public release; and
- the owner completes at least two weeks of dogfooding before broader invitations.

Public App Store release, minors, medical workflows, advertising, and subscriptions require a new
privacy/legal review and are outside MVP.

## 16. Related Authority

- [VISION.md](./VISION.md)
- [PRD.md](./PRD.md)
- [ARCHITECTURE.md](./ARCHITECTURE.md)
- [DATA_MODEL.md](./DATA_MODEL.md)
- [AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md)
- [COST_MODEL.md](./COST_MODEL.md)
