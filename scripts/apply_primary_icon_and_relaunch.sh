#!/bin/bash
set -euo pipefail

REPO_ROOT="${1:?repo root required}"
THEME="${2:?theme required}"
CURRENT_PID="${3:?current pid required}"

ASSETS_DIR="$REPO_ROOT/FloatyDo/FloatyDo/Assets.xcassets"
THEME_PNG="$ASSETS_DIR/${THEME}.imageset/${THEME}.png"
APP_ICON_SET_NAME="GeneratedAppIcon_${THEME}"
GENERATED_SET="$ASSETS_DIR/${APP_ICON_SET_NAME}.appiconset"
GENERATED_CONTENTS="$GENERATED_SET/Contents.json"
DERIVED_DATA="$REPO_ROOT/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/FloatyDo.app"
INSTALL_PATH="/Applications/FloatyDo.app"
THEME_MARKER="$REPO_ROOT/.floatydo-primary-icon-theme"
LOG_PATH="/tmp/floatydo-primary-icon-relaunch.log"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
APP_SUPPORT_DIR="$HOME/Library/Application Support/FloatyDo"
PROJECT_ROOT_FILE="$APP_SUPPORT_DIR/project-root.txt"
BUILD_STAMP="$(date +%s)"

exec >"$LOG_PATH" 2>&1
echo "[$(date)] Starting primary icon relaunch for theme: $THEME"
echo "Repo root: $REPO_ROOT"

if [[ ! -f "$THEME_PNG" ]]; then
  echo "Missing theme source: $THEME_PNG" >&2
  exit 1
fi

rm -rf "$ASSETS_DIR"/GeneratedAppIcon_*.appiconset
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

echo "[$(date)] Rebuilding FloatyDo with primary icon theme: $THEME"
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project "$REPO_ROOT/FloatyDo/FloatyDo.xcodeproj" \
  -scheme FloatyDo \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  ASSETCATALOG_COMPILER_APPICON_NAME="$APP_ICON_SET_NAME" \
  CURRENT_PROJECT_VERSION="$BUILD_STAMP" \
  INFOPLIST_KEY_CFBundleVersion="$BUILD_STAMP" \
  build

printf '%s\n' "$THEME" > "$THEME_MARKER"
mkdir -p "$APP_SUPPORT_DIR"
printf '%s\n' "$REPO_ROOT" > "$PROJECT_ROOT_FILE"

echo "[$(date)] Installing rebuilt app to $INSTALL_PATH"
rm -rf "$INSTALL_PATH"
/usr/bin/ditto "$APP_PATH" "$INSTALL_PATH"
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

kill "$CURRENT_PID" 2>/dev/null || true
sleep 0.2
nohup /usr/bin/open -n "$INSTALL_PATH" >>"$LOG_PATH" 2>&1 &
