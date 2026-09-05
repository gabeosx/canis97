#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOMEBREW_BIN="${CANIS97_HOMEBREW_BIN:-brew}"
CASK_FQN=""
PRIOR_ARCHIVE=""
CURRENT_ARCHIVE=""
WORK_DIR=""
REPORT_PATH=""
APP_DIR=""
TAP_DIR=""
CACHE_DIR=""

usage() {
  echo "usage: $0 --cask-fqn OWNER/TAP/canis97 --prior-archive PATH --current-archive PATH --work-dir PATH" >&2
  exit 2
}

fail() {
  echo "Homebrew release verification error: $*" >&2
  exit 1
}

canonical_file() {
  local candidate="$1"
  [[ -f "$candidate" && ! -L "$candidate" ]] || fail "archive must be a regular non-symlink file: $candidate"
  (cd "$(dirname "$candidate")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$candidate")")
}

version_from_archive() {
  local archive_name="$(basename "$1")"
  [[ "$archive_name" =~ ^Canis97-((0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*))-arm64\.dmg$ ]] || fail "archive name must be Canis97-MAJOR.MINOR.PATCH-arm64.dmg"
  printf '%s\n' "${BASH_REMATCH[1]}"
}

render_local_cask() {
  local version="$1"
  local archive="$2"
  local archive_sha
  archive_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
  /usr/bin/ruby -ruri -e '
    version, digest, archive = ARGV
    abort "unsafe archive path" if archive.match?(/[\r\n]/)
    uri = URI::DEFAULT_PARSER.escape("file://#{archive}")
    puts "cask \"canis97\" do"
    puts "  version \"#{version}\""
    puts "  sha256 \"#{digest}\""
    puts
    puts "  url \"#{uri}\""
    puts "  name \"Canis97\""
    puts "  depends_on arch: :arm64"
    puts "  depends_on macos: \">= :tahoe\""
    puts
    puts "  app \"Canis97.app\""
    puts "end"
  ' "$version" "$archive_sha" "$archive" > "$TAP_DIR/Casks/canis97.rb"
}

assert_installed_version() {
  local expected_version="$1"
  local info_plist="$APP_DIR/Canis97.app/Contents/Info.plist"
  [[ -f "$info_plist" ]] || fail "Homebrew did not install Canis97.app into isolated app directory"
  local installed_version
  installed_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")" || fail 'installed app lacks CFBundleShortVersionString'
  [[ "$installed_version" == "$expected_version" ]] || fail "installed version $installed_version did not match $expected_version"
}

brew_run() {
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_CACHE="$CACHE_DIR" "$HOMEBREW_BIN" "$@"
}

write_report_and_cleanup() {
  local status="$?"
  local residue='none'
  if [[ -e "$APP_DIR/Canis97.app" ]]; then
    residue="$APP_DIR/Canis97.app"
  fi
  printf '{"schema_version":1,"cask":"%s","status":"%s","residue":"%s"}\n' \
    "$CASK_FQN" "$([[ "$status" -eq 0 && "$residue" == none ]] && printf clean || printf failed)" "$residue" > "$REPORT_PATH"
  rm -rf -- "$TAP_DIR" "$CACHE_DIR"
  [[ "$residue" == none ]] || exit 1
  exit "$status"
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --cask-fqn)
      [[ -z "$CASK_FQN" && "$#" -ge 2 ]] || usage
      CASK_FQN="$2"
      shift 2
      ;;
    --prior-archive)
      [[ -z "$PRIOR_ARCHIVE" && "$#" -ge 2 ]] || usage
      PRIOR_ARCHIVE="$2"
      shift 2
      ;;
    --current-archive)
      [[ -z "$CURRENT_ARCHIVE" && "$#" -ge 2 ]] || usage
      CURRENT_ARCHIVE="$2"
      shift 2
      ;;
    --work-dir)
      [[ -z "$WORK_DIR" && "$#" -ge 2 ]] || usage
      WORK_DIR="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done

[[ -n "$CASK_FQN" && -n "$PRIOR_ARCHIVE" && -n "$CURRENT_ARCHIVE" && -n "$WORK_DIR" ]] || usage
[[ "$CASK_FQN" =~ ^[a-z0-9][a-z0-9-]*/[a-z0-9][a-z0-9-]*/canis97$ ]] || fail 'cask must be fully qualified as owner/tap/canis97'
[[ "$WORK_DIR" = /* && "$WORK_DIR" != / && "$WORK_DIR" != "$ROOT_DIR" && ! -e "$WORK_DIR" ]] || fail 'work directory must be a new, explicit, isolated absolute path'
[[ "$WORK_DIR" != *$'\n'* && "$WORK_DIR" != *$'\r'* && "$WORK_DIR" != *'"'* ]] || fail 'work directory contains unsafe report-path characters'
[[ "${CANIS97_RUN_HOMEBREW_INTEGRATION:-}" == true ]] || fail 'set CANIS97_RUN_HOMEBREW_INTEGRATION=true for an owner-authorized local integration run'
command -v "$HOMEBREW_BIN" >/dev/null || fail "Homebrew command unavailable: $HOMEBREW_BIN"

PRIOR_ARCHIVE="$(canonical_file "$PRIOR_ARCHIVE")"
CURRENT_ARCHIVE="$(canonical_file "$CURRENT_ARCHIVE")"
[[ "$PRIOR_ARCHIVE" != "$CURRENT_ARCHIVE" ]] || fail 'prior and current archives must differ'
PRIOR_VERSION="$(version_from_archive "$PRIOR_ARCHIVE")"
CURRENT_VERSION="$(version_from_archive "$CURRENT_ARCHIVE")"
/usr/bin/ruby -e 'abort "current version must be newer than prior version" unless Gem::Version.new(ARGV[1]) > Gem::Version.new(ARGV[0])' "$PRIOR_VERSION" "$CURRENT_VERSION" || fail 'current archive must be a later immutable version'

APP_DIR="$WORK_DIR/apps"
TAP_DIR="$WORK_DIR/tap"
CACHE_DIR="$WORK_DIR/cache"
REPORT_PATH="$WORK_DIR/homebrew-lifecycle-report.json"
mkdir -p "$TAP_DIR/Casks" "$APP_DIR" "$CACHE_DIR"
trap write_report_and_cleanup EXIT
[[ ! -e "$APP_DIR/Canis97.app" ]] || fail 'isolated app directory already contains Canis97.app'

render_local_cask "$PRIOR_VERSION" "$PRIOR_ARCHIVE"
TAP_REF="${CASK_FQN%/canis97}"
brew_run tap "$TAP_REF" "$TAP_DIR"
brew_run install --cask --appdir "$APP_DIR" "$CASK_FQN"
assert_installed_version "$PRIOR_VERSION"

render_local_cask "$CURRENT_VERSION" "$CURRENT_ARCHIVE"
brew_run upgrade --cask --appdir "$APP_DIR" "$CASK_FQN"
assert_installed_version "$CURRENT_VERSION"
brew_run upgrade --cask --appdir "$APP_DIR" "$CASK_FQN"
assert_installed_version "$CURRENT_VERSION"
brew_run uninstall --cask "$CASK_FQN"
[[ ! -e "$APP_DIR/Canis97.app" ]] || fail 'uninstall left Canis97.app in isolated app directory'

printf 'Homebrew lifecycle verification completed: %s\n' "$REPORT_PATH"
