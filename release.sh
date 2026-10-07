#!/bin/bash
# Build the public release: a universal (Apple Silicon + Intel), ad-hoc signed
# ClaudeShot.app zipped into dist/, plus the SHA-256 the Homebrew cask needs.
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" ClaudeShot/Info.plist)
BUILD_DIR="$PWD/build/release"
APP="$BUILD_DIR/Release/ClaudeShot.app"
ZIP="$PWD/dist/ClaudeShot-$VERSION.zip"
rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR" dist

echo "Building ClaudeShot $VERSION (universal)..."
if ! xcodebuild -project ClaudeShot.xcodeproj -target ClaudeShot -configuration Release \
        SYMROOT="$BUILD_DIR" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
        CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build \
        > "$BUILD_DIR/xcodebuild.log" 2>&1; then
    grep -E "error:" "$BUILD_DIR/xcodebuild.log" || true
    echo "Build failed (full log: build/release/xcodebuild.log)"
    exit 1
fi

codesign --sign - --force --deep --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
xattr -cr "$APP"
lipo -archs "$APP/Contents/MacOS/ClaudeShot"

rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
echo "$ZIP"
shasum -a 256 "$ZIP"
