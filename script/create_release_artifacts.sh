#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
OUTPUT_DIR="${RELEASE_OUTPUT_DIR:-$ROOT_DIR/build/release}"
WORK_DIR="${RELEASE_WORK_DIR:-$ROOT_DIR/build/release-work}"
XCODEBUILD_BIN="${RELEASE_XCODEBUILD_BIN:-xcodebuild}"
CODESIGN_BIN="${RELEASE_CODESIGN_BIN:-codesign}"
XCRUN_BIN="${RELEASE_XCRUN_BIN:-xcrun}"
SPCTL_BIN="${RELEASE_SPCTL_BIN:-spctl}"
SYSPOLICY_CHECK_BIN="${RELEASE_SYSPOLICY_CHECK_BIN:-syspolicy_check}"
DITTO_BIN="${RELEASE_DITTO_BIN:-/usr/bin/ditto}"
CREATE_DMG_BIN="${RELEASE_CREATE_DMG_BIN:-$ROOT_DIR/script/create_visual_dmg.sh}"
SHASUM_BIN="${RELEASE_SHASUM_BIN:-shasum}"
RUBY_BIN="${RELEASE_RUBY_BIN:-/usr/bin/ruby}"
ARCHIVE_PATH="$WORK_DIR/Canis97.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/Canis97.app"
XPC_SERVICE_PATH="$APP_PATH/Contents/XPCServices/Canis97MotionConverter.xpc"
NOTARY_ARCHIVE="$WORK_DIR/Canis97-notary-submission.zip"
FINAL_ARCHIVE="$OUTPUT_DIR/Canis97-$VERSION-arm64.dmg"
DMG_IDENTIFIER='com.canis97.player.dmg'
CHECKSUMS_PATH="$OUTPUT_DIR/SHA256SUMS"
SBOM_PATH="$OUTPUT_DIR/Canis97-$VERSION.spdx"
VERIFICATION_MANIFEST="$OUTPUT_DIR/Canis97-$VERSION.verification.json"

fail() {
  echo "release artifact error: $*" >&2
  exit 1
}

require_absent_output() {
  local candidate="$1"
  [[ ! -e "$candidate" ]] || fail "refusing to replace existing output: $candidate"
}

check_entitlements() {
  local product_path="$1"
  local expected_json="$2"
  local actual_json entitlement_plist

  entitlement_plist="$("$CODESIGN_BIN" -d --entitlements :- "$product_path" 2>/dev/null)" || \
    fail "could not inspect entitlements for $product_path"
  if [[ -z "$entitlement_plist" ]]; then
    actual_json='{}'
  else
    actual_json="$(/usr/bin/plutil -convert json -o - - <<<"$entitlement_plist")" || \
      fail "could not decode entitlements for $product_path"
  fi
  "$RUBY_BIN" -rjson -e '
    actual = JSON.parse(STDIN.read)
    expected = JSON.parse(ARGV.fetch(0))
    abort "unexpected entitlements" unless actual == expected
  ' "$expected_json" <<<"$actual_json" || fail "unexpected entitlement on $product_path"
}

check_signed_product() {
  local product_path="$1"
  local expected_identifier="$2"
  local expected_entitlements="$3"
  local signature_info

  "$CODESIGN_BIN" --verify --strict --verbose=4 "$product_path"
  signature_info="$($CODESIGN_BIN -d --verbose=4 "$product_path" 2>&1)"
  grep -Fq "Identifier=$expected_identifier" <<<"$signature_info" || fail "unexpected identifier for $product_path"
  grep -Fq "TeamIdentifier=$APPLE_TEAM_ID" <<<"$signature_info" || fail "unexpected team for $product_path"
  grep -Fq 'Authority=Developer ID Application:' <<<"$signature_info" || fail "missing Developer ID signature for $product_path"
  grep -Fq 'Runtime Version=' <<<"$signature_info" || fail "missing hardened runtime for $product_path"
  grep -Fq 'Timestamp=' <<<"$signature_info" || fail "missing secure timestamp for $product_path"
  check_entitlements "$product_path" "$expected_entitlements"
}

check_signed_disk_image() {
  local disk_image_path="$1"
  local signature_info

  "$CODESIGN_BIN" --verify --strict --verbose=4 "$disk_image_path"
  signature_info="$($CODESIGN_BIN -d --verbose=4 "$disk_image_path" 2>&1)"
  grep -Fq "Identifier=$DMG_IDENTIFIER" <<<"$signature_info" || fail "unexpected identifier for $disk_image_path"
  grep -Fq "TeamIdentifier=$APPLE_TEAM_ID" <<<"$signature_info" || fail "unexpected team for $disk_image_path"
  grep -Fq 'Authority=Developer ID Application:' <<<"$signature_info" || fail "missing Developer ID signature for $disk_image_path"
  grep -Fq 'Timestamp=' <<<"$signature_info" || fail "missing secure timestamp for $disk_image_path"
}

write_verification_manifest() {
  local archive_sha sbom_sha checksums_sha
  archive_sha="$($SHASUM_BIN -a 256 "$FINAL_ARCHIVE" | awk '{print $1}')"
  sbom_sha="$($SHASUM_BIN -a 256 "$SBOM_PATH" | awk '{print $1}')"
  checksums_sha="$($SHASUM_BIN -a 256 "$CHECKSUMS_PATH" | awk '{print $1}')"

  "$RUBY_BIN" -rjson -e '
    version, archive, archive_sha, sbom, sbom_sha, checksums, checksums_sha, output = ARGV
    payload = {
      schema_version: 1,
      version: version,
      final_archive: File.basename(archive),
      final_archive_sha256: archive_sha,
      sbom: File.basename(sbom),
      sbom_sha256: sbom_sha,
      checksums: File.basename(checksums),
      checksums_sha256: checksums_sha,
      verification: {
        nested_signing: "passed",
        hardened_runtime: "passed",
        secure_timestamp: "passed",
        notarization: "accepted",
        stapling: "passed",
        codesign: "passed",
        spctl: "passed",
        syspolicy_check_distribution: "passed",
        dmg_layout: "passed",
        dmg_signing: "passed",
        dmg_notarization: "accepted",
        dmg_stapling: "passed",
        dmg_gatekeeper: "passed"
      }
    }
    File.write(output, JSON.pretty_generate(payload) + "\n")
  ' "$VERSION" "$FINAL_ARCHIVE" "$archive_sha" "$SBOM_PATH" "$sbom_sha" "$CHECKSUMS_PATH" "$checksums_sha" "$VERIFICATION_MANIFEST"
}

if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "usage: $0 MAJOR.MINOR.PATCH" >&2
  exit 2
fi
if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "BUILD_NUMBER must be a positive integer" >&2
  exit 2
fi
if [[ ! "$GITHUB_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "GITHUB_REPOSITORY must be OWNER/REPOSITORY" >&2
  exit 2
fi
for required_name in APPLE_TEAM_ID APPLE_ID APPLE_APP_SPECIFIC_PASSWORD; do
  [[ -n "${!required_name:-}" ]] || { echo "$required_name is required" >&2; exit 2; }
done
for output_path in "$FINAL_ARCHIVE" "$CHECKSUMS_PATH" "$SBOM_PATH" "$VERIFICATION_MANIFEST"; do
  require_absent_output "$output_path"
done

mkdir -p "$OUTPUT_DIR" "$WORK_DIR"

"$XCODEBUILD_BIN" archive \
  -project "$ROOT_DIR/SiriusMac.xcodeproj" \
  -scheme Canis97 \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$WORK_DIR/DerivedData" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CANIS97_GITHUB_REPOSITORY="$GITHUB_REPOSITORY" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  "CODE_SIGN_IDENTITY=$SIGNING_IDENTITY" \
  'OTHER_CODE_SIGN_FLAGS=--timestamp' \
  ENABLE_HARDENED_RUNTIME=YES

[[ -d "$APP_PATH" ]] || fail "archive did not contain Canis97.app"
[[ -d "$XPC_SERVICE_PATH" ]] || fail "archive did not contain Canis97MotionConverter.xpc"

# Sign nested executable code before its containing app, then verify both without
# --deep so each trust boundary is independently checked.
"$CODESIGN_BIN" --force --options runtime --timestamp \
  --entitlements "$ROOT_DIR/Canis97MotionConverter/Canis97MotionConverter.entitlements" \
  --sign "$SIGNING_IDENTITY" "$XPC_SERVICE_PATH"
check_signed_product "$XPC_SERVICE_PATH" 'com.canis97.player.motion-converter' '{"com.apple.security.app-sandbox":true}'
"$CODESIGN_BIN" --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_PATH"
check_signed_product "$APP_PATH" 'com.canis97.player' '{}'

"$DITTO_BIN" -c -k --keepParent "$APP_PATH" "$NOTARY_ARCHIVE"
[[ -f "$NOTARY_ARCHIVE" ]] || fail "notarization submission archive was not created"
"$XCRUN_BIN" notarytool submit "$NOTARY_ARCHIVE" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --wait

"$XCRUN_BIN" stapler staple "$APP_PATH"
"$XCRUN_BIN" stapler validate "$APP_PATH"
check_signed_product "$XPC_SERVICE_PATH" 'com.canis97.player.motion-converter' '{"com.apple.security.app-sandbox":true}'
check_signed_product "$APP_PATH" 'com.canis97.player' '{}'
"$SPCTL_BIN" --assess --type execute --verbose=2 "$APP_PATH"
"$SYSPOLICY_CHECK_BIN" distribution "$APP_PATH"

# Package the already-stapled app into the final user-facing disk image. The
# DMG is separately signed, notarized, and stapled because it is the outermost
# container that Gatekeeper evaluates when users download Canis97.
CANIS97_DMG_WORK_DIR="$WORK_DIR/visual-dmg" \
  "$CREATE_DMG_BIN" "$APP_PATH" "$FINAL_ARCHIVE"
[[ -f "$FINAL_ARCHIVE" ]] || fail "final DMG was not created"
"$CODESIGN_BIN" --force --timestamp --identifier "$DMG_IDENTIFIER" --sign "$SIGNING_IDENTITY" "$FINAL_ARCHIVE"
check_signed_disk_image "$FINAL_ARCHIVE"

"$XCRUN_BIN" notarytool submit "$FINAL_ARCHIVE" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --wait
"$XCRUN_BIN" stapler staple "$FINAL_ARCHIVE"
"$XCRUN_BIN" stapler validate "$FINAL_ARCHIVE"
check_signed_disk_image "$FINAL_ARCHIVE"
"$SPCTL_BIN" --assess --type open --context context:primary-signature --verbose=2 "$FINAL_ARCHIVE"
"$SYSPOLICY_CHECK_BIN" distribution "$APP_PATH"

archive_sha="$($SHASUM_BIN -a 256 "$FINAL_ARCHIVE" | awk '{print $1}')"
printf '%s  %s\n' "$archive_sha" "$(basename "$FINAL_ARCHIVE")" > "$CHECKSUMS_PATH"

RELEASE_ARCHIVE_PATH="$FINAL_ARCHIVE" \
  "$ROOT_DIR/script/generate_release_sbom.sh" "$VERSION" "$SBOM_PATH"
write_verification_manifest

printf 'release artifacts: %s\n' "$OUTPUT_DIR"
