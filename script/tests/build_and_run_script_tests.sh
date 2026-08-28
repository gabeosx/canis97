#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/script/build_and_run.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sirius-build-and-run.XXXXXX")"
HOOKS="$TEST_ROOT/hooks"
LOCK_PATH="$TEST_ROOT/launcher.lock"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$HOOKS"

cat > "$HOOKS/xcodebuild" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$(dirname "$SIL_TEST_APP_BINARY")"
: > "$SIL_TEST_APP_BINARY"
chmod +x "$SIL_TEST_APP_BINARY"
HOOK

cat > "$HOOKS/xcrun" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail

output=""
while (( $# > 0 )); do
  if [[ "$1" == "-o" ]]; then
    output="$2"
    break
  fi
  shift
done

[[ -n "$output" ]]
: > "$output"
chmod +x "$output"
HOOK

chmod +x "$HOOKS/xcodebuild" "$HOOKS/xcrun"

export PATH="$HOOKS:$PATH"
export CANIS97_XCODEBUILD="$HOOKS/xcodebuild"
export CANIS97_LOCK_PATH="$LOCK_PATH"
export CANIS97_DERIVED_DATA_PATH="$TEST_ROOT/derived-data"
export CANIS97_CLANG_CACHE_PATH="$TEST_ROOT/clang-cache"
export CANIS97_SWIFTPM_CACHE_PATH="$TEST_ROOT/swiftpm-cache"
export CANIS97_NATIVE_LAUNCHER_BINARY="$TEST_ROOT/native-launcher"
export SIL_TEST_APP_BINARY="$CANIS97_DERIVED_DATA_PATH/Build/Products/Debug/Canis97.app/Contents/MacOS/Canis97"

mkdir "$LOCK_PATH"
if "$SCRIPT" run >/dev/null 2>&1; then
  echo "FAIL: a second launcher must fail while another invocation owns the lock" >&2
  exit 1
fi
if [[ ! -d "$LOCK_PATH" ]]; then
  echo "FAIL: a failed contender removed another launcher's lock" >&2
  exit 1
fi

"$SCRIPT" --build-only >/dev/null
if [[ ! -d "$LOCK_PATH" ]]; then
  echo "FAIL: build-only removed another launcher's lock" >&2
  exit 1
fi

echo "build-and-run-lock-ownership: PASS"
