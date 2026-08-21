---
phase: 03-native-mac-listening-experience
reviewed: 2026-08-21T21:10:01Z
depth: standard
files_reviewed: 10
files_reviewed_list:
  - SiriusMac/App/ListeningSessionController.swift
  - SiriusMac/Catalog/ListeningPresentationModel.swift
  - SiriusMac/Catalog/ListeningView.swift
  - SiriusMac/SiriusMacApp.swift
  - SiriusMac/Library/PlaybackQueue.swift
  - SiriusMac/Listening/PlaybackCoordinator.swift
  - SiriusMac/Listening/SystemMediaController.swift
  - SiriusMacTests/ListeningSessionControllerTests.swift
  - SiriusMacTests/PlaybackQueueTests.swift
  - SiriusMacTests/SystemMediaControllerTests.swift
findings:
  critical: 1
  warning: 1
  info: 0
  total: 2
status: issues_found
---

# Phase 03: Code Review Report

**Reviewed:** 2026-08-21T21:10:01Z
**Depth:** standard
**Files Reviewed:** 10
**Status:** issues_found

## Summary

The synchronous `isTunePending` write now occurs before queue mutation or task scheduling, so the targeted no-yield next/previous race is fixed. Menu, compact-player, and MediaPlayer navigation predicates observe it, and confirmed playback still preserves the last-confirmed metadata/Now Playing semantics.

However, cancelling the returned replacement-tune task leaves the coordinator in `.awaitingLiveContract` and leaves `isTunePending` true forever. The separate Library window also continues to offer active Tune controls while that guard rejects their request.

Validation: `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/ListeningSessionControllerTests -derivedDataPath /private/tmp/siriusmac-review-derived` passed (11 tests). `git diff --check 1b68064^ 1b68064` was clean.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01 [BLOCKER]: Cancelling a replacement-tune task permanently latches navigation

**File:** `/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningPresentationModel.swift:150-153`; `/Users/gabe/sirius-mac/SiriusMac/Listening/PlaybackCoordinator.swift:657-665`

**Issue:** `ListeningPresentationModel.tune` sets `isTunePending` before returning an externally cancellable `Task`, but has no cancellation handler. If that task is cancelled while it replaces confirmed playback, `PlaybackCoordinator.tune` has already set `state = .awaitingLiveContract` (lines 552-565). When its resolver completes, the `!Task.isCancelled` guard returns without moving the coordinator to a terminal state (lines 661-665). The presentation model then re-applies `.awaitingLiveContract`, a state that deliberately does not clear `isTunePending` (lines 240-244). All next/previous/play-pause eligibility remains disabled indefinitely, despite the request having been cancelled.

**Fix:** Treat cancellation as a coordinated terminal operation: forward it to a main-actor coordinator cancellation method that invalidates the resolution and publishes `.stopped` or `.unavailable(.cancelled)`, then apply that state so the pending guard clears. Do not simply clear the guard in the task cancellation handler, because that would allow a still-running resolver to race a later navigation. Add a regression test that starts a confirmed replacement navigation, cancels its returned task before resolution completes, then verifies `isTunePending == false` and that a subsequent next/previous can be accepted.

```swift
return Task { [weak self, playbackCoordinator] in
    await withTaskCancellationHandler {
        await playbackCoordinator.tune(channelID)
        self?.applyConfirmedPlaybackState(playbackCoordinator.state)
    } onCancel: {
        Task { @MainActor [weak self, playbackCoordinator] in
            await playbackCoordinator.cancelPendingTune()
            self?.applyConfirmedPlaybackState(playbackCoordinator.state)
        }
    }
}
```

## Warnings

### WR-01 [WARNING]: Library Tune affordances remain enabled while their requests are rejected

**File:** `/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:449-457`

**Issue:** The primary library’s row context-menu Tune action and double-click path remain active during `isTunePending`. They call the controller, which correctly rejects the request before queue mutation, but the UI still advertises an available action that silently does nothing. This is inconsistent with the pending-aware menu, compact player, and MediaPlayer controls, and makes an in-flight navigation look broken.

**Fix:** Bind those Tune affordances to the same pending eligibility. Disable the context-menu Tune button when `model.isTunePending`, and guard the double-click action before calling `tune(channel)`; keep selection/favorite controls available.

```swift
Button("Tune") { tune(channel) }
    .disabled(model.isTunePending)

.onTapGesture(count: 2) {
    guard !model.isTunePending else { return }
    tune(channel)
}
```

---

_Reviewed: 2026-08-21T21:10:01Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
