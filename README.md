<!-- PROJECT LOGO -->

<p align="center">
  <img src="https://cdn.jsdelivr.net/gh/PurnaJear06/Tracend@e3fe125/design/stitch/source/tracend-logo-reference.png" width="100" alt="Tracend logo" />
</p>

<h3 align="center">Tracend</h3>

<p align="center">
  <strong>The evidence-driven AI personal trainer.</strong><br/>
  <sub>Your body. Your data. Your next move.</sub>
</p>

<!-- BADGES -->

<p align="center">
  <a href="https://github.com/PurnaJear06/Tracend/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/PurnaJear06/Tracend/ci.yml?style=for-the-badge&label=CI&branch=main" alt="CI"/></a>
  <a href="https://github.com/PurnaJear06/Tracend/actions/workflows/deploy.yml"><img src="https://img.shields.io/github/actions/workflow/status/PurnaJear06/Tracend/deploy.yml?style=for-the-badge&label=Deploy&branch=main" alt="Deploy"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-4A57E8?style=for-the-badge&labelColor=0D1117" alt="MIT License"/></a>
  <img src="https://img.shields.io/badge/iOS-17%2B-4A57E8?style=for-the-badge&logo=apple&logoColor=white&labelColor=0D1117" alt="iOS 17+"/>
</p>

<!-- NAV -->

<p align="center">
  <a href="#features"><strong>Features</strong></a> &middot;
  <a href="#how-it-works"><strong>How it works</strong></a> &middot;
  <a href="#architecture"><strong>Architecture</strong></a> &middot;
  <a href="#quick-start"><strong>Quick Start</strong></a> &middot;
  <a href="#documentation"><strong>Docs</strong></a> &middot;
  <a href="#license"><strong>License</strong></a>
</p>

<p align="center"><sub>Private beta &middot; Apple HealthKit &middot; every model decision requires your approval</sub></p>

---

<p align="center">
  <img src="https://cdn.jsdelivr.net/gh/PurnaJear06/Tracend@main/design/store/hero/banner-1400w.webp" alt="Tracend on iPhone: Today dashboard, Coach chat, Train session, Nutrition plan, Progress charts - five screens of the app" />
</p>

## Why Tracend

Most fitness apps give you a spreadsheet. Most AI apps give you a chatbot guessing at your body. Tracend is neither.

**Tracend is an evidence-driven AI personal trainer.** It builds a personalized training and nutrition plan around your actual capacity, observes real execution and recovery through Apple Health, and produces clear daily coaching decisions with the reasoning shown inline. Plans stay stable until evidence supports a change, and every persistent change requires your approval.

- **Calculated, never generated.** Trends, adherence, and baselines are computed by deterministic code. The model interprets; it never does the math.
- **Nothing acts on its own.** No plan activation, no confirmed meal, no durable user fact without your explicit approval.
- **Everything is auditable.** Evidence, validation, approval, new version, audit event. Every persistent change follows this chain.
- **The plan survives failure.** When AI, HealthKit, or media processing is down, your active plan keeps working.

> [!NOTE]
> Private beta on a single paired iPhone. Apple HealthKit is the source of truth for all health data. The full model boundary and provider rules live in [`docs/AI_SAFETY_SPEC.md`](docs/AI_SAFETY_SPEC.md).

## Features

### Today

Sleep, activity, and vitals from Apple Health become three tappable factors: **Recovery**, **Training**, and **Nutrition**. Plain-language explanations, progressive disclosure, no wall of numbers. A daily readiness score derived from HRV, resting heart rate, sleep, respiratory rate, and prior strain, with each driver shown as its own metric.

### Train

Set-level session tracking: reps, RPE, and pain per set. In-progress sessions survive an app restart and resume where you left off. HealthKit auto-detects completed workouts and reconciles them with your scheduled plan.

### Coach

Coaching chat that remembers your history across sessions. Five-layer continuity memory: narrative entries, user preferences, session summaries, message search, and context assembly. Every recommendation cites its evidence source, with reasoning chains shown inline.

### Nutrition

Log meals by text or photo. Vision identifies the food and estimates macros. You confirm before anything is persisted. Per-meal-slot schedule compliance with 7-day adherence visibility. Confirmed meals stay visible after midnight; corrections become audited amendments.

### Progress

Weight, measurements, and body metrics on a single date-ordered effective timeline. Raw charts, no smoothing masquerading as current data. Same-day corrections are audited amendments, never silent overwrites.

## How it works

### The AI never touches the numbers

This is the part that makes Tracend different from every other AI fitness app. The AI never touches the numbers. Deterministic code calculates every trend, adherence measure, and baseline from your Apple Health data. The model layer interprets results and proposes actions. Output passes schema, semantics, evidence-citation, and policy-permission checks, and is rejected on any failure. Nothing is activated, confirmed, or persisted without your explicit approval.

**Deterministic math. Interpretive model. Audited persistence.**

```mermaid
flowchart LR
  HK["Apple HealthKit"] --> FEAT["Deterministic feature engine<br/>trends, adherence, baselines"]
  FEAT --> CTX["Context assembly<br/>five-layer memory in PostgreSQL"]
  CTX --> AI["Model layer<br/>interprets, proposes"]
  AI --> VAL["Output validation<br/>schema, semantics, evidence, policy"]
  VAL --> APR["Your approval<br/>required for every persistent change"]
  APR --> DB[("PostgreSQL<br/>RLS + audit events")]
  HK --> DB
```

## Architecture

Flutter iOS client. Supabase backend: PostgreSQL with row-level security, 9 Deno Edge Functions, Storage, and automated backups. AI providers are routed server-side only, so the app never names, embeds, or depends on a specific one. The single source of truth for model boundaries and provider rules is [`docs/AI_SAFETY_SPEC.md`](docs/AI_SAFETY_SPEC.md).

**9 Edge Functions:** `coach-chat` · `coach-decide` · `health-check` · `health-sync` · `meal-analyze` · `meal-media-retention` · `onboarding-propose-plan` · `privacy-delete-account` · `privacy-export`

## Quick Start

```sh
git clone https://github.com/PurnaJear06/Tracend.git
cd Tracend

# 1. Install toolchain (one-time)
./scripts/bootstrap-flutter.sh
./scripts/bootstrap-tools.sh

# 2. Run checks
./scripts/flutter.sh analyze         # Dart static analysis
./scripts/flutter.sh test            # Flutter unit + widget tests
./scripts/deno.sh task check         # Deno fmt + lint + test

# 3. Full pre-deploy gate (all layers - matches CI)
./scripts/pre-deploy.sh
```

> [!NOTE]
> All tooling state stays under `.tooling/`. Never invoke `flutter`, `deno`, `supabase`, or
> `docker` directly: use the `./scripts/` wrappers. See [`AGENTS.md`](AGENTS.md)
> for the full toolchain reference.

## Documentation

| Document                                                           | Purpose                                                     |
| :----------------------------------------------------------------- | :---------------------------------------------------------- |
| [`AGENTS.md`](AGENTS.md)                                           | Agent instructions, toolchain reference, architecture rules |
| [`docs/PRD.md`](docs/PRD.md)                                       | Product scope, audience, feature requirements               |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)                     | System design, data flow, component boundaries              |
| [`docs/UX_FLOWS.md`](docs/UX_FLOWS.md)                             | Screen navigation, interaction states, journeys             |
| [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md)                   | Visual tokens, component specs, theming rules               |
| [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md)                         | Entity definitions, field schemas, lifecycle rules          |
| [`docs/AI_SAFETY_SPEC.md`](docs/AI_SAFETY_SPEC.md)                 | Model boundaries, provider rules, output validation         |
| [`docs/SECURITY_PRIVACY.md`](docs/SECURITY_PRIVACY.md)             | Data collection, retention, deletion, access control        |
| [`docs/TESTING_STRATEGY.md`](docs/TESTING_STRATEGY.md)             | Test layers, coverage expectations, quality gates           |
| [`docs/IMPLEMENTATION_ROADMAP.md`](docs/IMPLEMENTATION_ROADMAP.md) | Phase sequencing, milestones, delivery plan                 |
| [`docs/CONTEXT_BUDGET.md`](docs/CONTEXT_BUDGET.md)                 | AI context budget rules and contract testing                |
| [`docs/adr/`](docs/adr/)                                           | Architecture Decision Records                               |

## License

Released under the [MIT License](LICENSE).

---

<p align="center">
  <sub>Tracend is a working brand pending trademark and App Store name clearance.</sub>
</p>
