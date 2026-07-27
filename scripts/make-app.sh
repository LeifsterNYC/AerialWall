#!/bin/bash
# Assembles dist/AerialWall.app from a release swift build.
#   VERSION=1.2.3 REPO=owner/name SPARKLE_PUBLIC_KEY=... [UNIVERSAL=1] ./scripts/make-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.0.0-dev}"
REPO="${REPO:-LeifsterNYC/AerialWall}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-MISSING_PUBLIC_KEY}"

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN_DIR=".build/apple/Products/Release"
else
  swift build -c release
  BIN_DIR="$(swift build -c release --show-bin-path)"
fi

APP=dist/AerialWall.app
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp "$BIN_DIR/AerialWall" "$APP/Contents/MacOS/AerialWall"

sed -e "s|__VERSION__|$VERSION|g" \
    -e "s|__REPO__|$REPO|g" \
    -e "s|__SUPUBLICEDKEY__|$SPARKLE_PUBLIC_KEY|g" \
    Resources/Info.plist > "$APP/Contents/Info.plist"

SPARKLE_FRAMEWORK="$(find .build -type d -name "Sparkle.framework" -path "*macos*" | head -1)"
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
  SPARKLE_FRAMEWORK="$(find .build -type d -name "Sparkle.framework" | head -1)"
fi
[[ -n "$SPARKLE_FRAMEWORK" ]] || { echo "Sparkle.framework not found in .build" >&2; exit 1; }
cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/"

codesign --force --deep --sign - "$APP"
echo "Built $APP (version $VERSION)"
