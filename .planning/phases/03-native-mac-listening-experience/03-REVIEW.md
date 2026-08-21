---
phase: 03-native-mac-listening-experience
reviewed: 2026-08-21T21:22:00Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - SiriusMac/App/ListeningSessionController.swift
  - SiriusMac/Catalog/ListeningPresentationModel.swift
  - SiriusMac/Catalog/ListeningView.swift
  - SiriusMac/Listening/PlaybackCoordinator.swift
  - SiriusMacTests/ListeningSessionControllerTests.swift
  - SiriusMacTests/MetadataPresentationTests.swift
findings:
  critical: 0
  warning: 1
  info: 0
  total: 1
status: issues_found
---

# Phase 03: Code Review Report

**Reviewed:** 2026-08-21T21:22:00Z
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found

## Summary

The cancellation fix invalidates the coordinator generation before publishing `.stopped`, so a resolver that ignores cancellation cannot replace a later navigation. The context-menu Tune item and double-click are pending-aware while ordinary row selection and favorite controls remain enabled. The focused Xcode suite passed: 25 tests across `ListeningSessionControllerTests` and `MetadataPresentationTests`; `git diff --check 1f3dadb..90a60a5` was clean.

One timing gap remains: cancellation requests route through a newly scheduled main-actor task. Therefore a caller that cancels a returned tune task and immediately invokes next/previous in the same actor turn sees the stale pending gate and has its navigation rejected. The new regression test yields until the gate clears, so it does not cover that required timing variant.

## Narrative Findings (AI reviewer)

## Warnings

### WR-01 [WARNING]: Same-turn navigation is still rejected immediately after cancellation

**File:** `/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningPresentationModel.swift:173-183`; `/Users/gabe/sirius-mac/SiriusMacTests/ListeningSessionControllerTests.swift:499-507`

**Issue:** The cancellation handler schedules `Task { @MainActor ... cancellationRelay.cancel() }` rather than applying cancellation before `Task.cancel()` returns. Until that task runs, `isTunePending` remains `true`, so `ListeningSessionController.navigate` rejects a next/previous request through its `!listeningModel.isTunePending` guard. The new test masks this by yielding in a loop until pending clears before calling `previous()`. Cancellation is eventually safe and stale resolution is invalidated, but the required cancellation-timing behavior is not atomic: a same-turn follow-up navigation silently fails.

**Fix:** Make the cancellation transition observable synchronously at the model boundary, while preserving the coordinator generation invalidation before re-opening navigation. One approach is to retain a main-actor-owned tune-request token and have cancellation synchronously mark it terminal, then call the coordinator cancellation method from the same main-actor context; alternatively expose a non-suspending cancellation method on the model/controller. Add a deterministic no-yield regression:

```swift
replacement.cancel()
let followUp = controller.previous() // no Task.yield() first
XCTAssertNotNil(followUp)
```

The test should also complete the ignored cancelled resolver after the follow-up confirms playback, proving the stale result cannot replace it.

---

_Reviewed: 2026-08-21T21:22:00Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
