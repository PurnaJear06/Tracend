# Coaching Platform Program (October 2026)

**Status:** approved by the owner on 2026-10-15. Iteration 1 (Phase 0 + Phase 1) is merged and
live; the owner's device check passed on 2026-10-15. Iteration 2 (Phase 2) is merged (2026-10-16); the
Claude cutover follows `docs/runbooks/phase2-claude-cutover.md`. Iteration 3 (Phase 3) round 1
(U3, B2, B6) merged on 2026-10-17; rounds 2 and 3 are next.

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
| D9 | Heart rate never sets the load. It raises or lowers confidence, informs rest, cardio dosing and recovery, and prompts a question. Clarified by the owner (2026-10-23, O1): heart rate informs and offers, the athlete decides. The recovery score (built from heart-derived signals) never applies or pre-selects a same-day adjustment by itself; it tells the athlete what it shows, opens the check-in and the option to talk it through with Coach, and the athlete may then choose an adjustment themselves with one tap and Undo. |
| D10 | Sleeping heart rate starts in shadow mode: computed and stored, not used in the recovery score until a later reviewed change. |
| D11 | Privacy and AI wording (owner, 2026-10-15): no model names anywhere the athlete or the public reads (app, notices, website, privacy policy). Remove every DeepSeek, Groq and Qwen mention. Name the receiving company only where disclosure is needed: one line in each AI consent notice and the privacy policy's processor list. Rewrite the notices and privacy pages for clarity. This is a beta exit criterion. |

## Phases and board

Strict order between phases. Chunks inside a phase run in parallel. Status values: `todo`,
`building`, `review`, `ready` (handed to the owner), `merged`, `live` (deployed and verified).

| Phase | Chunk | Stream | Goal | Migration code | Waits for | Status | PR |
|---|---|---|---|---|---|---|---|
| 0 | P0 | program | This doc, contracts, migration-order CI check | — | — | live | #102 |
| 1 | B0 | training-engine | Mock decision obeys the policy; rules plan ranks by equipment and experience | — | P0 | live | #105 |
| 1 | A1 | ai-gateway | Provider-neutral SQL, provider on notices, consent v2, budget v2 | 11 | P0 | live | #103 |
| 1 | A2 | ai-gateway | Gateway module and adapters, not wired to features | — | P0 | live | #106 |
| 1 | C1 | workout-hr | Set start/end, actual rest, reps-left, workout events | 31 | P0 | live | #104 |
| 1 | D0 | ios-widgets | Widget extension and rest-timer Live Activity (countdown only) | — | P0 | live | #112 |
| 1 | E1 | research-library | pgvector, library tables, `search_library_v1`, doc rule change | 41 | P0 | live | #109 |
| 1 | W1 | website | Site copy fixes, privacy policy naming Anthropic, TestFlight checklist | — | P0 | merged | #108 |
| 1 | U1 | ui | Glass tab bar (owner request 2026-10-15) | — | P0 | live | #107 |
| 2 | A3 | ai-gateway | Meal photo on Haiku, physique on Sonnet | 13 | A1, A2 | merged | #119 |
| 2 | A4 | ai-gateway | Onboarding plan and questions on Sonnet | — | A1, A2 | merged | #122 |
| 2 | A5 | ai-gateway | Daily decision on Sonnet | — | A1, A2, B0 | merged | #117 |
| 2 | A6 | ai-gateway | Coach chat, cache-friendly prompt | — | A1, A2 | merged | #120 |
| 2 | A7 | ai-gateway | Notices and app wording per D11 (no model names; remove DeepSeek/Groq/Qwen everywhere), budget limits, evals, docs, cutover runbook | 17 | A3–A6 | merged | #124 |
| 2 | D1 | ios-widgets | Live Activity with Done / Skip / +30s | — | C1, D0 | merged | #121 |
| 2 | C2 | workout-hr | Native heart-rate reader, per-set summaries | 32 | C1, D0 | merged | #123 |
| 2 | B1 | training-engine | Catalog v2 and coaching-standard rule data | 21 | B0 | merged | #118 |
| 3 | U3 | ui | Launch speed: tabs load on first open, shared reads, photo decode size, measured baseline | — | — | merged | #126 |
| 3 | B2 | training-engine | Templates by goal × days × experience; fractional volume | — | B1 | merged | #127 |
| 3 | B3 | training-engine | Progression from actual sets; hub 1.7; Train shows targets | 23 | B2 | merged | #132 |
| 3 | B6 | training-engine | Screening gate (own words, ACSM 2015 method) | 26 | B1 | merged | #128 |
| 3 | B7 | training-engine | Goal phase review, athlete-set targets, no projection as a goal in Coach chat | 27 | B2 | merged | #136, #141 |
| 3 | C3 | workout-hr | Heart-rate profile, zones, recovery, sleeping HR (shadow) | 33 | C2 | merged | #133 |
| 3 | D2 | ios-widgets | Today and Lock Screen widgets | — | D1 | todo | |
| 3 | E2 | research-library | Ingestion, the first 30 sources and the retrieval test set | 42 | E1 | merged | #135 |
| 3 | E3 | research-library | Library inside Coach chat | 43 | A6, E2 | todo | |
| 3 | A8 | ai-gateway | Coach proposals: Coach proposes a change in chat (`proposal_intent`), rules compute every number, the athlete approves with one tap, a new version and an audit event are written, undo for 7 days; temporary blocks end by themselves | 18 | A6, B7 | merged | #148 |
| 3 | A9 | ai-gateway | Coach safety and honesty: pre-model red-flag screen, numbers grounding, safety floors, plain error messages, local date, no-plan chat | 19 | B7 | merged | #143, #142 |
| 3 | A10 | ai-gateway | Coach memory: confirmed facts, athlete state, coach notes, a new context assembler (v9) | 20 | B7, A9 | todo | |
| 3 | A11 | ai-gateway | Coach eval bank: synthetic athletes that gate every Coach change | — | B7 | todo | |
| 4 | B4 | training-engine | Same-day readiness adjustment, one-tap approval (B4-1 server in review; B4-2 app next) | 24 | B3, C3 | review | #165 |
| 4 | B5 | training-engine | Deloads, cardio dosing, joint rules, pain check, red flags | 25 | B3 | todo | |
| 4 | C4 | workout-hr | Watch-workout prompt, load signals for the engine | 34 | C3 | review | |
| 4 | E4 | research-library | Regional modules | 44 | E3 | review | #164 |
| 4 | E5 | research-library | Plan explanations citing sources | — | E3, B3 | todo | |

| 5 | L1 | lifestyle | Lifestyle log: alcohol, smoking and vaping, cannabis and other substances (during beta) | 51 | beta start | todo | |
| 5 | L2 | lifestyle | Hydration: water target and log, Apple Health water | 52 | beta start | todo | |
| 5 | L3 | lifestyle | Health history: conditions and medications in onboarding (structured, not report analysis) | 53 | beta start | todo | |

**Iteration 1 merge order:** P0 → B0 → A1 → C1 → A2 → E1 → D0 → W1.

**Iteration 2 merge order:** P2 (kickoff docs) → B1 → A3 → A5 → A6 → D1 → A4 → C2 → A7. C2 is
stacked on D1's branch (both change the Xcode project and the workout screen).

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
11. **Docs in the same PR:** your chunk's own section of the stream's handoff file, and any
    authority doc your chunk changes the behaviour of. From Iteration 2 the lead stamps this
    board's row and the `PROGRAM:coaching-platform-2026-10` lines of `docs/PROGRESS_CONTEXT.md` on
    your branch right before the merge, so parallel PRs never conflict on them.

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

### File owners (Phase 2)

| Path | Owner |
|---|---|
| `meal-analyze/**`, `physique-check/**`, `_shared/physique/**`, `_shared/providers/{groq_meal_vision,gemini_meal_vision,physique_vision}_provider*.ts`, new `_evals/{meal_vision,physique}_*` | A3 |
| `onboarding-plan/**`, `onboarding-propose-plan/**`, `_shared/providers/onboarding_plan_provider.ts`, `_shared/onboarding/questions.ts`, `_evals/onboarding_plan_eval.ts` | A4 |
| `coach-decide/**`, `_shared/providers/{daily_decision,coach_model,create_coach_model,deepseek_coach_model,groq_coach_model,gemini_coach_model}_provider*.ts`, new `_evals/daily_decision_*` | A5 |
| `coach-chat/**`, `_shared/providers/coach_chat_provider*.ts`, `_shared/coach_chat_fallback*.ts`, new `_shared/coach_context/**` (Contract 7 host), `_evals/{coach_chat_eval*,fixtures.ts,prompts.json}` | A6 |
| `lib/shared/ai_provider_names.dart`, `lib/features/consent/**`, `lib/features/coach/coach_labels.dart`, `lib/features/onboarding/onboarding_proposal_view.dart`, `lib/features/progress/widgets/photo_widgets.dart`, `lib/features/progress/progress_screen.dart` (wording only), `_shared/ai_budget*.ts`, `_shared/ai_consent*.ts`, AI authority-doc sections (AI_SAFETY_SPEC §10, COST_MODEL, ARCHITECTURE §3.7, SECURITY_PRIVACY processors, PRD §5.8) | A7 |
| `ios/**` (project, Runner, extension), `lib/shared/live_activity/**`, `lib/features/train/**` | D1 |
| `ios/Runner/Native/HeartRateReader.swift` (new; stacked on D1, so D1's project file is the base), `lib/features/health/**`, new `lib/features/workout_hr/**`, one listener call site in `lib/features/train/` that D1 reviews | C2 |
| `_shared/onboarding/catalog*.ts` (catalog v2; existing exports keep their shape), new `_shared/training/standard/**` | B1 |
| `_shared/ai/**` (gateway, routes, models), `_shared/providers/deepseek_models.ts`, `.github/workflows/**`, `scripts/**`, `supabase/config.toml` | lead only (file a contract request) |
| Board rows and `PROGRAM:` lines in `docs/PROGRESS_CONTEXT.md` | lead (rule 11) |

Everyone else reads `catalog.ts`, `coach_chat_fallback.ts` and `deepseek_models.ts` but does not edit
them. Until A7, A3–A6 leave the AI authority-doc sections alone: production keeps today's providers
until the cutover, so those sections stay true.

### File owners (Phase 3, round 1)

| Path | Owner |
|---|---|
| `lib/features/shell/**`, `lib/features/progress/widgets/photo_widgets.dart`, read sharing inside the existing repositories under `lib/features/**` (callers see no change), new `test/perf/**` | U3 |
| `_shared/onboarding/{rules_plan,policy,generate,plan_contract}*.ts` (plan contract additive only), `_shared/onboarding/catalog_plans_test.ts` digests, new `_shared/training/templates/**`, `docs/ALGORITHMS.md` §9 | B2 |
| `_shared/training/screening/**` (Contract 8 type is fixed), migration code 26, `lib/features/onboarding/{onboarding_flow,onboarding_repository}.dart`, `_shared/onboarding/answers*.ts`, privacy export and deletion for its table | B6 |

U3 leaves `lib/features/onboarding/**` alone. B6 merges after B2; after rebasing it adds the one call
that passes the stored outcome into `policiesFor` (B2's file, reviewed by the lead).

### File owners (Phase 4)

| Path | Owner |
|---|---|
| migration code 24 (`day_adjustments`), `workout_sessions.day_adjustment_id`, `public.get_my_day_adjustment_v1`, `respond_to_day_adjustment_v1`, the redefinitions of `start_workout`, `private.progression_decision` and `private.next_session_targets`, new `_shared/training/readiness/**`, `_shared/training/standard/sources.ts` (new sources only), `privacy-export` (its tables), the `day_adjustment_*` contract fixtures and tests | B4-1 |
| new `lib/features/readiness/**`, `lib/features/today/{today_screen,today_session_progress}.dart`, `lib/features/train/**`, `lib/shared/plan_changes.dart` | B4-2 |
| migration code 25 (`pain_reports`, deloads, cardio), `save_daily_check_in`, `private.day_adjustment_compute` (joint rules from B5-1), new `_shared/training/{joints,standard/deload.ts}`, `_shared/coach_proposals/training.ts` (the deload branch), `lib/features/today/check_in_sheet.dart`, `lib/features/readiness/**` after B4-2 | B5 |
| `_shared/coach_context/**` (a `readiness` contributor), `coach-chat/**`, `coach-decide/**`, `_shared/coach_proposals/**` (except B5's deload branch), the A9 red-flag screen | ai-gateway (see the contract requests) |
| `.github/workflows/**`, `scripts/**`, `supabase/config.toml`, board rows and `PROGRAM:` lines | lead only |

B4-1 does not edit `_shared/coach_context/contributors/training_plan.ts` (C4 owns it in review).

### File owners (Phase 3, round 2)

| Path | Owner |
|---|---|
| new `_shared/training/progression/**`, `lib/features/train/**`, migration code 23 (a new training-hub version, 1.7, additive), its contract fixture, new `_shared/coach_context/contributors/progression.ts` | B3 |
| new `_shared/training/heart_rate/**`, `lib/features/workout_hr/**`, `lib/features/health/**`, `ios/Runner/Native/HeartRateReader.swift`, migration code 33, new `_shared/coach_context/contributors/heart_rate.ts` | C3 |
| new `supabase/library/**` (source content), new `_shared/library/**`, migration code 42, new `_evals/library_*`, a new embedding Edge Function if the design needs one | E2 |
| `_shared/coach_context/registry.ts`, `.github/workflows/**`, `scripts/**`, `supabase/config.toml` | lead only (file a contract request) |

B3 and C3 write their Contract 7 contributor modules with tests but do not register them; the
registry changes with E3 in round 3, so the Coach prompt does not change in round 2.

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

### Contract 3: Workout events and commands (Dart, C1 defines, D0/D1/C2 consume), version 1.1

```dart
sealed class WorkoutEvent { DateTime get at; }
final class SetStarted extends WorkoutEvent { int exerciseOrder; int setNumber; }
final class SetCompleted extends WorkoutEvent { int exerciseOrder; int setNumber; int? reps; double? loadKg; int? rir; }
final class RestStarted extends WorkoutEvent { int seconds; DateTime endsAt; String nextLabel; }
final class RestAdjusted extends WorkoutEvent { DateTime endsAt; }
final class ExerciseAdvanced extends WorkoutEvent { int exerciseOrder; String name; }
final class WorkoutEnded extends WorkoutEvent { bool completed; }

sealed class WorkoutCommand {}
final class CompleteCurrentSet extends WorkoutCommand { int exerciseOrder; int setNumber; }   // v1.1 (D1)
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

### Contract 5: Readiness adjustment (B4), version 1.0 as built (B4-1)

`get_my_day_adjustment_v1(local_date date)` returns
`{schema_version, band: "green"|"amber"|"red"|"unknown", triggers: text[], kind: "none"|"reduce_sets"|"hold_load"|"swap_to_easy_cardio", changes: [{exercise_order, sets_from, sets_to, load_note}], explanation, status: "proposed"|"accepted"|"declined"|"none"}`.
`respond_to_day_adjustment_v1(local_date date, accept boolean)` records the answer with an audit
event and returns the updated object.

As built, only today (the athlete's own local date) can be read or answered. The keys above are
kept exactly; everything else is additive: each change also carries `planned_exercise_id`, `name`,
`load_kg_from`, `load_kg_to`, `reps_from`, `reps_to` and `rpe_to`; the object adds `available`,
`unavailable_reason` (`no_plan`, `rest_day`, `session_started`, `session_done`, `coach_adjusted`),
`safety_route` (`pain_referral`), `confidence`, `missing`, `cardio`, `planned_workout_id`,
`workout_name`, `sets_total_from`, `sets_total_to`, `previous_answer` (`kind`, `status`,
`answered_at`, `reason`: `check_in` or `new_data`), `answered_at`,
`rules_version`, `origin` (`proposed` or `chosen`), `options` (every kind the athlete may choose,
with its own changes and sentence) and `signals` (what the recovery score and sleep show).
The training hub is 1.8 (the sessions inside a target's basis gain `adjusted` and `sets_planned`).
`respond_to_day_adjustment_v1(local_date, accept, chosen_kind text default null)` takes a third,
optional argument: with `accept = true` and a `chosen_kind` from `options` the athlete applies a
kind of their own choosing (D9); `accept = false` declines or undoes (Undo) until the session
starts. Errors: 42501 signed out; 22023 another date, nothing to answer, a kind that would change
nothing, or a safety day; 55000 the day cannot be adjusted; P0001 more than 20 answers a day. Old
builds never call these functions and see no change.

### Contract 6: Library search (E1), version 1.1

`search_library_v1(query_text text, query_embedding public.library_embedding, match_count int, filters jsonb)`
is `security definer`, executable by `service_role` only. `public.library_embedding` is a domain
over `extensions.vector(384)`; callers pass the same JSON array of 384 numbers. v1.1 reason:
`supabase db dump` strips GRANT/REVOKE lines that mention the `extensions` schema, so a function
with a plain `vector` argument came back from a restore executable by `anon` and `authenticated`. Hybrid: full-text top 30 and vector top
30 merged by reciprocal rank fusion (k = 60). Returns rows
`{chunk_id, source_id, title, year, url, section, body, header, score}`. `filters` may hold
`region` and `topics` (text arrays). `match_count` is capped at 8.

**Version 2 (E3, migration code 43, for the lead's approval).** `search_library_v2(query_text,
query_embedding, match_count, filters, target_user_id uuid default null)` replaces v1, which is
dropped (nothing deployed called it). Full-text search ORs the terms of the question; fusion is
reciprocal rank fusion with k = 50; rows add `source_key` (the manifest key Coach cites) and carry
`schema_version` 2; at most three rows per source; `match_count` is capped at 10 (null means 8);
`target_user_id` limits the sources to the athlete's regions (global plus the country in the account
locale, and `IN` for an Indian time zone) when `filters` names no region. Details: DATA_MODEL.md
section 12. From E4 (migration `20261023120044`, no signature change) the athlete's stored
`user_accounts.country_code` replaces that locale and time-zone guess when it is set.

**Version 3 (E3 production pass, migration code 44, for the lead's approval).**
`search_library_v3(query_text, query_embedding, query_embedding_model, match_count, filters,
target_user_id uuid default null)` is added beside v2, which stays for the deployed Coach chat until
a cleanup migration. Same search, plus: vector search compares only chunks embedded with
`query_embedding_model` (required with an embedding); rows add `evidence_level`, `kind`,
`vector_distance` (cosine distance to the question), `text_rank` (`ts_rank`, 0 when no term
matched) and `library_version` (`private.library_version()`), and carry `schema_version` 3. Coach
chat applies the relevance floor to these rows (`_shared/library/retrieval.ts`). Details:
DATA_MODEL.md section 12.

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

**Version 1.1 (E3, for the lead's approval).** `render`'s input gains the optional
`previousQuestions?: readonly string[]`: the athlete's own earlier questions in the conversation,
newest first, current question excluded. The library uses it to give a follow-up a topic; a
contributor that does not need it ignores it. Coach chat's evidence also gains the source `library`
(an evidence item whose `code` is a library source id shown in the turn; `coach_chat_v1.ts`).

**Version 1.2 (E3 production pass, for the lead's approval).** Two optional additions. `render`'s
input gains `queryEmbedding?: { text, startedAt, embedding }`: the question's library embedding,
started at the beginning of the request (the library reuses it when its query is that text). A
contributor may return `trace` (names and numbers only, never content) beside `text` and `shown`;
the host passes it on as `traces[id]`, and Coach chat logs the library's as `library_retrieval`.

### Contract 8: Screening outcome (B6 produces, B2 reads)

`_shared/training/screening/outcome.ts`: `ScreeningOutcome = "cleared" | "moderate_until_cleared" |
"see_professional"`. `PlanPolicies` gains an optional `screening`; missing means `cleared`.
`moderate_until_cleared` caps the plan at moderate effort (no strength emphasis, at least 3 reps in
reserve, no vigorous conditioning). `see_professional` builds no plan and takes today's excluded
path (professional guidance, nothing built).

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

## Chunk briefs: Iteration 2 (Phase 2)

Every brief adds: read this doc, `CLAUDE.md`, `docs/PROGRESS_CONTEXT.md`, the stream's handoff, and
the authority docs your chunk touches.

**A3–A6 share these rules (switch one feature to the gateway).**
- Call the gateway (Contract 1) when `route(feature)` returns a route. When it returns null, the
  feature runs today's path unchanged: same provider, same request (a parity test proves it).
  Production keeps today's providers until A7's cutover sets the `AI_<FEATURE>_*` settings, so
  merging and deploying changes nothing for the athlete.
- With a route, read consent through `get_ai_consent_v2` / `aiConsentWithProvider` and pass the
  vendor as `consentVendor`. A mismatch sends nothing and takes the feature's existing
  consent-needed path. Reserve with `reserve_ai_budget_v2` (the ceiling comes from the route and the
  model price table) before the call; settle with `usage.costUsd` after.
- Store the vendor and model that actually answered in the feature's existing provenance columns.
- Stable system content first, with `cache: true` at the end of the stable prefix.
- Map each `AiFailure` to the feature's existing error codes. No new athlete-facing text that names a
  model (D11).
- Evals: build the feature's eval on the existing `_evals/` pattern. Run the Claude route live with
  `ANTHROPIC_API_KEY` from `.env` (export it through the shell; never print, log or commit it),
  at most USD 2 per chunk. Compare with the latest recorded baseline for the feature (eval workflow
  logs or the handoff); where none exists, record the Claude result as the baseline and say so.
  Never send real athlete data or photos to an eval.

**A3: meal photo on Haiku 5.5, physique check on Sonnet 5.5.** Features `meal_vision` and
`physique_vision`. Reuse the meal-analyze consent-provider guard and the JPEG checks. Migration code
13 only if a whitelist or provenance column still refuses `anthropic`. Eval images: only images
already in the repo's fixtures or generated test images; no athlete photos.

**A4: onboarding plan and questions on Sonnet 5.5.** Features `onboarding_plan` and
`onboarding_questions`. The plan contract, policy and rules plan stay authoritative: the model's
plan is validated by `plan_contract.ts` and falls back to the rules plan exactly as today. Eval on
`_evals/onboarding_plan_eval.ts`.

**A5: daily decision on Sonnet 5.5.** Feature `daily_decision`. The mock provider stays the default
when nothing is configured, and the B0 rule holds: no output the active policy forbids reaches the
athlete (the existing validator runs on every route). New `_evals/daily_decision_*` over the
existing decision fixtures.

**A6: Coach chat, cache-friendly.** Feature `coach_chat`. Reorder the prompt so the stable parts
(rules, athlete file) form a cacheable prefix and the question comes last; `prepare_coach_chat_v8`
stays frozen. Add the Contract 7 host in `_shared/coach_context/` with no contributors yet (E3, C3
and B3 add them). The route chooses Haiku 5.5 or Sonnet 5.5 by settings; evaluate both and
recommend one. Done when a repeated question shows cache reads in its `ai_call` log, and the eval
meets the baseline.

**A7: wording, budgets, cutover (after A3–A6 merge).** Apply D11 in the app (the six files in A7's row of the Phase 2 file
owners): "AI answer" and a provenance line without a model name. Draft the new consent
notices (coaching v6, meal photo v2, physique v2) for the owner to edit and publish. Migration code 17
sets the Phase 2 budget limits the owner chooses. Update the AI authority-doc sections, run the
final evals, and write the cutover runbook: the settings per feature, `verify-live-function.sh
--all`, the 2-week rollback by settings (D1), and the order (notices published → settings set →
checked → DeepSeek and Groq dropped from the privacy processor list after the rollback window).

**D1: Live Activity buttons.** Done, Skip and +30s on the Lock Screen and in the Dynamic Island
(iOS 17 interactive Live Activities with App Intents). Each button maps to a Contract 3 command
(`CompleteCurrentSet`, `SkipRest`, `AddRest(30)`) through the workout controller's one command sink;
the Live Activity never writes sets itself. Works while the app is in the background. No push, and
an App Group only if the intents cannot reach the app without one (say why). Gates: `build ios
--release --no-codesign`, widget and contract tests, then the lead's signed install and the owner's
device check (a full workout run from the Lock Screen).

**C2: per-set heart rate (stacked on D1).** `HeartRateReader.swift` reads Apple Watch heart-rate
samples during a workout (HealthKit anchored query; about every 5 seconds while a Watch workout runs,
sparser otherwise) and hands them to Dart. Dart computes Contract 4 summaries per set from
`started_at`/`completed_at` plus the following 60 seconds, and saves them with
`persist_set_heart_rate_v1` (migration code 32: table, RLS with `auth.uid()`, pgTAP, privacy export
and deletion in the same PR). Summaries only; raw samples never leave the phone. D9: heart rate never
changes a load or a prescription. Show at most a small per-set heart-rate line in the workout detail.
Update SECURITY_PRIVACY §4 and DATA_MODEL for the summaries (Contract 4 is owner-approved). Done when
a Watch session gives at least 80% coverage on the owner's device check.

**B1: catalog v2 and coaching-standard data.** Each catalog exercise gains secondary muscles, joint
stress (knee, back, shoulder), regressions and progressions, substitutes and a load step. New
`_shared/training/standard/` holds rule data (rep ranges by goal, rest by exercise class, weekly sets
per muscle, progression steps), each value with its source, written in our own words (D3: no paid
course material). Existing catalog exports keep their shape, so today's plans do not change (B2 uses
the new data). Migration code 21 only if the catalog is mirrored in SQL. Done when a test proves
every substitute, regression and progression points at a real exercise, and every rule value has a
source.

## Chunk briefs: Iteration 3 (Phase 3)

Round 1 runs U3, B2 and B6 in parallel; round 2 runs C3, E2 and B3 (after B2); round 3 runs D2 and
E3. Builders run on Sonnet; the review is `codex review --base origin/main` in the builder's
worktree (the owner's ChatGPT plan), and the lead checks the fixes.

**U3: launch speed (owner-approved after the 2026-10-17 GPT review).** `AppShell` builds all five
tabs inside one `IndexedStack`, so every tab starts its reads at launch. Mount a tab the first time
it is selected and keep it mounted after that; Today mounts at launch. Share reads that several tabs
make for the same data within a short window, the way the shared brief repository already does (a
second caller joins the in-flight read; no long-lived cache, no stale data after a write). Decode
progress photos at their displayed size (`cacheWidth` / `ResizeImage` from the layout size and the
device pixel ratio). No visual change. Prove it with a widget test that counts repository reads at
launch and on first opening each tab (before and after numbers in the handoff). The lead then
measures a profile build on the owner's iPhone (cold launch, tab switches, Progress scroll, photo
viewer, Coach, a full workout) and records the numbers as the first budgets in TESTING_STRATEGY §6.

**B2: templates and fractional volume.** Replace the rules plan's single layout with templates
chosen by goal × days (1–6) × experience × session length: full body for few days, upper/lower and
push/pull/legs splits as days rise. Weekly sets per muscle come from `_shared/training/standard/`
(indirect sets count 0.5), within the policy. Reconcile the standard with the policy where they
differ (strength rest, beginner strength reps, hypertrophy compound rest; see the training-engine
handoff) and record each choice in ALGORITHMS §9. Owner decision 2026-10-15: full-gym plans default
to lat pulldowns, with pull-ups returning as a variation; core work rotates. Read Contract 8 and cap
intensity for `moderate_until_cleared`. The plan contract and its validator stay authoritative and
change only additively; the model path still falls back to the rules plan. Update the
`catalog_plans_test.ts` digests on purpose and report what changed (sets by muscle, exercise mix),
as B0 did. No migration.

**B6: screening gate (ACSM 2015 method, our own words).** Ask, during onboarding before the plan:
whether the athlete exercises regularly now, whether they have known heart, metabolic or kidney
disease, whether they have signs or symptoms of one, and whether a professional has cleared them.
Map the answers to Contract 8 following the ACSM 2015 preparticipation logic: any symptom, or
inactive with known disease and no clearance, gives `see_professional`; active with known disease
and no clearance gives `moderate_until_cleared`; otherwise `cleared`. Store the answers, the outcome
and the date (migration code 26: user-owned table, RLS with `auth.uid()`, pgTAP, privacy export and
deletion in the same PR). The existing exclusions (pregnancy, rehab, acute injury, clinical
nutrition) stay. Questions and guidance in plain words, no diagnosis; update UX_FLOWS §4.1, PRD and
AI_SAFETY_SPEC where they describe eligibility.

**Round 2 (started 2026-10-17).**

**E2: the knowledge base, part 1.** The library is the Coach's knowledge base for how to train and
eat: the evidence behind good coaching, written so Coach can explain and cite it. Rules still set
the plan's numbers (Architecture 1); B1's standard is built from the same evidence. About 30
sources, chosen for coaching value and quality (position stands, consensus statements, systematic
reviews and meta-analyses, public guidelines): training (volume, intensity, frequency, rest,
progression, deloads, time-efficient training), nutrition (protein, energy balance and body
composition, timing, creatine, caffeine, hydration), cardio and activity guidelines, recovery and
sleep, pre-exercise screening, and joint-friendly training (no rehab). Licence rule (D3): store
full text only where the licence allows it (CC BY and similar); otherwise store a summary in our
own words with the citation and link. Free public articles from certification bodies (NASM, ACE,
NSCA) may be summarised in our own words with a link; their textbooks, course modules and exam
material are never used. Every source records its licence and why it was chosen; the full list goes
in the handoff for the owner to review. Ingestion must reach production through the normal deploy
(no manual production steps; the deploy workflow sets the embedder's address in Vault): content as files in the repo, loaded by migration 42, embeddings
filled server-side with `gte-small`. Build the retrieval test set (about 40 athlete questions, each
with the sources a good answer needs) and report recall in the top 8 with the real search.

**B3: progression from the sets actually logged.** Deterministic next-session targets per exercise
(load, reps, sets) from `exercise_sets` actuals and B1's `progression.ts` (double progression,
load steps by equipment, reps in reserve). A stall or a missed session holds or lowers; never more
than the standard's step. D9: heart rate never sets a load. Training hub 1.7 adds the targets
(additive; older builds ignore them). Train shows the next target on each exercise. A Contract 7
contributor (`progression.ts`) summarises recent progression for Coach (not registered yet).

**C3: heart-rate profile.** From HealthKit and C2's per-set summaries: resting heart rate, an
estimated maximum (age formula until an observed higher peak replaces it), heart-rate zones from
heart-rate reserve, and recovery after sets. Sleeping heart rate is computed and stored in shadow
(D10): never used in the recovery score. D9: heart rate never sets a load. Migration 33: user-owned
tables with RLS, pgTAP, privacy export and deletion. A small zones view in the app, and a Contract 7
contributor (`heart_rate.ts`, not registered yet).

**A8: Coach proposals (round 3, with E3; owner, 2026-10-17).** Coach gets hands with a safety
check. In chat, Coach may propose a structured change: goal or phase (cut, maintenance, diet break,
gain) and target, calorie and protein targets, training days or session length, an exercise swap,
or overall plan intensity. Deterministic rules turn the proposal into the exact numbers and refuse
anything outside the policy, the standard or the screening outcome; the model never writes a number
that becomes durable. The athlete sees a card with the before and after and taps Approve or Not now;
approval creates a new plan or goal version with an audit event and can be undone (Architecture 2
and 3). Reuse the onboarding proposal versioning, `evaluate_change_eligibility` and B7's goal target
RPC. Migration code 18.

**Later rounds (recorded now).** E2 builds a retrieval test set with its first 30 sources: about 40
athlete questions, each with the sources a good answer needs. E3 makes the library shape every Coach
reply (owner, 2026-10-17): the coaching principles digest from E2 sits in the cached stable prefix of
every Coach chat and daily decision prompt, and every Coach chat turn retrieves from the library
before answering, not only questions that ask why. E5 does the same for plan explanations and the
onboarding plan prompt. Rules and validators still bound every number. E3 ships only
if the retrieval test set passes: recall of the expected sources in the top 8, every citation pointing at a
retrieved chunk, and no unsupported claim in the eval; when retrieval is slow or fails, Coach
answers without it (the Contract 7 host's time limit). Before the external beta, the lead repeats
U3's device measurements against the recorded budgets.

## Coach design (owner-approved 2026-10-17, checked against industry practice)

Goal: Coach behaves like a certified coach on every reply, with no temporary fixes. Research
summary (Anthropic Contextual Retrieval and context-engineering posts, the Mem0, Zep and LangMem
memory work, Letta, ChatGPT memory, Google PH-LLM and the Personal Health Agent) is recorded in the
decisions log. Borrow patterns, not packages: no LangChain, LangGraph, LlamaIndex, Mem0 or Zep
(frameworks hide the prompt, and autonomous memory writes break Architecture rule 2).

**Three memory stores plus knowledge.**
1. **Confirmed facts** (profile): goal and target, phase, screening, conditions and medications,
   equipment, schedule, injuries, food and exercise likes, coaching style. Only the athlete writes
   them; Coach may propose one and the athlete confirms. Each fact is versioned (superseded, never
   overwritten), carries its source, `confirmed_at` and, for volatile facts such as injuries or
   schedule, a re-confirm date. An athlete statement that contradicts a confirmed fact triggers an
   update proposal and never silently overrides it.
2. **Athlete state** (computed): one deterministic renderer with a weekly horizon (check-ins and
   notes, recovery, plan and next meal, next targets, heart-rate profile, complete-day nutrition,
   open proposals) and a long-term horizon (phases such as "cut, June to October, -15.2 kg",
   monthly weight, strength per lift, adherence by month). Computed on demand; cached only if slow.
3. **Coach notes** (episodic): small structured notes per session, written in the background after
   the reply (topics, concerns, advice given, commitments and whether they were followed), capped,
   decaying, linked to message ids, labelled as the coach's notes and treated as untrusted. Search
   over raw past messages backs them up, because extraction loses detail.
4. **Knowledge**: the coaching principles digest in the cached prefix, plus library retrieval on
   every Coach turn.

**Context assembler (v9, alongside the frozen v8).** Fixed budgets per part; order stable parts
(rules, principles digest, confirmed facts) before volatile ones (state, notes, retrieved chunks,
the question) so the prefix caches; precedence: Tracend calculations, then confirmed facts, then
the athlete's recent statements, then coach notes, then knowledge. Every item carries its date and
every window is stated. v8 stays for rollback until v9 passes the eval bank.

**Retrieval, just enough for about 35 sources.** Fix full-text search (OR the terms instead of
`websearch_to_tsquery`'s AND), fuse with reciprocal rank fusion (k about 50), filter by topic and
population, and rewrite follow-up questions with the previous turn's topic. Return 8 to 10 chunks
with source ids and require Coach to cite them. No reranker, contextual chunk prefixes or larger
embedding model until the library passes about 100K tokens. E3 runs one head-to-head check on the
retrieval questions answered end to end: retrieval against the whole library in the cached prefix.
If quality is within noise, keep whichever is simpler.

**Guardrails (A9).** A deterministic red-flag screen before the model (symptoms, check-in pain of
7 or more) returns a fixed referral; a numbers check allows only numbers from the context and the
athlete's message (repair once, else the labelled data summary); safety floors (calorie floor,
weekly loss ceiling, healthy-weight floor, cut length, the screening cap); no claimed actions;
replies about 120 words by default; a stronger model route for progress, nutrition-number and plan
questions.

**Memory controls (A10).** The athlete can view, edit and delete confirmed facts and coach notes,
and can open a chat that is not remembered.

**Eval bank (A11), gates every Coach change.** Retrieval: the 42 questions plus about 15 multi-source
and 10 no-answer questions, recall and MRR, no model call, every pull request. Answers: 60 to 100
synthetic athletes (the owner's case, a stale goal detail, an outlier reading, partial logging, no
target at a healthy weight, "I fainted", a contradicted fact, and more), mostly code-graded, each
run 3 times; safety categories allow zero failures. A model judge only for tone, with binary
rubrics, a different model from the one answering, and checked against about 30 human labels.

**Build order (round 3).** B7, then A9, A11 (grows with each chunk), A10, E3, A8, then D2.

## Phase 5: during the beta (owner, 2026-10-17)

These ship between beta test rounds, not before the first one. Each is sensitive data: its own
consent line, RLS, export and deletion, never sent to AI without the athlete's AI consent (a new
notice when new data goes to the AI provider, AI_SAFETY_SPEC), and non-judgemental wording.

- **L1 lifestyle log.** Alcohol (drinks and time; the calories also count in nutrition; Apple
  Health has a number-of-alcoholic-beverages type), smoking and vaping (count per day), cannabis
  and other substances (optional, private, never required). Used only as evidence: it can explain a
  poor night, a higher resting heart rate or a recovery dip, and lowers confidence. Coach never
  diagnoses, never advises on drug use beyond health effects, and points to support resources.
- **L2 hydration.** A daily water target (from the plan, body weight and activity) and a quick log,
  read from and written to Apple Health water.
- **L3 health history.** Structured conditions and medications in onboarding, extending B6.
  Medications matter for coaching: beta-blockers, for example, blunt heart rate and break C3's
  zones. Uploading or analysing medical reports stays excluded (CLAUDE.md MVP boundary) unless the
  owner changes that rule.
- **Candidates for the owner to decide:** menstrual-cycle tracking (Apple Health cycle data;
  training and recovery effects), caffeine (timing against sleep), illness and sick days, travel
  and shift work.

## Review loop (every chunk)

1. Builder implements in its worktree and runs the stream's tests plus `./scripts/pre-deploy.sh`
   (or `--skip-colima --skip-reset` with CI pgTAP).
2. A separate reviewer agent checks: contract match, frozen files untouched, old-build safety,
   RLS and export/deletion, tests that exercise the change, docs updated.
3. Builder fixes findings, pushes, and opens the PR. All required checks must be green.
4. The lead verifies against this doc, re-stamps if needed, and hands the PR to the owner.

## Contract requests

(A2's consent-granularity request was resolved by Contract 1 v2.)

Open, from B4/B5 (none of these files are built in B4-1):

1. **ai-gateway, Coach context:** a volatile `readiness` contributor (Contract 7) rendering today's
   band, kind, status and `signals` from a service-role reader (B4-1 builds the RPCs the athlete
   calls; the service-role reader `get_readiness_context_v1(p_user_id, p_local_date)` arrives with
   B5-1). `_shared/training/readiness/payload.ts` is the strict parser.
2. **ai-gateway, A9 red-flag screen (with B5-1):** treat today's newest pain report with outcome
   `urgent`, `clinician_today` or `clinician` like a check-in pain of 7 or more.
3. **ai-gateway, reply guard (with B5-1):** no sets, loads or exercises for a joint in state `held`.
4. **ai-gateway, A8:** `buildNextSessionAdjustment` for today refuses when an accepted day
   adjustment exists (add `today_adjusted` to `get_coach_proposal_inputs_v1`); deload intents
   delegate to B5-3's builder. Later, move A8's "lighter today" onto the B4 overlay so one mechanism
   remains.
5. **ai-gateway, A5 coach-decide:** add `day_adjustment` (band, kind, status) to the daily snapshot
   and an evidence code `READINESS_ADJUSTMENT_PROPOSED`, so the daily note never contradicts the
   card.
6. **research-library (E):** update `bell_2023_deloading` from its CC BY full text; add
   summary-only entries for Finucane 2020, Stiell 1997 and NICE NG59 (B5).
7. **lead:** if B5-3 uses a `training-proposals` Edge Function, `supabase/config.toml` and the
   deploy list.

A8's earlier request (wire Coach chat to the proposal engine after A10) was resolved in the same
pull request as part 1 (#148): coach-chat calls `proposeCoachChange` after every reply guard has
passed, stores `proposalId` on the assistant message (`coach_messages.proposal_id`, set by
`link_coach_proposal_v1`), and the thread renders `CoachProposalLoader` under the reply. Details:
`docs/handoff/ai-gateway.md` ("A8: Coach proposals") and AI_SAFETY_SPEC §6.

## Decisions log

- 2026-10-15: program approved; Iteration 1 = Phase 0 + Phase 1.
- 2026-10-15: Contract 1 v2. Consent compares a vendor id (`anthropic`, `deepseek`, `groq`,
  `gemini`), not the wire protocol, so a DeepSeek notice can never pass a Groq route. SQL stores
  vendor ids only (A1 adds `anthropic`; `openai_compatible` is never stored). Eval routers use
  vendor `router`, which no notice names. Resolves A2's contract request.
- 2026-10-15: D11 (no model names in user-facing text). App files that name providers today:
  `lib/shared/ai_provider_names.dart`, `lib/features/consent/ai_coaching_consent.dart`,
  `lib/features/coach/coach_labels.dart`, `lib/features/onboarding/onboarding_proposal_view.dart`,
  and (found in A3 review) `lib/features/progress/widgets/photo_widgets.dart` and
  `lib/features/progress/progress_screen.dart`, which show the photo provider's name; notice bodies are rows the owner publishes (A7 drafts them).
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
- 2026-10-15: Contract 6 v1.1 (E1). `query_embedding` is the domain `public.library_embedding`
  over `extensions.vector(384)`, because `supabase db dump` strips grants that mention
  `extensions`. Library regions are `global` or ISO alpha-2 codes; regional callers pass
  `['global', '<code>']`.
- 2026-10-15: Iteration 1 merged and live (#102–#114); the owner's device check of build 395 passed
  (Lock Screen and Dynamic Island countdown). The authority docs were rewritten against `main`
  (#115); open owner decisions are listed in `docs/PROGRESS_CONTEXT.md`.
- 2026-10-15: Iteration 2 = Phase 2. A3–A6 ship behind route settings, so production providers do
  not change until A7's cutover. A7 gets migration code 17 for the Phase 2 budget limits. The lead
  stamps board rows and PROGRESS lines at merge time (rule 11).
- 2026-10-16: Contract 3 v1.1 (D1 review). `CompleteCurrentSet` names the set the Live Activity
  showed (`exerciseOrder`, `setNumber`); the workout applies it only while that set is still the
  current unticked one and no rest is running, so a double tap or a stale Done never ticks the
  next set. Presses older than 8 s are dropped.
- 2026-10-17: Iteration 3 = Phase 3, run in three rounds to fit the owner's usage. U3 (launch speed)
  added after the owner's GPT review found every tab loading at launch; E2/E3 gain a retrieval test
  set and a pass gate; a device speed check comes before the external beta. Contract 8 (screening
  outcome) added. Reviews use the Codex CLI on the owner's ChatGPT plan.
- 2026-10-17: round 1 merged (#125 kickoff, #126 U3, #127 B2, #128 B6) after Codex review fixes:
  cover-sized photo decoding (U3); a stricter screening expires plans built under a weaker one and
  approval re-checks the current outcome (B6).
- 2026-10-17: round 2 = B3, C3, E2. E2 gets migration code 42. Owner direction: the library is a
  knowledge base for how to train, built from the best open evidence; NASM/ACE/NSCA public articles
  may be summarised in our own words, never their textbooks or course material.
- 2026-10-17 (owner): the knowledge base shapes every Coach response, as a certified coach's training
  would. E2 adds a coaching principles digest (our own words, about 1,200–1,800 tokens, cited) for
  the cached prefix of Coach chat and the daily decision; E3 retrieves on every Coach turn; E5
  covers plan explanations and the onboarding plan prompt. Rules and validators still bound numbers.
- 2026-10-17 (owner): A8 Coach proposals added to round 3. Phase 5 (during the beta): L1 lifestyle
  log (alcohol, smoking, substances), L2 hydration, L3 health history; medical-report analysis stays
  excluded unless the owner changes the MVP rule.
- 2026-10-17 (owner): Coach design approved after an industry check. Three memory stores (confirmed
  facts, computed athlete state, coach notes) plus knowledge; a v9 context assembler beside the
  frozen v8; just-enough retrieval (fixed full-text, RRF, filters, follow-up rewrite; no reranker
  yet; a head-to-head against the whole library in the cached prefix); A9 guardrails; A10 memory
  with athlete controls; A11 eval bank gating every Coach change; no agent or memory frameworks.
  A9 (code 19) and A10 (code 20) added.
- 2026-10-17: B7 added after the owner's Coach chat showed a 15 kg loss reported as "7 kg" and
  projected into a future weight. Goal phase review in Coach chat (deterministic summary, five
  outcomes with cited basis), athlete-set targets (migration 27), no projection without a target
  and none below the healthy-BMI floor, no claimed actions, short replies. Registers the first
  Contract 7 contributor (`goal_phase`) and changes the coach-chat prompt, so its parity digests
  are recorded again.
- 2026-10-17: round 2 merged: B3 (#132), C3 (#133), E2 (#135, the deploy now sets `library_embed_url`; 122 chunks embedding in production), and B7 (#136). Each had a Codex or Claude Opus review and fixes.
- 2026-10-17: B7.1 (#141): the goal phase also reads the whole recorded weight history, and the
  long-cut rules judge the continuous loss (at least 4 readings, no gap over 35 days, a fresh latest
  reading). Six Codex passes. A9 split into a server half (#143) and an app half (#142). Reviews
  (Codex, then Claude Opus while Codex was rate-limited) found red-flag fail-opens. The rule
  adopted: an exemption counts only when it governs the matched symptom or figure in the same
  clause; self-harm and eating-disorder mentions get no exemptions; when in doubt, refer. Known
  cost: some education questions ("does creatine cause dizziness?") now get a referral. A11
  measures it. Merge order: #143 before #142, so no-plan chat never reaches the model without
  the plan status.
- 2026-10-23: advanced experience level and four staple lifts (owner-approved after the Coach
  simulator found the top level was intermediate and the catalog lacked a weighted pull-up,
  close-grip bench press, conventional deadlift and Bulgarian split squat). Advanced is the athlete's
  choice from three years of training; new exercises are advanced-level so other levels' plans are
  unchanged; numbers come from the standard's cited sources, and where none separates advanced
  lifters the intermediate value stands. Details: training-engine handoff and ALGORITHMS "Advanced
  level".
- 2026-10-23: E4 (regional modules). The athlete may store an optional country (`user_accounts.country_code`; `ZZ` is "another country") and `private.library_regions_for_account` prefers it over the locale and time-zone guess; no plan rule reads it. D5's four regions each have a nutrition and a body-measure source; NICE is deferred (its text could not be read).
- 2026-10-23 (owner): B4/B5 design approved. O2 to O13 as recommended (in-house points and bands;
  ACWR excluded; one tap with Undo and no confirm sheet; the adjustment is an overlay, not a plan
  version; one-week deloads; pain bands 1-3 watch, 4-6 modify, 7 or more refer; self-attested
  clinician clearance; Cardio target 150 minutes with Apple Health workouts counted as moderate;
  withhold advice on a red-flag day, never block the workout). O1 amended: the recovery score alone
  never applies or pre-selects an adjustment; it informs the athlete and opens the check-in, and the
  athlete may choose an adjustment themselves with one tap and Undo (D9 clarified above). Authority
  doc conflicts C1 (same-day adjustments are overlays), C2 (UX_FLOWS files B4 as same-day, one tap),
  C4 (D9) and C6 (A8 merged on the board, Phase 4 file owners) resolved in the B4-1 PR.
