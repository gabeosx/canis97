#!/usr/bin/env bash
set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ARTIFACT="$ROOT/.planning/phases/04.1-product-identity-experience-polish/04.1-BRAND-DECISION.json"
readonly IDENTITY="$ROOT/SiriusMac/App/ProductIdentity.swift"
readonly MIGRATION="$ROOT/SiriusMac/App/ProductIdentityMigration.swift"
readonly LIBRARY_STORE="$ROOT/SiriusMac/Library/LibraryStore.swift"
readonly SELECTION_STORE="$ROOT/SiriusMac/Skins/SkinSelectionStore.swift"
readonly PACKAGE_IMPORTER="$ROOT/SiriusMac/Skins/SkinPackageImporter.swift"
readonly WINDOW_CONTROLLER="$ROOT/SiriusMac/Windows/CompactWindowController.swift"
readonly KEYCHAIN_STORE="$ROOT/SiriusMac/Security/KeychainCredentialStore.swift"
readonly CLIENT_PACKAGE="$ROOT/Packages/SiriusXMClient/Package.swift"
readonly AUTH_VIEW="$ROOT/SiriusMac/Authentication/AuthenticationView.swift"
readonly APP="$ROOT/SiriusMac/SiriusMacApp.swift"
readonly ABOUT_VIEW="$ROOT/SiriusMac/App/AboutProductView.swift"
readonly AUTH_ORACLE="$ROOT/SiriusMac/Authentication/ClosedAuthenticationOracle.swift"
readonly LISTENING_VIEW="$ROOT/SiriusMac/Catalog/ListeningView.swift"
readonly SKIN_MANAGEMENT_VIEW="$ROOT/SiriusMac/Skins/SkinManagementView.swift"
readonly SKIN_IMPORTER="$ROOT/SiriusMac/Skins/SkinPackageImporter.swift"
readonly ACCESSIBILITY_TESTS="$ROOT/SiriusMacTests/AccessibilityContractTests.swift"
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
  [[ "$artifact_status" == "proposed" || "$artifact_status" == "rescreen-required" || "$artifact_status" == "approved" ]] || fail "tracer requires proposed, rescreen-required, or approved artifact status"
  if [[ "$artifact_status" == "rescreen-required" ]]; then
    case "$(/usr/bin/plutil -extract selectedIdentityDisposition raw "$ARTIFACT")" in
      withdrawn-after-bitdeck-rescreen|withdrawn-after-bitjuke-rescreen|withdrawn-after-cueamp-rescreen|withdrawn-after-pixaud-rescreen) ;;
      *) fail "rescreen-required artifact must quarantine the withdrawn identity" ;;
    esac
  fi
  if [[ "$artifact_status" == "approved" ]]; then
    [[ "$(/usr/bin/plutil -extract approval.state raw "$ARTIFACT")" == "approved-product-decision" ]] || fail "approved artifact must record an approved product decision"
    [[ "$(/usr/bin/plutil -extract approval.decisionText raw "$ARTIFACT")" == "approve exact tuple" ]] || fail "approved artifact must record the exact user decision"
    [[ -n "$(/usr/bin/plutil -extract approval.approvedOn raw "$ARTIFACT")" ]] || fail "approved artifact must record an approval date"
    [[ "$(/usr/bin/plutil -extract selectedIdentityDisposition raw "$ARTIFACT")" == "approved-exact-tuple" ]] || fail "approved artifact must freeze the exact tuple"
  fi
  [[ "$(/usr/bin/plutil -extract legalClearanceClaim raw "$ARTIFACT")" == "false" ]] || fail "legalClearanceClaim must remain false"
  [[ "$(/usr/bin/plutil -extract attorneyReviewRequired raw "$ARTIFACT")" == "true" ]] || fail "attorneyReviewRequired must remain true"
  local required_keys=(displayName appTypeName targetName moduleName executableName appBundleIdentifier unitTestTargetName unitTestBundleIdentifier uiTestTargetName uiTestBundleIdentifier schemeName schemeFileName uiValidationSchemeName uiValidationSchemeFileName skinPackageTypeIdentifier skinPackageExtension applicationSupportDirectoryName appLogSubsystem environmentPrefix scriptPrefix compactSceneID librarySceneID authenticationFrameAutosaveName compactFrameAutosaveName libraryFrameAutosaveName iconBasename iconConcept nonAffiliationStatement)
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

check_migration() {
  check_tracer
  require_file "$MIGRATION"; require_file "$LIBRARY_STORE"; require_file "$SELECTION_STORE"; require_file "$PACKAGE_IMPORTER"
  rg -q 'enum ProductIdentityMigrationOutcome' "$MIGRATION" || fail 'migration must use a closed outcome'
  rg -q 'writeCompletionMarker' "$MIGRATION" || fail 'migration must persist a completion marker only after verification'
  rg -q 'readDestination' "$MIGRATION" || fail 'migration must reread its destination'
  rg -q 'verifyDestination' "$MIGRATION" || fail 'migration must verify its destination'
  ! rg -n 'SecItem|AuthenticationCredential|URLSession|HTTPCookieStorage|SiriusXMClient' "$MIGRATION" || fail 'migration operation surface must remain non-secret and provider-free'
  rg -Fq 'ProductIdentity.applicationSupportDirectoryName' "$LIBRARY_STORE" || fail 'library destination must use the approved namespace'
  rg -Fq 'ProductIdentity.Legacy.applicationSupportDirectoryName' "$LIBRARY_STORE" || fail 'library must retain legacy read compatibility'
  rg -Fq 'migrateLegacyRecords' "$LIBRARY_STORE" || fail 'library migration must remain semantic'
  rg -Fq 'verifyLegacyRecords' "$LIBRARY_STORE" || fail 'library migration must verify its semantic destination'
  rg -Fq 'ProductIdentity.applicationSupportDirectoryName' "$SELECTION_STORE" || fail 'selection destination must use the approved namespace'
  rg -Fq 'validatedImportedPackageExists' "$SELECTION_STORE" || fail 'imported selection migration must require a validated package'
  rg -Fq 'ProductIdentity.Legacy.applicationSupportDirectoryName' "$PACKAGE_IMPORTER" || fail 'managed packages must retain legacy read compatibility'
  rg -Fq 'migrateLegacyPackagesIfNeeded' "$PACKAGE_IMPORTER" || fail 'managed packages require a validated compatibility copy'
  require_file "$WINDOW_CONTROLLER"; require_file "$KEYCHAIN_STORE"; require_file "$CLIENT_PACKAGE"
  rg -Fq 'ProductIdentity.FrameAutosaveName' "$WINDOW_CONTROLLER" || fail 'window writes must use approved product-owned frame names'
  rg -Fq 'ProductIdentity.Legacy.compactFrameAutosaveName' "$WINDOW_CONTROLLER" || fail 'window migration must retain legacy read names'
  rg -Fq 'WindowFrameMigration.migratedFrameString' "$WINDOW_CONTROLLER" || fail 'window migration must validate legacy frames before copying'
  rg -Fq 'Bundle.main.bundleIdentifier ?? "com.siriusmac.player"' "$KEYCHAIN_STORE" || fail 'legacy Keychain service fallback changed'
  rg -Fq 'account: String = "approved-reusable-credential"' "$KEYCHAIN_STORE" || fail 'Keychain account changed'
  ! rg -Fq 'ProductIdentity' "$KEYCHAIN_STORE" || fail 'Keychain must not participate in identity migration'
  rg -Fq 'name: "SiriusXMClient"' "$CLIENT_PACKAGE" || fail 'provider client package identity changed'
  printf 'product-identity migration contract: PASS\n'
}

check_presentation() {
  check_migration
  require_file "$APP"; require_file "$ABOUT_VIEW"; require_file "$AUTH_ORACLE"
  rg -Fq 'struct Canis97App: App' "$APP" || fail 'app entry point must use approved app type name'
  rg -Fq 'WindowGroup(ProductIdentity.displayName, id: ProductIdentity.SceneID.compact)' "$APP" || fail 'compact scene must use approved product identity'
  rg -Fq 'Window("\(ProductIdentity.displayName) Library", id: ProductIdentity.SceneID.library)' "$APP" || fail 'library scene must use approved product identity'
  rg -Fq 'CommandGroup(replacing: .appInfo)' "$APP" || fail 'app-owned About command is required'
  rg -Fq 'AboutProductView()' "$APP" || fail 'About window must compose AboutProductView'
  rg -Fq 'ProductIdentity.nonAffiliationStatement' "$ABOUT_VIEW" || fail 'About view must show the non-affiliation statement'
  rg -Fq 'connects subscribers to SiriusXM using their own subscriber account' "$ABOUT_VIEW" || fail 'About view must keep the factual subscriber-service boundary'
  rg -Fq 'ProductIdentity.displayName' "$AUTH_ORACLE" || fail 'authentication outcomes must lead with the product identity'
  rg -Fq 'SiriusXM did not accept' "$AUTH_ORACLE" || fail 'provider rejection copy must remain factual'
  require_file "$LISTENING_VIEW"; require_file "$SKIN_MANAGEMENT_VIEW"; require_file "$SKIN_IMPORTER"; require_file "$ACCESSIBILITY_TESTS"
  rg -Fq 'ProductIdentity.displayName) library' "$LISTENING_VIEW" || fail 'library accessibility label must use the product identity'
  rg -Fq 'ProductIdentity.skinPackageTypeIdentifier' "$SKIN_MANAGEMENT_VIEW" || fail 'appearance importer must accept the approved skin type'
  rg -Fq 'ProductIdentity.Legacy.skinPackageTypeIdentifier' "$SKIN_MANAGEMENT_VIEW" || fail 'appearance importer must retain the legacy skin type'
  rg -Fq 'ProductIdentity.skinPackageExtension' "$SKIN_IMPORTER" || fail 'skin importer must accept the approved extension'
  rg -Fq 'ProductIdentity.Legacy.skinPackageExtension' "$SKIN_IMPORTER" || fail 'skin importer must retain the legacy extension'
  rg -Fq 'testProductOwnedPresentationKeepsAccessibilityAndRecoveryAppOwned' "$ACCESSIBILITY_TESTS" || fail 'structural accessibility coverage is required'
  ! rg -Fq 'struct SiriusMacApp: App' "$APP" || fail 'legacy app entry-point type remains'
  printf 'product-identity presentation contract: PASS\n'
}

case "${1:-}" in
  --tracer) check_tracer ;;
  --migration) check_migration ;;
  --presentation) check_presentation ;;
  --appearance|--cutover|--final-source|--built-product) fail "${1} contract is staged for its downstream plan" ;;
  *) printf 'usage: %s --tracer|--migration|--presentation|--appearance|--cutover|--final-source|--built-product\n' "$0" >&2; exit 64 ;;
esac
