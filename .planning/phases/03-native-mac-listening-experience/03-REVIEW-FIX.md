---
phase: 03-native-mac-listening-experience
fixed_at: 2026-08-21T19:43:00Z
review_path: /Users/gabe/sirius-mac/.planning/phases/03-native-mac-listening-experience/03-REVIEW.md
iteration: 3
findings_in_scope: 6
fixed: 5
skipped: 1
status: partial
---

# Phase 03: Code Review Fix Report

**Fixed at:** 2026-08-21T19:43:00Z
**Source review:** `/Users/gabe/sirius-mac/.planning/phases/03-native-mac-listening-experience/03-REVIEW.md`
**Iteration:** 3 (automatic iteration cap reached)

**Summary:**

- Findings in scope across initial review and re-reviews: 6
- Fixed: 5
- Remaining: 1 warning

## Fixed Issues

### CR-01: A recoverable SwiftData initialization failure terminates the entire app

**Files modified:** `SiriusMac/Library/LibraryStore.swift`, `SiriusMacTests/LibraryStoreTests.swift`
**Commit:** `392cadb`
**Applied fix:** Durable SwiftData container initialization now explicitly falls back to an in-memory container; a regression test simulates durable-container failure and verifies the library remains usable.

### WR-01: Failed metadata refresh leaves old metadata labeled as current

**Files modified:** `SiriusMac/Metadata/MetadataPresentationModel.swift`, `SiriusMacTests/MetadataPresentationTests.swift`
**Commit:** `7b2b2a2`
**Applied fix:** Unavailable and failed refreshes now cancel in-flight artwork work and immediately mark retained metadata stale while the existing expiry schedule still controls final fallback.

### WR-02: Retained failed-tune UI exposes a transport button that cannot act

**Files modified:** `SiriusMac/Player/CompactPlayerPresentation.swift`, `SiriusMacTests/CompactPlayerPresentationTests.swift`
**Commit:** `db5517e`
**Applied fix:** Retained confirmed content no longer carries old transport controls into pending or unavailable replacement states.

### WR-03: Playback-queue tests are not compiled into the test target

**Files modified:** `SiriusMac.xcodeproj/project.pbxproj`
**Commit:** `875bbb1`
**Applied fix:** Added `PlaybackQueueTests.swift` to the SiriusMacTests sources build phase so its six queue and reveal-request tests execute normally.

### Iteration 2 WR-01: Stopped compact state retains inert transport controls

**Files modified:** `SiriusMac/Player/CompactPlayerPresentation.swift`, `SiriusMacTests/CompactPlayerPresentationTests.swift`
**Commit:** `2224ac6`
**Applied fix:** Stopped compact state now retains confirmed station identity without advertising transport actions that cannot execute.

## Remaining Issue After Iteration 3

### WR-01: Library and menu transport controls remain actionable when no command is valid

The final re-review found that library and Player-menu transport controls are not disabled consistently in initial, stopped, or queue-unavailable states. This warning remains open because the automatic three-iteration cap was reached. See `03-REVIEW.md` for the full finding and remediation guidance.

## Verification

All gates ran in the **main checkout** (no isolated worktree), using `/tmp/sirius-mac-review-fix-dd` for Derived Data.

- Focused `LibraryStoreTests`: 9 passed
- Focused `MetadataPresentationTests`: 11 passed
- Focused `CompactPlayerPresentationTests`: 10 passed
- Focused `PlaybackQueueTests`: 6 passed
- Full `SiriusMacTests` target after the five applied fixes: 166 passed, 0 failures
- Final iteration-3 re-review test run: passed

---

_Updated: 2026-08-21T19:43:00Z_
_Fixers: gsd-code-fixer plus orchestrator commit handoff for iteration 2_
_Iteration: 3 (partial; one warning remains)_
