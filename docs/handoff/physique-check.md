# Physique check (owner-only experiment)

**Status (2026-10-02):** PR open, not deployed. PR 2 of the coach-quality batch (plan:
`~/.claude/plans/sprightly-splashing-dolphin.md`; PR 1, the coach intake, shipped in #70).

## What it does

From Progress, an allowlisted athlete with a complete photo set can start a physique check. The
`physique-check` Edge Function sends the set's front, side and back photos (metadata stripped) with
sex, height, latest weight and measurements, and goal to Groq `qwen/qwen3.8-27b`. The reply must
pass `_shared/physique/contract.ts`: 1–3 muscles to develop relative to the athlete's own build,
with confidence and a short reason, up to three neutral observations, photo issues and
limitations. Any body-fat, percentage, score, looks, sexual, medical, sensitive-trait or eating
wording rejects the whole reply. The app shows it as an AI visual estimate, and the athlete may
confirm up to two suggested muscles as their focus (`set_my_priority_muscles` →
`user_profiles.priority_muscles`), which the Coach reads at once and the next plan uses. Rules:
AI_SAFETY_SPEC §9.

## Pieces

- **Migration** `20261002150000_physique_check.sql`:
  - `delete_my_progress_photo_set` deletes the set's analyses first. Before, a set with an analysis
    could not be deleted.
  - `photo_ai_notices` with notice `progress-photo-ai-v1` (Groq, the model, the data, Zero Data
    Retention), plus `has_photo_ai_consent` and `get_my_photo_ai_notice`.
  - `physique_analyses.result/notice_version/confirmed_muscles/confirmed_at` (result checked by
    `private.is_valid_physique_result`), `persist_physique_analysis` (service role, audit
    `progress.physique_check.completed` with telemetry) and `set_my_priority_muscles` (audit
    `profile.priority_muscles.updated`).
  - `progress_vision` now counts toward the 30-a-day limit.
- **Server:** `physique-check/` (status and check modes), `_shared/physique/contract.ts`,
  `_shared/physique/jpeg.ts`, `_shared/providers/physique_vision_provider.ts`. Registered in
  `deploy.yml`, `hotfix.yml` and `config.toml`. `physique_analyses` is added to the privacy export.
- **App:** a physique check repository, plus the Progress photo card, consent, result and confirm
  sheets. The card says "Sent to Groq only when you start a physique check" only for accounts the
  function serves; for everyone else it still says "Never sent to AI", which stays true.

## Review fixes (before merge)

- A stored check and its disclosure load apart from current availability: switching the check off
  never makes the card claim photos were "never sent to AI".
- The newest photo set is chosen deterministically (`captured_on`, then `created_at`, then `id`).
- The JPEG cleaner walks the whole file: metadata between progressive scans and anything after the
  end marker are removed.
- Deleting a set reloads the stored check, so a deleted analysis can't be opened.
- Usage is recorded before the result is stored. A failed usage record is reported to Sentry but
  never turns a stored answer into a failure, since a retry would pay for another call.

## Deliberate deviations from the plan

- **Three photos, not four.** Groq's vision API takes at most three images per request, so the
  lower-body pose is not sent. Front, side and back show the whole body.
- **3 MB per photo, not 4 MB.** Groq takes base64 images up to 4 MB, and base64 grows a file by a
  third.
- **The repair is conditional and text-only.** One check uses about 7,600 of the free tier's 8,000
  tokens a minute. The correction never resends the photos, and runs only when Groq reports at least
  2,500 tokens left; otherwise the check fails honestly (nothing stored, tokens counted).
- **No onboarding card.** A new athlete has no photo set during onboarding, and the check needs a
  complete one. It lives in Progress; focus muscles chosen there replace the onboarding focus.
- **The HEIC conversion stays on the device.** The app already re-encodes every pick to JPEG
  (`image_picker`, quality 88, longest side 1800 px, `requestFullMetadata: false`). The server
  refuses anything that is not a JPEG and strips every metadata segment itself.

## Owner steps after merge (in order)

1. Wait for the deploy, then run `./scripts/verify-live-function.sh --all` from the merged commit
   (11 functions).
2. Groq console → Settings → Data Controls → turn on **Zero Data Retention** for the organization
   that owns `GROQ_API_KEY`. Record the date here: **ZDR proof: _not yet recorded_**.
3. Find your user ID (dashboard SQL editor, read-only):
   `select id from auth.users where email = '<your email>';`
4. Set the secrets in the Supabase dashboard (Edge Functions → Secrets): `PHYSIQUE_VISION_ENABLED`
   = `true`, then `PHYSIQUE_VISION_ALLOWED_USERS` = your ID. The provider and model default to
   `groq` / `qwen/qwen3.8-27b`. A secret change creates a new version of every function, so run
   `verify-live-function.sh --all` again afterwards.
5. Device test (build from merged main):
   1. Grant the photo notice and run the check twice on the same set. Note how repeatable it is,
      and compare it with ChatGPT's read.
   2. Confirm one or two muscles, then ask the Coach about your focus.
   3. Delete a photo set that has an analysis.
   4. Read-only SQL for the telemetry:
      `select created_at, metadata from audit_events where action_code = 'progress.physique_check.completed' order by created_at desc limit 5;`

**Rollback:** set `PHYSIQUE_VISION_ENABLED` to anything but `true` (or clear the allowlist), then
run verify-live `--all`. The app hides the check when status says disabled.

## Before any other account

A separate PR adds the evaluation in AI_SAFETY_SPEC §9 (body types and skin tones, pose, clothing,
lighting and pump, repeatability, wrong priorities, forbidden outputs, text in the image, and empty
or unrelated photos). Until then the allowlist holds only the owner.
