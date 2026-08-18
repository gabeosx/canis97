#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="SiriusMac"
DEVELOPER_DIR_PATH="/Applications/Xcode.app/Contents/Developer"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/SiriusMac.xcodeproj"
DERIVED_DATA_PATH="/tmp/sirius-mac-derived-data"
CLANG_CACHE_PATH="/tmp/sirius-mac-clang-cache"
SWIFTPM_CACHE_PATH="/tmp/sirius-mac-swiftpm-cache"
APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

if [[ "$MODE" != "--build-only" && "$MODE" != "build-only" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

DEVELOPER_DIR="$DEVELOPER_DIR_PATH" \
CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_PATH" \
SWIFTPM_MODULECACHE_OVERRIDE="$SWIFTPM_CACHE_PATH" \
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$APP_NAME" \
    -configuration Debug \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    build

[[ -x "$APP_BINARY" ]]
echo "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --build-only|build-only)
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate 'process == "SiriusMac"'
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate '(subsystem == "com.siriusmac.player" AND category == "authentication") OR (subsystem == "com.siriusmac.client" AND category == "diagnostics")'
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
