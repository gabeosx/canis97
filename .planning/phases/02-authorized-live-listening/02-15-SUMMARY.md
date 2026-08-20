---
phase: 02-authorized-live-listening
plan: "15"
subsystem: launch-safety
tags: [bash, xcodebuild, process-invariants, telemetry, testing]
requires:
  - phase: 02-11
    provides: bounded authentication checkpoint and current app preservation contract
provides:
  - Atomic single-instance launcher with zero-before and exact-binary verification
  - Fake-process launcher and app-host guard matrix
  - Build-only path that performs no lifecycle work
affects: [02-14, 02-16, 02-17, 02-18, bounded-uat]
actuals:
  tokens: 4177
  tasks: 2
  commits: 5
tech-stack:
  added: []
  patterns:
    - Sourceable shell lifecycle helpers with explicit command hooks
    - Telemetry-first exact-bundle launch held under one atomic lock
key-files:
  created:
    - script/lib/single_instance_launcher.sh
    - script/lib/resolve_process_binary.sh
    - script/tests/build_and_run_tests.sh
  modified:
    - script/build_and_run.sh
    - SiriusMac/Authentication/AuthenticationPresentationModel.swift
key-decisions:
  - "A matching app name is insufficient: launch success requires exactly one PID whose executable path equals the derived-data binary."
  - "Build-only remains strictly separate from all app lifecycle and telemetry operations."
requirements-completed: [PLAY-02]
coverage:
  - id: D1
    description: Atomic fake-process single-instance launcher including drain, exact-path, failure cleanup, and app-host guard schedules.
    requirement: PLAY-02
    verification:
      - kind: integration
        ref: bash script/tests/build_and_run_tests.sh --helper-only
        status: pass
    human_judgment: false
  - id: D2
    description: All supported launch modes route through the shared exact-bundle launcher while build-only has no lifecycle calls.
    requirement: PLAY-02
    verification:
      - kind: integration
        ref: bash script/tests/build_and_run_tests.sh
        status: pass
      - kind: other
        ref: ./script/build_and_run.sh --build-only
        status: pass
    human_judgment: false
duration: 15min
completed: 2026-08-20
status: complete
---

# Phase 02 Plan 15: Single-instance launcher safety summary

**A telemetry-first, exact-binary launcher now prevents duplicate SiriusMac processes, while build-only verification leaves the running app untouched.**

## Performance

- **Duration:** 15 min
- **Started:** 2026-08-20T14:48:00Z
- **Completed:** 2026-08-20T15:03:36Z
- **Tasks:** 2/2
- **Files modified:** 5

## Accomplishments

- Added an atomic directory lock with zero-old-process draining, one-PID verification, exact executable-path matching, fail-closed cleanup, and interruption traps.
- Added a fake-only concurrent launcher matrix, including host-guard success, failure, and leak cleanup paths.
- Routed production run modes through the lock and confirmed build-only builds without launching, inspecting, or terminating SiriusMac.

## Incremental Gate 2

**GREEN.** `bash script/tests/build_and_run_tests.sh` and `./script/build_and_run.sh --build-only` both passed. The test suite uses only temporary fake hooks. No real SiriusMac process, GUI app, WebKit instance, Keychain item, credential, or provider service was accessed or changed.

## Task Commits

1. **Task 02-15-01: Prove two concurrent invocations open the exact bundle once** — `c22d987` (`test`), `725db61` (`feat`)
2. **Task 02-15-02: Route every run mode through telemetry-first single-instance launch** — `97f192d` (`test`), `87b95f3` (`feat`), `0b84600` (`fix`)

## Decisions Made

- Compare the sole launched PID's executable path byte-for-byte with the exact derived-data binary.
- Reserve real lifecycle commands for later explicitly authorized checkpoints; this plan proves the protocol only through fake hooks and build-only.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking compile error] Handle non-durable credential persistence in the presentation flow**
- **Found during:** Task 02-15-02 build-only verification
- **Issue:** Plan 02-12 added `.credentialPersistenceFailed` but left the app presentation switch non-exhaustive, blocking the required build-only check.
- **Fix:** Map the closed persistence failure to the existing unsupported presentation so it cannot reach Ready or expose storage detail.
- **Files modified:** `SiriusMac/Authentication/AuthenticationPresentationModel.swift`
- **Verification:** `./script/build_and_run.sh --build-only` passed.
- **Committed in:** `87b95f3`

**Total deviations:** 1 auto-fixed (Rule 3).
**Impact on plan:** Required to make the build-only safety gate executable; no app was launched or state changed.

## Issues Encountered

- The initial sandboxed Xcode build could not write its normal compiler cache. Re-running the identical build-only command with local Xcode cache access succeeded.

## Known Stubs

None.

## Next Phase Readiness

- Plans 02-14, 02-16, and 02-18 can use `single_instance_guard_app_host` for their zero-before/zero-after app-host checks.
- Incremental Gate 2 is green. The current production app was neither inspected nor altered by this plan.

## Self-Check: PASSED

- Confirmed all five listed code/test files and all four task commits exist.
- Confirmed the fake launcher matrix and build-only verification pass.
