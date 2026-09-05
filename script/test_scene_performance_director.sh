#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d /private/tmp/canis97-director-check.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
# Standalone Foundation CLI. No XCTest, test host, NSApplication or provider.
swiftc -O -warnings-as-errors -strict-concurrency=complete \
  -module-cache-path "$scratch/cache" \
  "$repo_root/Packages/Canis97MotionSafety/Sources/Canis97MotionSafety/ScenePerformanceDirector.swift" \
  "$repo_root/script/tests/scene_performance_director_tests.swift" \
  -o "$scratch/check"
"$scratch/check"
