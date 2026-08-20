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
source "$ROOT_DIR/script/lib/single_instance_launcher.sh"

export SIL_APP_NAME="$APP_NAME"
export SIL_APP_BUNDLE="$APP_BUNDLE"
export SIL_APP_BINARY="$APP_BINARY"
export SIL_LOCK_PATH="${SIL_LOCK_PATH:-/tmp/sirius-mac-launch.lock}"
export SIL_PGREP="${SIL_PGREP:-/usr/bin/pgrep}"
export SIL_TERMINATE_ALL="${SIL_TERMINATE_ALL:-/usr/bin/pkill}"
export SIL_PID_PATH="${SIL_PID_PATH:-$ROOT_DIR/script/lib/resolve_process_binary.sh}"
export SIL_OPEN="${SIL_OPEN:-/usr/bin/open}"
export SIL_SLEEP="${SIL_SLEEP:-/bin/sleep}"

TELEMETRY_PID=""

cleanup_telemetry() {
  if [[ -n "$TELEMETRY_PID" ]]; then
    kill "$TELEMETRY_PID" >/dev/null 2>&1 || true
    TELEMETRY_PID=""
  fi
}
trap cleanup_telemetry EXIT

build_exact_bundle() {
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
}

start_authentication_telemetry() {
  /usr/bin/log stream --info --style compact \
    --predicate '(subsystem == "com.siriusmac.player" AND category == "authentication") OR (subsystem == "com.siriusmac.client" AND category == "diagnostics")' &
  TELEMETRY_PID=$!
  if ! kill -0 "$TELEMETRY_PID" 2>/dev/null; then
    echo "authentication telemetry stream did not start" >&2
    return 1
  fi
}

launch_after_build() {
  single_instance_launch_locked
}

build_and_launch() {
  local mode="$1"
  build_exact_bundle
  if [[ "$mode" == "--telemetry" || "$mode" == "telemetry" ]]; then
    start_authentication_telemetry
  fi
  launch_after_build

  case "$mode" in
    --debug|debug)
      lldb -p "$(sil_pid_list | awk 'NF { print; exit }')"
      ;;
    --logs|logs)
      /usr/bin/log stream --info --style compact --predicate 'process == "SiriusMac"'
      ;;
    --telemetry|telemetry)
      wait "$TELEMETRY_PID"
      ;;
    --verify|verify)
      echo "verified exact SiriusMac launch"
      ;;
    run)
      ;;
  esac
}

case "$MODE" in
  --build-only|build-only)
    single_instance_build_only build_exact_bundle
    ;;
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
    single_instance_with_lock build_and_launch "$MODE"
    ;;
  *)
    echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
