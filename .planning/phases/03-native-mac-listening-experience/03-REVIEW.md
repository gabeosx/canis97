---
phase: 03-native-mac-listening-experience
reviewed: 2026-08-22T13:37:45Z
depth: standard
files_reviewed: 7
files_reviewed_list:
  - SiriusMac/App/ListeningSessionController.swift
  - SiriusMac/Catalog/ListeningPresentationModel.swift
  - SiriusMac/Catalog/ListeningView.swift
  - SiriusMac/Listening/PlaybackCoordinator.swift
  - SiriusMacTests/ListeningSessionControllerTests.swift
  - SiriusMacTests/MetadataPresentationTests.swift
  - SiriusMacTests/PlaybackInstallationOrderTests.swift
findings:
  critical: 2
  warning: 0
  info: 0
  total: 2
status: issues_found
---

# Phase 03: Code Review Report

**Reviewed:** 2026-08-22T13:37:45Z
**Depth:** standard
**Files Reviewed:** 7
**Status:** issues_found

## Summary

Commit `b12ae63` correctly captures a `PlaybackStatePublication` at the coordinator boundary and successfully handles the stale previous-command and item-failure cases covered by its new tests. The focused `ListeningSessionControllerTests` suite passes (18 tests). Two ordering holes remain: the model asynchronously applies multiple publications from the same coordinator generation without an event sequence, and an enabled Stop command can be scheduled before the pending tune it is intended to cancel. Both can leave UI/media state inconsistent with the command the listener issued.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01 [BLOCKER]: Publications from one coordinator generation can be applied out of order

**File:** `/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningPresentationModel.swift:279-286`, `/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningPresentationModel.swift:299-300`, `/Users/gabe/sirius-mac/SiriusMac/Listening/PlaybackCoordinator.swift:538-547`

**Issue:** `PlaybackStatePublication` captures the command generation, but not a monotonically increasing event sequence. The coordinator can publish several semantic states within one command generation (for example `.awaitingLiveContract` at `PlaybackCoordinator.swift:610-612`, followed by `.playing` at line 903 or `.unavailable` at line 945). Each observer notification launches an independent unstructured `Task` at lines 279-286. Those tasks are not ordered by this code, while the filter at lines 299-300 accepts an equal generation. If the later `.playing`/terminal task is delivered first and the earlier `.awaitingLiveContract` task follows, the model regresses to awaiting after playback has been confirmed/failed. In the successful case it retains confirmed metadata while presenting an unresolved playback state; in the terminal case it can present an inert pending state after the request was retired. The added tests deliberately exercise only cross-generation publications, so they cannot expose this same-generation ordering gap.

**Fix:** Apply the `@MainActor` observer callback synchronously, which is safe because both the coordinator and model are main-actor isolated, or add an immutable per-publication sequence number and reject `sequence <= lastAppliedSequence`. Keep the command/presentation generations for cross-request filtering. Add a deterministic delivery seam that queues two publications from one coordinator generation and applies them in reverse order; assert the final model state remains the later `.playing` or terminal state, with the pending gate and metadata matching it.

### CR-02 [BLOCKER]: Stop can execute before the pending tune task and allow it to start playback afterward

**File:** `/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningPresentationModel.swift:203-215`, `/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningPresentationModel.swift:229-231`, `/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:150-153`, `/Users/gabe/sirius-mac/Listening/PlaybackCoordinator.swift:661-665`

**Issue:** `tune(_:)` synchronously marks the model pending but defers the call to `PlaybackCoordinator.tune` into a new unstructured task (lines 203-212). Stop is intentionally enabled during that pending period, yet `stopPlayback()` also merely queues a separate task through `command`. If the stop task runs before the tune task enters the coordinator, `PlaybackCoordinator.stop()` sees no selected channel, publishes `.stopped`, and returns. The older tune task can then run, install the selected channel, and start audio after the listener pressed Stop. The model observer rejects the early `.stopped` publication because its presentation generation is not the active request's generation, so it does not cancel the pending request either. The existing immediate-cancellation tests cover `ListeningTuneRequest.cancel()`, which invalidates the coordinator synchronously, but none covers the public Stop path that the UI keeps enabled.

**Fix:** Make Stop synchronously revoke the active tune request before creating any asynchronous coordinator work (for example, route it through the same request-scoped cancellation helper as `ListeningTuneRequest.cancel()`), then publish/update the stopped state. Alternatively, make the coordinator record a synchronous stop generation that a subsequently started tune must validate before resolving. Add a deterministic test that holds the tune task before its first coordinator call, invokes `stopPlayback()` with no yield, then releases the tune task; assert no resolver request/item installation/play request occurs and `isTunePending` is false.

---

_Reviewed: 2026-08-22T13:37:45Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
