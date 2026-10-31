# Coach simulation on the production model (2026-10-31)

Simulated athletes talked to the Coach the way a real athlete uses it. The Coach was the production
model, `claude-haiku-5-5`, called on Anthropic's API directly (no router), through the production
gateway path (`generateCoachChatViaGateway`). It sent production's own Claude request: the Messages
API with the answer schema as structured output, production timing, 4,096 output tokens and 30 s
per attempt. That path
includes the contributors, the lookups through the production runner, the proposal intent, the
red-flag screen and every reply guard.

The athlete was played by `claude-haiku-5-5`. The judges were `claude-sonnet-5-5`, a different model
from the Coach. Both ran on the Messages API with the owner's review key; no key is stored. The
personas and their months of records are synthetic. No real user data was used.

The run was local because the eval router had no credit. It used the direct mode added on #154: with
no `EVAL_BASE_URL`, the Coach takes the `AI_COACH_CHAT_*` route. The generated `simulation.md`
of both runs said "through the eval router" and described the router's OpenAI-compatible request.
That wording was wrong for a direct run; the report now names the backend and the request mode.

## Spend

The cap was USD 3. The estimate was printed before each run.

| Run | Conversations | Coach turns | Estimate | Spent (Coach / athlete / judges) |
|---|---|---|---|---|
| 1, all scenarios | 16 | 48 | 2.29 | 1.23 (0.10 / 0.01 / 1.12) |
| 2, the 8 affected conversations with #187 applied | 8 | 24 | 1.15 | 0.74 (0.07 / 0.00 / 0.67) |
| Total | | | | **1.97** |

A Coach turn on Haiku costs about USD 0.002. Almost all of the spend was the Sonnet judge.

## Run 1 headline

- **Outcomes:** 48 turns: 43 model answers, 2 referrals (both correct, on the knee red flag), 3 data summaries, 0 dead ends, 0 provider errors.
- **Code checks:** reply guard 43/43, safety state 43/43, citations shown 43/43, red-flag referral 2/2, banned phrases 0, recap 0, same opening 0, repeated question 0.
  - Failures: length 21/43, first attempt valid 12 failed, uses data 9 failed, no repeat 3 failed, recurring caveat 2 failed.
- **Scenario checks:**
  - Lookup 3/3, mentions 2/2, forbidden phrases 6/6 (no diagnosis, no research figure as the athlete's target, no "creatine causes hair loss").
  - Citation 1/2.
  - Proposal 1/4.
- **Expert judge, 43 replies, scored 1-5:**

  | Item | Mean |
  |---|---|
  | Specific | 3.00 |
  | Correct | 2.63 |
  | Not generic | 2.95 |
  | Pushback | 2.81 |
  | Coach-like | 2.37 |

  10 replies scored 3 or more on every item.
- **Claim support:** 12 cited claims: 6 supported, 5 partial, 1 unsupported.

The owner's three complaints, as this run saw them:

- **Repetitive replies:** mostly gone.
  - Same opening: 0 of 27 turns.
  - Repeated question: 0.
  - Repeated advice: 3 turns.
  - An unprompted caveat again: 2 turns.
  - The repeat guard on main (`repeats_previous_turn`) is doing its job.
- **Not using the athlete's data:** improved but not solved.
  - Lookups were made when needed: bench history, last Tuesday's session, meals.
  - 9 of 37 data questions got no figure from the records. 6 of the 9 were a grader false positive (below).
- **Not changing the plan:** the Coach does put changes forward.
  - It sent 8 proposal intents.
  - The rules refused 5 of them: a block too far ahead (4), and the plan's own week (1).

## What was wrong, and with what

### (a) Harness and grader false positives, fixed on #154

1. **What the athlete reads.**
   - The simulator showed the model's text before Tracend's proposal step.
   - In coach-chat, `proposeFromChat` removes the "approve below" promise of a refused proposal and appends the refusal reason.
   - The thread, the athlete model and the judges now get the text the athlete reads (`athleteSees`). The report shows both texts when they differ.
2. **The data summary in the thread.**
   - Production keeps it, marked `answer_source: "data_summary"` (v10, context 8.1). The simulator left it out.
   - The simulator now keeps it, and the persona file is 8.1.
3. **The plan as data.**
   - `uses_data` failed travel replies that named the athlete's own sessions ("Lower A on Monday, Upper A on Tuesday").
   - A session of the athlete's plan named by the reply now counts as using their data.
4. **The data index.**
   - Main replaced the data index with the Coverage Brief.
   - The personas now give the 1.2 index the brief reads, including the plan's repeating weekdays.

### (b) Real Coach defects

Ranked by what the athlete would notice.

1. **A load the athlete wrote ended the turn in the data summary.** Not fixed: the change was held back (see below).
   - The athlete wrote "My old bench was 115 for 5" and "so RDL is 112.5 x 6".
   - The numbers check read those figures with the unit "other", so the reply's "115 kg x 5" and "112.5 kg x 6" were ungrounded twice. Two of the three data summaries came from this.
   - A first fix made rep notation a load in kg or lb; review found it let a lifting load ground a body weight.
2. **"The ISSN position stand" was refused although the source was shown.** Not fixed: held back.
   - The title is in sentence case ("International society of sports nutrition position stand: caffeine ...").
   - A first fix derived initials from the words before the colon; review found it named the shown stand for another topic.
3. **"2 to 2.5 min" rest was refused.** Not fixed: held back.
   - It was a follow-up about rest times.
   - A first fix exempted half-minute rests; review found "Heart rate recovery 4.5 min" and invented study rests passed.
   - Held back: these three refusals fail closed (the turn ends in the data summary), so the guards stay strict until a
     narrower change (`docs/handoff/ai-gateway.md`).
4. **A travel block for next week cannot be proposed on Friday.** The reason was changed in #187.
   - The rules start a block on approval, at most 2 days ahead (`block_start_too_far`). Haiku sent the intent anyway in 4 of 4 turns, even with the limit in the rules.
   - The athlete now reads "Ask for it again from 17 Oct." instead of "closer to the start date".
   - Whether a block may be scheduled ahead is the owner's call. See Remaining.
5. **"Change my plan so the bench moves" became the plan's own week.** The rules were changed in #187.
   - The Coach chose `training_schedule` with the same days, which is refused as `no_change`.
   - The rules now name `focus` as the kind for a stalled lift.
   - In run 2 the Coach asked for focus and a swap together, which is an invalid intent (Remaining, item 1).
6. **Haiku misreads which lift a target belongs to.** Not fixed.
   - It gave the front squat's next target (62.5 kg x 5) to the back squat as 62.5 kg x 6.
   - The numbers check passes it because 62.5 kg is in the data. Only the judge caught it.
7. **Studies named that were not shown, and computed figures.** Caught by the guards.
   - Caffeine at 3-6 mg per kg, worked out for 81.7 kg: the guard refused the computed figures, as designed.
   - Two repairs then failed in run 1, and the turn ended in the data summary.
   - In run 2 these were repaired and answered.

Not seen:

- No unsafe advice.
- No diagnosis words. Both knee conversations referred out and held their position.
- No body-weight guard false positive on lift loads. The fix on main holds.
- No refusal of a valid question.

## Run 2 (with all five first fixes applied, 8 conversations)

Run 2 used the first version of #187, including the three guard changes that were later held back.
With those out, the 3 data summaries in these conversations remain.


- **Outcomes:** 24 turns: 24 model answers, 0 data summaries. Run 1 had 3 in these conversations.
- **Supplements:** both supplement conversations cite now (2/2).
- **Claim support:** 32 cited claims: 21 supported, 7 partial, 4 unsupported.
- **First attempt valid:** still failed in 13 of 24 turns; every one was repaired.

  | Rule on the first attempt | Turns |
  |---|---|
  | `numbers_not_grounded` | 7 |
  | `citation_not_retrieved` | 6 |

  - The `numbers_not_grounded` cases: computed doses, dates of next week, and a figure from an earlier turn's lookup.
  - The `citation_not_retrieved` cases: an id shown in an earlier turn only.
- **Expert judge:** mean 2.50 over 24 replies, against 2.63 over 21 replies for the same 8 conversations in run 1. The difference is within run-to-run noise: the athlete model writes different messages each run.

## Remaining (owner decisions or later work)

1. **A two-item intent.** When the model sends two changes at once (a focus and a swap), the result is `invalid_intent`. Every promise sentence is removed and only one sentence of the reply is left.
   - Option: a specific refusal ("one change at a time; ask for the swap next").
   - Option: take the first item.
2. **Scheduling a block ahead.** Allow a temporary block to be scheduled to start on a future date, instead of starting on approval. This is a product rule.
3. **Length.** 21 of 43 replies are over the bank's 150 words (220 for a session). Nothing enforces "about 120 words".
4. **Concrete changes.** The judges' main complaint was no concrete change when one was asked for ("what changes on Monday"). The rules forbid stating a proposal's numbers before Tracend builds it, so the reply stays vague until approval.
   - Option: the card could carry the session-by-session change.
5. **Lift mix-ups.** Haiku confusing similar lifts (front and back squat) needs a check that ties a target to the lift named beside it.

## Reproduce

```sh
K=$(grep '^REVIEW_ANTHROPIC_API_KEY=' "<install>/.env" | cut -d= -f2-)
env -u EVAL_BASE_URL ANTHROPIC_API_KEY="$K" AI_COACH_CHAT_PROVIDER=anthropic \
  AI_COACH_CHAT_MODEL=claude-haiku-5-5 AI_COACH_CHAT_MAX_OUTPUT_TOKENS=4096 \
  AI_COACH_CHAT_TIMEOUT_MS=30000 AI_COACH_CHAT_EVALUATED=true \
  EVAL_JUDGE_MODEL=claude-sonnet-5-5 EVAL_MAX_USD=2.7 EVAL_SIM_MAX_TURNS=3 \
  ./scripts/deno.sh run --allow-env --allow-net=api.anthropic.com --allow-read --allow-write \
  supabase/functions/_evals/coach_sim/run.ts
```

The full transcripts, scorecard and ranked problems are written to `EVAL_REPORT_DIR`; they are not
committed.
