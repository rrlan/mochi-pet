#!/bin/bash
#
# Build Mochi into a self-contained .app bundle using swiftc.
# Requires only the Xcode Command Line Tools (no full Xcode needed).
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Mochi"
APP="$ROOT/build/$APP_NAME.app"
BIN="$APP/Contents/MacOS/$APP_NAME"
ICON="$ROOT/assets/AppIcon.icns"

echo "==> Cleaning previous build"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ ! -f "$ICON" ]]; then
  echo "==> Generating app icon"
  python3 "$ROOT/tools/generate_app_icon.py"
fi

echo "==> Compiling Swift sources"
# Pin the deployment target: the UI uses macOS 14 APIs (e.g. onChange(of:initial:)).
swiftc -O \
  -target "$(uname -m)-apple-macos14.0" \
  "$ROOT"/Sources/*.swift \
  -o "$BIN" \
  -framework AppKit \
  -framework SwiftUI

echo "==> Writing Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>Mochi 桌面宠物</string>
    <key>CFBundleIdentifier</key><string>com.yangran.mochi</string>
    <key>CFBundleVersion</key><string>0.1.5</string>
    <key>CFBundleShortVersionString</key><string>0.1.5</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Mochi needs permission to add quick memos to Apple Notes.</string>
</dict>
</plist>
PLIST

echo "==> Copying app icon"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc code-sign so macOS is happy launching it locally.
echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
  echo "   (codesign skipped — app still runs unsigned locally)"

# Make the companion CLI executable.
chmod +x "$ROOT/bin/mochi" 2>/dev/null || true

echo "==> Done: $APP"
echo "    CLI: $ROOT/bin/mochi  (symlink it onto your PATH to use from hooks)"
