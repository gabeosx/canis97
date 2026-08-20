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
if [[ "${SIL_BUILD_AND_RUN_SOURCE_ONLY:-0}" != "1" ]]; then
  trap cleanup_telemetry EXIT
fi

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
  single_instance_launch_locked
}

build_and_launch() {
  local mode="$1" launch_status=0
  if ! build_exact_bundle >/dev/null; then
    sil_report_invariant_stage "${SIL_BUILD_FAILURE_STAGE:-build-command-failed}" || true
    return 1
  fi
  if [[ "$mode" == "--telemetry" || "$mode" == "telemetry" ]]; then
    if ! start_authentication_telemetry; then
      sil_report_invariant_stage "${SIL_TELEMETRY_FAILURE_STAGE:-telemetry-start-failed}" || true
      return 1
    fi
  fi
  launch_after_build
  launch_status=$?
  if (( launch_status != 0 )); then
    if [[ -z "${SIL_REPORTED_INVARIANT_STAGE:-}" ]]; then
      sil_report_invariant_stage launch-wrapper-no-stage-failed || true
    fi
    return "$launch_status"
  fi

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

if [[ "${SIL_BUILD_AND_RUN_SOURCE_ONLY:-0}" == "1" ]]; then
  if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 0
  fi
  exit 0
fi

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
