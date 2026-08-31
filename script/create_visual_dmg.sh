#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-}"
OUTPUT_DMG="${2:-}"
WORK_DIR="${CANIS97_DMG_WORK_DIR:-}"
BACKGROUND_PATH="${CANIS97_DMG_BACKGROUND_PATH:-$ROOT_DIR/Distribution/DMG/background.png}"
LAYOUT_SCRIPT="${CANIS97_DMG_LAYOUT_SCRIPT:-$ROOT_DIR/Distribution/DMG/layout.applescript}"
HDIUTIL_BIN="${CANIS97_DMG_HDIUTIL_BIN:-hdiutil}"
OSASCRIPT_BIN="${CANIS97_DMG_OSASCRIPT_BIN:-osascript}"
SETFILE_BIN="${CANIS97_DMG_SETFILE_BIN:-/usr/bin/SetFile}"
DITTO_BIN="${CANIS97_DMG_DITTO_BIN:-/usr/bin/ditto}"
MOUNT_PATH="${CANIS97_DMG_MOUNT_PATH:-/Volumes/Canis97}"
PACKAGE_DIR="$WORK_DIR/dmg-package"
STAGING_DIR="$PACKAGE_DIR/staging"
READ_WRITE_DMG="$PACKAGE_DIR/Canis97-layout.dmg"
MOUNTED=false

fail() {
  echo "visual DMG error: $*" >&2
  exit 1
}

detach_image() {
  if [[ "$MOUNTED" == true ]]; then
    "$HDIUTIL_BIN" detach "$MOUNT_PATH" -quiet >/dev/null 2>&1 || true
  fi
}
trap detach_image EXIT

[[ -d "$APP_PATH" && "$APP_PATH" == *.app ]] || fail "first argument must be an app bundle"
[[ "$OUTPUT_DMG" = /* && "$OUTPUT_DMG" == *.dmg && ! -e "$OUTPUT_DMG" ]] || \
  fail "second argument must be a new absolute .dmg path"
[[ "$WORK_DIR" = /* && "$WORK_DIR" != / ]] || fail "CANIS97_DMG_WORK_DIR must be an explicit absolute path"
[[ -f "$BACKGROUND_PATH" && ! -L "$BACKGROUND_PATH" ]] || fail "DMG background is missing"
[[ -f "$LAYOUT_SCRIPT" && ! -L "$LAYOUT_SCRIPT" ]] || fail "DMG Finder layout script is missing"
[[ ! -e "$PACKAGE_DIR" ]] || fail "refusing to replace existing DMG work directory"
[[ ! -e "$MOUNT_PATH" ]] || fail "DMG mount path is already in use: $MOUNT_PATH"

mkdir -p "$STAGING_DIR/.background"
"$DITTO_BIN" "$APP_PATH" "$STAGING_DIR/Canis97.app"
"$DITTO_BIN" "$BACKGROUND_PATH" "$STAGING_DIR/.background/background.png"
ln -s /Applications "$STAGING_DIR/Applications"
"$SETFILE_BIN" -a V "$STAGING_DIR/.background"

"$HDIUTIL_BIN" create -quiet \
  -volname Canis97 \
  -srcfolder "$STAGING_DIR" \
  -format UDRW \
  -o "$READ_WRITE_DMG"

"$HDIUTIL_BIN" attach -readwrite -noverify -noautoopen \
  -mountpoint "$MOUNT_PATH" \
  "$READ_WRITE_DMG" \
  -quiet
MOUNTED=true

"$OSASCRIPT_BIN" "$LAYOUT_SCRIPT"
sync
"$HDIUTIL_BIN" detach "$MOUNT_PATH" -quiet
MOUNTED=false

"$HDIUTIL_BIN" convert "$READ_WRITE_DMG" \
  -quiet \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$OUTPUT_DMG"

[[ -f "$OUTPUT_DMG" ]] || fail "compressed DMG was not created"
printf 'visual DMG: %s\n' "$OUTPUT_DMG"
