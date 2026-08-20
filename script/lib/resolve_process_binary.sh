#!/usr/bin/env bash
set -euo pipefail

pid="$1"
/bin/ps -p "$pid" -o command= | awk '{ print $1; exit }'
