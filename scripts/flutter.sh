#!/bin/sh
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$REPO_ROOT/tool/versions.env"

export PUB_CACHE="$REPO_ROOT/.tooling/pub-cache"
export HOME="$REPO_ROOT/.tooling/home"
export CP_HOME_DIR="$REPO_ROOT/.tooling/cocoapods-home"
export COCOAPODS_DISABLE_STATS=true

FLUTTER_ROOT="$REPO_ROOT/.tooling/flutter-sdk"
FLUTTER_BIN="$FLUTTER_ROOT/bin/flutter"
DART_BIN="$FLUTTER_ROOT/bin/dart"

if [ ! -x "$FLUTTER_BIN" ]; then
  echo "Flutter SDK is missing from $FLUTTER_ROOT." >&2
  echo "Run ./scripts/bootstrap-flutter.sh first." >&2
  exit 1
fi

mkdir -p \
  "$REPO_ROOT/.tooling/dart-tool" \
  "$REPO_ROOT/.tooling/flutter-build" \
  "$REPO_ROOT/.tooling/home" \
  "$REPO_ROOT/.tooling/cocoapods-home" \
  "$REPO_ROOT/.tooling/ios/Pods" \
  "$REPO_ROOT/.tooling/ios/ephemeral"

link_generated_path() {
  target=$1
  source=$2
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    echo "Refusing to replace generated path: $target" >&2
    exit 1
  fi
  if [ ! -L "$target" ]; then
    ln -s "$source" "$target"
  fi
}

link_generated_path "$REPO_ROOT/.dart_tool" "$REPO_ROOT/.tooling/dart-tool"
link_generated_path "$REPO_ROOT/build" "$REPO_ROOT/.tooling/flutter-build"
link_generated_path "$REPO_ROOT/ios/Pods" "$REPO_ROOT/.tooling/ios/Pods"
link_generated_path "$REPO_ROOT/ios/Flutter/ephemeral" "$REPO_ROOT/.tooling/ios/ephemeral"

version_stamp="$REPO_ROOT/.tooling/flutter-version"
if [ ! -f "$version_stamp" ] || [ "$(sed -n '1p' "$version_stamp")" != "$FLUTTER_VERSION" ]; then
  installed_version=$("$FLUTTER_BIN" --version --machine | sed -n 's/.*"frameworkVersion": *"\([^"]*\)".*/\1/p')
  if [ "$installed_version" != "$FLUTTER_VERSION" ]; then
    echo "Flutter $FLUTTER_VERSION is required; found $installed_version." >&2
    exit 1
  fi
  printf '%s\n' "$installed_version" > "$version_stamp"
fi

cd "$REPO_ROOT"
if [ "${1:-}" = "format" ]; then
  exec "$DART_BIN" "$@"
fi
exec "$FLUTTER_BIN" "$@"
