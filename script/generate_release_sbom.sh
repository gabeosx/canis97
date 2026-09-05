#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"
OUTPUT_PATH="${2:-}"
ARCHIVE_PATH="${RELEASE_ARCHIVE_PATH:-}"
RESOLVED_PATH="$ROOT_DIR/SiriusMac.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

if [[ -z "$VERSION" || -z "$OUTPUT_PATH" || ! -f "$ARCHIVE_PATH" ]]; then
  echo "usage: RELEASE_ARCHIVE_PATH=artifact.dmg $0 VERSION OUTPUT.spdx" >&2
  exit 2
fi
if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "VERSION must be MAJOR.MINOR.PATCH" >&2
  exit 2
fi
if [[ ! "${GITHUB_REPOSITORY:-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "GITHUB_REPOSITORY must be OWNER/REPOSITORY" >&2
  exit 2
fi

ARCHIVE_SHA="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
CREATED="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
DOCUMENT_NAMESPACE="https://github.com/${GITHUB_REPOSITORY}/releases/tag/v${VERSION}/sbom"

{
  printf 'SPDXVersion: SPDX-2.3\n'
  printf 'DataLicense: CC0-1.0\n'
  printf 'SPDXID: SPDXRef-DOCUMENT\n'
  printf 'DocumentName: Canis97-%s\n' "$VERSION"
  printf 'DocumentNamespace: %s\n' "$DOCUMENT_NAMESPACE"
  printf 'Creator: Tool: Canis97-release-workflow\n'
  printf 'Created: %s\n\n' "$CREATED"
  printf 'PackageName: Canis97\n'
  printf 'SPDXID: SPDXRef-Package-Canis97\n'
  printf 'PackageVersion: %s\n' "$VERSION"
  printf 'PackageDownloadLocation: https://github.com/%s/releases/download/v%s/%s\n' \
    "$GITHUB_REPOSITORY" "$VERSION" "$(basename "$ARCHIVE_PATH")"
  printf 'FilesAnalyzed: false\n'
  printf 'PackageChecksum: SHA256: %s\n' "$ARCHIVE_SHA"
  printf 'PackageSupplier: NOASSERTION\n'
  printf 'PackageCopyrightText: NOASSERTION\n\n'
  printf 'Relationship: SPDXRef-DOCUMENT DESCRIBES SPDXRef-Package-Canis97\n'
} > "$OUTPUT_PATH"

/usr/bin/ruby -rjson -e '
  resolved_path, output_path = ARGV
  pins = JSON.parse(File.read(resolved_path)).fetch("pins", [])
  lottie = pins.find { |pin| pin.fetch("identity") == "lottie-ios" }
  abort "Lottie dependency missing" unless lottie
  abort "Lottie must remain exactly 4.6.1" unless lottie.fetch("state").fetch("version") == "4.6.1"
  File.open(output_path, "a") do |output|
    pins.each do |pin|
      identity = pin.fetch("identity")
      state = pin.fetch("state", {})
      version = state["version"] || state["revision"] || "NOASSERTION"
      name = identity == "lottie-ios" ? "Lottie" : identity
      spdx_id = "SPDXRef-Package-" + identity.gsub(/[^A-Za-z0-9.-]/, "-")
      output.puts
      output.puts "PackageName: #{name}"
      output.puts "SPDXID: #{spdx_id}"
      output.puts "PackageVersion: #{version}"
      output.puts "PackageDownloadLocation: #{pin["location"] || "NOASSERTION"}"
      output.puts "FilesAnalyzed: false"
      output.puts "PackageSupplier: NOASSERTION"
      output.puts "PackageCopyrightText: NOASSERTION"
      output.puts
      output.puts "Relationship: SPDXRef-Package-Canis97 DEPENDS_ON #{spdx_id}"
    end
    %w[SiriusXMClient Canis97MotionSafety].each do |identity|
      spdx_id = "SPDXRef-Package-#{identity}"
      output.puts
      output.puts "PackageName: #{identity}"
      output.puts "SPDXID: #{spdx_id}"
      output.puts "PackageVersion: NOASSERTION"
      output.puts "PackageDownloadLocation: NOASSERTION"
      output.puts "FilesAnalyzed: false"
      output.puts "PackageSupplier: NOASSERTION"
      output.puts "PackageCopyrightText: NOASSERTION"
      output.puts
      output.puts "Relationship: SPDXRef-Package-Canis97 DEPENDS_ON #{spdx_id}"
    end
  end
' "$RESOLVED_PATH" "$OUTPUT_PATH"
