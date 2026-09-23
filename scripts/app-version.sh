#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
pubspec_version=$(sed -n 's/^version: *//p' "$repo_root/pubspec.yaml" | head -1)

if ! printf '%s\n' "$pubspec_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$'; then
  echo "pubspec.yaml version must use MAJOR.MINOR.PATCH+BUILD: $pubspec_version" >&2
  exit 1
fi

default_name=${pubspec_version%+*}
default_number=${pubspec_version#*+}
build_name=${TRACEND_BUILD_NAME:-$default_name}

if [ -n "${TRACEND_BUILD_NUMBER:-}" ]; then
  build_number=$TRACEND_BUILD_NUMBER
elif git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  build_number=$(git -C "$repo_root" rev-list --count HEAD)
else
  build_number=$default_number
fi

if ! printf '%s\n' "$build_name" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Build name must use MAJOR.MINOR.PATCH: $build_name" >&2
  exit 1
fi
if ! printf '%s\n' "$build_number" | grep -Eq '^[1-9][0-9]*$'; then
  echo "Build number must be a positive integer: $build_number" >&2
  exit 1
fi

case "${1:-version}" in
  name) printf '%s\n' "$build_name" ;;
  number) printf '%s\n' "$build_number" ;;
  version) printf '%s+%s\n' "$build_name" "$build_number" ;;
  *)
    echo "Usage: app-version.sh [name|number|version]" >&2
    exit 1
    ;;
esac
