#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVELOPER_DIR_PATH="/Applications/Xcode.app/Contents/Developer"

if [[ "${1:-}" != "--owner-confirmed" || "${2:-}" != "--test-launch-safety-reviewed" || "$#" -ne 2 ]]; then
  echo "usage: $0 --owner-confirmed --test-launch-safety-reviewed" >&2
  echo "Requires separate owner confirmation that launched-test safety review has passed." >&2
  echo "Runs unit-only offline verification, then launches one owner-confirmed telemetry session." >&2
  exit 2
fi

cd "$ROOT_DIR"

DEVELOPER_DIR="$DEVELOPER_DIR_PATH" swift test --package-path Packages/SiriusXMClient
DEVELOPER_DIR="$DEVELOPER_DIR_PATH" xcodebuild test \
  -project SiriusMac.xcodeproj \
  -scheme Canis97 \
  -destination 'platform=macOS' \
  -only-testing:Canis97Tests \
  -parallel-testing-enabled NO

# `exec` replaces this shell, so one confirmed invocation can launch telemetry once only.
exec "$ROOT_DIR/script/build_and_run.sh" --telemetry
