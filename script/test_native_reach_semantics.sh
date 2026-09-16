#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d /private/tmp/canis97-native-reach-check.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT

# Foundation-only executable: no XCTest host, NSApplication, credentials,
# network transport, widget process, or audio runtime.
swiftc -O -warnings-as-errors -strict-concurrency=complete \
  -module-cache-path "$scratch/cache" \
  "$repo_root/SiriusMac/NativeReach/NativeReachSemantic.swift" \
  "$repo_root/script/tests/native_reach_semantic_tests.swift" \
  -o "$scratch/check"
"$scratch/check"
