#!/bin/sh
# Refuse an iOS app whose Flutter assets are missing. Every icon and the brand
# typefaces are font files in App.framework/flutter_assets. Without them the app
# still installs and launches but draws each icon as a "?" box, as build 185 did
# after another checkout's build deleted its assets.
#
# Also refuse an app without its home screen icon (any, dark and tinted) or its
# launch screen artwork in the compiled asset catalog, which iOS would replace
# with a blank icon and a blank launch screen.
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

python3 - "$1" <<'PY'
import json
import os
import plistlib
import subprocess
import sys

app = sys.argv[1]
missing = []
with open(os.path.join(app, "Info.plist"), "rb") as info_file:
    info = plistlib.load(info_file)
icon_name = (
    info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {}).get("CFBundleIconName")
)
launch = info.get("UILaunchScreen", {})
if icon_name != "AppIcon":
    missing.append(f"CFBundleIconName AppIcon in Info.plist (found {icon_name!r})")

catalog = os.path.join(app, "Assets.car")
renditions = []
if os.path.isfile(catalog):
    listing = subprocess.run(
        ["xcrun", "assetutil", "--info", catalog],
        check=True,
        capture_output=True,
        text=True,
    )
    renditions = json.loads(listing.stdout)[1:]
else:
    missing.append("Assets.car")

icons = [r for r in renditions if r.get("Name") == "AppIcon" and r.get("AssetType") == "Icon Image"]
appearances = {
    "any": None,
    "dark": "UIAppearanceDark",
    "tinted": "ISAppearanceTintable",
}
for label, appearance in appearances.items():
    sizes = {r.get("PixelWidth") for r in icons if r.get("Appearance") == appearance}
    # 120 px is the iPhone home screen icon; 1024 px is the store artwork.
    for pixels in (120, 1024):
        if pixels not in sizes:
            missing.append(f"AppIcon {label} {pixels}x{pixels}")
for key, asset_type in (("UIImageName", "Image"), ("UIColorName", "Color")):
    name = launch.get(key)
    if not name or not any(
        r.get("Name") == name and r.get("AssetType") == asset_type for r in renditions
    ):
        missing.append(f"launch screen {key} {name!r} in Assets.car")

if missing:
    print(f"The app bundle is missing its icon or launch artwork in {app}:", file=sys.stderr)
    for item in missing:
        print(f"  - {item}", file=sys.stderr)
    sys.exit(1)
print("✓ App icon (any, dark, tinted) and launch screen artwork present")
PY
