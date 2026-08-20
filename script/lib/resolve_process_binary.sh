#!/usr/bin/env bash
set -euo pipefail

pid="$1"
expected_path="${2:-}"
lsof_command="${SIL_LSOF:-/usr/sbin/lsof}"
realpath_command="${SIL_REALPATH:-/bin/realpath}"

# The build path is intentionally under /tmp, a compatibility symlink to
# /private/tmp on macOS. lsof reports the mapped physical path, while the
# launcher retains the logical build path. Canonicalize only the expected
# value used for comparison and return the original expected text on a match
# so the caller can continue to compare its own configured path verbatim.
canonical_expected_path=""
if [[ -n "$expected_path" ]]; then
  if ! canonical_expected_path="$("$realpath_command" "$expected_path" 2>/dev/null)" || [[ -z "$canonical_expected_path" ]]; then
    exit 1
  fi
fi

# argv[0] is caller-controlled text, so it cannot prove the executable that is
# mapped into a process. Restrict lsof to text mappings and read its machine
# format instead. Debug builds can map both the executable and a debug dylib,
# so an expected executable is selected by exact mapping rather than output
# ordering. A missing mapping is an invariant failure, not a fallback to
# argv-derived identity.
binary_path="$("$lsof_command" -a -p "$pid" -d txt -Fn 2>/dev/null | awk -v expected="$canonical_expected_path" -v output_expected="$expected_path" '
  /^n/ {
    path = substr($0, 2)
    if (first == "") {
      first = path
    }
    if (expected != "") {
      if (path == expected) {
        print output_expected
        found = 1
        exit
      }
    }
  }
  END {
    if (!found && first != "") {
      print first
    }
  }
')"
if [[ -z "$binary_path" ]]; then
  exit 1
fi
printf '%s\n' "$binary_path"
