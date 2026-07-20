# Owner Groq Qwen test routing — 2026-07-11

Implemented and hosted ADR 0006: Groq `qwen/qwen3.6-27b` is the owner-test provider for controlled
Coach decisions/chat and JPEG/PNG meal-photo candidates. The provider key remains in Supabase Edge
Function secrets. The migration adds Groq metadata validation and a service-only USD 2 / 10
requests-per-day guard.

Verification: Edge Function format, lint, typecheck, and 35 tests pass; hosted migration history
matches local; three deployed endpoints return 401 without a session. Owner device smoke remains:
run a Coach decision/chat and one meal photo, then confirm/edit the candidates before testing the
next day's decision.

**Follow-up repair:** The initial Qwen Coach call recorded a failed provider run before any billable
Groq usage. Groq's current Qwen guidance requires instructions inside the user message rather than a
separate system message. The three Qwen routes were corrected and redeployed; 35 Edge Function
checks still pass. A fresh signed iPhone build with the Tracend launcher icon was installed and
launched.

**Root-cause verification and final repair:** A temporary server-only diagnostic used the stored
Groq key with no owner data. The minimal Qwen request returned HTTP 200; the real Coach adapter then
reached the strict validator but failed only when Qwen reasoning mode produced unpermitted evidence.
Qwen non-thinking JSON mode returned HTTP 200 and passed the same Coach schema/policy validation.
The diagnostic endpoint and temporary secret were deleted immediately. The production Coach/chat
routes now use this verified mode. Nutrition now offers Camera and Photo Library selection; a signed
build was installed and launched.

**Chat transparency repair:** Hosted `model_runs` showed a real Qwen chat success followed by a Qwen
validation failure that had been silently persisted as `deterministic-chat-fallback-v1`. The
fallback path is removed. Qwen gets one schema-repair retry; a second failure is recorded as a
failed `coach_chat` model run and the app shows a retryable unavailable state rather than generic
coaching prose. Immediate live replies are labeled `Qwen AI response`.
