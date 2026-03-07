#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="Release"
INSTALL=0
PROJECT="FloatyDo/FloatyDo.xcodeproj"
SCHEME="FloatyDo"
DERIVED_DATA="/tmp/FloatyDoHostDerivedData"
PACKAGE_CACHE="/tmp/FloatyDoHostSourcePackages"
APP="FloatyDo.app"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            CONFIG="Debug"
            ;;
        --release)
            CONFIG="Release"
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

echo "Building FloatyDo host app ($CONFIG)..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED_DATA" \
    -clonedSourcePackagesDirPath "$PACKAGE_CACHE" \
    build

BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIG/$APP"

if [[ ! -d "$BUILT_APP" ]]; then
    echo "Expected app bundle not found at $BUILT_APP" >&2
    exit 1
fi

rm -rf "$APP"
ditto "$BUILT_APP" "$APP"

echo "Created $APP"
echo ""

if [[ "$INSTALL" -eq 1 ]]; then
    echo "Installing $APP to /Applications/FloatyDo.app"
    rm -rf /Applications/FloatyDo.app
    ditto "$APP" /Applications/FloatyDo.app
    echo "Installed /Applications/FloatyDo.app"
else
    echo "To install, drag FloatyDo.app to /Applications or run:"
    if [[ "$CONFIG" == "Debug" ]]; then
        echo "  ./scripts/bundle.sh --debug --install"
    else
        echo "  ./scripts/bundle.sh --release --install"
    fi
fi
