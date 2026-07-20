# Tracend Development Guide

Phase 1 keeps project tooling and caches inside this repository on the external SSD. Run commands
from the repository root.

## Prerequisites

- macOS on Apple silicon
- Xcode 26.6
- Flutter 3.41.7 with Dart 3.11.5
- Node.js 22 or later
- macOS Virtualization.framework support

## Project-local Flutter SDK

Copy the pinned Flutter SDK into `.tooling/` before running Flutter commands. The source SDK must
already be Flutter 3.41.7; after this bootstrap, the wrapper never executes Flutter or Dart from
internal storage:

```sh
./scripts/bootstrap-flutter.sh
```

If Flutter is not on `PATH`, provide its existing SDK directory explicitly:

```sh
FLUTTER_SOURCE=/path/to/flutter ./scripts/bootstrap-flutter.sh
```

## Project-local Supabase CLI

Install the pinned Supabase CLI and Deno runtime:

```sh
./scripts/bootstrap-tools.sh
```

Verify it:

```sh
./scripts/supabase.sh --version
```

The wrapper redirects Supabase user state to `.tooling/home` and never requires a global Supabase
installation.

## Hosted Supabase project

Authenticate and link the repository-local CLI to the Tracend project:

```sh
./scripts/supabase.sh login
./scripts/supabase.sh link --project-ref qsfzzsjenopqqqhvpyaw
./scripts/supabase.sh projects list
```

The linked project is `Tracend` in Southeast Asia (Singapore). CLI credentials remain under
`.tooling/home`, and link metadata remains under `supabase/.temp/`; both paths are ignored by git.
Linking does not deploy local migrations. Review the remote migration plan before any database push.

Preview and deploy reviewed migrations:

```sh
./scripts/supabase.sh db push --linked --dry-run
./scripts/supabase.sh db push --linked
```

The dry run must list only the expected reviewed migrations before deployment.

Deploy a reviewed Edge Function using server-side bundling. `--use-api` avoids the Docker bind-mount
limitation of the external SSD path:

```sh
./scripts/supabase.sh functions deploy onboarding-propose-plan \
  --project-ref qsfzzsjenopqqqhvpyaw \
  --use-api

./scripts/supabase.sh functions deploy health-sync \
  --project-ref qsfzzsjenopqqqhvpyaw \
  --use-api

./scripts/supabase.sh functions deploy meal-media-retention \
  --project-ref qsfzzsjenopqqqhvpyaw \
  --use-api \
  --no-verify-jwt

./scripts/supabase.sh functions deploy privacy-export \
  --project-ref qsfzzsjenopqqqhvpyaw \
  --use-api

./scripts/supabase.sh functions deploy privacy-delete-account \
  --project-ref qsfzzsjenopqqqhvpyaw \
  --use-api
```

`meal-media-retention` is not public: it validates the dedicated `RETENTION_WORKER_SECRET` in its
handler. Store the same generated value in Edge Function secrets and Supabase Vault, and have Cron
read the Vault value; never place it in Flutter, shell history, logs, or committed environment
files. The same scheduled worker performs export-package retention; no second secret or Cron job is
required. Private-beta backup, recovery, export decryption, and incident procedures are in
[`docs/BETA_OPERATIONS.md`](docs/BETA_OPERATIONS.md).

`coach-decide` defaults to the deterministic mock. Live Gemini remains disabled unless all of these
server-side names are reviewed and configured together:

```text
COACH_MODEL_PROVIDER
COACH_AI_ENABLED
GEMINI_API_KEY
GEMINI_MODEL
GEMINI_PAID_DATA_TERMS_ACCEPTED
GEMINI_INPUT_COST_PER_MILLION_USD
GEMINI_OUTPUT_COST_PER_MILLION_USD
MEAL_VISION_ENABLED
MEAL_VISION_MODEL_EVALUATED
MEAL_VISION_MODEL
MEAL_VISION_INPUT_COST_PER_MILLION_USD
MEAL_VISION_OUTPUT_COST_PER_MILLION_USD
```

Do not enable them for restricted data on unpaid Gemini service. Values belong only in Supabase Edge
Function secrets, never Flutter, repository files, shell history, logs, or chat. Adapter deployment
alone does not activate Gemini. The only approved production model value is `gemini-3.5-flash`.
Coach uses medium thinking and meal vision uses low thinking; Flash-Lite model IDs fail closed
rather than becoming an automatic cost fallback.

## Project-local container runtime

Install the pinned Colima and Lima binaries into `.tooling/`:

```sh
./scripts/bootstrap-container-runtime.sh
```

Start the Docker-compatible VM with all runtime state on the external SSD:

```sh
./scripts/container.sh start
```

Stop it without deleting local data:

```sh
./scripts/container.sh stop
```

## Local backend

After the project-local container runtime is running:

```sh
./scripts/supabase.sh start
./scripts/supabase.sh db reset
./scripts/test-db.sh
```

Stop services without deleting local data:

```sh
./scripts/supabase.sh stop
```

The local Supabase stack must remain bound to the local machine and must never be exposed publicly.

## Edge Function checks

```sh
./scripts/deno.sh task check
```

## Flutter toolchain and iPhone build

Use the repository wrapper for every Flutter command. It verifies Flutter 3.41.7 and keeps the SDK,
Flutter/Dart home, pub cache, `.dart_tool`, CocoaPods, plugin dependency targets, and Flutter build
output under `.tooling/`:

```sh
./scripts/flutter.sh pub get
./scripts/flutter.sh format --set-exit-if-changed lib test
./scripts/flutter.sh analyze
./scripts/flutter.sh test
./scripts/flutter.sh build ios --release --no-codesign
```

The iOS target is iPhone-only. Use the unsigned release build as the local and CI compilation gate.
Do not boot a simulator on this development Mac. Install and run on a physically connected iPhone
only after the Apple team and signing configuration are selected; signing remains an explicit
deployment decision.

Runtime configuration is compile-time environment data. Keep only the project URL and publishable
key in ignored environment-specific configuration, then pass values without committing them:

```sh
./scripts/flutter.sh run \
  --dart-define=TRACEND_ENV=local \
  --dart-define=TRACEND_AUTH_MODE=owner_email_password \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your_local_publishable_key
```

The shell runs without Supabase configuration for UI development. Secret, service-role, and
AI-provider keys are never accepted by the Flutter app. Email and password are entered at runtime
and must never appear in a Dart define, environment file, command history, or committed fixture. A
physical iPhone cannot use the Mac-only `127.0.0.1` URL; use reviewed hosted public configuration
after deployment approval.

Run the development-only component gallery without adding a production route:

```sh
./scripts/flutter.sh run -t lib/component_gallery.dart
```

Do not commit `.tooling`, local environment files, generated builds, service keys, provider keys, or
private user data.
