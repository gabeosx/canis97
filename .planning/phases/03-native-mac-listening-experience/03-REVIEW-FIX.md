---
phase: 03-native-mac-listening-experience
fixed_at: 2026-08-21T21:22:58Z
review_path: /Users/gabe/sirius-mac/.planning/phases/03-native-mac-listening-experience/03-REVIEW.md
iteration: post-cap-4
findings_in_scope: 4
fixed: 3
skipped: 1
status: partial
---

# Phase 03: Code Review Fix Report

**Updated at:** 2026-08-21T21:22:58Z
**Source review:** `/Users/gabe/sirius-mac/.planning/phases/03-native-mac-listening-experience/03-REVIEW.md`
**Iteration:** post-cap-4

**Summary:**

- Findings in scope: 4
- Fixed: 3
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

## Verification

All verification ran in the main checkout (the requested no-worktree mode).

- Focused cancellation and Library Tune contract tests: passed (2 tests); the full focused `ListeningSessionControllerTests` plus `MetadataPresentationTests` selection also passed (25 tests).
- Full `xcodebuild test`: passed, 174 tests.
- `swift test` in `Packages/SiriusXMClient`: passed, 91 tests.
- Standalone `./script/build_and_run.sh --build-only`: passed.
- `git diff --check`: passed.

## Remaining Review Findings

- **WR-01 (warning):** cancellation cleanup is scheduled onto a new main-actor task, so a next/previous request made immediately after `Task.cancel()` in the same actor turn still sees `isTunePending == true` and is rejected. The existing cancellation regression yields before navigating and does not cover this no-yield timing.

---

_Updated: 2026-08-21T21:22:58Z_
_Fixer: the agent (gsd-code-fixer)_
_Iteration: post-cap-4_
