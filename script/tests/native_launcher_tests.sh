#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE="$ROOT_DIR/script/native_single_instance_launcher.swift"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sirius-native-launcher-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-cache"
export SWIFT_MODULE_CACHE_PATH="$BUILD_DIR/swift-cache"

if [[ ! -f "$SOURCE" ]]; then
  echo "FAIL: native single-instance launcher source is missing" >&2
  exit 1
fi

xcrun swiftc -parse-as-library "$SOURCE" -framework AppKit -o "$BUILD_DIR/native-launcher"
"$BUILD_DIR/native-launcher" self-test | grep -qx 'native-launcher-tests: PASS'

if ! rg -q 'native_single_instance_launcher.swift' "$ROOT_DIR/script/build_and_run.sh"; then
  echo "FAIL: build_and_run.sh must route GUI launch through the native launcher" >&2
  exit 1
fi

if rg -q 'SIL_PGREP|SIL_TERMINATE_ALL|SIL_PID_PATH|SIL_OPEN' "$ROOT_DIR/script/build_and_run.sh"; then
  echo "FAIL: build_and_run.sh must not use shell process-table launch hooks" >&2
  exit 1
fi

echo "native-launcher-routing: PASS"
