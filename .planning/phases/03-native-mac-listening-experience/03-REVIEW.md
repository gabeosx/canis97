---
phase: 03-native-mac-listening-experience
reviewed: 2026-08-21T21:49:59Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - SiriusMac/App/ListeningSessionController.swift
  - SiriusMac/Catalog/ListeningPresentationModel.swift
  - SiriusMac/Listening/PlaybackCoordinator.swift
  - SiriusMacTests/ListeningSessionControllerTests.swift
findings:
  critical: 2
  warning: 0
  info: 0
  total: 2
status: issues_found
---

# Phase 03: Code Review Report

**Reviewed:** 2026-08-21T21:49:59Z
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues_found

## Summary

Commit `289eb46` correctly scopes a returned cancellation handle to its active request, so a repeated or late cancellation of request A no longer directly cancels request B. The focused `ListeningSessionControllerTests` target passes. However, the model still identifies a coordinator observation only by channel ID and leaves a pending request active after an item-level terminal failure. Both defects can disable valid navigation or publish stale UI state, so this change is not ready to ship.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01 [BLOCKER]: Same-channel observations can retire a newer tune request

**File:** `/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningPresentationModel.swift:186-197`, `/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningPresentationModel.swift:276-280`, `/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningPresentationModel.swift:335-344`

**Issue:** A request is retired when any observed `.playing(channelID)` has the same `channelID` as `activeTuneChannelID`; no request/coordinator generation is compared. A same-channel retune therefore has this sequence: old channel A is playing, the old observation's `Task` is queued, the listener starts a new tune to A (which sets a new `activeTuneID` synchronously), then the queued task reads the still-old coordinator `.playing(A)` before the new tune task runs. Lines 277-280 treat that old playback confirmation as confirmation of the new request and clear `isTunePending`. The next navigation can then be accepted while the replacement tune is unresolved. The same missing observation identity permits a queued old terminal state to clear the last confirmed metadata after B has claimed the model but before B has updated the coordinator.

**Fix:** Carry a monotonically increasing, model-owned tune generation into the coordinator observation boundary (or expose a coordinator command generation with each state publication). Retire a request only when the observed generation equals the active request's generation; do not use a channel ID as confirmation. Capture the observed state and generation in the observation callback rather than reading only the coordinator's latest mutable state in a later `Task`. Add deterministic regressions for (1) an already-queued `.playing(A)` observation followed in the same main-actor turn by a retune to A, and (2) a queued terminal observation followed by B claiming the model; both must retain B's pending gate and the last confirmed metadata.

### CR-02 [BLOCKER]: An item failure after installation permanently latches `isTunePending`

**File:** `/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningPresentationModel.swift:190-195`, `/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningPresentationModel.swift:294-305`, `/Users/gabe/sirius-mac/Listening/PlaybackCoordinator.swift:668-691`, `/Users/gabe/sirius-mac/Listening/PlaybackCoordinator.swift:876-900`, `/Users/gabe/sirius-mac/SiriusMacTests/ListeningSessionControllerTests.swift:840-873`

**Issue:** `PlaybackCoordinator.tune` returns immediately after installing an item, while its state remains `.awaitingLiveContract` until AVFoundation later reports playing, paused, or failure. `applyCompletedTuneState` deliberately keeps the request active for that awaiting state (lines 315-321). If the item later fails, the coordinator publishes `.unavailable`, but the observation handler's terminal branch only clears `isTunePending` when `activeTuneID == nil` (lines 299-305). No task completion remains to retire the active ID, so the model remains permanently pending and all navigation stays disabled. The phase test runtime discards the `onFailure` callback (lines 840-851), so the new cancellation tests cannot detect this path.

**Fix:** Retire the active request when a terminal coordinator state is published for the active coordinator generation, including `.unavailable`, `.stopped`, and `.idle`; preserve the pending gate only for an observation positively known to be from a different generation. Extend `SessionPlaybackRuntime` to retain and invoke `onFailure`, then add a deterministic test that resolves/installs a replacement, fires an item failure before playing, and verifies `isTunePending` clears and subsequent navigation is accepted. Cover the equivalent failure after a same-channel retune as well.

---

_Reviewed: 2026-08-21T21:49:59Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
