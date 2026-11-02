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
3. **Review `ios/Runner/Info.plist`** (in a PR by the owner of `ios/**`):
   - Read every purpose string (Health, camera, photo library) against what the app does.
   - The app reads Health and never writes to it (no write calls in `lib/`), so remove
     `NSHealthUpdateUsageDescription` unless a build starts asking for write access.
   - Set `ITSAppUsesNonExemptEncryption` to `NO`. The app itself only uses HTTPS; the export
     file's AES-256-GCM encryption runs on the server, not in the app. This answers export
     compliance for every build.
4. **Create the app record.** App Store Connect > Apps > New App: iOS, the Tracend name (it must be
   free on the App Store), primary language, bundle ID `com.tracend.app`, a SKU. Then:
   - privacy policy URL `https://tracend.pages.dev/privacy/` and a support URL;
   - the age rating questionnaire, answered so the rating is 18+ (Tracend is for adults).
5. **Fill in App Privacy (nutrition labels)** to match `site/src/pages/privacy.astro`. Mark every
   type "Linked to you", purpose App Functionality, not used for tracking:
   - Contact Info: Email Address.
   - Health & Fitness: Health (Apple Health data, weight, body measurements) and Fitness
     (workouts, sets, training load), as two separate types.
   - User Content: Photos or Videos (meal and progress photos); Other User Content (Coach
     messages, meals, check-ins).
   - Identifiers: User ID.
   - Diagnostics: Crash Data, Performance Data (Sentry traces) and Other Diagnostic Data.
6. **Build and upload.** Build from a merged `main` commit through the wrapper with the `.env`
   dart-defines, as `scripts/install-device.sh` does, not from a bare Xcode archive:
   `./scripts/flutter.sh build ipa --release` with `--build-name "$(./scripts/app-version.sh name)"`,
   `--build-number "$(./scripts/app-version.sh number)"` (the git commit count, so it grows with
   every merge) and `--dart-define` for `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` and
   `SENTRY_DSN`. Run `./scripts/verify-app-bundle.sh` on the built `Runner.app`
   (`build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app` under the checkout's
   build directory), then upload the `.ipa` with Apple's Transporter app, or from CI with an App
   Store Connect API key (issuer ID, key ID and `.p8` as GitHub secrets; workflows are the lead's
   files).
7. **Check the upload email.** If App Store Connect reports ITMS-91053 (missing API declaration) or
   ITMS-91061 (missing privacy manifest), add `ios/Runner/PrivacyInfo.xcprivacy` declaring the
   required-reason APIs named in the email, update any SDK it names, and upload again.
8. **Test internally first.** Add the owner as an internal tester (no review needed) and install
   the TestFlight build. Check sign-in, Apple Health permission, every AI consent notice, export
   and account deletion on that build.
9. **Make Supabase Auth email work for outsiders.** Supabase's built-in email only reaches the
   project team. In Dashboard > Authentication > Emails > SMTP Settings, set custom SMTP with the
   Gmail account the waitlist already uses (`smtp.gmail.com`, port 465, the same app password).
   Set the Site URL to `https://tracend.pages.dev` (Authentication > URL Configuration): a sign-up
   confirmation link confirms the email and lands there. The app takes no session from a link, so
   it needs no redirect URL. Then:
   - **Reset password email.** The app resets a forgotten password with a code typed into the app,
     and Supabase's default template only has a link. In Authentication > Emails > Templates >
     Reset password, set the subject to `Your Tracend password reset code` and the body to:

     ```html
     <h2>Reset your Tracend password</h2>
     <p>Enter this code in the Tracend app, with your new password:</p>
     <p style="font-size:28px;font-weight:bold;letter-spacing:6px;">{{ .Token }}</p>
     <p>The code works once and expires in one hour. If you did not ask to reset your password,
     ignore this email: your password stays the same.</p>
     ```

     Keep `{{ .ConfirmationURL }}` out of it: opening that link would use up the code.
   - **Code settings.** In Authentication > Sign In / Providers > Email, keep Email OTP Expiration at
     3600 seconds (the template says one hour) and Email OTP Length at 6.
   - **Leaked-password protection.** Turn on the setting that refuses passwords found in known
     breaches (Authentication > Passwords). The app says "This password has appeared in a data
     breach" when Auth refuses one.
   - **Check.** Sign up with an invited address outside the team and check that the confirmation
     email arrives, its link confirms the address and **Resend email** sends another. Then use
     **Forgot password?** on that account: the code arrives, **Set new password** signs in, and the
     old password no longer works.
10. **Open the gate in Supabase.** Turn production sign-ups back on (Dashboard > Authentication >
    Sign In / Providers > Allow new users to sign up). The invite-only trigger still refuses any
    email that has no row in `private.signup_invites`, so add each tester before they sign up:
    `select * from private.invite_from_waitlist(n);` for confirmed waitlist signups, or insert the
    email into `private.signup_invites` with a note. Check that an email with no invite is still
    refused.
11. **Prepare Beta App Review.** In TestFlight > Test Information add the beta description, a
    feedback email, the privacy policy URL `https://tracend.pages.dev/privacy/`, and a reviewer
    account: invite a reviewer email (step 10), sign up once, load synthetic data only, and give
    its email and password in the sign-in fields. In the review notes say that Apple Health
    access is optional, and that the AI disclosure follows App Review Guideline 5.1.2(i): before
    any AI feature shares data with a third-party AI company, the app shows a notice naming that
    company and what is sent, asks for explicit permission, and works without it.
12. **Create the external group.** TestFlight > External Testing > add a group, add the build and
    submit it for Beta App Review. The first build of each version is reviewed; later builds of
    the same version usually are not. Then add testers by email, using the same emails that were
    invited in step 10. Do not use a public link while sign-ups are invite-only.
13. **Run it.** Builds expire after 90 days; upload a new one before then. Watch Sentry and the AI
    budget after each new group.
