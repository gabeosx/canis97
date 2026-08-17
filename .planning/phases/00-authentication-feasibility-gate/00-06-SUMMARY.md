---
phase: 00-authentication-feasibility-gate
plan: "06"
subsystem: authentication-feasibility
tags: [swift, swiftpm, canonical-contract, provenance, approval-gate]
requires:
  - phase: 00-05
    provides: empirical-proof-v2 contract and current-Xcode readiness gate
provides:
  - strict canonical browser experiment construction contract
  - non-selecting native purpose-contract qualification
  - digest-bound experiment readiness and owner approval commands
affects: [phase-00-authentication-feasibility-gate, phase-01-safe-interoperability-foundation]
actuals:
  tokens: 8448
  tasks: 2
  commits: 4
tech-stack:
  added: []
  patterns: [closed semantic facts, canonical contract digest, fail-closed CLI approval binding]
key-files:
  created:
    - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/PublicAuthContract.swift
    - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/PublicAuthContractTests.swift
  modified:
    - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/CandidateSelection.swift
    - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityRunner/main.swift
key-decisions:
  - "Open third-party callback documentation remains an auditable fact and never alone blocks a bounded browser experiment."
  - "Native-purpose evidence is a non-selecting later-branch input; it cannot choose or launch native-direct authentication."
  - "Owner approval is issued only for an exact digest of canonical ready construction bounds."
patterns-established:
  - "Represent only closed semantic states and provenance enums; reject free text, unknown fields, raw-capture fields, and noncanonical bytes."
  - "Bind readiness and approval artifacts to a deterministic contract digest rather than summaries or mutable input."
requirements-completed: [FEAS-01, FEAS-02, FEAS-04, FEAS-05]
coverage:
  - id: D1
    description: Strict browser construction, provenance, and native-purpose contract validation
    requirement: FEAS-01
    verification:
      - kind: unit
        ref: Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/PublicAuthContractTests.swift
        status: pass
    human_judgment: false
  - id: D2
    description: Digest-bound readiness and owner approval commands that cannot select native-direct
    requirement: FEAS-02
    verification:
      - kind: unit
        ref: Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/PublicAuthContractTests.swift
        status: pass
      - kind: integration
        ref: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Spikes/AuthenticationFeasibility
        status: pass
    human_judgment: false
duration: 8min
completed: 2026-08-17
status: complete
---

# Phase 00 Plan 06: Safe Auth Experiment Contract Summary

**A strict, digest-canonical browser experiment contract that permits safe readiness with open documentation while keeping native-direct evidence conditional and non-selecting.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-08-17T17:27:00Z
- **Completed:** 2026-08-17T17:35:11Z
- **Tasks:** 2/2
- **Files modified:** 4

## Accomplishments

- Added strict browser construction and native-purpose schemas with closed provenance/state vocabularies, canonical bytes, and deterministic digests.
- Made open callback-documentation facts non-dispositive while incomplete safety bounds yield `browser-experiment-incomplete` and unsafe input fails closed.
- Added fixed runner commands to validate contracts, derive readiness, record a digest-bound owner approval, and validate that approval without echoing inputs.

## Task Commits

Each TDD task was committed as RED then GREEN:

1. **Task 1: Define the closed safe-construction and empirical contract schema**
   - `909fa0c` test: failing public contract tests
   - `bb04a1e` feat: canonical safe auth experiment contracts
2. **Task 2: Gate experiment readiness and approval commands on safe bounds**
   - `d2ed3ff` test: failing readiness approval tests
   - `a2e14e6` feat: readiness and digest-bound CLI approval implementation

## Files Created/Modified

- `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/PublicAuthContract.swift` — closed browser/native evidence schema, canonical parser, digest, readiness, and approval values.
- `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/CandidateSelection.swift` — browser readiness derivation and explicit non-selection for native purpose evidence.
- `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityRunner/main.swift` — fixed validation, readiness, approval-recording, and approval-validation commands.
- `Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/PublicAuthContractTests.swift` — boundary, provenance, canonicalization, incomplete, unsafe, and approval-binding coverage.

## Decisions Made

- A missing public third-party callback document is represented as `open`; it cannot create a false `NO-GO unsupported` or prevent a safely bounded owner-operated experiment.
- Native-purpose qualification never makes native-direct live-capable by itself; strict WebKit rule-out and separate owner approval remain external later conditions.
- The owner approval artifact validates the exact canonical contract digest, rejecting any changed or incomplete construction contract.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Spikes/AuthenticationFeasibility --filter PublicAuthContractTests` — passed (6 tests).
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Spikes/AuthenticationFeasibility` — passed (18 tests).
- `git diff --check HEAD~4 HEAD` — passed.

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None.

## Issues Encountered

The sandbox initially blocked Xcode’s normal module cache and the Git index. Both were resolved through narrowly scoped execution permissions; no project files or dependencies were changed to work around those environment constraints.

## User Setup Required

None - this plan deliberately does not contact SiriusXM or launch an authentication surface.

## Next Phase Readiness

The phase now has a canonical safe-construction and approval boundary for a later owner-operated WKWebView proof run. This plan does not establish live feasibility, authorize native-direct, or unlock Phase 1.

## Self-Check: PASSED

- Confirmed all four task commits exist in Git history.
- Confirmed the four plan source/test files exist at their recorded paths.

---
*Phase: 00-authentication-feasibility-gate*
*Completed: 2026-08-17*
