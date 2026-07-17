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

Gemini is the planned sole live provider for owner dogfooding. Meal/progress vision cost depends on
the evaluated model, image dimensions/detail, and tokenization. Until measured with real fixtures,
use a conservative total AI budget of **$1–$5 per active user per month**. This is a planning
envelope, not a promised bill.

The Gemini Free tier is suitable only for synthetic evaluation data in this project. Restricted
coaching data requires a billing-enabled paid-service project because unpaid-service data terms do
not satisfy Tracend's privacy requirements. Billing is a privacy gate as well as a cost decision; it
does not by itself authorize live traffic.

The production baseline is stable `gemini-3.5-flash`: USD 1.50 per million input tokens and USD 9.00
per million output tokens at the verified 2026-07-04 paid standard rate. Coach uses medium thinking,
meal extraction uses low, and high is reserved for named difficult review fixtures. A USD 3
per-owner monthly warning and USD 5 hard stop are enforced server-side, with 30 Coach requests per
owner/day. Lite models are not production routes. Quality-adjusted rupee cost is controlled with
bounded context/output and task-specific thinking.

**Owner test exception (ADR 0006, 2026-07-11):** Groq Qwen `qwen/qwen3.6-27b` is used server-side
for ten owner-test days only. Groq's free-plan quota is not a number of free days and can change;
the app additionally enforces 10 total AI requests/day, a USD 1 warning, and a USD 2 hard stop.

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
