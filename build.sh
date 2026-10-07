#!/bin/bash
# Build ClaudeShot from source, install it in /Applications and launch it.
#
# Signing identity: $SIGN_IDENTITY, else the one in .signing.local (never committed), else ad-hoc.
# A real certificate keeps the Accessibility permission across rebuilds; ad-hoc asks again each time.
# Don't add the sandbox entitlement: macOS refuses to launch Apple Development builds that have it.
set -e
cd "$(dirname "$0")"
[ -f .signing.local ] && source .signing.local
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

BUILD_DIR="$PWD/build"
APP="$BUILD_DIR/Release/ClaudeShot.app"
DEST="/Applications/ClaudeShot.app"
mkdir -p "$BUILD_DIR"

echo "Building..."
if ! xcodebuild -project ClaudeShot.xcodeproj -target ClaudeShot -configuration Release \
        SYMROOT="$BUILD_DIR" CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build \
        > "$BUILD_DIR/xcodebuild.log" 2>&1; then
    grep -E "error:" "$BUILD_DIR/xcodebuild.log" || true
    echo "Build failed (full log: build/xcodebuild.log)"
    exit 1
fi

echo "Installing in /Applications..."
pkill -x ClaudeShot 2>/dev/null || true; sleep 0.3
rm -rf "$DEST"
ditto "$APP" "$DEST"
codesign --sign "$SIGN_IDENTITY" --force --deep --timestamp=none "$DEST"
xattr -cr "$DEST"

open "$DEST"
sleep 1.5
if pgrep -x ClaudeShot > /dev/null; then
    echo "ClaudeShot is running. Shortcut: Cmd+Shift+Space"
    echo "First time only: allow it in System Settings > Privacy & Security >"
    echo "  Accessibility, and Screen & System Audio Recording."
else
    echo "ClaudeShot did not start"
    exit 1
fi
