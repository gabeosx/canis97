#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DMG_SCRIPT="$ROOT_DIR/script/create_visual_dmg.sh"
BACKGROUND="$ROOT_DIR/Distribution/DMG/background.png"
LAYOUT="$ROOT_DIR/Distribution/DMG/layout.applescript"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$DMG_SCRIPT" ]] || fail 'visual DMG builder is missing or not executable'
[[ -f "$BACKGROUND" && ! -L "$BACKGROUND" ]] || fail 'visual DMG background is missing'
[[ -f "$LAYOUT" && ! -L "$LAYOUT" ]] || fail 'visual DMG Finder layout is missing'
[[ "$(sips -g pixelWidth "$BACKGROUND" 2>/dev/null | awk '/pixelWidth/ { print $2 }')" == 720 ]] || fail 'DMG background width changed'
[[ "$(sips -g pixelHeight "$BACKGROUND" 2>/dev/null | awk '/pixelHeight/ { print $2 }')" == 460 ]] || fail 'DMG background height changed'
grep -Fq 'Open it and drag Canis97 into Applications.' "$ROOT_DIR/website/index.html" || fail 'landing-page install copy drifted from the DMG'
grep -Fq 'set position of item "Canis97.app"' "$LAYOUT" || fail 'Canis97 icon position is not fixed'
grep -Fq 'set position of item "Applications"' "$LAYOUT" || fail 'Applications icon position is not fixed'
grep -Fq 'set background picture of viewOptions' "$LAYOUT" || fail 'Finder background is not configured'

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/canis97-dmg-contract.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT
COMMAND_LOG="$TEMP_ROOT/commands.log"
APP_PATH="$TEMP_ROOT/Canis97.app"
OUTPUT_DMG="$TEMP_ROOT/Canis97-1.2.3-arm64.dmg"
mkdir -p "$APP_PATH/Contents"

fake_hdiutil() {
  printf 'hdiutil %s\n' "$*" >> "$CANIS97_DMG_TEST_COMMAND_LOG"
  local operation="$1"
  shift
  case "$operation" in
    create|convert)
      local output=''
      while [[ "$#" -gt 0 ]]; do
        if [[ "$1" == -o ]]; then
          output="$2"
          shift 2
        else
          shift
        fi
      done
      [[ -n "$output" ]] || return 11
      mkdir -p "$(dirname "$output")"
      : > "$output"
      ;;
    attach)
      local mount_path=''
      while [[ "$#" -gt 0 ]]; do
        if [[ "$1" == -mountpoint ]]; then
          mount_path="$2"
          shift 2
        else
          shift
        fi
      done
      [[ -n "$mount_path" ]] || return 12
      mkdir -p "$mount_path"
      ;;
    detach) ;;
    *) return 13 ;;
  esac
}

fake_osascript() {
  printf 'osascript %s\n' "$*" >> "$CANIS97_DMG_TEST_COMMAND_LOG"
}

fake_setfile() {
  printf 'SetFile %s\n' "$*" >> "$CANIS97_DMG_TEST_COMMAND_LOG"
}

fake_ditto() {
  printf 'ditto %s\n' "$*" >> "$CANIS97_DMG_TEST_COMMAND_LOG"
  local source="$1"
  local destination="$2"
  if [[ -d "$source" ]]; then
    mkdir -p "$destination"
  else
    cp "$source" "$destination"
  fi
}

export -f fake_hdiutil fake_osascript fake_setfile fake_ditto
CANIS97_DMG_TEST_COMMAND_LOG="$COMMAND_LOG" \
CANIS97_DMG_WORK_DIR="$TEMP_ROOT/work" \
CANIS97_DMG_MOUNT_PATH="$TEMP_ROOT/mount" \
CANIS97_DMG_HDIUTIL_BIN=fake_hdiutil \
CANIS97_DMG_OSASCRIPT_BIN=fake_osascript \
CANIS97_DMG_SETFILE_BIN=fake_setfile \
CANIS97_DMG_DITTO_BIN=fake_ditto \
bash "$DMG_SCRIPT" "$APP_PATH" "$OUTPUT_DMG" >/dev/null

[[ -f "$OUTPUT_DMG" ]] || fail 'visual DMG builder did not produce its output'
[[ -L "$TEMP_ROOT/work/dmg-package/staging/Applications" ]] || fail 'Applications shortcut is missing'
[[ "$(readlink "$TEMP_ROOT/work/dmg-package/staging/Applications")" == /Applications ]] || fail 'Applications shortcut target changed'
grep -Fq 'hdiutil create -quiet -volname Canis97' "$COMMAND_LOG" || fail 'read-write layout image was not created'
grep -Fq 'osascript ' "$COMMAND_LOG" || fail 'Finder layout was not applied'
grep -Fq 'hdiutil convert ' "$COMMAND_LOG" || fail 'read-only compressed image was not created'

CANIS97_DMG_WORK_DIR="$TEMP_ROOT/invalid-work" \
  bash "$DMG_SCRIPT" "$APP_PATH" "$TEMP_ROOT/not-a-dmg.zip" >/dev/null 2>&1 && fail 'builder accepted a non-DMG output'

echo 'PASS: visual DMG packaging contract'
