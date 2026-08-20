#!/usr/bin/env bash

# Source this file from development scripts.  Callers provide command hooks so
# the protocol can be tested without ever reaching the host process table or
# LaunchServices.

sil_value() {
  local name="$1" value="${!1:-}"
  if [[ -z "$value" ]]; then
    echo "single-instance launcher requires $name" >&2
    return 2
  fi
  printf '%s\n' "$value"
}

sil_pid_list() {
  "$(sil_value SIL_PGREP)" "$(sil_value SIL_APP_NAME)" 2>/dev/null || true
}

sil_pid_count() {
  sil_pid_list | awk 'NF { count += 1 } END { print count + 0 }'
}

sil_wait_for_count() {
  local expected="$1" attempts="${SIL_DRAIN_ATTEMPTS:-20}" count
  while (( attempts >= 0 )); do
    count="$(sil_pid_count)"
    if [[ "$count" == "$expected" ]]; then
      return 0
    fi
    (( attempts == 0 )) && break
    "$(sil_value SIL_SLEEP)" "${SIL_POLL_INTERVAL:-0.1}"
    ((attempts -= 1))
  done
  return 1
}

sil_release_lock() {
  local lock_path="${SIL_LOCK_PATH:-}"
  [[ -n "$lock_path" && -d "$lock_path" ]] && rmdir "$lock_path" 2>/dev/null || true
}

sil_acquire_launch_lock() {
  local lock_path attempts
  lock_path="$(sil_value SIL_LOCK_PATH)" || return
  attempts="${SIL_LOCK_ATTEMPTS:-1}"
  while (( attempts > 0 )); do
    if mkdir "$lock_path" 2>/dev/null; then
      return 0
    fi
    ((attempts -= 1))
    (( attempts == 0 )) && break
    "$(sil_value SIL_SLEEP)" "${SIL_POLL_INTERVAL:-0.1}"
  done
  echo "single-instance launcher already active" >&2
  return 1
}

sil_terminate_all() {
  "$(sil_value SIL_TERMINATE_ALL)" "$(sil_value SIL_APP_NAME)" || true
}

sil_close_all_and_wait() {
  sil_terminate_all
  sil_wait_for_count 0
}

sil_exact_binary_matches_only_pid() {
  local pids pid actual expected path_hook
  pids="$(sil_pid_list)"
  pid="$(printf '%s\n' "$pids" | awk 'NF { print; exit }')"
  expected="$(sil_value SIL_APP_BINARY)" || return
  path_hook="$(sil_value SIL_PID_PATH)" || return
  actual="$("$path_hook" "$pid")" || return 1
  [[ "$actual" == "$expected" ]]
}

single_instance_launch_locked() {
  # This protocol performs no build itself.  A caller that needs the lock to
  # span a build invokes its build function between acquire and this function.
  sil_close_all_and_wait || return 1
  "$(sil_value SIL_OPEN)" "$(sil_value SIL_APP_BUNDLE)" || {
    sil_close_all_and_wait || true
    return 1
  }
  if ! sil_wait_for_count 1 || ! sil_exact_binary_matches_only_pid; then
    sil_close_all_and_wait || true
    return 1
  fi
}

single_instance_launch() {
  local status=0
  sil_acquire_launch_lock || return 1
  single_instance_launch_locked || status=$?
  sil_release_lock
  return "$status"
}

single_instance_with_lock() {
  local status=0
  sil_acquire_launch_lock || return 1
  "$@" || status=$?
  sil_release_lock
  return "$status"
}

single_instance_build_only() {
  "$@"
}

single_instance_guard_app_host() {
  local status=0 zero_status=0
  sil_acquire_launch_lock || return 1
  sil_close_all_and_wait || status=1
  if (( status == 0 )); then
    "$@" || status=$?
  fi
  sil_wait_for_count 0 || zero_status=1
  if (( zero_status != 0 )); then
    sil_close_all_and_wait || true
    status=1
  fi
  sil_release_lock
  return "$status"
}
