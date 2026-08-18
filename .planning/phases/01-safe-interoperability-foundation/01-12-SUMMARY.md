---
phase: 01-safe-interoperability-foundation
plan: "12"
subsystem: authentication
tags: [swift, webkit, concurrency, xctest, credential-handoff]
requires:
  - phase: 01-11
    provides: Explicit user-operated re-arm lifecycle for the volatile WebView handoff
provides:
  - Atomic available/selecting/consumed credential-selection lifecycle
  - Deterministic concurrency and cancellation proof for one credential transfer per attempt
affects: [phase-02-authorized-live-listening, authentication-boundary]
actuals:
  tokens: 4083
  tasks: 1
  commits: 2
tech-stack:
  added: []
  patterns: [main-actor reservation before suspension, controlled continuation-based concurrency tests]
key-files:
  created: []
  modified:
    - SiriusMac/Authentication/WebAuthenticationBridge.swift
    - SiriusMacTests/WebAuthenticationBridgeTests.swift
key-decisions:
  - "Reserve a credential-selection attempt before any cookie-store await and commit it before credential delivery awaits."
  - "Only explicit new-attempt disposal may return a consumed handoff to available."
patterns-established:
  - "Use a per-reservation generation guard so an older uncommitted selection cannot re-arm a newer explicit attempt."
requirements-completed: [AUTH-01, SECR-02, CLNT-04]
coverage:
  - id: D1
    description: "Overlapping explicit WebView selections read cookies once and transfer one opaque credential."
    requirement: AUTH-01
    verification:
      - kind: unit
        ref: "SiriusMacTests/WebAuthenticationBridgeTests.swift#testConcurrentSelectionsReserveOneCookieReadAndOneCredentialTransfer"
        status: pass
    human_judgment: false
  - id: D2
    description: "Cancellation and malformed pre-commit paths release only the uncommitted reservation, while post-commit cancellation remains consumed."
    requirement: SECR-02
    verification:
      - kind: unit
        ref: "SiriusMacTests/WebAuthenticationBridgeTests.swift#testCancelledSelectionReleasesReservationWithoutDeliveringCredential"
        status: pass
      - kind: unit
        ref: "SiriusMacTests/WebAuthenticationBridgeTests.swift#testCommittedSelectionStaysConsumedWhileTheCredentialConsumerSuspendsOrCallerCancels"
        status: pass
    human_judgment: false
  - id: D3
    description: "Injected cookie-store and handoff-disposal controls reproduce race and re-arm boundaries without timing tolerances."
    requirement: CLNT-04
    verification:
      - kind: unit
        ref: "SiriusMacTests/WebAuthenticationBridgeTests.swift#testExplicitNewAttemptBlocksSelectionUntilHandoffDisposalCompletes"
        status: pass
    human_judgment: false
duration: 6min
completed: 2026-08-18
status: complete
---

# Phase 01 Plan 12: Atomic WebView Credential Handoff Summary

**A main-actor reservation-to-consumption state machine now transfers at most one volatile WebView credential per explicit attempt, even across controlled async overlap and cancellation.**

## Performance

- **Duration:** 6 min
- **Started:** 2026-08-18T14:26:00Z
- **Completed:** 2026-08-18T14:32:00Z
- **Tasks:** 1
- **Files modified:** 2

## Accomplishments

- Replaced the late Boolean latch with private available, selecting, and consumed credential-selection states.
- Reserved selection before the cookie-store await, reset only uncommitted reservations, and committed consumption before opaque credential delivery.
- Added deterministic XCTest continuations for overlapping selection, cancellation, suspended consumer delivery, and explicit new-attempt re-arming.

## Task Commits

1. **Task 01-12-01: Reserve, commit, and prove one WebView credential transfer per attempt** - `2d30322` (test), `c027f11` (feat)

## Files Created/Modified

- `SiriusMac/Authentication/WebAuthenticationBridge.swift` - Implements the guarded credential-selection lifecycle, fail-closed cancellation result, and explicit re-arm sequencing.
- `SiriusMacTests/WebAuthenticationBridgeTests.swift` - Adds controlled cookie-read, consumer, and handoff-disposal test doubles plus concurrency regressions.

## Decisions Made

- Credential selection enters `selecting` synchronously, so every overlapping selector returns without inspecting cookies.
- A selection becomes `consumed` immediately before opaque credential delivery; delivery completion or caller cancellation never re-arms it.
- A reservation generation prevents an older in-flight selector from releasing a newer explicit new-attempt reservation.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added a private controlled handoff-disposal seam**
- **Found during:** Task 01-12-01
- **Issue:** The existing opaque handoff had no controllable suspension point, so the required proof that explicit new-attempt disposal blocks selection could not be deterministic.
- **Fix:** Added an internal `handoffDisposer` closure and a test-only suspending disposer; production behavior still discards the same volatile handoff before re-arming.
- **Files modified:** `SiriusMac/Authentication/WebAuthenticationBridge.swift`, `SiriusMacTests/WebAuthenticationBridgeTests.swift`
- **Verification:** Focused `WebAuthenticationBridgeTests` suite passes.
- **Committed in:** `c027f11` (part of task commit)

---

**Total deviations:** 1 auto-fixed (1 missing critical test control)
**Impact on plan:** Required for the planned deterministic explicit re-arm regression; no public API, provider contract, or persistence behavior changed.

## Issues Encountered

- The RED test build correctly failed because the bridge had neither the cancellation result nor the state-machine lifecycle. The green implementation resolved those expected gaps.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The Phase 1 WebView credential boundary is deterministically protected against duplicate handoffs under overlap and cancellation.
- No Phase 1 authorization-boundary blocker remains in this plan's scope.

## Self-Check: PASSED

- Confirmed both modified source and test files exist.
- Confirmed task commits `2d30322` and `c027f11` exist in git history.

---
*Phase: 01-safe-interoperability-foundation*
*Completed: 2026-08-18*
