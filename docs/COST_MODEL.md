# Tracend Cost Model

## Qwen Reasoning Routing

Routine chat and daily formatting use non-reasoning Qwen. High reasoning is reserved for weekly
review and plan analysis, then followed by a bounded structured formatting request. Existing owner
USD request/month guards apply to the combined token usage of both calls.

**Status:** Authoritative MVP budget assumptions\
**Pricing snapshot:** 2026-06-28, USD before tax and currency conversion\
**Review cadence:** Before paid upgrade, TestFlight expansion, provider/model change, or material
usage change

Pricing changes over time. Verify the linked official pricing pages before committing spend.

## 1. Recommended Cost Posture

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

## 2. Supabase Platform Cost

Official references:
[Supabase billing](https://supabase.com/docs/guides/platform/billing-on-supabase),
[billing FAQ](https://supabase.com/docs/guides/platform/billing-faq), and
[cost controls](https://supabase.com/docs/guides/platform/cost-control).

### Free

Base cost: **$0/month**.

Current included limits relevant to Tracend:

- two active free projects across organizations owned/administered by the user;
- 500 MB database per project;
- 1 GB Storage;
- 5 GB egress;
- 50,000 monthly active users; and
- 500,000 Edge Function invocations.

This is technically sufficient for development, owner dogfooding, and a small active friends/family
beta. Free projects with low activity over a seven-day period may be paused, and free projects
should be backed up manually using `supabase db dump` plus a separate Storage export. A paused
project can be resumed, but the interruption makes Free unsuitable once testers depend on continuous
availability.

### Pro

Base subscription: **$25/month per organization**.

One default-size project is normally covered by the included **$10 compute credit**. Current
relevant included usage is:

- 8 GB database disk per project;
- 100 GB Storage;
- 250 GB egress;
- 100,000 monthly active users; and
- 2 million Edge Function invocations.

Additional default-size projects start at roughly **$10/month each** after the organization's
compute credit. Therefore:

- one Pro private-beta project: approximately **$25/month**;
- two default-size hosted projects in one Pro organization: approximately **$35/month**; and
- usage above quotas or optional add-ons: extra.

The Pro Spend Cap covers many variable items, including Storage, egress, Edge Function invocations,
database disk, and MAU. It does not cover explicitly selected compute/add-ons.

## 3. Apple Cost

An Apple free developer account can test directly on the owner's device from Xcode, so early local
development can remain free. The
[Apple Developer Program](https://developer.apple.com/programs/whats-included/) currently costs
**$99 per membership year**, or local currency where available. Paid membership is required for
TestFlight distribution and the production Apple capabilities used by the beta.

Equivalent monthly planning value: **$8.25/month**, but Apple bills annually.

## 4. AI API Cost Assumptions

ChatGPT Pro/Plus does **not** include API usage; API calls are billed separately. Current reference
pricing is on the [OpenAI API pricing page](https://openai.com/api/pricing/).

For planning only, assume:

- economical structured model for daily decisions;
- stronger model only for onboarding, weekly review, or ambiguous conflicts;
- compact feature snapshots rather than raw history;
- one normal daily decision per active user;
- one weekly review per active user;
- up to one meal-image analysis per day for a highly engaged user;
- bounded retries and no duplicate analysis; and
- normalized/compressed images at the lowest evaluated detail that preserves accuracy.

Phase 7 initially generates weekly reviews deterministically inside PostgreSQL, so they incur no
model-token cost. Queue/Cron work remains bounded to one deduplicated weekly job per active user
plus at most three attempts. The stronger-model estimate below applies only if a later evaluated
interpretation step is explicitly enabled.

At the 2026-06-28 standard rates, GPT-5.4 mini is listed at $0.75 per million input tokens and $4.50
per million output tokens; GPT-5.4 is $2.50 input and $15 output per million tokens. A
representative text-only month is inexpensive:

| Workload per user/month                   |         Illustrative tokens |   Approximate cost |
| ----------------------------------------- | --------------------------: | -----------------: |
| 30 daily decisions on mini                |  4k input + 700 output each |        about $0.19 |
| 4 weekly reviews on stronger model        | 8k input + 1.2k output each |        about $0.15 |
| onboarding, retries, occasional conflicts |                    variable | budget $0.10–$0.75 |

DeepSeek V4.1 Flash (`COACH_MODEL_PROVIDER=deepseek`) is the current active Coach/chat provider.

The Gemini Free tier is suitable only for synthetic evaluation data. Gemini paid-service routing
requires billing-enabled project and data-terms review before it can process restricted data.
Prior Gemini baseline: `gemini-3.5-flash` at USD 1.50/1M input and USD 9.00/1M output tokens
(2026-07-04 paid standard rate). Coach used medium thinking, meal extraction used low, high was
reserved for named difficult review fixtures. A USD 3 per-owner monthly warning and USD 5 hard stop
were enforced server-side, with 30 Coach requests per owner/day. Lite models were not production
routes.

**Prior owner test (ADR 0006, 2026-07-11, superseded 2026-07-26):** Groq Qwen `qwen/qwen3.6-27b`
was used server-side for owner dogfooding through beta. Now superseded pending evaluation.

**Owner AI budget (2026-09-29):** USD 1 monthly warning, USD 2 server-side hard stop, and 30
requests per owner/day shared by Coach chat, daily decisions and meal photos
(`assert_owner_ai_budget`, `get_my_ai_budget_state`). The daily-decision preparation
(`prepare_daily_coaching`) applies the same 30, counting only runs that called an AI model
(2026-09-30). The daily count was 10, which about 10 meal
photos a day would use up; the USD 2 stop still bounds spend.

**Meal photos (2026-09-29):** Groq `qwen/qwen3.8-27b` (`MEAL_VISION_PROVIDER=groq`), the named
successor of `qwen/qwen3.6-27b`, which Groq shut down on 2026-09-14. On Groq's free tier (no card
on file) a request over the limit is refused rather than billed. The binding free-tier limit is
**1,000 output tokens per minute** for this model (Groq's 429 on the owner's key, 2026-09-30). Groq
refuses a request whose `max_completion_tokens` exceeds it before generating anything, so the
request asks for at most 1,000 and leaves out the qwen3.6 route's reasoning options (with them the
same request was refused; without them it succeeded). A test photo used about 1,340 input tokens.
About one photo per minute fits; a second photo within the minute may be refused with
`meal_vision_request_failed:429:rate_limit_exceeded`. Usage events still carry an estimate at Groq's paid
qwen3.8 price (USD 0.80 input, 4.00 output per million tokens, fixed in
`groq_meal_vision_provider.ts`), about USD 0.004 per photo, so the budget never undercounts if the
key moves to a paid tier. Gemini paid-tier Flash was the
more accurate alternative but needs a billing-enabled project; DeepSeek image input was ruled out
because DeepSeek may train on inputs by default and stores them in China.

**Active production provider (2026-07-26):** DeepSeek via `COACH_MODEL_PROVIDER=deepseek`, at
`https://api.deepseek.com/v1/chat/completions` (OpenAI-compatible, JSON output, thinking mode,
1M-token context).
- **Model:** DeepSeek retired V4 Flash on 2026-09-10. Its name `deepseek-v4-flash` is temporarily
  routed to DeepSeek-V4.1-Flash, whose own name is `deepseek-flash`. The Edge code accepts both
  (`_shared/providers/deepseek_models.ts`).
- **V4.1 Flash list prices** from 04:00 UTC on 2026-09-10, in USD per million tokens:
  - Off-peak: 0.003 cache-hit input, 0.15 cache-miss input, 0.60 output.
  - Peak (weekdays 01:00–04:00 and 06:00–10:00 UTC, which is 06:30–09:30 and 11:30–15:30 IST):
    0.006, 0.30, 1.20.
- **Cost estimates** use the peak cache-miss price (0.30 input, 1.20 output), so the USD 1 warning
  and USD 2 hard stop never undercount. Until 2026-09-28 they used the retired V4 Flash rate (0.14
  input, 0.28 output), which undercounted V4.1 Flash output by up to 4.3×.
- **Onboarding plan** (2026-10, `ONBOARDING_PLAN_*`):
  - about 4K input and 2–3K output tokens, roughly USD 0.004 at the peak price, with thinking off;
  - with thinking on (the default since 2026-10), reasoning adds roughly 4–7K output tokens, so
    about USD 0.01 a plan; reasoning is billed as output and recorded on its own in the audit event;
  - a repaired plan adds one non-thinking call (about USD 0.004);
  - it is recorded in `ai_usage_events` as `onboarding_plan` and counts toward the USD 2 stop and
    the 30-a-day limit;
  - a provider without a known price must set the cost secrets, or the rules plan is used.
- **Coach follow-up questions** (2026-10, before the onboarding plan): one call of about 2K input
  and up to 4K output tokens (mostly reasoning), at most about USD 0.005; recorded as
  `onboarding_questions`, counted toward the same limits, and asked once per set of answers.
- **Per question:** a v8 question (~15K input + ~800 output tokens) is estimated at about
  USD 0.0055. The real cost is lower off-peak (about USD 0.0027) and much lower on a same-day
  follow-up that hits the cache.

## 5. Expected Monthly Scenarios

| Stage                         | Supabase | AI planning envelope |                 Apple |            Expected cash cost |
| ----------------------------- | -------: | -------------------: | --------------------: | ----------------------------: |
| Local development             |       $0 |                $0–$5 | $0 until distribution |               **$0–$5/month** |
| Owner TestFlight on Free      |       $0 |                $1–$5 |              $99/year |    **$1–$5/month + $99/year** |
| Up to 10 active users on Free |       $0 |              $10–$40 |              $99/year |  **$10–$40/month + $99/year** |
| 10 active users on Pro        |      $25 |              $10–$40 |              $99/year |  **$35–$65/month + $99/year** |
| 25 active users on Pro        |      $25 |             $25–$100 |              $99/year | **$50–$125/month + $99/year** |

Monthly-equivalent totals including the annual Apple fee are approximately:

- owner on Free: **$9–$13/month equivalent**;
- 10 active users on Free: **$18–$48/month equivalent**;
- 10 active users on Pro: **$43–$73/month equivalent**; and
- 25 active users: **$58–$133/month equivalent**.

For this private beta, Supabase compute, database, Storage, egress, Auth, and Edge Function use may
remain inside Free limits at first and should remain inside one Pro project's included quotas later.
AI image analysis is the main variable cost.

## 6. Storage Estimate

Use compressed uploads and retention from [SECURITY_PRIVACY.md](./SECURITY_PRIVACY.md).

Illustrative 10-user beta:

- progress photos: 3 photos/month × 1 MB × 10 users × 12 months ≈ 360 MB;
- meal photos retained for 30 days: 1 photo/day × 0.5 MB × 10 users × 30 days ≈ 150 MB; and
- exports, thumbnails, and overhead: maintain a monitored buffer.

This fits under the current 1 GB Free Storage allowance but uses roughly half of it before overhead,
exports, or larger photos. It remains far below the current 100 GB Pro allowance. Monitor Free
Storage and database size weekly; actual measurements replace estimates once uploads exist.

## 7. Required Cost Controls

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

## 8. Upgrade Triggers

Increase spend only when metrics justify it:

- database or Storage approaches 70% of included quota;
- sustained Edge Function latency or resource limits affect the coaching loop;
- a second hosted environment is required for safe release operations;
- AI quality evaluation proves a more expensive model materially improves safety/usefulness; or
- beta growth makes manual monitoring insufficient.

Any paid add-on or provider change updates this document and [ARCHITECTURE.md](./ARCHITECTURE.md)
before purchase.
