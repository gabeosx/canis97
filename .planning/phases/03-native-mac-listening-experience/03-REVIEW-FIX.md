---
phase: 03-native-mac-listening-experience
fixed_at: 2026-08-21T21:33:42Z
review_path: /Users/gabe/sirius-mac/.planning/phases/03-native-mac-listening-experience/03-REVIEW.md
iteration: post-cap-4
findings_in_scope: 5
fixed: 4
skipped: 1
status: partial
---

# Phase 03: Code Review Fix Report

**Updated at:** 2026-08-21T21:33:42Z
**Source review:** `/Users/gabe/sirius-mac/.planning/phases/03-native-mac-listening-experience/03-REVIEW.md`
**Iteration:** post-cap-4

**Summary:**

- Findings in scope: 5
- Fixed: 4
- Remaining: 1

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

## Verification

All verification ran in the main checkout (the requested no-worktree mode).

- Focused `ListeningSessionControllerTests`: passed (12 tests), including cancellation followed immediately by Previous without `Task.yield()`.
- Full `xcodebuild test`: passed, 174 tests.
- `swift test` in `Packages/SiriusXMClient`: passed, 91 tests.
- Standalone `./script/build_and_run.sh --build-only`: passed.
- `git diff --check`: passed.

## Remaining Review Findings

- **CR-01 (blocker):** `ListeningTuneRequest.cancel()` is not scoped to the request that created it. Repeating cancellation on an old handle, or cancelling a completed handle after a newer tune starts, can invalidate and stop that newer tune. Cancellation must be idempotent and conditional on a matching active tune identity.

---

_Updated: 2026-08-21T21:33:42Z_
_Fixer: the agent (gsd-code-fixer)_
_Iteration: post-cap-4_
