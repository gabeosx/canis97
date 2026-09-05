#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d /private/tmp/canis97-atlas-check.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
# Offscreen CALayer primitive CLI, without an NSApplication or app/test host.
swiftc -O -swift-version 6 -warnings-as-errors -module-cache-path "$scratch/cache" \
  "$repo_root/script/tests/sprite_atlas_geometry_tests.swift" -parse-as-library -o "$scratch/check"
"$scratch/check"
