#!/usr/bin/env bash
# Build 08FOSE.app from source.
# Output: dist/08FOSE.app
# Run before make_dmg.sh.
set -euo pipefail

APP_NAME="08FOSE"
BUNDLE_ID="com.marzipan.fontgrid"
EXECUTABLE="FontGrid"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
BUILD_DIR="${ROOT_DIR}/.build/arm64-apple-macosx/release"
ICON_SRC="${ROOT_DIR}/Sources/FontGrid/Resources/AppIcon.png"

# Read version from Theme.swift
APP_VERSION=$(grep 'static let appVersion' "${ROOT_DIR}/Sources/FontGrid/Theme.swift" \
  | sed 's/.*"\(.*\)".*/\1/')

echo "Building ${APP_NAME} v${APP_VERSION}..."

# 1. Release build
cd "${ROOT_DIR}"
swift build -c release

# 2. Clean previous bundle
rm -rf "${APP_BUNDLE}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"

# 3. Executable
cp "${BUILD_DIR}/${EXECUTABLE}" "${CONTENTS}/MacOS/${EXECUTABLE}"

# 4. SPM resource bundle (wallpapers, AppIcon.png)
cp -R "${BUILD_DIR}/${EXECUTABLE}_${EXECUTABLE}.bundle" \
       "${CONTENTS}/Resources/${EXECUTABLE}_${EXECUTABLE}.bundle"

# 5. AppIcon.icns — round corners via make-icon.swift, then iconutil
TMP_DIR="$(mktemp -d)"
ICON_ROUNDED="${TMP_DIR}/AppIcon-rounded.png"
swift "${ROOT_DIR}/Tools/make-icon.swift" "${ICON_SRC}" "${ICON_ROUNDED}"

TMP_ICONSET="${TMP_DIR}/AppIcon.iconset"
mkdir -p "${TMP_ICONSET}"
for SIZE in 16 32 64 128 256 512; do
  sips -z "${SIZE}" "${SIZE}" "${ICON_ROUNDED}" \
    --out "${TMP_ICONSET}/icon_${SIZE}x${SIZE}.png" > /dev/null
done
sips -z 32  32  "${ICON_ROUNDED}" --out "${TMP_ICONSET}/icon_16x16@2x.png"  > /dev/null
sips -z 64  64  "${ICON_ROUNDED}" --out "${TMP_ICONSET}/icon_32x32@2x.png"  > /dev/null
sips -z 256 256 "${ICON_ROUNDED}" --out "${TMP_ICONSET}/icon_128x128@2x.png"> /dev/null
sips -z 512 512 "${ICON_ROUNDED}" --out "${TMP_ICONSET}/icon_256x256@2x.png"> /dev/null
cp "${ICON_ROUNDED}" "${TMP_ICONSET}/icon_512x512@2x.png"
iconutil -c icns "${TMP_ICONSET}" -o "${CONTENTS}/Resources/AppIcon.icns"
rm -rf "${TMP_DIR}"

# 6. Info.plist
cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>       <string>${BUNDLE_ID}</string>
  <key>CFBundleName</key>             <string>${EXECUTABLE}</string>
  <key>CFBundleDisplayName</key>      <string>${APP_NAME}</string>
  <key>CFBundleExecutable</key>       <string>${EXECUTABLE}</string>
  <key>CFBundlePackageType</key>      <string>APPL</string>
  <key>CFBundleIconFile</key>         <string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>          <string>${APP_VERSION}</string>
  <key>NSHighResolutionCapable</key>  <true/>
  <key>NSPrincipalClass</key>         <string>NSApplication</string>
  <key>LSMinimumSystemVersion</key>   <string>13.0</string>
</dict>
</plist>
PLIST

echo "Done: ${APP_BUNDLE}"
