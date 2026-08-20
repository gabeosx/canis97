#!/usr/bin/env bash
set -euo pipefail

pid="$1"
expected_path="${2:-}"
lsof_command="${SIL_LSOF:-/usr/sbin/lsof}"

# argv[0] is caller-controlled text, so it cannot prove the executable that is
# mapped into a process. Restrict lsof to text mappings and read its machine
# format instead. Debug builds can map both the executable and a debug dylib,
# so an expected executable is selected by exact mapping rather than output
# ordering. A missing mapping is an invariant failure, not a fallback to
# argv-derived identity.
binary_path="$("$lsof_command" -a -p "$pid" -d txt -Fn 2>/dev/null | awk -v expected="$expected_path" '
  /^n/ {
    path = substr($0, 2)
    if (expected != "") {
      if (path == expected) {
        print path
        found = 1
        exit
      }
    } else if (first == "") {
      first = path
    }
  }
  END {
    if (expected == "" && first != "") {
      print first
    }
  }
')"
if [[ -z "$binary_path" ]]; then
  exit 1
fi
printf '%s\n' "$binary_path"
