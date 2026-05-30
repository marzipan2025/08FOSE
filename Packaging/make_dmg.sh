#!/usr/bin/env bash
# Package 08FOSE.app into a distributable macOS DMG.
set -euo pipefail

APP_NAME="08FOSE"
VOL_NAME="08FOSE"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_BUNDLE="${ROOT_DIR}/dist/${APP_NAME}.app"
BG_IMG="${ROOT_DIR}/08fose.png"
STAGING_DIR="${ROOT_DIR}/dist/dmg-staging"
FINAL_DMG="${ROOT_DIR}/dist/${APP_NAME}.dmg"

if [ ! -d "$APP_BUNDLE" ]; then
  echo "Missing app bundle: $APP_BUNDLE" >&2
  echo "Run ./build-app.sh first." >&2
  exit 1
fi

if [ ! -f "$BG_IMG" ]; then
  echo "Missing DMG background: $BG_IMG" >&2
  exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "create-dmg not found. Install with: brew install create-dmg" >&2
  exit 1
fi

rm -rf "$STAGING_DIR" "$FINAL_DMG"
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"

echo "Creating DMG..."
create-dmg \
  --volname "$VOL_NAME" \
  --background "$BG_IMG" \
  --window-pos 129 129 \
  --window-size 640 480 \
  --icon-size 128 \
  --icon "${APP_NAME}.app" 195 240 \
  --app-drop-link 445 240 \
  --hide-extension "${APP_NAME}.app" \
  --no-internet-enable \
  "$FINAL_DMG" \
  "$STAGING_DIR"

rm -rf "$STAGING_DIR"

echo "DMG created at:"
echo "  $FINAL_DMG"
