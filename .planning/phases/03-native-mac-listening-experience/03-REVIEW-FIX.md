---
phase: 03-native-mac-listening-experience
fixed_at: 2026-08-21T20:12:53Z
review_path: /Users/gabe/sirius-mac/.planning/phases/03-native-mac-listening-experience/03-REVIEW.md
iteration: post-cap-1
findings_in_scope: 7
fixed: 6
skipped: 1
status: partial
commit_status: committed
---

# Phase 03: Code Review Fix Report

**Fixed at:** 2026-08-21T20:12:53Z
**Source review:** `/Users/gabe/sirius-mac/.planning/phases/03-native-mac-listening-experience/03-REVIEW.md`
**Iteration:** post-cap-1

**Summary:**

- Findings in scope across the review iterations: 7
- Fixed: 6
- Remaining: 1 warning
- Commit handoff: all six applied fixes are committed.

## Fixed Issues

### CR-01: A recoverable SwiftData initialization failure terminates the entire app

**Files modified:** `SiriusMac/Library/LibraryStore.swift`, `SiriusMacTests/LibraryStoreTests.swift`
**Commit:** `392cadb`
**Applied fix:** Durable SwiftData initialization falls back to in-memory storage when the durable container cannot open.

### WR-01: Failed metadata refresh leaves old metadata labeled as current

**Files modified:** `SiriusMac/Metadata/MetadataPresentationModel.swift`, `SiriusMacTests/MetadataPresentationTests.swift`
**Commit:** `7b2b2a2`
**Applied fix:** Failed metadata refreshes immediately mark retained content stale and cancel obsolete artwork work.

### WR-02: Retained failed-tune UI exposes a transport button that cannot act

**Files modified:** `SiriusMac/Player/CompactPlayerPresentation.swift`, `SiriusMacTests/CompactPlayerPresentationTests.swift`
**Commit:** `db5517e`
**Applied fix:** Pending and unavailable replacement states no longer retain obsolete compact-player transport controls.

### WR-03: Playback-queue tests are not compiled into the test target

**Files modified:** `SiriusMac.xcodeproj/project.pbxproj`
**Commit:** `875bbb1`
**Applied fix:** Added `PlaybackQueueTests.swift` to the SiriusMacTests sources build phase.

### Iteration 2 WR-01: Stopped compact state retains inert transport controls

**Files modified:** `SiriusMac/Player/CompactPlayerPresentation.swift`, `SiriusMacTests/CompactPlayerPresentationTests.swift`
**Commit:** `2224ac6`
**Applied fix:** Stopped compact state retains station identity without exposing inert transport controls.

### Post-cap WR-01: Library and Player-menu transport controls remain actionable when no command is valid

**Files modified:** `SiriusMac/App/ListeningSessionController.swift`, `SiriusMac/Authentication/AuthenticationView.swift`, `SiriusMac/Catalog/ListeningPresentationModel.swift`, `SiriusMac/Catalog/ListeningView.swift`, `SiriusMac/SiriusMacApp.swift`, `SiriusMacTests/ListeningSessionControllerTests.swift`, `SiriusMacTests/MetadataPresentationTests.swift`
**Commit:** `4389ca8`
**Applied fix:** A shared, confirmed-state command contract now disables invalid library and Player-menu controls. Previous/Next also require queue availability. Stop stays enabled only while the coordinator has cancellable playback work, including a pending tune or recoverable unavailable state.

## Remaining Issue After Final Post-Cap Re-review

### WR-01: System media commands stay enabled while a replacement tune is pending

The final 22-file review found that MediaPlayer command availability is not refreshed before the pending replacement-tune early return, and its handlers do not enforce the shared availability projection as a race-safe backstop. The library and Player menu are correct; system media remains inconsistent. See `03-REVIEW.md` for full remediation guidance.

## Verification

All verification ran in the **main checkout** (no isolated worktree).

- Focused `ListeningSessionControllerTests` and `MetadataPresentationTests`: passed.
- Full `SiriusMacTests` suite: passed.
- Standalone `SiriusMac` macOS build: passed.
- `git diff --check`: passed.

Xcode emitted pre-existing warnings in `AccessibilityAnnouncer.swift` and `WebAuthenticationBridgeTests.swift`; neither is part of this fix.

---

_Updated: 2026-08-21T20:12:53Z_
_Fixer: gsd-code-fixer with orchestrator commit handoff_
_Iteration: post-cap-1 (partial; one warning remains)_
