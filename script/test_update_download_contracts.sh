#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/canis97-update-contract.XXXXXX")"
trap 'rm -rf -- "$TASK_DIR"' EXIT
xcrun swiftc -parse-as-library -swift-version 6 -module-cache-path "$TASK_DIR/module-cache" \
  "$ROOT_DIR/SiriusMac/Updates/SemanticVersion.swift" \
  "$ROOT_DIR/SiriusMac/Updates/UpdateChecker.swift" \
  "$ROOT_DIR/script/tests/update_download_contract_tests.swift" \
  -o "$TASK_DIR/update-contracts"
"$TASK_DIR/update-contracts"
