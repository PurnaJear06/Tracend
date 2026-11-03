# Private-Beta Operations

This runbook supports Phase 8 owner dogfooding. It does not expand the product scope or replace the
privacy rules in `SECURITY_PRIVACY.md`.

## Backups on Supabase Free

Free Supabase has no daily backups of its own. `nightly-backup.yml` runs at 19:17 UTC every night
(and by hand from Actions > Nightly Backup > Run workflow) and stores an encrypted database backup
in the private `Tracend-backups` repository, the newest 30:
`database-backup-<stamp>.tar.gz.enc` holds roles, schema and data, restore-drilled into a
throwaway database before it is stored. Every merge to `main` makes one too.

**Photos are not backed up yet.** Progress photos (the private `progress-photos` bucket) are in no
backup: database dumps hold their metadata, not the bytes. Meal photos (`meal-images`) are
deleted about 7 days after capture and `account-exports` hold short-lived files, so neither needs
one. A photo backup in the private backups repository was built and removed from this PR: that
repository's history is force-pushed but GitHub keeps old objects, so a deleted account's photos
could not be guaranteed to leave within 30 nights. The follow-up is an encrypted photo backup to a
store with lifecycle deletion: Cloudflare R2 (already on the account, free tier 10 GB) with a
30-day lifecycle rule. You create the bucket and a key scoped to that bucket only; the key goes
in as a GitHub secret, never in the repository. Until then a lost bucket loses the photos.

A failed night emails the repository owner (GitHub sends this for any failed scheduled run). Look
at Actions > Nightly Backup once a week while the beta runs, and open the backups repository
after the first night to check the new file.

**Restore.** Decrypt with the passphrase from the `BACKUP_ARCHIVE_PASSPHRASE` secret:

```sh
read -s BACKUP_ARCHIVE_PASSPHRASE
export BACKUP_ARCHIVE_PASSPHRASE
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -in database-backup-<stamp>.tar.gz.enc \
  -pass env:BACKUP_ARCHIVE_PASSPHRASE | tar -xzf - -C <empty-directory>
unset BACKUP_ARCHIVE_PASSPHRASE
```

The restore drill in `deploy.yml` (`docs/CI_CD_DEPLOYMENT.md`, Backup contract) is the tested way to restore a database backup.

Optional: a second owner-controlled copy of both backups, kept encrypted on the external SSD and
never committed or placed in a shared folder. Quarterly, restore the database and the photos into
an isolated local Supabase project using synthetic verification only. Record the date, result and
owner without copying user data into worklogs.

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

## Changing the beta terms or the privacy notice

The app's legal pages are `site/src/pages/beta-terms.astro` and `site/src/pages/privacy.astro`.
Each page's version is its "Last updated" date. In one PR:

1. Edit the page and set its "Last updated" date to the day it goes live.
2. Set the matching constant in `LegalNotices` (`lib/features/consent/legal_consent.dart`) to the
   same date in ISO form (`termsVersion` or `privacyVersion`; health-data consent follows the
   privacy notice). `test/legal_versions_test.dart` fails in CI until the page and the constant
   agree.
3. Merge. The deploy publishes the page; then install the app built from that `main` commit.
   On its next launch every onboarded athlete whose grant is older sees **Terms and privacy** and
   agrees again (or signs out, or deletes the account) before the app opens. Git history keeps
   every earlier version of each page, and `consent_records.notice_version` says which one each
   athlete agreed to.

The server stores Apple Health only for an athlete whose newest `health_data` consent record is a
grant (any version). After the migration `20261102213907_health_data_consent_enforced.sql`
deploys, an installed build 920 cannot sync Apple Health: `health-sync` answers 403
`health_consent_required` until the new build is installed and the athlete agrees on the **Terms
and privacy** screen. Nothing is lost: the sync does not move its last-sync mark, so the next sync
sends the same window again. Install the new build soon after the deploy.

A wording fix that changes nothing an athlete agreed to still changes the date, and so asks
everyone again; batch such fixes. The website terms (`terms.astro`) cover only the site and the
waitlist and are not asked for in the app. The beta terms are a draft written without a lawyer;
have them reviewed before inviting anyone outside the owner.

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
2. **Sign with the paid team.** The Xcode project still names the free team in every
   `DEVELOPMENT_TEAM` line of `ios/Runner.xcodeproj/project.pbxproj` (the app, the widget
   extension and the tests); switch all of them to the paid Team ID in a PR (Xcode: Signing &
   Capabilities for each target). `scripts/build-testflight.sh` reads the team from there and
   refuses a project that names more than one. In Certificates, Identifiers & Profiles:
   - register the App ID `com.tracend.app` with the HealthKit capability and the App Group
     `group.com.tracend.app`;
   - register the widget extension's App ID `com.tracend.app.TracendWidgets` with the same App
     Group (its Live Activity needs no extra capability);
   - let Xcode create the Apple Distribution certificate and the App Store profiles for both. The
     first `build-testflight.sh` run does it, because the build uses automatic signing and Xcode
     must be signed in to the paid team (Xcode > Settings > Accounts).
3. **`ios/Runner/Info.plist` and the privacy manifest** are done in the repository:
   `ITSAppUsesNonExemptEncryption` is `false` (the app itself only uses HTTPS and SHA hashing; the
   export file's AES-256-GCM encryption runs on the server, so every upload skips the export
   compliance question), the Health text names the data read and says where it goes, and
   `ios/Runner/PrivacyInfo.xcprivacy` declares the one required-reason API the app's own code uses
   (UserDefaults, reason CA92.1), no tracking, and the data types of step 5. Keep that file in step
   with `site/src/pages/privacy.astro` whenever the app collects something new.
4. **Create the app record.** App Store Connect > Apps > New App: iOS, the Tracend name (it must be
   free on the App Store), primary language, bundle ID `com.tracend.app`, a SKU. Then:
   - privacy policy URL `https://tracend.pages.dev/privacy/` and a support URL (the app's beta
     terms are at `https://tracend.pages.dev/beta-terms/`);
   - the age rating questionnaire, answered so the rating is 18+ (Tracend is for adults).
5. **Fill in App Privacy (nutrition labels)** to match `site/src/pages/privacy.astro`. Mark every
   type "Linked to you", purpose App Functionality, not used for tracking:
   - Contact Info: Email Address.
   - Health & Fitness: Health (Apple Health data, weight, body measurements) and Fitness
     (workouts, sets, training load), as two separate types.
   - User Content: Photos or Videos (meal and progress photos); Other User Content (Coach
     messages, meals, check-ins).
   - Identifiers: User ID.
   - Diagnostics: Crash Data, Performance Data (Sentry traces) and Other Diagnostic Data (Sentry
     reports of handled errors, with error type and code only). `PrivacyInfo.xcprivacy` declares
     the same types.
6. **Set up the upload key (once).** App Store Connect > Users and Access > Integrations > App
   Store Connect API > Team Keys > generate a key with the Developer role. Note the Key ID and the
   Issuer ID shown on that page, and download the `.p8` file: Apple lets you download it once.
   Save it as `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8` with `chmod 600` (the folder
   `altool` searches), and put the two IDs in your shell profile as `ASC_KEY_ID` and
   `ASC_ISSUER_ID`. The key never goes in the repository, `.env`, a GitHub secret or chat; revoke
   it from the same page if it leaks.
7. **Build and upload.** From a clean checkout of the newest `origin/main` (a worktree is fine:
   `git checkout --detach origin/main`) with `.env` filled in as for `install-device.sh`:
   `./scripts/build-testflight.sh --check` runs every guard first, then
   `./scripts/build-testflight.sh` builds the signed App Store `.ipa`, checks the bundle inside it
   (icons, fonts, privacy manifest, widget extension, build number) and prints the upload command:
   `xcrun altool --upload-app --type ios -f <ipa> --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"`
   (or drag the `.ipa` into Apple's Transporter app). It refuses a dirty tree, a commit that is not
   the `origin/main` tip, an empty `SUPABASE_URL` or `SUPABASE_PUBLISHABLE_KEY`, and a build number
   that is not higher than the last one built on this Mac. The build number is the commit count of
   `origin/main`, so it grows with every merge and later uploads are never rejected as "bundle
   version must be higher". A build without the server settings would show "This build is missing
   its server settings" instead of running a demo, but it should never get that far.
8. **Check the upload email.** Apple emails about any problem within minutes. ITMS-91053 (missing
   API declaration) means a required-reason API is used that `ios/Runner/PrivacyInfo.xcprivacy`
   does not declare: add the reason the email names, update any SDK it names, and upload again.
9. **Test internally first.** Add the owner as an internal tester (no review needed) and install
   the TestFlight build. Check sign-in, Apple Health permission, every AI consent notice, export
   and account deletion on that build.
10. **Make Supabase Auth email work for outsiders.** Supabase's built-in email only reaches the
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
11. **Open the gate in Supabase.** Turn production sign-ups back on (Dashboard > Authentication >
    Sign In / Providers > Allow new users to sign up). The invite-only trigger still refuses any
    email that has no row in `private.signup_invites`, so add each tester before they sign up:
    `select * from private.invite_from_waitlist(n);` for confirmed waitlist signups, or insert the
    email into `private.signup_invites` with a note. Check that an email with no invite is still
    refused.
12. **Prepare Beta App Review.** In TestFlight > Test Information add the beta description, a
    feedback email, the privacy policy URL `https://tracend.pages.dev/privacy/`, and a reviewer
    demo account, because sign-ups are off and the reviewer cannot create one: invite a reviewer
    email (step 11), sign up once in the build, finish onboarding with synthetic data only, and
    give its email and password in the sign-in fields of Test Information. Keep the account
    working for as long as builds are in review, and delete it with the in-app deletion when the
    beta ends. In the review notes say that Apple Health
    access is optional, and that the AI disclosure follows App Review Guideline 5.1.2(i): before
    any AI feature shares data with a third-party AI company, the app shows a notice naming that
    company and what is sent, asks for explicit permission, and works without it.
13. **Create the external group.** TestFlight > External Testing > add a group, add the build and
    submit it for Beta App Review. The first build of each version is reviewed; later builds of
    the same version usually are not. Then add testers by email, using the same emails that were
    invited in step 11. Do not use a public link while sign-ups are invite-only.
14. **Run it.** Builds expire after 90 days; upload a new one before then. Watch Sentry and the AI
    budget after each new group.
