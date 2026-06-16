#!/usr/bin/env bash
# Generate 08FOSE/Assets.xcassets/AppIcon.appiconset from the full-bleed master
# PNG, baking in the macOS rounded-rect silhouette (macOS does not round app
# icons automatically). Reuses Tools/make-icon.swift for the rounding, then
# downscales with sips. Re-run whenever the source art changes.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Sources/FontGrid/Resources/AppIcon.png"
SET="08FOSE/Assets.xcassets/AppIcon.appiconset"

[ -f "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }
mkdir -p "$SET"

WORK="$(mktemp -d)"
MASTER="$WORK/rounded-1024.png"
swift Tools/make-icon.swift "$SRC" "$MASTER"

# size -> filename (macOS icon set: 16,32,128,256,512 at @1x and @2x)
emit() { sips -z "$1" "$1" "$MASTER" --out "$SET/$2" >/dev/null; }
emit 16   icon_16.png
emit 32   icon_16@2x.png
emit 32   icon_32.png
emit 64   icon_32@2x.png
emit 128  icon_128.png
emit 256  icon_128@2x.png
emit 256  icon_256.png
emit 512  icon_256@2x.png
emit 512  icon_512.png
emit 1024 icon_512@2x.png

cat > "$SET/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16",   "filename" : "icon_16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16",   "filename" : "icon_16@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32",   "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32",   "filename" : "icon_32@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_128@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_256@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_512@2x.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

rm -rf "$WORK"
echo "✓ Generated $SET"
