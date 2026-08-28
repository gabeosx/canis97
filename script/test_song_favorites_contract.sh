#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly MODEL_SOURCE="$ROOT_DIR/SiriusMac/Library/SongFavoriteModels.swift"
readonly MODEL_TEST="$ROOT_DIR/script/tests/SongFavoriteModelContractTests.swift"
readonly STORE_SOURCE="$ROOT_DIR/SiriusMac/Library/LibraryStore.swift"
readonly CONTROLLER_SOURCE="$ROOT_DIR/SiriusMac/App/ListeningSessionController.swift"
readonly APP_SOURCE="$ROOT_DIR/SiriusMac/SiriusMacApp.swift"
readonly PROJECT_FILE="$ROOT_DIR/SiriusMac.xcodeproj/project.pbxproj"

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
  require_text "$STORE_SOURCE" 'final class FavoriteRecord'
  require_text "$STORE_SOURCE" 'final class FavoriteSongRecord'
  require_text "$STORE_SOURCE" 'func setSongFavorite'
  require_text "$STORE_SOURCE" 'FavoriteSongRecord.persistedPropertyNames'
  require_text "$CONTROLLER_SOURCE" 'func setFavoriteCurrentSong'
  require_text "$CONTROLLER_SOURCE" 'favoriteCurrentSongCandidate'
  require_text "$APP_SOURCE" 'Favorite Current Song'
  require_text "$PROJECT_FILE" 'SongFavoriteModels.swift in Sources'
  ! rg -n 'PlaybackQueue|SystemMedia|NowPlaying|tune\(' "$MODEL_SOURCE" >/dev/null || fail 'song model acquired playback authority'
  printf 'song favorites persistence contract: PASS\n'
}

case "${1:-}" in
  model) check_model ;;
  persistence) check_persistence ;;
  *) printf 'usage: %s model|persistence\n' "$0" >&2; exit 64 ;;
esac
