---
phase: 02-authorized-live-listening
plan: "16"
subsystem: playback-coordination
tags: [swift, avfoundation, xctest, xcodebuild, playback-race]
requires:
  - phase: 02-09
    provides: install-before-ready playback coordination and stale callback guards
  - phase: 02-17
    provides: passed native authentication and durable persistence checkpoint
provides:
  - Initial-status playback observation staged until the exact item is installed
  - Deterministic synchronous-ready coverage for initial tune, live-edge resume, and recovery
  - A consistent MetadataPresentationTests Xcode group reference
affects: [02-18, playback, recovery, session-restoration]
actuals:
  tokens: 4382
  tasks: 2
  commits: 3
tech-stack:
  added: []
  patterns:
    - Record an observation identity before subscription and consume ready state only after item installation.
    - Exercise AVFoundation ordering with a synchronous fake runtime rather than media loading.
key-files:
  created: []
  modified:
    - SiriusMac/Listening/PlaybackCoordinator.swift
    - SiriusMacTests/PlaybackInstallationOrderTests.swift
    - SiriusMac.xcodeproj/project.pbxproj
key-decisions:
  - Initial item status is observed with `.initial` and `.new`, but an early ready signal is staged until the matching item is installed.
  - Initial tune, live-edge resume, and recovery share the same staged-ready/install/play path.
  - The focused app-host test is wrapped by the Plan 02-15 guard; build-only verification never launches the production app.
requirements-completed: [PLAY-01, PLAY-02, PLAY-03]
coverage:
  - id: D1
    description: Initial, resumed, and recovered already-ready items request play once only after installation.
    requirement: PLAY-01
    verification:
      - kind: unit
        ref: SiriusMacTests/PlaybackInstallationOrderTests.swift#synchronous-ready ordering tests
        status: pass
      - kind: integration
        ref: guarded xcodebuild -only-testing:SiriusMacTests/PlaybackInstallationOrderTests
        status: pass
    human_judgment: false
  - id: D2
    description: One coordinator preserves exact observation identity and ignores stale, cancelled, superseded, and duplicate ready callbacks.
    requirement: PLAY-02
    verification:
      - kind: unit
        ref: SiriusMacTests/PlaybackInstallationOrderTests.swift#late callback and duplicate-ready cases
        status: pass
    human_judgment: false
  - id: D3
    description: Recovery re-resolves once and applies the same already-ready ordering without publishing playing before runtime confirmation.
    requirement: PLAY-03
    verification:
      - kind: unit
        ref: SiriusMacTests/PlaybackInstallationOrderTests.swift#testSynchronousReadyDuringObservationWaitsForRecoveredInstallBeforePlaying
        status: pass
    human_judgment: false
metrics:
  duration: 4 min
  completed: 2026-08-20
status: complete
---

# Phase 02 Plan 16: AVFoundation readiness closeout Summary

**Already-ready AVPlayer items now stage readiness until their exact installation, so initial tune, live-edge resume, and recovery each request play exactly once without accepting stale callbacks.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-08-20T16:04:29-04:00
- **Completed:** 2026-08-20T16:08:00-04:00
- **Tasks:** 2/2
- **Files modified:** 3

## Accomplishments

- Observes both initial and later AVPlayerItem status and stages a matching early-ready callback until installation completes.
- Adds deterministic synchronous-observer regressions for initial tune, live-edge resume, recovery, duplicate readiness, and existing stale callback cases.
- Corrects the dangling `MetadataPresentationTests.swift` group child without changing its source build-phase membership.

## Incremental Gate 5

**GREEN.** The passed authentication UAT precondition was confirmed before changes. The offline authentication matrix passed all 14 synthetic cases, and guarded `PlaybackInstallationOrderTests` passed 11/11 tests. `plutil -lint`, guarded `xcodebuild -list`, and guarded `./script/build_and_run.sh --build-only` also passed. The production app was not launched; the focused XCTest host was guarded and each guarded invocation completed with the guard's zero-before/zero-after condition.

## Task Commits

1. **Task 02-16-01: Stage an already-ready item until exact installation** - `d39727f` (`test` RED), `a99cd80` (`fix` GREEN)
2. **Task 02-16-02: Repair the MetadataPresentationTests project reference** - `fbb828e` (`fix`)

## Files Created/Modified

- `SiriusMac/Listening/PlaybackCoordinator.swift` - Initial-status observation and exact pending-ready/install guards.
- `SiriusMacTests/PlaybackInstallationOrderTests.swift` - Synchronous-ready fake runtime and ordering regressions.
- `SiriusMac.xcodeproj/project.pbxproj` - Correct MetadataPresentationTests group reference.

## Decisions Made

- Record the observation identity before subscribing, then consume only an exact staged ready signal after the item is installed.
- Keep test coverage synthetic and offline; no provider, media URL, WebView, or Keychain composition is involved.
- Preserve all durable authentication state for Plan 02-18 restoration checks.

## Verification

- `bash script/test_offline_auth_matrix.sh` — passed (14/14 synthetic cases).
- Guarded `xcodebuild test -only-testing:SiriusMacTests/PlaybackInstallationOrderTests` — passed (11/11 tests).
- `plutil -lint SiriusMac.xcodeproj/project.pbxproj` — passed.
- Guarded `xcodebuild -project SiriusMac.xcodeproj -list` — passed.
- Guarded `./script/build_and_run.sh --build-only` — passed; no app launch.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Invoke the app-host guard as its sourceable library API.**
- **Found during:** Task 1 verification.
- **Issue:** `single_instance_launcher.sh` defines `single_instance_guard_app_host` but has no command-line dispatcher, so the plan's literal `bash ... --guard-app-host` form returned successfully without running its enclosed command.
- **Fix:** Ran each Xcode command through a Bash shell that sources the guard and invokes `single_instance_guard_app_host` directly.
- **Files modified:** None.
- **Verification:** Every intended focused test, project-list, and build-only command executed under that guard and passed.

---

**Total deviations:** 1 auto-fixed (1 blocking verification invocation).
**Impact on plan:** Verification now enforces the intended guard behavior; production scope and authentication persistence remain unchanged.

## Issues Encountered

- The initial sandboxed Xcode run could not write normal compiler/package caches. The guarded test was rerun with the required local Xcode cache access and failed in RED for the intended ordering assertions before passing in GREEN.

## Known Stubs

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 02-18 can restore the preserved durable session and verify the listening controls without another password entry.
- Phase requirements remain pending global completion because Plan 02-18 also declares PLAY-01 through PLAY-03.

## Self-Check: PASSED

- Required source, test, and project artifacts exist and contain the staged-ready and corrected reference identifiers.
- Task commits `d39727f`, `a99cd80`, and `fbb828e` exist in history.
- No tracked file deletions were introduced by this plan.

---
*Phase: 02-authorized-live-listening*
*Completed: 2026-08-20*
