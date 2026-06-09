#!/bin/bash
# Package script for regular PowerInfo (macOS 15.0+)
set -e

APP_NAME="PowerInfo"
BUILD_DIR="build"
DMG_NAME="${APP_NAME}-1.5.0"
VOLUME_NAME="${APP_NAME}"

# Build first
./build.sh

# Create temporary DMG staging area
STAGING_DIR=$(mktemp -d)
cp -R "${BUILD_DIR}/${APP_NAME}.app" "${STAGING_DIR}/"

# Create Applications symlink
ln -s /Applications "${STAGING_DIR}/Applications"

# Create DMG
if [ -f "${DMG_NAME}.dmg" ]; then rm "${DMG_NAME}.dmg"; fi
hdiutil create -volname "${VOLUME_NAME}" -srcfolder "${STAGING_DIR}" -ov -format UDZO "${DMG_NAME}.dmg"

# Cleanup
rm -rf "${STAGING_DIR}"

echo "Created: ${DMG_NAME}.dmg"
