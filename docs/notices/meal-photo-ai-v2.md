# Meal photo notice v2 (draft for the owner)

Status: draft. Not published. Publishing is the owner's step in
[`docs/runbooks/phase2-claude-cutover.md`](../runbooks/phase2-claude-cutover.md) (step 3).

What it replaces: `meal-photo-ai-v1` (Groq). Athletes are asked again before their next meal photo
analysis (`has_meal_photo_ai_consent` counts only a grant of the current version).

Covers: meal photo analysis (`meal_vision`). Names the receiving company once, "Anthropic", and no model
(D11). The `model` argument below is a stored provenance field of the notice row; the app does not
show it. Retention wording: Anthropic's published commercial policy (deleted within 30 days, not used
for training; see the note in `ai-coaching-v6.md`). Re-check it on the day you publish.

## Publish (owner, SQL editor)

```sql
select private.publish_meal_photo_ai_notice(
  'meal-photo-ai-v2',
  'anthropic',
  'Anthropic',
  'claude-haiku-5-5',
  $notice$Meal photo analysis is an AI estimate, not a measurement. When you analyze a meal photo, Tracend sends Anthropic, a US company, a resized copy of that one photo. Its AI suggests the foods it sees with portions, calories and macros. Your name, email address, other photos and the rest of your data are not sent.

Under its standard commercial terms, that company deletes the photo and its answer within 30 days and does not use them to train its models. It may keep them longer only where the law requires it or to enforce its usage rules. Tracend keeps the photo privately in your account and deletes it after the review window unless you save it.

Nothing is logged until you review and confirm the foods. Without photo analysis you can still log meals yourself. You can turn it off at any time in Log a meal. That stops new analyses.$notice$
);
```

## Check after publishing

```sql
select version, provider, provider_label, length(body)
from public.meal_photo_ai_notices order by created_at desc limit 1;
```
