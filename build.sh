#!/bin/bash
set -e

# Configuration
APP_NAME="PowerInfo"
BUILD_DIR="build"
CONTENTS_DIR="${BUILD_DIR}/${APP_NAME}.app/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# Kill existing instance if running
killall "$APP_NAME" 2>/dev/null || true

# Cleanup
rm -rf "$BUILD_DIR"

# Create directory structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Compile the Swift code
swiftc -O -sdk $(xcrun --show-sdk-path --sdk macosx) -framework Cocoa -framework IOKit PowerInfo.swift -o "${MACOS_DIR}/${APP_NAME}"

# Create Info.plist
cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.user.PowerInfo</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "Build complete! You can find the app in ${BUILD_DIR}/${APP_NAME}.app"
# Run the app to test
open "${BUILD_DIR}/${APP_NAME}.app"
