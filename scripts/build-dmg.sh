#!/bin/bash
set -euo pipefail

# Build AppCleaner DMG installer
# Usage: ./scripts/build-dmg.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$PROJECT_DIR/AppCleaner"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="AppCleaner"
BUNDLE_ID="com.appcleaner.AppCleaner"
VERSION="1.2.0"
DMG_NAME="AppCleaner-${VERSION}-macOS"
DMG_PATH="$DIST_DIR/$DMG_NAME.dmg"

# Code signing
SIGN_IDENTITY="Developer ID Application: Károly Fehér (YG66KQ8KDT)"
NOTARIZE_PROFILE="vc-notarize"

echo "==> Building $APP_NAME v${VERSION} DMG installer"

# Clean
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$DIST_DIR"

# ── 1. Collect source files ───────────────────────────────────────────
SOURCES=(
    "$SRC_DIR/AppCleanerApp.swift"
    "$SRC_DIR/Models/AppInfo.swift"
    "$SRC_DIR/Models/AppComponent.swift"
    "$SRC_DIR/Services/AppScanner.swift"
    "$SRC_DIR/Services/ComponentFinder.swift"
    "$SRC_DIR/Services/LeftoverScanner.swift"
    "$SRC_DIR/Services/DriveCleanerScanner.swift"
    "$SRC_DIR/Views/ContentView.swift"
    "$SRC_DIR/Views/CleanDriveView.swift"
    "$SRC_DIR/Views/AppListView.swift"
    "$SRC_DIR/Views/ComponentListView.swift"
    "$SRC_DIR/Views/ComponentRow.swift"
    "$SRC_DIR/Utilities/FileSize.swift"
    "$SRC_DIR/Utilities/ScriptRunner.swift"
)

# ── 2. Compile ────────────────────────────────────────────────────────
echo "==> Compiling Swift sources..."
swiftc \
    "${SOURCES[@]}" \
    -o "$BUILD_DIR/$APP_NAME" \
    -target arm64-apple-macosx14.0 \
    -framework SwiftUI \
    -framework AppKit \
    -framework UniformTypeIdentifiers \
    -O

echo "==> Compile OK"

# ── 3. Create .app bundle ─────────────────────────────────────────────
echo "==> Creating app bundle..."
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy icon
ICNS_PATH="$SRC_DIR/Resources/AppIcon.icns"
if [ -f "$ICNS_PATH" ]; then
    cp "$ICNS_PATH" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key>
	<string>AppCleaner</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleVersion</key>
	<string>${VERSION}</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleExecutable</key>
	<string>${APP_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIconName</key>
	<string>AppIcon</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSAppleEventsUsageDescription</key>
	<string>AppCleaner uses Finder to move files to the Trash and to empty the Trash.</string>
</dict>
</plist>
PLIST

# Entitlements (no sandbox)
cat > "$BUILD_DIR/entitlements.plist" << 'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<false/>
	<key>com.apple.security.automation.apple-events</key>
	<true/>
</dict>
</plist>
ENTITLEMENTS

# ── 4. Code sign ──────────────────────────────────────────────────────
echo "==> Signing app bundle..."
codesign --force --options runtime \
    --entitlements "$BUILD_DIR/entitlements.plist" \
    --sign "$SIGN_IDENTITY" \
    "$APP_BUNDLE"

echo "==> Verifying signature..."
codesign --verify --verbose "$APP_BUNDLE"

# ── 5. Create DMG ────────────────────────────────────────────────────
echo "==> Creating DMG..."

DMG_STAGING="$BUILD_DIR/dmg-staging"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

rm -f "$DMG_PATH"

# Create read-write DMG first, then set volume icon, then convert to read-only
DMG_RW="$BUILD_DIR/$DMG_NAME-rw.dmg"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDRW \
    "$DMG_RW"

# Set volume icon
if [ -f "$ICNS_PATH" ]; then
    echo "==> Setting volume icon..."
    MOUNT_DIR=$(hdiutil attach "$DMG_RW" -readwrite -noverify -noautoopen | grep "/Volumes/" | sed 's/.*\/Volumes/\/Volumes/')
    cp "$ICNS_PATH" "$MOUNT_DIR/.VolumeIcon.icns"
    SetFile -a C "$MOUNT_DIR"
    hdiutil detach "$MOUNT_DIR" -quiet
fi

# Convert to compressed read-only
hdiutil convert "$DMG_RW" -format UDZO -o "$DMG_PATH"
rm -f "$DMG_RW"

# Sign the DMG itself
echo "==> Signing DMG..."
codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"

# ── 6. Notarize ──────────────────────────────────────────────────────
echo "==> Submitting for notarization (this may take a few minutes)..."
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARIZE_PROFILE" --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

# ── 7. Update dist .app, then clean up ───────────────────────────────
rm -rf "$DIST_DIR/$APP_NAME.app"
cp -R "$APP_BUNDLE" "$DIST_DIR/$APP_NAME.app"

rm -rf "$BUILD_DIR"

echo ""
echo "==> Done! Signed & notarized DMG created at:"
echo "    dist/$DMG_NAME.dmg"
echo ""
echo "    Size: $(du -h "$DMG_PATH" | cut -f1)"
