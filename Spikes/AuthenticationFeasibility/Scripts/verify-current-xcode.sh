#!/bin/sh

# This preflight intentionally has no provider, GUI, account, or browser surface.
# Its durable output contains only fixed version labels and one closed status.
set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_dir/../../.." && pwd)
default_output="$repository_root/.planning/phases/00-authentication-feasibility-gate/00-TOOLCHAIN.md"
mode=check
output="$default_output"
source=''

usage() {
    exit 2
}

case "${1:-}" in
    "") ;;
    --output)
        [ "$#" -eq 2 ] || usage
        output=$2
        ;;
    --require-ready)
        [ "$#" -eq 1 ] || usage
        mode=require-ready
        ;;
    --require-ready-or-closed)
        [ "$#" -eq 1 ] || usage
        mode=require-ready-or-closed
        ;;
    --check-conditional)
        [ "$#" -eq 4 ] || usage
        mode=check-conditional
        output=$2
        ;;
    *) usage ;;
esac

ready_artifact() {
    printf '%s\n' \
        'Schema: phase-0-toolchain-v1' \
        'Status: current-sdk-ready' \
        'Xcode: 26.6' \
        'macOS SDK: 26.5' \
        'Deployment target: macOS 26.0' \
        'Framework imports: passed' \
        'Replacement execution: incomplete' \
        'Phase 1 continuation: blocked'
}

pending_artifact() {
    printf '%s\n' \
        'Schema: phase-0-toolchain-v1' \
        'Status: environment-pending' \
        'Toolchain: unavailable-or-mismatched' \
        'Replacement execution: incomplete' \
        'Phase 1 continuation: blocked'
}

artifact_matches() {
    expected=$1
    candidate=$2
    [ -r "$candidate" ] || return 1
    temporary=$(mktemp "${TMPDIR:-/tmp}/auth-feasibility-toolchain.XXXXXX") || return 1
    trap 'rm -f "$temporary" "$source"' EXIT HUP INT TERM
    "$expected" > "$temporary"
    cmp -s "$temporary" "$candidate"
}

is_ready() { artifact_matches ready_artifact "$1"; }
is_pending() { artifact_matches pending_artifact "$1"; }

case "$mode" in
    require-ready)
        is_ready "$output"
        exit $?
        ;;
    require-ready-or-closed)
        is_ready "$output" || is_pending "$output"
        exit $?
        ;;
    check-conditional)
        # Later conditional tasks provide their own closed contract validators. This
        # gate permits only an exact ready or exact incomplete toolchain artifact.
        is_ready "$output" || is_pending "$output"
        exit $?
        ;;
esac

source=$(mktemp "${TMPDIR:-/tmp}/auth-feasibility-imports.XXXXXX.swift") || exit 1
temporary=$(mktemp "$(dirname -- "$output")/.toolchain.XXXXXX") || { rm -f "$source"; exit 1; }
trap 'rm -f "$temporary" "$source"' EXIT HUP INT TERM
printf '%s\n' 'import AppKit' 'import WebKit' 'import AVFoundation' > "$source"

status=environment-pending
developer_directory=$(xcode-select -p 2>/dev/null) || developer_directory=''
if [ -n "$developer_directory" ]; then
    xcode_version=$(DEVELOPER_DIR="$developer_directory" xcodebuild -version 2>/dev/null) || xcode_version=''
    sdk_version=$(DEVELOPER_DIR="$developer_directory" xcrun --sdk macosx --show-sdk-version 2>/dev/null) || sdk_version=''
    if [ "$(printf '%s\n' "$xcode_version" | sed -n '1p')" = 'Xcode 26.6' ] &&
       [ "$sdk_version" = '26.5' ] &&
       DEVELOPER_DIR="$developer_directory" xcrun swiftc -target arm64-apple-macos26.0 -typecheck "$source" >/dev/null 2>&1; then
        status=current-sdk-ready
    fi
fi

if [ "$status" = current-sdk-ready ]; then
    ready_artifact > "$temporary"
else
    pending_artifact > "$temporary"
fi
mv -f "$temporary" "$output"
