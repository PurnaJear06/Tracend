# Coaching Platform Program (October 2026)

**Status:** approved by the owner on 2026-10-15. Iteration 1 (Phase 0 + Phase 1) is in progress.

This is the single source of truth for every agent working on the program. Read it fully before
touching code. If this document and an authority doc (`docs/*.md`) disagree, stop and report the
conflict on the board; do not choose silently.

## Goal

1. Run all AI on a provider-neutral gateway (Claude now; any provider later by settings alone).
2. Coach-grade, deterministic training rules: templates, progression from the sets actually
   logged, deloads, joint-friendly modifications, a screening gate.
3. Per-set timing and Apple Watch heart rate that build a personal profile.
4. Same-day re-plan from recovery, approved by the athlete with one tap.
5. A research library (RAG) behind Coach answers and plan explanations.
6. Widgets and a workout Live Activity (Lock Screen and Dynamic Island).
7. A global audience: regional nutrition and body-measure modules.

Rules decide every number. AI explains, proposes and words. Nothing a model says becomes durable
without validation, the athlete's approval and an audit event (CLAUDE.md, Architecture 1–3).

## Owner decisions (2026-10-14/15)

| # | Decision |
|---|---|
| D1 | Remove DeepSeek and Groq as defaults; move to Claude (Haiku 5.5 and Sonnet 5.5). Keep the old routes as a settings-only rollback for 2 weeks after cutover. |
| D2 | The AI layer is plug-and-play: one gateway, per-feature settings. |
| D3 | A research library over open papers, guidelines and in-house summaries in our own words. Paid course material (K11, NASM, ACE) is never stored. pgvector is allowed; the "no vector databases" rule is replaced by this program (E1 updates CLAUDE.md and ARCHITECTURE.md). |
| D4 | Embeddings: Supabase's built-in `gte-small` (384 dimensions), run inside Edge Functions. No new processor. Hybrid search with Postgres full-text closes most of the quality gap. |
| D5 | Global audience. Regional modules (India ICMR-NIN, US DGA, UK NICE, Australia) chosen by the athlete's region. |
| D6 | Knee, back and shoulder training modifications are in scope: swaps, range limits, a pain check, referral warning signs. No diagnosis, no rehab programs. |
| D7 | The beta waits until all four phases are merged and device-checked. No fixed date. |
| D8 | Claude builds with sub-agents; the owner merges. |
| D9 | Heart rate never sets the load. It raises or lowers confidence, informs rest, cardio dosing and recovery, and prompts a question. |
| D10 | Sleeping heart rate starts in shadow mode: computed and stored, not used in the recovery score until a later reviewed change. |
| D11 | Privacy and AI wording (owner, 2026-10-15): no model names anywhere the athlete or the public reads (app, notices, website, privacy policy). Remove every DeepSeek, Groq and Qwen mention. Name the receiving company only where disclosure is needed: one line in each AI consent notice and the privacy policy's processor list. Rewrite the notices and privacy pages for clarity. This is a beta exit criterion. |

## Phases and board

Strict order between phases. Chunks inside a phase run in parallel. Status values: `todo`,
`building`, `review`, `ready` (handed to the owner), `merged`, `live` (deployed and verified).

| Phase | Chunk | Stream | Goal | Migration code | Waits for | Status | PR |
|---|---|---|---|---|---|---|---|
| 0 | P0 | program | This doc, contracts, migration-order CI check | — | — | review | |
| 1 | B0 | training-engine | Mock decision obeys the policy; rules plan ranks by equipment and experience | — | P0 | review | |
| 1 | A1 | ai-gateway | Provider-neutral SQL, provider on notices, consent v2, budget v2 | 11 | P0 | todo | |
| 1 | A2 | ai-gateway | Gateway module and adapters, not wired to features | — | P0 | todo | |
| 1 | C1 | workout-hr | Set start/end, actual rest, reps-left, workout events | 31 | P0 | todo | |
| 1 | D0 | ios-widgets | Widget extension and rest-timer Live Activity (countdown only) | — | P0 | todo | |
| 1 | E1 | research-library | pgvector, library tables, `search_library_v1`, doc rule change | 41 | P0 | todo | |
| 1 | W1 | website | Site copy fixes, privacy policy naming Anthropic, TestFlight checklist | — | P0 | todo | |
| 2 | A3 | ai-gateway | Meal photo on Haiku, physique on Sonnet | 13 | A1, A2 | todo | |
| 2 | A4 | ai-gateway | Onboarding plan and questions on Sonnet | — | A1, A2 | todo | |
| 2 | A5 | ai-gateway | Daily decision on Sonnet | — | A1, A2, B0 | todo | |
| 2 | A6 | ai-gateway | Coach chat, cache-friendly prompt | — | A1, A2 | todo | |
| 2 | A7 | ai-gateway | Notices and app wording per D11 (no model names; remove DeepSeek/Groq/Qwen everywhere), evals, docs, cutover runbook | — | A3–A6 | todo | |
| 2 | D1 | ios-widgets | Live Activity with Done / Skip / +30s | — | C1, D0 | todo | |
| 2 | C2 | workout-hr | Native heart-rate reader, per-set summaries | 32 | C1, D0 | todo | |
| 2 | B1 | training-engine | Catalog v2 and coaching-standard rule data | 21 | B0 | todo | |
| 3 | B2 | training-engine | Templates by goal × days × experience; fractional volume | — | B1 | todo | |
| 3 | B3 | training-engine | Progression from actual sets; hub 1.7; Train shows targets | 23 | B2 | todo | |
| 3 | B6 | training-engine | Screening gate (own words, ACSM 2015 method) | 26 | B1 | todo | |
| 3 | C3 | workout-hr | Heart-rate profile, zones, recovery, sleeping HR (shadow) | 33 | C2 | todo | |
| 3 | D2 | ios-widgets | Today and Lock Screen widgets | — | D1 | todo | |
| 3 | E2 | research-library | Ingestion and the first 30 sources | — | E1 | todo | |
| 3 | E3 | research-library | Library inside Coach chat | 43 | A6, E2 | todo | |
| 4 | B4 | training-engine | Same-day readiness adjustment, one-tap approval | 24 | B3, C3 | todo | |
| 4 | B5 | training-engine | Deloads, cardio dosing, joint rules, pain check, red flags | 25 | B3 | todo | |
| 4 | C4 | workout-hr | Watch-workout prompt, load signals for the engine | — | C3 | todo | |
| 4 | E4 | research-library | Regional modules | 44 | E3 | todo | |
| 4 | E5 | research-library | Plan explanations citing sources | — | E3, B3 | todo | |

**Iteration 1 merge order:** P0 → B0 → A1 → C1 → A2 → E1 → D0 → W1.

## Collision rules

1. **Own worktree.** Each chunk works in `/Volumes/Crucial X9/dev/Tracend-<chunk>` (lower case,
   for example `Tracend-a2`) on branch `claude/<chunk>-<slug>` from `origin/main`, with `.tooling`
   symlinked to the primary checkout's. Never touch the primary checkout.
2. **Migration names** are `YYYYMMDDHHMMcc_<snake_name>.sql`. The last two digits `cc` are the
   chunk's code from the board, so two chunks can never produce the same version. A chunk with
   two migrations uses consecutive minutes.
3. **Re-stamp before handoff.** Right before the PR is handed to the owner, `git fetch` and run
   `./scripts/check-migration-order.sh origin/main`. If it fails, rename the new migration(s) to a
   current timestamp (keep the code) and push. CI runs the same check on every pull request.
4. **One owner per shared file per phase.** The table below is binding. If you need a change in a
   file you do not own, add a line under "Contract requests" and stop that part of the work.
5. **Frozen for the whole program** (no agent edits these SQL functions or files):
   `complete_workout_v2`, `prepare_coach_chat_v8`, `build_coach_athlete_context`,
   `health_sync_v1` contract, `persist_health_sync_v2`. New Coach context arrives through
   contributors (Contract 7); new set data through `sync_workout_draft` (Contract 2).
6. **Every new or changed RPC** returns `schema_version`, gets a fixture under `test/contract/`
   (if Flutter calls it) and a test that asserts its complete key list.
7. **Every new user-owned table** has RLS with `auth.uid()`, a pgTAP RLS test, and is added to
   `privacy-export` and account deletion in the same PR.
8. **Old app builds keep working.** Every column added is nullable or defaulted; every RPC change is
   additive; missing request keys keep the stored value.
9. **Local database.** Only one local Supabase stack runs at a time. Builders test SQL through CI
   pgTAP on their branch; the lead serialises any local run.
10. **No production actions.** No `db push`, no `functions deploy`, no secret changes, no merges.
11. **Docs in the same PR:** the stream's handoff file, this board's row (status and PR), and the
    stream's line inside the `PROGRAM:coaching-platform-2026-10` block of
    `docs/PROGRESS_CONTEXT.md`. Edit only your own lines.

### File owners (Phase 1)

| Path | Owner |
|---|---|
| `supabase/functions/_shared/providers/mock_coach_model_provider.ts`, `_shared/onboarding/rules_plan.ts`, `_shared/onboarding/catalog.ts` (ranking fields only) | B0 |
| `supabase/functions/_shared/ai_consent.ts`, `_shared/ai_budget.ts`, AI whitelist SQL | A1 |
| `supabase/functions/_shared/ai/**` (new) | A2 |
| `lib/features/train/**`, `lib/features/workout/**`, `sync_workout_draft`, `exercise_sets` | C1 |
| `ios/**` (project, Runner, new extension), `lib/shared/live_activity/**` (new) | D0 |
| `private.library_*`, `search_library_v1`, `CLAUDE.md` and `docs/ARCHITECTURE.md` vector-DB lines | E1 |
| `site/**`, `docs/BETA_OPERATIONS.md` | W1 |
| `.github/workflows/**`, `scripts/**` | lead only |
| `docs/plans/coaching-platform-2026-10/README.md` | everyone edits only their own board row and contract requests; the lead edits the rest |

D0 and C1 both touch the workout screen's rest timer: C1 owns `lib/features/**`; D0 exposes a
`WorkoutActivityBridge` and C1 calls it in Phase 2 (D1). In Phase 1 D0 starts and ends the Live
Activity from `rest_timer.dart` through one call site that C1 reviews.

## Contracts (version 1)

A contract changes only by a new version entry here, approved by the lead. Builders implement the
shape exactly.

### Contract 1: AI gateway (`supabase/functions/_shared/ai/`), version 2

```ts
type AiFeature =
  | "coach_chat" | "daily_decision" | "onboarding_plan" | "onboarding_questions"
  | "meal_vision" | "physique_vision" | "library_context";
type AiProvider = "anthropic" | "openai_compatible" | "gemini";   // wire protocol
// Who receives the data. Stored in SQL whitelists, notices and consent; a notice names a vendor.
// "router" is for synthetic evals through an OpenAI-compatible router; no notice names it.
type AiVendor = "anthropic" | "deepseek" | "groq" | "gemini" | "router";

type AiRoute = Readonly<{
  feature: AiFeature;
  provider: AiProvider;
  vendor: AiVendor;               // from the model table; DeepSeek/Groq hosts are pinned per vendor
  providerLabel: string;          // shown in notices, e.g. "Claude (Anthropic)"
  model: string;
  baseUrl?: string;               // openai_compatible only; must match the vendor's host, any https host for "router"
  thinking: "off" | "adaptive";   // mapped per model; Sonnet 5.5 "off" = between_tools
  effort?: "low" | "medium" | "high";
  maxOutputTokens: number;
  timeoutMs: number;
  evaluated: boolean;             // false = eval not yet passed; features may refuse
}>;

// Reads AI_<FEATURE>_{PROVIDER,MODEL,BASE_URL,THINKING,EFFORT,MAX_OUTPUT_TOKENS,TIMEOUT_MS,EVALUATED}
// and the provider's key (ANTHROPIC_API_KEY, OPENAI_COMPATIBLE_API_KEY_<FEATURE>, GEMINI_API_KEY).
// Returns null when the feature has no complete route: the feature takes its existing rules path.
function route(feature: AiFeature, env?: (name: string) => string | undefined): AiRoute | null;

type AiContent =
  | { type: "text"; text: string; cache?: boolean }   // cache = end of a cacheable prefix
  | { type: "image"; mediaType: "image/jpeg"; base64: string };

type AiRequest = Readonly<{
  route: AiRoute;
  system: AiContent[];            // stable first, so prefixes cache
  messages: { role: "user" | "assistant"; content: AiContent[] }[];
  output: { kind: "text" } | { kind: "json"; schema: Record<string, unknown> };
  consentVendor: AiVendor | null;     // vendor named by the athlete's accepted notice
  signal?: AbortSignal;
}>;

type AiUsage = Readonly<{
  inputTokens: number; outputTokens: number;
  cacheReadTokens: number; cacheWriteTokens: number;
  costUsd: number;                // from the model price table; list prices, never guessed
}>;

type AiResult =
  | { ok: true; text: string; json?: unknown; usage: AiUsage; model: string; stop: "end" | "max_tokens" }
  | { ok: false; reason: AiFailure; usage: AiUsage | null; retryAfterSeconds?: number };

type AiFailure =
  | "consent_provider_mismatch"   // no request sent
  | "refused"                     // provider safety refusal (stop_reason "refusal")
  | "rate_limited" | "overloaded" | "timeout" | "network"
  | "invalid_output"               // JSON did not parse or match the schema
  | "provider_error";

function call(request: AiRequest, deps?: { fetch?: typeof fetch; now?: () => number }): Promise<AiResult>;
```

Rules:
- Never sends `temperature`, `top_p` or a forced `tool_choice` to Claude 5 models. Structured output
  uses `output_config.format` (JSON schema).
- Refuses before sending when `consentVendor !== route.vendor` (`consent_provider_mismatch`).
- Rollback parity: OpenAI-compatible and Gemini requests send what today's providers send
  (per-model request defaults such as `temperature: 0.1`, the JSON schema restated in the system
  prompt for JSON mode). Claude 5 requests never carry sampling parameters.
- Budget is the caller's job (`AiBudget.reserve` before `call`, release or keep after), unchanged.
- Logs one scrubbed `ai_call` line per call: feature, provider, model, outcome, token counts, cost,
  latency. Never prompt text, image data or reply text.
- Prices live in one table in `_shared/ai/models.ts` (per MTok input, output, cache read, cache
  write, and the Haiku 5.5 long-prompt tier).

### Contract 2: Set data (C1)

`public.exercise_sets` gains nullable columns:

| Column | Type | Rule |
|---|---|---|
| `started_at` | `timestamptz` | when the set began (first tap or the end of the previous rest) |
| `completed_at` | `timestamptz` | when it was ticked; `>= started_at` |
| `rest_before_seconds` | `integer` | actual rest before this set, 0–3600 |
| `rir` | `smallint` | reps in reserve 0–5 (5 means "5 or more") |
| `timing_source` | `text` | `app` or `watch` |

`sync_workout_draft(session_id, client_revision, draft)` keeps its signature. Each set object may
carry `started_at`, `completed_at`, `rest_before_seconds`, `rir`, `timing_source`. A missing key
keeps the stored value (older builds send none). Invalid values raise `22023`. Times more than 10
minutes in the future or more than 10 minutes before the session's recorded start are rejected
(the allowance absorbs small phone/server clock differences). If the server refuses timing, the app
resends the draft without the timing keys, so logged sets are never blocked by a clock error. `get_my_workout_session` and
`get_my_exercise_history` return the new fields (additive). `rpe` stays; the app stops asking for
it only when `rir` is shown.

### Contract 3: Workout events and commands (Dart, C1 defines, D0/D1/C2 consume)

```dart
sealed class WorkoutEvent { DateTime get at; }
final class SetStarted extends WorkoutEvent { int exerciseOrder; int setNumber; }
final class SetCompleted extends WorkoutEvent { int exerciseOrder; int setNumber; int? reps; double? loadKg; int? rir; }
final class RestStarted extends WorkoutEvent { int seconds; DateTime endsAt; String nextLabel; }
final class RestAdjusted extends WorkoutEvent { DateTime endsAt; }
final class ExerciseAdvanced extends WorkoutEvent { int exerciseOrder; String name; }
final class WorkoutEnded extends WorkoutEvent { bool completed; }

sealed class WorkoutCommand {}
final class CompleteCurrentSet extends WorkoutCommand {}
final class SkipRest extends WorkoutCommand {}
final class AddRest extends WorkoutCommand { int seconds; }   // +30 from the Live Activity
```

One `Stream<WorkoutEvent>` per active session and one command sink. The Live Activity and the
heart-rate reader only listen; they never write sets.

### Contract 4: Per-set heart rate (C2)

`persist_set_heart_rate_v1(session_id uuid, summaries jsonb)` (authenticated, own sessions), one
row per set in `public.exercise_set_heart_rate`: `exercise_set_id`, `start_bpm`, `peak_bpm`,
`end_bpm`, `drop_30s_bpm`, `drop_60s_bpm`, `coverage` (0–1 share of the set and the following
60 s with samples), `sample_count`, `source` (`watch_workout` or `background`). Summaries only;
raw samples never leave the phone.

### Contract 5: Readiness adjustment (B4)

`get_my_day_adjustment_v1(local_date date)` returns
`{schema_version, band: "green"|"amber"|"red"|"unknown", triggers: text[], kind: "none"|"reduce_sets"|"hold_load"|"swap_to_easy_cardio", changes: [{exercise_order, sets_from, sets_to, load_note}], explanation, status: "proposed"|"accepted"|"declined"|"none"}`.
`respond_to_day_adjustment_v1(local_date date, accept boolean)` records the answer with an audit
event and returns the updated object.

### Contract 6: Library search (E1)

`search_library_v1(query_text text, query_embedding vector(384), match_count int, filters jsonb)`
is `security definer`, executable by `service_role` only. Hybrid: full-text top 30 and vector top
30 merged by reciprocal rank fusion (k = 60). Returns rows
`{chunk_id, source_id, title, year, url, section, body, header, score}`. `filters` may hold
`region` and `topics` (text arrays). `match_count` is capped at 8.

### Contract 7: Coach context contributor (A6 defines the host, E3/C3/B3 add contributors)

```ts
type CoachContextContributor = Readonly<{
  id: string;                         // e.g. "library", "heart_rate_profile"
  slot: "stable" | "volatile";        // stable = cached prefix; volatile = after the athlete file
  budgetChars: number;
  render(input: { userId: string; question: string; localDate: string }): Promise<string | null>;
}>;
```

The host renders contributors after the frozen athlete file, in a fixed order, each clipped to its
budget, labelled as reference data that never overrides Tracend rules or the athlete's data.

## Chunk briefs: Iteration 1

Every brief adds: read this doc, `CLAUDE.md`, `docs/PROGRESS_CONTEXT.md`, and the stream's handoff.

**B0: decision and plan bug fixes.** Fix `mock_coach_model_provider.ts` so it never returns an
action the active policy forbids (PROCEED under `request_data`, ADJUST_TODAY under
`maintain_only`); a property test runs every policy against the decision contract. Fix the rules
plan's exercise choice (`rules_plan.ts`, catalog order puts bodyweight first): rank candidates by
the athlete's equipment and experience so a full-gym lifter gets barbell or dumbbell compounds.
Golden tests for full gym, dumbbells only, and bodyweight only. Edge Functions only; no app change.

**A1: provider-neutral database.** One migration (code 11).
- Every SQL provider whitelist (persist RPCs and check constraints that name `deepseek`, `groq`,
  `gemini`) accepts the vendor id `anthropic` in addition to today's values (Contract 1 v2).
- `ai_consent_notices` gains `provider` (nullable for old rows); `photo_ai_notices` and
  `meal_photo_ai_notices` accept `anthropic`.
- `get_ai_consent_v2(target_user_id, purpose)` returns `{granted, provider, notice_version}` for the
  current notice; `has_ai_coaching_consent` keeps working.
- `reserve_ai_budget_v2(target_user_id, run_purpose, ceiling_usd)`: the caller passes the per-call
  ceiling from the route; limits stay in `private.ai_budget_limits`. The old function is unchanged.
- `ai_consent.ts` gains `aiConsentWithProvider`; `ai_budget.ts` gains an optional ceiling. Existing
  callers compile and behave the same. pgTAP for every new function.

**A2: AI gateway.** New `supabase/functions/_shared/ai/` implementing Contract 1: `routes.ts`,
`models.ts` (prices and capabilities), `gateway.ts`, `adapters/anthropic.ts`,
`adapters/openai_compatible.ts`, `adapters/gemini.ts`, `log.ts`. Offline tests with a fake fetch:
no temperature sent to Claude 5, thinking mapping per model, cache-token cost maths, refusal,
429 with `retry-after`, 529, timeout, invalid JSON, consent mismatch sends nothing. No feature
uses it yet. Reuse the request shapes in `onboarding_plan_provider.ts`, `groq_*` and `gemini_*`
providers.

**C1: set timing.** Migration (code 31) per Contract 2, including the new `sync_workout_draft`.
In the app: record `started_at`/`completed_at` per set, save the actual rest, add a reps-left
picker (0–5) per set, and publish Contract 3 events from the workout controller. Contract fixtures
for `get_my_workout_session` and `get_my_exercise_history`. Widget tests for the picker; a unit
test for rest maths across app backgrounding.

**D0: widget extension and rest Live Activity.** Before writing code, the lead confirms the free
team can sign a second bundle ID. Add a WidgetKit extension target (`TracendWidgets`) with an
ActivityKit `RestActivityAttributes` (ends at, next set label). `lib/shared/live_activity/`
exposes `WorkoutActivityBridge.startRest/updateRest/end` over a method channel in
`SceneDelegate`. The countdown uses `Text(timerInterval:)` so it runs with the app closed. No
buttons, no App Group, no push. `build ios --release --no-codesign` and a signed install on the
iPhone 18 are the gates.

**E1: library tables.** First, a local spike: `create extension vector` and `Supabase.ai.Session("gte-small")`
in an Edge Function on the local stack. Then a migration (code 41): enable `vector`;
`private.library_sources`, `private.library_chunks` (body, header, `embedding vector(384)`,
generated `tsvector`, HNSW and GIN indexes), `private.library_ingest_runs`; `search_library_v1`
per Contract 6; pgTAP for ranking on a seeded fixture. Update `CLAUDE.md`, `ARCHITECTURE.md` and
`IMPLEMENTATION_ROADMAP.md` to replace the "no vector databases" rule with D3. Add `private` table
reset to the restore drill if needed. No ingestion yet.

**W1: website.** Apply D11 to the site and privacy policy (no model names, Anthropic named once as
the AI processor, plain-language rewrite). Fix the copy contradictions found on 2026-10-14: "progress photos are private"
next to AI processing (say what is processed and by whom), name Anthropic as an AI processor in
the privacy page, iOS only (no "Android in testing"), the physique check shown as coming later.
Add the TestFlight checklist to `docs/BETA_OPERATIONS.md`. Follow `site/PRODUCT.md` claim rules.

## Review loop (every chunk)

1. Builder implements in its worktree and runs the stream's tests plus `./scripts/pre-deploy.sh`
   (or `--skip-colima --skip-reset` with CI pgTAP).
2. A separate reviewer agent checks: contract match, frozen files untouched, old-build safety,
   RLS and export/deletion, tests that exercise the change, docs updated.
3. Builder fixes findings, pushes, and opens the PR. All required checks must be green.
4. The lead verifies against this doc, re-stamps if needed, and hands the PR to the owner.

## Contract requests

None yet.

## Decisions log

- 2026-10-15: program approved; Iteration 1 = Phase 0 + Phase 1.
- 2026-10-15: Contract 1 v2. Consent compares a vendor id (`anthropic`, `deepseek`, `groq`,
  `gemini`), not the wire protocol, so a DeepSeek notice can never pass a Groq route. SQL stores
  vendor ids only (A1 adds `anthropic`; `openai_compatible` is never stored). Eval routers use
  vendor `router`, which no notice names. Resolves A2's contract request.
- 2026-10-15: D11 (no model names in user-facing text). App files that name providers today:
  `lib/shared/ai_provider_names.dart`, `lib/features/consent/ai_coaching_consent.dart`,
  `lib/features/coach/coach_labels.dart`, `lib/features/onboarding/onboarding_proposal_view.dart`;
  notice bodies are rows the owner publishes (A7 drafts them).
- 2026-10-15 (owner): the website keeps "Android in testing" and shows the physique check as live
  (13 Oct notes stand); "For iPhone, best with Apple Watch" (never Watch-only); the glass tab bar's
  sheen and fade are an allowed exception to the gradients-in-data-only rule; full-gym plans default
  to lat pulldowns, with pull-ups returning as a variation in B2.
- 2026-10-15: beta exit criterion. Health data must not go to DeepSeek once external testers join
  (App Review 5.1.3; DeepSeek's API terms give no clear no-training/retention position). Phase 2
  cutover moves every feature to Anthropic before the external TestFlight group opens; the privacy
  processor list drops DeepSeek and Groq after the rollback window.
- 2026-10-15: migration-order check added to the Migration Collision Check job
  (`scripts/check-migration-order.sh`).
