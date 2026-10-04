#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
BUILD_DIR="$ROOT_DIR/.build"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "Invalid semantic version in Resources/Info.plist" >&2
    exit 1
fi
APP_DIR="$ROOT_DIR/dist/Mwifi-$VERSION.app"
if [[ -e "$APP_DIR" || -L "$APP_DIR" ]]; then
    echo "Build already exists: $APP_DIR. Use a new version for a new release." >&2
    exit 1
fi
SDK_PATH="$(xcrun --sdk "${MWIFI_SDK:-macosx}" --show-sdk-path)"
MODULE_CACHE="$BUILD_DIR/module-cache"
SDK_INTERFACE="$SDK_PATH/usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface"
SDK_SWIFT_VERSION="$(sed -n 's@^// swift-compiler-version: @@p' "$SDK_INTERFACE")"

cd "$ROOT_DIR"
mkdir -p "$BUILD_DIR/release" "$MODULE_CACHE"
swiftc \
    -O \
    -parse-as-library \
    -module-name Mwifi \
    -file-prefix-map "$ROOT_DIR=." \
    -debug-prefix-map "$ROOT_DIR=." \
    -target arm64-apple-macosx13.0 \
    -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE" \
    -interface-compiler-version "$SDK_SWIFT_VERSION" \
    "$ROOT_DIR"/Sources/Mwifi/*.swift \
    -framework SwiftUI \
    -framework AppKit \
    -framework Charts \
    -framework CoreLocation \
    -framework CoreWLAN \
    -framework UserNotifications \
    -framework ServiceManagement \
    -lsqlite3 \
    -o "$BUILD_DIR/release/Mwifi"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/release/Mwifi" "$APP_DIR/Contents/MacOS/Mwifi"
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/Mwifi.icns" "$APP_DIR/Contents/Resources/Mwifi.icns"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"
