#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d /private/tmp/canis97-metadata-artwork.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
export CLANG_MODULE_CACHE_PATH="$scratch/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$scratch/swift"

# This is a pure fixture executable. It contains no app entry point, player,
# authentication composition, or test host, and never opens a network session.
swift build --jobs 4 --package-path "$root/Packages/SiriusXMClient" --scratch-path "$scratch/package"
bin_path="$(swift build --package-path "$root/Packages/SiriusXMClient" --scratch-path "$scratch/package" --show-bin-path)"
if [[ -f "$bin_path/SiriusXMClient.o" ]]; then
  module_path="$bin_path"
  objects=("$bin_path/SiriusXMClient.o")
else
  module_path="$bin_path/Modules"
  objects=("$bin_path"/SiriusXMClient.build/*.swift.o)
fi
swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos26.0" -I "$module_path" \
  "${objects[@]}" \
  "$root/SiriusMac/Metadata/MetadataPresentationModel.swift" \
  "$root/script/tests/metadata_artwork_tests.swift" \
  -o "$scratch/metadata-artwork-tests"
"$scratch/metadata-artwork-tests"
