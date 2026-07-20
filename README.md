# Tracend

Tracend is an evidence-driven AI personal trainer that turns health, training, nutrition, and
progress data into clear coaching decisions.

The repository currently contains the Phase 1 Supabase foundation and Flutter iOS UI shell. Product
and implementation boundaries are defined in [`AGENTS.md`](AGENTS.md) and the authoritative files
under [`docs/`](docs/).

## Flutter development

Flutter 3.41.7 and Dart 3.11.5 are required. Bootstrap the pinned SDK, then use the repository
wrapper so the SDK, pub, CocoaPods, Dart home, and build state remain under `.tooling/` on the
external SSD:

```sh
./scripts/bootstrap-flutter.sh
./scripts/flutter.sh pub get
./scripts/flutter.sh analyze
./scripts/flutter.sh test
./scripts/flutter.sh build ios --release --no-codesign
```

Tracend uses an iPhone-only native target. Local runtime testing uses a physically connected iPhone
after Apple signing is configured; simulator runs are not part of the repository workflow.

The development-only component gallery runs with:

```sh
./scripts/flutter.sh run -t lib/component_gallery.dart
```

The UI shell runs without backend configuration. Supply only a Supabase URL and publishable key
through compile-time environment values when needed. See
[`DEVELOPMENT_GUIDE.md`](DEVELOPMENT_GUIDE.md) for verified commands.
