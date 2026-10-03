#!/bin/sh
# Renders the Tracend app icon and launch image from the mark in
# lib/shared/brand/tracend_mark.dart, so the artwork always matches the app.
#
# 1. test/brand/app_icon_test.dart draws the 1024 icon masters (any, dark and
#    tinted) and the 3x launch image into ios/Runner/Assets.xcassets.
# 2. sips scales every other size each Contents.json lists from its master,
#    and stale PNGs the catalogs no longer list are removed.
# 3. The same test, run normally, checks every size and the alpha rules.
#
# Usage: ./tool/render_app_icon.sh   (macOS; needs sips and python3)
set -eu
set -o pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
catalog="ios/Runner/Assets.xcassets"

./scripts/flutter.sh test \
  --dart-define=TRACEND_RENDER_BRAND_ASSETS=true \
  --plain-name "opaque 1024" \
  test/brand/app_icon_test.dart

tab="$(printf '\t')"
# Prints "<folder>\t<master>\t<target>\t<pixels>" for each image to scale.
python3 - "$catalog" <<'PY' |
import json
import os
import struct
import sys

catalog = sys.argv[1]
masters = {None: "Icon-App", "dark": "Icon-App-Dark", "tinted": "Icon-App-Tinted"}


def images(folder):
    with open(os.path.join(folder, "Contents.json"), encoding="utf-8") as file:
        return json.load(file)["images"]


def width(png):
    with open(png, "rb") as file:
        return struct.unpack(">I", file.read(20)[16:20])[0]


def prune(folder, listed):
    for name in os.listdir(folder):
        if name.endswith(".png") and name not in listed:
            os.remove(os.path.join(folder, name))


icons = os.path.join(catalog, "AppIcon.appiconset")
listed = set()
for image in images(icons):
    appearance = (image.get("appearances") or [{}])[0].get("value")
    master = f"{masters[appearance]}-1024x1024@1x.png"
    points = float(image["size"].split("x")[0])
    pixels = round(points * int(image["scale"].rstrip("x")))
    listed.add(image["filename"])
    if image["filename"] != master:
        print(icons, master, image["filename"], pixels, sep="\t")
prune(icons, listed)

launch = os.path.join(catalog, "LaunchImage.imageset")
listed = set()
by_scale = {image["scale"]: image["filename"] for image in images(launch)}
master = by_scale["3x"]
points = width(os.path.join(launch, master)) // 3
for scale, name in by_scale.items():
    listed.add(name)
    if name != master:
        print(launch, master, name, points * int(scale.rstrip("x")), sep="\t")
prune(launch, listed)
PY
while IFS="$tab" read -r folder master target pixels; do
  sips --resampleHeightWidth "$pixels" "$pixels" \
    "$folder/$master" --out "$folder/$target" >/dev/null
done

./scripts/flutter.sh test test/brand/app_icon_test.dart
echo "✓ App icon, dark and tinted variants and launch image rendered"
