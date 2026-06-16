#!/bin/bash
# Package 08FOSE into a distributable macOS .app bundle.
#
# Builds the real Xcode app target (08FOSE.xcodeproj) and copies the product to
# ./dist/08FOSE.app. Xcode handles Info.plist, the app icon (Assets.xcassets),
# resource bundling (Contents/Resources, with Wallpapers/ preserved) and ad-hoc
# signing — no hand-assembly. This replaces the old SwiftPM-wrapping approach,
# whose generated Bundle.module accessor only resolved resources via a
# compile-time-absolute .build path and so crashed on every Mac except the one
# that built it.
#
# Version is the single source of truth in Theme.appVersion and is injected into
# the build as MARKETING_VERSION / CURRENT_PROJECT_VERSION.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="08FOSE"
SCHEME="08FOSE"
PROJECT="08FOSE.xcodeproj"
DERIVED="$PWD/.build/xcode"
VERSION="$(grep -m1 'appVersion' Sources/FontGrid/Theme.swift | sed -E 's/.*"([^"]+)".*/\1/')"

echo "▸ Building ${APP_NAME} v${VERSION} (xcodebuild, Release)…"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$VERSION" \
  clean build

BUILT_APP="$DERIVED/Build/Products/Release/${APP_NAME}.app"
[ -d "$BUILT_APP" ] || { echo "build did not produce $BUILT_APP" >&2; exit 1; }

echo "▸ Staging dist/${APP_NAME}.app…"
mkdir -p dist
rm -rf "dist/${APP_NAME}.app"
cp -R "$BUILT_APP" "dist/${APP_NAME}.app"

echo "▸ Verifying signature…"
codesign --verify --deep --strict "dist/${APP_NAME}.app"

echo "✓ Built dist/${APP_NAME}.app  (v${VERSION})"
echo "  open dist/${APP_NAME}.app   # or drag into /Applications"
