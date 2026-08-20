---
phase: 02-authorized-live-listening
plan: "13"
subsystem: authentication
tags: [swift, swiftui, webkit, keychain, offline-testing, security]
requires:
  - phase: 02-12
    provides: closed native rejection and persistence semantics
provides:
  - Fixed closed authentication presentation and lifecycle labels
  - Synthetic local restore and web selection matrix without an app host
  - Fresh nonpersistent WebView rotation before explicit sign-in loading
affects: [02-14, 02-17, authentication, WebView, Keychain restore]
actuals:
  tokens: 13108
  tasks: 3
  commits: 3
tech-stack:
  added: []
  patterns:
    - Foundation-only closed authentication oracle for presentation and offline verification
    - Pure cookie snapshot reduction with opaque single-consumption handoff
    - Retire-and-rotate nonpersistent WebView session before each explicit sign-in load
key-files:
  created:
    - SiriusMac/Authentication/ClosedAuthenticationOracle.swift
    - SiriusMac/Authentication/WebCredentialSelectionPolicy.swift
    - script/test_offline_auth_matrix.sh
    - script/tests/OfflineAuthenticationMatrixTests.swift
  modified:
    - SiriusMac/Authentication/AuthenticationPresentationModel.swift
    - SiriusMac/Authentication/RestorableAuthenticationCredentialSource.swift
    - SiriusMac/Authentication/WebAuthenticationBridge.swift
    - SiriusMac.xcodeproj/project.pbxproj
    - SiriusMacTests/AuthenticationPresentationModelTests.swift
    - SiriusMacTests/SelectedAuthenticationCompositionTests.swift
    - SiriusMacTests/WebAuthenticationBridgeTests.swift
key-decisions:
  - "Use a closed enum-only oracle for all presentation and lifecycle labels; no provider payload can enter the UI or telemetry contract."
  - "Treat missing, invalid, and unavailable local material as distinct terminal restore results with zero WebView fallback."
  - "Rotate the app-owned nonpersistent WebView session before every explicit sign-in load and block the attempt if retirement fails."
patterns-established:
  - "No-host authentication gates compile only pure Foundation sources and use synthetic outcomes."
  - "Web credential selection exposes a credential only for one exact valid candidate; all other outcomes are fixed labels."
requirements-completed: [CAT-03, PLAY-04]
coverage:
  - id: D1
    description: Stage-specific profile, entitlement, persistence, and restore presentation is fixed and secret-free.
    requirement: CAT-03
    verification:
      - kind: unit
        ref: bash script/test_offline_auth_matrix.sh --oracle-only
        status: pass
    human_judgment: false
  - id: D2
    description: Missing, invalid, unavailable, and valid synthetic local restoration remains out of WebView and classifies deterministically.
    requirement: CAT-03
    verification:
      - kind: unit
        ref: bash script/test_offline_auth_matrix.sh --local-only
        status: pass
    human_judgment: false
  - id: D3
    description: Closed web selection outcomes and reset failure are single-consumption and fail closed before player loading.
    requirement: PLAY-04
    verification:
      - kind: unit
        ref: bash script/test_offline_auth_matrix.sh
        status: pass
    human_judgment: false
duration: 10min
completed: 2026-08-20
status: complete
---

# Phase 02 Plan 13: No-host authentication matrix summary

**Closed native authentication stages, deterministic local restore, and fresh nonpersistent WebView rotation are now proven by a complete synthetic offline matrix.**

## Performance

- **Duration:** 10 min
- **Started:** 2026-08-20T11:11:30-04:00
- **Completed:** 2026-08-20T11:20:49-04:00
- **Tasks:** 3/3
- **Files modified:** 11

## Accomplishments

- Added a Foundation-only closed oracle that distinguishes profile, entitlement, persistence, local-restoration, and WebView-reset outcomes with fixed secret-free presentation labels.
- Made automatic restoration emit fixed local availability or restore-completed events and keep every terminal local state out of WebView.
- Replaced dynamic cookie-name inventory telemetry with a pure closed selection policy; every explicit sign-in now retires and rotates its nonpersistent session before exactly one player load.

## Incremental Gate 1

**GREEN.** `bash script/test_offline_auth_matrix.sh` passed all fourteen synthetic oracle, local-restore, and WebView outcome cases. The run used no Xcode test host, SiriusMac process, Keychain item, WebKit data store, provider operation, or network access. The currently running production app was not inspected or altered.

Focused app-host regressions were written but intentionally not run: Plan 02-14 owns app-host verification only after its cleanup-ordering gate and the Plan 02-15 launcher safety gate are green.

## Task Commits

1. **Task 02-13-01: Render one complete synthetic transaction from fixed stage inputs** — `822ef5b` (`feat`)
2. **Task 02-13-02: Cover local credential availability and zero-WebView restore** — `66fa3c0` (`feat`)
3. **Task 02-13-03: Make web selection fixed-label, single-consumption, and genuinely fresh** — `622708b` (`feat`)

## Decisions Made

- Presentation and local lifecycle telemetry cross only an enum-only oracle; the disconnected free-form diagnostics surface was removed.
- A failed WebView retirement is terminal for that explicit attempt: it cannot load the player entry or select a credential.
- The debug Web Inspector exposure was removed along with cookie-name inventory so visual sign-in state is never treated as credential evidence.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added app-target membership for new authentication source files**
- **Found during:** Task 02-13-03
- **Issue:** The Xcode project explicitly lists source files, so the new closed oracle and pure selection policy would not be compiled by later authorized app-host checks.
- **Fix:** Added only those two source files to the existing SiriusMac target membership.
- **Files modified:** `SiriusMac.xcodeproj/project.pbxproj`
- **Verification:** `plutil -lint SiriusMac.xcodeproj/project.pbxproj` passed; the no-host matrix remained green.
- **Committed in:** `622708b`

**Total deviations:** 1 auto-fixed (1 blocking)

## Issues Encountered

- The standalone compiler needs its normal user module cache outside the filesystem sandbox. The exact no-host commands were rerun with permission and passed; no application, Keychain, WebKit, provider, or network operation occurred.

## Next Phase Readiness

- Incremental Gate 1 is green through the complete synthetic authentication matrix.
- Plan 02-14 may now run its guarded package checks and, only after the Plan 02-15 launcher guard proves zero processes, its bounded app-host checks. No live sign-in is authorized by this plan.

## Self-Check: PASSED

- Verified task commits `822ef5b`, `66fa3c0`, and `622708b` exist.
- Verified the created oracle, selection policy, and offline matrix files exist.
- Verified the complete standalone matrix, Swift syntax parse, project-file lint, and static no-dynamic-telemetry scan passed.
