#!/bin/bash
# Assembles dist/AerialWall.app from a release swift build.
#   VERSION=1.2.3 REPO=owner/name SPARKLE_PUBLIC_KEY=... [UNIVERSAL=1] ./scripts/make-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.0.0-dev}"
REPO="${REPO:-LeifsterNYC/AerialWall}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"

# A release without a real public key ships apps that can never verify an update.
if [[ -z "$SPARKLE_PUBLIC_KEY" ]]; then
  if [[ "$VERSION" == "0.0.0-dev" ]]; then
    SPARKLE_PUBLIC_KEY="DEV_BUILD_NO_UPDATES"
  else
    echo "SPARKLE_PUBLIC_KEY is required for release builds" >&2
    exit 1
  fi
fi

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
