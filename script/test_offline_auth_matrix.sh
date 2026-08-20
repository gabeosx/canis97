#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/siriusmac-offline-auth.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
export CLANG_MODULE_CACHE_PATH="$TEMP_DIR/clang-cache"
export SWIFT_MODULE_CACHE_PATH="$TEMP_DIR/swift-cache"

swiftc \
  "$ROOT_DIR/SiriusMac/Authentication/ClosedAuthenticationOracle.swift" \
  "$ROOT_DIR/script/tests/OfflineAuthenticationMatrixTests.swift" \
  -o "$TEMP_DIR/offline-auth-matrix"

"$TEMP_DIR/offline-auth-matrix" "$@"
