#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/Info.plist")"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
APP="$ROOT/dist/认知统计.app"
codesign --verify --deep --strict "$APP"
cp "$ROOT/LICENSE" "$STAGE/LICENSE.txt"
cp "$ROOT/docs/INSTALL.txt" "$STAGE/使用说明.txt"
ditto --norsrc --noextattr --noqtn "$APP" "$STAGE/认知统计.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname RenZhi -srcfolder "$STAGE" -ov -format UDZO "$ROOT/dist/RenZhi-$VERSION.dmg"
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$APP" "$ROOT/dist/RenZhi-$VERSION-macOS.zip"
cd "$ROOT/dist"
shasum -a 256 "RenZhi-$VERSION.dmg" "RenZhi-$VERSION-macOS.zip" > SHA256SUMS
printf 'Packaged version %s\n' "$VERSION"
