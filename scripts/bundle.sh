#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Building FloatyDo (release)..."
swift build -c release

APP="FloatyDo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp .build/release/FloatyDo "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"

echo "Created $APP"
echo ""
echo "To install, drag FloatyDo.app to /Applications or run:"
echo "  cp -r FloatyDo.app /Applications/"
