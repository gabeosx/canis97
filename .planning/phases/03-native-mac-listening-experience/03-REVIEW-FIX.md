---
phase: 03-native-mac-listening-experience
fixed_at: 2026-08-22T14:04:37Z
review_path: /Users/gabe/sirius-mac/.planning/phases/03-native-mac-listening-experience/03-REVIEW.md
iteration: final-bounded-ordering-repair
findings_in_scope: 9
fixed: 9
skipped: 0
status: all_fixed
---

# Phase 03: Code Review Fix Report

**Updated at:** 2026-08-22T14:04:37Z
**Source review:** `/Users/gabe/sirius-mac/.planning/phases/03-native-mac-listening-experience/03-REVIEW.md`
**Iteration:** final-bounded-ordering-repair

**Summary:**

- Findings in scope: 9
- Fixed: 9
- Remaining: 0

## Fixed Issues

### WR-01: A second remote navigation event can supersede the first before pending state is published

**Files modified:** `SiriusMac/App/ListeningSessionController.swift`, `SiriusMac/Catalog/ListeningPresentationModel.swift`, `SiriusMac/Catalog/ListeningView.swift`, `SiriusMac/SiriusMacApp.swift`, `SiriusMacTests/ListeningSessionControllerTests.swift`
**Commit:** 1b68064
**Applied fix:** Added a synchronous main-actor `isTunePending` gate before a tune task is scheduled. Controller navigation now checks this gate before advancing the queue, command availability disables non-cancel transport commands while it is set, and library, compact-player, menu, and system-media routes use the shared projection. The state clears on reset and on confirmed or terminal coordinator observations. A deterministic no-yield test sends immediate remote Next and Previous pairs, verifies the second event fails, and verifies exactly one replacement observation and queue movement occur per accepted event.

### CR-01: Cancelling a replacement-tune task permanently latches navigation

**Files modified:** `SiriusMac/Catalog/ListeningPresentationModel.swift`, `SiriusMac/Listening/PlaybackCoordinator.swift`, `SiriusMacTests/ListeningSessionControllerTests.swift`
**Commit:** b85f964
**Applied fix:** Added a cancellation relay for the externally returned tune task. It coordinates cancellation through `PlaybackCoordinator.cancelPendingTune()`, which invalidates the resolver generation and active observation before publishing `.stopped`; the relay then applies that terminal state so `isTunePending` clears even if cancellation happened before tune dispatch. A deterministic replacement-tune test holds a resolver that ignores cancellation, cancels the returned task, accepts a later Previous navigation, then releases the stale resolver and verifies it cannot replace the newer confirmed playback.

### WR-01: Library Tune affordances remain enabled while their requests are rejected

**Files modified:** `SiriusMac/Catalog/ListeningView.swift`, `SiriusMacTests/MetadataPresentationTests.swift`
**Commit:** 90a60a5
**Applied fix:** Disabled the Library context-menu Tune action during a pending tune and made the double-click Tune path return early during that same state. Favorite and selection behavior remains untouched. A source contract test locks both pending guards in place.

### WR-01: Same-turn navigation is rejected immediately after cancellation

**Files modified:** `SiriusMac/Catalog/ListeningPresentationModel.swift`, `SiriusMac/App/ListeningSessionController.swift`, `SiriusMacTests/ListeningSessionControllerTests.swift`
**Commit:** 82ec46c
**Applied fix:** Replaced the returned raw tune `Task` with a main-actor `ListeningTuneRequest`. Its cancellation method now invalidates the coordinator generation and applies the terminal state synchronously before it cancels the worker task, so a same-turn Next or Previous request is accepted only after stale resolver work is no longer authorized. The deterministic regression cancels a replacement tune, immediately navigates Previous without yielding, then completes the cancellation-ignoring resolver and proves it cannot replace the later confirmed playback.

### CR-01: Stale cancellation handles can stop a newer tune

**Files modified:** `SiriusMac/Catalog/ListeningPresentationModel.swift`, `SiriusMacTests/ListeningSessionControllerTests.swift`
**Commit:** 289eb46
**Applied fix:** Assigned each accepted tune a model-owned UUID and channel identity. Cancellation now reaches `PlaybackCoordinator.cancelPendingTune()` only when the handle still matches that active request, retires that identity synchronously before invalidating coordinator work, and is locally idempotent. Matching completion, matching confirmed playback, and reset retire the identity; queued terminal observations from older work leave a newer request's pending gate intact. Deterministic regressions prove both repeated cancellation of an already-cancelled handle and first-time cancellation of an already-completed handle cannot stop a newer pending tune, which still confirms playback.

### CR-01: Same-channel observations can retire a newer tune request

**Files modified:** `SiriusMac/Catalog/ListeningPresentationModel.swift`, `SiriusMac/Listening/PlaybackCoordinator.swift`, `SiriusMacTests/ListeningSessionControllerTests.swift`
**Commit:** b12ae63
**Applied fix:** Added immutable `PlaybackStatePublication` values containing both the coordinator command generation and the model-owned presentation generation. The coordinator captures and supplies the publication at its state-change boundary; the model accepts a publication while pending only when its presentation generation matches the active request, and never rereads mutable coordinator state from a delayed callback. Regressions prove an old queued `.playing(A)` cannot confirm a newer same-channel retune and an old queued terminal state cannot clear B's pending gate or A's confirmed metadata.

### CR-02: An item failure after installation permanently latches `isTunePending`

**Files modified:** `SiriusMac/Catalog/ListeningPresentationModel.swift`, `SiriusMac/Listening/PlaybackCoordinator.swift`, `SiriusMacTests/ListeningSessionControllerTests.swift`
**Commit:** b12ae63
**Applied fix:** Matching terminal publications (`.unavailable`, `.stopped`, and `.idle`) now retire the active tune identity. The session playback runtime retains its item-failure callback so deterministic tests can fire post-install failures. Replacement and same-channel-retune tests verify pending clears and a subsequent queue navigation or tune is accepted.

### CR-01: Publications from one coordinator generation can be applied out of order

**Files modified:** `SiriusMac/Catalog/ListeningPresentationModel.swift`, `SiriusMacTests/PlaybackInstallationOrderTests.swift`, `SiriusMacTests/ListeningSessionControllerTests.swift`
**Commit:** c3b99f6
**Applied fix:** Removed the unstructured observer task: the main-actor model now applies the coordinator's immutable publication inline, preserving source order for every state change in one coordinator generation. The request handle no longer uses `Task.yield()`. A deterministic observer test verifies `.awaitingLiveContract` then terminal publication delivery retains one generation and its source order; the replaced stale-terminal test verifies the terminal state is settled before a later tune can claim presentation ownership.

### CR-02: Stop can execute before the pending tune task and allow it to start playback afterward

**Files modified:** `SiriusMac/Catalog/ListeningPresentationModel.swift`, `SiriusMac/Listening/PlaybackCoordinator.swift`, `SiriusMacTests/ListeningSessionControllerTests.swift`
**Commit:** c3b99f6
**Applied fix:** The model now owns the accepted tune worker and checks its request identity both before and immediately after its dispatch seam. Stop synchronously retires and cancels that active request, then invokes the coordinator's synchronous stopped-state boundary before returning. The deterministic no-yield regression holds the worker before its first coordinator call, stops it, releases it, and proves zero resolve/install/play activity with a cleared pending gate and stopped coordinator.

## Verification

All verification ran in the main checkout (the requested no-worktree mode).

- Focused `ListeningSessionControllerTests`, `PlaybackInstallationOrderTests`, `MetadataPresentationTests`, and `ListeningCompositionTests`: passed, 76 tests.
- Full `xcodebuild test`: passed, 182 tests.
- `swift test` in `Packages/SiriusXMClient`: passed, 91 tests.
- Standalone `./script/build_and_run.sh --build-only`: passed.
- `git diff --check`: passed.

## Remaining Review Findings

None. The single final independent review reported `clean` with zero critical, warning, or informational findings; its focused 31-test suite and diff check passed.

---

_Updated: 2026-08-22T14:04:37Z_
_Fixer: the agent (gsd-code-fixer)_
_Iteration: final-bounded-ordering-repair_
