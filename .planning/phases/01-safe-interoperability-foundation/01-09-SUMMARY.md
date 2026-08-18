---
phase: 01-safe-interoperability-foundation
plan: "09"
subsystem: native-web-authentication-lifecycle
tags: [swift, webkit, authentication, security, xctest, tdd]
requires:
  - phase: 01-06
    provides: Nonpersistent WebView credential bridge and exact cookie policy.
  - phase: 01-07
    provides: Native authentication and entitlement composition.
provides:
  - Explicit per-attempt WebView credential handoff re-arm
  - Terminal retry and sign-out-to-new-login regression coverage
affects: [01-10, phase-2]
tech-stack:
  added: []
  patterns: [explicit user-operated re-arm, actor-isolated volatile handoff disposal, single-consumption credential transfer]
key-files:
  created: []
  modified:
    - SiriusMac/Authentication/WebAuthenticationBridge.swift
    - SiriusMac/Authentication/AuthenticationPresentationModel.swift
    - SiriusMacTests/WebAuthenticationBridgeTests.swift
    - SiriusMacTests/SelectedAuthenticationCompositionTests.swift
decisions:
  - "Only an explicit user-operated new sign-in attempt may discard and re-arm the volatile WebView credential handoff."
metrics:
  duration: 5min
  completed: 2026-08-18
status: complete
actuals:
  tokens: 2583
  tasks: 1
  commits: 2
coverage:
  - id: D1
    description: An accepted WebView credential remains single-consumption within one attempt and stale unconsumed material is erased before an explicit re-arm.
    requirement: AUTH-01
    verification:
      - kind: unit
        ref: "SiriusMacTests/WebAuthenticationBridgeTests.swift#testExplicitNewAttemptDiscardsAnUnconsumedHandoffAndRearmsOneTransfer"
        status: pass
    human_judgment: false
  - id: D2
    description: Explicit retry after a terminal native authentication result completes a newly armed bridge-to-client transaction without automatic retry.
    requirement: AUTH-01
    verification:
      - kind: integration
        ref: "SiriusMacTests/SelectedAuthenticationCompositionTests.swift#testExplicitRetryAfterTerminalClientResultStartsOneFreshNativeTransaction"
        status: pass
    human_judgment: false
  - id: D3
    description: Explicit new login after sign-out completes native authentication and entitlement using one fresh credential handoff.
    requirement: AUTH-01
    verification:
      - kind: integration
        ref: "SiriusMacTests/SelectedAuthenticationCompositionTests.swift#testExplicitNewLoginAfterSignOutTransfersOneFreshCredential"
        status: pass
    human_judgment: false
---

# Phase 01 Plan 09: Explicit WebView Retry and Re-login Summary

**Explicit user-operated WebView attempts now erase stale volatile handoffs, re-arm one credential transfer, and repeat the same native authentication and entitlement path.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-08-18T13:14:42Z
- **Completed:** 2026-08-18T13:19:12Z
- **Tasks:** 1
- **Files modified:** 4

## Accomplishments

- Made `beginUserOperatedSignIn()` asynchronous and ordered: selection is fail-closed while the bridge actor discards prior volatile material, then the per-attempt latch is reset before loading the existing nonpersistent WebView URL.
- Kept the opaque credential source internal while allowing deterministic test collaborators to observe transfers; `discard()` returns no credential value.
- Made composed presentation await the explicit reset/load sequence without changing its native authentication, entitlement, or single-flight boundaries.
- Added regressions for per-attempt single consumption, terminal-result retry, and sign-out-to-new-login using synthetic cookies and scripted client outcomes only.

## Task Commits

1. **Task 1: Re-arm one WebView credential handoff only for an explicit new attempt** - `32c576e` (RED), `22560ef` (GREEN)

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/WebAuthenticationBridgeTests -only-testing:SiriusMacTests/SelectedAuthenticationCompositionTests test` — passed (12 tests).
- Static acceptance checks confirmed the existing exact cookie policy remains the only selector, no raw credential accessor was added, and no timer or automatic retry path was introduced.

## Decisions Made

- Re-arming remains a private bridge lifecycle operation that only runs after an explicit Sign In or Retry action reaches the composed presentation flow.
- The bridge temporarily treats selection as consumed while its actor erases a stale handoff, so callback timing cannot transfer prior material into a newly requested attempt.

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None.

## Threat Flags

None - this plan introduced no new endpoint, authentication method, file access pattern, or trust boundary.

## Self-Check: PASSED

- All four planned source and test files exist in the app or unconditional XCTest targets.
- TDD commits `32c576e` and `22560ef` exist in git history in RED then GREEN order.
- The focused bridge and composition command passes all 12 selected XCTest cases.
