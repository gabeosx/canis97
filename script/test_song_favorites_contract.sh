#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly MODEL_SOURCE="$ROOT_DIR/SiriusMac/Library/SongFavoriteModels.swift"
readonly MODEL_TEST="$ROOT_DIR/script/tests/SongFavoriteModelContractTests.swift"
readonly STORE_SOURCE="$ROOT_DIR/SiriusMac/Library/LibraryStore.swift"
readonly CONTROLLER_SOURCE="$ROOT_DIR/SiriusMac/App/ListeningSessionController.swift"
readonly APP_SOURCE="$ROOT_DIR/SiriusMac/SiriusMacApp.swift"
readonly LIBRARY_VIEW_SOURCE="$ROOT_DIR/SiriusMac/Catalog/ListeningView.swift"
readonly ANNOUNCER_SOURCE="$ROOT_DIR/SiriusMac/Accessibility/AccessibilityAnnouncer.swift"
readonly COMPACT_PLAYER_SOURCE="$ROOT_DIR/SiriusMac/Player/CompactPlayerView.swift"
readonly PROJECT_FILE="$ROOT_DIR/SiriusMac.xcodeproj/project.pbxproj"
readonly HARNESS_SOURCE="$ROOT_DIR/SiriusMac/Testing/UITestHarness.swift"
readonly STORE_TESTS="$ROOT_DIR/SiriusMacTests/LibraryStoreTests.swift"
readonly CONTROLLER_TESTS="$ROOT_DIR/SiriusMacTests/ListeningSessionControllerTests.swift"

fail() { printf 'song favorites contract: %s\n' "$*" >&2; exit 1; }
require_file() { [[ -f "$1" ]] || fail "missing required file: ${1#$ROOT_DIR/}"; }
require_text() { rg -Fq "$2" "$1" || fail "missing '$2' in ${1#$ROOT_DIR/}"; }

check_model() {
  require_file "$MODEL_SOURCE"; require_file "$MODEL_TEST"
  local temp_dir
  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/canis97-song-favorites.XXXXXX")"
  trap 'rm -rf "${temp_dir:-}"' EXIT
  export CLANG_MODULE_CACHE_PATH="$temp_dir/clang-cache"
  export SWIFT_MODULE_CACHE_PATH="$temp_dir/swift-cache"
  cp "$MODEL_TEST" "$temp_dir/main.swift"
  swiftc "$MODEL_SOURCE" "$temp_dir/main.swift" -o "$temp_dir/song-favorite-model-contract"
  "$temp_dir/song-favorite-model-contract"
  require_text "$MODEL_SOURCE" 'struct FavoriteSongIdentity'
  require_text "$MODEL_SOURCE" 'struct FavoriteSongSnapshot'
  ! rg -n 'import (AppKit|AVFoundation|SiriusXMClient|SwiftData)|URLSession|PlaybackQueue|tune\(' "$MODEL_SOURCE" >/dev/null || fail 'pure model acquired app, service, or playback authority'
}

check_persistence() {
  require_file "$STORE_SOURCE"; require_file "$CONTROLLER_SOURCE"; require_file "$APP_SOURCE"; require_file "$PROJECT_FILE"
  require_file "$HARNESS_SOURCE"; require_file "$STORE_TESTS"; require_file "$CONTROLLER_TESTS"
  require_text "$STORE_SOURCE" 'final class FavoriteRecord'
  require_text "$STORE_SOURCE" 'final class FavoriteSongRecord'
  require_text "$STORE_SOURCE" 'func setSongFavorite'
  require_text "$STORE_SOURCE" 'static let persistedPropertyNames'
  require_text "$CONTROLLER_SOURCE" 'func setFavoriteCurrentSong'
  require_text "$CONTROLLER_SOURCE" 'favoriteCurrentSongCandidate'
  require_text "$APP_SOURCE" 'favoriteCurrentSongState.title'
  require_text "$PROJECT_FILE" 'SongFavoriteModels.swift in Sources'
  require_text "$HARNESS_SOURCE" 'FavoriteSongRecord.self'
  require_text "$STORE_TESTS" 'testSongFavoritesDeduplicateAndReload'
  require_text "$STORE_TESTS" 'testSongFavoriteFallbackDoesNotPublishAnEphemeralSavedState'
  require_text "$CONTROLLER_TESTS" 'FavoriteSongRecord.self'
  local container_count song_record_count
  container_count="$(rg -F 'ModelContainer(' "$STORE_SOURCE" "$HARNESS_SOURCE" "$STORE_TESTS" "$CONTROLLER_TESTS" | wc -l | tr -d ' ')"
  song_record_count="$(rg -F 'FavoriteSongRecord.self' "$STORE_SOURCE" "$HARNESS_SOURCE" "$STORE_TESTS" "$CONTROLLER_TESTS" | wc -l | tr -d ' ')"
  [[ "$song_record_count" -ge "$container_count" ]] || fail 'every production, review, and focused-test ModelContainer must register FavoriteSongRecord'
  require_text "$STORE_SOURCE" 'return lhs.identity.normalizedArtist < rhs.identity.normalizedArtist'
  require_text "$STORE_SOURCE" 'return lhs.identity.normalizedTitle < rhs.identity.normalizedTitle'
  ! rg -n 'PlaybackQueue|SystemMedia|NowPlaying|tune\(' "$MODEL_SOURCE" >/dev/null || fail 'song model acquired playback authority'
  printf 'song favorites persistence contract: PASS\n'
}

check_collection() {
  require_file "$LIBRARY_VIEW_SOURCE"; require_file "$STORE_TESTS"
  require_text "$LIBRARY_VIEW_SOURCE" 'case favoriteSongs'
  require_text "$LIBRARY_VIEW_SOURCE" '"Favorite Songs"'
  require_text "$LIBRARY_VIEW_SOURCE" 'struct FavoriteSongRow'
  require_text "$LIBRARY_VIEW_SOURCE" 'protocol SongFavoriteClipboardWriting'
  require_text "$LIBRARY_VIEW_SOURCE" 'SystemSongFavoriteClipboardWriter'
  require_text "$LIBRARY_VIEW_SOURCE" 'snapshot.copyText'
  require_text "$LIBRARY_VIEW_SOURCE" 'No Favorite Songs Yet'
  require_text "$STORE_TESTS" 'testFiveLockedTabsExposeNativeTitlesAndPersistenceValues'
  require_text "$STORE_TESTS" 'testFavoriteSongSearchUsesOnlySavedSongPresentation'
  require_text "$STORE_TESTS" 'testFavoriteSongRowKeepsSavedContextOutOfChannelProjection'
  local row_source
  row_source="$(sed -n '/^struct FavoriteSongRow:/,$p' "$LIBRARY_VIEW_SOURCE")"
  ! printf '%s' "$row_source" | rg -n 'LibraryChannelItem|NativeListDoubleActionBridge|PlaybackQueue|tune\(|Now Playing|isFavorite\(' >/dev/null \
    || fail 'favorite-song row acquired channel, queue, or playback authority'
  printf 'song favorites collection contract: PASS\n'
}

check_action() {
  require_file "$CONTROLLER_SOURCE"; require_file "$APP_SOURCE"; require_file "$ANNOUNCER_SOURCE"
  require_file "$CONTROLLER_TESTS"
  require_text "$CONTROLLER_SOURCE" 'var title: String'
  require_text "$CONTROLLER_SOURCE" 'var accessibilityHint: String'
  require_text "$CONTROLLER_SOURCE" 'func setSongFavorite'
  require_text "$APP_SOURCE" 'favoriteCurrentSongState.title'
  require_text "$APP_SOURCE" 'favoriteCurrentSongState.accessibilityHint'
  require_text "$ANNOUNCER_SOURCE" 'case songFavoriteAdded'
  require_text "$ANNOUNCER_SOURCE" 'Added song to Favorite Songs'
  require_text "$ANNOUNCER_SOURCE" 'Removed song from Favorite Songs'
  require_text "$CONTROLLER_TESTS" 'testEveryIneligibleReasonHasClosedAccessibleCopy'
  require_text "$CONTROLLER_TESTS" 'testSongMutationRouteStaysOutsideListeningAndSystemMediaAuthority'
  require_text "$APP_SOURCE" 'case .toggleFavorite:'
  require_text "$COMPACT_PLAYER_SOURCE" 'compact.favorite'
  require_text "$APP_SOURCE" 'case .toggleFavorite:'
  printf 'song favorites action contract: PASS\n'
}

check_final() {
  check_model
  check_persistence
  check_collection
  check_action
  ! rg -n 'URLSession|OAuth|playlist|deepLink|Spotify|AppleMusic|MusicKit' \
    "$LIBRARY_VIEW_SOURCE" "$CONTROLLER_SOURCE" "$APP_SOURCE" >/dev/null \
    || fail 'song favorite surfaces acquired external-service authority'
  printf 'song favorites final contract: PASS\n'
}

case "${1:-}" in
  model) check_model ;;
  persistence) check_persistence ;;
  collection) check_collection ;;
  action) check_action ;;
  final) check_final ;;
  *) printf 'usage: %s model|persistence|collection|action|final\n' "$0" >&2; exit 64 ;;
esac
