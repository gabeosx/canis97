---
phase: 03-native-mac-listening-experience
reviewed: 2026-08-21T20:12:53Z
depth: standard
files_reviewed: 22
files_reviewed_list:
  - Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift
  - SiriusMac.xcodeproj/project.pbxproj
  - SiriusMac/Accessibility/AccessibilityAnnouncer.swift
  - SiriusMac/App/ListeningSessionController.swift
  - SiriusMac/Authentication/AuthenticationView.swift
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
  - SiriusMacTests/MetadataPresentationTests.swift
  - SiriusMacTests/PlaybackQueueTests.swift
  - SiriusMacTests/SystemMediaControllerTests.swift
findings:
  critical: 0
  warning: 1
  info: 0
  total: 1
status: issues_found
---

# Phase 03: Code Review Report

**Reviewed:** 2026-08-21T20:12:53Z
**Depth:** standard
**Files Reviewed:** 22
**Status:** issues_found

## Summary

This final post-cap standard review re-read all declared source and test files, traced the controller, compact player, Player menu, and MediaPlayer command paths, and verified the shared `ListeningCommandAvailability` projection for initial, pending, playing, paused, stopped, unavailable, and queue-direction states.

The earlier findings remain resolved: persistent-library initialization falls back to in-memory storage, failed metadata is immediately stale, the compact player does not retain inert transport after pending/failed/stopped transitions, and `PlaybackQueueTests.swift` is compiled by the Xcode test target. The final change correctly disables invalid Library and Player-menu commands. One equivalent availability bug remains in the system media controls during a replacement tune.

`xcodebuild test -quiet -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -derivedDataPath /private/tmp/sirius-mac-final-rereview-derived` passed. `git diff --check` was clean.

## Narrative Findings (AI reviewer)

## Warnings

### WR-01 [WARNING]: System media commands stay enabled while a replacement tune is pending

**File:** `/Users/gabe/sirius-mac/SiriusMac/App/ListeningSessionController.swift:405-413`, `/Users/gabe/sirius-mac/SiriusMac/App/ListeningSessionController.swift:478-497`

**Issue:** When a user changes channels after a confirmed stream exists, `PlaybackCoordinator.tune` transitions to `.awaitingLiveContract` while the old confirmed channel is still present. `publishConfirmedSystemMediaState()` deliberately returns at lines 406-413 to preserve previous Now Playing metadata, but it also leaves the previous play/pause, Previous, and Next enabled state untouched. Those commands are no longer valid under `ListeningCommandAvailability`: Play/Pause returns `.commandFailed`, while Previous/Next can start another tune and supersede the in-flight request. The Library and Player menu now disable those commands, so media keys and Control Center are the remaining inconsistent entry point.

**Fix:** Set system media availability from the shared projection on every observed state, including the pending branch, and make the handlers enforce the same projection as a race-safe backstop. For example:

```swift
private func setSystemCommandAvailability(using media: SystemMediaController) {
    let availability = commandAvailability
    media.setSupportedCommandAvailability(
        playPause: availability.playPause,
        previous: availability.previous,
        next: availability.next
    )
}

private func handleSystemNext() -> SystemRemoteCommandStatus {
    guard commandAvailability.next else { return .commandFailed }
    return next() == nil ? .commandFailed : .success
}
```

Call the helper before the `.awaitingLiveContract` early return and replace the queue-only guards in both navigation handlers. Add a controller test that reaches a pending replacement tune after confirmed playback and asserts all three remote commands are disabled and cannot invoke a second tune.

---

_Reviewed: 2026-08-21T20:12:53Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
