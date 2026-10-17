# Tracend Cost Model

**Status:** Authoritative MVP budget assumptions\
**Prices:** USD before tax and currency conversion. Each table states its date and source.\
**Review cadence:** Before paid upgrade, TestFlight expansion, provider/model change, or material
usage change

Pricing changes over time. Verify the linked official pricing pages before committing spend. Any
paid add-on or provider change updates this document and [ARCHITECTURE.md](./ARCHITECTURE.md)
before purchase.

## 1. AI Providers and Per-Feature Costs Today

Which feature uses which provider, and the settings that choose it, are in
[AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md) §10.2. In production **today, until the Claude cutover
(§3)**:

| Feature | Provider and model | Typical call | Estimated cost per call | Reservation ceiling |
| --- | --- | --- | --- | ---: |
| Coach chat question | DeepSeek V4.1 Flash | ~15K input + ~800 output tokens | about USD 0.0055 (peak) | 0.02 |
| Daily decision | DeepSeek V4.1 Flash | not measured here | — | 0.01 |
| Onboarding plan | DeepSeek V4.1 Flash | ~4K input + 2–3K output, plus 4–7K reasoning with thinking on | about USD 0.01 (thinking on); about 0.004 (off) | 0.05 |
| Onboarding follow-up questions | DeepSeek V4.1 Flash | ~2K input + up to 4K output (mostly reasoning) | at most about USD 0.005 | 0.02 |
| Meal photo | Groq `qwen/qwen3.8-27b` | ~1,340 input + up to 1,000 output | about USD 0.004 at the paid price | 0.01 |
| Physique check (owner only) | Groq `qwen/qwen3.8-27b` | 3 photos × 2,048 + ~600 prompt input, up to 800 output | about USD 0.007 at the paid price | 0.03 |

Weekly reviews are generated deterministically inside PostgreSQL and incur no model-token cost.
Queue/Cron work stays bounded to one deduplicated weekly job per active user plus at most three
attempts.

### DeepSeek (Coach chat, daily decision, onboarding)

`https://api.deepseek.com/v1/chat/completions` (OpenAI-compatible, JSON output, thinking mode,
1M-token context). DeepSeek retired V4 Flash on 2026-09-10; its name `deepseek-v4-flash` is
temporarily routed to DeepSeek-V4.1-Flash, whose own name is `deepseek-flash`. The Edge code
accepts both (`_shared/providers/deepseek_models.ts`).

V4.1 Flash list prices from 04:00 UTC on 2026-09-10, in USD per million tokens:

- Off-peak: 0.003 cache-hit input, 0.15 cache-miss input, 0.60 output.
- Peak (weekdays 01:00–04:00 and 06:00–10:00 UTC, which is 06:30–09:30 and 11:30–15:30 IST):
  0.006, 0.30, 1.20.

Cost estimates use the peak cache-miss price (0.30 input, 1.20 output), so the budget stops never
undercount. The real cost of a chat question is lower off-peak (about USD 0.0027) and much lower
on a same-day follow-up that hits the cache.

- **Onboarding plan:** reasoning is billed as output and recorded on its own in the audit event.
  A repaired plan adds one non-thinking call (about USD 0.004). A provider without a known price
  must set the cost secrets, or the rules plan is used.
- **Follow-up questions:** asked once per set of answers. A claim stops overlapping requests from
  paying twice, and skipping waits for the running call rather than starting the plan beside it.

### Groq (meal photos, physique check)

Groq's paid list price for `qwen/qwen3.8-27b` is USD 0.80 input and 4.00 output per million
tokens, fixed in `groq_meal_vision_provider.ts`. The key is on Groq's free tier (no card on file),
so a request over the limit is refused rather than billed. Usage events still carry an estimate at
the paid price, so the budget never undercounts if the key moves to a paid tier.

- **Meal photos:** the binding free-tier limit is **1,000 output tokens per minute** for this
  model (Groq's 429 on the owner's key, 2026-09-30). Groq refuses a request whose
  `max_completion_tokens` exceeds it before generating anything, so the request asks for at most
  1,000 and sends no reasoning options. About one photo per minute fits; a second photo within the
  minute may be refused with `meal_vision_request_failed:429:rate_limit_exceeded`.
- **Physique check:** one check uses about 7,600 of the free tier's 8,000 tokens a minute, so a
  second check (or the text-only correction) within the minute may be refused (429
  `physique_check_busy`). Recorded as `progress_vision`.
- Gemini paid-tier Flash was the more accurate meal alternative but needs a billing-enabled
  project. DeepSeek image input was ruled out because DeepSeek may train on inputs by default and
  stores them in China.

### Rollback and prior providers

- **No call is free by default.** An unset price uses the list price (DeepSeek peak 0.30/1.20,
  Groq Coach 0.6/3, Gemini 1.5/9) in coach-decide as in coach-chat. A price set to 0 or below stops
  the Coach provider, and Gemini meal photos refuse to run without both prices.
- The Gemini Free tier is suitable only for synthetic evaluation data. Gemini paid-service routing
  requires a billing-enabled project and data-terms review before it can process restricted data.
- The AI gateway (`_shared/ai/models.ts`) prices every call from one table; a model without a
  price has no route. Its rollback routes keep today's prices: DeepSeek at the peak rates above
  (cache hits 0.006), Groq qwen3.8 and Gemini 3.5 Flash with cached tokens at the full input
  price, since no cache discount is verified for them.

## 2. Budget Stops in Code

Every limit below is enforced server-side in SQL and counts every account. Source: migrations
`20261009150000_ai_budget_reservations.sql` and `20261015120011_provider_neutral_ai.sql`, and
`_shared/ai_budget.ts`.

| Limit | Value | Where |
| --- | --- | --- |
| Monthly warning, per athlete | 80% of the hard stop, USD 2.40 (shown, not enforced) | `get_my_ai_budget_state`, and `budget_warning` in Coach chat |
| Monthly hard stop, per athlete | USD 3 | `private.ai_budget_limits.per_person_monthly_usd`, read by `reserve_ai_budget`, `reserve_ai_budget_v2`, `assert_owner_ai_budget` |
| Daily requests, per athlete | 30, shared by Coach chat, daily decisions, meal photos, physique checks and onboarding | same |
| Global monthly stop, all accounts | USD 50 (confirm at cutover) | `private.ai_budget_limits.global_monthly_usd` |

Owner decision 2026-10-16: USD 3 per athlete per month, replacing USD 2, and a USD 50 global stop,
replacing USD 10; the owner said "that is fine" to the global value, which is marked to confirm at
the cutover. Migration code 17 (`20261016004017_ai_budget_phase2.sql`) moves the per-athlete stop
from a literal inside four functions into the limits row and sets both values. The 30 requests a
day are unchanged.

- **Daily decisions:** `prepare_daily_coaching` applies the same 30, counting only runs that
  called an AI model. A daily decision with no place left falls back to the deterministic
  provider, as without consent; the plan stays usable.
- **Changing a stop:** from the SQL editor,
  `update private.ai_budget_limits set per_person_monthly_usd = 4, updated_at = now();` or
  `update private.ai_budget_limits set global_monthly_usd = 20, updated_at = now();`
  (each above 0 and at most 1,000). The global stop stops every model call once the month's total
  across all accounts reaches it.

**Reservations.** Every model call first takes a place with `reserve_ai_budget` and gives it back
with `settle_ai_budget` once its usage is recorded or no call was made.

- Open places count toward the limits at a per-purpose ceiling (the last column of the table in
  §1) and as one request each, so parallel calls cannot all pass a check that only saw finished
  calls.
- A call is admitted only if its own ceiling still fits under each stop, so the per-athlete and
  global stops are never crossed by an admitted call.
- A place is left open on purpose whenever billing cannot be ruled out: a timeout, a dropped
  connection or an unreadable answer with no usage reported (Coach chat, meal photos, physique
  checks, onboarding), an unrecorded usage row, or a failed live daily decision. It then keeps
  counting at its ceiling, so a failure can only overcount. Only a refusal (429) or an HTTP error
  rules billing out.
- **Route ceilings:** `reserve_ai_budget_v2(target_user_id, run_purpose, ceiling_usd)` takes the
  per-call ceiling from the caller's route instead of the fixed per-purpose table, so a Haiku and
  a Sonnet route of the same feature hold what each can cost. The ceiling must be at least
  USD 0.001 and at most USD 0.50, and is rounded up to six decimals. The same stops apply. It also
  accepts the gateway's feature names and stores them under today's purposes (`daily_decision` as
  `daily_coaching`, `physique_vision` as `progress_vision`, `library_context` as `coach_chat`).
  `AiBudget.reserve(purpose, ceilingUsd)` calls it; without a ceiling it calls
  `reserve_ai_budget`. Every feature on a gateway route passes its route's ceiling; the settings
  path of each feature still reserves the fixed per-purpose ceiling.

**Failed calls count.** A meal photo whose answer is unusable still records its usage, and so does
one whose candidates the database refuses. A failed Coach chat records the tokens of every attempt
at the list price (`persist_failed_coach_chat_run_v2`), as does an answer that could not be
stored. Every billed onboarding call counts, including empty or cut-off answers and the repair.

## 3. Claude routes (Phase 2 cutover)

> **Not live until the owner runs the cutover**
> ([`docs/runbooks/phase2-claude-cutover.md`](./runbooks/phase2-claude-cutover.md)). The code is
> merged behind settings (program decision D1, chunks A3-A7); the table in §1 is still what
> production runs.

Phase 2 moves every feature to Claude through the AI gateway: Coach chat and meal photos to
Haiku 5.5, the daily decision and the physique check to Sonnet 5.5; onboarding follows later, after
chunk B2. The old routes stay available by settings for two weeks after the cutover.

| Feature | Model | Measured cost per call (synthetic evals, 2026-10-15/16) | Reservation ceiling |
| --- | --- | --- | ---: |
| Coach chat question | Haiku 5.5 | USD 0.00045 (97.6% of prompt tokens read from cache) | up to 0.014 |
| Daily decision | Sonnet 5.5 | about USD 0.009 | about 0.06 |
| Meal photo | Haiku 5.5 | about USD 0.0002 | 0.00175 |
| Physique check (one correction at most) | Sonnet 5.5 | about USD 0.01 a set | 0.071 |
| Onboarding plan (later) | Sonnet 5.5 | USD 0.02-0.08 | 0.24-0.27 |
| Onboarding questions (later) | Sonnet 5.5 | about USD 0.003 | 0.023 |

Measured costs come from small synthetic runs (the evals in `docs/handoff/ai-gateway.md`), not from
athletes; the first month of `ai_call` logs replaces them. Ceilings are worst cases, never clamped,
and are what the stops count while a call is in flight.

**Claude list prices (2026-10-15,** [pricing page](https://platform.claude.com/docs/en/about-claude/pricing)**),**
USD per million tokens. The gateway's price table (`_shared/ai/models.ts`) uses these values.

| Model                                  | Input | 5-min cache write | Cache read | Output |
| -------------------------------------- | ----: | ----------------: | ---------: | -----: |
| Claude Haiku 5.5, prompt ≤ 100K tokens |  0.10 |             0.125 |       0.01 |   0.50 |
| Claude Haiku 5.5, prompt > 100K tokens |  0.50 |             0.625 |       0.05 |   2.50 |
| Claude Sonnet 5.5                      |  2.00 |              2.50 |       0.10 |  10.00 |
| Claude Opus 5.5                        |  4.00 |              5.00 |       0.20 |  20.00 |

- Haiku's prompt length counts every input token, cache reads and writes included; a request over
  100K pays the higher card for all its tokens.
- The gateway marks cache prefixes with the default 5-minute lifetime, so writes use that rate
  (1-hour writes cost 2x input and are not used).
- Thinking is billed as output on every provider. US-only inference (`inference_geo`) costs 1.1x
  and is not used.

**Illustrative per-call costs**, using today's token sizes from §1, uncached. Thinking tokens and
image token counts on Claude are not measured yet; the Phase 2 evals measure them.

| Call | Haiku 5.5 | Sonnet 5.5 |
| --- | ---: | ---: |
| Coach chat question (15K input + 800 output) | about USD 0.002 | about USD 0.038 |
| Onboarding plan (4K input + 2–3K output, before thinking) | — | about USD 0.03–0.04 |
| Onboarding questions (2K input + up to 4K output) | — | at most about USD 0.044 |
| Each 1K thinking tokens | USD 0.0005 | USD 0.01 |

Consequences for the stops in §2:

- Several Sonnet calls cost more than today's fixed per-purpose ceilings (Coach chat 0.02,
  onboarding questions 0.02, onboarding plan 0.05 with thinking). Phase 2 routes therefore reserve
  with their own ceiling through `reserve_ai_budget_v2`.
- With Coach chat on Haiku 5.5 at about USD 0.00045 a question, the 30 requests a day (not the
  money) bind first: 30 questions a day for a month cost about USD 0.40. An uncached Sonnet question
  at about USD 0.038 would let the USD 3 stop allow roughly 80 a month, so keep Coach chat on the
  cached Haiku route.
- A typical athlete is expected to cost well under USD 1 a month on these routes; USD 3 is a ceiling
  with headroom, and the USD 50 global stop covers roughly 50-100 active athletes before it binds.
  Both are the owner's numbers (2026-10-16) and are re-read from the logs after the first month.
- Anthropic does not use commercial API data for training and deletes it within 30 days (the
  notices say so); that is a retention term, not a cost.

## 4. Infrastructure Costs

### Recommended cost posture

- Develop locally with Supabase CLI and Docker-compatible runtime.
- Use one ongoing Supabase Free hosted project for owner dogfooding and the first few friends/family
  while quotas, manual backups, and possible inactivity pausing are acceptable. Free is a plan, not
  a time-limited trial.
- Upgrade to one Supabase Pro project only when reliable non-pausing availability, automated daily
  backups, larger quotas, or beta scale justify it.
- Do not purchase a second hosted staging project initially; use local Supabase and synthetic
  fixtures.
- Enable Supabase Spend Cap when on Pro, and enable AI-provider project budgets before beta
  invitations on every Supabase plan.
- Keep custom domains, PITR, read replicas, larger compute, dedicated IPv4, and external
  observability add-ons outside MVP unless a measured need appears.

### Services

| Service | Use | Cost |
| --- | --- | --- |
| Supabase | Database, Auth, Storage, Edge Functions (production project `qsfzzsjenopqqqhvpyaw`) | Free USD 0; Pro USD 25/month (below) |
| Supabase `gte-small` embeddings | Research library (D4): 384-dimension embeddings run inside Edge Functions, stored with pgvector | No separate AI provider; counts as Edge Function use and database size. Tables exist (E1); ingestion is planned (E2). |
| Apple Developer Program | TestFlight and production Apple capabilities | USD 99 per membership year (about USD 8.25/month). Today the app is signed by a free team. |
| Cloudflare Pages | Website `tracend.pages.dev`, published by `site-deploy.yml` | Free |
| Cloudflare Turnstile | Bot check on the waitlist form | No paid plan used |
| Gmail SMTP | Waitlist emails (`_shared/smtp.ts`, `smtp.gmail.com`, port 465) | A Gmail account; about 500 messages a day. A custom domain moves this to a transactional provider. |
| GitHub | Code, Actions CI and deploys; encrypted backups in a private repository | The main repository is public; no paid plan recorded |

### Supabase

Official references:
[Supabase billing](https://supabase.com/docs/guides/platform/billing-on-supabase),
[billing FAQ](https://supabase.com/docs/guides/platform/billing-faq), and
[cost controls](https://supabase.com/docs/guides/platform/cost-control). Limits below are from the
2026-06-28 snapshot.

**Free: $0/month.** Two active free projects across organizations owned/administered by the user;
500 MB database per project; 1 GB Storage; 5 GB egress; 50,000 monthly active users; and 500,000
Edge Function invocations. This is technically sufficient for development, owner dogfooding, and a
small active friends/family beta. Free projects with low activity over a seven-day period may be
paused, and free projects should be backed up manually using `supabase db dump` plus a separate
Storage export. A paused project can be resumed, but the interruption makes Free unsuitable once
testers depend on continuous availability.

**Pro: $25/month per organization.** One default-size project is normally covered by the included
**$10 compute credit**. Included usage: 8 GB database disk per project; 100 GB Storage; 250 GB
egress; 100,000 monthly active users; and 2 million Edge Function invocations. Additional
default-size projects start at roughly **$10/month each** after the organization's compute credit:
one Pro project is about **$25/month**, two default-size projects about **$35/month**, and usage
above quotas or optional add-ons is extra. The Pro Spend Cap covers many variable items, including
Storage, egress, Edge Function invocations, database disk, and MAU. It does not cover explicitly
selected compute/add-ons.

### Storage estimate

Use compressed uploads and retention from [SECURITY_PRIVACY.md](./SECURITY_PRIVACY.md).

Illustrative 10-user beta:

- progress photos: 3 photos/month × 1 MB × 10 users × 12 months ≈ 360 MB;
- meal photos retained for 30 days: 1 photo/day × 0.5 MB × 10 users × 30 days ≈ 150 MB; and
- exports, thumbnails, and overhead: maintain a monitored buffer.

This fits under the 1 GB Free Storage allowance but uses roughly half of it before overhead,
exports, or larger photos. It remains far below the 100 GB Pro allowance. Monitor Free Storage and
database size weekly; actual measurements replace estimates once uploads exist.

### Expected monthly scenarios

AI spend is capped by the global stop (USD 50 a month from migration code 17, §2; USD 10 before),
whatever the number of users.

| Stage                         | Supabase |    AI (capped) |                 Apple |                 Expected cash cost |
| ----------------------------- | -------: | -------------: | --------------------: | ---------------------------------: |
| Local development             |       $0 |          $0–$5 | $0 until distribution |                    **$0–$5/month** |
| Owner TestFlight on Free      |       $0 |          $1–$5 |              $99/year |         **$1–$5/month + $99/year** |
| Up to 10 active users on Free |       $0 |    up to $50   |              $99/year |      **up to $50/month + $99/year** |
| 10–25 active users on Pro     |      $25 |    up to $50   |              $99/year | **$25–$75/month + $99/year**       |

Raising the global stop raises the AI column by the same amount. For this private beta, Supabase
compute, database, Storage, egress, Auth, and Edge Function use may remain inside Free limits at
first and should remain inside one Pro project's included quotas later. AI calls, especially image
analysis, are the main variable cost.

## 5. Required Cost Controls

- While on Free: weekly logical database dump, separate Storage export/inventory, pause-warning
  email monitoring, and 70% quota alerts/checks.
- On Pro: Spend Cap enabled.
- One remote project until a second environment has measured value.
- Dashboard billing alerts and weekly owner review during beta.
- Per-user daily limits for coach decisions, retries, and photo analyses.
- Idempotency keys and duplicate-image detection before AI calls.
- Maximum image dimensions and compression before upload/provider transfer.
- Provider project monthly budget and alert thresholds.
- Server-side model routing; users cannot choose an expensive model.
- AI kill switch that preserves approved plans and manual logging.
- `model_runs` records estimated and actual usage/cost without raw sensitive content.
- Meal-image retention enforced so Storage does not grow indefinitely.
- One open encrypted export per owner, three downloads, and seven-day retention; the existing daily
  retention call performs cleanup without another schedule.

## 6. Upgrade Triggers

Increase spend only when metrics justify it:

- database or Storage approaches 70% of included quota;
- sustained Edge Function latency or resource limits affect the coaching loop;
- a second hosted environment is required for safe release operations;
- AI quality evaluation proves a more expensive model materially improves safety/usefulness; or
- beta growth makes manual monitoring insufficient.
