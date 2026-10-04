#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "Invalid semantic version in Resources/Info.plist" >&2
    exit 1
fi

APP_DIR="$ROOT_DIR/dist/Mwifi-$VERSION.app"
DMG_NAME="Mwifi-$VERSION-arm64.dmg"
DMG_PATH="$ROOT_DIR/dist/$DMG_NAME"
CHECKSUM_PATH="$DMG_PATH.sha256"
if [[ -e "$DMG_PATH" || -L "$DMG_PATH" || -e "$CHECKSUM_PATH" || -L "$CHECKSUM_PATH" ]]; then
    echo "Release asset already exists. Use a new version for a new release." >&2
    exit 1
fi

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_DIR/Contents/Info.plist")"
if [[ "$APP_VERSION" != "$VERSION" || "$APP_BUILD" != "$BUILD_NUMBER" ]]; then
    echo "App version/build does not match Resources/Info.plist" >&2
    exit 1
fi
if [[ "$(lipo -archs "$APP_DIR/Contents/MacOS/Mwifi")" != "arm64" ]]; then
    echo "Expected an arm64 application" >&2
    exit 1
fi
codesign --verify --deep --strict "$APP_DIR"

# Package only the app, without Finder metadata or local extended attributes.
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mwifi-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
ditto --norsrc --noextattr --noqtn "$APP_DIR" "$STAGING_DIR/Mwifi.app"
ln -s /Applications "$STAGING_DIR/Applications"
codesign --verify --deep --strict "$STAGING_DIR/Mwifi.app"
hdiutil create \
    -volname "Mwifi $VERSION" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -fs HFS+ \
    "$DMG_PATH"
hdiutil verify "$DMG_PATH"
cd "$ROOT_DIR/dist"
shasum -a 256 "$DMG_NAME" > "$CHECKSUM_PATH"
echo "$DMG_PATH"
echo "$CHECKSUM_PATH"
