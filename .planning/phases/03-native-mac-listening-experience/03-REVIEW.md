---
phase: 03-native-mac-listening-experience
reviewed: 2026-08-21T20:37:39Z
depth: standard
files_reviewed: 23
files_reviewed_list:
  - Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift
  - SiriusMac.xcodeproj/project.pbxproj
  - SiriusMac/Accessibility/AccessibilityAnnouncer.swift
  - SiriusMac/App/ListeningSessionController.swift
  - SiriusMac/Authentication/AuthenticationView.swift
  - SiriusMac/Catalog/ListeningPresentationModel.swift
  - SiriusMac/Catalog/ListeningView.swift
  - SiriusMac/Library/LibraryStore.swift
  - SiriusMac/Library/PlaybackQueue.swift
  - SiriusMac/Listening/PlaybackCoordinator.swift
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
  - SiriusMacTests/MetadataPresentationTests.swift
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

**Reviewed:** 2026-08-21T20:37:39Z
**Depth:** standard
**Files Reviewed:** 23
**Status:** issues_found

## Summary

All 23 submitted source and test files were re-read in context. The prior findings are resolved: storage has an in-memory fallback, failed metadata is marked stale immediately, failed or stopped replacement presentation has no inert transport, `PlaybackQueueTests.swift` is compiled by the test target, and pending replacement state disables MediaPlayer commands while retaining last-confirmed Now Playing content. Handler guards correctly reject events that arrive after the pending state has been observed.

One race remains before that asynchronous pending-state transition occurs: two immediate next/previous media events can queue competing tune tasks. The second task supersedes the first, so one intended navigation can be lost. No credential, URL, or media-key material is exposed in the reviewed code.

Validation completed successfully: `xcodebuild test -quiet -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -derivedDataPath /private/tmp/sirius-mac-phase03-final-review` and `swift test` in `Packages/SiriusXMClient` (91 package tests). `git diff --check` is clean.

## Narrative Findings (AI reviewer)

## Warnings

### WR-01 [WARNING]: A second remote navigation event can supersede the first before pending state is published

**File:** `/Users/gabe/sirius-mac/SiriusMac/App/ListeningSessionController.swift:145-151`, `/Users/gabe/sirius-mac/SiriusMac/App/ListeningSessionController.swift:455-482`; `/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningPresentationModel.swift:137-145`

**Issue:** `handleSystemNext`/`handleSystemPrevious` checks `commandAvailability` and then calls `navigate`, which immediately advances the `PlaybackQueue` but only starts the tune inside a newly scheduled `Task`. Until that task runs, `listeningModel.playbackState` is still `.playing` or `.paused`, so `commandAvailability` remains true and another media-key/Control Center event is accepted. The second `navigate` advances the queue again and its tune supersedes the first in `PlaybackCoordinator`; two rapid presses can therefore discard the first requested channel instead of disabling controls after the first command. The same timing window exists for the menu/library routes that invoke the shared controller navigation.

**Fix:** Make pending navigation visible synchronously at the controller/model boundary, then have every command predicate include that synchronous in-flight flag until the coordinator emits a terminal or confirmed state. Alternatively, expose a synchronous `beginTune` operation on `PlaybackCoordinator` that sets `.awaitingLiveContract` before returning the task. Keep the existing handler guards as a backstop, and add a controller test that sends two remote `next` events without yielding between them; it should return `.commandFailed` for the second event and create exactly one replacement observation.

```swift
// Set this before scheduling the task and clear it from the playback observer.
guard !isNavigationPending, commandAvailability.next else { return .commandFailed }
isNavigationPending = true
return next() == nil ? .commandFailed : .success
```

---

_Reviewed: 2026-08-21T20:37:39Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
