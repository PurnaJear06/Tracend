# Tracend Implementation Roadmap

**Status:** Execution order for the private-beta MVP\
**As of:** 2026-10-15\
**Constraint:** This roadmap does not expand [PRD.md](./PRD.md)\
**Program authority:** [`docs/plans/coaching-platform-2026-10/README.md`](./plans/coaching-platform-2026-10/README.md)
holds the phases, chunks, contracts, file owners and board status. This roadmap summarises it. If
they disagree, stop and report the conflict; do not choose silently.\
**Coordination:** Live state is in [PROGRESS_CONTEXT.md](./PROGRESS_CONTEXT.md) and the
per-stream files in [`docs/handoff/`](./handoff/). Completed phase plans and superseded handoffs
live under [`docs/archive/`](./archive/) and are not active instructions.

Build complete vertical slices instead of every screen, table, or AI component separately.

## 1. Where We Are

Tracend is an owner-only private beta on the owner's iPhone. Production Auth sign-ups are switched
off on top of an invite-only trigger. It is not approved for public production.

**July 2026: the MVP foundation.** The first roadmap's eight phases were built and deployed to
the Singapore Supabase project in early July, with owner-device checks along the way: the Flutter
and Supabase foundation, owner email/password auth and onboarding with explicit plan approval,
workout logging and check-ins, HealthKit summaries, controlled coaching with a mock provider,
manual meal logging with editable candidates, progress measurements and private photos, the weekly
review, and privacy export, deletion and retention. A production rebuild followed (daily brief,
training hub, persistent Coach threads, versioned meal schedules), then Coach context v4/v5,
continuity memory and a cross-layer stability pass (Sentry, backup and rollback scripts,
`health-check`, auth settings). DeepSeek became the live Coach provider on 2026-07-26 (ADR 0011).
The deterministic feature engine (ADR 0010) merged in August.

**September 2026: correctness and release safety.** Baseline dynamics, AI-context honesty and an
independent reference oracle for the scores; sleep aggregation fixes; the release foundation
(`deploy.yml` with a CI gate, dry-run, encrypted backup and isolated restore drill); and the Coach
chat reliability work (FLUTTER-8): every question gets the same full athlete file (v8), a labeled
data summary replaces a failed reply, and the app reopens the last conversation. Functions deploy
one at a time and each is checked live against the commit. AI coaching consent, meal-photo AI on
Groq, and Coach calculators followed.

**October 2026 (1–14): product depth.** UI polish, then the owner-chosen graphite and lime
redesign of every screen and a rebuilt Today with two recovery modes. Onboarding now builds an
AI-proposed plan that deterministic code validates, with coach intake questions and an owner-only
physique check. A five-PR security hardening pass (2026-10-09) added invite-only sign-ups,
Keychain session storage and SHA-pinned workflow actions. Backups moved to a private repository.
The public website and double opt-in waitlist launched on Cloudflare Pages (2026-10-13).

**2026-10-15: coaching platform program, Iteration 1.** The owner approved the program, and
Phase 0 and Phase 1 merged the same day (section 2). The restore drill now also compares
privileges and RLS flags with the migrations, and account deletion removes invite and waitlist
rows.

## 2. Current Program: Coaching Platform (October 2026)

The plan is the single source of truth for phases, chunks, contracts, migration codes and file
owners. Phases run in strict order; chunks inside a phase run in parallel. Its goals: one
provider-neutral AI gateway (Claude now, any provider later by settings), coach-grade
deterministic training rules, per-set timing and Apple Watch heart rate, a same-day re-plan
approved by the athlete, a research library behind Coach answers, widgets and a workout Live
Activity, and regional modules for a global audience. Rules decide every number; AI explains,
proposes and words.

**Phase 0 (P0): done and live (#102).** The plan, contracts and the migration-order CI check.

**Phase 1: done.** Every chunk is merged:

- B0 (#105, live): the mock decision obeys the policy; the rules plan ranks exercises by equipment
  and experience.
- A1 (#103, live): provider-neutral SQL, consent v2 and budget v2.
- A2 (#106, live): the gateway module with Claude, OpenAI-compatible and Gemini adapters. No
  feature uses it yet.
- C1 (#104, live): set start and end, actual rest, reps left, and workout events.
- D0 (#112, merged; build 395 installed): the `TracendWidgets` extension and the rest-timer Live
  Activity countdown. The owner's Lock Screen and Dynamic Island check is pending.
- E1 (#109, live): pgvector, library tables and the library search (`search_library_v1`, replaced by
  `search_library_v2` in E3, then `search_library_v3` with distances and the relevance floor in
  E3.1).
- W1 (#108, merged): site copy and privacy policy fixes and the TestFlight checklist. The site
  publish waits for the owner to set the `CONTACT_EMAIL` repository variable.
- U1 (#107, live): the glass tab bar. The owner did not like it, so a U2 design pass comes next,
  with a prototype first.

**Phase 2: next.** Move every AI feature onto the gateway and Anthropic, and build on the Phase 1
workout data:

- A3–A6: meal photo on Haiku and physique on Sonnet; onboarding plan and questions, the daily
  decision, and Coach chat on Sonnet, with a cache-friendly Coach prompt.
- A7: notices and app wording per D11 (no model names; remove DeepSeek, Groq and Qwen
  everywhere), evals, docs and the cutover runbook.
- D1: Live Activity buttons (Done, Skip, +30s). C2: a native heart-rate reader and per-set
  summaries. B1: catalog v2 and coaching-standard rule data.

**Phase 3.** Templates by goal, days and experience (B2); progression from the sets actually
logged, with targets on Train (B3); a screening gate (B6); a heart-rate profile, zones, recovery
and sleeping heart rate in shadow mode (C3); Today and Lock Screen widgets (D2); library
ingestion of the first 30 sources (E2) and the library inside Coach chat (E3).

**Phase 4.** The same-day readiness adjustment with one-tap approval (B4); deloads, cardio dosing,
joint rules, a pain check and red flags (B5); the watch-workout prompt and load signals (C4);
regional modules (E4); and plan explanations that cite sources (E5).

**After Phase 4.** The beta waits until all four phases are merged and device-checked; there is
no fixed date (D7). D11 (no model names in anything the athlete or the public reads) is a beta exit
criterion. Health data must not go to DeepSeek once external testers join, so the Phase 2 cutover
moves every feature to Anthropic before the external TestFlight group opens.

## 3. Standing Sequencing Rules

- Follow the plan's board order: strict between phases, parallel inside a phase, and each chunk
  waits for the chunks named in its "Waits for" column.
- Deterministic first. Start a feature with the deterministic rules path or a mock provider that
  uses the final schema; turn on a live model only after its evaluation passes and all of its
  server-side secrets are set together. Model output never activates a plan, confirms a meal, or
  writes a durable fact.
- The active plan stays usable when AI, HealthKit, or media processing fails.
- Migrations are forward-only and additive, and old app builds keep working. `deploy.yml` applies
  migrations before it deploys functions. Install a Flutter change only from the merged `main`
  commit, and only after the deploy has applied any migration it needs.
- Change an Edge secret that only new code accepts after that code is confirmed live.
- Physical-iPhone installation from merged `main` and the owner's device check are the release gate
  for app changes.
- Destructive tests (account deletion) run only on synthetic accounts, never on the owner's.
- Stay on the Supabase Free plan until reliability or automated daily backups make Pro worth it; do
  not upgrade just because code exists ([COST_MODEL.md](./COST_MODEL.md)).
- Do not add NestJS, Railway, a separate API server, a separate vector database, autonomous agents,
  LangGraph, Redis, microservices, medical-report analysis, Android, subscriptions, social
  features, or public-store infrastructure. `pgvector` is allowed for the research library only
  (decision D3, 2026-10-15; program E1–E5). RAG over user data stays deferred until structured
  retrieval is measured to fail. [ARCHITECTURE.md](./ARCHITECTURE.md) controls adoption.
- Keep the licensed food catalog, Sign in with Apple, and external beta distribution deferred until
  their gates are met. Sign in with Apple is the planned external-beta route (ADR 0002).

## 4. Next Actions

1. Owner: set the `CONTACT_EMAIL` repository variable so the website publishes and deploys tag
   releases again ([CI_CD_DEPLOYMENT.md](./CI_CD_DEPLOYMENT.md)).
2. Owner: the D0 Lock Screen and Dynamic Island check on the installed build.
3. U2: a design pass, prototype first, for the owner to choose from before any build.
4. Phase 2 chunks A3–A7, D1, C2 and B1, as the plan's board and chunk briefs define them.

## 5. Decision Records

Short records for choices that are expensive to reverse live in [`docs/adr/`](./adr/):

- ADR 0001: Flutter 3.41.7 and Dart 3.11.5 pinned, iOS 17.0 minimum, iPhone only.
- ADR 0002: owner email/password auth for development; Sign in with Apple is the external beta
  route.
- ADR 0003: persistent, owner-scoped Coach threads under forced RLS.
- ADR 0004: versioned meal schedules, separate from nutrition targets.
- ADR 0005: paid Gemini routing behind budget gates; never activated.
- ADR 0006: Groq Qwen owner-test routing; superseded as the Coach provider.
- ADR 0007–0009: Coach context v4 and v5 and continuity memory. Context v8 (2026-09-27) later gave
  every question the same full athlete file ([CONTEXT_BUDGET.md](./CONTEXT_BUDGET.md)).
- ADR 0010: the deterministic feature engine.
- ADR 0011: DeepSeek activated as the live Coach provider on 2026-07-26. An earlier review on
  2026-07-04 had rejected DeepSeek for restricted data; ADR 0011 records the reversal.
- ADR 0012: a compiled asset catalog for the app icon and launch screen.
- Program decisions D1–D11 (2026-10-14/15) and the decisions log live in the plan. D1 moves the
  default from DeepSeek and Groq to Claude, with the old routes kept as a settings-only rollback for
  two weeks after cutover.
