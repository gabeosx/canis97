#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
harness="$repo_root/script/animated_skin_acceptance.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/canis97-animation-acceptance.XXXXXX")"
hooks="$test_root/hooks"
state="$test_root/state"
app="$test_root/Build/Products/AnimationAcceptance/Canis97.app"

cleanup() { rm -rf "$test_root"; }
trap cleanup EXIT
mkdir -p "$hooks" "$state" "$app/Contents/MacOS"
printf '#!/usr/bin/env bash\nexit 0\n' > "$app/Contents/MacOS/Canis97"
chmod +x "$app/Contents/MacOS/Canis97"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.canis97.player</string><key>CFBundleShortVersionString</key><string>0.1.0</string><key>CFBundleVersion</key><string>1</string></dict></plist>
PLIST

cat > "$hooks/pgrep" <<'HOOK'
#!/usr/bin/env bash
printf 'preflight\n' >> "$CANIS97_ACCEPTANCE_TEST_STATE/events"
exit 1
HOOK
cat > "$hooks/readiness" <<'HOOK'
#!/usr/bin/env bash
printf 'readiness\n' >> "$CANIS97_ACCEPTANCE_TEST_STATE/events"
if [[ "${CANIS97_ACCEPTANCE_TEST_EXPECT_LOCK_ABSENT:-0}" == 1 ]]; then
  [[ ! -e "$CANIS97_ACCEPTANCE_TEST_LOCK_PATH" ]] || exit 91
fi
[[ ! -e "$CANIS97_ACCEPTANCE_TEST_OUTPUT_DIR" ]] || exit 92
case "${CANIS97_ACCEPTANCE_TEST_READINESS_MODE:-ready}" in
  ready) printf 'ready\n' ;;
  wrong) printf 'not-ready\n' ;;
  closed) : ;;
  *) exit 93 ;;
esac
HOOK
cat > "$hooks/launch_app" <<'HOOK'
#!/usr/bin/env bash
[[ -d "$CANIS97_ACCEPTANCE_TEST_LOCK_PATH" && -d "$CANIS97_ACCEPTANCE_TEST_OUTPUT_DIR" ]] || exit 94
printf 'launch\n' >> "$CANIS97_ACCEPTANCE_TEST_STATE/events"
printf '4242\n'
HOOK
cat > "$hooks/prompt_scenario" <<'HOOK'
#!/usr/bin/env bash
printf 'prompt:%s\n' "$1" >> "$CANIS97_ACCEPTANCE_TEST_STATE/events"
HOOK
cat > "$hooks/terminate_owned_pid" <<'HOOK'
#!/usr/bin/env bash
printf 'terminate:%s\n' "$1" >> "$CANIS97_ACCEPTANCE_TEST_STATE/events"
HOOK
for stage in cpu-memory gpu-windowserver hitch-responsiveness energy; do
  cat > "$hooks/collect_$stage" <<'HOOK'
#!/usr/bin/env bash
printf 'fake metric for owned pid %s\n' "$1"
HOOK
  chmod +x "$hooks/collect_$stage"
done
chmod +x "$hooks/pgrep" "$hooks/readiness" "$hooks/launch_app" "$hooks/prompt_scenario" "$hooks/terminate_owned_pid"

assert_zero_launches() {
  [[ ! -f "$state/events" ]] || ! grep -qx 'launch' "$state/events"
}

assert_zero_post_readiness_activity() {
  assert_zero_launches || { echo 'FAIL: rejected readiness launched an app' >&2; exit 1; }
  [[ ! -f "$state/events" ]] || ! grep -q '^terminate:' "$state/events" || { echo 'FAIL: rejected readiness terminated a PID' >&2; exit 1; }
  [[ ! -e "$CANIS97_ACCEPTANCE_TEST_LOCK_PATH" ]] || { echo 'FAIL: rejected readiness created a lock' >&2; exit 1; }
  [[ ! -e "$CANIS97_ACCEPTANCE_TEST_OUTPUT_DIR" ]] || { echo 'FAIL: rejected readiness created evidence output' >&2; exit 1; }
}

rm -f "$state/events"
if "$harness" --app "$app" --output "$test_root/unauthorized" >/dev/null 2>&1; then
  echo 'FAIL: unauthorized invocation succeeded' >&2
  exit 1
fi
assert_zero_launches || { echo 'FAIL: unauthorized invocation launched an app' >&2; exit 1; }

if "$harness" --authorized-release-run --app "$test_root/Canis97.app" --output "$test_root/ambiguous" >/dev/null 2>&1; then
  echo 'FAIL: ambiguous app path succeeded' >&2
  exit 1
fi
assert_zero_launches || { echo 'FAIL: ambiguous invocation launched an app' >&2; exit 1; }

rm -f "$state/events"
export CANIS97_ACCEPTANCE_TEST_LOCK_PATH="$repo_root/.animation-acceptance.lock"
export CANIS97_ACCEPTANCE_TEST_OUTPUT_DIR="$test_root/non-tty"
"$harness" --authorized-release-run --app "$app" --output "$test_root/non-tty" >/dev/null 2>&1 || true
assert_zero_post_readiness_activity

for readiness_mode in closed wrong; do
  rm -f "$state/events"
  readiness_output="$test_root/readiness-$readiness_mode"
  export CANIS97_ACCEPTANCE_TEST_LOCK_PATH="$repo_root/.animation-acceptance.lock"
  export CANIS97_ACCEPTANCE_TEST_OUTPUT_DIR="$readiness_output"
  export CANIS97_ACCEPTANCE_TEST_READINESS_MODE="$readiness_mode"
  if CANIS97_ACCEPTANCE_TEST_HOOKS="$hooks" CANIS97_ACCEPTANCE_TEST_STATE="$state" PATH="$hooks:$PATH" \
    "$harness" --authorized-release-run --app "$app" --output "$readiness_output" >/dev/null 2>&1; then
    echo "FAIL: $readiness_mode readiness succeeded" >&2
    exit 1
  fi
  assert_zero_post_readiness_activity
done
unset CANIS97_ACCEPTANCE_TEST_READINESS_MODE

rm -f "$state/events"
export CANIS97_ACCEPTANCE_TEST_LOCK_PATH="$repo_root/.animation-acceptance.lock"
export CANIS97_ACCEPTANCE_TEST_OUTPUT_DIR="$test_root/evidence"
export CANIS97_ACCEPTANCE_TEST_EXPECT_LOCK_ABSENT=1
CANIS97_ACCEPTANCE_TEST_HOOKS="$hooks" \
CANIS97_ACCEPTANCE_TEST_STATE="$state" \
PATH="$hooks:$PATH" \
"$harness" --authorized-release-run --app "$app" --output "$test_root/evidence"
[[ "$(grep -cx 'launch' "$state/events")" == '1' ]] || { echo 'FAIL: authorized fake run did not launch exactly once' >&2; exit 1; }
[[ "$(grep -E '^(readiness|preflight|launch)$' "$state/events")" == $'readiness\npreflight\nlaunch' ]] || { echo 'FAIL: readiness did not precede preflight and launch' >&2; exit 1; }
[[ "$(grep -cx 'terminate:4242' "$state/events")" == '1' ]] || { echo 'FAIL: successful fake run did not terminate exactly its owned PID' >&2; exit 1; }
! grep -q '^terminate:31337$' "$state/events" || { echo 'FAIL: successful fake run terminated an unowned PID' >&2; exit 1; }
[[ "$(grep '^stage:' "$test_root/evidence/events.log")" == $'stage:cpu-memory\nstage:gpu-windowserver\nstage:hitch-responsiveness\nstage:energy' ]] || { echo 'FAIL: evidence stages were not distinct and ordered' >&2; exit 1; }
for stage in cpu-memory gpu-windowserver hitch-responsiveness energy; do
  [[ -s "$test_root/evidence/$stage.txt" ]] || { echo "FAIL: missing $stage evidence" >&2; exit 1; }
done
[[ "$(cat "$test_root/evidence/FINAL_STATUS")" == complete ]] || { echo 'FAIL: successful fake evidence was not complete' >&2; exit 1; }
[[ -s "$test_root/evidence/ARTIFACTS.sha256" ]] || { echo 'FAIL: artifact hashes were not recorded' >&2; exit 1; }
grep -qx 'exit_status=0' "$test_root/evidence/build-context.txt" || { echo 'FAIL: successful run did not record exit status' >&2; exit 1; }

if rg -n '(^|[^[:alnum:]_])(pkill|killall|curl|URLSession)([^[:alnum:]_]|$)' "$harness" >/dev/null ||
   ! rg -q 'kill -TERM "\$owned_pid"' "$harness" ||
   ! rg -q '\[\[ -t 0 && -t 1 \]\]' "$harness" ||
   ! rg -q 'acknowledgement" == "ready"' "$harness"; then
  echo 'FAIL: harness may contact a service or terminate a PID it does not own' >&2
  exit 1
fi

mkdir "$repo_root/.animation-acceptance.lock"
export CANIS97_ACCEPTANCE_TEST_OUTPUT_DIR="$test_root/locked"
unset CANIS97_ACCEPTANCE_TEST_EXPECT_LOCK_ABSENT
if CANIS97_ACCEPTANCE_TEST_HOOKS="$hooks" CANIS97_ACCEPTANCE_TEST_STATE="$state" PATH="$hooks:$PATH" \
  "$harness" --authorized-release-run --app "$app" --output "$test_root/locked" >/dev/null 2>&1; then
  echo 'FAIL: concurrent acceptance run succeeded' >&2
  exit 1
fi
rmdir "$repo_root/.animation-acceptance.lock"

rm -f "$state/events"
export CANIS97_ACCEPTANCE_TEST_OUTPUT_DIR="$test_root/interrupted"
export CANIS97_ACCEPTANCE_TEST_EXPECT_LOCK_ABSENT=1
cat > "$hooks/interrupt_after_launch" <<'HOOK'
#!/usr/bin/env bash
exit 0
HOOK
chmod +x "$hooks/interrupt_after_launch"
set +e
CANIS97_ACCEPTANCE_TEST_HOOKS="$hooks" \
CANIS97_ACCEPTANCE_TEST_STATE="$state" \
PATH="$hooks:$PATH" \
"$harness" --authorized-release-run --app "$app" --output "$test_root/interrupted"
interrupt_status=$?
set -e
[[ "$interrupt_status" == 130 ]] || { echo 'FAIL: fake interruption did not return 130' >&2; exit 1; }
grep -qx 'terminate:4242' "$state/events" || { echo 'FAIL: interruption did not terminate only the owned PID' >&2; exit 1; }
[[ "$(cat "$test_root/interrupted/FINAL_STATUS")" == incomplete ]] || { echo 'FAIL: interrupted evidence was not marked incomplete' >&2; exit 1; }

echo 'animated-skin-acceptance: PASS'
