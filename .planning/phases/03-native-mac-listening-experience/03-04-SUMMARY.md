---
phase: 03-native-mac-listening-experience
plan: 04
subsystem: ui
tags: [swiftui, macos, compact-player, accessibility, presentation]
requires:
  - phase: 03-03
    provides: Shared listening session, library store, queue availability, and confirmed metadata projection
provides:
  - Closed compact-player semantic presentation and native fallback renderer
  - Typed app-owned compact controls and recovery actions
  - Accessible empty, pending, failure, fallback, and long-text compact states
affects: [03-05, 03-08, phase-04-skins]
actuals:
  tokens: 10015
  tasks: 2
  commits: 4
tech-stack:
  added: []
  patterns:
    - Renderer-independent Sendable/Equatable presentation values with typed action dispatch
    - Scene-owned retention of prior confirmed compact content during transient state changes
key-files:
  created:
    - SiriusMac/Player/CompactPlayerPresentation.swift
    - SiriusMac/Player/CompactPlayerView.swift
    - SiriusMacTests/CompactPlayerPresentationTests.swift
  modified:
    - SiriusMac/SiriusMacApp.swift
    - SiriusMac.xcodeproj/project.pbxproj
key-decisions:
  - "Compact rendering consumes only closed semantic values and app-owned typed actions; it owns no playback, persistence, or system-media collaborator."
  - "The scene retains only a prior confirmed presentation while pending or failure states are transient, preserving truthful confirmed content."
patterns-established:
  - "Compact accessibility: visual two-line metadata uses complete tooltip and VoiceOver values."
requirements-completed: [UI-01, UI-03]
coverage:
  - id: D1
    description: "Closed compact presentation maps confirmed channel, metadata, artwork, favorite, and queue state."
    requirement: UI-01
    verification:
      - kind: unit
        ref: "SiriusMacTests/CompactPlayerPresentationTests.swift#testConfirmedPlaybackMapsOnlySemanticSlots"
        status: pass
    human_judgment: false
  - id: D2
    description: "Compact empty, pending, recovery, fallback, and long-text semantics remain truthful and bounded."
    requirement: UI-03
    verification:
      - kind: unit
        ref: "SiriusMacTests/CompactPlayerPresentationTests.swift"
        status: pass
    human_judgment: true
    rationale: "The explicit 400 × 288 rendered long-text displacement check is reserved for Plan 03-08 native scene inspection."
duration: 11 min
completed: 2026-08-21
status: complete
---

# Phase 03 Plan 04: Compact Player Semantic Presentation Summary

**A fixed native compact player now renders closed confirmed listening state with typed controls, accessible recovery, and a skin-safe semantic seam.**

## Performance

- **Duration:** 11 min
- **Started:** 2026-08-21T17:09:58Z
- **Completed:** 2026-08-21T17:20:57Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Replaced the compact tracer with a 400 × 288 native SwiftUI fallback using closed semantic slots and approved palette, type, spacing, and native-control roles.
- Routed favorite, transport, library, and recovery requests through the existing shared controller; the renderer holds no playback, persistence, or system-media owner.
- Added exhaustive compact-state fixtures and focused tests for confirmed, empty, pending, recovery, fallback, and Unicode long-text behavior.

## Task Commits

1. **Task 1: Render the confirmed compact happy path through semantic slots** - `c7d4896` (test), `7ef445a` (feat)
2. **Task 2: Complete compact empty, pending, failure, fallback, and overflow states** - `7579c32` (test), `3ba62c1` (feat)

## Files Created/Modified

- `SiriusMac/Player/CompactPlayerPresentation.swift` - Closed semantic slots, style roles, bounded artwork, state projection, and typed recovery actions.
- `SiriusMac/Player/CompactPlayerView.swift` - Native compact fallback renderer, accessibility/tooltip semantics, and deterministic previews.
- `SiriusMac/SiriusMacApp.swift` - Connects the compact scene to shared session actions and retains confirmed content during transient states.
- `SiriusMacTests/CompactPlayerPresentationTests.swift` - State, style, recovery, fallback, and long-text contracts.
- `SiriusMac.xcodeproj/project.pbxproj` - Registers the compact source and test files.

## Decisions Made

- The rendering seam is a value type plus typed action enum: future appearance can alter bounded visual roles without gaining behavior or accessibility authority.
- The compact scene, not the renderer, retains the last confirmed semantic presentation through pending/failure changes.
- The pre-existing compact tracer lived in `SiriusMacApp.swift`, so that actual scene root was updated instead of the plan-listed `AuthenticationView.swift`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed unsupported image-resizing call from the native artwork wrapper**
- **Found during:** Task 1
- **Issue:** `NativeArtworkImage` is already a wrapped view and has no `resizable()` API.
- **Fix:** Rendered the validated artwork through its existing native view boundary.
- **Files modified:** `SiriusMac/Player/CompactPlayerView.swift`
- **Verification:** Focused and full Xcode tests passed.
- **Committed in:** `7ef445a`

**2. [Rule 3 - Blocking issue] Replaced the actual compact tracer at its real scene root**
- **Found during:** Task 1
- **Issue:** The plan identified `AuthenticationView.swift`, but the authenticated compact tracer is defined in `SiriusMacApp.swift`.
- **Fix:** Updated `CompactListeningSlice` in the actual scene root while preserving the shared controller identity.
- **Files modified:** `SiriusMac/SiriusMacApp.swift`
- **Verification:** Full Xcode suite passed.
- **Committed in:** `7ef445a`

---

**Total deviations:** 2 auto-fixed (1 Rule 1, 1 Rule 3)
**Impact on plan:** Both changes were necessary to build the planned compact surface correctly; no unrelated scope was added.

## Issues Encountered

- The first full-suite pass reported one non-reproducing failure in verbose Xcode output; an immediate `xcodebuild test -quiet` rerun completed successfully.

## Known Stubs

None. The `photo` artwork path is the approved missing-artwork fallback, not placeholder application data.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 03-05 can attach compact-only window policy to the existing Always on Top action hook without granting the renderer window ownership.
- Plan 03-08 must perform the explicit rendered 400 × 288 long-text displacement inspection; automated state contracts cover line limits and complete semantic values but do not claim rendered-layout evidence.

## Self-Check

PASSED

- Confirmed `CompactPlayerPresentation.swift`, `CompactPlayerView.swift`, and `CompactPlayerPresentationTests.swift` exist.
- Confirmed task commits `c7d4896`, `7ef445a`, `7579c32`, and `3ba62c1` exist in git history.

---
*Phase: 03-native-mac-listening-experience*
*Completed: 2026-08-21*
