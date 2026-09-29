#!/bin/sh
set -eu

# Git exports these to hooks; Flutter would then read this repo as its own SDK
# checkout, report an unknown version, and fail dependency resolution.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX

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

# Worktrees link .tooling to the primary checkout's, which shares the SDK and
# the dependency caches. Build state must stay per checkout: when the build
# configuration changes, Flutter deletes the previous build's outputs by the
# paths that build recorded, so two checkouts building through one build/
# directory delete each other's fresh assets (build 185 shipped without its
# fonts). A checkout that reaches .tooling through a link keeps its build state
# under .tooling/checkouts/, and checkout-path there names the checkout.
# ios/Pods stays shared: CocoaPods writes the real location of the Pods
# directory into the tracked Xcode project, and Flutter reinstalls pods whenever
# a checkout's Podfile.lock differs from the shared Manifest.lock.
TOOLING_DIR=$(CDPATH= cd -- "$REPO_ROOT/.tooling" && pwd -P)
CHECKOUT_DIR=$(CDPATH= cd -- "$REPO_ROOT" && pwd -P)
if [ "$TOOLING_DIR" = "$CHECKOUT_DIR/.tooling" ]; then
  STATE_DIR=$TOOLING_DIR
else
  checkout_id=$(printf '%s' "$CHECKOUT_DIR" | cksum | cut -d ' ' -f 1)
  STATE_DIR="$TOOLING_DIR/checkouts/$(basename "$CHECKOUT_DIR")-$checkout_id"
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$CHECKOUT_DIR" > "$STATE_DIR/checkout-path"
fi

mkdir -p \
  "$REPO_ROOT/.tooling/home" \
  "$REPO_ROOT/.tooling/cocoapods-home" \
  "$REPO_ROOT/.tooling/ios/Pods" \
  "$STATE_DIR/dart-tool" \
  "$STATE_DIR/flutter-build" \
  "$STATE_DIR/ios/ephemeral"

link_generated_path() {
  target=$1
  source=$2
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    echo "Refusing to replace generated path: $target" >&2
    exit 1
  fi
  # Also re-points links that earlier versions of this script aimed at the
  # shared build state.
  if [ "$(readlink "$target" 2>/dev/null || true)" != "$source" ]; then
    rm -f "$target"
    ln -s "$source" "$target"
  fi
}

link_generated_path "$REPO_ROOT/.dart_tool" "$STATE_DIR/dart-tool"
link_generated_path "$REPO_ROOT/build" "$STATE_DIR/flutter-build"
link_generated_path "$REPO_ROOT/ios/Pods" "$REPO_ROOT/.tooling/ios/Pods"
link_generated_path "$REPO_ROOT/ios/Flutter/ephemeral" "$STATE_DIR/ios/ephemeral"

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
