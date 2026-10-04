#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
BUILD_DIR="$ROOT_DIR/.build"
SDK_PATH="$(xcrun --sdk "${MWIFI_SDK:-macosx}" --show-sdk-path)"
MODULE_CACHE="$BUILD_DIR/module-cache"
SDK_INTERFACE="$SDK_PATH/usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface"
SDK_SWIFT_VERSION="$(sed -n 's@^// swift-compiler-version: @@p' "$SDK_INTERFACE")"

mkdir -p "$BUILD_DIR/tests" "$MODULE_CACHE"
swiftc \
    -O \
    -parse-as-library \
    -target arm64-apple-macosx13.0 \
    -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE" \
    -interface-compiler-version "$SDK_SWIFT_VERSION" \
    "$ROOT_DIR/Sources/Mwifi/BatteryReading.swift" \
    "$ROOT_DIR/Sources/Mwifi/BatteryMonitor.swift" \
    "$ROOT_DIR/Sources/Mwifi/RouterClient.swift" \
    "$ROOT_DIR/Sources/Mwifi/LaunchAtLoginService.swift" \
    "$ROOT_DIR/Sources/Mwifi/NotificationService.swift" \
    "$ROOT_DIR/Sources/Mwifi/TrafficUsage.swift" \
    "$ROOT_DIR/Sources/Mwifi/TrafficUsageStore.swift" \
    "$ROOT_DIR/Sources/Mwifi/NetworkTrafficSampler.swift" \
    "$ROOT_DIR/Sources/Mwifi/WiFiNetworkService.swift" \
    "$ROOT_DIR/Sources/Mwifi/NotificationPolicy.swift" \
    -framework SwiftUI \
    -framework AppKit \
    -framework UserNotifications \
    -framework ServiceManagement \
    -framework CoreLocation \
    -framework CoreWLAN \
    -lsqlite3 \
    "$ROOT_DIR/Tests/ManualTests.swift" \
    -o "$BUILD_DIR/tests/MwifiTests"

"$BUILD_DIR/tests/MwifiTests"
