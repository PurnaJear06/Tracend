# Tracend Current State

**As of:** 2026-10-20

**Lifecycle:** owner-only private beta; not approved for public production. Production Auth
sign-ups are switched off (2026-10-15) on top of the invite-only trigger.

**Current priority (2026-10-15): the coaching platform program.** Plan, contracts and board:
[`docs/plans/coaching-platform-2026-10/README.md`](./plans/coaching-platform-2026-10/README.md).
Iteration 1 (Phase 0 + Phase 1) is live. Iteration 2 (Phase 2: A3–A7, D1, C2, B1) is merged
(2026-10-16). The AI features still run on DeepSeek and Groq until the owner follows the cutover
runbook. One line per stream; the lead updates these lines when a chunk merges.

<!-- PROGRAM:coaching-platform-2026-10 -->
- program: P0 (contracts, migration-order CI check) live (#102).
- ai-gateway: A1 (#103) and A2 (#106) live. Phase 2 merged: meal photo and physique check (A3,
  #119), onboarding (A4, #122), daily decision (A5, #117) and Coach chat (A6, #120) call Claude
  through the gateway once their route settings are set; A7 (#124) removed provider names from the
  app, drafted the notices, set the USD 3 / USD 50 budget and wrote the cutover runbook
  (`docs/runbooks/phase2-claude-cutover.md`). Data goes only to the vendor the accepted notice
  names. Phase 3 round 3 (2026-10-17): A9 Coach safety and honesty merged as #143 (server: a
  red-flag screen before the model, a numbers check, safe ranges and reply guards on every visible
  field, a screening contributor, the coaching-principles digest in the stable prefix, an optional
  stronger route) and #142 (app: plain error messages, same-key retries, the athlete's local date,
  chat without a plan, one budget gate, a warning at 80%; migration 19). Coach answer validity
  (2026-10-24, branch `claude/coach-response-validity`, in review): 22% of bank answers fell back
  as `provider_response_invalid`, now 3%; causes were parser and validator false positives
  ("0.26 kg a week" read as a 26 kg body weight, "Thu 2026-10-15" as a study, refusals read as
  advice), not truncation or the schema. Handoff:
  [`ai-gateway.md`](./handoff/ai-gateway.md).
- training-engine: B0 live (#105). B1 merged (#118: catalog v2 and coaching-standard data with
  sources; nothing reads it until B2). Phase 3 round 1 merged (2026-10-17): B2 templates and
  fractional volume (#127), B6 screening gate (#128, migration 26). Round 2 merged (2026-10-17): B3 progression from logged sets, hub 1.7 (#132); B7 goal phase review,
  athlete-set targets and no projection as a goal (#136); B7.1 the whole recorded weight history
  and the continuous loss judged across it (#141). Advanced experience level and four staple lifts (weighted pull-up, close-grip and incline barbell bench press, Bulgarian split squat) in review on `claude/advanced-level-catalog` (2026-10-23, migration `20261023100050`; intermediate plans unchanged, advanced chosen by the athlete from 3 years). B4-1 same-day readiness adjustment, server side, in review as #165 (2026-10-23, migration
  `20261023140024`): `day_adjustments`, `get_my_day_adjustment_v1` / `respond_to_day_adjustment_v1`
  (hold loads, one set fewer or easy cardio for today only; one tap and Undo; the recovery score never
  adjusts a session alone, the athlete may choose), `start_workout` building the adjusted sets and B3
  ignoring adjusted sessions as evidence for lowering a load. B4-2, the app card on Today and Train (one tap, Undo until the start, Talk to Coach, safety referral), in review on `claude/b4-2-day-adjustment-card` (2026-10-24, no server change). B5-1 (pain check and joint rules) merged as #172; B5-3 and B5-4 (deloads and cardio dosing, server) in review. Handoff:
  [`training-engine.md`](./handoff/training-engine.md).
- workout-hr: C1 live (#104). C2 merged (#123: per-set Apple Watch heart-rate summaries,
  migration 32; raw samples stay on the phone); the owner's Watch check is pending. C3 merged (#133): heart-rate profile, zones, recovery, sleeping
  heart rate in shadow. C4 in review (branch `claude/watch-workout-prompt`, migration 34): a card on the
  workout screen suggests starting a Watch workout when the last three had no Watch heart rate, and
  load signals (rest, recovery, confidence; never a load) are computed for the training engine and
  shown to Coach as two fixed sentences in the plan context. Handoff: [`workout-hr.md`](./handoff/workout-hr.md).
- ios-widgets: D0 live (#112). D1 merged (#121: Done, Skip and +30s on the Lock Screen and in the
  Dynamic Island); the owner's device check is pending. D2 merged (#149): Today widgets on the Home Screen and the
  Lock Screen, Lock Screen numbers an off-by-default per-athlete choice, 12-hour expiry, snapshot
  excluded from backups and emptied on every sign-out. Live Activity set logging in review (branch
  `claude/live-activity-set-logging`): the card shows the set in progress with **Log set** and **Open**
  (kg and reps only with Lock Screen numbers on), then the rest, the next set, and "All sets logged";
  Log set is the in-app Done set. Handoff: [`ios-widgets.md`](./handoff/ios-widgets.md).
- research-library: E1 live (#109: pgvector, library tables, `search_library_v1`, D3 doc rule). E2 merged (#135): 35 sources, 122 chunks embedded in production
  by `library-embed`, retrieval test set (hybrid recall 0.93). E2.1 merged (14 gap sources). E2.2 merged (#152): 57 more
  verified sources (106 in all, 351 chunks) and machine-readable licences with a verbatim flag, review date and supersession
  (migration `20261018170042_library_expansion.sql`). E3 merged (#150: the library in every
  Coach reply). E3.1 in review (engine production pass, migration 44): `search_library_v3` with
  distances, a relevance floor recalibrated on the 106-source library (219 calibration questions:
  recall 0.855, 27 of 30 out-of-library questions shown nothing; the 55-question hold-out set gave
  recall 0.897, 7 of 8, but multi-source recall 0.646 and word-search no-answer precision 63% miss
  their gates), a word-search floor (recall 0.611, down from 0.795 unfloored), an explicit no-match line, evidence level and Tracend's-reading marks
  on excerpts, the embedding started with the request, a `library_retrieval` log line, the library
  version on each answer, a retire path, the retrieval gate on library pull requests and a deploy
  check. E4 in review (#164, branch `claude/regional-modules`, migration `20261023120044`): regional
  modules for India, the US, the UK and Australia (eight new sources, 114 in all; each region has a
  nutrition and a body-measure source) and an optional **Country** in Account
  (`user_accounts.country_code`, `get_my_country_v1` and `set_my_country_v1`) that picks the regional
  sources instead of the locale and time-zone guess; no plan number reads it, nothing changes with it
  empty; needs the migration first, then an app reinstall for the row. NICE is not included (its text
  could not be read). E5 in review (branch `claude/e5-plan-explanations`, no migration): plan
  explanations cite sources. Coach chat searches a "why is my plan like this?" question with what
  the plan is made of added (counts and enumerated values) and tells Coach to explain from the plan's
  own numbers first; the onboarding plan (`onboarding-plan`, gateway route) shows the model library
  excerpts for the athlete's region, accepts the ids it lists in a new `sources` field only if they
  were shown, and stores each as a `library` evidence item that the app lists under "Why this plan"
  ("Research behind this plan"; needs a reinstall). A plan with no source to cite says so in "Not
  known yet", and one whose search found nothing or failed is low confidence; the rules plan and the
  settings path use no library. `onboarding-propose-plan` is the old mock and is unchanged. The CI
  retrieval gate also scores 12 plan questions. Handoff: [`research-library.md`](./handoff/research-library.md).
- website: W1 merged (#108); the site publishes once the owner sets the `CONTACT_EMAIL` variable. Handoff: [`website.md`](./handoff/website.md).
- ui: U3 launch speed merged (#126, 2026-10-17: tabs load on first open, launch reads 22 to 6,
  cover-sized photo decoding). Device speed budgets still to record.
  U1 glass tab bar live (#107). The owner did not like it (2026-10-15): a U2 design pass with a prototype comes next.
<!-- /PROGRAM:coaching-platform-2026-10 -->

**Lost replies and thread switching (2026-10-24, branch `claude/lost-replies-thread-switch`, PR open):** QA audit groups E
and F, app only. Coach: the latest conversation open wins and a failed open restores the previous chat; New conversation
keeps the Continue row; a conversation loads its newest 200 messages; a follow-up tapped while Coach is busy waits
visibly instead of being dropped. A Coach proposal, the onboarding plan approval, a manual meal and an Apple Health
sync no longer treat a lost reply as a failure: they re-read the server, repeat one idempotency key, or keep what was
typed; a failed meal photo deletes its draft and an empty draft can be deleted. Needs `./scripts/install-device.sh`
from the merged commit. Workout finish (M-E3) is left to the open workout PRs. Details: "Lost replies, idempotent
writes and thread switching" in [`ai-gateway.md`](./handoff/ai-gateway.md).

**Query order fix (2026-10-24, branch `claude/explicit-query-order`, PR open):** saved Coach conversations loaded
newest-first (postgrest-dart's `order()` defaults to descending, and `loadMessages` left the direction out), so a
reply sat above its question and the screen opened on the oldest message. Fixed with an explicit ascending order;
every other `.order(` in the app now states its direction (active goal by priority, measurements, meals, meal
candidates and today's workout were also descending by accident) and a source-scan test keeps it that way. App
only, no migration; needs `./scripts/install-device.sh` from the merged commit. Details: "Coach conversations load
oldest-first" in [`ai-gateway.md`](./handoff/ai-gateway.md).

**Coach opens a fresh chat (2026-10-24, branch `claude/coach-chat-fresh`, PR open):** Coach reopens the last
conversation only if its last message is under 6 hours old, otherwise a new conversation with a **Continue last
chat** row (checked again when the Coach tab is re-activated or the app resumes, never mid-send or with a typed
draft); opening any conversation now lands on its newest message even when content lays out late. App only, no
migration. Details: "Coach opens a fresh chat after 6 hours" in [`ai-gateway.md`](./handoff/ai-gateway.md).

**Stale open workouts (2026-10-23, branch `claude/stale-workout-resume`, PR open):** the owner's Legs B resumed a
session left open since 2026-07-17 (timer 2348 h, today's sets saved on a July date). An open session from an earlier
local day more than 3 hours old is now closed as `abandoned` (rows and sets kept) when any workout is opened and by an
hourly job, and the phone sends an earlier day's unsent sets and finish first, then drops its draft; a session the
rule closed still takes that late send on its own date. Migration `20261023150021`; `start_workout` (as #165 left it) closes the caller's stale sessions after its advisory lock and before its open-session lookup. Details:
"Stale workouts" in [`training-engine.md`](./handoff/training-engine.md).

**B5-1 pain check, red flags and joint rules, server side (2026-10-24, branch `claude/b5-1-pain-red-flags`, PR open):**
migration `20261024060025` adds `pain_reports`, `record_pain_check_v1`, the optional pain keys of
`save_daily_check_in`, joint states (held, limited, watch), joint swaps and range cues, the safety
routes `urgent`, `clinician_today` and `clinician`, the `joint_adjust` kind and payload 1.1 of the
day adjustment, and `get_readiness_context_v1` for Coach context. A red flag or a pain of 7 or more
gives a referral and no training change (even on a rest day or with no check-in); a held joint stays
held until the athlete says a clinician cleared it. No app change yet (B5-2); the app must not offer
the new pain keys until then, and the installed B4-2 build must tolerate the new kind and routes
(see the handoff). Details: "B5-1" in [`training-engine.md`](./handoff/training-engine.md).

**B5-3 deloads and B5-4 cardio dosing, server side (2026-10-24, branch `claude/b5-3-4-deloads-cardio`, PR open):**
migrations `20261024060125` and `20261024060225` add `get_my_training_guidance_v1` and
`get_training_guidance_for_v1` (1.1): when a lighter week could help (two lifts heading down, four amber
or red days of the last seven, a finished block that was trained), what suppresses it (a running block,
28 days since the last deload, too little training, `see_professional`, a safety route), and the weekly
cardio dose (150 minutes, 300 for fat loss and recomposition) from Apple Health workouts with what
intensity is open today. A deload stays a proposal the athlete approves: the A8 builder now makes exactly
one week, half the sets, loads held, effort 7 or lower. Nothing is applied by rules and heart rate picks
nothing. Review round 1 (migration `20261024060325`): B3 holds instead of stepping up during a deload week
and ignores deload sessions as stall evidence, a pending deload is withheld and unapprovable on a safety-route
day, 14 days of quiet after a declined or expired proposal, and the cardio gates (unavailable today, a cleared
screening row). Not built yet: the `training-proposals` Edge Function (lead: config and deploy list), the Train
card and Cardio row (app), the Coach contributor. Details: "B5-3 and B5-4" in
[`training-engine.md`](./handoff/training-engine.md).

**Coach knows today's readiness card (2026-10-24, branch `claude/coach-readiness-context`, PR open):** a `readiness`
Coach context block (band, the card's answer state, safety route and strictness, held/limited/watched joints, fixed
rules; no red-flag code or severity) read from `get_readiness_context_v1` with a 1.5 s deadline and an
ok/unavailable/failed/timeout trace; the deload and cardio-week reader (`get_training_guidance_for_v1`) is not wired yet: it needs a cost measurement first. Today's meals
and the Coach decision's freshness follow the server day on Today, not the phone date. Daily coaching retries a
busy or failing provider once and names a rejection by its HTTP status (`anthropic_request_failed_status_<n>`,
`anthropic_overloaded`). Details: "Coach knows today's readiness card" in [`ai-gateway.md`](./handoff/ai-gateway.md).
Still open: the reply guard and the A9 screen do not read pain reports (contract requests 2 and 3).

**Unfinished workouts (2026-10-24, branch `claude/unfinished-workout`, PR open):** the owner's Legs B (23 sets logged,
never finished) was closed by the stale rule and Coach then called it "not done". A stale-closed session with logged sets
is now offered back on Today ("You didn't finish Legs B on Fri 23 Oct · 23 sets logged"): **Save workout** completes it
on its own date with the athlete's effort, **Discard** keeps it out for good, each audited; nothing is finished for them.
Coach reads it as "logged N sets, not finished", not undone or missed. Migration `20261024050011`
(`get_my_unfinished_workout_v1`, `resolve_unfinished_workout_v1`, `get_coach_plan_state_v1` 1.3); needs the migration
deployed before the app is reinstalled. Details: "Unfinished workouts" in
[`training-engine.md`](./handoff/training-engine.md).

**Incident 2026-10-18: every Coach chat turn timed out (Refs FLUTTER-K). Fixed by #155 (deploy pending verification: confirm `schema_sha` `274ee4fafead` and a first successful turn in production).** The gateway's answer
schema had grown to 24 optional properties and 4 unions and listed the day's evidence codes, so
Claude recompiled its grammar on every turn and passed the 30 s route timeout (`model_runs`:
`provider_timeout`, about 31.7 s, 0 tokens). Fix (`claude/coach-schema-flatten`): one fixed
schema with every key required and no union (0 optional, 0 unions, 2,818 bytes, same bytes for every
athlete), the evidence codes checked by the parser instead of the schema, one retry of a timed-out
first call, per-attempt timing and schema-hash telemetry in the logs and Sentry, a CI guard on the
schema's shape, and a turn deadline counted from the request's start so the data summary still
returns inside the app's 45 s. Nothing changes for the app. Details: "Coach answer schema: one stable grammar" in
[`ai-gateway.md`](./handoff/ai-gateway.md).

**Coach reply guards (2026-10-18, branch `claude/coach-reply-guards`, PR open):** from the Coach
simulator: a lift's load is no longer read as a body weight (55 kg on the overhead press was sending
athletes to the data summary); a plan the athlete asked for keeps its answer (session lengths like "30
min walk" are advice, and a reply that still fails only on figures, unshown sources or repeats is cut
sentence by sentence instead of replaced by the data summary; loads and body-weight, calorie and
medical figures are never let through); a shown study named in the text is attached to the evidence
and one that was not shown is repaired; the app's data summary stays in the thread (migration
`20261018210031`, `prepare_coach_chat_v10`, trend in kg/week); the same closing question or sentence on
consecutive turns is repaired and then cut. Answer schema unchanged. Details: "Coach reply guards" in
[`ai-gateway.md`](./handoff/ai-gateway.md); rules in `AI_SAFETY_SPEC.md` §11, §11.2 and §12.

**Coach investigates first (2026-10-20, branch `claude/coach-investigate-first`, PR open).** Coach
now checks every relevant kind of record before it answers. A Coverage Brief replaces the data
index (per kind: what the context shows, what a lookup adds, what exists and how fresh, the kinds to
check with it), watch-outs computed by code across kinds of record (back-to-back muscles, a session
due on a poor-recovery day, a pain flag planned again, behind plan, repeated skips, drift, stale
weigh-in or sync, plan age) join the context, the prompt makes the first reply a sweep (up to 8
lookups), a refused request gets one corrected round, the model tier follows the state of the
records, and `coach_messages.lookups` records lookups per round. Migration
`20261020100017_coach_investigation.sql` (additive; new kinds are filters on existing lookups, so the
answer schema is unchanged at 2,818 bytes). 37 `inv-` eval cases and a 90% domain-coverage gate; the
live measurement is still to run. Owner decisions: `past_messages` now returns Coach's own earlier
replies, labelled and never grounding a figure (AI_SAFETY_SPEC §11.1a); breathing rate and the athlete's
free text in a workout are held back until a notice names them (§10.3, wording in `ai-gateway.md`). One grounding rule covers every path (records ground both, a pending proposal's figures ground only a figure about the proposal, a model's words and anything undeclared ground nothing: §11.1 "What grounds a figure"), and sleep durations carry their hours so "5.7 h" rests on a "341 min" row. Details: "Coach investigates first" in
[`ai-gateway.md`](./handoff/ai-gateway.md).

**Coach week-ahead fix (2026-10-18, merged as #156).** On a Sunday Coach
named only the week's undone session and never said that Monday trains the same muscles. Coach
now sees the next 7 days from the athlete's own date with each session's muscles, a deterministic
line when two sessions share a muscle on consecutive days, and can look up the plan for any past or
future dates (`plan_history`, filter `schedule`, up to 90 days ahead). Migration
`20261018190042_coach_schedule.sql` (RPCs 1.0 to 1.1, fields added); the answer schema is unchanged.
Details: "Coach sees the next 7 days" in [`ai-gateway.md`](./handoff/ai-gateway.md).

**Authority docs rewritten (2026-10-15):** the 13 authority docs were checked against `main` after
Iteration 1. The addenda were folded in and the contradictions and stale facts were removed. Planned
work is marked "Planned" and points at the program plan. No rule was changed. Rules that the code or
a plan decision contradicts are kept as written and are waiting on the owner:
- Sign in with Apple is required but not built.
- "Rehabilitation excluded" vs D6 injury modifications.
- "No Android" vs the site's "Android in testing".
- Body-fat range: allowed in PRD and VISION, forbidden in AI_SAFETY_SPEC §9.
- Glow ban vs the built glows.
- Meal images: the rule says 30 days, but the code deletes them after about 7.

Decided by the owner on 2026-10-16:
- A model change within the same company needs no new consent notice (D11 names the company,
  not the model). A new company, new data sent or a retention change still does.
- Phase 2 AI budget: USD 3 per person and USD 50 overall per month (from the owner's USD 100
  Anthropic credit), set by #124's migration.
- Per-set heart-rate summaries (Contract 4, #123) are allowed; raw heart-rate series still never
  leave the phone.

Known gaps found:
- `privacy-export` leaves out several tables (SECURITY_PRIVACY §15).
- The app's terms and privacy checkboxes don't link to the site pages.

**Website and waitlist (2026-10-13):** the public website (`site/`, Astro, Cloudflare Pages at
https://tracend.pages.dev) and a double opt-in waitlist on the production project (three
session-less Edge Functions, migration `20261013100000_waitlist.sql`). Joining grants no app
access; the owner invites confirmed signups with `private.invite_from_waitlist(n)`. `deploy.yml`
now publishes the site after the functions and checks the live version. The owner's one-time
Gmail, Cloudflare, GitHub and Supabase settings are in
[`docs/handoff/website.md`](./handoff/website.md).

**Deletion removes invite and waitlist rows (2026-10-15, live #110):** deleting an account now
also deletes its `private.signup_invites` row and its email's waitlist signup (trigger on the Auth
delete; owner's choice), and the migration clears rows that earlier deletions left. SQL only, no
reinstall. See [`docs/handoff/account-session.md`](./handoff/account-session.md).

**Restore drill privileges (2026-10-15):** the deploy's backup restore drill now compares function
EXECUTE, table and schema privileges for anon and authenticated, and RLS flags, in `public` and
`private` with the state the migrations create, and stops the deploy on a difference.
`supabase db dump` drops GRANT and REVOKE lines that name excluded schemas, so a restore could
silently re-open a revoked function. Details: [`docs/handoff/backend.md`](./handoff/backend.md).

**Security hardening (2026-10-09):** a source review of `d26cf2c` raised leads that the owner
asked to fix in five PRs, merged in order; details stay in the owner's private report. PR 1
(media key grammar and ownership, a key guard on every service-role Storage call, the Coach
preference caller check, restore-drill log output) and PR 2 (invite-only sign-ups, recent sign-in
from `amr`, full Storage purge on deletion, no export during deletion, Coach conversation delete
fixed) and PR 3 (time zone writes, consent integrity, health sync bounds, upload quotas and an
orphan sweep, row and size caps) and PR 4a (AI budget reservations, a USD 10 global monthly stop,
failed-call cost, list-price defaults) and PR 4b (meal-photo AI notice enforced by meal-analyze,
AI notice v5; needs the new build) and PR 5 (Keychain session storage, SHA-pinned actions,
read-only workflow tokens) are in review. Workstream state:
[`docs/handoff/security-hardening.md`](./handoff/security-hardening.md).

**Current priority (2026-10-03):** the app-wide graphite + lime redesign. The owner chose palette
A and the round 3 signature picks (focus logging, muscle map on, big new-best moment, day boxes,
white and lime icon) and asked for parallel delivery against a five-hour window. Delivery is now
two integrated pull requests instead of ten: the foundation (backend data, workout logging and
Train data layers, tokens, Archivo, shared widgets, tab bar, icon, launch and intro), then the six
screens, built in parallel. Device checks drop to two: after the foundation, and after the screens
with a real workout. Workstream state: [`docs/handoff/redesign.md`](./handoff/redesign.md). The
foundation (#78) merged and deployed on 2026-10-03 (`12f5bbb`, migration applied); the six screens
are integrated in one PR. The installed app sends the fixed session effort of 8 until the screens
PR ships the new logging. Older plans' exercises are linked to the catalog by exact name (#80, SQL
only) so the Train muscle map can light them; #81 added reviewed muscles for the names the
catalog lacks (build 329 installed). Today's food card is now the fuel rail: protein to go and
the day's meals on a line, since Nutrition already holds the full ledger. Meal slot status
(`due`, `upcoming`, `skipped`) now follows the athlete's time zone instead of UTC (SQL only, no
reinstall).
Today was rebuilt on 2026-10-04 around the owner's chosen prototype: a recovery tick ring split by
driver, a morning check-in gate in place of the tab bar, Sleep/Load/Fuel tiles, a session strip that
fills as sets are logged, and the week as recovery ticks (brief 1.7, migration first, then install).
Recovery then gained two modes (owner report, 2026-10-04: "around 10, and it changes"): a night with
the watch scores that night against nights; without one, a morning estimate scores the morning's
HRV against mornings plus the check-in and settles at noon. Resting HR is yesterday's final value
(brief 1.8, scoring 2.3, migration first, then install).

**Previous priority:** UI polish, so the app reads as a finished consumer product rather than a
beta full of logs. The owner approved the plan on 2026-10-01 and chose to start it before the full
owner-device acceptance checklist. Order: Progress (P1) → Nutrition (P2) → Today, Train, Coach,
Account (P3–P6). Workstream state: [`docs/handoff/ui-polish.md`](./handoff/ui-polish.md).

Progress (#56) and Nutrition (#57) merged on 2026-10-01, and build 235 (main 46c892b) is installed.
The owner liked Progress but found Nutrition ordinary, and chose option A's row style for Today's
meals only (#58). P3–P6 wait for the owner's device check on the new build.

The FLUTTER-8 Coach work is shipped: PR #35, A1, A2, and B are live (B at main 21c3b55, build 225).
The direct DeepSeek evaluation is still unmeasured, and the owner's device check on build 225 is
open; see [`docs/handoff/backend.md`](./handoff/backend.md).

New-user onboarding: a 2026-10-01 audit found the onboarding plan is still the Phase-2 mock, and
it ignores goal, equipment and session length. The approved plan is not the delivered plan, and
reopening on the proposal step spins forever. The owner chose an AI-proposed plan, validated by
deterministic code, with a swappable provider. PR 1 fixes Today's workout date, Start session, and
the Coach's proposal line. PR 2 (server, in review) adds per-purpose AI notices, an exercise
catalog, `onboarding-policy-v1` and the new `onboarding-plan` function (any provider, set by secrets,
with a rules fallback). Review fixes on PR 2: movements to avoid enforced on every path, daily
coaching checks its own notice, nutrition capped to the database bounds with infeasible answers
refused up front, billed failures counted, and expired proposals recoverable. PR 3 (app) adds the
new onboarding steps (including movements to avoid), a resumable plan build, the full proposal
screen, expired-plan recovery and the server-rendered AI notice. All three merged and deployed
2026-10-02 (`c0931ef`), with the eval fixes (#63, #64, `dd76316`); the app is installed and the
`ONBOARDING_PLAN_*` secrets are set, so consenting athletes get a DeepSeek plan. The final
onboarding batch is four stacked PRs: A turns on thinking for the first attempt (setting
`ONBOARDING_PLAN_THINKING`, default on) and stores call telemetry in the audit event; B publishes notice
`ai-coaching-v4` for every purpose (fixing new athletes' grants never counting for the plan),
stores the device time zone, feeds a 28-day Apple Health summary into the plan, and keeps
movements to avoid on the profile for the Coach; C adds the optional Apple Health onboarding step
(weight and activity shown from it, a 31-date first sync, health state per athlete, the device
time zone stored); D fixes onboarding's remaining flaws (draft
restore that could overwrite answers, duplicate consent records, review with Edit, steppers,
2x-text layout, reject confirmation, a "You're set" screen, the profile's onboarding answers). Evals run
through NaraRouter only (owner's decision). All four merged and deployed 2026-10-02 (c35946c) and
the app is installed. On the owner's fresh account the AI plan worked (thinking, 38 s) but felt
generic, so a **coach-quality batch** of three PRs follows: (1) coach intake — training years,
barbell top sets turned into starting loads, up to two focus muscles with weekly set minimums,
0–3 follow-up questions from the coach, and Apple Health usual months against the last 28 days
(`onboarding-policy-v2`, merged in #70 and deployed `a716afb`, build 273 installed); (2) an
owner-only physique check on progress photos: Groq suggests muscles to develop from one photo set
under its own notice, and the athlete confirms up to two as their focus (merged in #72, deployed
`9995cc3`, on for the owner only; see
[`docs/handoff/physique-check.md`](./handoff/physique-check.md)); (3) calibration and a stale-safe
re-plan from two weeks of logged sets. See
[`docs/handoff/onboarding.md`](./handoff/onboarding.md).

Account deletion recovery (owner report 2026-10-02, build 273): after **Delete account** spun
and the app was force-closed, it opened on "Connection needed" for a deleted account. The gate
never asked Auth whether a stored, unexpired session's account still existed, and the deletion
request had no timeout. The fix (in review) validates the session with Auth on launch, signs out
on any refusal, bounds the deletion wait with server confirmation and **Check again**, stores the
pending check-in per athlete, and lets a stopped deletion be claimed again (additive migration).
Needs a reinstall. See [`docs/handoff/account-session.md`](./handoff/account-session.md).

## Shipped baseline

- iOS-only Flutter app backed by Supabase Auth, PostgreSQL/RLS, Storage, and nine Edge Functions.
- Deterministic recovery, sleep, training-load, nutrition, and plan state remains authoritative;
  model output can explain or propose but cannot silently activate durable changes.
- Coach chat reliability (FLUTTER-8) is live. PR #35 and A1 (#36) merged on 2026-09-28, and A1 has
  been live since a 10:50 UTC redeploy (see Release controls):
  - PR #35: typed validation rules, targeted fail-closed repair, fresh coaching-date scores, shared
    daily/chat evidence, whole-section budgeting, the full shared persona, and a scoring-failure
    guard.
  - A1 (#36): the root-cause fix.
    - Every question gets the same full athlete file (`prepare_coach_chat_v8`); keywords no longer
      remove data.
    - The formatter renders all history, and the question comes last for caching.
    - Accuracy rules stay strict while formatting limits become generous ceilings.
    - Labeled estimates and clarifying questions are allowed.
    - The question is saved before the model runs.
    - DeepSeek failures are recorded with rule names.
    - A labeled data-summary reply replaces the 503 for app request schema 1.1.
    - A live 60-prompt evaluation runs on demand.
    - Review fixes (2026-09-28):
      - Long threads keep their newest messages instead of failing with `chat context too large`.
        That was a 422 before the model ran, pre-existing since July.
      - Data summaries never re-enter the coach's memory.
      - Every blocked turn reaches Sentry, and its 422 names a finite reason.
      - DeepSeek retired V4 Flash on 2026-09-10. The code accepts V4.1 Flash as `deepseek-flash`
        as well as the temporary legacy alias, and cost estimates use V4.1 Flash peak prices.
      - The live evaluation runs 17 calls by default, always including every safety prompt, and
        can run through an OpenAI-compatible router as a smoke test.
    - Second review fixes (2026-09-28):
      - A data summary for a message that may be about a health risk is a safety referral
        without numbers, and every summary ends with that referral.
      - A scoring failure no longer blocks the day's first chat (`prepare_daily_coaching` guard).
      - A retried request returns its first attempt's outcome instead of the thread list.
      - Watch averages carry a day count per metric.
      - The installed app still gets the 503 on a model failure until A2, by design.
  - A2 (#41, merged 2026-09-29): the app side.
    - The app sends request 1.1, so a model failure shows a labeled data summary or safety note,
      with Retry and the beta diagnostic.
    - Coach reopens the last conversation (since 2026-10-24 only within 6 hours) and creates a thread on its first send.
    - It lists only conversations that contain a message (`get_my_coach_threads`).
    - The first install (build 185) had no font files, so every icon showed as a "?" box. Its
      build folder was shared with other checkouts. A rebuild from the same commit, with every font
      present, replaced it the same day (see
      [Device installs](./CI_CD_DEPLOYMENT.md#device-installs)).
- HealthKit sleep aggregation handles mixed staged and unspecified intervals without double-counting.
- Owner batch, 2026-09-29/30 (PRs #42–#49, all deployed):
  - each checkout builds in its own folder, and installs refuse an app bundle without its fonts;
  - AI coaching consent in onboarding and Account, with Coach and Today gated in the app;
  - Coach replies render bold, italic and lists;
  - meal-photo failures show under the buttons and reach Sentry;
  - meal photos run on Groq `qwen/qwen3.8-27b` on the free tier, which allows 1,000 output tokens a
    minute (about one photo a minute);
  - the owner AI budget is USD 1 warning, USD 2 stop, 30 requests a day;
  - `sentry_flutter` 9.30.1 with matching iOS pods.
- Fresh-database pgTAP parity, Flutter/Deno tests, iOS compilation, migration collision checks, and
  secret scanning run in CI. Locally:
  - PR #35 passes 124 Deno tests, 422 Flutter tests, 34 pgTAP files / 951 assertions, analysis, an
    unsigned iOS release build, and the linked production migration dry-run.
  - A1 passes 157 Deno tests and, in CI on a fresh database, every pgTAP file, including the
    45-assertion v8 file and the 7-assertion scoring-guard file.
  - A2 passes 443 Flutter tests and 159 Deno tests. Its 7-assertion thread-list pgTAP file runs
    in CI.

  The seven required PR checks gate every push.

## Release controls

- `main` accepts reviewed pull requests with all required checks passing.
- Every agent follows the delivery workflow in `AGENTS.md`: a worktree and pull request per change,
  no hook or branch-protection bypass, and no agent merges. The owner merges.
- Deployment waits for successful CI on the exact merged `main` commit.
- Failed, missing, empty, checksum-invalid, or non-restorable database backups stop deployment.
- Production dumps are restore-drilled in an isolated local Supabase database before migration.
- The encrypted backup is stored in a separate private repository by `scripts/store-backup.sh`
  (newest 30 kept), never as a workflow artifact: artifacts of a public repository are downloadable
  by any signed-in GitHub user.
- Edge Functions deploy one at a time, and each is confirmed live by comparing the deployed source
  with the commit; the release tag waits for that check. On 2026-09-28, parallel deploys had
  reported success while Supabase kept the previous version of four functions. Supabase's
  intermittent deploy 500 is retried automatically (`scripts/deploy-function.sh`).
- Semantic versions come from `pubspec.yaml`; build numbers are monotonic in CI and derived from Git
  history for local device builds.
- Each checkout builds in its own folder. The device installer refuses an app bundle without its
  fonts and asset manifests, and CI checks the same on its iOS build.

See [CI_CD_DEPLOYMENT.md](./CI_CD_DEPLOYMENT.md) for the executable release contract.

## Open release blockers

These are not silently considered complete:

1. Coach chat: A1's server code is live. End-to-end acceptance remains open:
   - Done on 2026-09-28: `DEEPSEEK_MODEL` is `deepseek-flash`, and afterwards all nine live
     functions matched the released commit (`./scripts/verify-live-function.sh --all`).
   - The DeepSeek regression run is still owed; it needs a DeepSeek key. A NaraRouter run on
     2026-09-29 answered 27 of 30 (90% against the 97% gate):
     - every safety prompt was handled safely, with no dead ends and no unpermitted evidence;
     - the 3 misses were invalid JSON from the router on the largest synthetic athlete.
   - Measure A1 in production with the handoff queries after real iPhone use.
   - A2 is merged, deployed, and reinstalled with the app's `SENTRY_DSN`. The owner's A2 device
     check in the handoff is next.
   - B (calculators, `_shared/coach_calculations.ts`) is in review. Its merge gate is the direct
     DeepSeek eval, before and after. Then owner-device acceptance and Sentry verification.
2. Meal photos need their own AI consent before anyone other than the owner uses them: the AI
   coaching notice covers DeepSeek and says photos are not sent, but meal photos go to Groq. See the
   backend handoff, "Meal photos".
3. Approve a coherent visual direction and then redesign from the current product truth; do not
   copy a competitor's protected assets or flows.
4. Complete the Apple AI-consent/App Review review, privacy/legal review, pricing decision, developer
   account/entity decision, and brand/IP clearance before expanding beyond owner dogfooding.
5. Refresh dependencies in small reviewed batches; old Dependabot PRs were based on obsolete code
   and checks and are not release candidates.
   - Batch 1 (2026-09-30): `supabase_flutter` 2.17.2, `shared_preferences` 2.5.5, `uuid` 4.6.0,
     and in-range transitive updates. The passkeys and `ua_client_hints` pods left with the old
     `gotrue`. A network failure during a function call now arrives as `FunctionsFetchException`,
     so Health maps it to "Connection lost" (`healthSyncFailureMessage`).
   - `health` 13.3.2 (2026-09-30, after batch 1): it rewrote its iOS plugin in Swift. The iOS
     release build fails with "Definition of 'HealthPlugin' must be imported from module
     'health.Swift'" only in a checkout that built 13.3.1 before: `flutter clean` leaves the old
     `HealthPlugin.h` in that checkout's `build/ios/Release-iphoneos/health` (`build` links to the
     checkout's own build folder under `.tooling`). Delete that folder once. CI builds from scratch. Its new iOS 15 minimum is below the app's 17.
   - GitHub Actions: `actions/checkout` v4 → v5 and the last `supabase/setup-cli@v1` → v2, for the
     Node.js 20 deprecation warning GitHub showed on every job.
   - Majors not taken: `cupertino_icons` 2.0.0 and the pinned `device_info_plus` override.

## What happens next

UI polish, one PR per screen, in the order in [`docs/handoff/ui-polish.md`](./handoff/ui-polish.md).
Each PR changes only Flutter code and docs, so it needs a device install from merged `main` and no
backend deploy. AI coaching needs the athlete's consent, asked in onboarding and once for existing
accounts; for server enforcement status, see the backend handoff, "AI coaching consent".

## Sources of truth

- Product and system behavior: `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/DATA_MODEL.md`
- Safety, security, and privacy: `docs/AI_SAFETY_SPEC.md`, `docs/SECURITY_PRIVACY.md`
- UX and visual rules: `docs/UX_FLOWS.md`, `docs/DESIGN_SYSTEM.md`
- Algorithms and tests: `docs/ALGORITHMS.md`, `docs/TESTING_STRATEGY.md`
- Release process: `docs/CI_CD_DEPLOYMENT.md`
- Historical progress, plans, and handoffs: `docs/archive/`

Historical artifacts explain prior decisions but are not instructions for current work.
