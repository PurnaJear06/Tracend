#!/bin/sh
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$REPO_ROOT/tool/versions.env"

DESTINATION="$REPO_ROOT/.tooling/flutter-sdk"
SOURCE=${FLUTTER_SOURCE:-}

if [ -z "$SOURCE" ]; then
  SYSTEM_FLUTTER=$(command -v flutter || true)
  if [ -n "$SYSTEM_FLUTTER" ]; then
    while [ -L "$SYSTEM_FLUTTER" ]; do
      LINK_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$SYSTEM_FLUTTER")" && pwd)
      LINK_TARGET=$(/usr/bin/readlink "$SYSTEM_FLUTTER")
      case "$LINK_TARGET" in
        /*) SYSTEM_FLUTTER=$LINK_TARGET ;;
        *) SYSTEM_FLUTTER="$LINK_DIRECTORY/$LINK_TARGET" ;;
      esac
    done
    SOURCE=$(CDPATH= cd -- "$(dirname -- "$SYSTEM_FLUTTER")/.." && pwd)
  fi
fi

if [ -z "$SOURCE" ] || [ ! -x "$SOURCE/bin/flutter" ]; then
  echo "Set FLUTTER_SOURCE to an existing Flutter $FLUTTER_VERSION SDK." >&2
  exit 1
fi

VERSION_FILE="$SOURCE/bin/cache/flutter.version.json"
if [ ! -f "$VERSION_FILE" ]; then
  echo "Flutter source has no cached version manifest: $VERSION_FILE" >&2
  exit 1
fi

SOURCE_VERSION=$(sed -n 's/.*"frameworkVersion": *"\([^"]*\)".*/\1/p' "$VERSION_FILE")
if [ "$SOURCE_VERSION" != "$FLUTTER_VERSION" ]; then
  echo "Flutter $FLUTTER_VERSION is required; source contains $SOURCE_VERSION." >&2
  exit 1
fi

mkdir -p "$DESTINATION"
/usr/bin/rsync -a --delete "$SOURCE/" "$DESTINATION/"
printf '%s\n' "$FLUTTER_VERSION" > "$REPO_ROOT/.tooling/flutter-version"
echo "Flutter $FLUTTER_VERSION installed at $DESTINATION"
