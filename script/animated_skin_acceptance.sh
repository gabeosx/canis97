#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
template="$repo_root/.planning/phases/05-public-release-compatibility-support/05-ANIMATED-SKIN-EVIDENCE-TEMPLATE.md"
lock_path="$repo_root/.animation-acceptance.lock"

authorized=0
app_path=""
output_dir=""
owned_pid=""
run_status="incomplete"
lock_held=0

usage() {
  cat <<'USAGE'
Usage: animated_skin_acceptance.sh --authorized-release-run --app PATH --output DIR

Collects offline-only optimized animation evidence. This command refuses to
launch unless the exact authorization flag and one AnimationAcceptance app
bundle path are supplied. It never signs in to, or contacts, SiriusXM.
USAGE
}

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 2
}

hook() {
  local candidate="${CANIS97_ACCEPTANCE_TEST_HOOKS:-}/$1"
  [[ -n "${CANIS97_ACCEPTANCE_TEST_HOOKS:-}" && -x "$candidate" ]] || return 1
  printf '%s\n' "$candidate"
}

record() {
  printf '%s\n' "$1" >> "$output_dir/events.log"
}

write_unavailable() {
  local stage="$1" reason="$2"
  printf 'not available: %s\n' "$reason" > "$output_dir/$stage.txt"
}

terminate_owned_pid() {
  [[ -n "$owned_pid" ]] || return 0
  local terminate_hook
  if terminate_hook="$(hook terminate_owned_pid)"; then
    "$terminate_hook" "$owned_pid" || true
  else
    kill -TERM "$owned_pid" 2>/dev/null || true
  fi
  record "terminated-owned-pid"
  owned_pid=""
}

finish() {
  local status="$?"
  trap - EXIT INT TERM HUP
  if [[ -n "$output_dir" && -d "$output_dir" ]]; then
    if (( status != 0 )); then
      run_status="incomplete"
    fi
    # A successful evidence collection still owns the launched app process.
    # Never leave it running after the harness returns; only this tracked PID
    # may be signalled, and no existing process is ever attached to.
    terminate_owned_pid
    printf '%s\n' "$run_status" > "$output_dir/FINAL_STATUS"
    printf 'exit_status=%s\n' "$status" >> "$output_dir/build-context.txt"
    (cd "$output_dir" && find . -type f ! -name ARTIFACTS.sha256 -exec shasum -a 256 {} +) > "$output_dir/ARTIFACTS.sha256" 2>/dev/null || true
  fi
  if (( lock_held == 1 )); then
    rmdir "$lock_path" 2>/dev/null || true
  fi
  exit "$status"
}

trap finish EXIT
trap 'exit 130' INT TERM HUP

while (( $# > 0 )); do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --authorized-release-run)
      authorized=1
      ;;
    --app)
      (( $# >= 2 )) || fail "--app requires a path"
      app_path="$2"
      shift
      ;;
    --output)
      (( $# >= 2 )) || fail "--output requires a directory"
      output_dir="$2"
      shift
      ;;
    *)
      fail "unknown argument"
      ;;
  esac
  shift
done

(( authorized == 1 )) || fail "--authorized-release-run is required before any launch"
[[ -n "$app_path" && -n "$output_dir" ]] || fail "--app and --output are required"
[[ -d "$app_path" && ! -L "$app_path" ]] || fail "--app must name one non-symlink .app bundle"
[[ "$app_path" == *.app ]] || fail "--app must name a .app bundle"
app_path="$(cd "$app_path" && pwd -P)"
case "$app_path" in
  */Build/Products/AnimationAcceptance/Canis97.app) ;;
  *) fail "--app must name the exact AnimationAcceptance product" ;;
esac

app_binary="$app_path/Contents/MacOS/Canis97"
app_info="$app_path/Contents/Info.plist"
[[ -x "$app_binary" && -f "$app_info" ]] || fail "AnimationAcceptance app bundle is incomplete"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_info" 2>/dev/null || true)" == "com.canis97.player" ]] || fail "app bundle identity is not Canis97"
[[ ! -e "$output_dir" ]] || fail "--output must be a new evidence directory"
[[ -f "$template" ]] || fail "evidence template is missing"

require_terminal_readiness() {
  local readiness_hook acknowledgement
  if readiness_hook="$(hook readiness)"; then
    acknowledgement="$("$readiness_hook")" || fail "terminal-control readiness cannot be proven"
  else
    [[ -t 0 && -t 1 ]] || fail "interactive stdin and stdout are required before launch"
    printf 'Type ready to confirm terminal control before launching Canis97: ' >&1
    IFS= read -r acknowledgement || fail "terminal-control readiness cannot be proven"
  fi
  [[ "$acknowledgement" == "ready" ]] || fail "terminal-control acknowledgement must be exactly ready"
}

# This gate deliberately precedes every runtime side effect: no process
# preflight, lock, evidence directory, or launch happens until an operator can
# prove the terminal remains under control.
require_terminal_readiness

if pgrep -x Canis97 >/dev/null 2>&1; then
  fail "an existing Canis97 process is running"
fi
mkdir "$lock_path" 2>/dev/null || fail "another animation acceptance run owns the repository lock"
lock_held=1
mkdir -p "$output_dir"
cp "$template" "$output_dir/EVIDENCE.md"
: > "$output_dir/events.log"

{
  printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  sw_vers 2>/dev/null || true
  xcodebuild -version 2>/dev/null || true
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_info" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_info" 2>/dev/null || true
  shasum -a 256 "$app_binary" | awk '{ print $1 "  Canis97" }'
} > "$output_dir/build-context.txt"
record "preflights-passed"

launch_hook="$(hook launch_app || true)"
if [[ -n "$launch_hook" ]]; then
  owned_pid="$($launch_hook "$app_binary")"
else
  env CANIS97_OFFLINE_REVIEW_MODE=1 \
      CANIS97_OFFLINE_REVIEW_SURFACE=compactPopulated \
      CANIS97_OFFLINE_REVIEW_APPEARANCE=orbitDeck \
      "$app_binary" > "$output_dir/app.stdout.log" 2> "$output_dir/app.stderr.log" &
  owned_pid="$!"
fi
[[ "$owned_pid" =~ ^[0-9]+$ ]] || fail "launch did not return one owned PID"
record "launch-once"

collect_stage() {
  local stage="$1" stage_hook
  record "stage:$stage"
  if stage_hook="$(hook "collect_$stage")"; then
    "$stage_hook" "$owned_pid" > "$output_dir/$stage.txt"
    return
  fi
  case "$stage" in
    cpu-memory)
      ps -o pid=,%cpu=,rss= -p "$owned_pid" > "$output_dir/$stage.txt" 2>/dev/null || write_unavailable "$stage" "process sample unavailable"
      ;;
    gpu-windowserver)
      write_unavailable "$stage" "requires an operator-managed GPU or WindowServer trace"
      ;;
    hitch-responsiveness)
      write_unavailable "$stage" "requires an operator-managed Instruments hitches trace; screenshots are excluded"
      ;;
    energy)
      write_unavailable "$stage" "requires an operator-managed energy trace with appropriate privileges"
      ;;
  esac
}

for stage in cpu-memory gpu-windowserver hitch-responsiveness energy; do
  collect_stage "$stage"
done

prompt_scenario() {
  local scenario="$1" prompt_hook
  record "prompt:$scenario"
  if prompt_hook="$(hook prompt_scenario)"; then
    "$prompt_hook" "$scenario"
  else
    read -r -p "Verify $scenario, record the result in EVIDENCE.md, then press Return: " _
  fi
}

for scenario in \
  "Orbit Deck visual quality and native controls" \
  "Signal Garden visual quality and native controls" \
  "Native static recovery" \
  "Reduce Motion static fallback" \
  "hide then show lifecycle suspension" \
  "inactive then active lifecycle suspension" \
  "pause then play lifecycle suspension"; do
  prompt_scenario "$scenario"
done

if interrupt_hook="$(hook interrupt_after_launch || true)"; [[ -n "$interrupt_hook" ]]; then
  "$interrupt_hook" "$owned_pid"
  exit 130
fi

run_status="complete"
record "completed"
