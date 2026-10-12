#!/bin/bash
# DiskDoom — archive, export, DMG, notarize, staple.
#
# Prereqs (fill in before first run):
#   TEAM_ID            — Apple Developer team (10 chars)
#   APPLE_ID           — the Apple ID used for notarytool
#   NOTARY_KEYCHAIN    — keychain item holding an app-specific password
#                        (xcrun notarytool store-credentials NOTARY_PASSWORD ...)
#   create-dmg         — brew install create-dmg
set -euo pipefail

APP_NAME="DiskDoom"
VERSION="1.0.0"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
TEAM_ID="YOUR_TEAM_ID"
APPLE_ID="your@email.com"
NOTARY_PROFILE="NOTARY_PASSWORD"   # notarytool credentials profile

BUILD_DIR="build"

echo "🔨 Archiving (Release, Developer ID)…"
xcodebuild -project DiskBuddy.xcodeproj \
    -scheme DiskBuddy \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$BUILD_DIR/derived" \
    -archivePath "$BUILD_DIR/${APP_NAME}.xcarchive" \
    archive

echo "📦 Exporting…"
xcodebuild -exportArchive \
    -archivePath "$BUILD_DIR/${APP_NAME}.xcarchive" \
    -exportPath "$BUILD_DIR/export" \
    -exportOptionsPlist scripts/ExportOptions.plist

echo "💿 Creating DMG…"
create-dmg \
    --volname "$APP_NAME" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "${APP_NAME}.app" 175 190 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 425 190 \
    "$BUILD_DIR/$DMG_NAME" \
    "$BUILD_DIR/export/${APP_NAME}.app" || {
        # create-dmg returns non-zero on benign AppleScript hiccups; keep the DMG if it exists
        [ -f "$BUILD_DIR/$DMG_NAME" ] || exit 1
}

echo "🔏 Signing DMG…"
codesign --sign "Developer ID Application: ${SIGNING_NAME:- ($TEAM_ID)}" \
    --timestamp "$BUILD_DIR/$DMG_NAME" 2>/dev/null || \
codesign --sign "Developer ID Application" --timestamp "$BUILD_DIR/$DMG_NAME"

echo "📤 Notarizing…"
xcrun notarytool submit "$BUILD_DIR/$DMG_NAME" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "@keychain:${NOTARY_PROFILE}" \
    --wait

echo "📎 Stapling…"
xcrun stapler staple "$BUILD_DIR/$DMG_NAME"

echo "✅ Done: $BUILD_DIR/$DMG_NAME"
