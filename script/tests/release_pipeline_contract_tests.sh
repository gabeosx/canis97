#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/release.yml"
ARTIFACT_SCRIPT="$ROOT_DIR/script/create_release_artifacts.sh"
SBOM_SCRIPT="$ROOT_DIR/script/generate_release_sbom.sh"
PREFLIGHT_WORKFLOW="$ROOT_DIR/.github/workflows/release-preflight.yml"

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

require_literal 'Create or reuse the exact draft release' "$WORKFLOW"
require_literal 'Verify draft asset set before publication' "$WORKFLOW"
require_literal 'Publish the verified immutable draft' "$WORKFLOW"
require_literal 'concurrency:' "$WORKFLOW"
require_literal 'cancel-in-progress: false' "$WORKFLOW"
require_literal 'gh release create "$RELEASE_TAG" --draft' "$WORKFLOW"
require_literal 'gh release upload "$RELEASE_TAG"' "$WORKFLOW"
require_literal 'gh release download "$RELEASE_TAG"' "$WORKFLOW"
require_literal 'gh release edit "$RELEASE_TAG" --draft=false' "$WORKFLOW"
require_literal 'Canis97-$VERSION-arm64.dmg' "$WORKFLOW"
require_literal 'DeveloperIDG2CA.cer' "$WORKFLOW"
require_literal 'PBE-SHA1-3DES' "$WORKFLOW"
require_literal 'DeveloperIDG2CA.cer' "$PREFLIGHT_WORKFLOW"
require_literal 'PBE-SHA1-3DES' "$PREFLIGHT_WORKFLOW"
reject_literal 'gh release create "$RELEASE_TAG" \\' "$WORKFLOW"

draft_verify_line="$(grep -n 'Verify draft asset set before publication' "$WORKFLOW" | cut -d: -f1)"
publish_line="$(grep -n 'Publish the verified immutable draft' "$WORKFLOW" | cut -d: -f1)"
tap_update_line="$(grep -n 'Update the Homebrew tap' "$WORKFLOW" | cut -d: -f1)"
[[ "$draft_verify_line" -lt "$publish_line" && "$publish_line" -lt "$tap_update_line" ]] || fail 'publish/tap ordering is not fail-closed'

require_literal 'XPC_SERVICE_PATH=' "$ARTIFACT_SCRIPT"
require_literal 'SIGNING_IDENTITY=' "$ARTIFACT_SCRIPT"
require_literal 'NOTARY_ARCHIVE=' "$ARTIFACT_SCRIPT"
require_literal 'FINAL_ARCHIVE=' "$ARTIFACT_SCRIPT"
require_literal 'CREATE_DMG_BIN=' "$ARTIFACT_SCRIPT"
require_literal 'DMG_IDENTIFIER=' "$ARTIFACT_SCRIPT"
require_literal 'VERIFICATION_MANIFEST=' "$ARTIFACT_SCRIPT"
require_literal 'SYSPOLICY_CHECK_BIN=' "$ARTIFACT_SCRIPT"
require_literal 'distribution "$APP_PATH"' "$ARTIFACT_SCRIPT"
require_literal 'check_signed_product' "$ARTIFACT_SCRIPT"
require_literal 'write_verification_manifest' "$ARTIFACT_SCRIPT"
require_literal 'check_signed_disk_image' "$ARTIFACT_SCRIPT"
require_literal 'notarytool submit "$FINAL_ARCHIVE"' "$ARTIFACT_SCRIPT"
require_literal '--type open --context context:primary-signature' "$ARTIFACT_SCRIPT"
require_literal 'Lottie' "$SBOM_SCRIPT"
require_literal '4.6.1' "$SBOM_SCRIPT"

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/canis97-release-contract.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT
COMMAND_LOG="$TEMP_ROOT/commands.log"

fake_log() {
  printf '%s\n' "$*" >> "$RELEASE_COMMAND_LOG"
}

fake_xcodebuild() {
  fake_log "xcodebuild $*"
  local next_is_archive=0
  local archive_path=""
  for argument in "$@"; do
    if [[ "$next_is_archive" == 1 ]]; then
      archive_path="$argument"
      break
    fi
    [[ "$argument" == '-archivePath' ]] && next_is_archive=1
  done
  mkdir -p "$archive_path/Products/Applications/Canis97.app/Contents/XPCServices/Canis97MotionConverter.xpc"
}

fake_codesign() {
  fake_log "codesign $*"
  local target="${!#}"
  if [[ "$*" == *'--force'* && "$target" == *Canis97MotionConverter.xpc ]]; then
    [[ "$*" == *'--entitlements '*'/Canis97MotionConverter/Canis97MotionConverter.entitlements'* ]] || {
      echo 'XPC signing must explicitly retain the sandbox entitlement' >&2
      return 1
    }
  fi
  if [[ "$*" == *'--entitlements :-'* ]]; then
    if [[ "$target" == *Canis97MotionConverter.xpc ]]; then
      printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/></dict></plist>'
    else
      : # codesign emits no bytes when a signature has no entitlements.
    fi
  elif [[ "$*" == *'--verbose=4'* ]]; then
    if [[ "$target" == *Canis97MotionConverter.xpc ]]; then
      printf '%s\n' 'Identifier=com.canis97.player.motion-converter' 'TeamIdentifier=TEAM12345' 'Authority=Developer ID Application: Example' 'Runtime Version=26.0.0' 'Timestamp=2026-08-30'
    elif [[ "$target" == *.dmg ]]; then
      printf '%s\n' 'Identifier=com.canis97.player.dmg' 'TeamIdentifier=TEAM12345' 'Authority=Developer ID Application: Example' 'Timestamp=2026-08-30'
    else
      printf '%s\n' 'Identifier=com.canis97.player' 'TeamIdentifier=TEAM12345' 'Authority=Developer ID Application: Example' 'Runtime Version=26.0.0' 'Timestamp=2026-08-30'
    fi
  fi
}

fake_xcrun() {
  fake_log "xcrun $*"
}

fake_spctl() {
  fake_log "spctl $*"
}

fake_syspolicy_check() {
  fake_log "syspolicy_check $*"
}

fake_rejecting_policy() {
  fake_log "syspolicy_check rejected $*"
  return 1
}

fake_ditto() {
  fake_log "ditto $*"
  local target="${!#}"
  mkdir -p "$(dirname "$target")"
  : > "$target"
}

fake_create_dmg() {
  fake_log "create_visual_dmg $*"
  local target="${!#}"
  mkdir -p "$(dirname "$target")"
  : > "$target"
}

export -f fake_log fake_xcodebuild fake_codesign fake_xcrun fake_spctl fake_syspolicy_check fake_rejecting_policy fake_ditto fake_create_dmg
RELEASE_COMMAND_LOG="$COMMAND_LOG" \
BUILD_NUMBER=1 \
GITHUB_REPOSITORY=gabeosx/canis97 \
APPLE_TEAM_ID=TEAM12345 \
APPLE_ID=release@example.invalid \
APPLE_APP_SPECIFIC_PASSWORD=fake-password \
RELEASE_OUTPUT_DIR="$TEMP_ROOT/output" \
RELEASE_WORK_DIR="$TEMP_ROOT/work" \
RELEASE_XCODEBUILD_BIN=fake_xcodebuild \
RELEASE_CODESIGN_BIN=fake_codesign \
RELEASE_XCRUN_BIN=fake_xcrun \
RELEASE_SPCTL_BIN=fake_spctl \
RELEASE_SYSPOLICY_CHECK_BIN=fake_syspolicy_check \
RELEASE_DITTO_BIN=fake_ditto \
RELEASE_CREATE_DMG_BIN=fake_create_dmg \
bash "$ARTIFACT_SCRIPT" 1.2.3 >/dev/null

test -f "$TEMP_ROOT/work/Canis97-notary-submission.zip" || fail 'fake notary archive missing'
test -f "$TEMP_ROOT/output/Canis97-1.2.3-arm64.dmg" || fail 'fake final DMG missing'
test -f "$TEMP_ROOT/output/Canis97-1.2.3.verification.json" || fail 'verification manifest missing'
grep -Fq 'PackageName: Lottie' "$TEMP_ROOT/output/Canis97-1.2.3.spdx" || fail 'SBOM omitted Lottie identity'
grep -Fq 'PackageVersion: 4.6.1' "$TEMP_ROOT/output/Canis97-1.2.3.spdx" || fail 'SBOM changed Lottie version'
grep -Fq 'PackageName: SiriusXMClient' "$TEMP_ROOT/output/Canis97-1.2.3.spdx" || fail 'SBOM omitted local client identity'
grep -Fq 'PackageName: Canis97MotionSafety' "$TEMP_ROOT/output/Canis97-1.2.3.spdx" || fail 'SBOM omitted local motion identity'

xpc_sign_line="$(grep -n -- '--sign Developer ID Application .*Canis97MotionConverter.xpc' "$COMMAND_LOG" | head -1 | cut -d: -f1)"
app_sign_line="$(grep -n -- '--sign Developer ID Application .*Canis97.app$' "$COMMAND_LOG" | head -1 | cut -d: -f1)"
notary_line="$(grep -n 'notarytool submit' "$COMMAND_LOG" | head -1 | cut -d: -f1)"
final_archive_line="$(grep -n 'create_visual_dmg .*Canis97-1.2.3-arm64.dmg' "$COMMAND_LOG" | head -1 | cut -d: -f1)"
[[ -n "$xpc_sign_line" && -n "$app_sign_line" && "$xpc_sign_line" -lt "$app_sign_line" ]] || fail 'nested service must sign before app'
[[ -n "$notary_line" && -n "$final_archive_line" && "$notary_line" -lt "$final_archive_line" ]] || fail 'final archive must follow notarization'
test "$(grep -Fc 'notarytool submit' "$COMMAND_LOG")" -eq 2 || fail 'app and final DMG must both be submitted for notarization'
grep -Fq 'spctl --assess --type open --context context:primary-signature' "$COMMAND_LOG" || fail 'DMG Gatekeeper assessment was skipped'
grep -Fq 'syspolicy_check distribution' "$COMMAND_LOG" || fail 'distribution policy gate was skipped'
"$ROOT_DIR/script/generate_release_sbom.sh" invalid "$TEMP_ROOT/invalid.spdx" >/dev/null 2>&1 && fail 'SBOM accepted invalid invocation'

if RELEASE_COMMAND_LOG="$COMMAND_LOG" \
  BUILD_NUMBER=2 \
  GITHUB_REPOSITORY=gabeosx/canis97 \
  APPLE_TEAM_ID=TEAM12345 \
  APPLE_ID=release@example.invalid \
  APPLE_APP_SPECIFIC_PASSWORD=fake-password \
  RELEASE_OUTPUT_DIR="$TEMP_ROOT/rejected-output" \
  RELEASE_WORK_DIR="$TEMP_ROOT/rejected-work" \
  RELEASE_XCODEBUILD_BIN=fake_xcodebuild \
  RELEASE_CODESIGN_BIN=fake_codesign \
  RELEASE_XCRUN_BIN=fake_xcrun \
  RELEASE_SPCTL_BIN=fake_spctl \
  RELEASE_SYSPOLICY_CHECK_BIN=fake_rejecting_policy \
  RELEASE_DITTO_BIN=fake_ditto \
  RELEASE_CREATE_DMG_BIN=fake_create_dmg \
  bash "$ARTIFACT_SCRIPT" 1.2.4 >/dev/null 2>&1; then
  fail 'policy rejection unexpectedly produced a releasable artifact'
fi
test ! -e "$TEMP_ROOT/rejected-output/Canis97-1.2.4-arm64.dmg" || fail 'policy rejection wrote final DMG'

echo "PASS: draft-first workflow and final-artifact contract"
