#!/bin/sh
# Build a signed iOS release against the hosted Supabase project and install it on
# the paired iPhone. Config (SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY / SENTRY_DSN)
# is read from the gitignored .env file, so agents never ask the user for keys.
#
# Usage:
#   ./scripts/install-device.sh                 # auto-detect the connected iPhone
#   ./scripts/install-device.sh --device <id>   # target a specific CoreDevice id
#   DEVICE_ID=<id> ./scripts/install-device.sh  # same, via env var
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$REPO_ROOT"

ENV_FILE="$REPO_ROOT/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE." >&2
  echo "Copy .env.example to .env and fill SUPABASE_URL + SUPABASE_PUBLISHABLE_KEY." >&2
  exit 1
fi

set -a
. "$ENV_FILE"
set +a

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_PUBLISHABLE_KEY:-}" ]; then
  echo "SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY must be set in $ENV_FILE." >&2
  exit 1
fi

DEVICE_ID="${DEVICE_ID:-}"
for arg in "$@"; do
  case "$arg" in
    --device=*) DEVICE_ID="${arg#--device=}" ;;
    --device) shift_next=1 ;;
    *) if [ "${shift_next:-0}" = "1" ]; then DEVICE_ID="$arg"; shift_next=0; fi ;;
  esac
done

list_devices() {
  xcrun devicectl list devices 2>/dev/null | sed -n '1,40p'
}

if [ -z "$DEVICE_ID" ]; then
  json_out="$REPO_ROOT/.tooling/devicectl-devices.json"
  mkdir -p "$REPO_ROOT/.tooling"
  xcrun devicectl list devices --json-output "$json_out" >/dev/null 2>&1 || true
  DEVICE_ID=$(python3 - "$json_out" <<'PY'
import json, sys
path = sys.argv[1]
try:
    data = json.load(open(path))
except Exception:
    sys.exit(0)
devices = data.get("result", {}).get("devices", [])
connected = [
    d for d in devices
    if d.get("hardwareProperties", {}).get("deviceType") == "iPhone"
    and (d.get("connectionProperties", {}) or {}).get("transportType")
]
if len(connected) == 1:
    print(connected[0].get("identifier", ""))
PY
)
  if [ -z "$DEVICE_ID" ]; then
    echo "Could not auto-detect a single connected iPhone. Available devices:" >&2
    list_devices >&2
    echo "Re-run with: ./scripts/install-device.sh --device <identifier>" >&2
    exit 1
  fi
fi

echo "==> Target device: $DEVICE_ID"

BUILD_ARGS="build ios --release
  --dart-define SUPABASE_URL=$SUPABASE_URL
  --dart-define SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"
if [ -n "${SENTRY_DSN:-}" ]; then
  BUILD_ARGS="$BUILD_ARGS --dart-define SENTRY_DSN=$SENTRY_DSN"
fi

echo "==> Building signed release (Supabase: $SUPABASE_URL)"
# shellcheck disable=SC2086
./scripts/flutter.sh $BUILD_ARGS

APP_PATH="$REPO_ROOT/build/ios/iphoneos/Runner.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Build did not produce $APP_PATH." >&2
  exit 1
fi

echo "==> Installing on device"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "==> Done. Launch Tracend on the iPhone to test."
