# Private-Beta Operations

This runbook supports Phase 8 owner dogfooding. It does not expand the product scope or replace the
privacy rules in `SECURITY_PRIVACY.md`.

## Weekly backup on Supabase Free

1. Create an encrypted backup directory under `.tooling/backups/YYYY-MM-DD/` on the external SSD.
2. Run `./scripts/supabase.sh db dump --linked --file <directory>/database.sql` before migrations
   and at least weekly while the beta is active.
3. In the Supabase Storage dashboard, export the private `meal-images`, `progress-photos`, and
   `account-exports` buckets into the same encrypted directory. Keep object paths with their bucket
   names because the database dump contains metadata, not object bytes.
4. Generate a SHA-256 inventory with
   `find <directory> -type f -print0 | sort -z | xargs -0 shasum -a 256 > <directory>/SHA256SUMS`.
5. Copy the encrypted directory to a second owner-controlled location. Never commit it or place it
   in a public/shared folder.
6. Quarterly, restore the database and Storage inventory into an isolated local Supabase project
   using synthetic verification only. Record the date, result, and owner without copying user data
   into worklogs.

## Export package recovery

The app creates a ZIP payload encrypted with AES-256-GCM and a password-derived key. After
downloading the `.tracendexport` file to the external SSD, decrypt it with the repository-local Deno
runtime and a password supplied only through the process environment:

```sh
read -s TRACEND_EXPORT_PASSWORD
export TRACEND_EXPORT_PASSWORD
./scripts/deno.sh run \
  --allow-env=TRACEND_EXPORT_PASSWORD \
  --allow-read='/Volumes/Crucial X9/path/export.tracendexport' \
  --allow-write='/Volumes/Crucial X9/path/decrypted' \
  scripts/decrypt-export.ts \
  '/Volumes/Crucial X9/path/export.tracendexport' \
  '/Volumes/Crucial X9/path/decrypted'
unset TRACEND_EXPORT_PASSWORD
```

Delete decrypted copies when no longer needed. Tracend cannot recover the export password.

## Incident rehearsal

For suspected token, key, RLS, Storage, or provider exposure:

1. Disable the affected function/provider path while preserving approved plans and manual logging.
2. Revoke sessions or rotate only the affected server-side secret. Never place replacement values in
   chat, logs, commits, or mobile configuration.
3. Verify RLS, private bucket policies, function authentication, and sanitized logs with synthetic
   users.
4. Determine affected resource IDs and time window without copying restricted content into the
   incident record.
5. Notify affected beta users when required, restore service from reviewed configuration, and run
   the critical hosted synthetic suite.
6. Record cause, containment, validation, and preventive action. Do not record tokens, object paths,
   signed URLs, health values, photos, prompts, or notes.

The 2026-07-03 tabletop rehearsal used a hypothetical leaked worker secret. The expected containment
path is function disablement, secret rotation, Cron/Vault update, unauthenticated rejection
verification, and retention-worker smoke.

## TestFlight external beta checklist

Today the beta is owner-only: signed release builds go straight to the owner's iPhone
(`./scripts/install-device.sh`), production Auth sign-ups are off, and sign-ups are invite-only.
Opening the beta to other people waits for decision D7 (all four phases of
`docs/plans/coaching-platform-2026-10/README.md` merged and device-checked) and the D11 wording.
Work through this list in order once the paid Apple Developer Program is active.

1. **Enroll.** On the iPhone, open the Apple Developer app, sign in with the Apple Account that
   will own the app, and enroll (Account > Enroll; enrollment in India is done in the app). Use
   the 2-factor Apple Account, the legal name and the ID Apple asks for, and pay the annual fee.
   Wait for the confirmation email, then note the new paid Team ID.
2. **Sign with the paid team.** In Xcode (Signing & Capabilities) switch the Runner target, and any
   extension target, from the free team to the paid team. Register the bundle IDs
   (`com.tracend.app` and each extension) in Certificates, Identifiers & Profiles with the HealthKit
   capability, and only the other capabilities the build uses. Let Xcode create the Apple
   Distribution certificate and App Store profiles.
3. **Create the app record.** App Store Connect > Apps > New App: iOS, the Tracend name (it must be
   free on the App Store), primary language, bundle ID `com.tracend.app`, a SKU. Set the privacy
   policy URL to `https://tracend.pages.dev/privacy/` and a support URL.
4. **Fill in App Privacy (nutrition labels)** to match `site/src/pages/privacy.astro`: email
   address; health and fitness (Apple Health types, workouts, weight, measurements); photos (meal
   and progress); other user content (Coach messages, meals, check-ins); user ID; crash and other
   diagnostic data (Edge Function reports can carry the user ID). Purpose: app functionality. No
   tracking, no third-party advertising.
5. **Upload a build.** Raise the build number in `pubspec.yaml` (it must grow on every upload) and
   build from a merged `main` commit with the `.env` values, as `install-device.sh` does. Upload
   either from Xcode (Product > Archive > Distribute App > App Store Connect) or from CI with an App
   Store Connect API key (issuer ID, key ID and `.p8` kept as GitHub secrets; workflows are the
   lead's files). Answer the export compliance question once: the app uses HTTPS and AES-256-GCM
   for export files, then record the answer in `Info.plist` (`ITSAppUsesNonExemptEncryption`) so
   later builds skip it. Before uploading, run `./scripts/verify-app-bundle.sh` on the archived
   `Runner.app` (inside the `.xcarchive` under `Products/Applications/`).
6. **Test internally first.** Add the owner as an internal tester (no review needed) and install
   the TestFlight build. Check sign-in, Apple Health permission, every AI consent notice, export
   and account deletion on that build.
7. **Open the gate in Supabase.** Turn production sign-ups back on (Dashboard > Authentication >
   Sign In / Providers > Allow new users to sign up). The invite-only trigger still refuses any
   email that has no row in `private.signup_invites`, so add each tester before they sign up:
   `select * from private.invite_from_waitlist(n);` for confirmed waitlist signups, or insert the
   email into `private.signup_invites` with a note. Check that an email with no invite is still
   refused.
8. **Prepare Beta App Review.** In TestFlight > Test Information add the beta description, a
   feedback email, and a reviewer account: invite a reviewer email (step 7), sign up once, load
   synthetic data only, and give its email and password in the sign-in fields. In the review notes
   say that Apple Health access is optional, and that the AI disclosure follows App Review
   Guideline 5.1.2(i): before any AI feature shares data with a third-party AI company, the app
   shows a notice naming that company and what is sent, asks for explicit permission, and works
   without it.
9. **Create the external group.** TestFlight > External Testing > add a group, add the build and
   submit it for Beta App Review. The first build of each version is reviewed; later builds of the
   same version usually are not. Then add testers by email, using the same emails that were
   invited in step 7. Do not use a public link while sign-ups are invite-only.
10. **Run it.** Builds expire after 90 days; upload a new one before then. Watch Sentry and the AI
    budget after each new group.
