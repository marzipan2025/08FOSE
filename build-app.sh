#!/bin/bash
# Package FontGrid (08FOSE) into a distributable macOS .app bundle.
#
# Produces ./dist/FontGrid.app from a release build:
#   - generates AppIcon.icns from Sources/FontGrid/Resources/AppIcon.png
#   - assembles Contents/{Info.plist,MacOS,Resources}
#   - places the SwiftPM resource bundle where Bundle.module looks for it
#   - ad-hoc code-signs so Gatekeeper lets it launch locally
set -euo pipefail
cd "$(dirname "$0")"

export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_HOME="$PWD/.build/swiftpm-home"
export XDG_CACHE_HOME="$PWD/.build/cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_HOME" "$XDG_CACHE_HOME"

APP_NAME="08FOSE"          # user-facing name: bundle, Dock, Finder
PRODUCT="FontGrid"         # SwiftPM product / executable name
BUNDLE_ID="com.marzipan.fontgrid"
ICON_SRC="Sources/FontGrid/Resources/AppIcon.png"
# Keep in sync with Theme.appVersion
VERSION="$(grep -m1 'appVersion' Sources/FontGrid/Theme.swift | sed -E 's/.*"([^"]+)".*/\1/')"

APP="dist/${APP_NAME}.app"
CONTENTS="${APP}/Contents"
MACOS="${CONTENTS}/MacOS"
RES="${CONTENTS}/Resources"

echo "▸ Building release binary…"
swift build -c release --disable-sandbox
BIN_DIR="$(swift build -c release --disable-sandbox --show-bin-path)"

echo "▸ Generating AppIcon.icns…"
WORK="$(mktemp -d)"
SHAPED="$WORK/AppIcon-rounded.png"
swift Tools/make-icon.swift "$ICON_SRC" "$SHAPED"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size             "$SHAPED" --out "$ICONSET/icon_${size}x${size}.png"     >/dev/null
  sips -z $((size*2)) $((size*2)) "$SHAPED" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
if ! iconutil -c icns "$ICONSET" -o "$WORK/AppIcon.icns"; then
  python3 Tools/make-icns.py "$ICONSET" "$WORK/AppIcon.icns"
fi

echo "▸ Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"
cp "$BIN_DIR/$PRODUCT" "$MACOS/$PRODUCT"
cp "$WORK/AppIcon.icns" "$RES/AppIcon.icns"
cp "$SHAPED" "$RES/DockIcon.png"
if [ -d "$BIN_DIR/${PRODUCT}_${PRODUCT}.bundle" ]; then
  cp -R "$BIN_DIR/${PRODUCT}_${PRODUCT}.bundle" "$RES/"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>          <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>           <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>           <string>${PRODUCT}</string>
    <key>CFBundleIconFile</key>             <string>AppIcon</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleShortVersionString</key>   <string>${VERSION}</string>
    <key>CFBundleVersion</key>              <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>       <string>13.0</string>
    <key>NSHighResolutionCapable</key>      <true/>
    <key>NSPrincipalClass</key>             <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "▸ Ad-hoc code-signing…"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"

rm -rf "$WORK"
echo "✓ Built ${APP}  (v${VERSION})"
echo "  open dist/${APP_NAME}.app   # or drag into /Applications"
