---
phase: 03-native-mac-listening-experience
reviewed: 2026-08-21T21:32:44Z
depth: standard
files_reviewed: 7
files_reviewed_list:
  - SiriusMac/App/ListeningSessionController.swift
  - SiriusMac/Catalog/ListeningPresentationModel.swift
  - SiriusMac/Catalog/ListeningView.swift
  - SiriusMac/Library/PlaybackQueue.swift
  - SiriusMac/Listening/PlaybackCoordinator.swift
  - SiriusMac/SiriusMacApp.swift
  - SiriusMacTests/ListeningSessionControllerTests.swift
findings:
  critical: 1
  warning: 0
  info: 0
  total: 1
status: issues_found
---

# Phase 03: Code Review Report

**Reviewed:** 2026-08-21T21:32:44Z
**Depth:** standard
**Files Reviewed:** 7
**Status:** issues_found

## Summary

The new `ListeningTuneRequest` correctly makes the first cancellation synchronous: `cancel()` invalidates the coordinator generation and clears the pending gate before same-turn navigation. The focused `ListeningSessionControllerTests` suite passed (12 tests). The regression test deterministically covers cancellation followed by immediate navigation and confirms a cancellation-ignoring resolver cannot install stale playback.

However, the returned cancellation handle is not scoped to the tune that created it. A stale handle can cancel a later, unrelated tune. This is a playback correctness blocker and must be fixed before shipping.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01 [BLOCKER]: A stale cancellation handle can stop a newer tune

**File:** `/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningPresentationModel.swift:42-60`; `/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningPresentationModel.swift:72-84`; `/Users/gabe/sirius-mac/SiriusMac/Listening/PlaybackCoordinator.swift:572-577`

**Issue:** Every `ListeningTuneRequest.cancel()` invokes its captured `TuneCancellationRelay` without identifying the tune it owns. After request A is cancelled and request B begins, calling `A.cancel()` again (or calling it for the first time after A already completed) reaches `PlaybackCoordinator.cancelPendingTune()`. Because the coordinator only sees B's current `resolutionTask`/`.awaitingLiveContract` state, it invalidates B's generation, clears B's selected channel, and publishes `.stopped`. Repeated cancellation and cancel-after-completion therefore let an obsolete request terminate later playback.

**Fix:** Give each request a model-owned identity/generation and make cancellation idempotent and conditional on that request still being active. Clear the active identity before calling `cancelPendingTune()` so only the currently active request can invalidate the coordinator. For example:

```swift
private var activeTuneID: UUID?

func cancelTune(id: UUID) {
    guard activeTuneID == id else { return }
    activeTuneID = nil
    playbackCoordinator.cancelPendingTune()
    applyConfirmedPlaybackState(playbackCoordinator.state)
}
```

Pass `id` into `ListeningTuneRequest` and clear it on the matching terminal completion. Add deterministic tests that (1) cancel A, start B, then call `A.cancel()` again, and (2) complete A, start B, then call `A.cancel()`. In both cases B must remain pending and be able to confirm playback.

---

_Reviewed: 2026-08-21T21:32:44Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
