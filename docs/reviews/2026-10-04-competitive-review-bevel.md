# Competitive review: Bevel and the AI-trainer field — 2026-10-04

**Scope:** the owner found Bevel (bevel.health) during the first week of device testing. It
looks close to Tracend and polished. Questions: what Bevel really is; where Tracend is
different, better or behind; what to learn and build; what else in the market is like Tracend;
and how to build the gaps efficiently.

**Method:** read-only. No product code was changed.

- **Bevel dossier:** from the App Store listing, Bevel's help centre, privacy policy, press
  coverage and independent reviews.
- **Field profile:** 15 competitors, from primary sources where they could be reached.
- **Tracend inventory:** verified against the code at `1da7ea2` (main after #83), with file
  paths.
- **Spot checks in this session:** the claims this review leans on were re-checked against
  primary sources:
  - the App Store listing (version, ratings, prices)
  - Bevel's pricing article
  - the court docket for the WHOOP lawsuit
  - Future's AI shutdown
  - WHOOP's AI hallucination reports
  - Apple's Mulberry change
  - in Tracend's code: the missing plan-change path, the meal-photo consent gap, and the
    absent widget, Watch and Live Activity targets

Bevel itself was not installed or used. Its features come from its own listing, help centre
and reviews, not from hands-on testing. Claims that rest on one source, or that a competitor
reported about itself, are marked in "Not verified".

This review builds on the market section of
[2026-09-04-full-project-review.md](./2026-09-04-full-project-review.md). Bevel has changed
a lot since then: its core went free, it launched Pro and its AI coach, added training plans,
and was sued by WHOOP.

## Verdict

1. **Bevel is the closest app to Tracend in the market, but it does a different job.**
   - **Bevel:** a very broad, free health *dashboard* (scores, food, strength, cycle, journal,
     labs), with a paid AI chat coach on top.
   - **Tracend:** a *trainer*. It writes your plan, makes one evidence-based decision each day,
     and changes the plan only with your approval.
   - Do not chase Bevel's breadth. A software app with about 20 people, $14M in funding and a
     free core already owns "dashboard of everything" on iPhone.
2. **Tracend's real differentiators are rarer than they look, and one is only half built.**
   - **Built and genuinely unusual:**
     - deterministic, explainable recovery, with drivers and an "How this is calculated" panel
       that says "No AI";
     - a null instead of an invented number;
     - an AI that interprets but never calculates;
     - AI-proposed meals that you confirm.
   - **Only half built:** approval-gated plan changes with versions and an audit trail exist
     for onboarding only. After onboarding the coach cannot propose a plan change: the server
     rejects any daily decision that carries one. Closing that loop is the single most valuable
     thing to build next. Nobody else has it, and it answers the market's main objection to AI
     coaching: whether to trust it.
3. **The market is moving towards Tracend's thesis.**
   - **WHOOP:** its AI coach is publicly caught inventing data.
   - **Future:** shut down its AI trainer in June 2026 and went back to human coaches.
   - **Survey data:** only 10% of consumers prefer AI guidance to a human (Les Mills 2026,
     10,000+ people).
   - **Apple:** scaled back its AI health coach in February 2026.

   "An AI coach you can audit and that never acts without you" is an open position.
4. **Tracend is behind on table stakes that cost little to close**, because most of the
   plumbing already exists:
   - widgets
   - barcode scanning, a food database and saved foods
   - background HealthKit sync
   - meal reminders
   - mid-workout edits (add a set, substitute an exercise)
   - showing the coach's evidence and today's adjustments on Today
5. **Act on two risks before any account other than the owner's:**
   - the meal-photo AI has no consent check;
   - WHOOP's patents cover "physiological data → automated exercise and sleep
     recommendations". Get an IP check before any commercial launch.

## Bevel at a glance (verified)

| Fact | Detail | Source |
|---|---|---|
| Name on store | "Bevel: AI Health Coach – Exercise, Sleep & Nutrition", v3.2.2 (2026-10-03), iOS 18+ | App Store |
| Ratings | 4.8★, 17K US ratings (#142 Health & Fitness); site claims 49.1K global | App Store, bevel.health |
| Company | Finerpoint, Inc., New York; founded late 2023; ~20 people; $4M seed + $10M Series A (General Catalyst) | TechCrunch 2025-10-30, the5krunner |
| Users | 100K+ DAU and 80%+ 90-day retention (Oct 2025, company-reported); ~500K MAU (Apr 2026); "2.5M members" on site (likely cumulative) | TechCrunch, Fitt |
| Free | Recovery, Sleep, Strain, Stress, Energy Bank, nutrition (barcode, photo, text, 6M+ foods, recipes), Strength Builder (700+ exercises, Watch app), cycle, journal, widgets | Bevel pricing article, App Store |
| Pro | $14.99/mo or $99.99/yr: Bevel Intelligence (chat, check-ins, plans), Health Records, Biological Age, training plans; weekly AI allowance plus credit packs $4.99–$49.99 | App Store, Bevel pricing article |
| AI | Chat with memory, scheduled check-ins (daily, weekly, monthly), multi-week plans it can "create, review, and schedule or migrate", meal plans, lab analysis, web search; four personalities (Commander, Friend, Guardian, Data Nerd); LLM sub-processors Google, Anthropic, OpenAI, Baseten | App Store, help centre, privacy policy |
| Scores | Recovery 1–100% (sleep score, HRV during sleep, RHR, wrist temp, resp rate, SpO₂); Strain 0–100%+ logarithmic; 60-day rolling baselines; inputs published, **weights not published** | Help centre |
| Lawsuit | Whoop, Inc. v. Finerpoint, Inc., D. Del. 1:26-cv-00289, filed 2026-03-17: trade dress, copyright, four patents on physiological data → exercise and sleep recommendations; jury trial set for September 2028 | Court docket, law.com, the5krunner |

**What reviewers praise:**
- a polished design and a "ten-second morning check";
- the free tier is a real product;
- food logging, especially photo and barcode;
- it replaces several apps;
- it is cheaper than WHOOP.

**What they complain about:**
- **Black-box scores:** it does not show which input moved them.
- **Data without guidance:** "big on data, but falls short on guidance" (Lifehacker).
- **Shallow depth:** strength and nutrition are shallower than specialist apps.
- **Battery drain.**
- **Sync:** needs the app opened.
- **3.0 redesign:** it alienated some users.
- **Price:** Pro is the most expensive in its category, plus credit metering.
- **Overnight wear:** the Watch must be worn overnight.

**Top requests on its feedback board:**
- sync with MacroFactor or Lose It
- dynamic calorie targets (TDEE)
- supplement tracking
- fewer taps to log food
- background sync

## Side by side: Bevel vs Tracend

✅ built · ◐ partial · ✗ not built · — out of scope by decision

| Area | Bevel | Tracend (verified at `1da7ea2`) |
|---|---|---|
| Recovery score | ✅ black box (inputs listed, weights hidden) | ✅ **explained**: five driver rows, weights and z-scores in "How this is calculated", "No AI" (`recovery_readout_card.dart`, `ALGORITHMS.md`) |
| Missing data | Scores shown daily; reviewers say they look more precise than they are | ✅ null instead of invention; confidence tiers; "No data" rows |
| Strain | ✅ headline ring, Target Strain range | ◐ calculated (daily strain, ACWR, monotony), shown only in a driver row and the Train load sheet; no Today readout |
| Sleep | ✅ score, need, sleep bank, smart alarm | ✅ quality score with four sub-scores and debt; ✗ hypnogram, ✗ alarm |
| Stress / Energy Bank | ✅ | ✗ (not planned) |
| HealthKit inputs | HRV, RHR, sleep, resp, SpO₂, wrist temp, HR zones, steps | HRV (SDNN), RHR, sleep stages, resp, steps, active energy, weight, workouts; ✗ SpO₂, ✗ wrist temp, ✗ HR samples |
| Background sync | ✗ (users ask for it) | ✗ sync only when Today opens or on pull to refresh |
| Training plan | ✅ AI-generated multi-week plans (Pro) | ✅ AI plan proposed at onboarding, checked by deterministic policy, **approved by the athlete**, versioned |
| Changing the plan later | ✅ AI can create and "schedule or migrate" plans | ✗ **not built**: `persist_daily_coaching_result_v2` rejects any daily decision with change proposals; no in-season proposal or diff screen |
| Daily decision | ✗ (scores plus chat) | ✅ coach-decide: proceed / adjust / gather data / review / escalate, with evidence, risk flags and missing data |
| Today's adjustments shown | n/a | ◐ produced on the server; the Flutter model does not parse `today_adjustments`; the coach note shows only text and reason |
| Workout logging | ✅ Strength Builder, Watch live sync, plate calculator, supersets, videos, Live Activity | ✅ focus logging, prefill, last time and best, RPE, pain chip, rest timer, new-best moment, offline draft; ✗ Watch, ✗ Live Activity, ✗ add/remove set, ✗ substitution UI (the server supports it) |
| Muscle view | ✅ Muscular Load, Muscle Freshness | ✅ 2.5D muscle map (shown at ≥75% coverage) |
| Progression | ✅ AI progressive-overload suggestions | ◐ plan rule text plus prefill; no load-progression engine |
| Exercise library | ✅ 900+ with videos | ◐ 72-exercise catalog (onboarding allowlist) plus reviewed muscle names; no browser or videos |
| Food logging | ✅ photo, barcode, text, 6M+ database, recipes, CGM | ◐ photo AI with confirm step, plus manual entry; ✗ barcode, ✗ database, ✗ saved foods UI (the `user_foods` table exists) |
| Targets | Static goals (dynamic TDEE is a top request) | ✅ from the approved plan; ◐ not editable; macro adherence calculated but not shown |
| Meal schedule | ✗ | ✅ timeline, next meal, fuel rail on Today; ✗ editor, ✗ reminders (`reminder_enabled` column unused) |
| AI chat | ✅ memory, web search, personalities, credits | ✅ full athlete context, "Calculated by Tracend" block, evidence, data gaps and "How the Coach reasoned" per answer, fallback when the model fails, preference chips you confirm |
| AI honesty architecture | LLM over data | ✅ deterministic calculations; the model only interprets; numbers come from SQL |
| Weekly review | ✅ AI check-ins (Pro) | ✅ deterministic weekly review (free of AI) |
| Progress | ✅ trends, body projections | ✅ weight trend, measurements, strength bests, private photos, physique check (owner only) |
| Widgets / Watch / Live Activity | ✅ / ✅ / ✅ | ✗ / ✗ / ✗ (only Runner and RunnerTests targets) |
| Notifications | ✅ check-ins, reminders | ◐ local only: check-in 19:00, weekly review, rest timer |
| Activity status (sick, travel, injured) | ✅ | ✗ |
| Health records / bio age | ✅ (Pro) | — excluded (medical-report analysis) |
| Cycle / caffeine / water / journal | ✅ | — not planned; check-in covers mood, energy, soreness, pain |
| Privacy | Pseudonymised prompts, 3-day retention at providers, not HIPAA-covered | ✅ RLS everywhere; per-purpose AI notices; encrypted export; delete account; ◐ meal-photo consent missing |
| Sign-in | Sign in with Apple | ✗ email and password only (owner beta) |
| Price | Free core; Pro $99.99/yr plus credits | — no subscriptions in MVP |

## Where Tracend is genuinely different, and should stay that way

1. **Explainable scores.** Bevel's most-cited weakness is that it never says why recovery is
   62. Tracend's drivers card and "How this is calculated" panel do exactly that. Publishing the
   method (from `ALGORITHMS.md`) also meets Apple's health-score disclosure expectations, and
   competitors cannot match it without exposing their IP.
2. **Honesty about missing data.** Bevel and WHOOP show a score every day. Tracend shows "No
   data", lowers its confidence and says what is missing. That is a trust feature: market it,
   don't apologise for it.
3. **The AI never calculates.** WHOOP's documented failures ("I invented 'more awake last
   night' without data", Gear Patrol, Jul 2026) cannot happen by design. The numbers come from
   SQL, and the model is limited to the evidence it is given.
4. **One decision a day, not a wall of numbers.** Reviewers fault Bevel for "data without
   guidance". Tracend's coach-decide gives one action with evidence. This is the product.
5. **AI proposes, you confirm.** It already applies to onboarding plans, meal photos and coach
   preferences. Photo calorie apps are criticised for accuracy, so the confirm step is a selling
   point, not friction.
6. **A plan with an ending.** Everyone sells endless tracking. Tracend sells a 5–6 month plan
   (from the 2026-09-04 review). Keep it.
7. **Meal timing.** Bevel has no meal schedule. Tracend's schedule, next meal and fuel rail
   are rare in the field.

## Where Tracend is behind (prioritised)

Each gap shows the cost (S, M or L), with notes on existing plumbing that makes it cheap.

| # | Gap | Why it matters | Cost |
|---|---|---|---|
| G1 | **No plan changes after onboarding** (the coach cannot propose; no diff or approval screen) | It is the differentiator, and it isn't live. A coach that can never change your plan isn't a trainer. | **M–L.** Reuse `change_proposals`, the onboarding proposal view, plan versions and audit events; this is also the planned calibration / re-plan PR |
| G2 | **Today doesn't show the coach's adjustments or evidence** | The daily decision is the product, but Today shows only its text. "Reduce to 3 sets today" should appear on the workout. | **S–M.** The server already produces `today_adjustments` and evidence; parse and show them |
| G3 | **Meal-photo AI has no consent check** (`meal-analyze`) | An Apple 5.1.2(i) and privacy blocker before any account other than the owner's | **S.** The per-purpose notice system exists; add a `meal_photo` purpose naming the provider |
| G4 | **No widget** | The category's main cause of churn is low usage; Today has to escape the app. Bevel, Athlytic and Fitbod all ship widgets. | **M.** A WidgetKit extension reading a small JSON the app writes (recovery, today's workout, protein to go) |
| G5 | **No barcode, food database or saved foods** | Logging food is the most frequent action; photo alone is slow for packaged food | **M.** Barcode via a scanner plugin plus Open Food Facts (free); `user_foods` already exists for saved foods |
| G6 | **No background HealthKit sync** | Scores go stale until the app opens. It is one of Bevel's top complaints too, so it's a chance to beat them. | **M.** HealthKit background delivery plus an observer query calling `health-sync` |
| G7 | **No mid-workout edits** (add or remove a set, substitute an exercise) | Hevy and Strong set the bar for fast logging; real sessions deviate | **M.** The server supports substitution (slug trigger, truth repair); the UI is missing |
| G8 | **Strain not on Today; no activity status** | Bevel's three-number morning check; travelling or sick days currently look like bad recovery | **S** each. Strain is already calculated; status is one table plus a check-in option feeding confidence and coach-decide |
| G9 | **No meal reminders** | The meal schedule exists but never nudges | **S.** `reminder_enabled` plus the existing `TracendNotifications.swift` |
| G10 | **No load-progression engine** | JuggernautAI and Dr. Muscle charge $350–400/yr for automatic progression | **M.** Deterministic double progression from logged reps and RPE, offered as a proposal (it fits G1) |
| G11 | **No Watch app or Live Activity** | Table stakes for strength apps (Bevel, Fitbod, SensAI) | **L** for Watch, **M** for Live Activity; do after G1–G9 |
| G12 | **Smaller gaps** | Plan-version history screen; macro adherence not shown; targets not editable; no hypnogram; no exercise videos or browser; Sign in with Apple; Terms and Privacy links | S–M each |

## What to learn from Bevel

**Adopt (fits Tracend, cheap):**
- **The ten-second morning check.** Recovery, sleep and strain at a glance on Today. Our hero
  already has recovery and vitals; add a strain readout (G8). *Do not copy WHOOP's or Bevel's
  three-ring layout:* that layout is the trade dress in the lawsuit.
- **Activity status:** travelling, sick, injured or on a break (G8). It feeds confidence and
  coach-decide, so a bad-data day isn't read as bad recovery.
- **Proactive check-ins.** Tracend has the deterministic weekly review. Add a short morning
  push ("Recovery 71, Upper body A as planned, 92 g protein to go") when the brief is ready,
  using local notifications. No AI needed.
- **Widgets** (G4) and **barcode, database and saved foods** (G5): table stakes Bevel gives
  away for free.

**Adapt (good idea, Tracend-shaped):**
- **Coach personality.** Bevel offers four tones. Tracend could offer a tone preference
  (direct or encouraging) through the existing confirmed preference chips, affecting wording
  only, never the decision or evidence. Low cost; do it only if testers ask.
- **AI-built plans you can "schedule or migrate".** Bevel lets the AI create and move plans.
  Tracend's version is G1: the AI proposes and you see the diff, approve, and get a new version
  you can roll back. It is the same capability, made trustworthy.
- **Muscle freshness.** Bevel and Fitbod show per-muscle readiness. Tracend's muscle map could
  later colour by days since each muscle was trained, using deterministic logged volume (no AI).

**Avoid:**
- **Health records and biological age:** excluded (medical-report analysis), with liability.
- **Caffeine, water, cycle, journal, CGM:** breadth that dilutes the trainer and that Bevel
  already does free.
- **Metered AI credits:** users dislike them. If Tracend charges later, the coach should be
  effectively unlimited for normal use.
- **The three-ring score layout, and copying WHOOP's or Bevel's visuals:** active litigation.
- **Big-bang redesigns after launch:** Bevel's 3.0 lost some loyal users. Ship changes in small
  steps once there are real users.

## Other apps like Tracend

| App | What it is | AI model of work | Price | Signal | Relevance to Tracend |
|---|---|---|---|---|---|
| **Bevel** | Software health dashboard + AI coach | Chat, check-ins, AI plans you schedule or migrate | Free; $99.99/yr Pro | 4.8★ 17K US; $14M raised | **Closest overall** |
| **WHOOP** | Strap + subscription | OpenAI chat; builds workouts from a prompt; suggests a de-load when recovery is low | $199–359/yr | 2.5M+ members; $10.1B valuation | Same score thinking; **AI caught inventing data**; no real nutrition |
| **Oura** | Ring + membership | Advisor chat with charts; photo meals rated for quality | $69.99/yr + ring | 5M paid members; IPO filed | Sleep authority; no training plans |
| **Google Health Coach** | Gemini fitness, sleep and wellness coach | Conversational plans; photo and voice meals | $9.99/mo | Bundled with Google AI Pro | Matches on paper; **not available for Apple Watch** |
| **Vora** | All-in-one AI coach, any wearable | Chat (capped) plus a daily plan from readiness | $89.99/yr | ~108 ratings | Same concept, early and very broad |
| **SensAI** | LLM coach writing training from HealthKit | Generates programmes from recovery | $69.99/yr | ~30 ratings | Same concept, no traction |
| **Athlytic** | Low-cost WHOOP alternative | Mostly deterministic scores; small Q&A | $29.99/yr | 4.8★ 11K | Price anchor for scores alone |
| **Gentler Streak** | Recovery-aware activity guidance | Deterministic suggestions | $39.99/yr | Apple Design Award 2024 | Validates the "no drill sergeant" tone |
| **Fitbod** | Algorithmic gym sessions | Auto-generates each session from logged volume | $95.99/yr | 4.8★ 287K | Muscle-map benchmark; ignores sleep, HRV and food |
| **JuggernautAI / Dr. Muscle** | Algorithmic strength | Daily readiness → auto-adjusted programming, deloads | $350–400/yr | Niche, high price | Proves people pay for progression (G10) |
| **Hevy / Strong** | Set loggers | Hevy Trainer auto-progresses, "not AI" | $24–30/yr | 4.9★ ~100K | Logging-speed bar (G7) |
| **MacroFactor / Cal AI** | Nutrition | Adaptive targets / photo logging | $72/yr / — | Cal AI acquired by MyFitnessPal | Photo logging is commodity; accuracy and confirming are where apps differ |
| **Future / Ladder** | Human coaches / coach-led teams | Humans write plans | $149–199/mo / $180–480/yr | Future dropped AI (June 2026); Ladder ~150K paid | Ceiling for paid judgment; trust beats automation |
| **Apple** | Workout Buddy (watchOS 26) | Spoken in-workout feedback, generated on device | Free | Mulberry coach scaled back (Feb 2026) | No Apple coach for at least 6–12 months (inference) |
| **Runna, Garmin Connect+, Welltory, Rise** | Running plans / Garmin AI / HRV / sleep | Various | $70–150/yr | — | Adjacent, not direct |

**Synthesis:**
- **Closest to Tracend's exact combination:** Bevel, then WHOOP (hardware, no real nutrition).
  Vora and SensAI match the concept but are tiny.
- **Not credibly done by anyone:**
  - a proposed plan change shown as a diff, with its evidence, as a new version you approve
    and can roll back;
  - one daily decision applied to today's actual prescribed sets and meals;
  - scores whose method you can read.

**Table stakes in 2026:**
- recovery, sleep and strain scores
- an AI chat with memory
- photo, barcode and text food logging
- AI workout generation
- per-exercise history and PRs with a muscle view
- a Watch logging app
- fast set logging
- widgets
- a free tracking tier

**Pricing norms:**
- **All-in-one AI coach:** $70–100/yr.
- **Strength specialists:** up to $400/yr.
- **Human coaches:** $1,800+/yr.

Not relevant during the MVP (no subscriptions).

## Recommended plan (efficient order)

Rules carried through:
- **No new features during the test week.** Fix only what testing surfaces.
- **Reuse existing plumbing before building anything new.**
- **Respect the MVP exclusions.**

### Now, during the test week (blockers only)
1. **G3 meal-photo consent.** Add a `meal_photo` AI-notice purpose naming the provider;
   `meal-analyze` refuses without it. S.
2. **Terms and Privacy links** in onboarding: the open public-release blocker. S.

### Next, the first PR after testing: "close the coaching loop" (the moat)
3. **G2 show the decision on Today.** Parse `today_adjustments` and the evidence; show "Coach:
   3 sets instead of 4 today, because HRV is low for you" on the workout card, and apply it as
   a suggestion in focus logging. S–M.
4. **G1 in-season plan proposals.**
   - **What can be proposed:** coach-decide (or a weekly deterministic rule) can propose a
     bounded change:
     - a deload week
     - volume ± one set
     - an exercise swap from the catalog
     - calorie or protein target ± a step
   - **Where it goes:** into `change_proposals`, shown as a diff screen (reuse
     `onboarding_proposal_view.dart`). Approve creates a new plan version plus an audit event;
     reject records the reason.
   - **Two-week calibration:** this is also the planned calibration / re-plan PR.
   - **Size:** M–L.
5. **G8 strain readout and activity status.** S each; these feed G1's evidence.

### Then, table stakes in one sweep
6. **G9 meal reminders.** S.
7. **G5 barcode** (Open Food Facts) **and saved foods** (`user_foods`). M.
8. **G7 add or remove a set, and substitution UI.** M.
9. **G6 background HealthKit delivery.** M.
10. **G4 home-screen widget:** recovery, today's workout, protein to go. M.

### Later
11. **G10 progression engine:** deterministic, offered as G1 proposals.
12. **G11 Live Activity**, then a Watch app.
13. **Smaller items:** plan-version history, editable targets with approval, macro adherence
    card, hypnogram, exercise videos, Sign in with Apple, a tone preference, muscle freshness.

### Why this order is efficient
- G2 and G1 reuse the decision payload, the proposal tables, the onboarding proposal view and
  plan versioning that already exist. The moat ships for a fraction of a new feature's cost.
- G3, G9 and G8 are each a few hours on existing systems.
- The table-stakes sweep comes before any Watch work because each item is M and benefits every
  session.

## Risks

- **IP.** WHOOP's four asserted patents cover analysing physiological data to give automated
  exercise and sleep recommendations, which describes Tracend's core loop too.
  - The WHOOP v. Bevel trial is set for September 2028.
  - Tracend's deterministic, published, evidence-traceable approach is a philosophical hedge,
    not a legal one.
  - **Get a real IP review before any commercial launch** (repeats 2026-09-04).
- **Trade dress.** Avoid three-ring score layouts and WHOOP or Bevel visual idioms. Tracend's
  single 270° dial with graphite and lime is distinct; keep it that way.
- **AI consent and provider disclosure.** Fix G3 before testers. Keep per-purpose notices for
  every new AI use, including tone and proposals.
- **Breadth temptation.** Bevel's feature list is long because its business is engagement
  with a dashboard. Tracend's is outcomes against a plan; every feature should serve the
  daily decision or the plan.

## Not verified

- Bevel's score weights (not published); which LLM powers which Bevel feature.
- Bevel 3.0 details beyond the help centre and App Store, and the exact homepage wording of
  "HIPAA and SOC 2".
- ScreensDesign's estimate of about $750K a month in revenue (third-party, method unknown).
- What "2.5M members" counts.
- Reddit sentiment (r/bevelhealth could not be fetched).
- Competitor-sourced figures: SensAI and Vora traction, Future's rating, the Cal AI accuracy
  study, the prices for Dr. Muscle and Ladder tiers.
- WHOOP feature details: WHOOP's own pages returned 403, so these come from secondary coverage.
- The 6–12 month window before an Apple coach is an inference from Bloomberg's report, not a
  fact.

## Sources

**Bevel**
- https://www.bevel.health
- https://apps.apple.com/us/app/bevel-ai-health-coach/id6456176249
- https://help.bevel.health/en/articles/11583937 (pricing)
- https://help.bevel.health/en/articles/11194113 (features by version)
- https://help.bevel.health/en/articles/11251073 (key terms)
- https://help.bevel.health/en/articles/11258177 (recovery)
- https://help.bevel.health/en/articles/11586817 (Intelligence)
- https://www.bevel.health/privacy-policy
- https://feedback.bevel.health
- https://techcrunch.com/2025/10/30/bevel-raises-10m-series-a-from-general-catalyst-for-its-ai-health-companion/
- https://gadgetsandwearables.com/2025/12/21/bevel-app-free/
- https://gadgetsandwearables.com/2026/05/16/bevel-3/
- https://www.healthappinsider.com/en/reviews/bevel-review
- https://australianapplenews.com/2026/01/07/review-bevel-a-health-app-that-ticks-almost-all-the-boxes/
- https://www.autonomous.ai/ourblog/bevel-app-review
- https://neura.health/insight/bevel-health-app-in-depth-review
- https://tech.yahoo.com/wearables/articles/bevel-sort-makes-apple-watch-230000160.html

**WHOOP v. Bevel**
- https://www.pacermonitor.com/public/case/63631790/Whoop,_Inc_v_Finerpoint,_Inc
- https://www.law.com/radar/card/pm-63631790-whoop-inc-v-finerpoint-inc/
- https://the5krunner.com/2026/04/04/whoop-sues-bevel/

**Market signals**
- https://athletechnews.com/future-pulls-the-plug-on-ai-personal-training-commits-to-human-coaches/
- https://www.gearpatrol.com/fitness/whoop-ai-reddit-user-feedback-pros-cons/
- https://9to5mac.com/2026/02/05/apple-reportedly-scales-back-plans-for-ai-powered-health-coach/
- https://techcrunch.com/2026/05/07/googles-9-99-per-month-ai-health-coach-launches-may-19/
- https://ouraring.com/membership
- https://techcrunch.com/2026/09/21/ouras-2-2b-ipo-is-mostly-a-payday-for-existing-shareholders/
- https://hlth.com/insights/news/whoop-secures-575m-series-g-round-reaching-10-1b-valuation-2026-04-01

**Competitors**
- https://askvora.com/features
- https://apps.apple.com/us/app/athlytic-ai-fitness-coach/id1543571755
- https://www.healthappinsider.com/en/reviews/gentler-streak-review
- https://apps.apple.com/us/app/fitbod-gym-fitness-planner/id1041517543
- https://www.garagegymreviews.com/juggernautai-review
- https://insider.fitt.co/ladder-raises-105m-for-strength-training-app/
- https://arvo.guru/vs/macrofactor
- https://www.apple.com/newsroom/2025/06/watchos-26-delivers-more-personalized-ways-to-stay-active-and-connected/
