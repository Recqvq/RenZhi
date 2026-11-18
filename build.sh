#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/认知统计.app"
BUILD_TEMP="$(mktemp -d)"
trap 'rm -rf "$BUILD_TEMP"' EXIT
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
xcrun swift "$ROOT/Scripts/GenerateIcon.swift" "$BUILD_TEMP/AppIcon.iconset"
iconutil -c icns "$BUILD_TEMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
for architecture in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -parse-as-library \
    -target "$architecture-apple-macos14.0" \
    -file-prefix-map "$ROOT"=RenZhi -debug-prefix-map "$ROOT"=RenZhi \
    -framework AppKit -framework Combine -framework SwiftUI -framework UserNotifications \
    "$ROOT"/Sources/*.swift -o "$BUILD_TEMP/AttendanceSentinel-$architecture"
done
lipo -create "$BUILD_TEMP/AttendanceSentinel-arm64" "$BUILD_TEMP/AttendanceSentinel-x86_64" \
  -output "$APP/Contents/MacOS/AttendanceSentinel"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built %s\n' "$APP"
