# Progress photo (physique check) notice v2 (draft for the owner)

Status: draft. Not published. Publishing is the owner's step in
[`docs/runbooks/phase2-claude-cutover.md`](../runbooks/phase2-claude-cutover.md) (step 3).

What it replaces: `progress-photo-ai-v1` (Groq). Athletes are asked again before their next physique
check (`has_photo_ai_consent` counts only a grant of the current version).

Covers: the physique check (`physique_vision`). Names the receiving company once, "Anthropic", and no
model (D11). The `model` argument below is a stored provenance field of the notice row; the app does
not show it. v1 said the athlete's other AI coaching used a different provider; with one company for
every feature that sentence is replaced by "never receives your photos". Retention wording: Anthropic's
published commercial policy (deleted within 30 days, not used for training; see `ai-coaching-v6.md`).
Re-check it on the day you publish.

## Publish (owner, SQL editor)

```sql
select private.publish_photo_ai_notice(
  'progress-photo-ai-v2',
  'anthropic',
  'Anthropic',
  'claude-sonnet-5-5',
  $notice$A physique check is an AI visual estimate, not a measurement. When you start one, Tracend sends Anthropic, a US company, the front, side and back photos of the set you choose, with your sex, height, latest weight and body measurements, and your goal. Its AI suggests up to three muscles to develop, relative to your own build. Your name, email address and other photos are not sent, and Tracend never asks for a body-fat figure or a score.

Under its standard commercial terms, that company deletes the photos and its answer within 30 days and does not use them to train its models. It may keep them longer only where the law requires it or to enforce its usage rules. Tracend keeps your photos privately and saves the result in your account.

Nothing changes on its own: you choose which suggestions become your focus muscles. You can turn photo checks off at any time. That stops new checks; past results stay until you delete the photo set or your account. Your Coach chat and other AI coaching never receive your photos.$notice$
);
```

## Check after publishing

```sql
select version, provider, provider_label, length(body)
from public.photo_ai_notices order by created_at desc limit 1;
```
