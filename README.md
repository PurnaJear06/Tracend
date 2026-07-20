# Tracend

[![CI](https://github.com/PurnaJear06/Tracend/actions/workflows/ci.yml/badge.svg)](https://github.com/PurnaJear06/Tracend/actions/workflows/ci.yml)
[![Pre-Deploy Gate](https://github.com/PurnaJear06/Tracend/actions/workflows/pre-deploy.yml/badge.svg)](https://github.com/PurnaJear06/Tracend/actions/workflows/pre-deploy.yml)

An evidence-driven AI personal trainer that turns health, training, nutrition, and progress data
into clear coaching decisions.

Tracend is a working brand pending formal trademark and App Store name clearance.

## Architecture

```
┌──────────────┐     ┌─────────────────────────────────┐     ┌──────────────┐
│  Flutter iOS │────▶│  Supabase (Singapore)            │────▶│  AI Provider │
│  iPhone app  │     │  ├─ PostgreSQL + RLS             │     │  (Groq Qwen) │
│              │◀────│  └─ 9 Edge Functions (Deno)      │◀────│              │
└──────────────┘     └─────────────────────────────────┘     └──────────────┘
```

- **Flutter iOS**: Five-tab UI (Today · Train · Coach · Nutrition · Progress) with Apple HealthKit
  integration.
- **Supabase**: PostgreSQL with row-level security, 9 Deno Edge Functions for AI coaching, health
  sync, meal analysis, onboarding, privacy, and media retention.
- **AI**: Groq Qwen `qwen/qwen3.6-27b` for Coach/chat and meal vision. All AI keys stay
  server-side. Model output never mutates persistent state without user approval.

## Quick Start

```sh
# Bootstrap toolchain (one-time)
./scripts/bootstrap-flutter.sh
./scripts/bootstrap-tools.sh

# Verify everything passes
./scripts/flutter.sh analyze
./scripts/flutter.sh test
./scripts/deno.sh task check
```

See [AGENTS.md](AGENTS.md) for the full toolchain reference and architecture rules.

## Documentation

| Doc                                  | Purpose                               |
| ------------------------------------ | ------------------------------------- |
| [AGENTS.md](AGENTS.md)               | Agent instructions + toolchain        |
| [docs/PRD.md](docs/PRD.md)           | Product scope and requirements        |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design and data flow   |
| [docs/UX_FLOWS.md](docs/UX_FLOWS.md) | Navigation and interaction states     |
| [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md) | Visual system and components  |
| [docs/DATA_MODEL.md](docs/DATA_MODEL.md) | Entities, fields, and lifecycle   |
| [docs/AI_SAFETY_SPEC.md](docs/AI_SAFETY_SPEC.md) | AI model policies and guards  |
| [docs/PROGRESS_CONTEXT.md](docs/PROGRESS_CONTEXT.md) | Live dashboard and status  |

## Stack

- **Client**: Flutter 3.41.7 / Dart 3.11.5 (iOS only)
- **Backend**: Supabase (PostgreSQL, Auth, Storage, Edge Functions)
- **AI**: Groq Qwen via Edge Functions
- **Crash reporting**: Sentry
- **CI/CD**: GitHub Actions
