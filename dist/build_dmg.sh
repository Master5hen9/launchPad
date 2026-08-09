#!/bin/bash
# Build launchPad as a release .app bundle and package it into a distributable
# .dmg (launchPad.app + drag-to-Applications shortcut).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STAGING_DIR="$SCRIPT_DIR/staging"
APP_PATH="$STAGING_DIR/launchPad.app"
DMG_PATH="$SCRIPT_DIR/launchPad.dmg"

# Version comes from an explicit override (used by release.sh), otherwise the
# latest git tag, otherwise 0.1.0.
DEFAULT_VERSION="$(cd "$ROOT_DIR" && git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
VERSION="${VERSION:-${DEFAULT_VERSION:-0.1.0}}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

echo "==> Building release binary (product: launchPad)"
(cd "$ROOT_DIR" && swift build -c release --product launchPad)

echo "==> Assembling app bundle"
rm -rf "$STAGING_DIR"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

cp "$ROOT_DIR/.build/release/launchPad" "$APP_PATH/Contents/MacOS/launchPad"
cp "$ROOT_DIR/Sources/launchPadCore/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"

cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>com.ming.launchpad</string>
	<key>CFBundleName</key>
	<string>launchPad</string>
	<key>CFBundleDisplayName</key>
	<string>launchPad</string>
	<key>CFBundleExecutable</key>
	<string>launchPad</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$BUILD_NUMBER</string>
	<key>LSMinimumSystemVersion</key>
	<string>26.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

echo "==> Signing (stable local identity first, ad-hoc fallback)"
STABLE_IDENTITY="launchPad Local"
if codesign --force --sign "$STABLE_IDENTITY" "$APP_PATH" 2>/dev/null; then
    echo "Signed with stable identity: $STABLE_IDENTITY"
else
    codesign --force --sign - "$APP_PATH"
    echo "Stable identity not available on this machine; fell back to ad-hoc"
fi

echo "==> Creating staging DMG source"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating $DMG_PATH"
hdiutil create -volname "launchPad" -srcfolder "$STAGING_DIR" -ov \
    -format UDZO -fs APFS "$DMG_PATH"

echo "==> Keeping an extracted copy at $SCRIPT_DIR/launchPad.app"
rm -rf "$SCRIPT_DIR/launchPad.app"
cp -R "$APP_PATH" "$SCRIPT_DIR/launchPad.app"

echo "==> Verifying"
codesign --verify --deep --strict "$APP_PATH" && echo "codesign OK"
hdiutil verify "$DMG_PATH" | tail -1

echo "Done: $DMG_PATH"
