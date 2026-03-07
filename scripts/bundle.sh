#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="release"
INSTALL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            CONFIG="debug"
            ;;
        --release)
            CONFIG="release"
            ;;
        --install)
            INSTALL=1
            ;;
        *)
            echo "Usage: $0 [--debug|--release] [--install]" >&2
            exit 1
            ;;
    esac
    shift
done

echo "Building FloatyDo ($CONFIG)..."
swift build -c "$CONFIG"

APP="FloatyDo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp ".build/$CONFIG/FloatyDo" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
cp -R "floatydo-icon.icon" "$APP/Contents/Resources/AppIcon.icon"

echo "Created $APP"
echo ""

if [[ "$INSTALL" -eq 1 ]]; then
    echo "Installing $APP to /Applications/FloatyDo.app"
    rm -rf /Applications/FloatyDo.app
    ditto "$APP" /Applications/FloatyDo.app
    echo "Installed /Applications/FloatyDo.app"
else
    echo "To install, drag FloatyDo.app to /Applications or run:"
    echo "  ./scripts/bundle.sh --$CONFIG --install"
fi
