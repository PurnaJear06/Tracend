<h1 align="center">Tracend</h1>

<p align="center">
  <strong>Evidence-driven AI personal trainer</strong><br />
  Your body. Your data. Your next move.
</p>

<p align="center">
  <a href="https://github.com/PurnaJear06/Tracend/actions/workflows/ci.yml"><img src="https://github.com/PurnaJear06/Tracend/actions/workflows/ci.yml/badge.svg" alt="CI" /></a>
  <a href="https://github.com/PurnaJear06/Tracend/actions/workflows/pre-deploy.yml"><img src="https://github.com/PurnaJear06/Tracend/actions/workflows/pre-deploy.yml/badge.svg" alt="Pre-Deploy Gate" /></a>
  <img src="https://img.shields.io/badge/Flutter-3.41.7-02569B?logo=flutter" alt="Flutter" />
  <img src="https://img.shields.io/badge/Deno-2.9.0-000000?logo=deno" alt="Deno" />
  <img src="https://img.shields.io/badge/Supabase-hosted-3FCF8E?logo=supabase" alt="Supabase" />
  <img src="https://img.shields.io/badge/AI-Groq%20Qwen%2027B-orange" alt="AI Model" />
</p>

---

Tracend gives you a personalized training and nutrition plan, observes real execution and recovery,
and produces clear daily coaching decisions — like a careful personal trainer. Plans remain stable
until evidence supports a change, and every persistent change requires your approval.

## Features

<table>
<tr>
<td width="50%">

### Today
Daily readiness dashboard with three tappable factors: Recovery, Training, and Nutrition. Apple
Health integration surfaces sleep, activity, and vitals with plain-language explanations.

</td>
<td width="50%">

### Train
Personalized workout plans with session tracking. Log sets, reps, and RPE. Apple HealthKit
auto-detects completed workouts and reconciles them with your plan.

</td>
</tr>
<tr>
<td width="50%">

### Coach
AI-powered coaching chat that remembers your history across sessions. Five-layer continuity memory
(narrative entries, preferences, session summaries, message search, and context assembly). Every
recommendation cites its evidence source.

</td>
<td width="50%">

### Nutrition
Log meals by text or photo. AI vision analyses meal photos for macros and composition.
Per-meal-slot schedule compliance tracking with 7-day adherence visibility.

</td>
</tr>
<tr>
<td width="50%">

### Progress
Weight trends, measurement history, and body metrics on a date-ordered timeline. Raw chart with no
smoothing masquerading as current data. Same-day corrections create audited amendments.

</td>
<td width="50%">

### Privacy-first AI
All AI provider keys live server-side in Supabase Edge Functions. Model output never activates a
plan, confirms a meal, or writes durable user state without your explicit approval. Photos are
private and purpose-bound, accessed only through short-lived authorization.

</td>
</tr>
</table>

## AI Stack

| Layer | Technology | Purpose |
| ----- | ---------- | ------- |
| **Coach chat** | Groq Qwen `qwen/qwen3.6-27b` | Evidence-backed coaching responses with reasoning chains |
| **Meal vision** | Groq Qwen (vision) | Macro estimation and food identification from photos |
| **Context assembly** | PostgreSQL + PL/pgSQL | Five-layer structured memory assembly before model inference |
| **Output validation** | Deterministic policy engine | Schema, semantics, evidence citations, and policy permissions |
| **Safety** | `beforeSend` scrubber | Redacts health values, meal content, and photo URLs before crash reporting |

## Architecture

```
┌─────────────────────┐       ┌──────────────────────────────────┐       ┌─────────────────┐
│     Flutter iOS     │       │       Supabase (Singapore)       │       │   Groq Cloud    │
│                     │  RLS  │                                  │       │                 │
│  ┌───────────────┐  │◄─────▶│  PostgreSQL + Row-Level Security │  API  │  Qwen 27B       │
│  │  Today · Train │  │       │                                  │◄─────▶│  (chat + vision)│
│  │  Coach · Nutri │  │       │  9 Edge Functions (Deno):        │       │                 │
│  │  Progress      │  │       │  coach-chat · coach-decide       │       └─────────────────┘
│  └───────────────┘  │       │  health-sync · meal-analyze       │
│                     │       │  onboarding · privacy-export      │
│  ┌───────────────┐  │       │  privacy-delete · health-check    │
│  │  Apple Health  │──┘       │  meal-media-retention            │
│  │  Kit           │          └──────────────────────────────────┘
│  └───────────────┘
└─────────────────────┘
```

## Quick Start

```sh
git clone https://github.com/PurnaJear06/Tracend.git
cd Tracend

# Install toolchain (one-time)
./scripts/bootstrap-flutter.sh
./scripts/bootstrap-tools.sh

# Run checks
./scripts/flutter.sh analyze
./scripts/flutter.sh test
./scripts/deno.sh task check

# Full pre-deploy gate
./scripts/pre-deploy.sh
```

See [AGENTS.md](AGENTS.md) for the complete toolchain reference, architecture rules, and deployment
workflow.

## Documentation

| Document | Purpose |
| -------- | ------- |
| [AGENTS.md](AGENTS.md) | Agent instructions, toolchain reference, architecture rules |
| [docs/PRD.md](docs/PRD.md) | Product scope, audience, and feature requirements |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design, data flow, and component boundaries |
| [docs/UX_FLOWS.md](docs/UX_FLOWS.md) | Screen navigation, interaction states, and user journeys |
| [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md) | Visual tokens, component specs, and theming rules |
| [docs/DATA_MODEL.md](docs/DATA_MODEL.md) | Entity definitions, field schemas, and lifecycle rules |
| [docs/AI_SAFETY_SPEC.md](docs/AI_SAFETY_SPEC.md) | Model authority, output validation, and safety constraints |
| [docs/SECURITY_PRIVACY.md](docs/SECURITY_PRIVACY.md) | Data collection, retention, deletion, and access control |
| [docs/TESTING_STRATEGY.md](docs/TESTING_STRATEGY.md) | Test layers, coverage expectations, and quality gates |
| [docs/IMPLEMENTATION_ROADMAP.md](docs/IMPLEMENTATION_ROADMAP.md) | Phase sequencing, milestones, and delivery plan |
| [docs/CONTEXT_BUDGET.md](docs/CONTEXT_BUDGET.md) | AI context budget rules and testing |
| [docs/adr/](docs/adr/) | Architecture Decision Records |

## Stack

**Client** — Flutter 3.41.7 · Dart 3.11.5 · iOS 17+ · HealthKit · Sentry crash reporting

**Backend** — Supabase · PostgreSQL · Row-Level Security · 9 Deno Edge Functions · Session pooler

**AI** — Groq Qwen 3.6 27B (chat + vision) · Five-layer continuity memory · Deterministic output
validation · All model keys server-side only

**Infra** — GitHub Actions CI · Pre-deploy gate · Automated database backups · Edge Function rollback
scripts · Colima container runtime

---

*Tracend is a working brand pending trademark and App Store name clearance.*
