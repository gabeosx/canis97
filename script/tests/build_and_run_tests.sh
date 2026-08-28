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
case "${SIL_TEST_PATH_MODE:-exact}" in
  missing)
    exit 1
    ;;
  delayed-missing)
    calls_file="$SIL_TEST_STATE/path-calls"
    calls=0
    [[ -f "$calls_file" ]] && calls=$(cat "$calls_file")
    calls=$((calls + 1))
    printf '%s' "$calls" > "$calls_file"
    if (( calls <= ${SIL_TEST_RESOLVE_READY_AFTER:-1} )); then
      exit 1
    fi
    ;;
esac
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
    printf 'p%s\nftxt\nn%s\nftxt\nn/usr/lib/dyld\n' "$pid" "${SIL_TEST_MAPPED_BINARY:-$SIL_TEST_EXACT_BINARY}"
    ;;
  wrong-path)
    printf 'p%s\nftxt\nn%s\nftxt\nn/usr/lib/dyld\n' "$pid" "$SIL_TEST_WRONG_BINARY"
    ;;
  multiple-mappings)
    printf 'p%s\nftxt\nn%s.debug.dylib\nftxt\nn%s\nftxt\nn/usr/lib/dyld\n' "$pid" "${SIL_TEST_MAPPED_BINARY:-$SIL_TEST_EXACT_BINARY}" "${SIL_TEST_MAPPED_BINARY:-$SIL_TEST_EXACT_BINARY}"
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
  rm -rf "$TEST_ROOT/Canis97.app"
  : > "$STATE/pids"
  : > "$STATE/events"
  : > "$STATE/opens"
  : > "$STATE/reports"
  printf '0' > "$STATE/terminate-calls"
  printf '0' > "$STATE/sleep-calls"
  rm -f "$STATE/release-open" "$STATE/opened" "$STATE/path-calls"
  unset SIL_TEST_STICKY
  unset SIL_TEST_HOLD_OPEN
  unset SIL_TEST_LSOF_MODE
  unset SIL_TEST_MAPPED_BINARY
  unset SIL_TEST_PATH_MODE
  unset SIL_TEST_RESOLVE_READY_AFTER
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
  export SIL_TEST_EXACT_BINARY="$TEST_ROOT/Canis97.app/Contents/MacOS/Canis97"
  export SIL_TEST_WRONG_BINARY="$TEST_ROOT/Canis97.app/Contents/MacOS/NotCanis97"
  export SIL_TEST_HELPER="$HELPER"
  export SIL_APP_NAME="Canis97"
  export SIL_APP_BUNDLE="$TEST_ROOT/Canis97.app"
  export SIL_APP_BINARY="$SIL_TEST_EXACT_BINARY"
  export SIL_LOCK_PATH="$TEST_ROOT/launcher.lock"
  export SIL_DRAIN_ATTEMPTS=2
  export SIL_RESOLVE_ATTEMPTS=2
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
export SIL_TEST_PATH_MODE=delayed-missing
export SIL_TEST_RESOLVE_READY_AFTER=1
if ! run_launch; then
  echo "FAIL: delayed mapped executable must be retried without reopening" >&2
  exit 1
fi
assert_eq 1 "$(wc -l < "$STATE/opens" | tr -d ' ')" "delayed mapped executable launch opens once"
assert_eq "401:$SIL_TEST_EXACT_BINARY" "$(cat "$STATE/pids")" "delayed mapped executable is accepted"
assert_file_empty "$STATE/reports" "delayed mapped executable launch emits no failure stage"

reset_state
mkdir -p "$(dirname "$SIL_TEST_EXACT_BINARY")"
: > "$SIL_TEST_EXACT_BINARY"
chmod +x "$SIL_TEST_EXACT_BINARY"
export SIL_TEST_MAPPED_BINARY="$(/bin/realpath "$SIL_TEST_EXACT_BINARY")"
export SIL_PID_PATH="$RESOLVER"
export SIL_LSOF="$HOOKS/lsof"
export SIL_TEST_LSOF_MODE=multiple-mappings
run_launch
assert_eq "401:$SIL_TEST_EXACT_BINARY" "$(cat "$STATE/pids")" "multiple text mappings retain the exact executable"
assert_file_empty "$STATE/reports" "multiple text mappings emit no failure stage"
export SIL_PID_PATH="$HOOKS/path"
unset SIL_LSOF

reset_state
mkdir -p "$(dirname "$SIL_TEST_EXACT_BINARY")"
: > "$SIL_TEST_EXACT_BINARY"
chmod +x "$SIL_TEST_EXACT_BINARY"
export SIL_PID_PATH="$RESOLVER"
export SIL_LSOF="$HOOKS/lsof"
export SIL_TEST_LSOF_MODE=wrong-path
if run_launch; then
  echo "FAIL: wrong mapped executable must fail without reopening" >&2
  exit 1
fi
assert_eq 'mapped-path-mismatch' "$(cat "$STATE/reports")" "wrong mapped executable reports mismatch rather than missing"
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
mkdir -p "$(dirname "$SIL_TEST_EXACT_BINARY")"
: > "$SIL_TEST_EXACT_BINARY"
chmod +x "$SIL_TEST_EXACT_BINARY"
export SIL_TEST_MAPPED_BINARY="$(/bin/realpath "$SIL_TEST_EXACT_BINARY")"
actual="$(SIL_LSOF="$HOOKS/lsof" "$RESOLVER" 401 "$SIL_TEST_EXACT_BINARY")"
assert_eq "$SIL_TEST_EXACT_BINARY" "$actual" "resolver selects the expected executable from multiple text mappings"

reset_state
export SIL_TEST_LSOF_MODE=wrong-path
mkdir -p "$(dirname "$SIL_TEST_EXACT_BINARY")"
: > "$SIL_TEST_EXACT_BINARY"
chmod +x "$SIL_TEST_EXACT_BINARY"
actual="$(SIL_LSOF="$HOOKS/lsof" "$RESOLVER" 401 "$SIL_TEST_EXACT_BINARY")"
assert_eq "$SIL_TEST_WRONG_BINARY" "$actual" "resolver returns a present wrong mapping for caller mismatch handling"

reset_state
export SIL_TEST_LSOF_MODE=missing
if SIL_LSOF="$HOOKS/lsof" "$RESOLVER" 401 >/dev/null; then
  echo "FAIL: resolver must fail closed when no mapped executable is available" >&2
  exit 1
fi

# Darwin's /tmp is a compatibility symlink to /private/tmp. The production
# build path deliberately uses /tmp, while lsof reports the mapped physical
# executable. Exercise the actual lsof query and parser against a harmless
# system executable reached through a temporary alias; this never starts or
# inspects Canis97.
reset_state
(
  synthetic_alias_root="$(mktemp -d "${TMPDIR:-/tmp}/sirius-resolver-alias.XXXXXX")"
  synthetic_alias="$synthetic_alias_root/SyntheticRunner"
  ln -s /bin/sleep "$synthetic_alias"
  "$synthetic_alias" 20 &
  synthetic_alias_pid=$!
  cleanup_synthetic_alias() {
    /bin/kill "$synthetic_alias_pid" 2>/dev/null || true
    wait "$synthetic_alias_pid" 2>/dev/null || true
    rm -rf "$synthetic_alias_root"
  }
  trap cleanup_synthetic_alias EXIT
  if ! actual="$(SIL_LSOF=/usr/sbin/lsof "$RESOLVER" "$synthetic_alias_pid" "$synthetic_alias")"; then
    echo "FAIL: resolver must accept the physical mapped executable for a logical expected path" >&2
    exit 1
  fi
  assert_eq "$synthetic_alias" "$actual" "resolver accepts the physical mapped executable for a logical expected path"
)

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

# The legacy fake matrix remains as regression coverage for app-host test
# guards. Production GUI launching is now owned by the native LaunchServices
# helper and has its own compile-and-run fake workspace matrix.
bash "$ROOT_DIR/script/tests/native_launcher_tests.sh"

echo "PASS: native build/run routing contract"
