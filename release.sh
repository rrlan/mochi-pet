#!/bin/bash
#
# Build a distributable Mochi.dmg: a universal (Apple Silicon + Intel) .app,
# ad-hoc signed, packaged into a drag-to-Applications disk image.
#
# Note: this is NOT notarized, so on first launch users must right-click → Open
# (or allow it once in System Settings → Privacy & Security). For a seamless
# double-click install you need an Apple Developer ID + notarization.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Mochi.app"
BIN="$APP/Contents/MacOS/Mochi"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo 0.1.0)"
DMG="$ROOT/build/Mochi-$VERSION.dmg"
DEPLOY="macos14.0"

# 1) Build the app skeleton (Info.plist, icon, ad-hoc sign) via build.sh.
"$ROOT/build.sh"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/build/Mochi-$VERSION.dmg"

# 2) Replace the single-arch binary with a universal one.
echo "==> Building universal binary (arm64 + x86_64, $DEPLOY)"
swiftc -O -target "arm64-apple-$DEPLOY"  "$ROOT"/Sources/*.swift -o /tmp/mochi-arm64 -framework AppKit -framework SwiftUI
swiftc -O -target "x86_64-apple-$DEPLOY" "$ROOT"/Sources/*.swift -o /tmp/mochi-x86   -framework AppKit -framework SwiftUI
lipo -create /tmp/mochi-arm64 /tmp/mochi-x86 -output "$BIN"
rm -f /tmp/mochi-arm64 /tmp/mochi-x86
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
echo "==> $(lipo -info "$BIN")"

# 3) Package the DMG (Mochi.app + an Applications drop target).
echo "==> Packaging $DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Mochi 桌面宠物" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "==> Done: $DMG ($(du -h "$DMG" | awk '{print $1}'))"
