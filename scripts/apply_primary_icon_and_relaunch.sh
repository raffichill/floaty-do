#!/bin/bash
set -euo pipefail

REPO_ROOT="${1:?repo root required}"
THEME="${2:?theme required}"
MARKER_THEME="${3:?marker theme required}"
CURRENT_PID="${4:?current pid required}"

ICONS_DIR="$REPO_ROOT/FloatyDo/FloatyDo/Icons"
THEME_ICON="$ICONS_DIR/${THEME}.icon"
APP_ICON_NAME="$THEME"
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
XCODEBUILD="/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"

exec >"$LOG_PATH" 2>&1

log() {
  echo "[$(date)] $*"
}

die() {
  log "ERROR: $*"
  exit 1
}

verify_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    die "Missing file: $path"
  fi
}

assert_known_theme() {
  case "$THEME" in
    theme1|theme2|theme3|theme4|theme5|theme6|theme7|theme8)
      return 0
      ;;
    *)
      die "Unknown theme: $THEME"
      ;;
  esac
}

verify_binary() {
  local app_bundle="$1"
  if [[ ! -d "$app_bundle" ]]; then
    die "Build did not produce app bundle: $app_bundle"
  fi

  local info_plist="$app_bundle/Contents/Info.plist"
  verify_file "$info_plist"

  local icon_name
  icon_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$info_plist" 2>/dev/null || true)
  if [[ "$icon_name" != "$APP_ICON_NAME" ]]; then
    die "Unexpected CFBundleIconName: ${icon_name:-<missing>} (expected $APP_ICON_NAME)"
  fi

  local icon_file
  icon_file=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$info_plist" 2>/dev/null || true)
  if [[ -n "$icon_file" ]]; then
    if [[ "$icon_file" != *.icns ]]; then
      icon_file="${icon_file%.*}.icns"
    fi
    verify_file "$app_bundle/Contents/Resources/$icon_file"
  fi
}

verify_icon_source() {
  local icon_path="$1"
  if [[ ! -d "$icon_path" ]]; then
    die "Missing icon source: $icon_path"
  fi

  verify_file "$icon_path/icon.json"
}

atomic_write() {
  local content="$1"
  local path="$2"
  local tmp="${path}.tmp"
  printf '%s\n' "$content" > "$tmp"
  mv "$tmp" "$path"
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

register_clean_bundles() {
  local stale_path
  for stale_path in \
    "$REPO_ROOT/DerivedData/Build/Products/Debug/FloatyDo.app" \
    "$REPO_ROOT/.build/host-app/Debug/FloatyDo.app" \
    "/private/tmp/FloatyDoHostDerivedData/Build/Products/Debug/FloatyDo.app" \
    "/private/tmp/FloatyDoHostDerivedData/Build/Products/Release/FloatyDo.app"
  do
    "$LSREGISTER" -u "$stale_path" >/dev/null 2>&1 || true
  done
  "$LSREGISTER" -f -R -trusted "$INSTALL_PATH"
}

log "Starting primary icon relaunch for theme: $THEME"
log "Repo root: $REPO_ROOT"
log "Build stamp: $BUILD_STAMP"

assert_known_theme
verify_icon_source "$THEME_ICON"

log "Rebuilding FloatyDo with primary icon theme: $THEME"
"$XCODEBUILD" \
  -project "$REPO_ROOT/FloatyDo/FloatyDo.xcodeproj" \
  -scheme FloatyDo \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  clean build \
  ASSETCATALOG_COMPILER_APPICON_NAME="$APP_ICON_NAME" \
  CURRENT_PROJECT_VERSION="$BUILD_STAMP" \
  INFOPLIST_KEY_CFBundleVersion="$BUILD_STAMP"

verify_binary "$APP_PATH"
verify_icon_source "$THEME_ICON"

mkdir -p "$APP_SUPPORT_DIR"
atomic_write "$REPO_ROOT" "$PROJECT_ROOT_FILE"

log "Installing rebuilt app to $INSTALL_PATH"
rm -rf "$TMP_INSTALL"
/usr/bin/ditto "$APP_PATH" "$TMP_INSTALL"
rm -rf "$INSTALL_PATH"
mv "$TMP_INSTALL" "$INSTALL_PATH"
verify_binary "$INSTALL_PATH"
atomic_write "$MARKER_THEME" "$THEME_MARKER"

if [[ -x "$LSREGISTER" ]]; then
  register_clean_bundles
fi

/usr/bin/killall Dock >/dev/null 2>&1 || true

kill_running_instances
nohup /usr/bin/open -n "$INSTALL_PATH" >>"$LOG_PATH" 2>&1 &
log "Relaunch triggered for theme: $THEME"
