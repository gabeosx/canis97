#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="AuthFeasibilityHarness"
BUNDLE_ID="com.siriusmac.auth-feasibility-harness"
MIN_SYSTEM_VERSION="26.0"
DEVELOPER_DIR_PATH="/Applications/Xcode.app/Contents/Developer"
CLANG_CACHE_PATH="/tmp/sirius-auth-clang-cache"
SWIFTPM_CACHE_PATH="/tmp/sirius-auth-swiftpm-cache"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/Spikes/AuthenticationFeasibility"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
PROBE_OUTPUT="$ROOT_DIR/.planning/phases/00-authentication-feasibility-gate/00-BROWSER-PROBE.md"

if [[ "$MODE" != "--build-only" && "$MODE" != "build-only" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_PATH" \
SWIFTPM_MODULECACHE_OVERRIDE="$SWIFTPM_CACHE_PATH" \
DEVELOPER_DIR="$DEVELOPER_DIR_PATH" \
  swift build --package-path "$PACKAGE_DIR" --product "$APP_NAME"
BUILD_BINARY="$(CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_PATH" SWIFTPM_MODULECACHE_OVERRIDE="$SWIFTPM_CACHE_PATH" DEVELOPER_DIR="$DEVELOPER_DIR_PATH" swift build --package-path "$PACKAGE_DIR" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

[[ -x "$APP_BINARY" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")" == "$APP_NAME" ]]
echo "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE" --args --live-browser --output "$PROBE_OUTPUT"
}

case "$MODE" in
  --build-only|build-only)
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY" --live-browser --output "$PROBE_OUTPUT"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
