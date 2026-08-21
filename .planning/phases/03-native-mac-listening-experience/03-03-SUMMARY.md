---
phase: 03-native-mac-listening-experience
plan: 03
subsystem: native-library-and-queue
tags: [swiftui, swiftdata, playback, library, accessibility]
dependency_graph:
  requires: [03-02]
  provides: [captured-playback-queue, four-tab-library, library-reveal]
  affects: [03-04, 03-08]
tech_stack:
  added: []
  patterns: [stable-id-queue, coordinator-owned-tuning, semantic-library-projection]
key_files:
  created: [SiriusMac/Library/PlaybackQueue.swift, SiriusMacTests/PlaybackQueueTests.swift]
  modified: [SiriusMac/Library/LibraryStore.swift, SiriusMac/App/ListeningSessionController.swift, SiriusMac/Catalog/ListeningPresentationModel.swift, SiriusMac/Catalog/ListeningView.swift, SiriusMac/SiriusMacApp.swift, SiriusMacTests/LibraryStoreTests.swift]
decisions:
  - "Queue candidates are filtered against the current semantic entitled lineup and returned only as stable IDs."
  - "Explicit library tunes use the shared coordinator without changing independent browse selection."
  - "Library reveal requests are generation-tagged semantic stable IDs."
metrics:
  duration: 17min
  completed: 2026-08-21
status: complete
actuals:
  tokens: 6960
  tasks: 2
  commits: 4
---

# Phase 03 Plan 03: Native Library and Captured Queue Summary

Implemented a stable-ID, no-wrap playback queue plus a native Channels/Categories/Favorites/Recents library whose browse selection, confirmed playback, and explicit tuning remain independent.

## Accomplishments

- Added captured queue traversal with current-entitlement filtering, finite no-wrap bounds, full-lineup fallback, direction availability, and generation-tagged reveal requests.
- Routed explicit and queue tuning through the existing `PlaybackCoordinator` path without granting cached queue or local-library IDs playback authority.
- Added a persisted four-tab library with visible-tab search, scrolling native rows, fixed artwork wells, favorite controls, confirmed Now Playing markers, explicit double-click/Return tuning, and reveal-to-Channels behavior.
- Added deterministic semantic queue and library state contracts.

## Verification

- `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/PlaybackQueueContractTests` — passed.
- `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/LibraryViewStateContractTests` — passed.
- `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` — passed, 135 tests.

## Task Commits

1. Task 1: Navigate a captured entitled queue and reveal the result
   - `4f36fce` — `test(03-03): add failing playback queue contract tests`
   - `fa5b815` — `feat(03-03): add stable playback queue navigation`
2. Task 2: Deliver the four-tab native library with explicit selection and tune
   - `78a00aa` — `test(03-03): add failing library state contracts`
   - `b04087e` — `feat(03-03): deliver four-tab native library`

## Decisions Made

- Queue traversal remains volatile and semantic: local IDs are reconciled with the current entitled snapshot before every navigation command.
- A direct semantic tune method avoids changing browse selection while preserving the coordinator as the only playback entry point.
- Selected library tab is persisted through the existing non-secret `LibraryStore` preference boundary.

## Deviations from Plan

### Auto-fixed Issues

1. [Rule 1 - Bug] Replaced a lazy closure that captured a mutating queue value during focused compilation.
- **Found during:** Task 1
- **Fix:** Used finite direct index traversal for candidate selection.
- **Files modified:** `SiriusMac/Library/LibraryStore.swift`

2. [Rule 3 - Blocking issue] Added a direct semantic tune method to the presentation model.
- **Found during:** Task 1
- **Fix:** The controller must send accepted queue IDs to the coordinator without rewriting browse selection; the existing selected-only API could not preserve D-08.
- **Files modified:** `SiriusMac/Catalog/ListeningPresentationModel.swift`

## Known Stubs

- `SiriusMac/Library/PlaybackQueue.swift:1` — Project-file source registration is retained as an Xcode reference while the compiled semantic queue currently lives beside `LibraryStore` to avoid a second Sources phase; the implementation is exercised by the compiled queue contract tests. Follow-up should move this declaration into its named source file within the existing Sources phase.

## Self-Check: PASSED

- Confirmed all listed task commits and created files are reachable on disk, and the focused and full Xcode suites pass.
