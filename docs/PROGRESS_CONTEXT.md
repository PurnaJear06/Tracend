# Tracend Progress Context

**Purpose:** tiny live dashboard and pointer index, not a history dump.

This file is operational only and never overrides `AGENTS.md` or authoritative
product, architecture, data, safety, privacy, UX, testing, roadmap, or cost docs.

## Required Agent Flow

Every agent working in this repo must:

1. Read `AGENTS.md`.
2. Read only the authoritative docs relevant to the task.
3. Read this dashboard.
4. Open the scoped handoff file for the active workstream.
5. Inspect the actual files before editing.
6. After material work, update the scoped handoff file and this dashboard.
7. Add or update a worklog only when detailed history is useful.
8. Add an ADR only for expensive-to-reverse decisions.

## Context Layers

| Layer | Path | Purpose | Read by Default |
| --- | --- | --- | --- |
| Rules | `AGENTS.md` | Mandatory agent behavior | Yes |
| Authority | `docs/*.md` specs | Product, architecture, data, safety, UX, testing | Relevant only |
| Dashboard | `docs/PROGRESS_CONTEXT.md` | Current phase, owners, pointers | Yes |
| Handoff | `docs/handoff/*.md` | Current state per workstream | Relevant only |
| Worklog | `docs/worklog/*.md` | Detailed dated history | Only when needed |
| ADR | `docs/adr/*.md` | Durable decisions and consequences | When relevant |

## Current Phase
Phases 1–8 are hosted; approved owner-device QA is complete.
## Active Workstreams

| Workstream | Status | Read Next | Detail History |
| --- | --- | --- | --- |
| Backend foundation | **Complete — verified** | `docs/handoff/backend.md` | `docs/worklog/2026-06-28-phase-1-foundation.md` |
| Frontend/UI shell | **Complete — verified by iPhone release build** | `docs/handoff/frontend.md` | `docs/worklog/2026-06-28-phase-1-foundation.md` |
| Stitch/design handoff | **23 references imported; AI Usage detail pending** | `docs/handoff/design.md` | `design/stitch/README.md` |
| Product/architecture scope | Stable MVP docs | Relevant authority docs | ADRs as needed |
| Phase 2 auth decision | **Owner email/password mode approved** | `docs/adr/0002-owner-development-auth.md` | — |
| Phase 2 vertical slice | **Hosted; iPhone login/onboarding reached** | frontend/backend handoffs | `docs/worklog/2026-07-01-phase-2-local.md` |
| Phase 3 workout/check-in | **Hosted; iPhone check-in/restore verified** | frontend/backend handoffs | `docs/worklog/2026-07-01-phase-3-workout-check-in.md` |
| Phase 4 HealthKit summaries | **Complete — hosted and iPhone verified** | frontend/backend handoffs | `docs/worklog/2026-07-01-phase-4-healthkit.md` |
| Phase 5 controlled coaching | **Complete — hosted and iPhone verified** | backend/frontend handoffs | `docs/worklog/2026-07-02-phase-5-controlled-coaching.md` |
| Phase 6 nutrition/meals | **Complete — hosted and iPhone verified** | backend/frontend handoffs | `docs/worklog/2026-07-02-phase-6-nutrition.md` |

## Global Current State

- Phase 1 is complete. External SSD is mandatory for all tooling, caches,
  container state, and generated artifacts.
- Backend: **complete and verified** — pgTAP 8/8 pass, Supabase CLI, migrations,
  RLS, Edge Function contracts, and mock provider all in place under `supabase/`.
- Hosted backend: repository linked to Supabase project
  `qsfzzsjenopqqqhvpyaw` in Southeast Asia (Singapore); the Phase 1 foundation
  migration was deployed successfully, and hosted pgTAP passed 8/8 on
  2026-06-29.
- Design: **sixteen authentication/onboarding references** are imported under
  `design/stitch/onboarding/`; **Account/Profile** is imported under
  `design/stitch/account/`. The My AI Usage detail remains pending.
- Navigation: five tabs confirmed — Today · Train · Coach · Nutrition · Progress.
- Frontend: owner email/password auth, session restoration, beginner and
  experienced onboarding, approval, sign out, and five-tab shell are complete.
- Backend: two forward-only Phase 2 migrations add consent/profile/draft/goal,
  immutable snapshot, proposal, plan/target versioning, audit, service-only mock
  persistence, and transactional response contracts. Deno checks pass and
  pgTAP passes 39/39 for two isolated users across both onboarding paths.
- Hosted: migration versions `20260701090000` and `20260701100000` match local
  and remote; `onboarding-propose-plan` is ACTIVE at version 1 as of 2026-07-01.
- Phase 3 workout/check-in is hosted; migration `20260701120000` matches remote.
- Phase 4: read-only HealthKit adapter, daily/stage normalization, explicit HRV
  metric/unit, manual/partial/stale/unavailable states, authenticated sync,
  service-only persistence, provenance validation, RLS, and idempotency are
  hosted. Migration `20260701140000` matches remote and `health-sync` version 1
  is ACTIVE. Deno tests pass 9/9, database pgTAP passes 81/81, and Flutter tests
  pass 33/33.
- The signed Phase 4 build is trusted on the owner's iPhone 12. Apple Health
  permission and authenticated partial refresh passed: seven summaries were
  accepted and none rejected across three sync runs.
- Signed hosted build is installed/trusted on the owner's iPhone 12. Login,
  onboarding entry, check-in save, app restore, and workout restore work.
- UI fidelity pass is installed on iPhone across all built primary surfaces.
- Sign in with Apple remains deferred. No anonymous auth,
  client-supplied identity, secret key, or live provider call was added.
- Phase 5 local: deterministic policy, mock `coach-decide`, forced RLS, usage,
  Today/Coach UI; Deno 16/16, pgTAP 101/101, Flutter 35/35, iOS build pass.
- Phase 5 hosted: migration `20260702090000` matches remote, `coach-decide`
  version 7 is ACTIVE, and unauthenticated access returns sanitized HTTP 401.
  The signed 19.1 MB build launched after profile trust; Coach generation,
  Today decision state, and normal app behavior passed owner QA.
- Phase 6 approved scope is hosted/iPhone verified; live photo AI and food catalog remain deferred.
- Phase 7 foundation plus distinct-date repair are hosted through `20260702173000`; histories match. Flutter 49/49, Deno 18/18; signed build installed/launched on iPhone.
- Phase 7 foundation owner-device QA passed for measurement persistence, baseline, weekly-review preview, and private-photo guidance.
- Phase 7 private media `20260702200000` and pose-guidance owner QA passed.
- Weekly review `20260702223000` is hosted/parity verified; pgTAP 200/200, signed 19 MB app installed. Owner enqueue/worker smoke completed with zero failures.
- Phase 8/rebuild is hosted through `20260704151000`. Owner context is imported; Gemini routes are `gemini-3.5-flash` only and still disabled by billing/privacy gates. Deno 32/32, pgTAP 287/287, Flutter 65/65, signed hosted app installed/launched July 4.
- Local 2026-07-05 repair is ready but not hosted: `20260705100000` fixes placeholder meal schedule foods, Today Health evidence freshness, and Train rest-day fallback. Hosted dry-run lists only this migration. Local verification: Deno 32/32, pgTAP 290/290, Flutter format/analyze/test 65/65, unsigned iPhone build 19.3 MB.
## Global Open Decisions
- Apple Developer Program enrollment, Sign in with Apple capability, and
  TestFlight environment names before any external beta.
- Gemini remains mock pending paid privacy/evaluation gates; hosted DeepSeek and Flash-Lite are rejected for restricted-data production use.
- Licensed food catalog source.
- Explicit approval to deploy `20260705100000` to hosted Supabase and install the repaired hosted build.
## Global Known Issues
- Do not commit `.codex/config.toml`; it can contain local MCP/API keys.
- CoreSimulator remains unsuitable for the external Developer path and is not
  part of the local workflow. Do not run it or move its state internally; use
  the verified CLI iPhone build and a physical device after signing is set.
- Pinned Supabase CLI 2.101.0 times out on the local `db reset` host handshake;
  migrations were reapplied inside the healthy SSD-local container and
  pgTAP passed. Do not interpret the CLI timeout as a schema failure.
- Hosted `db dump --linked` cannot resolve the direct database hostname in the local container; weekly backup needs a reviewed pooler/dashboard path.
## Update Rules
Keep this dashboard under 120 lines. If it grows, move detail into:
- `docs/handoff/backend.md`
- `docs/handoff/frontend.md`
- `docs/handoff/design.md`
- `docs/worklog/YYYY-MM-DD-topic.md`
- `docs/adr/NNNN-topic.md`
Do not add chat transcripts, command spam, raw logs, credentials, secrets,
private health data, prompts, or generated design dumps.
