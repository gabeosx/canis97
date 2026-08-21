---
phase: 03-native-mac-listening-experience
reviewed: 2026-08-21T19:43:00Z
depth: standard
files_reviewed: 20
files_reviewed_list:
  - Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift
  - SiriusMac.xcodeproj/project.pbxproj
  - SiriusMac/Accessibility/AccessibilityAnnouncer.swift
  - SiriusMac/App/ListeningSessionController.swift
  - SiriusMac/Catalog/ListeningPresentationModel.swift
  - SiriusMac/Catalog/ListeningView.swift
  - SiriusMac/Library/LibraryStore.swift
  - SiriusMac/Library/PlaybackQueue.swift
  - SiriusMac/Listening/SystemMediaController.swift
  - SiriusMac/Metadata/MetadataPresentationModel.swift
  - SiriusMac/Player/CompactPlayerPresentation.swift
  - SiriusMac/Player/CompactPlayerView.swift
  - SiriusMac/SiriusMacApp.swift
  - SiriusMac/Windows/CompactWindowController.swift
  - SiriusMacTests/AccessibilityContractTests.swift
  - SiriusMacTests/CompactPlayerPresentationTests.swift
  - SiriusMacTests/LibraryStoreTests.swift
  - SiriusMacTests/ListeningSessionControllerTests.swift
  - SiriusMacTests/PlaybackQueueTests.swift
  - SiriusMacTests/SystemMediaControllerTests.swift
findings:
  critical: 0
  warning: 1
  info: 0
  total: 1
status: issues_found
---

# Phase 03: Code Review Report

**Reviewed:** 2026-08-21T19:43:00Z
**Depth:** standard
**Files Reviewed:** 20
**Status:** issues_found

## Summary

This final standard-depth re-review covered the declared client adapter, listening-state, persistence, MediaPlayer, window, accessibility, presentation, and test-target scope. The prior four findings remain resolved: SwiftData falls back to in-memory storage, failed metadata is immediately marked stale, failed replacement tunes suppress stale compact transport, and `PlaybackQueueTests.swift` is in the Xcode test target. The iteration-two compact stopped-state transport regression is also resolved.

`xcodebuild test -quiet -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -derivedDataPath /private/tmp/sirius-mac-final-review-derived` completed successfully. One user-facing transport-state defect remains outside the compact-player fix.

## Narrative Findings (AI reviewer)

## Warnings

### WR-01 [WARNING]: Library and menu transport controls remain actionable when no command is valid

**File:** `/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:130-138`; `/Users/gabe/sirius-mac/SiriusMac/SiriusMacApp.swift:153-164`

**Issue:** The library's Pause, Resume Live, and Stop buttons are always enabled, while the Player menu's Previous, Play/Pause, and Next commands are never disabled. Before the user has selected/tuned a channel, Pause or Resume calls `PlaybackCoordinator` with no selected channel and changes the UI to `.unavailable(.selectionUnavailable)`. After Stop, the menu's Play command calls `toggleConfirmedPlayback()`, which deliberately returns `nil` for `.stopped`; Previous and Next similarly return `nil` without feedback when the queue is unavailable. The compact presentation now suppresses these stale controls, but the library and menu still advertise actions that cannot execute.

**Fix:** Derive command eligibility from the same confirmed playback state and queue availability used by `ListeningSessionController`, disable unsupported controls in both surfaces, and add controller/view-contract tests for the initial and stopped states. For example:

```swift
Button("Pause") { _ = model.pausePlayback() }
    .disabled(model.playbackState != .playing(model.confirmedChannelID))

Button("Resume Live") { _ = model.resumePlaybackAtLiveEdge() }
    .disabled(model.playbackState != .paused || model.confirmedChannelID == nil)

Button("Previous") { _ = controller.previous() }
    .disabled(controller.queueAvailability != .previous && controller.queueAvailability != .both)
```

Give Stop its own eligibility predicate (including an in-flight tune that can be cancelled), and use the same predicates for the menu Play/Pause and Next controls.

---

_Reviewed: 2026-08-21T19:43:00Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
