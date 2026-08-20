---
phase: 02-authorized-live-listening
plan: "12"
subsystem: authentication
tags: [swift, swiftpm, authentication, diagnostics, persistence, testing]
requires:
  - phase: 02-11
    provides: bounded, redacted native authentication evidence
provides:
  - Closed 401/403 stage diagnostics for native authentication and entitlement
  - Persistence-gated active session publication with a non-durable failure outcome
affects: [02-13, 02-14, 02-17, authentication, Keychain persistence]
actuals:
  tokens: 4134
  tasks: 2
  commits: 2
tech-stack:
  added: []
  patterns:
    - Injected actor collaborators for a fully offline authentication transaction matrix
    - Active state publication only after opaque credential persistence succeeds
key-files:
  created: []
  modified:
    - Packages/SiriusXMClient/Sources/SiriusXMClient/Diagnostics/SafeDiagnosticEvent.swift
    - Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/AuthenticationFlowAdapter.swift
    - Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift
    - Packages/SiriusXMClient/Tests/SiriusXMClientTests/SessionCoordinatorTests.swift
key-decisions:
  - "Represent HTTP 401 and 403 only as fixed closed diagnostic outcomes, while retaining the existing public rejected result."
  - "Publish a durable active session only after the injected credential store succeeds; surface storage failure as a distinct semantic outcome."
patterns-established:
  - "Offline auth tests use only invented credentials, injected actors, and synthetic native responses."
  - "Cancellation after persistence begins is checked before active session publication."
requirements-completed: [CAT-03, PLAY-04]
coverage:
  - id: D1
    description: Closed stage-specific authorization rejection diagnostics with redaction canaries.
    requirement: CAT-03
    verification:
      - kind: unit
        ref: Packages/SiriusXMClient/Tests/SiriusXMClientTests/AuthenticationOutcomeTests.swift#authorizationRejectionsAreStageSpecificAndRedacted
        status: pass
    human_judgment: false
  - id: D2
    description: Durable session publication only after successful opaque credential persistence.
    requirement: PLAY-04
    verification:
      - kind: unit
        ref: Packages/SiriusXMClient/Tests/SiriusXMClientTests/SessionCoordinatorTests.swift#persistenceFailureDoesNotProduceActiveSession
        status: pass
    human_judgment: false
duration: 4min
completed: 2026-08-20
status: complete
---

# Phase 02 Plan 12: Native authentication diagnostics and durability summary

**Synthetic native authentication now identifies 401/403 at the exact profile or entitlement stage, and Ready is withheld until opaque credential persistence succeeds.**

## Performance

- **Duration:** 4 min
- **Completed:** 2026-08-20T14:55:31Z
- **Tasks:** 2/2
- **Files modified:** 8

## Accomplishments

- Added fixed `http-unauthorized` and `http-forbidden` diagnostic outcomes without admitting any response material into diagnostics.
- Added injected offline tests that prove profile and entitlement rejections short-circuit downstream verifier/store calls.
- Made credential-store success a prerequisite for `.active`; save failure has a separate public semantic result and cancellation cannot publish Ready.

## Incremental Gate 1

**GREEN.** Both named no-host SwiftPM suites passed:

- `swift test --package-path Packages/SiriusXMClient --filter AuthenticationOutcomeTests`
- `swift test --package-path Packages/SiriusXMClient --filter SessionCoordinatorTests`

No Xcode test host, SiriusMac app process, Keychain item, WebKit instance, provider request, or network service was accessed. The already-running production app was left untouched.

## Task Commits

1. **Task 02-12-01: Trace one synthetic 401/403 to its exact closed native stage** — `70ec363` (`feat`)
2. **Task 02-12-02: Gate ordinary Ready on confirmed credential persistence** — `5c2c7ad` (`feat`)

## Decisions Made

- Distinguish 401 from 403 only through closed enum labels and preserve the public fail-closed rejection semantics.
- A failed opaque store returns `credentialPersistenceFailed`; it never maps to the ordinary authenticated/Ready result.

## Deviations from Plan

None - plan executed as specified. The SwiftPM compiler required its normal user-level module cache outside the filesystem sandbox; the same package-only test commands were run with approval and remained offline/no-host.

## Issues Encountered

- The initial sandboxed SwiftPM invocation could not create its compiler module cache. This was an execution-environment permission issue before compilation, resolved by rerunning the exact package-only commands with approval.

## Next Phase Readiness

- Incremental Gate 1 is green; Plan 02-13 may expand the offline matrix without a new sign-in or app launch.
- The persistence result is semantic and closed; later app-host checks can consume it without exposing Keychain or provider details.

## Self-Check: PASSED

- Verified both task commits exist and all listed package files are present.
- Verified both required no-host SwiftPM suites pass.
