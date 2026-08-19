---
phase: 02-authorized-live-listening
plan: "04"
subsystem: native-catalog
tags: [swift, swiftui, swiftpm, catalog, offline-tests]
requires:
  - phase: 02-03
    provides: fixed live compatibility contracts and non-materialization boundary
provides:
  - strict, entitled semantic catalog snapshots with explicit freshness
  - a native SwiftUI channel browser with semantic-only selection
  - deterministic offline catalog and presentation test coverage
affects: [02-05, 02-07, playback, metadata]
actuals:
  tokens: 16466
  tasks: 2
  commits: 4
tech-stack:
  added: []
  patterns:
    - actor-owned semantic catalog refresh with last-valid stale fallback
    - injected main-actor SwiftUI listing flow with generation-based refresh protection
key-files:
  created:
    - SiriusMac/Catalog/ListeningView.swift
  modified:
    - Packages/SiriusXMClient/Sources/SiriusXMClient/Public/LiveListeningModels.swift
    - Packages/SiriusXMClient/Sources/SiriusXMClient/Public/SiriusXMClient.swift
    - SiriusMac/Catalog/ListeningPresentationModel.swift
    - SiriusMac/Authentication/AuthenticationView.swift
key-decisions:
  - "Catalog browsing consumes only closed semantic values and production fails closed until a later compatibility plan supplies materializable opaque inputs."
  - "The entitled view shares AuthenticationComposition's SiriusXMClient and stores selection as the stable channel identity only."
patterns-established:
  - "Keep provider request construction and response shapes out of SwiftUI; inject a closed semantic flow instead."
  - "Treat a retained catalog as visibly stale browsing data and never as tuning authority."
requirements-completed: [CAT-01, CAT-02, CAT-03]
coverage:
  - id: D1
    description: Strict entitled standard/app-only channel-linear catalog snapshots with deterministic filtering, identity, ordering, and stale fallback.
    requirement: CAT-01
    verification:
      - kind: unit
        ref: "swift test --package-path Packages/SiriusXMClient"
        status: pass
    human_judgment: false
  - id: D2
    description: Native entitled lineup browser with explicit fresh/stale/empty/failure state and selection that performs no playback work.
    requirement: CAT-02
    verification:
      - kind: unit
        ref: "xcodebuild test -only-testing:SiriusMacTests/SemanticListeningPresentationTests"
        status: pass
    human_judgment: false
  - id: D3
    description: Existing fixed listening contract remains compatible with the native catalog composition.
    requirement: CAT-03
    verification:
      - kind: integration
        ref: "xcodebuild test -only-testing:SiriusMacTests/ListeningCompositionTests"
        status: pass
    human_judgment: false
duration: 16min
completed: 2026-08-19
status: complete
---

# Phase 02 Plan 04: Entitled Catalog and Native Browser Summary

**Strict actor-owned catalog snapshots and a native SwiftUI lineup browser that expose only semantic, entitled channel data with explicit freshness.**

## Performance

- **Duration:** 16 min
- **Started:** 2026-08-19T18:06:10Z
- **Completed:** 2026-08-19T18:21:49Z
- **Tasks:** 2/2
- **Files modified:** 11

## Accomplishments

- Published strict semantic catalog models and filtering that retain only entitled standard/app-only linear channels, preserve optional presentation fields, and order deterministically.
- Added actor-owned one-refresh catalog access with explicit stale snapshots after a failed refresh, without exposing provider response material or opaque media values.
- Replaced the prior catalog/tune-check controls with a native SwiftUI lineup view that shares the authenticated client, displays fresh/stale/empty/failure state, and records a stable selection without playback work.

## Task Commits

Each TDD task was committed atomically:

1. **Task 02-04-01: Publish the strict entitled catalog snapshot** - `91ca774` (test), `b163377` (feat)
2. **Task 02-04-02: Browse and select the semantic lineup natively** - `0be5f6b` (test), `9618d5a` (feat)

## Files Created/Modified

- `Packages/SiriusXMClient/Sources/SiriusXMClient/Public/LiveListeningModels.swift` - closed public channel, freshness, entitlement, artwork-reference, and catalog-failure semantics.
- `Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift` - strict filtering, identity validation, deterministic ordering, and preflight support.
- `Packages/SiriusXMClient/Sources/SiriusXMClient/Public/SiriusXMClient.swift` - actor-owned semantic refresh and last-valid stale result handling.
- `Packages/SiriusXMClient/Tests/SiriusXMClientTests/LiveCatalogAdapterTests.swift` - deterministic invented-fixture coverage for CAT-01 through CAT-03 behavior.
- `SiriusMac/Catalog/ListeningPresentationModel.swift` - injected semantic catalog flow, single-flight refresh, generation protection, and selection-only state.
- `SiriusMac/Catalog/ListeningView.swift` - native SwiftUI channel browser with deterministic presentation and state UI.
- `SiriusMac/Authentication/AuthenticationView.swift` - transitions entitled users to the shared-client native browser and resets it on session cleanup.
- `SiriusMacTests/ListeningCompositionTests.swift` - offline presentation-flow coverage.

## Decisions Made

- Preserved Plan 02-03's fixed-operation safety boundary: the default catalog capability does not synthesize or dispatch a provider request while opaque materialization inputs remain unobserved. It returns a closed unavailable failure until a later compatibility plan authorizes that capability.
- Bound catalog browsing to the same `SiriusXMClient` used by `AuthenticationComposition`; the view cannot create a parallel session or inspect provider data.
- Removed runtime catalog/tune observation controls from the SwiftUI screen. Selection is intentionally non-playback work, so AVFoundation remains unobserved until Plan 02-05.

## TDD Gate Compliance

- RED and GREEN commits exist in order for both tasks: `91ca774` → `b163377` and `0be5f6b` → `9618d5a`.

## Verification

- `plutil -lint SiriusMac.xcodeproj/project.pbxproj` — passed.
- `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/SemanticListeningPresentationTests` — 5 tests passed.
- `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/ListeningCompositionTests` — 20 tests passed.
- `swift test --package-path Packages/SiriusXMClient` — 57 tests passed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Test contract] Updated the public consumer assertion for the new semantic catalog failure result.**
- **Found during:** Task 02-04-01
- **Issue:** A pre-existing public API test expected the older unconditional `.unavailable` result after the planned async semantic catalog API replaced it with an explicit authentication-unavailable failure.
- **Fix:** Updated the expectation while retaining the test's semantic-only public-consumer boundary.
- **Files modified:** `Packages/SiriusXMClient/Tests/PublicAPITests/PublicConsumerTests.swift`
- **Verification:** Full package suite passed.
- **Committed in:** `b163377`

**2. [Rule 1 - Test compilation] Bound actor-isolated test values before XCTest assertions.**
- **Found during:** Task 02-04-02
- **Issue:** XCTest autoclosures cannot contain `await`, which prevented the new deterministic catalog-flow tests from compiling.
- **Fix:** Retrieved actor call counts before the assertions.
- **Files modified:** `SiriusMacTests/ListeningCompositionTests.swift`
- **Verification:** Focused presentation suite passed (5 tests).
- **Committed in:** `9618d5a`

---

**Total deviations:** 2 auto-fixed (2 Rule 1)
**Impact on plan:** Both fixes preserved the plan's API and native UI boundaries; no provider operation, browser automation, runtime DOM manipulation, or playback behavior was added.

## Issues Encountered

The Xcode test runtime emitted sandbox-local App Intents service warnings (`com.apple.linkd.autoShortcut`), but the test sessions completed successfully. They are unrelated to catalog behavior.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The app now has a deterministic native selection surface fed only by semantic catalog snapshots.
- Materializing a live provider catalog or resolving/tuning media remains intentionally deferred behind the fixed compatibility boundary; no AVFoundation behavior was observed or added in this plan.

## Self-Check: PASSED

- Verified all listed client, app, test, and summary files exist.
- Verified each task's RED and GREEN commit exists in Git history.

---
*Phase: 02-authorized-live-listening*
*Completed: 2026-08-19*
