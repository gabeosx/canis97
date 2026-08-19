---
phase: 02-authorized-live-listening
plan: "05"
subsystem: playback
tags: [swift, avfoundation, avplayer, swiftui, siriusxmclient, tdd]
requires:
  - phase: 02-04
    provides: Fresh entitled catalog identities selected without playback authority
  - phase: 02-03
    provides: Fixed tune/resource contract and opaque Apple media handoff
provides:
  - Current-session, entitlement-gated live-stream resolution with closed failure domains
  - One composition-owned AVPlayer runtime and confirmed playback coordinator
  - Native tune, pause, current-live-edge resume, stop, and supersession semantics
affects: [03-native-control-surfaces, playback, media-controls]
actuals:
  tokens: 24701
  tasks: 2
  commits: 12
tech-stack:
  added: []
  patterns:
    - Opaque SPI-only resource handoff from SiriusXMClient to the app AVFoundation seam
    - Generation-guarded single-player command serialization with observation-confirmed state
key-files:
  created: []
  modified:
    - Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift
    - Packages/SiriusXMClient/Sources/SiriusXMClient/Public/LiveListeningModels.swift
    - Packages/SiriusXMClient/Sources/SiriusXMClient/Public/SiriusXMClient.swift
    - SiriusMac/Listening/PlaybackCoordinator.swift
    - SiriusMac/Authentication/AuthenticationView.swift
    - SiriusMac/Catalog/ListeningPresentationModel.swift
    - SiriusMacTests/ListeningCompositionTests.swift
key-decisions:
  - "Production composition injects its single composed SiriusXMClient into SiriusXMPlaybackResolver and one PlaybackCoordinator; unavailable defaults remain test-only."
  - "AVPlayer state is published only after current item/player observation confirms readiness, rate, and time-control status."
  - "Resume resolves the selected identity again and replaces the item at the current live edge; it never seeks a retained DVR offset."
  - "The authorized one-use live test is not retried: AVFoundation playback remains NOT OBSERVED."
patterns-established:
  - "Playback commands invalidate a generation before cancelling obsolete work, observations, and item installation."
  - "Presentation state observes the coordinator so delayed AVFoundation confirmations propagate to SwiftUI."
requirements-completed: [CAT-03, PLAY-01, PLAY-02, PLAY-04]
coverage:
  - id: D1
    description: Current-session live resolution returns only a generation-bound opaque Apple handoff with closed failure mapping.
    requirement: PLAY-04
    verification:
      - kind: unit
        ref: "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SiriusXMClient"
        status: pass
    human_judgment: false
  - id: D2
    description: One composed native coordinator serializes tune, pause, live-edge resume, stop, and channel-switch supersession without optimistic state.
    requirement: PLAY-02
    verification:
      - kind: unit
        ref: "SiriusMacTests/ListeningCompositionTests"
        status: pass
    human_judgment: false
  - id: D3
    description: A selected entitled channel receives a real AVFoundation playback attempt and produces an audibility outcome.
    requirement: PLAY-01
    verification:
      - kind: manual_procedural
        ref: "One-use production live proof"
        status: unknown
    human_judgment: true
    rationale: "The authorized one-use live action was consumed before production playback composition existed; no retry is authorized, so AVFoundation playback remains NOT OBSERVED."
status: complete
---

# Phase 02 Plan 05: Confirmed Native Playback Composition Summary

**Current-session live resolution and one composition-owned AVPlayer coordinator now provide closed, observation-confirmed native playback semantics, while real AVFoundation playback remains deliberately unobserved.**

## Performance

- **Duration:** 1h 47m
- **Started:** 2026-08-19T14:30:33-04:00
- **Completed:** 2026-08-19T16:17:13-04:00
- **Tasks:** 2/2
- **Files modified:** 14 implementation/test files (plus this summary)
- **Status:** Offline-complete

## Accomplishments

- Added `SiriusXMClient.resolveLiveStream(for:)` behavior that requires a current active, entitled session, preserves the fixed tune/resource/optional-key sequence, rechecks generation after each await, and returns only a redacted opaque handoff or a closed `LiveListeningFailure`.
- Composed the same production `SiriusXMClient` into `SiriusXMPlaybackResolver` and one `PlaybackCoordinator`; the entitled graph no longer constructs the unavailable default playback collaborators.
- Implemented one AVFoundation runtime with one `AVPlayer`, item observation before association, `replaceCurrentItem`, observation-confirmed playing/paused state, current-live-edge re-resolution on resume, idempotent stop, and generation-based cancellation of stale tune/switch callbacks.
- Bound `ListeningPresentationModel` to later coordinator state changes, so delayed AVFoundation confirmation reaches the UI instead of leaving it at the state present when a command returned.

## Task Commits

Each TDD task was committed atomically across its RED/GREEN and corrective coverage steps:

1. **Task 1: Resolve one selected channel through current authorization**
   - `1bce100` — `test(02-05): add failing live resolution failure coverage`
   - `86509a2` — `feat(02-05): enforce current-session live resolution`
   - `cc6f8d7` — `fix(02-05): align public live selection result`
   - `556de1d` — `test(02-05): add fixed resolver guardrails`
   - `fba20ab` — `feat(02-05): bound fixed live stream resolution`
   - `7a793a3` — `test(02-05): add production live adapter coverage`
   - `1e60db5` — `feat(02-05): wire bounded production live adapter`
2. **Task 2: Control one confirmed live player from the native browse surface**
   - `39122c9` — `test(02-05): add failing idempotent stop coverage`
   - `a7e31c2` — `feat(02-05): route native controls through one coordinator`
   - `8f990ea` — `docs(02-05): clarify AVFoundation proof gate`
   - `6693ea9` — `test(02-05): require production playback composition`
   - `bc166f8` — `feat(02-05): compose confirmed native playback`

## Files Created/Modified

- `Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift` — bounded tune/resource resolution and safe handoff lifecycle.
- `Packages/SiriusXMClient/Sources/SiriusXMClient/Public/LiveListeningModels.swift` and `SiriusXMClient.swift` — closed resolution availability, failure mapping, and current-session API.
- `Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift` and `SessionState.swift` — generation/session validity for live resolution.
- `Packages/SiriusXMClient/Tests/SiriusXMClientTests/LivePlaybackCoordinatorTests.swift` — fixed-contract, authorization, optional-key, and stale-work coverage.
- `SiriusMac/Authentication/AuthenticationView.swift` — real client-backed resolver and one coordinator in the production composition.
- `SiriusMac/Listening/PlaybackCoordinator.swift` — sole `AVPlayer` owner, command serialization, lifecycle teardown, and closed AVFoundation mappings.
- `SiriusMac/Catalog/ListeningPresentationModel.swift` and `ListeningView.swift` — semantic control routing and observation-propagated presentation state.
- `SiriusMacTests/ListeningCompositionTests.swift` — production composition, single-player, no-optimism, live-edge, stop, pause supersession, and safe-failure tests.

## Decisions Made

- The production playback authority is constructed beside the production client, not from default unavailable collaborators. Test-only generic composition remains fail-closed.
- The opaque playback handoff is consumed solely through `@_spi(Playback)` to create an `AVPlayerItem`; URLs, headers, keys, response bodies, item descriptions, and `NSError` text do not enter UI state or failures.
- Pause during an unresolved tune invalidates and cancels that generation before it can install or play; it is not merely a request to a future player item.
- Real provider playback is not inferred from a clean compilation or fake-runtime tests. The remaining AVFoundation live outcome is explicitly **NOT OBSERVED**.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SiriusXMClient` — **70/70 tests passed** across 11 suites.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/ListeningCompositionTests` — **25/25 focused app tests passed**.
- `plutil -lint SiriusMac.xcodeproj/project.pbxproj` — **passed**.
- Offline clean build — **passed**: `/private/tmp/sirius-mac-02-05-offline-final/Build/Products/Debug/SiriusMac.app`.
- Built executable SHA-256: `23fbcbb87cca1ac24e267dbd7782b26adfcc70aeaa8cdd10a4c79877519a6be0`.
- The full unfiltered app suite was intentionally **not run**: it exercises Keychain tests, which would violate this plan's explicit no-Keychain boundary.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Production composition] Replaced unavailable default playback collaborators in the entitled production graph.**
- **Found during:** Task 2
- **Issue:** The initial one-use production Tune action settled at `Playback unavailable` because `AuthenticationComposition` constructed `PlaybackCoordinator()` with unavailable default authorization and driver collaborators; no provider playback path was reached.
- **Fix:** Injected the already-composed `SiriusXMClient` into `SiriusXMPlaybackResolver` and the single composition-owned coordinator, then added production-composition coverage.
- **Files modified:** `SiriusMac/Authentication/AuthenticationView.swift`, `SiriusMac/Listening/PlaybackCoordinator.swift`, `SiriusMacTests/ListeningCompositionTests.swift`
- **Verification:** Focused composition tests pass 25/25.
- **Committed in:** `6693ea9`, `bc166f8`

**2. [Rule 1 - Async presentation] Propagated delayed playback confirmation to presentation state.**
- **Found during:** Task 2 review
- **Issue:** `ListeningPresentationModel` copied coordinator state only as a command returned, so later item/player callbacks could leave the UI at an old state.
- **Fix:** Added observation tracking that updates presentation state whenever the coordinator publishes a later state.
- **Files modified:** `SiriusMac/Catalog/ListeningPresentationModel.swift`, `SiriusMacTests/ListeningCompositionTests.swift`
- **Verification:** Focused composition tests pass 25/25.
- **Committed in:** `bc166f8`

**3. [Rule 1 - Command serialization] Made pause supersede an in-flight tune.**
- **Found during:** Task 2 review
- **Issue:** A pause issued during unresolved tune work could allow the stale tune to later install and play an item.
- **Fix:** Pause now invalidates/cancels unresolved work before it can install or publish state; a deterministic regression test proves no install/play follows.
- **Files modified:** `SiriusMac/Listening/PlaybackCoordinator.swift`, `SiriusMacTests/ListeningCompositionTests.swift`
- **Verification:** Focused composition tests pass 25/25.
- **Committed in:** `bc166f8`

---

**Total deviations:** 3 auto-fixed Rule 1 correctness issues.
**Impact on plan:** Required production-composition and asynchronous-command correctness work only; no provider contract, authorization, or control-surface scope expanded.

## Live Evidence Boundary

The authorized one-use production live test was consumed before this corrected composition was in place. It stopped locally at the prior `Playback unavailable` placeholder path. It made **no** tune, resource, key, media, or AVFoundation request, so no playback/audibility conclusion can be drawn. No retry is authorized; the current AVFoundation implementation remains **NOT OBSERVED** live.

## Known Stubs

None. The unavailable resolver in the generic test composition is intentional fail-closed test wiring; it is not the entitled production graph.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 3 control surfaces can reuse the existing composition-owned `PlaybackCoordinator` rather than creating a player or provider-request path. Any future AVFoundation live evidence must be explicitly authorized and remains separate from this offline-complete plan.

## Self-Check: PASSED

- Summary exists at `.planning/phases/02-authorized-live-listening/02-05-SUMMARY.md`.
- All 12 listed 02-05 task commits are present in repository history.
- The recorded offline artifact and checksum were produced by the final clean build.

---
*Phase: 02-authorized-live-listening*
*Completed: 2026-08-19*
