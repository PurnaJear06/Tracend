# Private-Beta Operations

This runbook supports Phase 8 owner dogfooding. It does not expand the product
scope or replace the privacy rules in `SECURITY_PRIVACY.md`.

## Weekly backup on Supabase Free

1. Create an encrypted backup directory under `.tooling/backups/YYYY-MM-DD/` on
   the external SSD.
2. Run `./scripts/supabase.sh db dump --linked --file <directory>/database.sql`
   before migrations and at least weekly while the beta is active.
3. In the Supabase Storage dashboard, export the private `meal-images`,
   `progress-photos`, and `account-exports` buckets into the same encrypted
   directory. Keep object paths with their bucket names because the database
   dump contains metadata, not object bytes.
4. Generate a SHA-256 inventory with
   `find <directory> -type f -print0 | sort -z | xargs -0 shasum -a 256 > <directory>/SHA256SUMS`.
5. Copy the encrypted directory to a second owner-controlled location. Never
   commit it or place it in a public/shared folder.
6. Quarterly, restore the database and Storage inventory into an isolated
   local Supabase project using synthetic verification only. Record the date,
   result, and owner without copying user data into worklogs.

## Export package recovery

The app creates a ZIP payload encrypted with AES-256-GCM and a password-derived
key. After downloading the `.tracendexport` file to the external SSD, decrypt
it with the repository-local Deno runtime and a password supplied only through
the process environment:

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

Delete decrypted copies when no longer needed. Tracend cannot recover the
export password.

## Incident rehearsal

For suspected token, key, RLS, Storage, or provider exposure:

1. Disable the affected function/provider path while preserving approved plans
   and manual logging.
2. Revoke sessions or rotate only the affected server-side secret. Never place
   replacement values in chat, logs, commits, or mobile configuration.
3. Verify RLS, private bucket policies, function authentication, and sanitized
   logs with synthetic users.
4. Determine affected resource IDs and time window without copying restricted
   content into the incident record.
5. Notify affected beta users when required, restore service from reviewed
   configuration, and run the critical hosted synthetic suite.
6. Record cause, containment, validation, and preventive action. Do not record
   tokens, object paths, signed URLs, health values, photos, prompts, or notes.

The 2026-07-03 tabletop rehearsal used a hypothetical leaked worker secret. The
expected containment path is function disablement, secret rotation, Cron/Vault
update, unauthenticated rejection verification, and retention-worker smoke.
