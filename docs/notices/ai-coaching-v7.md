# AI coaching notice v7 (draft for the owner)

Status: draft. Not published. Publishing is the owner's step below, run from the Supabase SQL editor
after the cycle support PRs are merged and deployed (`ai_notice_coverage.ts` must already say 7 for the
three new kinds of data, which it does from the Coach cycle PR).

What it replaces: `ai-coaching-v6` (Anthropic). Same company, same purposes (`coach_chat`,
`daily_coaching`, `onboarding_plan`) and the same text, except the list of what the Coach chat and the
daily decision send, which adds four kinds of data:
- the notes the athlete writes in a workout (the session note, an exercise's note, the reason for a
  swap): approved by the owner on 2026-10-20, held back by `workout_notes` until now;
- Apple Health breathing rate: approved on 2026-10-20, held back by `breathing_rate`;
- active energy: sent since before v6 (the athlete file's Apple Health days) but not named in the
  Coach list (AI_SAFETY_SPEC §10.3 says the next notice should name it);
- cycle data, only for an athlete who turns on cycle tracking: her cycle answers (status, typical
  length) and the period days she logs or allows from Apple Health (`cycle_data`, cycle support v1).

What publishing does: every athlete is asked again on the next app start, because a grant of an older
version no longer counts; Coach chat answers 403 `ai_consent_required` for each athlete until she
accepts v7 (the plan, logging and Apple Health keep working). From her acceptance on, Coach sees the
three held-back kinds of data and, if she tracks her cycle, the cycle block. Nothing else changes for
her. Until it is published no athlete can hold v7, so Coach behaves exactly as under v6.

Rules this text follows (D11): it names the receiving company once, "Anthropic", and no model; the
retention paragraph is v6's (re-check Anthropic's page on the day you publish, as for v6). Every later
coaching notice opens the same data (`firstNoticeNaming` counts versions, not text), so a later
version, a rollback included, must name it too (runbook `phase2-claude-cutover.md`, step 6.2).

## Publish (owner, SQL editor)

Dollar quoting keeps the text exactly as written.

```sql
select private.publish_ai_notice(
  'ai-coaching-v7',
  'anthropic',
  'Anthropic',
  array['coach_chat','daily_coaching','onboarding_plan'],
  $notice$The Coach chat and your daily decision are written by an AI model. Tracend may also use an AI model to draft your starting plan and the few follow-up questions it asks first. This notice covers that too, but until Tracend turns it on, your starting plan is built from Tracend’s own rules and nothing from onboarding is sent to an AI. For the Coach chat and daily decision, Tracend sends Anthropic, a US company, your training plan and workout logs with the notes you write in them, check-ins, Apple Health summaries (sleep, heart rate, HRV, breathing rate, steps, active energy and workouts), meals and nutrition targets, body measurements, goals, focus muscles and preferences, your cycle data if you turn on cycle tracking (your cycle answers and the period days you log or allow from Apple Health), and the messages you send the Coach. Once AI starting plans are on, it also sends your onboarding answers: goal, age, sex, height, weight and target weight, daily activity, training days and session length, years of training and what has worked or stalled, equipment, limitations, movements to avoid, focus and strong muscles, diet notes, the barbell top sets you report with Tracend’s one-rep-max estimates, your answers to the follow-up questions, any changes you ask for to a proposal and, if you have one, your current plan. If you connected Apple Health, it also sends a summary of your last 4 weeks (average steps, active energy and sleep, workouts per week, and your weight trend) and of your usual completed months. Your name, email address and photos are not sent.

Under its standard commercial terms, that company deletes this data within 30 days and does not use it to train its models. It may keep data longer only where the law requires it or to enforce its usage rules.

Tracend checks every AI answer, decision and plan against its safety rules. A starting plan or a plan change never starts until you approve it. Without AI coaching, Tracend builds your starting plan with its own rules, and your plan, logging, Apple Health sync and progress keep working; the Coach chat and AI daily decisions stay off. You can turn AI coaching off at any time in Account. That stops new requests; data already sent is deleted on the schedule above.$notice$
);
```

## Check after publishing

```sql
select version, provider, provider_label, purposes, length(body)
from public.ai_consent_notices order by created_at desc limit 1;
select * from public.ai_notice_current order by purpose;
```

Expect `ai-coaching-v7`, `anthropic`, `Anthropic`, and `coach_chat`, `daily_coaching`, `onboarding_plan`
pointing at v7 in `ai_notice_current`. The body is under the 4,000 character limit. Then accept the
notice in the app and ask Coach about your recovery on an account with cycle tracking on: the reply
should use the cycle (the `cycle_context` log line says `ok`).
