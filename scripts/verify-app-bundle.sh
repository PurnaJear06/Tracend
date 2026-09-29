#!/bin/sh
# Refuse an iOS app whose Flutter assets are missing. Every icon and the brand
# typefaces are font files in App.framework/flutter_assets. Without them the app
# still installs and launches but draws each icon as a "?" box, as build 185 did
# after another checkout's build deleted its assets.
#
# Usage: ./scripts/verify-app-bundle.sh build/ios/iphoneos/Runner.app
set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: verify-app-bundle.sh <path/to/Runner.app>" >&2
  exit 2
fi

python3 - "$1/Frameworks/App.framework/flutter_assets" <<'PY'
import json
import os
import sys

assets = sys.argv[1]
icon_families = ("MaterialIcons", "packages/cupertino_icons/CupertinoIcons")
missing = []


def present(relative):
    path = os.path.join(assets, relative)
    if os.path.isfile(path) and os.path.getsize(path) > 0:
        return True
    missing.append(relative)
    return False


present("AssetManifest.bin")
font_files = 0
if present("FontManifest.json"):
    with open(os.path.join(assets, "FontManifest.json"), encoding="utf-8") as manifest_file:
        manifest = json.load(manifest_file)
    families = {entry["family"] for entry in manifest}
    missing += [f"font family {family}" for family in icon_families if family not in families]
    for entry in manifest:
        for font in entry["fonts"]:
            font_files += 1
            present(font["asset"])

if missing:
    print(f"The app bundle is missing Flutter assets in {assets}:", file=sys.stderr)
    for item in missing:
        print(f"  - {item}", file=sys.stderr)
    sys.exit(1)
print(f"✓ Flutter assets present: AssetManifest.bin, FontManifest.json, {font_files} font files")
PY
