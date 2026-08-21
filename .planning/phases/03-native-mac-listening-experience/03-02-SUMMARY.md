---
phase: 03-native-mac-listening-experience
plan: 02
subsystem: local-library
tags: [swiftdata, swiftui, observation, favorites, recents, privacy]
requires:
  - phase: 03-01
    provides: app-lifetime listening controller and confirmed playback state
provides:
  - one main-actor SwiftData facade for non-secret favorites and recents
  - stable-ID desired-state favorites shared by controller-owned library UI
  - confirmed-playback-only 50-entry recent history with destructive clear confirmation
affects: [03-03 library tabs, 03-04 compact player, 03-06 system media controls]
actuals:
  tokens: 18764
  tasks: 2
  commits: 4
tech-stack:
  added: [SwiftData]
  patterns: [main-actor ModelContext facade, explicit durable allow-list, confirmed-transition persistence]
key-files:
  created: [SiriusMac/Library/LibraryStore.swift, SiriusMacTests/LibraryStoreTests.swift]
  modified: [SiriusMac/App/ListeningSessionController.swift, SiriusMac/Catalog/ListeningView.swift, SiriusMac/SiriusMacApp.swift, SiriusMacTests/ListeningSessionControllerTests.swift]
key-decisions:
  - "Persist only stable identity, name, display number, category, rank, and confirmation time; provider, resource, metadata, artwork, and session values remain out of SwiftData."
  - "The controller observes newly published confirmed playback state and records a recent only when the current semantic catalog supplies a safe snapshot."
  - "Favorites use desired-state commands under one main actor instead of read-then-toggle operations."
patterns-established:
  - "App-lifetime local state is injected from ListeningSessionController into scene roots; views never create ModelContainer instances."
  - "Durable model schema changes require an allow-list contract test."
requirements-completed: [LIBR-01, LIBR-02, LIBR-03]
coverage:
  - id: D1
    description: "Stable-ID favorite state is idempotent, unique, and shared through the controller-owned local store."
    requirement: LIBR-01
    verification:
      - kind: unit
        ref: "SiriusMacTests/LibraryStoreTests.swift#testSettingFavoriteTrueTwiceKeepsOneStableRecord"
        status: pass
      - kind: unit
        ref: "SiriusMacTests/LibraryStoreTests.swift#testInterleavedDesiredFavoriteCommandsEndAtLastStateWithoutDuplicates"
        status: pass
    human_judgment: false
  - id: D2
    description: "Recents are recorded only after confirmed playback, ordered uniquely, capped at fifty, and clearable without changing favorites."
    requirement: LIBR-02
    verification:
      - kind: integration
        ref: "SiriusMacTests/ListeningSessionControllerTests.swift#testControllerRecordsARecentOnlyAfterNewConfirmedPlayback"
        status: pass
      - kind: unit
        ref: "SiriusMacTests/LibraryStoreTests.swift#testRecentsRetainExactlyTheNewestFiftyUniqueConfirmedChannels"
        status: pass
    human_judgment: false
  - id: D3
    description: "SwiftData records expose only the declared non-secret presentation allow-list."
    requirement: LIBR-03
    verification:
      - kind: unit
        ref: "SiriusMacTests/LibraryStoreTests.swift#testDurableModelsExposeOnlyTheDeclaredSafeAllowList"
        status: pass
    human_judgment: false
duration: 8min
completed: 2026-08-21
status: complete
---

# Phase 03 Plan 02: Shared Favorites and Confirmed Recents Summary

**A controller-owned SwiftData library now shares idempotent stable-ID favorites and a secret-safe, confirmed-playback recent history across native listening surfaces.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-08-21T12:44:02-04:00
- **Completed:** 2026-08-21T12:51:37-04:00
- **Tasks:** 2
- **Files modified:** 7
- **Verification:** focused `LibraryStoreTests` and full Xcode suite passed (131 tests).

## Accomplishments

- Added one main-actor `LibraryStore` and `ModelContext` facade with an explicit durable allow-list for favorites, recents, and bounded player preferences.
- Wired favorite actions in library channel rows to the controller-owned store; repeated desired-state commands remain unique and immediate.
- Recorded recents only after a new confirmed `.playing(channelID)` transition has a current safe catalog snapshot; replay moves the item to rank zero and history retains the newest 50 unique channels.
- Added the approved Clear Recents confirmation text and empty-state copy without changing favorites.

## Task Commits

1. **Task 1: Deliver shared idempotent favorites from one safe local store**
   - `89c4f7d` — `test(03-02): add failing library store contract tests`
   - `0bf9918` — `feat(03-02): add shared safe favorite store`
2. **Task 2: Record, order, cap, and clear only confirmed-listen recents**
   - `4f9039a` — `test(03-02): add failing confirmed recent tests`
   - `d491744` — `feat(03-02): persist confirmed listening recents`

## Files Created/Modified

- `SiriusMac/Library/LibraryStore.swift` — SwiftData records, safe snapshots, favorites, recents, and preference schema.
- `SiriusMacTests/LibraryStoreTests.swift` — idempotency, ordering, cap, clear, and durable-schema coverage.
- `SiriusMac/App/ListeningSessionController.swift` — app-lifetime store ownership and confirmed-transition observer.
- `SiriusMac/Catalog/ListeningView.swift` — favorite controls, recent empty state, and clear-confirmation UI.
- `SiriusMac/SiriusMacApp.swift` — injects the controller-owned store into the library root.
- `SiriusMacTests/ListeningSessionControllerTests.swift` — confirms no recent is recorded before playback confirmation.
- `SiriusMac.xcodeproj/project.pbxproj` — registers the store and its test source exactly once in their targets.

## Decisions Made

- Favorites are desired-state mutations keyed by `LiveChannelID`, so repeated and interleaved commands cannot read then toggle stale state.
- The local store persists only presentation-safe scalar fields and never accepts a local record as authority to tune.
- Recents derive from confirmed coordinator state, not tune intent, pending work, failures, cancellation, pause, or stop.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical integration] Injected the store through the app library root.**
- **Found during:** Task 1
- **Issue:** The plan required a single controller-owned store in library rows, but the app root was omitted from the task file list and still constructed `ListeningView` without that store.
- **Fix:** Passed `controller.libraryStore` through `LibraryRoot`.
- **Files modified:** `SiriusMac/SiriusMacApp.swift`
- **Verification:** focused library tests and full 131-test Xcode suite passed.
- **Committed in:** `0bf9918`

---

**Total deviations:** 1 auto-fixed (Rule 2).
**Impact on plan:** Necessary wiring only; no scope expansion.

## Issues Encountered

- The first sandboxed Xcode invocation could not write normal Xcode module caches. Re-running the same required test command with approved local build-cache access produced the expected RED and subsequent green runs.

## Known Stubs

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 03-03 can render Favorites and Recents tabs from the shared `LibraryStore` projections.
- Compact-player and system-media work can consume the same favorites/recents state without adding persistence ownership.

## Self-Check: PASSED

- Confirmed the created store and test files exist and all four task commits are reachable in git history.

---
*Phase: 03-native-mac-listening-experience*
*Completed: 2026-08-21*
