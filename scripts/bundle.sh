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
LOCAL_OUTPUT_DIR=".build/host-app"

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
LOCAL_APP="$LOCAL_OUTPUT_DIR/$CONFIG/$APP"

if [[ ! -d "$BUILT_APP" ]]; then
    echo "Expected app bundle not found at $BUILT_APP" >&2
    exit 1
fi

rm -rf "$APP"
rm -rf "$LOCAL_APP"
mkdir -p "$(dirname "$LOCAL_APP")"
ditto "$BUILT_APP" "$LOCAL_APP"

echo "Created $LOCAL_APP"
echo ""

if [[ "$INSTALL" -eq 1 ]]; then
    echo "Installing $APP to /Applications/FloatyDo.app"
    rm -rf /Applications/FloatyDo.app
    ditto "$BUILT_APP" /Applications/FloatyDo.app
    echo "Installed /Applications/FloatyDo.app"
else
    echo "Local app bundle:"
    echo "  $LOCAL_APP"
    echo ""
    echo "To install, run:"
    if [[ "$CONFIG" == "Debug" ]]; then
        echo "  ./scripts/bundle.sh --debug --install"
    else
        echo "  ./scripts/bundle.sh --release --install"
    fi
fi
