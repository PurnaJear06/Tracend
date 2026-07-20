# 2026-07-03 — Phase 8 Privacy and Operations

Notification force-close/reopen QA passed after native desired-toggle storage and delivery repair.

Forward migrations added forced-RLS export and deletion state, private export Storage, opaque Queue
messages, recent-authentication gates, bounded downloads, retryable retention, and content-free
deletion receipts. Export builds readable JSON/CSV plus purpose-organized media into a ZIP, then
encrypts it with PBKDF2-HMAC-SHA256 and AES-256-GCM using a password/key that is never persisted.
Deletion removes private Storage before canonical Supabase Auth deletion.

Hosted migrations and `privacy-export`, `privacy-delete-account`, and the updated retention worker
were deployed. A temporary synthetic hosted account passed export generation, secure download, local
decryption, manifest validation, account deletion, and receipt verification. No owner data or secret
value was copied into tests, logs, or this record. Synthetic artifacts and temporary API-key files
were removed.

Verification: fresh local migration replay, pgTAP 236/236, Deno 22/22, Flutter
format/analysis/tests, iPhone-only release compilation, and `git diff --check`. Free backup,
recovery, decryption, and incident procedures are documented in `docs/BETA_OPERATIONS.md`.

The hosted-config release passed strict signing and installed on the connected iPhone. CLI launch
was denied only because the device was locked; no simulator was used.

Owner export smoke opened Safari and downloaded successfully, while iOS returned a false URL-launch
result and the sheet showed an error/unchanged local counter. Hosted state confirmed the download
was correctly recorded as 1 of 3. The client now uses explicit external-browser mode and treats an
exception-free handoff as success, avoiding the false negative while preserving server-side count
authority.
