---
phase: 01-safe-interoperability-foundation
plan: "10"
subsystem: authentication-cleanup-lifecycle
tags: [swift, swift-testing, xctest, keychain, webkit, security]
requires:
  - phase: 01-04
    provides: Memory-first session retirement with app-owned Keychain and browser cleanup seams.
  - phase: 01-07
    provides: Native bridge/client composition with deterministic collaborators.
  - phase: 01-09
    provides: Explicit user-operated WebView lifecycle re-arm.
provides:
  - Fresh-composition explicit cleanup of Keychain and exact WebView residue
  - Coalesced overlapping cleanup with explicit-only later retries
  - Native presentation controls and lifecycle regression coverage
affects: [phase-2, phase-5]
tech-stack:
  added: []
  patterns: [actor-owned cleanup task, memory-first cleanup, explicit retry only, Keychain-and-WebView aggregate outcome]
key-files:
  created: []
  modified:
    - Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift
    - Packages/SiriusXMClient/Tests/SiriusXMClientTests/SignOutTests.swift
    - SiriusMac/Authentication/AuthenticationPresentationModel.swift
    - SiriusMac/Authentication/AuthenticationView.swift
    - SiriusMacTests/SelectedAuthenticationCompositionTests.swift
key-decisions:
  - "Every explicit cleanup request retires actor state then runs both idempotent cleaners; only overlapping requests share a result."
  - "Fresh composition exposes cleanup-only UI and never reads or restores a stored credential."
requirements-completed: [AUTH-03, SECR-01, SECR-02, CLNT-04]
actuals:
  tokens: 3852
  tasks: 1
  commits: 2
metrics:
  duration: 4min
  completed: 2026-08-18
status: complete
coverage:
  - id: D1
    description: Fresh and sequential explicit cleanup retires actor state, invokes Keychain and browser cleaners truthfully, coalesces overlap, and permits only explicit retries.
    requirement: AUTH-03
    verification:
      - kind: unit
        ref: "Packages/SiriusXMClient/Tests/SiriusXMClientTests/SignOutTests.swift#Memory-first sign-out"
        status: pass
    human_judgment: false
  - id: D2
    description: A fresh native composition removes randomized synthetic Keychain and matching browser residue without authentication or entitlement requests.
    requirement: SECR-01
    verification:
      - kind: integration
        ref: "SiriusMacTests/SelectedAuthenticationCompositionTests.swift#testFreshCompositionClearsSyntheticKeychainAndBrowserResidueWithoutAuthentication"
        status: pass
    human_judgment: false
  - id: D3
    description: Fresh cleanup failures remain signed out and expose another explicit cleanup action without automatic retry.
    requirement: SECR-02
    verification:
      - kind: integration
        ref: "SiriusMacTests/SelectedAuthenticationCompositionTests.swift#testFreshCleanupFailureStaysSignedOutAndAllowsAnExplicitRetry"
        status: pass
    human_judgment: false
---

# Phase 01 Plan 10: Fresh Local Session Cleanup Summary

**Fresh compositions can explicitly erase app Keychain credentials and exact WebView authentication residue through one coalesced, memory-first cleanup lifecycle.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-08-18T13:26:36Z
- **Completed:** 2026-08-18T13:30:28Z
- **Tasks:** 1
- **Files modified:** 5

## Accomplishments

- Replaced the signed-out early return with an actor-owned `cleanupTask` that retires in-memory state before concurrently awaiting Keychain erasure and exact browser-residue cleanup.
- Made overlapping cleanup requests share one outcome while every later explicit request safely invokes both idempotent cleaners again; incomplete cleanup stays signed out and retries only on another explicit request.
- Added `clearLocalSession()` and a visible `Clear Local Session` control for fresh, terminal, signed-out, cleanup-failed, and unsupported presentation states without adding a restore, fallback, or automatic retry path.
- Added Swift Testing and macOS XCTest regressions for fresh composition cleanup, synthetic Keychain/browser residue deletion, lifecycle failure presentation, concurrency, and idempotence.

## Task Commits

1. **Task 1: Clear persisted local auth material from a fresh app composition** - `e530a9d` (RED), `3501637` (GREEN)

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SiriusXMClient --filter SignOutTests` — passed (8 tests).
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/SelectedAuthenticationCompositionTests test` — passed (6 tests).
- Static acceptance checks confirmed the explicit native cleanup control, model intent, actor-owned coalescing task, and absence of a production `readStoredCredential()` call.

## Decisions Made

- Cleanup is an explicit local operation even when the coordinator starts signed out; it remains separate from authentication and entitlement.
- The actor stores only an in-flight cleanup task, never a completed-cleanup shortcut, so later explicit cleanup requests re-run both idempotent cleaners safely.

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None.

## Threat Flags

None - this plan introduced no endpoint, credential-read path, authentication method, or trust boundary.

## Self-Check: PASSED

- All five planned source and test files exist.
- TDD commits `e530a9d` and `3501637` exist in RED then GREEN order.
- Focused SwiftPM and macOS XCTest verification passed from the committed implementation.
