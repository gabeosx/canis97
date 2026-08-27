#!/usr/bin/env bash
set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ARTIFACT="$ROOT/.planning/phases/04.1-product-identity-experience-polish/04.1-BRAND-DECISION.json"
readonly IDENTITY="$ROOT/SiriusMac/App/ProductIdentity.swift"
readonly AUTH_VIEW="$ROOT/SiriusMac/Authentication/AuthenticationView.swift"
readonly ICON="$ROOT/SiriusMac/Assets/ProductIcon.icon"

fail() { printf 'product-identity contract: %s\n' "$*" >&2; exit 1; }
require_file() { [[ -f "$1" ]] || fail "missing required file: ${1#$ROOT/}"; }
require_key() {
  local key="$1" value
  value="$(/usr/bin/plutil -extract "selectedIdentity.$key" raw "$ARTIFACT" 2>/dev/null || true)"
  [[ -n "$value" ]] || fail "selectedIdentity.$key must be concrete"
}

check_tracer() {
  require_file "$ARTIFACT"; require_file "$IDENTITY"; require_file "$AUTH_VIEW"; require_file "$ICON/icon.json"
  /usr/bin/plutil -lint "$ARTIFACT" >/dev/null
  local artifact_status
  artifact_status="$(/usr/bin/plutil -extract status raw "$ARTIFACT")"
  [[ "$artifact_status" == "proposed" || "$artifact_status" == "rescreen-required" ]] || fail "tracer requires proposed or rescreen-required artifact status"
  if [[ "$artifact_status" == "rescreen-required" ]]; then
    [[ "$(/usr/bin/plutil -extract selectedIdentityDisposition raw "$ARTIFACT")" == "withdrawn-after-bitdeck-rescreen" ]] || fail "rescreen-required artifact must quarantine the withdrawn identity"
  fi
  [[ "$(/usr/bin/plutil -extract legalClearanceClaim raw "$ARTIFACT")" == "false" ]] || fail "legalClearanceClaim must remain false"
  [[ "$(/usr/bin/plutil -extract attorneyReviewRequired raw "$ARTIFACT")" == "true" ]] || fail "attorneyReviewRequired must remain true"
  local required_keys=(displayName appTypeName targetName moduleName executableName appBundleIdentifier unitTestTargetName unitTestBundleIdentifier uiTestTargetName uiTestBundleIdentifier schemeName uiValidationSchemeName skinPackageTypeIdentifier skinPackageExtension applicationSupportDirectoryName appLogSubsystem environmentPrefix scriptPrefix compactSceneID librarySceneID authenticationFrameAutosaveName compactFrameAutosaveName libraryFrameAutosaveName iconBasename iconConcept nonAffiliationStatement)
  local key
  local expected_line
  for key in "${required_keys[@]}"; do
    require_key "$key"
    expected_line="static let $key = \"$(/usr/bin/plutil -extract "selectedIdentity.$key" raw "$ARTIFACT")\""
    rg -Fq "$expected_line" "$IDENTITY" || fail "ProductIdentity.$key must match selectedIdentity exactly"
  done
  rg -q 'enum Legacy' "$IDENTITY" || fail 'ProductIdentity.Legacy is missing'
  rg -q 'keychainServiceCompatibilityValue = "com\.siriusmac\.player"' "$IDENTITY" || fail 'legacy Keychain compatibility value changed'
  ! rg -q 'SecItem|AuthenticationCredential|save\(|erase\(|copy\(|delete\(' "$IDENTITY" || fail 'ProductIdentity must not perform a Keychain migration'
  rg -q 'ProductIdentity\.displayName' "$AUTH_VIEW" || fail 'authentication surface must use ProductIdentity.displayName'
  rg -q 'ProductIdentity\.nonAffiliationStatement' "$AUTH_VIEW" || fail 'authentication surface must use ProductIdentity.nonAffiliationStatement'
  rg -q 'SiriusXM subscriber account' "$AUTH_VIEW" || fail 'authentication surface must retain factual subscriber-account wording'
  [[ "$(find "$ROOT/SiriusMac" -type d -name '*.icon' | wc -l | tr -d ' ')" == "1" ]] || fail 'exactly one Icon Composer source is required'
  [[ ! -d "$ROOT/SiriusMac/Assets.xcassets/AppIcon.appiconset" ]] || fail 'a competing AppIcon catalog is prohibited'
  [[ "$(find "$ICON/Assets" -type f -name '*.svg' | wc -l | tr -d ' ')" -ge 3 ]] || fail 'ProductIcon must contain at least three authored vector layers'
  rg -q '"groups"' "$ICON/icon.json" || fail 'Icon Composer groups are missing'
  rg -q '"supported-platforms"' "$ICON/icon.json" || fail 'Icon Composer platform declaration is missing'
  ! rg -ni '<(image|text)|siriusxm|sirius|apple|winamp' "$ICON/Assets" || fail 'icon layer contains prohibited imagery or text metadata'
  local forbidden_runtime_pattern="xcode""build|xct""est|XC""UIApplication|build_""and_run|Sirius""XMClient\\("
  ! rg -n "$forbidden_runtime_pattern" "$0" >/dev/null || fail 'tracer must remain source-only and launch-safe'
  printf 'product-identity tracer: PASS\n'
}

case "${1:-}" in
  --tracer) check_tracer ;;
  --migration|--presentation|--appearance|--cutover|--final-source|--built-product) fail "${1} contract is staged for its downstream plan and is not green during the proposed-identity tracer" ;;
  *) printf 'usage: %s --tracer|--migration|--presentation|--appearance|--cutover|--final-source|--built-product\n' "$0" >&2; exit 64 ;;
esac
