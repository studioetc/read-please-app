#!/bin/bash

APP_NAME="ReadPlease"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"

# Clean previous build
rm -rf "$APP_BUNDLE"

# Build release
swift build -c release

# Create App Bundle Structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy Binary
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Copy Info.plist
cp "Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Code Sign with stable Apple Development identity to retain permissions
codesign --force --deep --entitlements Entitlements.plist --sign "${CODESIGN_IDENTITY:--}" "$APP_BUNDLE"

echo "✅ App built at $APP_BUNDLE"
echo "👉 Move this to /Applications or run: open $APP_BUNDLE"
