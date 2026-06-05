#!/bin/bash
set -e

APP_NAME="PowerInfo-Legacy"
BUILD_DIR="build-legacy"
CONTENTS_DIR="${BUILD_DIR}/${APP_NAME}.app/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

killall "$APP_NAME" 2>/dev/null || true
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

swiftc -O -target x86_64-apple-macos12 -target arm64-apple-macos12 -sdk $(xcrun --show-sdk-path --sdk macosx) -framework Cocoa -framework IOKit PowerInfo-Legacy.swift -o "${MACOS_DIR}/${APP_NAME}"

cat > "${CONTENTS_DIR}/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>PowerInfo-Legacy</string>
	<key>CFBundleIdentifier</key>
	<string>com.user.PowerInfo-Legacy</string>
	<key>CFBundleName</key>
	<string>PowerInfo-Legacy</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.5.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>12.0</string>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
EOF

echo "Done! App at ${BUILD_DIR}/${APP_NAME}.app"
