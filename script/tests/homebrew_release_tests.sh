#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RENDER_SCRIPT="$ROOT_DIR/script/render_homebrew_cask.sh"
VERIFY_SCRIPT="$ROOT_DIR/script/verify_homebrew_release.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

test -x "$VERIFY_SCRIPT" || fail 'Homebrew lifecycle verifier is missing or not executable'

cask_output="$(bash "$RENDER_SCRIPT" 1.2.3 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa gabeosx/canis97)"
grep -Fq 'url "https://github.com/gabeosx/canis97/releases/download/v#{version}/Canis97-#{version}-arm64.dmg"' <<<"$cask_output" || fail 'cask URL is not immutable and versioned'
grep -Fq 'depends_on arch: :arm64' <<<"$cask_output" || fail 'cask omitted arm64 requirement'
grep -Fq 'depends_on macos: ">= :tahoe"' <<<"$cask_output" || fail 'cask omitted current macOS requirement'
grep -Fq 'app "Canis97.app"' <<<"$cask_output" || fail 'cask omitted app stanza'
grep -Fq 'zap trash:' <<<"$cask_output" || fail 'cask omitted cleanup stanza'
bash "$RENDER_SCRIPT" 1.2.3 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA gabeosx/canis97 >/dev/null 2>&1 && fail 'renderer accepted uppercase SHA-256'
bash "$RENDER_SCRIPT" 1.2.3 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 'gabeosx/canis97"; system("bad")' >/dev/null 2>&1 && fail 'renderer accepted unsafe repository interpolation'

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/canis97-homebrew-contract.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT
PRIOR_ARCHIVE="$TEMP_ROOT/Canis97-1.0.0-arm64.dmg"
CURRENT_ARCHIVE="$TEMP_ROOT/Canis97-1.1.0-arm64.dmg"
COMMAND_LOG="$TEMP_ROOT/commands.log"
: > "$PRIOR_ARCHIVE"
printf current > "$CURRENT_ARCHIVE"

fake_brew() {
  printf 'brew %s\n' "$*" >> "$CANIS97_TEST_COMMAND_LOG"
  local operation="$1"
  shift
  [[ "${CANIS97_FAKE_INTERRUPT:-}" != "$operation" ]] || return 27
  case "$operation" in
    tap)
      [[ "$1" == gabeosx/homebrew-tap && "$2" == "$CANIS97_TEST_TAP_DIR" ]] || return 12
      ;;
    install|upgrade)
      local appdir=""
      while [[ "$#" -gt 0 ]]; do
        if [[ "$1" == --appdir ]]; then
          appdir="$2"
          shift 2
        else
          shift
        fi
      done
      local version
      version="$(awk -F'"' '/^  version / { print $2 }' "$CANIS97_TEST_TAP_DIR/Casks/canis97.rb")"
      mkdir -p "$appdir/Canis97.app/Contents"
      printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>'"$version"'</string></dict></plist>' > "$appdir/Canis97.app/Contents/Info.plist"
      ;;
    uninstall)
      [[ "${CANIS97_FAKE_LEAVE_RESIDUE:-}" != true ]] && rm -rf "$CANIS97_TEST_APP_DIR/Canis97.app"
      ;;
    *) return 13 ;;
  esac
}

export -f fake_brew
CANIS97_TEST_COMMAND_LOG="$COMMAND_LOG" \
CANIS97_TEST_TAP_DIR="$TEMP_ROOT/work/tap" \
CANIS97_TEST_APP_DIR="$TEMP_ROOT/work/apps" \
CANIS97_HOMEBREW_BIN=fake_brew \
CANIS97_RUN_HOMEBREW_INTEGRATION=true \
bash "$VERIFY_SCRIPT" \
  --cask-fqn gabeosx/homebrew-tap/canis97 \
  --prior-archive "$PRIOR_ARCHIVE" \
  --current-archive "$CURRENT_ARCHIVE" \
  --work-dir "$TEMP_ROOT/work" >/dev/null

grep -Fxq 'brew install --cask --appdir /private' "$COMMAND_LOG" && fail 'unexpected command truncation'
grep -Fq 'brew tap gabeosx/homebrew-tap ' "$COMMAND_LOG" || fail 'verifier did not use the fully-qualified tap'
grep -Fq 'brew install --cask --appdir ' "$COMMAND_LOG" || fail 'verifier did not install into isolated app directory'
test "$(grep -Fc 'brew upgrade --cask --appdir ' "$COMMAND_LOG")" -eq 2 || fail 'verifier did not perform upgrade and repeated upgrade'
grep -Fq 'brew uninstall --cask gabeosx/homebrew-tap/canis97' "$COMMAND_LOG" || fail 'verifier did not uninstall fully-qualified cask'
grep -Fq '"status":"clean","residue":"none"' "$TEMP_ROOT/work/homebrew-lifecycle-report.json" || fail 'clean lifecycle report missing'

CANIS97_RUN_HOMEBREW_INTEGRATION=true CANIS97_HOMEBREW_BIN=fake_brew \
  bash "$VERIFY_SCRIPT" --cask-fqn gabeosx/homebrew-tap --prior-archive "$PRIOR_ARCHIVE" --current-archive "$CURRENT_ARCHIVE" --work-dir "$TEMP_ROOT/bad-fqn" >/dev/null 2>&1 && fail 'verifier accepted broad cask target'
CANIS97_HOMEBREW_BIN=fake_brew \
  bash "$VERIFY_SCRIPT" --cask-fqn gabeosx/homebrew-tap/canis97 --prior-archive "$PRIOR_ARCHIVE" --current-archive "$CURRENT_ARCHIVE" --work-dir "$TEMP_ROOT/no-gate" >/dev/null 2>&1 && fail 'verifier ran without explicit integration gate'
CANIS97_RUN_HOMEBREW_INTEGRATION=true CANIS97_HOMEBREW_BIN=fake_brew \
  bash "$VERIFY_SCRIPT" --cask-fqn gabeosx/homebrew-tap/canis97 --prior-archive "$PRIOR_ARCHIVE" --current-archive "$CURRENT_ARCHIVE" --work-dir "$TEMP_ROOT/unsafe\"report" >/dev/null 2>&1 && fail 'verifier accepted unsafe report path'

INVALID_ARCHIVE="$TEMP_ROOT/Canis97-latest-arm64.dmg"
: > "$INVALID_ARCHIVE"
CANIS97_RUN_HOMEBREW_INTEGRATION=true CANIS97_HOMEBREW_BIN=fake_brew \
  bash "$VERIFY_SCRIPT" --cask-fqn gabeosx/homebrew-tap/canis97 --prior-archive "$PRIOR_ARCHIVE" --current-archive "$INVALID_ARCHIVE" --work-dir "$TEMP_ROOT/bad-archive" >/dev/null 2>&1 && fail 'verifier accepted mutable/non-versioned archive'
OLDER_ARCHIVE="$TEMP_ROOT/Canis97-0.9.0-arm64.dmg"
: > "$OLDER_ARCHIVE"
CANIS97_RUN_HOMEBREW_INTEGRATION=true CANIS97_HOMEBREW_BIN=fake_brew \
  bash "$VERIFY_SCRIPT" --cask-fqn gabeosx/homebrew-tap/canis97 --prior-archive "$PRIOR_ARCHIVE" --current-archive "$OLDER_ARCHIVE" --work-dir "$TEMP_ROOT/version-regression" >/dev/null 2>&1 && fail 'verifier accepted non-upgrade archive pair'

CANIS97_TEST_COMMAND_LOG="$COMMAND_LOG" \
CANIS97_TEST_TAP_DIR="$TEMP_ROOT/interrupted/tap" \
CANIS97_TEST_APP_DIR="$TEMP_ROOT/interrupted/apps" \
CANIS97_HOMEBREW_BIN=fake_brew \
CANIS97_RUN_HOMEBREW_INTEGRATION=true \
CANIS97_FAKE_INTERRUPT=upgrade \
bash "$VERIFY_SCRIPT" \
  --cask-fqn gabeosx/homebrew-tap/canis97 \
  --prior-archive "$PRIOR_ARCHIVE" \
  --current-archive "$CURRENT_ARCHIVE" \
  --work-dir "$TEMP_ROOT/interrupted" >/dev/null 2>&1 && fail 'verifier accepted interrupted upgrade'
grep -Fq '"status":"failed"' "$TEMP_ROOT/interrupted/homebrew-lifecycle-report.json" || fail 'interruption report missing failure status'

CANIS97_TEST_COMMAND_LOG="$COMMAND_LOG" \
CANIS97_TEST_TAP_DIR="$TEMP_ROOT/residue/tap" \
CANIS97_TEST_APP_DIR="$TEMP_ROOT/residue/apps" \
CANIS97_HOMEBREW_BIN=fake_brew \
CANIS97_RUN_HOMEBREW_INTEGRATION=true \
CANIS97_FAKE_LEAVE_RESIDUE=true \
bash "$VERIFY_SCRIPT" \
  --cask-fqn gabeosx/homebrew-tap/canis97 \
  --prior-archive "$PRIOR_ARCHIVE" \
  --current-archive "$CURRENT_ARCHIVE" \
  --work-dir "$TEMP_ROOT/residue" >/dev/null 2>&1 && fail 'verifier accepted uninstall residue'
grep -Fq '"status":"failed"' "$TEMP_ROOT/residue/homebrew-lifecycle-report.json" || fail 'residue report missing failure status'

echo "PASS: Homebrew renderer and lifecycle contract"
