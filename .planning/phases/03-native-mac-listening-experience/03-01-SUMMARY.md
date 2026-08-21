---
phase: 03-native-mac-listening-experience
plan: "01"
subsystem: native-macos-listening
tags: [swiftui, observation, avfoundation, metadata, redaction, xctest]
requires:
  - phase: 02-authorized-live-listening
    provides: authenticated composition, entitled catalog, confirmed AVFoundation playback, and metadata presentation seams
provides:
  - one application-lifetime listening session shared by compact and library scene roots
  - confirmed-playback-only metadata presentation independent from browse selection
  - strict, value-free live metadata compatibility diagnostics and timestamp decoding
affects: [03-02, 03-03, 03-04, compact-player, library-window, system-media-controls]
actuals:
  tokens: 20113
  tasks: 2
  commits: 10
tech-stack:
  added: []
  patterns: [app-lifetime session controller, semantic surface projection, confirmed-state metadata, closed schema diagnostics]
key-files:
  created:
    - SiriusMac/App/ListeningSessionController.swift
    - SiriusMacTests/ListeningSessionControllerTests.swift
  modified:
    - SiriusMac/SiriusMacApp.swift
    - SiriusMac/Catalog/ListeningPresentationModel.swift
    - SiriusMac/Metadata/MetadataPresentationModel.swift
    - Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift
key-decisions:
  - "Retain exactly one AuthenticationComposition and PlaybackCoordinator in an app-lifetime ListeningSessionController; scene roots receive it by reference."
  - "Treat browse selection as non-authoritative intent; only a confirmed coordinator transition may change active metadata."
  - "Keep live metadata compatibility evidence value-free: require the observed semantic fields, classify only allow-listed decoder shapes, and accept bounded fractional ISO-8601 timestamps."
patterns-established:
  - "Native scenes consume closed ListeningSurfaceState snapshots and command methods, never credentials, transport objects, resolved media resources, or provider payloads."
  - "Metadata UI distinguishes loading from unavailable and keeps a confirmed channel's metadata stable while browsing another row."
requirements-completed: [MAC-01, MAC-04, UI-03]
coverage:
  - id: D1
    description: "Compact and library surfaces share one app-owned listening session and exact PlaybackCoordinator identity."
    requirement: MAC-01
    verification:
      - kind: unit
        ref: "xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/ListeningSessionControllerTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "Browse selection cannot imply playback; metadata changes only after confirmed playing state and remains truthful through loading, pause, and reset."
    requirement: UI-03
    verification:
      - kind: unit
        ref: "xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/MetadataPresentationTests"
        status: pass
      - kind: unit
        ref: "xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'"
        status: pass
    human_judgment: false
  - id: D3
    description: "The repaired native tracer presents a real confirmed title and artist while playback is active."
    requirement: MAC-04
    verification:
      - kind: manual_procedural
        ref: "Approved final live tracer checkpoint (user response: ok good)"
        status: pass
    human_judgment: true
    rationale: "Visual/native playback presentation needs a human judgment beyond deterministic unit coverage."
duration: 1h 7m
completed: 2026-08-21
status: complete
---

# Phase 03 Plan 01: Shared Listening Session Tracer Summary

**One app-owned native listening session now fans confirmed playback and metadata to compact and library surfaces, with strict redacted compatibility handling for live metadata.**

## Performance

- **Duration:** 1h 7m
- **Started:** 2026-08-21T15:29:32Z
- **Completed:** 2026-08-21T16:36:49Z
- **Tasks:** 2
- **Files modified:** 11

## Accomplishments

- Added one `ListeningSessionController` that retains the authentication composition and its sole `PlaybackCoordinator` for the whole app lifetime; the compact and singleton library scenes consume that same controller.
- Separated browse selection from confirmed listening state, so a selection cannot tune or alter current metadata before the coordinator confirms playback.
- Repaired live metadata presentation end to end: catalog loading begins when authentication becomes ready, current metadata is surfaced truthfully, and decoder compatibility remains strict and value-free.
- Passed user verification of the final native tracer: active playback visibly presented a real title and artist.

## Task Commits

Each planned task was committed atomically; close-out repairs remain separately traceable.

1. **Task 1: Prove one authenticated tune across two singleton native surfaces** - `962100a` (RED tests), `6c44560` (shared session implementation)
2. **Task 2: Separate browse selection from confirmed active metadata** - `127f280` (implementation and coverage)
3. **Tracer repair: load entitled catalog and surface confirmed metadata** - `c0b0549`, `4316cc5`
4. **Tracer repair: value-free metadata compatibility diagnostics and strict semantic fields** - `a8d7fd4`, `be2cf5e`, `c87bb90`
5. **Tracer repair: observed fractional timestamp contract** - `e0da143` (RED regression), `d89c768` (decoder acceptance)

_TDD gate compliance: `962100a` supplies the RED gate before `6c44560` supplies the GREEN implementation; `e0da143` likewise precedes `d89c768` for the timestamp regression._

## Files Created/Modified

- `SiriusMac/App/ListeningSessionController.swift` - App-lifetime session ownership, semantic compact/library projections, readiness-driven catalog load, and truthful metadata state.
- `SiriusMac/SiriusMacApp.swift` - Injects the one controller into distinct compact and singleton library scene roots while preserving the inert XCTest host.
- `SiriusMac/Catalog/ListeningPresentationModel.swift` - Keeps browse intent separate from confirmed playback and active metadata identity.
- `SiriusMac/Metadata/MetadataPresentationModel.swift` - Projects current, stale, loading, and unavailable metadata truthfully.
- `SiriusMacTests/ListeningSessionControllerTests.swift` - Covers singleton composition/coordinator identity, inert test hosting, catalog loading, and shared confirmed state.
- `SiriusMacTests/MetadataPresentationTests.swift` - Covers confirmation-driven metadata, browse isolation, and metadata lifecycle behavior.
- `Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift` - Strict bounded metadata decoding, allow-listed schema diagnostics, required semantic fields, and fractional timestamp support.
- `Packages/SiriusXMClient/Tests/SiriusXMClientTests/MetadataRefreshCoordinatorTests.swift` - Regression coverage for metadata schema gates and supported timestamp precision.

## Decisions Made

- Construct authentication and playback composition once at app lifetime; window/view lifecycle never becomes a playback ownership boundary.
- Fan out only closed semantic snapshots and command routes to SwiftUI surfaces, preserving the plan threat-model boundary against credentials, sessions, provider payloads, URLs, and transport material.
- Treat appearance of metadata as confirmed coordinator state, not browsing state; loading is distinct from unavailable.
- Fail closed on unobserved metadata shapes while keeping diagnostics restricted to allow-listed schema classes and parser outcomes with no response values retained.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Ready authentication did not automatically populate the catalog and confirmed metadata presentation**
- **Found during:** Task 1 tracer verification
- **Issue:** The shared-session seam existed, but an entitled ready transition could leave the catalog unloaded and the compact surface unable to show the confirmed metadata lifecycle.
- **Fix:** Added one readiness-gated catalog load, propagated confirmed metadata into semantic surface state, and added deterministic controller/presentation coverage.
- **Files modified:** `SiriusMac/App/ListeningSessionController.swift`, `SiriusMac/Metadata/MetadataPresentationModel.swift`, `SiriusMac/SiriusMacApp.swift`, related tests
- **Verification:** Focused controller and metadata suites plus the full 122-test Xcode suite pass.
- **Committed in:** `c0b0549`

**2. [Rule 1 - Bug] Loading metadata was rendered as unavailable**
- **Found during:** Task 1 tracer verification
- **Issue:** An in-flight confirmed metadata request was indistinguishable from an unavailable result.
- **Fix:** Added a loading presentation state while retaining explicit unavailable fallback behavior.
- **Files modified:** `SiriusMac/App/ListeningSessionController.swift`, `SiriusMacTests/ListeningSessionControllerTests.swift`
- **Verification:** Focused controller suite and the full suite pass.
- **Committed in:** `4316cc5`

**3. [Rule 2 - Missing Critical Functionality] Compatibility diagnostics needed to remain useful without retaining protected provider data**
- **Found during:** Live tracer repair
- **Issue:** Decoder failure evidence needed bounded classification for repairability, but raw metadata bodies or values would violate the project safety boundary.
- **Fix:** Added only allow-listed shape, parser, and timestamp classes; no response values, identifiers, URLs, credentials, cookies, or stream material are logged or fixture-retained.
- **Files modified:** `Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift`, related tests
- **Verification:** Static safety scan of all plan-touched source/tests and full suite pass.
- **Committed in:** `a8d7fd4`, `c87bb90`

**4. [Rule 1 - Bug] Metadata contract rejected valid observed timestamp precision and accepted incomplete semantic song data**
- **Found during:** Live tracer repair
- **Issue:** The decoder required an overly narrow ISO-8601 timestamp form and did not enforce the observed paired title/artist semantic contract.
- **Fix:** Added a failing fractional-timestamp regression before bounded parser support, and required the corresponding semantic artist field for a current-song value.
- **Files modified:** `Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift`, `Packages/SiriusXMClient/Tests/SiriusXMClientTests/MetadataRefreshCoordinatorTests.swift`, `SiriusMacTests/ListeningSessionControllerTests.swift`
- **Verification:** Focused suites and full suite pass; live tracer was user-approved.
- **Committed in:** `be2cf5e`, `e0da143`, `d89c768`

---

**Total deviations:** 4 auto-fixed (3 Rule 1, 1 Rule 2)
**Impact on plan:** All fixes directly repaired the production tracer and its safety boundary; no new playback runtime, provider access path, window owner, or persistent data surface was introduced.

## Issues Encountered

- The initial close-out test run was blocked by sandbox access to Xcode caches and DerivedData. Re-running the same required commands with that build-system access succeeded: both focused suites and the full suite passed, with 122 total tests and zero failures.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Subsequent Phase 3 plans can consume the app-lifetime controller and closed presentation projections without acquiring playback or authentication ownership.
- The native tracer’s final visual/live verification is approved. Continue to treat volatile provider metadata schemas as fail-closed and diagnostics as value-free.

## Self-Check: PASSED

- Confirmed all ten production/test commits listed above exist in the repository history.
- Confirmed required controller, metadata, adapter, and regression-test files exist.
- Confirmed focused controller and metadata tests plus full `xcodebuild test` pass.
- Confirmed the introduced diagnostics and fixtures contain no raw protected response data, resolved stream URLs, credentials, cookies, stream material, provider identifiers, or user data; only intentional semantic redaction guard references and closed diagnostic classes remain.

---
*Phase: 03-native-mac-listening-experience*
*Completed: 2026-08-21*
