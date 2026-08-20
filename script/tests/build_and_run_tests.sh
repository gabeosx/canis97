#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="$ROOT_DIR/script/lib/single_instance_launcher.sh"

if [[ ! -f "$HELPER" ]]; then
  echo "FAIL: single-instance launcher helper is missing" >&2
  exit 1
fi

# This suite supplies every lifecycle hook explicitly. It must never reach a
# real process inspector, terminator, opener, logger, or app binary.
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sirius-launcher-tests.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
STATE="$TEST_ROOT/state"
HOOKS="$TEST_ROOT/hooks"
mkdir -p "$STATE" "$HOOKS"

cat > "$HOOKS/pgrep" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
printf 'pgrep\n' >> "$SIL_TEST_STATE/events"
if [[ "${SIL_TEST_OPEN_MODE:-exact}" == "delayed-one" && -f "$SIL_TEST_STATE/opened" ]]; then
  sleep_calls=0
  [[ -f "$SIL_TEST_STATE/sleep-calls" ]] && sleep_calls=$(cat "$SIL_TEST_STATE/sleep-calls")
  if (( sleep_calls >= ${SIL_TEST_DELAYED_READY_AFTER:-1} )); then
    printf '401:%s\n' "$SIL_TEST_EXACT_BINARY" > "$SIL_TEST_STATE/pids"
  fi
fi
[[ -s "$SIL_TEST_STATE/pids" ]] || exit 1
cut -d: -f1 "$SIL_TEST_STATE/pids"
HOOK

cat > "$HOOKS/terminate" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
printf 'terminate\n' >> "$SIL_TEST_STATE/events"
calls_file="$SIL_TEST_STATE/terminate-calls"
calls=0
[[ -f "$calls_file" ]] && calls=$(cat "$calls_file")
calls=$((calls + 1))
printf '%s' "$calls" > "$calls_file"
if [[ "${SIL_TEST_STICKY:-0}" != "1" || "$calls" -gt 1 ]]; then
  : > "$SIL_TEST_STATE/pids"
fi
HOOK

cat > "$HOOKS/path" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
printf 'path:%s\n' "$1" >> "$SIL_TEST_STATE/events"
if [[ "${SIL_TEST_PATH_MODE:-exact}" == "missing" ]]; then
  exit 1
fi
awk -F: -v pid="$1" '$1 == pid { print substr($0, length(pid) + 2); exit }' "$SIL_TEST_STATE/pids"
HOOK

cat > "$HOOKS/lsof" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
printf 'lsof:%s\n' "$*" >> "$SIL_TEST_STATE/events"

pid=""
while (( $# > 0 )); do
  case "$1" in
    -p)
      shift
      pid="$1"
      ;;
  esac
  shift
done

case "${SIL_TEST_LSOF_MODE:-exact}" in
  exact)
    printf 'p%s\nn%s\n' "$pid" "$SIL_TEST_EXACT_BINARY"
    ;;
  wrong-path)
    printf 'p%s\nn%s\n' "$pid" "$SIL_TEST_WRONG_BINARY"
    ;;
  multiple-mappings)
    printf 'p%s\nn%s.debug.dylib\nn%s\n' "$pid" "$SIL_TEST_EXACT_BINARY" "$SIL_TEST_EXACT_BINARY"
    ;;
  missing)
    printf 'p%s\n' "$pid"
    ;;
  *)
    exit 91
    ;;
esac
HOOK

cat > "$HOOKS/open" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
printf 'open:%s\n' "$1" >> "$SIL_TEST_STATE/events"
count=$(wc -l < "$SIL_TEST_STATE/opens" | tr -d ' ')
printf '%s\n' "$1" >> "$SIL_TEST_STATE/opens"
case "${SIL_TEST_OPEN_MODE:-exact}" in
  exact)
    printf '401:%s\n' "$SIL_TEST_EXACT_BINARY" > "$SIL_TEST_STATE/pids"
    if [[ "${SIL_TEST_HOLD_OPEN:-0}" == "1" ]]; then
      while [[ ! -f "$SIL_TEST_STATE/release-open" ]]; do :; done
    fi
    ;;
  delayed-one)
    touch "$SIL_TEST_STATE/opened"
    : > "$SIL_TEST_STATE/pids"
    ;;
  zero) : > "$SIL_TEST_STATE/pids" ;;
  two) printf '401:%s\n402:%s\n' "$SIL_TEST_EXACT_BINARY" "$SIL_TEST_EXACT_BINARY" > "$SIL_TEST_STATE/pids" ;;
  wrong-path) printf '401:/tmp/not-the-built-binary\n' > "$SIL_TEST_STATE/pids" ;;
  fail) exit 9 ;;
  *) exit 91 ;;
esac
HOOK

cat > "$HOOKS/sleep" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
printf 'sleep\n' >> "$SIL_TEST_STATE/events"
sleep_calls_file="$SIL_TEST_STATE/sleep-calls"
sleep_calls=0
[[ -f "$sleep_calls_file" ]] && sleep_calls=$(cat "$sleep_calls_file")
printf '%s' "$((sleep_calls + 1))" > "$sleep_calls_file"
HOOK

cat > "$HOOKS/report" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  lock-acquisition-failed|launcher-configuration-missing|build-command-failed|build-output-missing|telemetry-start-failed|launch-wrapper-no-stage-failed|prelaunch-cleanup-failed|launch-command-failed|zero-after-open|multiple-after-open|unexpected-count-after-open|pid-selection-failed|mapped-path-missing|mapped-path-mismatch) ;;
  *) exit 92 ;;
esac
printf '%s\n' "$1" >> "$SIL_TEST_STATE/reports"
HOOK

cat > "$HOOKS/xcodebuild" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
printf 'xcodebuild\n' >> "$SIL_TEST_STATE/events"
case "${SIL_TEST_BUILD_MODE:-success}" in
  success)
    mkdir -p "$(dirname "$SIL_TEST_EXACT_BINARY")"
    : > "$SIL_TEST_EXACT_BINARY"
    chmod +x "$SIL_TEST_EXACT_BINARY"
    ;;
  fail)
    exit 23
    ;;
  missing-output)
    ;;
  *)
    exit 91
    ;;
esac
HOOK

cat > "$HOOKS/log" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
printf 'telemetry\n' >> "$SIL_TEST_STATE/events"
exit 0
HOOK

cat > "$HOOKS/kill" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
printf 'kill:%s\n' "$*" >> "$SIL_TEST_STATE/events"
if [[ "${SIL_TEST_KILL_MODE:-success}" == "start-fail" && "${1:-}" == "-0" ]]; then
  exit 1
fi
exit 0
HOOK

chmod +x "$HOOKS"/*

reset_state() {
  rm -rf "$TEST_ROOT/SiriusMac.app"
  : > "$STATE/pids"
  : > "$STATE/events"
  : > "$STATE/opens"
  : > "$STATE/reports"
  printf '0' > "$STATE/terminate-calls"
  printf '0' > "$STATE/sleep-calls"
  rm -f "$STATE/release-open" "$STATE/opened"
  unset SIL_TEST_STICKY
  unset SIL_TEST_HOLD_OPEN
  unset SIL_TEST_LSOF_MODE
  unset SIL_TEST_PATH_MODE
  unset SIL_TEST_DELAYED_READY_AFTER
  unset SIL_TEST_BUILD_MODE
  unset SIL_TEST_KILL_MODE
  export SIL_TEST_OPEN_MODE=exact
}

assert_eq() {
  local expected="$1" actual="$2" note="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: $note (expected '$expected', got '$actual')" >&2
    exit 1
  fi
}

assert_file_empty() {
  local file="$1" note="$2"
  if [[ -s "$file" ]]; then
    echo "FAIL: $note" >&2
    exit 1
  fi
}

configure_fake_hooks() {
  export SIL_TEST_STATE="$STATE"
  export SIL_TEST_EXACT_BINARY="$TEST_ROOT/SiriusMac.app/Contents/MacOS/SiriusMac"
  export SIL_TEST_WRONG_BINARY="$TEST_ROOT/SiriusMac.app/Contents/MacOS/NotSiriusMac"
  export SIL_TEST_HELPER="$HELPER"
  export SIL_APP_NAME="SiriusMac"
  export SIL_APP_BUNDLE="$TEST_ROOT/SiriusMac.app"
  export SIL_APP_BINARY="$SIL_TEST_EXACT_BINARY"
  export SIL_LOCK_PATH="$TEST_ROOT/launcher.lock"
  export SIL_DRAIN_ATTEMPTS=2
  export SIL_LOCK_ATTEMPTS=2
  export SIL_PGREP="$HOOKS/pgrep"
  export SIL_TERMINATE_ALL="$HOOKS/terminate"
  export SIL_PID_PATH="$HOOKS/path"
  export SIL_OPEN="$HOOKS/open"
  export SIL_SLEEP="$HOOKS/sleep"
  export SIL_INVARIANT_REPORT="$HOOKS/report"
}

source "$HELPER"
configure_fake_hooks
RESOLVER="$ROOT_DIR/script/lib/resolve_process_binary.sh"

# The test guard rejects accidental fallback to system process or launch tools.
if rg -n --fixed-strings '/usr/bin/open' "$HELPER" >/dev/null ||
   rg -n -e '(^|[[:space:];])pkill([[:space:];]|$)|(^|[[:space:];])pgrep([[:space:];]|$)' "$HELPER" >/dev/null; then
  echo "FAIL: helper may not invoke real process or launch commands" >&2
  exit 1
fi
if ! rg -q "trap 'sil_release_lock' EXIT" "$HELPER" ||
   ! rg -q "sil_close_all_and_wait.*exit 130" "$HELPER"; then
  echo "FAIL: lifecycle helper must release its lock and clean fake copies on interruption" >&2
  exit 1
fi

run_launch() {
  single_instance_launch
}

reset_state
run_launch
assert_eq 1 "$(wc -l < "$STATE/opens" | tr -d ' ')" "exact launch opens once"
assert_eq "401:$SIL_TEST_EXACT_BINARY" "$(cat "$STATE/pids")" "exact binary survives"
assert_file_empty "$STATE/reports" "exact launch emits no failure stage"

reset_state
export SIL_TEST_OPEN_MODE=delayed-one
export SIL_TEST_DELAYED_READY_AFTER=1
run_launch
assert_eq 1 "$(wc -l < "$STATE/opens" | tr -d ' ')" "delayed exact launch opens once"
assert_eq "401:$SIL_TEST_EXACT_BINARY" "$(cat "$STATE/pids")" "delayed exact process is accepted"
assert_file_empty "$STATE/reports" "delayed exact launch emits no failure stage"

reset_state
export SIL_PID_PATH="$RESOLVER"
export SIL_LSOF="$HOOKS/lsof"
export SIL_TEST_LSOF_MODE=multiple-mappings
run_launch
assert_eq "401:$SIL_TEST_EXACT_BINARY" "$(cat "$STATE/pids")" "multiple text mappings retain the exact executable"
assert_file_empty "$STATE/reports" "multiple text mappings emit no failure stage"
export SIL_PID_PATH="$HOOKS/path"
unset SIL_LSOF

reset_state
printf '111:%s\n' "$SIL_TEST_EXACT_BINARY" > "$STATE/pids"
run_launch
assert_eq 1 "$(wc -l < "$STATE/opens" | tr -d ' ')" "drained old process opens once"
assert_eq "401:$SIL_TEST_EXACT_BINARY" "$(cat "$STATE/pids")" "new exact process survives"

reset_state
printf '111:%s\n' "$SIL_TEST_EXACT_BINARY" > "$STATE/pids"
export SIL_TEST_STICKY=1
if run_launch; then
  echo "FAIL: sticky old process must fail" >&2
  exit 1
fi
assert_eq 0 "$(wc -l < "$STATE/opens" | tr -d ' ')" "sticky old process opens nothing"
grep -qx 'terminate' "$STATE/events"
assert_eq 'prelaunch-cleanup-failed' "$(cat "$STATE/reports")" "sticky old process reports its fixed stage"
unset SIL_TEST_STICKY

reset_state
export SIL_TEST_HOLD_OPEN=1
run_launch &
launch_pid=$!
while ! grep -q '^open:' "$STATE/events"; do :; done
if run_launch; then
  echo "FAIL: concurrent lock contender must not launch" >&2
  exit 1
fi
assert_eq 1 "$(wc -l < "$STATE/opens" | tr -d ' ')" "concurrent invocations open once"
touch "$STATE/release-open"
wait "$launch_pid"
unset SIL_TEST_HOLD_OPEN

for mode in zero two wrong-path; do
  reset_state
  export SIL_TEST_OPEN_MODE="$mode"
  if run_launch; then
    echo "FAIL: post-launch $mode invariant must fail" >&2
    exit 1
  fi
  assert_file_empty "$STATE/pids" "post-launch $mode is cleaned"
  grep -qx 'terminate' "$STATE/events"
  case "$mode" in
    zero) expected_stage='zero-after-open' ;;
    two) expected_stage='multiple-after-open' ;;
    wrong-path) expected_stage='mapped-path-mismatch' ;;
  esac
  assert_eq "$expected_stage" "$(cat "$STATE/reports")" "post-launch $mode reports its fixed stage"
done

reset_state
export SIL_TEST_OPEN_MODE=fail
if run_launch; then
  echo "FAIL: failed open command must fail" >&2
  exit 1
fi
assert_eq 'launch-command-failed' "$(cat "$STATE/reports")" "failed open command reports its fixed stage"

# A failure before the opener must not be relabeled as an open-command
# failure. These synthetic checks run only through the fake hooks above.
wrapper_without_stage() {
  return 17
}

reset_state
if single_instance_with_lock wrapper_without_stage; then
  echo "FAIL: wrapper failure without a stage must fail" >&2
  exit 1
fi
assert_eq 'launch-wrapper-no-stage-failed' "$(cat "$STATE/reports")" "wrapper preserves an absent inner stage"

reset_state
mkdir "$SIL_LOCK_PATH"
export SIL_LOCK_ATTEMPTS=1
if single_instance_with_lock true; then
  echo "FAIL: unavailable launch lock must fail" >&2
  exit 1
fi
assert_eq 'lock-acquisition-failed' "$(cat "$STATE/reports")" "lock failure reports its fixed stage"
rmdir "$SIL_LOCK_PATH"
export SIL_LOCK_ATTEMPTS=2

reset_state
export SIL_TEST_PATH_MODE=missing
if run_launch; then
  echo "FAIL: missing mapped executable must fail" >&2
  exit 1
fi
assert_file_empty "$STATE/pids" "missing mapped executable is cleaned"
assert_eq 'mapped-path-missing' "$(cat "$STATE/reports")" "missing mapped executable reports its fixed stage"

reset_state
saved_open="$SIL_OPEN"
unset SIL_OPEN
if run_launch; then
  echo "FAIL: missing launch configuration must fail" >&2
  exit 1
fi
assert_eq 'launcher-configuration-missing' "$(cat "$STATE/reports")" "missing launch configuration reports its fixed stage"
export SIL_OPEN="$saved_open"

# The resolver must read the mapped text executable, never argv[0]. The
# initial structural check makes the red phase safe: it avoids executing the
# old hard-coded `/bin/ps` implementation against the host process table.
if rg -q '/bin/ps.*command=' "$RESOLVER" || ! rg -q 'SIL_LSOF' "$RESOLVER"; then
  echo "FAIL: process resolver must use an injectable mapped-text executable query" >&2
  exit 1
fi

reset_state
actual="$(SIL_LSOF="$HOOKS/lsof" "$RESOLVER" 401)"
assert_eq "$SIL_TEST_EXACT_BINARY" "$actual" "resolver returns mapped executable path"
assert_eq 'lsof:-a -p 401 -d txt -Fn' "$(cat "$STATE/events")" "resolver queries only the mapped text executable"

reset_state
export SIL_TEST_LSOF_MODE=wrong-path
actual="$(SIL_LSOF="$HOOKS/lsof" "$RESOLVER" 401)"
assert_eq "$SIL_TEST_WRONG_BINARY" "$actual" "resolver does not substitute argv text"

reset_state
export SIL_TEST_LSOF_MODE=multiple-mappings
actual="$(SIL_LSOF="$HOOKS/lsof" "$RESOLVER" 401 "$SIL_TEST_EXACT_BINARY")"
assert_eq "$SIL_TEST_EXACT_BINARY" "$actual" "resolver selects the expected executable from multiple text mappings"

reset_state
export SIL_TEST_LSOF_MODE=missing
if SIL_LSOF="$HOOKS/lsof" "$RESOLVER" 401 >/dev/null; then
  echo "FAIL: resolver must fail closed when no mapped executable is available" >&2
  exit 1
fi

# This child shell is deliberately independent from this test's conditional
# context. With `set -e`, a launch stage that fails before a later side effect
# must terminate the wrapper rather than being converted to a zero status.
cat > "$TEST_ROOT/failure-propagation-probe.sh" <<'PROBE'
#!/usr/bin/env bash
set -euo pipefail
source "$SIL_TEST_HELPER"

failing_stage() {
  false
  printf 'continued\n' > "$SIL_TEST_STATE/failure-stage-continued"
}

single_instance_with_lock failing_stage
PROBE
chmod +x "$TEST_ROOT/failure-propagation-probe.sh"

reset_state
if "$TEST_ROOT/failure-propagation-probe.sh"; then
  echo "FAIL: lock wrapper must preserve launch-stage failure" >&2
  exit 1
fi
if [[ -e "$STATE/failure-stage-continued" ]]; then
  echo "FAIL: lock wrapper continued after a failing launch stage" >&2
  exit 1
fi
if [[ -d "$SIL_LOCK_PATH" ]]; then
  echo "FAIL: lock wrapper did not release its lock after a failing launch stage" >&2
  exit 1
fi

reset_state
single_instance_build_only true
assert_eq 0 "$(wc -l < "$STATE/events" | tr -d ' ')" "build-only makes no lifecycle calls"

reset_state
single_instance_guard_app_host true
assert_file_empty "$STATE/pids" "guard success leaves zero"

reset_state
if single_instance_guard_app_host false; then
  echo "FAIL: guard preserves wrapped failure" >&2
  exit 1
fi
assert_file_empty "$STATE/pids" "guard failure leaves zero"

reset_state
if single_instance_guard_app_host bash -c 'printf "999:%s\\n" "$SIL_TEST_EXACT_BINARY" > "$SIL_TEST_STATE/pids"'; then
  echo "FAIL: guard leak must fail" >&2
  exit 1
fi
assert_file_empty "$STATE/pids" "guard leak is cleaned"

echo "PASS: fake single-instance launcher matrix"

# The production entry point is checked structurally here.  Executing a run
# mode is intentionally forbidden during this autonomous plan.
BUILD_SCRIPT="$ROOT_DIR/script/build_and_run.sh"
if ! rg -q 'source .*single_instance_launcher\.sh' "$BUILD_SCRIPT" ||
   ! rg -q 'single_instance_with_lock build_and_launch' "$BUILD_SCRIPT" ||
   ! rg -q 'single_instance_build_only build_exact_bundle' "$BUILD_SCRIPT"; then
  echo "FAIL: all build/run modes must route through the single-instance helper" >&2
  exit 1
fi
if rg -n --fixed-strings 'open -n' "$BUILD_SCRIPT" >/dev/null ||
   rg -n -e '(^|[[:space:];])pkill([[:space:];]|$)|(^|[[:space:];])pgrep([[:space:];]|$)' "$BUILD_SCRIPT" >/dev/null; then
  echo "FAIL: build/run entry point retains a duplicate-prone lifecycle command" >&2
  exit 1
fi

# The outer build/telemetry wrapper has to classify failures before it reaches
# the helper. Keep this structural RED gate ahead of source-loading the script,
# so an older script cannot invoke a real compiler or telemetry process.
if ! rg -q 'SIL_XCODEBUILD' "$BUILD_SCRIPT" ||
   ! rg -q 'SIL_LOG' "$BUILD_SCRIPT" ||
   ! rg -q 'launch-wrapper-no-stage-failed' "$HELPER"; then
  echo "FAIL: build wrapper must expose injectable early-stage hooks and an explicit no-stage label" >&2
  exit 1
fi

# Source the entry point only after the structural guard above. All external
# commands are replaced with fixture hooks, so these checks cannot build,
# inspect, launch, or control a production process.
export SIL_BUILD_AND_RUN_SOURCE_ONLY=1
source "$BUILD_SCRIPT"
unset SIL_BUILD_AND_RUN_SOURCE_ONLY
APP_BUNDLE="$TEST_ROOT/SiriusMac.app"
APP_BINARY="$SIL_TEST_EXACT_BINARY"
export SIL_APP_NAME="SiriusMac"
export SIL_APP_BUNDLE="$APP_BUNDLE"
export SIL_APP_BINARY="$APP_BINARY"
export SIL_PGREP="$HOOKS/pgrep"
export SIL_TERMINATE_ALL="$HOOKS/terminate"
export SIL_PID_PATH="$HOOKS/path"
export SIL_OPEN="$HOOKS/open"
export SIL_SLEEP="$HOOKS/sleep"
export SIL_INVARIANT_REPORT="$HOOKS/report"
export SIL_XCODEBUILD="$HOOKS/xcodebuild"
export SIL_LOG="$HOOKS/log"
export SIL_KILL="$HOOKS/kill"

run_build_wrapper() {
  single_instance_with_lock build_and_launch "$1"
}

reset_state
export SIL_TEST_BUILD_MODE=fail
if run_build_wrapper run; then
  echo "FAIL: failed build command must fail" >&2
  exit 1
fi
assert_eq 0 "$(wc -l < "$STATE/opens" | tr -d ' ')" "failed build opens nothing"
assert_eq 'build-command-failed' "$(cat "$STATE/reports")" "failed build reports its fixed stage"

reset_state
export SIL_TEST_BUILD_MODE=missing-output
if run_build_wrapper run; then
  echo "FAIL: missing build output must fail" >&2
  exit 1
fi
assert_eq 0 "$(wc -l < "$STATE/opens" | tr -d ' ')" "missing build output opens nothing"
assert_eq 'build-output-missing' "$(cat "$STATE/reports")" "missing build output reports its fixed stage"

reset_state
export SIL_TEST_BUILD_MODE=success
export SIL_TEST_KILL_MODE=start-fail
if run_build_wrapper --telemetry; then
  echo "FAIL: failed telemetry start must fail" >&2
  exit 1
fi
assert_eq 0 "$(wc -l < "$STATE/opens" | tr -d ' ')" "failed telemetry start opens nothing"
assert_eq 'telemetry-start-failed' "$(cat "$STATE/reports")" "failed telemetry start reports its fixed stage"

reset_state
export SIL_TEST_BUILD_MODE=success
launch_after_build() {
  return 31
}
if run_build_wrapper run; then
  echo "FAIL: unstaged launch-wrapper failure must fail" >&2
  exit 1
fi
assert_eq 'launch-wrapper-no-stage-failed' "$(cat "$STATE/reports")" "wrapper never relabels an absent stage as an open failure"
launch_after_build() {
  single_instance_launch_locked
}

reset_state
export SIL_TEST_BUILD_MODE=success
run_build_wrapper run
assert_eq 1 "$(wc -l < "$STATE/opens" | tr -d ' ')" "successful fake build launches exactly once"
assert_file_empty "$STATE/reports" "successful fake build emits no failure stage"

echo "PASS: build/run routing contract"
