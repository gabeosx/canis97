---
phase: 01-safe-interoperability-foundation
plan: "14"
subsystem: authentication
tags: [swift, urlsession, redirects, fail-closed, transport-testing]
requires:
  - phase: 01-12
    provides: Ephemeral client-owned transport and lock-protected request state
provides:
  - Production redirect-callback invocation telemetry with no redirect data retention
  - Direct deterministic proof that every redirect completes without a follow-up request
affects: [authentication, transport, session-security, compatibility]
actuals:
  tokens: 1282
  tasks: 1
  commits: 2
tech-stack:
  added: []
  patterns:
    - Record redirect callback entry as a lock-protected scalar before an unconditional cancellation completion.
    - Test URLSession delegate behavior directly with synthetic Foundation objects rather than timing-sensitive network redirects.
key-files:
  created: []
  modified:
    - Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/EphemeralURLSessionTransport.swift
    - Packages/SiriusXMClient/Tests/SiriusXMClientTests/EphemeralSessionTests.swift
key-decisions:
  - "Redirect instrumentation exposes only an internal scalar attempt count and never retains redirect or credential-bearing request data."
patterns-established:
  - "Redirect callbacks record entry under the request-state lock, inspect the existing contract policy without branching, then complete with nil."
requirements-completed: [AUTH-02, SECR-02, CLNT-03, CLNT-04]
coverage:
  - id: D1
    description: The real URLSession redirect delegate records each attempt before it cancels every follow-up request.
    requirement: AUTH-02
    verification:
      - kind: unit
        ref: Packages/SiriusXMClient/Tests/SiriusXMClientTests/EphemeralSessionTests.swift#productionRedirectCallbackCancelsEveryFollowUp
        status: pass
    human_judgment: false
  - id: D2
    description: Redirect handling keeps authorization material ephemeral by retaining only a scalar count and no active request state.
    requirement: SECR-02
    verification:
      - kind: integration
        ref: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SiriusXMClient
        status: pass
    human_judgment: false
duration: 2 min
completed: 2026-08-18
status: complete
---

# Phase 01 Plan 14: Redirect Callback Instrumentation Summary

**The ephemeral URLSession transport now proves each production redirect callback is counted under lock and terminated with a nil follow-up request.**

## Performance

- **Duration:** 2 min
- **Started:** 2026-08-18T17:43:51Z
- **Completed:** 2026-08-18T17:45:34Z
- **Tasks:** 1/1
- **Files modified:** 2

## Accomplishments

- Replaced the permanently-zero follow-up proxy with an internal redirect-delegate invocation count.
- Recorded callback entry under the existing request-state lock before policy inspection and unconditional cancellation.
- Added deterministic coverage for contract-shaped and unapproved redirect destinations, including nil completion and inactive request state.

## Task Commits

1. **Task 1: Observe one real redirect callback and prove nil follow-up**
   - `cb3729b` — RED direct-delegate regression
   - `27d9b11` — lock-protected production callback instrumentation

## Files Created/Modified

- `Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/EphemeralURLSessionTransport.swift` — records redirect callback entries and cancels every follow-up.
- `Packages/SiriusXMClient/Tests/SiriusXMClientTests/EphemeralSessionTests.swift` — invokes the production delegate with synthetic redirect inputs and captures its nil completion.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SiriusXMClient --filter EphemeralSessionTests` — passed (4 tests).
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SiriusXMClient` — passed (29 tests, 6 suites).
- Static scan confirmed the obsolete `followUpRequestCount` observation is absent and the production callback records an attempt before `completionHandler(nil)`.

## Decisions Made

- Kept redirect mechanics entirely internal: the sole test observation is a count, not a redirect destination, response, header, body, or credential-bearing request.
- Kept cancellation unconditional for both contract-shaped and unapproved destinations; policy inspection grants no redirect exception.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Known Stubs

None.

## Next Phase Readiness

IN-01 now has production-callback evidence. The fail-closed direct-request boundary remains deterministic and ready for later transport or compatibility work.

## Self-Check: PASSED

- Both modified source and test files exist.
- RED commit `cb3729b` and GREEN commit `27d9b11` exist in git history.
