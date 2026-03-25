#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="Release"
INSTALL=0
LAUNCH=0
PROJECT="FloatyDo/FloatyDo.xcodeproj"
SCHEME="FloatyDo"
DERIVED_DATA="/tmp/FloatyDoHostDerivedData"
PACKAGE_CACHE="/tmp/FloatyDoHostSourcePackages"
APP="FloatyDo.app"
LOCAL_OUTPUT_DIR=".build/host-app"
INSTALLED_APP_PATH="/Applications/FloatyDo.app"
PROCESS_PATTERNS=(
    "/Applications/FloatyDo.app/Contents/MacOS/FloatyDo"
    "$PWD/.build/debug/FloatyDo"
    ".build/debug/FloatyDo"
    "$PWD/.build/host-app/Debug/FloatyDo.app/Contents/MacOS/FloatyDo"
    ".build/host-app/Debug/FloatyDo.app/Contents/MacOS/FloatyDo"
    "$PWD/.build/host-app/Release/FloatyDo.app/Contents/MacOS/FloatyDo"
    ".build/host-app/Release/FloatyDo.app/Contents/MacOS/FloatyDo"
)

terminate_running_floatydo() {
    local pids=()
    local ps_output
    ps_output="$(ps -axo pid=,args=)"

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local pid="${line%% *}"
        local args="${line#* }"
        for pattern in "${PROCESS_PATTERNS[@]}"; do
            if [[ "$args" == *"$pattern"* ]]; then
                pids+=("$pid")
                break
            fi
        done
    done <<< "$ps_output"

    if [[ "${#pids[@]}" -eq 0 ]]; then
        echo "No existing FloatyDo process to stop."
        return
    fi

    echo "Stopping existing FloatyDo process(es): ${pids[*]}"
    kill "${pids[@]}" 2>/dev/null || true
    sleep 0.4
}

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
        --launch)
            LAUNCH=1
            ;;
        *)
            echo "Usage: $0 [--debug|--release] [--install] [--launch]" >&2
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
    terminate_running_floatydo
    echo "Installing $APP to $INSTALLED_APP_PATH"
    rm -rf "$INSTALLED_APP_PATH"
    ditto "$BUILT_APP" "$INSTALLED_APP_PATH"
    echo "Installed $INSTALLED_APP_PATH"

    if [[ "$LAUNCH" -eq 1 ]]; then
        echo "Launching $INSTALLED_APP_PATH"
        open -a "$INSTALLED_APP_PATH"
    fi
else
    echo "Local app bundle:"
    echo "  $LOCAL_APP"
    echo ""
    echo "To install, run:"
    if [[ "$CONFIG" == "Debug" ]]; then
        echo "  ./scripts/bundle.sh --debug --install --launch"
    else
        echo "  ./scripts/bundle.sh --release --install --launch"
    fi
fi
