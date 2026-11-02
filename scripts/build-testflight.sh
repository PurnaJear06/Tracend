#!/usr/bin/env bash
# Build the signed App Store .ipa that goes to TestFlight. It does not upload: it checks the
# result and prints the upload command, so a person decides when a build reaches testers.
#
# Usage:
#   ./scripts/build-testflight.sh           # build, check and print the upload command
#   ./scripts/build-testflight.sh --check   # run every guard and print the plan; build nothing
#
# Run it from a clean checkout of the newest origin/main (git checkout --detach origin/main).
# It refuses a dirty tree, a commit that is not the origin/main tip, an empty
# SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY, a build number that is not higher than the last
# build this machine made, and a manual TRACEND_BUILD_NUMBER.
#
# Config comes from the gitignored .env, as for scripts/install-device.sh:
#   SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY (required), SENTRY_DSN (optional)
#
# Environment:
#   TRACEND_ENV_FILE   .env path override (default: <checkout>/.env)
#
# The build number is the commit count of origin/main (scripts/app-version.sh), which only ever
# grows on main, so each upload beats the last. The team ID is read from the Xcode project.
#
# Upload: docs/BETA_OPERATIONS.md has the one-time App Store Connect API key setup. The key
# stays on the owner's machine; nothing here reads or stores it.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
check_only=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) check_only=true ;;
    -h | --help)
      sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
  shift
done

die() {
  echo "build-testflight: $*" >&2
  exit 1
}

cd "$repo_root"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git checkout"
git fetch -q origin main || die "cannot fetch origin/main"

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  die "the working tree is not clean. Commit, stash or remove your changes: a TestFlight build comes from origin/main alone."
fi

head_sha="$(git rev-parse HEAD)"
main_sha="$(git rev-parse refs/remotes/origin/main)"
if [[ "$head_sha" != "$main_sha" ]]; then
  die "HEAD ($(git rev-parse --short HEAD)) is not the origin/main tip ($(git rev-parse --short origin/main)). Run: git checkout --detach origin/main"
fi

if [[ -n "${TRACEND_BUILD_NUMBER:-}" ]]; then
  die "TRACEND_BUILD_NUMBER is set. TestFlight numbers come from origin/main's commit count; unset it."
fi

env_file="${TRACEND_ENV_FILE:-$repo_root/.env}"
[[ -f "$env_file" ]] || die "missing $env_file. Copy .env.example to .env and fill SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY."
set -a
# shellcheck disable=SC1090
. "$env_file"
set +a
[[ -n "${SUPABASE_URL:-}" && -n "${SUPABASE_PUBLISHABLE_KEY:-}" ]] ||
  die "SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY must both be set in $env_file. A build without them would run as a local demo."
case "$SUPABASE_URL" in
  https://*) ;;
  *) die "SUPABASE_URL must start with https:// in a TestFlight build" ;;
esac

build_name="$("$repo_root/scripts/app-version.sh" name)"
build_number="$("$repo_root/scripts/app-version.sh" number)"

ledger="$repo_root/.tooling/testflight-builds.txt"
if [[ -s "$ledger" ]]; then
  read -r last_number _ last_sha _ < <(tail -n 1 "$ledger")
  if ((build_number < last_number)) || { ((build_number == last_number)) && [[ "$last_sha" != "$head_sha" ]]; }; then
    die "build $build_number is not higher than the last build made here ($last_number). Apple rejects an upload whose build number does not grow."
  fi
fi

team_id="$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM = \([A-Z0-9]*\);.*/\1/p' ios/Runner.xcodeproj/project.pbxproj | sort -u)"
[[ "$(printf '%s\n' "$team_id" | grep -c .)" -eq 1 ]] ||
  die "ios/Runner.xcodeproj must name exactly one DEVELOPMENT_TEAM (found: $(printf '%s' "$team_id" | tr '\n' ' '))"

echo "==> Tracend $build_name ($build_number) from $(git rev-parse --short HEAD), team $team_id"
echo "==> Supabase: $SUPABASE_URL"
[[ -n "${SENTRY_DSN:-}" ]] || echo "==> SENTRY_DSN is empty: this build will not report crashes."

if [[ "$check_only" == "true" ]]; then
  echo "==> --check: every guard passed. Nothing was built."
  exit 0
fi

build_dir="$repo_root/build/ios"
export_options="$build_dir/ExportOptions.plist"
mkdir -p "$build_dir"
# Automatic signing: Xcode creates the distribution certificate and profiles for both targets
# (the app and TracendWidgets) in the owner's team. Xcode, not Flutter, owns the build number.
cat >"$export_options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>teamID</key>
	<string>$team_id</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>destination</key>
	<string>export</string>
	<key>uploadSymbols</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
PLIST
plutil -lint "$export_options" >/dev/null

# Flutter prints a hint and still exits 0 when the export step fails, so an old .ipa must never
# be left in place to look like this build's.
rm -rf "$build_dir/ipa" "$build_dir/archive"

dart_defines=(
  --dart-define "SUPABASE_URL=$SUPABASE_URL"
  --dart-define "SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"
)
if [[ -n "${SENTRY_DSN:-}" ]]; then
  dart_defines+=(--dart-define "SENTRY_DSN=$SENTRY_DSN")
fi

echo "==> Building the signed App Store archive and .ipa"
./scripts/flutter.sh build ipa --release \
  --build-name "$build_name" \
  --build-number "$build_number" \
  --export-options-plist "$export_options" \
  "${dart_defines[@]}"

ipa="$(find "$build_dir/ipa" -maxdepth 1 -name '*.ipa' -print 2>/dev/null | head -n 1)"
[[ -n "$ipa" ]] || die "no .ipa was produced. Open $build_dir/archive/Runner.xcarchive in Xcode > Distribute App to see why signing or export failed."

unpacked="$(mktemp -d)"
trap 'rm -rf "$unpacked"' EXIT
unzip -q "$ipa" -d "$unpacked"
app="$unpacked/Payload/Runner.app"
[[ -d "$app" ]] || die "the .ipa has no Payload/Runner.app"

echo "==> Checking the bundle inside the .ipa"
./scripts/verify-app-bundle.sh "$app"
[[ "$(plutil -extract CFBundleVersion raw "$app/Info.plist")" == "$build_number" ]] ||
  die "the .ipa's build number is not $build_number"
[[ "$(plutil -extract CFBundleShortVersionString raw "$app/Info.plist")" == "$build_name" ]] ||
  die "the .ipa's version is not $build_name"
[[ "$(plutil -extract ITSAppUsesNonExemptEncryption raw "$app/Info.plist")" == "false" ]] ||
  die "the .ipa does not declare ITSAppUsesNonExemptEncryption=false"
[[ -d "$app/PlugIns/TracendWidgets.appex" ]] || die "the .ipa does not contain the TracendWidgets extension"

mkdir -p "$repo_root/.tooling"
printf '%s %s %s %s\n' "$build_number" "$build_name" "$head_sha" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$ledger"

echo ""
echo "==> Built $ipa"
echo "==> To upload (App Store Connect API key set up as in docs/BETA_OPERATIONS.md):"
echo "    xcrun altool --upload-app --type ios -f \"$ipa\" --apiKey \"\$ASC_KEY_ID\" --apiIssuer \"\$ASC_ISSUER_ID\""
echo "    Or drag the .ipa into the Transporter app."
