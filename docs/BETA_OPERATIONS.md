# Private-Beta Operations

This runbook supports Phase 8 owner dogfooding. It does not expand the product scope or replace the
privacy rules in `SECURITY_PRIVACY.md`.

## Backups on Supabase Free

Free Supabase has no daily backups of its own. `nightly-backup.yml` runs at 19:17 UTC every night
(and by hand from Actions > Nightly Backup > Run workflow) and stores two kinds of encrypted
backup in the private `Tracend-backups` repository, the newest 30 of each:

- `database-backup-<stamp>.tar.gz.enc`: roles, schema and data, restore-drilled into a throwaway
  database before it is stored. Every merge to `main` makes one too.
- `photo-backup-<stamp>.tar.gz.enc`: the private `progress-photos` bucket. Every night adds one (an empty
  bucket adds an archive with no files), so a deleted account's photos leave the backups within
  30 nights, as its database rows do. Meal photos (`meal-images`) are not backed up: the app deletes them about 7 days after
  they are taken. `account-exports` holds short-lived export files, also not backed up.

A failed night emails the repository owner (GitHub sends this for any failed scheduled run). Look
at Actions > Nightly Backup once a week while the beta runs, and open the backups repository
after the first night to check the new files.

**Size.** The backups repository holds 30 photo archives. GitHub recommends staying under 1 GB
per repository and rejects a file over 100 MiB, so the photo backup warns at 25 MiB and
`store-backup.sh` refuses an archive over 90 MiB. At the beta's size that is far away. When the
warning appears, move photo backups to object storage (Cloudflare R2 is on the existing
Cloudflare account; its free tier holds 10 GB) with its own access key kept as a GitHub secret.

**Restore.** Decrypt with the passphrase from the `BACKUP_ARCHIVE_PASSPHRASE` secret, then unpack:

```sh
read -s BACKUP_ARCHIVE_PASSPHRASE
export BACKUP_ARCHIVE_PASSPHRASE
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -in photo-backup-<stamp>.tar.gz.enc \
  -pass env:BACKUP_ARCHIVE_PASSPHRASE | tar -xzf - -C <empty-directory>
unset BACKUP_ARCHIVE_PASSPHRASE
```

The photos come out under the paths Storage used (`<account id>/<file>`). Upload them back with
`./scripts/supabase.sh storage cp --experimental --linked -r <directory> ss:///progress-photos`.
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
   Set the Site URL and the redirect URLs the app's auth links use (Authentication > URL
   Configuration). Then sign up with an invited address outside the team and check that the
   email arrives and its link works.
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
