---
phase: 03-native-mac-listening-experience
reviewed: 2026-08-21T19:16:29Z
depth: standard
files_reviewed: 20
files_reviewed_list:
  - Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift
  - SiriusMac.xcodeproj/project.pbxproj
  - SiriusMac/Accessibility/AccessibilityAnnouncer.swift
  - SiriusMac/App/ListeningSessionController.swift
  - SiriusMac/Catalog/ListeningPresentationModel.swift
  - SiriusMac/Catalog/ListeningView.swift
  - SiriusMac/Library/LibraryStore.swift
  - SiriusMac/Library/PlaybackQueue.swift
  - SiriusMac/Listening/SystemMediaController.swift
  - SiriusMac/Metadata/MetadataPresentationModel.swift
  - SiriusMac/Player/CompactPlayerPresentation.swift
  - SiriusMac/Player/CompactPlayerView.swift
  - SiriusMac/SiriusMacApp.swift
  - SiriusMac/Windows/CompactWindowController.swift
  - SiriusMacTests/AccessibilityContractTests.swift
  - SiriusMacTests/CompactPlayerPresentationTests.swift
  - SiriusMacTests/LibraryStoreTests.swift
  - SiriusMacTests/ListeningSessionControllerTests.swift
  - SiriusMacTests/PlaybackQueueTests.swift
  - SiriusMacTests/SystemMediaControllerTests.swift
findings:
  critical: 1
  warning: 3
  info: 0
  total: 4
status: issues_found
---

# Phase 03: Code Review Report

**Reviewed:** 2026-08-21T19:16:29Z
**Depth:** standard
**Files Reviewed:** 20
**Status:** issues_found

## Summary

The submitted listening, persistence, MediaPlayer, accessibility, and client-adapter changes were reviewed in context. The phase has one launch-time crash path and three user-visible robustness/test-reliability defects. No hard-coded credentials, command injection, arbitrary URL routing, or unsafe renderer execution was found in the reviewed scope.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01 [BLOCKER]: A recoverable SwiftData initialization failure terminates the entire app

**File:** `/Users/gabe/sirius-mac/SiriusMac/Library/LibraryStore.swift:420-425`

**Issue:** `LibraryStore()` is constructed unconditionally by `ListeningSessionController` during application launch, but `makeDefaultContainer()` turns every `ModelContainer` error into `preconditionFailure`. A corrupted/migration-incompatible local store, unavailable storage, or other SwiftData initialization failure therefore aborts the process before the user can sign in or listen. Library persistence is non-secret ancillary state and must not make the player unavailable.

**Fix:** Make container creation fallible at the composition boundary and either present a recoverable local-storage error or fall back to an explicitly in-memory `ModelContainer`. Do not call `preconditionFailure` for expected persistence initialization errors. For example:

```swift
private static func makeDefaultContainer() throws -> ModelContainer {
    try ModelContainer(for: FavoriteRecord.self, RecentRecord.self, PlayerPreferenceRecord.self)
}

// At composition, use an in-memory container (and a user-visible warning) if durable storage cannot open.
```

## Warnings

### WR-01 [WARNING]: Failed metadata refresh leaves old metadata labeled as current

**File:** `/Users/gabe/sirius-mac/SiriusMac/Metadata/MetadataPresentationModel.swift:165-173`

**Issue:** After a successful metadata result, a later `.unavailable` or `.failed` result only changes `availability` and clears the title/artist fields. It leaves `state.text` and `state.artwork` unchanged, so `nowPlayingSemanticMetadata`, the compact player, and the system Now Playing publisher continue to use the prior `.current` value as if it were fresh. The old expiry task also remains in place. This produces false current-program information whenever the upstream metadata call fails before the 90-second expiry.

**Fix:** On an unsuccessful refresh, immediately transition retained values to `.stale` (or to the channel fallback when no retained value is allowed), and keep expiry scheduling coherent. Add a test that returns `.current` once and then `.unavailable`/`.failed` before `staleAfter`.

### WR-02 [WARNING]: Retained failed-tune UI exposes a transport button that cannot act

**File:** `/Users/gabe/sirius-mac/SiriusMac/Player/CompactPlayerPresentation.swift:151-168`

**Issue:** When a replacement tune fails, `retainingConfirmedContent` correctly preserves the prior station artwork/text but also copies its `transport` unchanged. A previously playing station therefore renders a Pause button while the actual state is `.unavailable`; `toggleConfirmedPlayback()` rejects that state and the control does nothing. Previous/next availability can likewise describe the obsolete queue position.

**Fix:** Do not retain transport controls across `.unavailable`/`.pending` state, or rebuild `Transport` from the current playback state and queue availability with unsupported actions disabled. Cover a playing station followed by a failed tune in a presentation test.

### WR-03 [WARNING]: Playback-queue tests are not compiled into the test target

**File:** `/Users/gabe/sirius-mac/SiriusMac.xcodeproj/project.pbxproj:118`

**Issue:** `PlaybackQueueTests.swift` has a `PBXFileReference` and `PBXBuildFile` (`030300010000000000000001`) but is absent from the `SiriusMacTests` `PBXSourcesBuildPhase`. Its assertions, including queue fallback and reveal-request coverage, never execute under the Xcode test scheme.

**Fix:** Add `030300010000000000000001 /* PlaybackQueueTests.swift in Sources */` to the test target's source-build-phase `files` list (and retain it in the test group), then run the test target to verify it is discovered.

---

_Reviewed: 2026-08-21T19:16:29Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
