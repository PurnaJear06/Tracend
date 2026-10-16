# AI coaching notice v6 (draft for the owner)

Status: draft. Not published. Publishing is the owner's step in
[`docs/runbooks/phase2-claude-cutover.md`](../runbooks/phase2-claude-cutover.md) (step 3), run from the
Supabase SQL editor after the A3-A7 code is deployed.

What it replaces: `ai-coaching-v5` (DeepSeek). Every athlete is asked again on the next app start,
because a grant of an older version no longer counts.

Covers: Coach chat (`coach_chat`), the daily decision (`daily_coaching`) and the starting plan with its
follow-up questions (`onboarding_plan`). It is the one notice for all three, as v5 was.

Rules this text follows (D11): it names the receiving company once, "Anthropic", and no model. Nothing
else the athlete or the public reads names a model or company. What is sent matches v5 and
[`docs/SECURITY_PRIVACY.md`](../SECURITY_PRIVACY.md); if the data sent changes, change the text first.

Retention wording is Anthropic's published commercial policy ("we automatically delete inputs and
outputs on our backend within 30 days of receipt or generation", checked 2026-10-16 at
privacy.claude.com, "How long do you store my organization's data?"). Anthropic keeps data longer only
where the law requires or to enforce its usage rules, and up to 2 years if its safety systems flag an
input as a policy violation. The text says the first two plainly. Re-check the page on the day you
publish; if it changed, change the text.

The same body is built into the app as the fallback (`AiNotice.builtIn`,
`lib/features/consent/ai_coaching_consent.dart`); a test keeps the two identical.

## Publish (owner, SQL editor)

Dollar quoting keeps the text exactly as written. The label must contain "Anthropic" and no other
company (the A1 check refuses it otherwise).

```sql
select private.publish_ai_notice(
  'ai-coaching-v6',
  'anthropic',
  'Anthropic',
  array['coach_chat','daily_coaching','onboarding_plan'],
  $notice$Your starting plan, the Coach chat and your daily decision are written by an AI model. To write your starting plan, and the few follow-up questions it may ask first, Tracend sends Anthropic, a US company, your onboarding answers: goal, age, sex, height, weight and target weight, daily activity, training days and session length, years of training and what has worked or stalled, equipment, limitations, movements to avoid, focus and strong muscles, diet notes, the barbell top sets you report with Tracend’s one-rep-max estimates, your answers to the follow-up questions, any changes you ask for to a proposal and, if you have one, your current plan. If you connected Apple Health, it also sends a summary of your last 4 weeks (average steps, active energy and sleep, workouts per week, and your weight trend) and of your usual completed months. For the Coach chat and daily decision it sends your training plan and workout logs, check-ins, Apple Health summaries (sleep, heart rate, HRV, steps and workouts), meals and nutrition targets, body measurements, goals, focus muscles and preferences, and the messages you send the Coach. Your name, email address and photos are not sent.

Under its standard commercial terms, that company deletes this data within 30 days and does not use it to train its models. It may keep data longer only where the law requires it or to enforce its usage rules.

Tracend checks every AI plan, answer and decision against its safety rules, and nothing starts until you approve it. Without AI coaching, Tracend builds your starting plan with its own rules, and your plan, logging, Apple Health sync and progress keep working; the Coach chat and AI daily decisions stay off. You can turn AI coaching off at any time in Account. That stops new requests; data already sent is deleted on the schedule above.$notice$
);
```

## Check after publishing

```sql
select version, provider, provider_label, purposes, length(body)
from public.ai_consent_notices order by created_at desc limit 1;
select * from public.ai_notice_current order by purpose;
```

Expect `ai-coaching-v6`, `anthropic`, `Anthropic`, and `coach_chat`, `daily_coaching`, `onboarding_plan`
pointing at v6 in `ai_notice_current`. The body is under the 4,000 character limit.
