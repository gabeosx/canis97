#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/release.yml"
PREFLIGHT="$ROOT_DIR/.github/workflows/release-preflight.yml"
ARTIFACT_SCRIPT="$ROOT_DIR/script/create_release_artifacts.sh"
CASK_SCRIPT="$ROOT_DIR/script/render_homebrew_cask.sh"
LANDING_SCRIPT="$ROOT_DIR/website/app.js"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_literal() {
  local needle="$1"
  local file="$2"
  grep -Fq -- "$needle" "$file" || fail "expected $file to contain: $needle"
}

reject_literal() {
  local needle="$1"
  local file="$2"
  ! grep -Fq -- "$needle" "$file" || fail "expected $file to omit: $needle"
}

require_literal 'Canis97-$VERSION-arm64.dmg' "$WORKFLOW"
require_literal 'DeveloperIDG2CA.cer' "$WORKFLOW"
require_literal 'PBE-SHA1-3DES' "$WORKFLOW"
require_literal 'DeveloperIDG2CA.cer' "$PREFLIGHT"
require_literal 'PBE-SHA1-3DES' "$PREFLIGHT"
require_literal 'FINAL_ARCHIVE="$OUTPUT_DIR/Canis97-$VERSION-arm64.dmg"' "$ARTIFACT_SCRIPT"
require_literal 'create_visual_dmg.sh' "$ARTIFACT_SCRIPT"
require_literal '--identifier "$DMG_IDENTIFIER"' "$ARTIFACT_SCRIPT"
require_literal 'notarytool submit "$FINAL_ARCHIVE"' "$ARTIFACT_SCRIPT"
require_literal 'stapler staple "$FINAL_ARCHIVE"' "$ARTIFACT_SCRIPT"
require_literal '--type open --context context:primary-signature' "$ARTIFACT_SCRIPT"
require_literal 'Canis97-#{version}-arm64.dmg' "$CASK_SCRIPT"
require_literal 'arm64\.dmg$' "$LANDING_SCRIPT"

for file in "$WORKFLOW" "$ARTIFACT_SCRIPT" "$CASK_SCRIPT" "$LANDING_SCRIPT"; do
  reject_literal 'arm64.zip' "$file"
done

echo 'PASS: DMG release integration contract'
