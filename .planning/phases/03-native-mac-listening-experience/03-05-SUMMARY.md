---
phase: 03-native-mac-listening-experience
plan: 05
subsystem: ui
tags: [swiftui, appkit, nswindow, swiftdata, xctest]
requires:
  - phase: 03-04
    provides: compact semantic presentation and app-owned compact actions
provides:
  - Role-scoped native compact and library window lifecycle policy
  - Persisted compact-only Always on Top preference and shared menu bindings
affects: [native-window-verification, phase-03-08, macos-lifecycle]
actuals:
  tokens: 7277
  tasks: 2
  commits: 4
tech-stack:
  added: []
  patterns: [role-scoped NSViewRepresentable window attachment, injected lifecycle policy, non-secret SwiftData preference projection]
key-files:
  created: [SiriusMac/Windows/CompactWindowController.swift]
  modified: [SiriusMac/SiriusMacApp.swift, SiriusMac/App/ListeningSessionController.swift, SiriusMac/Library/LibraryStore.swift, SiriusMac/Player/CompactPlayerView.swift, SiriusMacTests/ListeningSessionControllerTests.swift, SiriusMac.xcodeproj/project.pbxproj]
key-decisions:
  - "Use role-scoped NSWindow notifications instead of replacing SwiftUI window delegates."
  - "Make normal application termination the sole compact-close shutdown path; it invalidates playback without erasing credentials."
  - "Persist one desired Always on Top Boolean in the existing non-secret LibraryStore facade."
patterns-established:
  - "Window lifecycle decisions live in an injected policy layer; AppKit attachment only applies those decisions to the exact scene window."
  - "Compact and application menus bind to the same LibraryStore desired-state value."
requirements-completed: [MAC-01, UI-01, UI-03]
coverage:
  - id: D1
    description: Compact and library role policy, frame validation, close semantics, and preference persistence.
    requirement: UI-03
    verification:
      - kind: unit
        ref: "SiriusMacTests/ListeningSessionControllerTests.swift#WindowLifecyclePolicyTests"
        status: pass
    human_judgment: false
  - id: D2
    description: Native singleton focus, window close, off-screen recovery, and background-audio behavior on a running macOS app.
    requirement: MAC-01
    verification:
      - kind: unit
        ref: "xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'"
        status: pass
    human_judgment: true
    rationale: Actual multi-window and audio lifecycle behavior requires native running-app observation.
duration: 13min
completed: 2026-08-21
status: complete
---

# Phase 03 Plan 05: Native Window Lifecycle Summary

**Fixed 400 × 288 compact playback window and independent library window lifecycle with safe frame recovery and persisted compact-only Always on Top state.**

## Performance

- **Duration:** 13 min
- **Started:** 2026-08-21T17:32:00Z
- **Completed:** 2026-08-21T17:44:46Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- Added a narrow, role-scoped AppKit adapter that fixes compact sizing, preserves library resizing, uses separate frame identities, and rejects off-screen restored frames.
- Routed compact close through normal application termination and idempotent listening-session shutdown without credential erasure; library close remains non-destructive.
- Persisted the single Always on Top desired state through `LibraryStore`, with compact and application menu toggles sharing that checked value and changing only compact window level.

## Task Commits

1. **Task 1: Enforce compact-primary and library-nondestructive native lifecycle** — `3a85740` (RED tests), `fe9f609` (implementation)
2. **Task 2: Restore valid frames and remember Always on Top without touching playback** — `22ffdc1` (RED tests), `701bfac` (implementation)

## Files Created/Modified

- `SiriusMac/Windows/CompactWindowController.swift` — injected policy, narrow AppKit attachment, frame safety, close handling, and app termination observer.
- `SiriusMac/SiriusMacApp.swift` — attaches each role to its exact scene, wires shutdown, window commands, and shared preference bindings.
- `SiriusMac/App/ListeningSessionController.swift` — idempotent shutdown that invalidates listening state without credential cleanup.
- `SiriusMac/Library/LibraryStore.swift` — safe durable Always on Top projection.
- `SiriusMac/Player/CompactPlayerView.swift` — checked compact menu backed by the persisted desired state.
- `SiriusMacTests/ListeningSessionControllerTests.swift` — lifecycle and preference policy tests without opening production windows.

## Decisions Made

- Used window-scoped notifications rather than replacing SwiftUI's `NSWindowDelegate`, retaining SwiftUI scene behavior while making compact close explicit.
- Kept all window controls non-authoritative: neither scene ownership, library reopening, frame restoration, nor level changes constructs a player, alters queue state, or touches credentials.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Build correctness] Reconciled strict-concurrency isolation for AppKit observer tokens.**
- **Found during:** Task 1
- **Issue:** Swift 6 rejected a main-actor controller's nonisolated protocol conformance and Objective-C observer tokens in deinitializers.
- **Fix:** Marked the attachment protocol main-actor isolated and imported AppKit with its Objective-C concurrency boundary explicitly preconcurrent.
- **Files modified:** `SiriusMac/Windows/CompactWindowController.swift`
- **Verification:** Focused and full Xcode test suites pass.
- **Committed in:** `fe9f609`

**2. [Rule 1 - Build correctness] Disambiguated the resizable library maximum-size scalar.**
- **Found during:** Task 1
- **Issue:** Swift resolved `.greatestFiniteMagnitude` ambiguously between `Double` and `CGFloat`.
- **Fix:** Selected `CGFloat.greatestFiniteMagnitude` explicitly.
- **Files modified:** `SiriusMac/Windows/CompactWindowController.swift`
- **Verification:** Focused and full Xcode test suites pass.
- **Committed in:** `fe9f609`

**Total deviations:** 2 auto-fixed Rule 1 build-correctness fixes.

## Issues Encountered

The first sandboxed Xcode invocation could not write its system build caches. Running the same focused and full tests with normal Xcode cache access succeeded; no source or test behavior was skipped.

## Known Stubs

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Automated policy coverage is ready for native-window verification in Plan 03-08.
- The final native checkpoint should confirm real compact-close termination, library focus/reopen, valid-frame centering, background audio continuity, and compact-only floating level behavior.

## Self-Check: PASSED

- Confirmed `SiriusMac/Windows/CompactWindowController.swift` and `SiriusMacTests/ListeningSessionControllerTests.swift` exist.
- Confirmed task commits `3a85740`, `fe9f609`, `22ffdc1`, and `701bfac` exist in git history.

---
*Phase: 03-native-mac-listening-experience*
*Completed: 2026-08-21*
