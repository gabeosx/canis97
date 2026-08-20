---
phase: 02-authorized-live-listening
plan: "14"
subsystem: authentication
tags: [swift, swiftui, swift-testing, xcodebuild, process-invariants]
requires:
  - phase: 02-13
    provides: closed offline authentication presentation matrix
  - phase: 02-15
    provides: single-instance app-host guard
provides:
  - Cleanup-before-authentication session ordering
  - Fixed native cleanup-in-progress presentation state
  - Guarded focused app-host regression evidence with zero process residue
affects: [02-17, authentication, Keychain persistence, WebView lifecycle]
actuals:
  tokens: 3292
  tasks: 2
  commits: 2
tech-stack:
  added: []
  patterns:
    - Await a coalesced cleanup task before an authentication attempt reads its credential source
    - Gate native authentication actions behind one fixed cleanup-in-progress state
key-files:
  created: []
  modified:
    - Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift
    - Packages/SiriusXMClient/Tests/SiriusXMClientTests/SignOutTests.swift
    - SiriusMac/Authentication/AuthenticationPresentationModel.swift
    - SiriusMac/Authentication/ClosedAuthenticationOracle.swift
    - SiriusMac/Authentication/AuthenticationView.swift
    - SiriusMacTests/AuthenticationPresentationModelTests.swift
decisions:
  - Await the current explicit cleanup before acquiring an authentication lease or credential source material.
  - Expose cleanup as a fixed in-progress state and reject every auth action until it settles.
metrics:
  duration: 17min
  completed: 2026-08-20
status: complete
---

# Phase 02 Plan 14: Cleanup ordering and native gate summary

**Older cleanup cannot erase a newer durable session, and the app visibly blocks reauthentication until cleanup finishes.**

## Accomplishments

- Added a deterministic in-memory blocked-erase regression: while cleanup is blocked, no new credential source, verifier, or persistence work starts; the new generation survives after release.
- Added `finishingCleanup`, with fixed copy and action gating for Sign Out and Clear Local Session.
- Restored exhaustive presentation handling and the fixed automatic-restore completion state required by the focused host matrix.

## Incremental Gate 3

**GREEN.** The focused `AuthenticationPresentationModelTests` and `SelectedAuthenticationCompositionTests` matrix passed **26/26** under the Plan 02-15 single-instance app-host guard. The guard closed the previous production SiriusMac process without UI actions, proved zero processes before the host, and returned with zero afterward. No production app was launched, and no real Keychain/browser state was inspected, erased, or altered.

## Verification

- `swift test --package-path Packages/SiriusXMClient --filter SignOutTests` — passed (10 tests).
- `swift test --package-path Packages/SiriusXMClient --filter SessionCoordinatorTests` — passed (10 tests).
- `bash script/test_offline_auth_matrix.sh` — passed (14 synthetic cases).
- `bash script/tests/build_and_run_tests.sh` — passed (fake process matrix only).
- Guarded focused `xcodebuild test` — passed (26 tests), exact zero SiriusMac processes afterward.

## Task Commits

1. **Task 02-14-01: Prove an older blocked erase cannot delete a later credential** — `c2cb1a4` (`fix`)
2. **Task 02-14-02: Keep native reauthentication blocked until cleanup is finished** — `017bec6` (`fix`)

## Deviations from Plan

### Auto-fixed Issues

1. **[Rule 3 - Blocking] Repaired exhaustive native presentation and test-host compilation**
   - **Found during:** Task 02-14-02 guarded host matrix.
   - **Issue:** Prior authentication states were not handled exhaustively in native presentation switches; one existing WebView test also used an async assertion unsupported by XCTest autoclosures.
   - **Fix:** Added closed handling for every presentation state, mapped automatic successful restore to its fixed completed state, and awaited the WebView selection before asserting.
   - **Files modified:** `AuthenticationPresentationModel.swift`, `AuthenticationView.swift`, `ClosedAuthenticationOracle.swift`, `WebAuthenticationBridgeTests.swift`.
   - **Verification:** Guarded focused app-host matrix passed 26/26 with zero processes after completion.

## Known Stubs

None.

## Self-Check: PASSED

- Both task commits exist and all listed production/test files are present.
- Incremental Gate 3 is green with zero SiriusMac processes remaining.
