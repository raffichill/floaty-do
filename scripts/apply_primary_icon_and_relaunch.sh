#!/bin/bash
set -euo pipefail

REPO_ROOT="${1:?repo root required}"
THEME="${2:?theme required}"
CURRENT_PID="${3:?current pid required}"

ASSETS_DIR="$REPO_ROOT/FloatyDo/FloatyDo/Assets.xcassets"
THEME_PNG="$ASSETS_DIR/${THEME}.imageset/${THEME}.png"
APP_ICON_SET_NAME="GeneratedAppIcon"
GENERATED_SET="$ASSETS_DIR/$APP_ICON_SET_NAME.appiconset"
GENERATED_CONTENTS="$GENERATED_SET/Contents.json"
DERIVED_DATA="$REPO_ROOT/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/FloatyDo.app"
INSTALL_PATH="/Applications/FloatyDo.app"
THEME_MARKER="$REPO_ROOT/.floatydo-primary-icon-theme"
APP_SUPPORT_DIR="$HOME/Library/Application Support/FloatyDo"
PROJECT_ROOT_FILE="$APP_SUPPORT_DIR/project-root.txt"
BUILD_STAMP="$(date +%s)"
TMP_INSTALL="${INSTALL_PATH}.tmp"
LOG_PATH="/tmp/floatydo-primary-icon-relaunch.log"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

exec >"$LOG_PATH" 2>&1

log() {
  echo "[$(date)] $*"
}

atomic_write() {
  local content="$1"
  local path="$2"
  local tmp="${path}.tmp"
  printf '%s\n' "$content" > "$tmp"
  mv "$tmp" "$path"
}

verify_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "Missing path: $path" >&2
    return 1
  fi
}

verify_binary() {
  local app_bundle="$1"
  if [[ ! -d "$app_bundle" ]]; then
    echo "Build did not produce app bundle: $app_bundle" >&2
    return 1
  fi

  local info_plist="$app_bundle/Contents/Info.plist"
  verify_file "$info_plist"

  local icon_name
  icon_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$info_plist" 2>/dev/null || true)
  if [[ "$icon_name" != "$APP_ICON_SET_NAME" ]]; then
    echo "Unexpected CFBundleIconName: ${icon_name:-<missing>} (expected $APP_ICON_SET_NAME)" >&2
    return 1
  fi

  local icon_file
  icon_file=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$info_plist" 2>/dev/null || true)
  if [[ -n "$icon_file" ]]; then
    if [[ "$icon_file" != *.icns ]]; then
      icon_file="${icon_file%.*}.icns"
    fi

    if [[ ! -f "$app_bundle/Contents/Resources/$icon_file" ]]; then
      echo "Expected bundled icon missing: $icon_file" >&2
      return 1
    fi
  fi
}

kill_running_instances() {
  if kill -0 "$CURRENT_PID" >/dev/null 2>&1; then
    kill "$CURRENT_PID" >/dev/null 2>&1 || true
  fi

  for _ in 1 2 3 4 5; do
    if ps -p "$CURRENT_PID" >/dev/null 2>&1; then
      kill -9 "$CURRENT_PID" >/dev/null 2>&1 || true
      sleep 0.2
    fi
  done

  if pgrep -f "^$INSTALL_PATH/Contents/MacOS/FloatyDo$" >/dev/null 2>&1; then
    pkill -f "^$INSTALL_PATH/Contents/MacOS/FloatyDo$" >/dev/null 2>&1 || true
    sleep 0.2
  fi
}

log "Starting primary icon relaunch for theme: $THEME"
log "Repo root: $REPO_ROOT"
log "Build stamp: $BUILD_STAMP"

if [[ ! -f "$THEME_PNG" ]]; then
  echo "Missing theme source: $THEME_PNG" >&2
  exit 1
fi

rm -rf "$GENERATED_SET"
mkdir -p "$GENERATED_SET"

cat > "$GENERATED_CONTENTS" <<'JSON'
{
  "images" : [
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon-512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon-1024.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

cp "$THEME_PNG" "$GENERATED_SET/icon-1024.png"
/usr/bin/sips -z 512 512 "$THEME_PNG" --out "$GENERATED_SET/icon-512.png" >/dev/null

log "Rebuilding FloatyDo with primary icon theme: $THEME"
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project "$REPO_ROOT/FloatyDo/FloatyDo.xcodeproj" \
  -scheme FloatyDo \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  clean build \
  ASSETCATALOG_COMPILER_APPICON_NAME="$APP_ICON_SET_NAME" \
  CURRENT_PROJECT_VERSION="$BUILD_STAMP" \
  INFOPLIST_KEY_CFBundleVersion="$BUILD_STAMP"

verify_binary "$APP_PATH"

verify_file "$THEME_PNG"

mkdir -p "$APP_SUPPORT_DIR"
atomic_write "$REPO_ROOT" "$PROJECT_ROOT_FILE"

log "Installing rebuilt app to $INSTALL_PATH"
rm -rf "$TMP_INSTALL"
/usr/bin/ditto "$APP_PATH" "$TMP_INSTALL"
rm -rf "$INSTALL_PATH"
mv "$TMP_INSTALL" "$INSTALL_PATH"
verify_binary "$INSTALL_PATH"
atomic_write "$THEME" "$THEME_MARKER"

if [[ -x "$LSREGISTER" ]]; then
  for stale_path in \
    "$REPO_ROOT/DerivedData/Build/Products/Debug/FloatyDo.app" \
    "$REPO_ROOT/.build/host-app/Debug/FloatyDo.app" \
    "/private/tmp/FloatyDoHostDerivedData/Build/Products/Debug/FloatyDo.app" \
    "/private/tmp/FloatyDoHostDerivedData/Build/Products/Release/FloatyDo.app"
  do
    "$LSREGISTER" -u "$stale_path" >/dev/null 2>&1 || true
  done
  "$LSREGISTER" -f -R -trusted "$INSTALL_PATH"
fi

/usr/bin/killall Dock >/dev/null 2>&1 || true

kill_running_instances

nohup /usr/bin/open -n "$INSTALL_PATH" >>"$LOG_PATH" 2>&1 &
log "Relaunch triggered for theme: $THEME"
