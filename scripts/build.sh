#!/bin/bash
set -euo pipefail

# Build AppCleaner macOS app
# Usage: ./scripts/build.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$PROJECT_DIR/AppCleaner"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="AppCleaner"
BUNDLE_ID="com.appcleaner.AppCleaner"
VERSION="1.1.3"

# Code signing
SIGN_IDENTITY="Developer ID Application: Károly Fehér (YG66KQ8KDT)"

echo "==> Building $APP_NAME v${VERSION}"

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
if [ -f "$SRC_DIR/Resources/AppIcon.icns" ]; then
    cp "$SRC_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
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

# ── 5. Copy to dist ──────────────────────────────────────────────────
echo "==> Copying to dist..."
rm -rf "$DIST_DIR/$APP_NAME.app"
cp -R "$APP_BUNDLE" "$DIST_DIR/$APP_NAME.app"

# ── 6. Clean up ──────────────────────────────────────────────────────
rm -rf "$BUILD_DIR"

echo ""
echo "==> Done! Signed app created at:"
echo "    dist/$APP_NAME.app"
echo ""
echo "    Run with: open dist/$APP_NAME.app"
