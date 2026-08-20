---
phase: 02-authorized-live-listening
reviewed: 2026-08-20T00:00:00Z
depth: standard
files_reviewed: 19
files_reviewed_list:
  - Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/SiriusXMRequestContract.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Public/LiveListeningModels.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Public/SiriusXMClient.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift
  - Packages/SiriusXMClient/Tests/SiriusXMClientTests/LiveCatalogAdapterTests.swift
  - Packages/SiriusXMClient/Tests/SiriusXMClientTests/LivePlaybackCoordinatorTests.swift
  - Packages/SiriusXMClient/Tests/SiriusXMClientTests/MetadataRefreshCoordinatorTests.swift
  - Packages/SiriusXMClient/Tests/SiriusXMClientTests/SessionCoordinatorTests.swift
  - Packages/SiriusXMClient/Tests/SiriusXMClientTests/SignOutTests.swift
  - SiriusMac.xcodeproj/project.pbxproj
  - SiriusMac/Authentication/AuthenticationView.swift
  - SiriusMac/Catalog/ListeningPresentationModel.swift
  - SiriusMac/Catalog/ListeningView.swift
  - SiriusMac/Listening/PlaybackCoordinator.swift
  - SiriusMac/Metadata/MetadataPresentationModel.swift
  - SiriusMacTests/ListeningCompositionTests.swift
  - SiriusMacTests/MetadataPresentationTests.swift
  - SiriusMacTests/PlaybackInstallationOrderTests.swift
findings:
  critical: 2
  warning: 1
  info: 0
  total: 3
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-08-20T00:00:00Z
**Depth:** standard
**Files Reviewed:** 19
**Status:** issues_found

## Summary

Static review of the Phase 02 library, macOS playback integration, and focused tests found two lifecycle failures that can respectively erase a newly authenticated local session and leave playback permanently idle. The review did not launch SiriusMac, run Xcode, contact SiriusXM, or retry UAT.

## Critical Issues

### CR-01: Previous sign-out cleanup can erase a newly authenticated session

**File:** `/Users/gabe/sirius-mac/Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift:223`

**Issue:** `signOut()` clears actor state and then starts Keychain/residue cleanup in a detached task (lines 233-257). `attemptSession()` does not wait for that task. A user can therefore start a new sign-in while the previous cleanup is blocked; the new attempt saves its credential at line 135, and the older detached cleanup can subsequently call `credentialStore.erase()` and remove that new credential (and may clear the new WebView residue). This leaves an apparently active in-memory session without its persisted credential and makes the next launch unexpectedly signed out.

**Fix:** Serialize authentication attempts behind outstanding cleanup, or make cleanup generation-aware so it cannot remove material created by a newer session. For example, await the existing cleanup task before accepting a new attempt:

```swift
func attemptSession() async -> SessionAttemptOutcome {
    if let cleanupTask {
        _ = await cleanupTask.value
    }
    // acquire the attempt lease and continue with authentication
}
```

Add a regression test with a blocking `CredentialStore.erase()`: call `signOut()`, complete a fresh successful `attemptSession()` before releasing erase, then assert the new credential remains stored after the original cleanup finishes.

### CR-02: A player item that is already ready never receives a play request

**File:** `/Users/gabe/sirius-mac/SiriusMac/Listening/PlaybackCoordinator.swift:292`

**Issue:** `AVFoundationItemObservation` observes `AVPlayerItem.status` using only `.new`. If the item has already transitioned to `.readyToPlay` before the observer is installed, no status change occurs and `onReady()` is never called. The coordinator installs that item but never calls `requestPlay()`, leaving it indefinitely in `.idle`. This is a normal AVFoundation timing race for cached or rapidly prepared assets; the focused fake runtime only emits readiness after installation, so it cannot expose it.

**Fix:** Request the initial KVO value and explicitly stage an early-ready signal until installation has completed. Merely adding `.initial` is insufficient here: its callback can run during `runtime.observe`, before the coordinator records the observation identity and installs the item. Record the observation identity before subscribing, make `onReady` set a `readyPendingInstall` flag when the item is not yet installed, then consume that flag immediately after `runtime.install(item)`:

```swift
itemStatusObservation = item.observe(\\.status, options: [.initial, .new]) { [weak self] item, _ in
    Task { @MainActor in self?.handleItemStatus(item.status) }
}
// After runtime.install(item): if readyPendingInstall { requestPlayForReadyItem(...) }
```

Add a runtime test that invokes the ready callback during observation setup (before installation) and asserts the coordinator requests play exactly once after, never before, the item is installed.

## Warnings

### WR-01: The Xcode test group points to a nonexistent file-reference object

**File:** `/Users/gabe/sirius-mac/SiriusMac.xcodeproj/project.pbxproj:69`

**Issue:** The `SiriusMacTests` group references `020700020000000000001` for `MetadataPresentationTests.swift`, but the declared `PBXFileReference` and the test build file both use `020700020000000000000001` (line 53). The group has a dangling object ID, so the test appears as a broken/missing entry in Xcode even though the build phase happens to use the correct ID.

**Fix:** Replace the group child ID with the declared 24-character file-reference ID:

```text
020700020000000000000001 /* MetadataPresentationTests.swift */,
```

---

_Reviewed: 2026-08-20T00:00:00Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
