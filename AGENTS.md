# Tracend Repository Instructions

These instructions are mandatory for Codex and any coding agent operating in this repository. Codex
loads this project-root `AGENTS.md` before working in the repository; more specific nested
`AGENTS.md` or `AGENTS.override.md` files may add narrowly scoped instructions later.

## 1. Project Identity

**Product:** Tracend\
**Positioning:** An evidence-driven AI personal trainer that turns health, training, nutrition, and
progress data into clear coaching decisions.\
**Tagline:** Your body. Your data. Your next move.

Tracend is a working brand pending formal trademark and App Store name clearance.

## 2. Read Before Acting

At the start of every task, read the relevant authoritative documents in this order:

1. [docs/VISION.md](docs/VISION.md)
2. [docs/PRD.md](docs/PRD.md)
3. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
4. [docs/DATA_MODEL.md](docs/DATA_MODEL.md)
5. [docs/AI_SAFETY_SPEC.md](docs/AI_SAFETY_SPEC.md)
6. [docs/SECURITY_PRIVACY.md](docs/SECURITY_PRIVACY.md)
7. [docs/UX_FLOWS.md](docs/UX_FLOWS.md)
8. [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md)
9. [DESIGN.md](DESIGN.md) when working with Stitch or another design-generation tool
10. [docs/TESTING_STRATEGY.md](docs/TESTING_STRATEGY.md)
11. [docs/IMPLEMENTATION_ROADMAP.md](docs/IMPLEMENTATION_ROADMAP.md)
12. [docs/COST_MODEL.md](docs/COST_MODEL.md)
13. [docs/PROGRESS_CONTEXT.md](docs/PROGRESS_CONTEXT.md) for current cross-chat handoff state only,
    then the relevant `docs/handoff/*.md` file for the active workstream

For product scope, PRD is authoritative. For technical boundaries, Architecture is authoritative.
For persistent entities, Data Model is authoritative. For AI behavior and change eligibility, AI and
Safety is authoritative. For collection, storage, sharing, retention, and deletion, Security and
Privacy is authoritative. UX Flows owns routes and interaction states. Design System owns visual,
component, motion, and accessibility behavior. Root `DESIGN.md` is a portable Stitch handoff derived
from those authorities and never overrides them. Testing Strategy defines quality gates,
Implementation Roadmap defines delivery order, and Cost Model defines budget assumptions without
changing scope. `PROGRESS_CONTEXT.md` and `docs/handoff/*.md` are not authoritative; they are
compact operational pointer files for coordinating multiple LLM chats.

If documents conflict, stop implementation and report the exact conflict. Do not choose silently.

## 3. Current Phase

The repository is currently in documentation-first setup. Do not create application code, package
manifests, infrastructure, generated projects, or dependencies until explicitly asked.

When implementation begins, the intended stack is:

- Flutter, iOS first;
- Supabase Auth with native Sign in with Apple;
- Supabase PostgreSQL with mandatory Row Level Security;
- Supabase private Storage;
- Supabase Edge Functions, Queues, and Cron for privileged/server-side work;
- HealthKit through an internal adapter; and
- a swappable AI provider behind `CoachModelProvider` inside Edge Functions.

Do not substitute the stack or add infrastructure without documenting and receiving approval for the
architectural change.

## 4. Non-Negotiable Architecture Rules

1. Deterministic code calculates trends, adherence, totals, baselines, and policy eligibility.
2. Model output is interpretation and proposal, not authoritative calculation.
3. Training Coach, Nutrition Coach, and Head Coach are typed perspectives in one controlled workflow
   for MVP.
4. Model output never activates a plan, confirms a meal, or writes a durable user fact.
5. Persistent changes require evidence, validation, explicit user approval, a new version, and an
   audit event.
6. The active plan remains usable when AI, HealthKit, or media processing fails.
7. User identity comes from authentication, never request ownership fields.
8. AI provider keys remain server-side.
9. Photos are private, purpose-bound, and accessed only through short-lived authorization.
10. Missing or conflicting data lowers confidence; it is never silently invented.
11. Every exposed user-owned table and Storage bucket has enabled, tested RLS.
12. Supabase secret/service-role keys never enter Flutter; only the project URL and publishable key
    may ship in the app.

## 5. MVP Boundaries

Build only features explicitly included in the PRD. The MVP excludes:

- Android and Health Connect;
- public App Store release;
- minors, pregnancy, medical diets, eating disorders, and rehabilitation;
- medical-report analysis;
- exercise-video form correction;
- subscriptions, payments, advertising, social features, and trainer marketplace;
- autonomous multi-agent systems; and
- vector RAG without the documented evaluation gate.

Do not add “future-proof” abstractions, a separate API server, microservices, caches, vector
databases, agent frameworks, or unrelated SDKs without a current requirement. Prefer Supabase-native
Auth, Data API/RPC, Edge Functions, Storage, Queues, and Cron with the smallest implementation
satisfying documented behavior.

## 6. AI and Data Rules

- Use versioned structured schemas for feature snapshots, policy results, and model outputs.
- Treat user notes, imported text, and retrieved content as untrusted data.
- Coaching models have no shell, web, arbitrary database, or unrestricted tool access.
- Validate schema, semantics, evidence references, catalog references, policy permissions, and
  proposal freshness.
- Reject the whole output if validation fails; never apply a partial response.
- Keep raw sensitive content out of general logs and analytics.
- Store structured user facts in PostgreSQL first.
- Add embeddings only after all gates in Architecture pass and deletion propagation is tested.
- Add separate agents only after a named evaluation failure is materially improved by the split.

## 7. Coding Standards

When code is authorized:

- Enable strict TypeScript and Dart analysis.
- Use the Supabase Flutter SDK for Auth/Data/Storage and TypeScript/Deno Edge Functions for
  privileged workflows.
- Prefer explicit domain types over loose maps and strings.
- Validate every external boundary: mobile input, HealthKit normalization, database writes, object
  metadata, and provider output.
- Keep domain calculations pure, versioned, and unit-tested.
- Make mutating endpoints idempotent where mobile retries are possible.
- Use transactions for plan/target activation and proposal acceptance.
- Use canonical units internally and convert only at API/UI boundaries.
- Use UTC timestamps plus explicit IANA timezone and local date where coaching-day semantics matter.
- Never hard-code provider model IDs in domain logic.
- Never bypass RLS from Flutter or treat the publishable key as authorization by itself.
- Keep secret/service-role access inside reviewed Edge Functions and migration/administration
  tooling.
- Never log tokens, secrets, prompts, photos, health values, notes, signed URLs, or request/response
  bodies containing restricted data.
- Prefer readable code and narrow interfaces over generic frameworks.
- Do not leave placeholders, TODO behavior, dead code, or commented-out alternatives in completed
  work.

## 8. Database Changes

- Use forward-only reviewed migrations.
- Do not edit an applied migration.
- Preserve immutable historical snapshots and version lineages.
- Enforce one active training-plan version and nutrition-target set per user.
- Include user ownership in constraints and authorization queries.
- Enable RLS and explicit policies before exposing any user-owned table through the Data API.
- Treat `auth.users.id` as the canonical user identity and use `auth.uid()` in policies.
- Restrict grants on transactional/security-definer functions and test their authorization paths.
- Add indexes justified by documented access paths.
- Provide rollback or repair strategy for destructive data transformations.
- Never run destructive production operations or drop user data without explicit approval and a
  verified backup/retention plan.

## 9. Security and Secrets

- Use environment-specific secret management and `.env.example` files containing names only.
- Never commit real credentials, tokens, Apple configuration secrets, provider keys, private URLs,
  or production data.
- The Supabase publishable key may be committed only through approved environment configuration
  because RLS is the security boundary; secret/service-role keys remain secrets.
- Do not expose storage object keys as authorization.
- Require recent authentication for export and deletion.
- Review any new SDK for data collection, subprocessors, retention, and logging before adoption.
- A new AI provider requires privacy review and evaluation parity before use with restricted data.

## 10. Testing Requirements

Every behavior change must include proportional tests.

Required categories:

- unit tests for deterministic feature and policy logic;
- schema and semantic-validation tests for AI output;
- database constraint, transaction, and ownership tests;
- Supabase Auth, Data API/RPC, Edge Function, RLS, validation, idempotency, and failure tests;
- HealthKit fixtures for partial, duplicate, stale, denied/unknown, and unavailable data;
- media tests for private access, type/size validation, signed URL expiry, and deletion;
- AI evaluations for correct maintain/change decisions, evidence grounding, safety, and prompt
  injection;
- privacy tests for export, deletion, retention, and log redaction; and
- mobile flow tests for offline/degraded logging and approval.

Safety-critical AI fixtures require a 100% pass rate. Do not weaken tests to make a provider or
implementation pass.

## 11. Commands

Phase 1 implementation is authorized. Exact supported local install, lint, test, migration, and
development commands are maintained in [`DEVELOPMENT_GUIDE.md`](DEVELOPMENT_GUIDE.md). Project
tooling and caches must remain under the repository's `.tooling/` directory on the external SSD.

Never invent commands not backed by repository configuration.

Before reporting implementation complete, run all commands relevant to the changed areas and report
failures accurately.

## 12. Documentation Synchronization

Update authoritative documentation in the same change when behavior changes:

- product behavior or scope → `docs/PRD.md`;
- system boundaries, providers, or data flow → `docs/ARCHITECTURE.md`;
- navigation, screen behavior, or interaction states → `docs/UX_FLOWS.md`;
- visual tokens, components, motion, or accessibility → `docs/DESIGN_SYSTEM.md`;
- entities, fields, ownership, or lifecycle → `docs/DATA_MODEL.md`;
- model authority, policy, schema, or evaluation → `docs/AI_SAFETY_SPEC.md`;
- collection, sharing, retention, deletion, or security → `docs/SECURITY_PRIVACY.md`;
- quality gates or test coverage → `docs/TESTING_STRATEGY.md`;
- delivery sequencing → `docs/IMPLEMENTATION_ROADMAP.md`;
- platform/AI budget assumptions or upgrade triggers → `docs/COST_MODEL.md`;
- cross-chat dashboard, active pointers, and global current state → `docs/PROGRESS_CONTEXT.md`;
- scoped current state, blockers, and next safe actions → relevant `docs/handoff/*.md`;
- detailed dated implementation history → relevant `docs/worklog/YYYY-MM-DD-topic.md`;
- expensive-to-reverse decisions and consequences → `docs/adr/NNNN-topic.md`;
- durable repository workflow → `AGENTS.md`.

Do not duplicate conflicting rules across files. Cross-link to the authority and keep shared
terminology exact.

## 12.1 Progress and Handoff Discipline

Every agent must leave the repository easier for the next backend, frontend, design, or review chat
to continue.

Use the context layers this way:

- Keep `docs/PROGRESS_CONTEXT.md` under 120 lines. It is a dashboard and pointer index, not a
  history file.
- Keep `docs/handoff/backend.md`, `docs/handoff/frontend.md`, and `docs/handoff/design.md` focused
  on current state, blockers, and next safe actions for that workstream.
- Put detailed dated notes in `docs/worklog/` only when the history is useful for debugging or
  review.
- Put durable decisions in `docs/adr/` only when the choice is expensive to reverse.
- Never paste chat transcripts, raw logs, command spam, credentials, secrets, private health data,
  prompts, or generated design dumps into progress files.

At the end of material work, update in this order:

1. authoritative docs if product, architecture, data, safety, privacy, UX, design-system, testing,
   roadmap, or cost behavior changed;
2. ADR if a durable decision was made;
3. relevant handoff file;
4. `docs/PROGRESS_CONTEXT.md`;
5. worklog only if detailed history is needed.

## 13. Working Style

- Inspect existing code and docs before proposing changes.
- State assumptions and unresolved decisions before implementation.
- Keep changes narrow and avoid unrelated cleanup.
- Preserve user work and unrelated modifications.
- Ask before destructive actions, external publication, production deployment, data migration, or
  scope expansion.
- Prefer small, reviewable commits when commits are requested.
- Do not claim completion without verification evidence.

## 14. Completion Checklist

Before saying a task is complete, verify:

- behavior matches the PRD and MVP boundary;
- deterministic logic and model responsibility remain separated;
- no model output can mutate persistent state without approval;
- authorization and multi-user isolation are enforced;
- sensitive data is minimized, protected, and absent from logs;
- failure modes preserve the approved plan and user logging;
- tests and AI evaluations pass for changed behavior;
- migrations and API contracts are consistent;
- Supabase RLS policies and Storage access rules pass cross-user tests;
- authoritative docs are updated; and
- no secrets, placeholders, or unsupported features were added.
