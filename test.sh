#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_TEMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TEMP"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  "$ROOT/Sources/AppConfiguration.swift" "$ROOT/Sources/FeishuSession.swift" \
  "$ROOT/Sources/AttendanceModel.swift" "$ROOT/Tests/Smoke.swift" -o "$TEST_TEMP/tests"
"$TEST_TEMP/tests" "$@"
