#!/usr/bin/env bash
# Builds a release binary and wraps it into build/Timekeeper.app (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Timekeeper"

APP=build/Timekeeper.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Timekeeper"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Built $APP — run: open $APP"
