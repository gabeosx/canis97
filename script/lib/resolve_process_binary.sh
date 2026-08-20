#!/usr/bin/env bash
set -euo pipefail

pid="$1"
lsof_command="${SIL_LSOF:-/usr/sbin/lsof}"

# argv[0] is caller-controlled text, so it cannot prove the executable that is
# mapped into a process. Restrict lsof to the text mapping and read its machine
# format instead. A missing mapping is an invariant failure, not a fallback to
# argv-derived identity.
binary_path="$("$lsof_command" -a -p "$pid" -d txt -Fn 2>/dev/null | awk '/^n/ { print substr($0, 2); exit }')"
if [[ -z "$binary_path" ]]; then
  exit 1
fi
printf '%s\n' "$binary_path"
