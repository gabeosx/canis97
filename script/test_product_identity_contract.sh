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
readonly WEB_AUTH_BRIDGE="$ROOT/SiriusMac/Authentication/WebAuthenticationBridge.swift"
readonly RESTORABLE_CREDENTIAL_SOURCE="$ROOT/SiriusMac/Authentication/RestorableAuthenticationCredentialSource.swift"
readonly PLAYBACK_COORDINATOR="$ROOT/SiriusMac/Listening/PlaybackCoordinator.swift"
readonly OFFLINE_REVIEW_HARNESS="$ROOT/SiriusMac/Testing/UITestHarness.swift"
readonly ICON="$ROOT/SiriusMac/Assets/ProductIcon.icon"
readonly PROJECT_FILE="$ROOT/SiriusMac.xcodeproj/project.pbxproj"
readonly APP_INFO_PLIST="$ROOT/SiriusMac/Info.plist"
readonly APP_SCHEME="$ROOT/SiriusMac.xcodeproj/xcshareddata/xcschemes/Canis97.xcscheme"
readonly UI_VALIDATION_SCHEME="$ROOT/SiriusMac.xcodeproj/xcshareddata/xcschemes/Canis97UIValidation.xcscheme"

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
  ! /usr/bin/sed -n '/^check_tracer()/,/^}/p' "$0" | rg -n "$forbidden_runtime_pattern" >/dev/null || fail 'tracer must remain source-only and launch-safe'
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
  require_file "$WEB_AUTH_BRIDGE"; require_file "$RESTORABLE_CREDENTIAL_SOURCE"; require_file "$PLAYBACK_COORDINATOR"; require_file "$OFFLINE_REVIEW_HARNESS"
  for source in "$WEB_AUTH_BRIDGE" "$RESTORABLE_CREDENTIAL_SOURCE" "$PLAYBACK_COORDINATOR"; do
    rg -Fq 'ProductIdentity.appLogSubsystem' "$source" || fail 'app telemetry must use the product log subsystem'
    rg -Fq 'ProductIdentity.displayName' "$source" || fail 'app telemetry must use the product display identity'
  done
  rg -Fq 'enum OfflineReviewLaunchMode' "$APP" || fail 'offline review launch mode must be product-neutral'
  rg -Fq 'ProductIdentity.environmentPrefix' "$APP" || fail 'offline review environment keys must use the approved prefix'
  rg -Fq 'enum OfflineReviewSurface' "$OFFLINE_REVIEW_HARNESS" || fail 'offline review surface selector is required'
  rg -Fq 'ClosedAuthenticationTerminal.allCases' "$OFFLINE_REVIEW_HARNESS" || fail 'offline review must cover all authentication outcomes'
  for surface in compactEmpty compactPopulated compactPending compactError libraryCollections libraryEmpty libraryError appearanceManagement nativeAppearance signalGlowAppearance tapeDeckAppearance; do
    rg -Fq "case $surface" "$OFFLINE_REVIEW_HARNESS" || fail "offline review surface missing: $surface"
  done
  ! rg -Fq 'SIRIUS_MAC_UI_TEST_MODE' "$APP" "$OFFLINE_REVIEW_HARNESS" || fail 'legacy offline-review environment key remains'
  ! rg -Fq 'struct SiriusMacApp: App' "$APP" || fail 'legacy app entry-point type remains'
  printf 'product-identity presentation contract: PASS\n'
}

check_appearance() {
  check_presentation
  local skin_appearance="$ROOT/SiriusMac/Skins/SkinAppearance.swift"
  local compact_player="$ROOT/SiriusMac/Player/CompactPlayerView.swift"
  local presentation_tests="$ROOT/SiriusMacTests/CompactPlayerPresentationTests.swift"
  local signal_glow="$ROOT/SiriusMac/Skins/Bundled/SignalGlow.json"
  local tape_deck="$ROOT/SiriusMac/Skins/Bundled/TapeDeck.json"
  require_file "$skin_appearance"; require_file "$compact_player"; require_file "$presentation_tests"
  require_file "$signal_glow"; require_file "$tape_deck"
  /usr/bin/jq -e . "$signal_glow" "$tape_deck" >/dev/null
  rg -Fq 'case chromeHighlight' "$skin_appearance" || fail 'closed chromeHighlight surface is required'
  rg -Fq 'case displayGlow' "$skin_appearance" || fail 'closed displayGlow surface is required'
  rg -Fq 'static func validateVersion2' "$skin_appearance" || fail 'schema version 2 validator is required'
  rg -Fq 'version1RequiredKeys' "$skin_appearance" || fail 'schema version 1 key set must remain explicit'
  rg -Fq 'version2RequiredKeys' "$skin_appearance" || fail 'schema version 2 key set must remain explicit'
  rg -Fq 'appOwnedDecorativeSurfaces' "$compact_player" || fail 'one native renderer must consume the decorative treatments'
  rg -Fq '.chromeHighlight' "$compact_player" || fail 'renderer must consume chromeHighlight'
  rg -Fq '.displayGlow' "$compact_player" || fail 'renderer must consume displayGlow'
  rg -Fq '.allowsHitTesting(false)' "$compact_player" || fail 'decorative treatments must remain noninteractive'
  rg -Fq '.accessibilityHidden(true)' "$compact_player" || fail 'decorative treatments must remain hidden from accessibility'
  rg -Fq '.frame(width: style.contentSize.width, height: style.contentSize.height' "$compact_player" || fail 'compact renderer must preserve fixed style content size'
  rg -Fq 'CGSize(width: 400, height: 288)' "$ROOT/SiriusMac/Player/CompactPlayerPresentation.swift" || fail 'Native fallback must remain 400×288'
  rg -Fq 'testVersionOneAppearanceRemainsExactWhileVersionTwoProjectsOnlyDecorativeTreatments' "$presentation_tests" || fail 'version compatibility coverage is required'
  rg -Fq 'testVersionTwoRejectsUnknownFieldsAndMissingOrInvalidDecorativeRoles' "$presentation_tests" || fail 'schema authority rejection coverage is required'
  rg -Fq 'testCompactAppearanceInputCannotChangeSemanticControlsOrGeometry' "$presentation_tests" || fail 'control and geometry coverage is required'
  rg -Fq 'testAppearanceFamilyKeepsOneActionAndAccessibilityContractForLongEmptyAndErrorContent' "$presentation_tests" || fail 'appearance family semantic coverage is required'
  for manifest in "$signal_glow" "$tape_deck"; do
    local schema_version
    schema_version="$(/usr/bin/jq -r '.schemaVersion' "$manifest")"
    [[ "$schema_version" == '2' ]] || fail 'bundled appearances must use schema version 2'
    [[ "$(/usr/bin/jq -r '.chromeHighlight' "$manifest")" != 'null' ]] || fail 'schema version 2 requires chromeHighlight'
    [[ "$(/usr/bin/jq -r '.displayGlow' "$manifest")" != 'null' ]] || fail 'schema version 2 requires displayGlow'
  done
  local forbidden_manifest_pattern='"(action|accessibility|focus|reduceMotion|contentWidth|contentHeight|transportControlSize|url|URL|menu|playback|authentication|persistence|window)'
  ! rg -n "$forbidden_manifest_pattern" "$skin_appearance" >/dev/null || fail 'skin manifest authority expanded beyond bounded appearance fields'
  printf 'product-identity appearance contract: PASS\n'
}

check_cutover() {
  check_appearance
  local test_product_suffix="xc""test"
  require_file "$PROJECT_FILE"; require_file "$APP_INFO_PLIST"; require_file "$APP_SCHEME"; require_file "$UI_VALIDATION_SCHEME"
  /usr/bin/plutil -lint "$PROJECT_FILE" >/dev/null
  /usr/bin/plutil -lint "$APP_INFO_PLIST" >/dev/null
  /usr/bin/xmllint --noout "$APP_SCHEME" "$UI_VALIDATION_SCHEME"
  [[ ! -e "$ROOT/SiriusMac.xcodeproj/xcshareddata/xcschemes/SiriusMac.xcscheme" ]] || fail 'legacy app scheme file remains'
  [[ ! -e "$ROOT/SiriusMac.xcodeproj/xcshareddata/xcschemes/SiriusMacUIValidation.xcscheme" ]] || fail 'legacy UI-validation scheme file remains'

  rg -Fq 'A00100050000000000000001 /* Canis97 */' "$PROJECT_FILE" || fail 'approved app target is not connected to the stable blueprint ID'
  rg -Fq 'E1E1E1E1E1E1E1E1E1E1E1E1 /* Canis97Tests */' "$PROJECT_FILE" || fail 'approved unit-test target is not connected to the stable blueprint ID'
  rg -Fq '030900050000000000000001 /* Canis97UITests */' "$PROJECT_FILE" || fail 'approved UI-test target is not connected to the stable blueprint ID'
  rg -Fq 'path = Canis97.app' "$PROJECT_FILE" || fail 'approved app product is missing'
  rg -Fq "path = Canis97Tests.$test_product_suffix" "$PROJECT_FILE" || fail 'approved unit-test product is missing'
  rg -Fq "path = Canis97UITests.$test_product_suffix" "$PROJECT_FILE" || fail 'approved UI-test product is missing'
  [[ "$(rg -c 'PRODUCT_BUNDLE_IDENTIFIER = com\.canis97\.player;' "$PROJECT_FILE")" == '2' ]] || fail 'app bundle ID must match in Debug and Release'
  [[ "$(rg -c 'PRODUCT_BUNDLE_IDENTIFIER = com\.canis97\.player\.tests;' "$PROJECT_FILE")" == '2' ]] || fail 'unit-test bundle ID must match in Debug and Release'
  [[ "$(rg -c 'PRODUCT_BUNDLE_IDENTIFIER = com\.canis97\.player\.uitests;' "$PROJECT_FILE")" == '2' ]] || fail 'UI-test bundle ID must match in Debug and Release'
  [[ "$(rg -c 'PRODUCT_MODULE_NAME = Canis97;' "$PROJECT_FILE")" == '2' ]] || fail 'app module must match in Debug and Release'
  [[ "$(rg -c 'TEST_HOST = "\$\(BUILT_PRODUCTS_DIR\)/Canis97\.app/Contents/MacOS/Canis97";' "$PROJECT_FILE")" == '2' ]] || fail 'unit-test host must use the approved app executable'
  [[ "$(rg -c 'TEST_TARGET_NAME = Canis97;' "$PROJECT_FILE")" == '2' ]] || fail 'UI-test target must use the approved app target'

  for source in ProductIdentity.swift ProductIdentityMigration.swift AboutProductView.swift PlaybackQueue.swift; do
    rg -Fq "$source in Sources" "$PROJECT_FILE" || fail "app source membership missing: $source"
  done
  while IFS= read -r test_source; do
    local test_basename
    test_basename="${test_source##*/}"
    rg -Fq "$test_basename in Sources" "$PROJECT_FILE" || fail "unit-test source membership missing: $test_basename"
  done < <(find "$ROOT/SiriusMacTests" -type f -name '*.swift' | sort)

  rg -Fq 'ProductIcon.icon in Resources' "$PROJECT_FILE" || fail 'ProductIcon resource membership is missing'
  [[ "$(rg -c 'ASSETCATALOG_COMPILER_APPICON_NAME = ProductIcon;' "$PROJECT_FILE")" == '2' ]] || fail 'ProductIcon must be the sole Debug and Release app-icon association'
  ! rg -Fq 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon' "$PROJECT_FILE" || fail 'competing AppIcon authority remains'
  [[ "$(find "$ROOT/SiriusMac" -type d -name '*.icon' | wc -l | tr -d ' ')" == '1' ]] || fail 'exactly one Icon Composer source is required after cutover'
  [[ "$(/usr/bin/plutil -extract UTExportedTypeDeclarations.0.UTTypeIdentifier raw "$APP_INFO_PLIST")" == 'com.canis97.skin-package' ]] || fail 'primary skin UTType declaration is missing'
  [[ "$(/usr/bin/plutil -convert json -o - "$APP_INFO_PLIST" | /usr/bin/jq -r '.UTExportedTypeDeclarations[0].UTTypeTagSpecification["public.filename-extension"][0]')" == 'canis97skin' ]] || fail 'primary skin extension declaration is missing'
  [[ "$(/usr/bin/plutil -extract UTImportedTypeDeclarations.0.UTTypeIdentifier raw "$APP_INFO_PLIST")" == 'com.siriusmac.skin-package' ]] || fail 'legacy skin UTType declaration is missing'
  [[ "$(/usr/bin/plutil -convert json -o - "$APP_INFO_PLIST" | /usr/bin/jq -r '.UTImportedTypeDeclarations[0].UTTypeTagSpecification["public.filename-extension"][0]')" == 'siriusskin' ]] || fail 'legacy skin extension declaration is missing'
  [[ "$(rg -c 'INFOPLIST_FILE = SiriusMac/Info.plist;' "$PROJECT_FILE")" == '2' ]] || fail 'app configurations must use the authoritative Info.plist'

  for scheme in "$APP_SCHEME" "$UI_VALIDATION_SCHEME"; do
    rg -Fq 'BlueprintIdentifier="A00100050000000000000001" BuildableName="Canis97.app" BlueprintName="Canis97"' "$scheme" || fail 'scheme app reference does not match the approved tuple'
    ! rg -Fq 'BlueprintName="SiriusMac"' "$scheme" || fail 'legacy app blueprint name remains in an approved scheme'
  done
  rg -Fq "BuildableName=\"Canis97Tests.$test_product_suffix\" BlueprintName=\"Canis97Tests\"" "$APP_SCHEME" || fail 'approved unit-test scheme reference is missing'
  rg -Fq "BuildableName=\"Canis97UITests.$test_product_suffix\" BlueprintName=\"Canis97UITests\"" "$APP_SCHEME" "$UI_VALIDATION_SCHEME" || fail 'approved UI-test scheme reference is missing'
  rg -Fq 'name: "SiriusXMClient"' "$CLIENT_PACKAGE" || fail 'provider client package identity changed during cutover'
  rg -Fq 'Bundle.main.bundleIdentifier ?? "com.siriusmac.player"' "$KEYCHAIN_STORE" || fail 'legacy Keychain service fallback changed during cutover'
  printf 'product-identity cutover contract: PASS\n'
}

selected_value() {
  /usr/bin/plutil -extract "selectedIdentity.$1" raw "$ARTIFACT"
}

check_final_source() {
  check_cutover

  local module_name app_bundle_identifier executable_name scheme_name environment_prefix
  local app_log_subsystem script_prefix display_name
  module_name="$(selected_value moduleName)"
  app_bundle_identifier="$(selected_value appBundleIdentifier)"
  executable_name="$(selected_value executableName)"
  scheme_name="$(selected_value schemeName)"
  environment_prefix="$(selected_value environmentPrefix)"
  app_log_subsystem="$(selected_value appLogSubsystem)"
  script_prefix="$(selected_value scriptPrefix)"
  display_name="$(selected_value displayName)"

  local unit_test_sources=(
    "$ROOT/SiriusMacTests/SelectedAuthenticationCompositionTests.swift"
    "$ROOT/SiriusMacTests/SkinPackageImporterTests.swift"
    "$ROOT/SiriusMacTests/SystemMediaControllerTests.swift"
    "$ROOT/SiriusMacTests/WebAuthenticationBridgeTests.swift"
  )
  local source
  for source in "${unit_test_sources[@]}"; do
    require_file "$source"
    rg -Fq "@testable import $module_name" "$source" || fail "remaining unit test must import approved module: ${source#$ROOT/}"
    ! rg -Fq '@testable import SiriusMac' "$source" || fail "legacy app module import remains: ${source#$ROOT/}"
  done

  local ui_tests="$ROOT/SiriusMacUITests/SiriusMacUITests.swift"
  require_file "$ui_tests"
  rg -Fq "$app_bundle_identifier" "$ui_tests" || fail 'UI tests must use the approved app bundle identifier'
  rg -Fq "$executable_name.app/Contents/MacOS/$executable_name" "$ui_tests" || fail 'UI tests must verify the approved exact executable path'
  rg -Fq "$environment_prefix" "$ui_tests" || fail 'UI tests must use the approved environment prefix'
  rg -Fq "$display_name" "$ui_tests" || fail 'UI tests must use the approved display/window identity'
  rg -Fq 'runningApplications' "$ui_tests" || fail 'UI tests must retain preflight process refusal'
  rg -Fq 'terminate' "$ui_tests" || fail 'UI tests must retain guarded teardown'

  local launcher="$ROOT/script/build_and_run.sh"
  local native_launcher="$ROOT/script/native_single_instance_launcher.swift"
  local live_checkpoint="$ROOT/script/live_compatibility_checkpoint.sh"
  local source_suite="$ROOT/script/tests/build_and_run_script_tests.sh"
  local build_suite="$ROOT/script/tests/build_and_run_tests.sh"
  for source in "$launcher" "$native_launcher" "$live_checkpoint" "$source_suite" "$build_suite"; do
    require_file "$source"
  done

  for expected in "$scheme_name" "$app_bundle_identifier" "$executable_name" "$app_log_subsystem" "$environment_prefix" "$script_prefix"; do
    rg -Fq "$expected" "$launcher" "$native_launcher" "$live_checkpoint" "$source_suite" "$build_suite" || fail "launcher consumers are missing approved identity value: $expected"
  done
  rg -Fq 'com.siriusmac.client' "$launcher" || fail 'provider-client telemetry subsystem must remain unchanged'
  rg -Fq 'SiriusXMClient' "$live_checkpoint" || fail 'live compatibility checkpoint must retain provider-client identity'

  ! rg -n '@testable import SiriusMac|com\.siriusmac\.player\.uitests|SIRIUS_MAC_UI_TEST_MODE|SiriusMac\.app/Contents/MacOS/SiriusMac' \
    "$ROOT/SiriusMacTests" "$ui_tests" "$launcher" "$native_launcher" "$live_checkpoint" "$source_suite" "$build_suite" >/dev/null \
    || fail 'stale app-owned identity remains outside an explicit compatibility fixture'

  printf 'product-identity final source contract: PASS\n'
}

check_built_product() {
  check_final_source
  local derived_data="${IDENTITY_DERIVED_DATA_PATH:-}"
  [[ -n "$derived_data" ]] || fail 'IDENTITY_DERIVED_DATA_PATH is required for built-product inspection'
  [[ -d "$derived_data" ]] || fail "DerivedData path does not exist: $derived_data"

  local executable_name app_bundle_identifier module_name icon_basename skin_type skin_extension
  executable_name="$(selected_value executableName)"
  app_bundle_identifier="$(selected_value appBundleIdentifier)"
  module_name="$(selected_value moduleName)"
  icon_basename="$(selected_value iconBasename)"
  skin_type="$(selected_value skinPackageTypeIdentifier)"
  skin_extension="$(selected_value skinPackageExtension)"

  local built_app
  built_app="$(find "$derived_data/Build/Products" -type d -path "*/$executable_name.app" -print -quit 2>/dev/null || true)"
  [[ -n "$built_app" ]] || fail "built app not found below $derived_data/Build/Products"
  local info="$built_app/Contents/Info.plist"
  local binary="$built_app/Contents/MacOS/$executable_name"
  require_file "$info"
  require_file "$binary"

  [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$info")" == "$app_bundle_identifier" ]] || fail 'built app bundle identifier does not match approved identity'
  [[ "$(/usr/bin/plutil -extract CFBundleExecutable raw "$info")" == "$executable_name" ]] || fail 'built app executable does not match approved identity'
  [[ "$(/usr/bin/plutil -extract CFBundleName raw "$info")" == "$executable_name" ]] || fail 'built app product name does not match approved identity'
  [[ "$(/usr/bin/plutil -extract CFBundleIconName raw "$info")" == "$icon_basename" ]] || fail 'built app icon basename does not match ProductIcon'
  /usr/bin/plutil -p "$info" | rg -Fq "$skin_type" || fail 'built app is missing the approved skin UTType'
  /usr/bin/plutil -p "$info" | rg -Fq "$skin_extension" || fail 'built app is missing the approved skin extension'
  /usr/bin/plutil -p "$info" | rg -Fq 'com.siriusmac.skin-package' || fail 'built app is missing the legacy skin compatibility UTType'
  /usr/bin/plutil -p "$info" | rg -Fq 'siriusskin' || fail 'built app is missing the legacy skin compatibility extension'
  ! /usr/bin/plutil -p "$info" | rg -Fq 'AppIcon' || fail 'built app contains a competing icon authority'

  local unit_product ui_product
  unit_product="$(find "$derived_data/Build/Products" -type d -name 'Canis97Tests.xctest' -print -quit 2>/dev/null || true)"
  ui_product="$(find "$derived_data/Build/Products" -type d -name 'Canis97UITests.xctest' -print -quit 2>/dev/null || true)"
  [[ -n "$unit_product" ]] || fail 'built unit-test product is missing'
  [[ -n "$ui_product" ]] || fail 'built UI-test product is missing'
  [[ -d "$built_app/Contents/Resources/$icon_basename.icon" || -f "$built_app/Contents/Resources/$icon_basename.icns" || -f "$built_app/Contents/Resources/Assets.car" ]] || fail 'built app has no compiled ProductIcon resource authority'
  [[ "$module_name" == 'Canis97' ]] || fail 'approved module identity changed before built-product inspection'

  printf 'product-identity built product: PASS (%s)\n' "$built_app"
}

case "${1:-}" in
  --tracer) check_tracer ;;
  --migration) check_migration ;;
  --presentation) check_presentation ;;
  --appearance) check_appearance ;;
  --cutover) check_cutover ;;
  --final-source) check_final_source ;;
  --built-product) check_built_product ;;
  *) printf 'usage: %s --tracer|--migration|--presentation|--appearance|--cutover|--final-source|--built-product\n' "$0" >&2; exit 64 ;;
esac
