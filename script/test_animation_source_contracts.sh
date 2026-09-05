#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="${ANIMATION_SOURCE_ROOT:-$repo_root}"

runtime="$source_root/SiriusMac/Motion/AnimatedSkinRuntime.swift"
converter="$source_root/Canis97MotionConverter/Canis97MotionConverterService.swift"
compact="$source_root/SiriusMac/Player/CompactPlayerView.swift"
entitlements="$source_root/Canis97MotionConverter/Canis97MotionConverter.entitlements"
project="$source_root/SiriusMac.xcodeproj/project.pbxproj"
app_source="$source_root/SiriusMac/SiriusMacApp.swift"
scheme="$source_root/SiriusMac.xcodeproj/xcshareddata/xcschemes/Canis97AnimationAcceptance.xcscheme"
exit97_manifest="$source_root/SiriusMac/Skins/Bundled/Exit97.json"
exit97_motion="$source_root/SiriusMac/Skins/Bundled/Exit97.motion.json"
exit97_scene="$source_root/SiriusMac/Skins/Bundled/Exit97.scene.json"
quartz_manifest="$source_root/SiriusMac/Skins/Bundled/QuartzDeck.json"
quartz_motion="$source_root/SiriusMac/Skins/Bundled/QuartzDeck.motion.json"
quartz_scene="$source_root/SiriusMac/Skins/Bundled/QuartzDeck.scene.json"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for required in "$runtime" "$converter" "$compact" "$entitlements" "$project" "$app_source" "$scheme" "$exit97_manifest" "$exit97_motion" "$exit97_scene" "$quartz_manifest" "$quartz_motion" "$quartz_scene"; do
  [[ -f "$required" ]] || fail "required animation contract source is missing"
done

# Strip comment-only regions before source inspection so explanatory prose can
# never satisfy or evade a contract. The current codebase does not nest blocks.
executable_region() {
  perl -0pe 's{/\*.*?\*/}{}gs; s{^[\t ]*//.*$}{}gm' "$1"
}

require_region() {
  local label="$1"
  local pattern="$2"
  local file="$3"
  LC_ALL=C grep -Eq "$pattern" <<< "$(executable_region "$file")" || fail "$label"
}

forbid_region() {
  local label="$1"
  local pattern="$2"
  local file="$3"
  if LC_ALL=C grep -Eq "$pattern" <<< "$(executable_region "$file")"; then
    fail "$label"
  fi
}

require_region "Lottie must remain pinned to exact 4.6.1" 'repositoryURL = "https://github\.com/airbnb/lottie-ios\.git"; requirement = \{[[:space:]]*kind = exactVersion; version = 4\.6\.1;' "$project"
require_region "acceptance build must define its isolated compilation condition" 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = CANIS97_ANIMATION_ACCEPTANCE;.*SWIFT_OPTIMIZATION_LEVEL = "-O";.*name = AnimationAcceptance;' "$project"
require_region "public Release must remain free of the acceptance condition" 'A00100080000000000000004.*name = Release;' "$project"
if LC_ALL=C grep -Eq 'A00100080000000000000004.*CANIS97_ANIMATION_ACCEPTANCE' <<< "$(executable_region "$project")"; then
  fail "public Release must not expose the offline acceptance condition"
fi
require_region "offline review must compile in acceptance builds" '#if DEBUG \|\| CANIS97_ANIMATION_ACCEPTANCE' "$app_source"
require_region "offline review must clear the session before returning" 'sessionController = nil' "$app_source"
require_region "offline review must return before normal composition" '^[[:space:]]*return$' "$app_source"
require_region "acceptance scheme must build the optimized configuration" 'buildConfiguration[[:space:]]*=[[:space:]]*"AnimationAcceptance"' "$scheme"
forbid_region "acceptance scheme must not include a test action" '<TestAction' "$scheme"
forbid_region "acceptance scheme must not include a profile action" '<ProfileAction' "$scheme"
forbid_region "acceptance scheme must not include an archive action" '<ArchiveAction' "$scheme"
require_region "runtime must force Core Animation" 'LottieConfiguration\(renderingEngine: \.coreAnimation' "$runtime"
require_region "runtime must validate canonical motion in app" 'CanonicalMotionCodec\.decode' "$runtime"
require_region "runtime must deny decoration image loading" 'DeniedAnimationImageProvider\(\)' "$runtime"
require_region "sprite scenes must pass an explicit asset allowlist" 'allowedAssets: Set\(motion\.spriteAssetURLs\.keys\)' "$runtime"
require_region "sprite scene JSON must use exact structural keys" 'object\(value,[[:space:]]*exact:' "$runtime"
require_region "sprite encounters must use a deterministic declared seed" 'seededOrder\(group\.layerIDs, seed: group\.seed\)' "$runtime"
require_region "decorative host must reject hit testing" 'override func hitTest\(_ point: NSPoint\) -> NSView\? \{ nil \}' "$runtime"
require_region "lifecycle suspension must pause the renderer" 'animationView\.pause\(\)' "$runtime"
require_region "host teardown must release the renderer view" 'animationView\.removeFromSuperview\(\)' "$runtime"
for visibility_contract in \
  '!isHiddenOrHasHiddenAncestor' \
  'window\.isVisible' \
  '!window\.isMiniaturized' \
  'window\.occlusionState\.contains\(\.visible\)' \
  '!NSApp\.isHidden'; do
  require_region "visible background windows must remain eligible for animation" "$visibility_contract" "$runtime"
done
forbid_region "animation lifecycle must not depend on foreground activation" 'isKeyWindow|NSApp\.isActive|didBecomeKeyNotification|didResignKeyNotification|didBecomeActiveNotification|didResignActiveNotification' "$runtime"
require_region "converter must retain a bounded data-only request" 'func convert\(_ request: Data, withReply reply:' "$converter"
require_region "converter must structurally validate source before adapting" 'RestrictedLottieSource\(data: request\)' "$converter"
require_region "converter must revalidate canonical budgets" 'CanonicalMotionValidator\(\)\.validate' "$converter"
require_region "converter must preserve only normalized opacity timelines" 'keyframes: opacity\.keyframes' "$converter"
require_region "converter must reject unsupported opacity animation forms" 'invalidOpacityTimeline' "$converter"
forbid_region "runtime must not construct a network provider" 'URLSession|URLRequest|URL\(string:|LottieConfiguration\.defaultURLSession' "$runtime"
forbid_region "converter must not gain file or network capability" 'URLSession|URLRequest|NSOpenPanel|NSFileCoordinator|FileManager\.default\.urls' "$converter"
forbid_region "converter protocol must not accept paths or URLs" 'func convert\([^\n]*(URL|String|UnsafeRawPointer)' "$converter"

for forbidden_entitlement in \
  'com.apple.security.network' \
  'keychain-access-groups' \
  'com.apple.security.files' \
  'com.apple.security.application-groups' \
  'com.apple.security.assets'; do
  if LC_ALL=C grep -Fq "$forbidden_entitlement" "$entitlements"; then
    fail "converter entitlement grants forbidden capability"
  fi
done

for identifier in \
  'compact.canvas' \
  'compact.favorite' \
  'compact.song-favorite' \
  'compact.transport.' \
  'compact.show-library' \
  'compact.always-on-top' \
  'compact.sign-out'; do
  require_region "compact native control identifier is missing" "$identifier" "$compact"
done
require_region "motion layer must remain noninteractive" '\.allowsHitTesting\(false\)' "$compact"
require_region "motion layer must remain hidden from accessibility" '\.accessibilityHidden\(true\)' "$compact"

jq -e '.schemaVersion == 4 and .size == "cinema448x360" and .motion.spriteScene == "Exit97.scene.json" and (.motion.spriteAssets | length) <= 24 and (.motion.spriteAssets | index("Exit97CruiseRig.png")) != null' "$exit97_manifest" >/dev/null \
  || fail "Exit 97 must declare its bounded local sprite scene"
jq -e '(.motion.events | keys | sort) == (["channelChanged","channelFavoriteAdded","channelFavoriteRemoved","favoriteChanged","recovered","songFavoriteAdded","songFavoriteRemoved"] | sort)' "$exit97_manifest" >/dev/null \
  || fail "Exit 97 must retain distinct song-heart and channel-star event hooks"
jq -e '.formatVersion == 2 and .canvas == {"width":448,"height":360} and (.layers | length) <= 32 and ([.layers[].timeline[]?] | length) <= 256 and (.encounterGroups | length) == 0 and .director.seed == 97 and (.performances | length) >= 15 and ([.layers[] | select(.identifier == "roadster" or .identifier == "night_world") | .timeline] | all(. == null))' "$exit97_scene" >/dev/null \
  || fail "Exit 97 sprite-scene budgets or deterministic encounters are invalid"
if jq -e '.. | strings | select(test("^(https?://|file://)"))' "$exit97_manifest" "$exit97_scene" >/dev/null; then
  fail "Exit 97 must not reference remote or absolute resources"
fi

jq -e '.schemaVersion == 4 and .motion.spriteScene == "QuartzDeck.scene.json" and (.motion.spriteAssets | length) == 3 and .decorations.backdrop == "QuartzDeckFaceplate@2x.png"' "$quartz_manifest" >/dev/null \
  || fail "Quartz Deck must declare its approved bounded local sprite rig"
jq -e '.size == "cinema448x360" and ([.slots[] | select(.semantic == "metadata")][0].frame == {"x":92,"y":316,"width":156,"height":40}) and ([.slots[] | select(.semantic == "favorite")][0].frame == {"x":216,"y":284,"width":32,"height":32}) and ([.slots[] | select(.semantic == "transport")][0].frame == {"x":264,"y":316,"width":128,"height":40})' "$quartz_manifest" >/dev/null \
  || fail "Quartz Deck must retain its large receiver geometry and native focus-safe inset"
jq -e '(.motion.events | keys | sort) == (["channelChanged","channelFavoriteAdded","channelFavoriteRemoved","favoriteChanged","recovered","songFavoriteAdded","songFavoriteRemoved"] | sort)' "$quartz_manifest" >/dev/null \
  || fail "Quartz Deck must retain distinct song-heart and channel-star event hooks"
jq -e '.formatVersion == 1 and .canvas == {"width":448,"height":360} and (.layers | length) == 7 and ([.layers[].timeline[]?] | length) <= 256 and (.encounterGroups | length) == 0 and ([.layers[] | select(.identifier == "record_label")][0].frame == {"x":133,"y":84,"width":97,"height":97}) and ([.layers[] | select(.role == "persistentSongFavorite")][0].frame == {"x":212,"y":317,"width":40,"height":40}) and ([.layers[] | select(.role == "persistentChannelFavorite")][0].frame == {"x":212,"y":284,"width":40,"height":40})' "$quartz_scene" >/dev/null \
  || fail "Quartz Deck sprite-scene budgets or favorite alignment are invalid"
if jq -e '.. | strings | select(test("^(https?://|file://)"))' "$quartz_manifest" "$quartz_scene" >/dev/null; then
  fail "Quartz Deck must not reference remote or absolute resources"
fi

printf 'PASS: animation source contracts\n'
