---
phase: 01-safe-interoperability-foundation
plan: "03"
subsystem: native-transport-and-diagnostics
tags: [swift, swiftpm, urlsession, oslog, security, redaction]
requires:
  - phase: 01-01
    provides: Opaque credential handoff and a reusable Foundation-only SwiftPM client boundary.
  - phase: 01-02
    provides: Fail-closed response classifiers and actor-owned session lifecycle seams.
provides:
  - Exact, client-owned ephemeral native transport for settled authentication and entitlement endpoints
  - Redirect-cancelling HTTPS host and request-shape policy for authorization material
  - Closed semantic OSLog diagnostics and synthetic-fixture structural rejection
affects: [01-04, 01-06, 01-07, phase-2]
actuals:
  tokens: 4470
  tasks: 2
  commits: 2
tech-stack:
  added: []
  patterns: [exact request contracts, ephemeral URLSession isolation, redirect cancellation, closed diagnostic events, structural fixture rejection]
key-files:
  created:
    - Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/SiriusXMRequestContract.swift
    - Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/EphemeralURLSessionTransport.swift
    - Packages/SiriusXMClient/Sources/SiriusXMClient/Diagnostics/SafeDiagnosticEvent.swift
    - Packages/SiriusXMClient/Sources/SiriusXMClient/Diagnostics/DiagnosticRedactor.swift
    - Packages/SiriusXMClient/Tests/SiriusXMClientTests/EphemeralSessionTests.swift
    - Packages/SiriusXMClient/Tests/FixtureTests/RedactionTests.swift
  modified:
    - Packages/SiriusXMClient/Package.swift
    - Packages/SiriusXMClient/Sources/SiriusXMClient/Public/AuthenticationModels.swift
key-decisions:
  - "Authorize only the two settled GET request contracts on api.edge-gateway.siriusxm.com; every redirect is cancelled after validation."
  - "Keep opaque credential material inaccessible to public consumers while allowing internal request construction through a scoped closure."
  - "Reject fixture structures and values containing sensitive terms instead of attempting to redact or export them."
patterns-established:
  - "Native authorization is permitted only after exact URL, method, header, and transport validation in one internal boundary."
  - "Diagnostic sinks take closed semantic enums and unrenderable handles, never arbitrary errors or transport values."
requirements-completed: [AUTH-02, SECR-02, SECR-03, CLNT-03, CLNT-04]
coverage:
  - id: D1
    description: Client-owned ephemeral transport restricts authorization to the settled request contract and cancels redirects.
    requirement: SECR-02
    verification:
      - kind: unit
        ref: "Packages/SiriusXMClient/Tests/SiriusXMClientTests/EphemeralSessionTests.swift"
        status: pass
    human_judgment: false
  - id: D2
    description: Closed diagnostics and fixture promotion structurally exclude secret-bearing keys and canary values.
    requirement: SECR-03
    verification:
      - kind: unit
        ref: "Packages/SiriusXMClient/Tests/FixtureTests/RedactionTests.swift"
        status: pass
    human_judgment: false
  - id: D3
    description: The full reusable client package remains deterministic and free of planning-artifact runtime dependencies.
    requirement: CLNT-04
    verification:
      - kind: integration
        ref: "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SiriusXMClient"
        status: pass
    human_judgment: false
duration: 6min
completed: 2026-08-18
status: complete
---

# Phase 01 Plan 03: Exact Native Transport and Safe Diagnostics Summary

**A client-owned ephemeral URLSession now sends authorization only to two exact settled endpoints, while diagnostics and fixtures structurally exclude upstream and secret material.**

## Performance

- **Duration:** 6 min
- **Started:** 2026-08-18T03:44:20Z
- **Completed:** 2026-08-18T03:50:32Z
- **Tasks:** 2
- **Files modified:** 10

## Accomplishments

- Added the exact HTTPS request contract for native authentication and entitlement verification, with no arbitrary URL or header construction surface.
- Added a client-owned ephemeral URLSession configuration with disabled shared cookie and credential stores, zero redirect follow-ups, and deterministic cancellation-state coverage.
- Added privacy-qualified OSLog emission for closed semantic events only, plus synthetic fixture validation that rejects recursive sensitive structures and values before promotion.

## Task Commits

1. **Task 1: Build exact ephemeral native authenticated transport** - `cb55b16` (feat)
2. **Task 2: Make diagnostics and fixtures safe by construction** - `0550879` (feat)

## Files Created/Modified

- `Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/SessionTransport.swift` - Injected internal transport seam for session verification.
- `Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/DirectHostPolicy.swift` - Exact HTTPS endpoint and authorization eligibility policy.
- `Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/EphemeralURLSessionTransport.swift` - Client-owned nonpersistent URLSession and redirect-cancelling delegate.
- `Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/SiriusXMRequestContract.swift` - Fixed authentication and entitlement request definitions.
- `Packages/SiriusXMClient/Sources/SiriusXMClient/Diagnostics/SafeDiagnosticEvent.swift` - Closed event taxonomy and privacy-qualified OSLog sink.
- `Packages/SiriusXMClient/Sources/SiriusXMClient/Diagnostics/DiagnosticRedactor.swift` - Recursive synthetic-fixture safety validator.
- `Packages/SiriusXMClient/Tests/SiriusXMClientTests/EphemeralSessionTests.swift` - Exact-host, configuration, redirect, and cancellation tests.
- `Packages/SiriusXMClient/Tests/FixtureTests/RedactionTests.swift` - Secret-canary exclusion and structural rejection tests.

## Decisions Made

- Retain authorization only in the narrow internal request builder, with an opaque credential’s material available to internal code through a scoped closure rather than a public accessor.
- Revalidate every redirect, then cancel it unconditionally; no redirect can forward authorization or become a second provider request.
- Reject unsafe fixtures at promotion rather than preserving a redacted approximation or adding an export path.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added a scoped internal credential-material closure.**
- **Found during:** Task 1 (Build exact ephemeral native authenticated transport)
- **Issue:** The existing opaque credential deliberately exposed no internal means to attach its material to the fixed native request without making it publicly readable.
- **Fix:** Added an internal, scoped `withVolatileMaterial` closure that keeps the material unavailable to public client consumers and persistence APIs.
- **Files modified:** `Packages/SiriusXMClient/Sources/SiriusXMClient/Public/AuthenticationModels.swift`
- **Verification:** `EphemeralSessionTests` and the full package suite pass.
- **Committed in:** `cb55b16`

**2. [Rule 1 - Bug] Corrected the scoped credential closure’s throwing signature.**
- **Found during:** Task 1
- **Issue:** The request builder must reject malformed authorization material, but the initial closure signature could not propagate that failure.
- **Fix:** Made the closure `rethrows` and propagated the validation error without exposing the material.
- **Files modified:** `Packages/SiriusXMClient/Sources/SiriusXMClient/Public/AuthenticationModels.swift`
- **Verification:** `EphemeralSessionTests` passes all four deterministic cases.
- **Committed in:** `cb55b16`

**3. [Rule 3 - Blocking] Added the missing isolated fixture test target.**
- **Found during:** Task 2 (Make diagnostics and fixtures safe by construction)
- **Issue:** The plan requires `FixtureTests/RedactionTests.swift`, but the SwiftPM manifest had no target that would compile or run the required suite.
- **Fix:** Added the dependency-free `FixtureTests` target to the package manifest.
- **Files modified:** `Packages/SiriusXMClient/Package.swift`
- **Verification:** `swift test --package-path Packages/SiriusXMClient --filter RedactionTests` passes.
- **Committed in:** `0550879`

**Total deviations:** 3 auto-fixed (1 Rule 1 bug fix, 1 Rule 2 critical security fix, 1 Rule 3 blocking fix).
**Impact on plan:** All changes preserve the locked native-request architecture, prevent material disclosure, and make the planned deterministic test suite executable without dependencies or provider contact.

## Issues Encountered

- The Context7 CLI was not installed in the environment, so the OSLog API use was verified against Apple’s official documentation and the Xcode compiler.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plans 01-04, 01-06, and 01-07 can inject the fixed transport seam while retaining the established fail-closed session actor and semantic public boundary.
- The request contract remains volatile by design: changed hosts, paths, redirects, or response behavior must terminate as unsupported rather than trigger a new authentication-method experiment.

## Self-Check: PASSED

- All ten changed source, manifest, and test files exist.
- Task commits `cb55b16` and `0550879` are present in git history with no tracked-file deletions.
- Focused transport and redaction suites pass, and the full SwiftPM package suite passes all 19 tests.

---
*Phase: 01-safe-interoperability-foundation*
*Completed: 2026-08-18*
