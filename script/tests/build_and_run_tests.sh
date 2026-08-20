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
awk -F: -v pid="$1" '$1 == pid { print substr($0, length(pid) + 2); exit }' "$SIL_TEST_STATE/pids"
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
  zero) : > "$SIL_TEST_STATE/pids" ;;
  two) printf '401:%s\n402:%s\n' "$SIL_TEST_EXACT_BINARY" "$SIL_TEST_EXACT_BINARY" > "$SIL_TEST_STATE/pids" ;;
  wrong-path) printf '401:/tmp/not-the-built-binary\n' > "$SIL_TEST_STATE/pids" ;;
  *) exit 91 ;;
esac
HOOK

cat > "$HOOKS/sleep" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
printf 'sleep\n' >> "$SIL_TEST_STATE/events"
HOOK

chmod +x "$HOOKS"/*

reset_state() {
  : > "$STATE/pids"
  : > "$STATE/events"
  : > "$STATE/opens"
  printf '0' > "$STATE/terminate-calls"
  rm -f "$STATE/release-open"
  unset SIL_TEST_STICKY
  unset SIL_TEST_HOLD_OPEN
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
}

source "$HELPER"
configure_fake_hooks

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
done

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

echo "PASS: build/run routing contract"
