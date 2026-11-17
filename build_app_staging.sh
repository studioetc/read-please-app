#!/bin/bash
# Stop at the first failure, so a failed build never packages a stale binary.
set -euo pipefail

APP_NAME="ReadPlease"
BUILD_DIR=".build/release"
APP_BUNDLE="ReadPlease-Staging.app"

# Clean previous build
rm -rf "$APP_BUNDLE"

# Build release
swift build -c release

# Create App Bundle Structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy Binary
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Copy SwiftPM resource bundles (e.g. KeyboardShortcuts) into Contents/Resources; without them
# Settings crashes when it creates a shortcut recorder (see ThirdParty/KeyboardShortcuts/VENDORED.md).
for bundle in "$BUILD_DIR"/*.bundle; do
  if [ -e "$bundle" ]; then cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"; fi
done

# Include the MIT/BSD notices with redistributed binaries.
cp "THIRD_PARTY_NOTICES.md" "$APP_BUNDLE/Contents/Resources/"

# Copy Info.plist
cp "Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Update Plist for staging
plutil -replace CFBundleIdentifier -string "com.onestepp.ReadPlease.staging" "$APP_BUNDLE/Contents/Info.plist"
plutil -replace CFBundleName -string "ReadPleaseStaging" "$APP_BUNDLE/Contents/Info.plist"
plutil -replace CFBundleExecutable -string "ReadPleaseStaging" "$APP_BUNDLE/Contents/Info.plist"

# Rename executable to match Bundle Executable
mv "$APP_BUNDLE/Contents/MacOS/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/ReadPleaseStaging"

# Code Sign with stable Apple Development identity to retain permissions
codesign --force --deep --entitlements Entitlements.plist --sign "${CODESIGN_IDENTITY:--}" "$APP_BUNDLE"

echo "✅ Staging App built at $APP_BUNDLE"
echo "👉 You can run: open $APP_BUNDLE"
