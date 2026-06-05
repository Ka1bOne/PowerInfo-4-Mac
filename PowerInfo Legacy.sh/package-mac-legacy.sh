#!/bin/bash
set -e

./build-legacy.sh

STAGING=$(mktemp -d)
cp -R build-legacy/PowerInfo-Legacy.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG="PowerInfo-Legacy-1.5.0.dmg"
if [ -f "$DMG" ]; then rm "$DMG"; fi

hdiutil create -volname "PowerInfo-Legacy" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
echo "Created: $DMG"
