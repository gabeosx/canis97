#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="SiriusMac"
APP_BUNDLE_IDENTIFIER="com.siriusmac.player"
DEVELOPER_DIR_PATH="/Applications/Xcode.app/Contents/Developer"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/SiriusMac.xcodeproj"
DERIVED_DATA_PATH="/tmp/sirius-mac-derived-data"
CLANG_CACHE_PATH="/tmp/sirius-mac-clang-cache"
SWIFTPM_CACHE_PATH="/tmp/sirius-mac-swiftpm-cache"
APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
NATIVE_LAUNCHER_SOURCE="$ROOT_DIR/script/native_single_instance_launcher.swift"
NATIVE_LAUNCHER_BINARY="${SIL_NATIVE_LAUNCHER_BINARY:-/tmp/sirius-mac-native-launcher}"
LAUNCH_LOCK_PATH="${SIL_LOCK_PATH:-/tmp/sirius-mac-launch.lock}"
export SIL_XCODEBUILD="${SIL_XCODEBUILD:-xcodebuild}"
export SIL_LOG="${SIL_LOG:-/usr/bin/log}"
export SIL_KILL="${SIL_KILL:-/bin/kill}"

TELEMETRY_PID=""

cleanup_telemetry() {
  if [[ -n "$TELEMETRY_PID" ]]; then
    "$SIL_KILL" "$TELEMETRY_PID" >/dev/null 2>&1 || true
    TELEMETRY_PID=""
  fi
}
cleanup_launcher() {
  cleanup_telemetry
  rmdir "$LAUNCH_LOCK_PATH" 2>/dev/null || true
}
if [[ "${SIL_BUILD_AND_RUN_SOURCE_ONLY:-0}" != "1" ]]; then
  trap cleanup_launcher EXIT
fi

report_process_stage() {
  printf 'process-stage: %s\n' "$1" >&2
}

acquire_launch_lock() {
  if ! mkdir "$LAUNCH_LOCK_PATH" 2>/dev/null; then
    report_process_stage lock-acquisition-failed
    return 1
  fi
}

build_native_launcher() {
  if ! CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_PATH" \
    SWIFT_MODULE_CACHE_PATH="$SWIFTPM_CACHE_PATH" \
    xcrun swiftc -parse-as-library "$NATIVE_LAUNCHER_SOURCE" -framework AppKit -o "$NATIVE_LAUNCHER_BINARY"; then
    report_process_stage native-launcher-build-failed
    return 1
  fi
}

build_exact_bundle() {
  SIL_BUILD_FAILURE_STAGE=""
  if ! DEVELOPER_DIR="$DEVELOPER_DIR_PATH" \
    CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_PATH" \
    SWIFTPM_MODULECACHE_OVERRIDE="$SWIFTPM_CACHE_PATH" \
    "$SIL_XCODEBUILD" \
      -project "$PROJECT_PATH" \
      -scheme "$APP_NAME" \
      -configuration Debug \
      -destination "platform=macOS" \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      CODE_SIGNING_ALLOWED=NO \
      build; then
    SIL_BUILD_FAILURE_STAGE="build-command-failed"
    return 1
  fi

  if [[ ! -x "$APP_BINARY" ]]; then
    SIL_BUILD_FAILURE_STAGE="build-output-missing"
    return 1
  fi
  echo "$APP_BUNDLE"
}

start_authentication_telemetry() {
  SIL_TELEMETRY_FAILURE_STAGE=""
  "$SIL_LOG" stream --info --style compact \
    --predicate '(subsystem == "com.siriusmac.player" AND category == "authentication") OR (subsystem == "com.siriusmac.client" AND category == "diagnostics")' &
  TELEMETRY_PID=$!
  if ! "$SIL_KILL" -0 "$TELEMETRY_PID" 2>/dev/null; then
    SIL_TELEMETRY_FAILURE_STAGE="telemetry-start-failed"
    echo "authentication telemetry stream did not start" >&2
    return 1
  fi
}

launch_after_build() {
  "$NATIVE_LAUNCHER_BINARY" launch "$APP_BUNDLE" "$APP_BUNDLE_IDENTIFIER" "$APP_BINARY"
}

build_and_launch() {
  local mode="$1" launch_status=0
  if ! build_exact_bundle >/dev/null; then
    report_process_stage "${SIL_BUILD_FAILURE_STAGE:-build-command-failed}"
    return 1
  fi
  if ! build_native_launcher; then
    return 1
  fi
  if [[ "$mode" == "--telemetry" || "$mode" == "telemetry" ]]; then
    if ! start_authentication_telemetry; then
      report_process_stage "${SIL_TELEMETRY_FAILURE_STAGE:-telemetry-start-failed}"
      return 1
    fi
  fi
  local launched_pid=""
  launched_pid="$(launch_after_build)" || launch_status=$?
  if (( launch_status != 0 )); then
    return "$launch_status"
  fi

  case "$mode" in
    --debug|debug)
      lldb -p "$launched_pid"
      ;;
    --logs|logs)
      /usr/bin/log stream --info --style compact --predicate 'process == "SiriusMac"'
      ;;
    --telemetry|telemetry)
      wait "$TELEMETRY_PID"
      ;;
    --verify|verify)
      echo "verified exact SiriusMac launch (pid $launched_pid)"
      ;;
    run)
      ;;
  esac
}

if [[ "${SIL_BUILD_AND_RUN_SOURCE_ONLY:-0}" == "1" ]]; then
  if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 0
  fi
  exit 0
fi

case "$MODE" in
  --build-only|build-only)
    build_exact_bundle
    build_native_launcher
    ;;
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
    acquire_launch_lock
    build_and_launch "$MODE"
    ;;
  *)
    echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
