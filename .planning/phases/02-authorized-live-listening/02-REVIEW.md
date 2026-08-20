---
phase: 02-authorized-live-listening
reviewed: 2026-08-20T21:36:07Z
depth: standard
files_reviewed: 35
files_reviewed_list:
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Diagnostics/SafeDiagnosticEvent.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/AuthenticationFlowAdapter.swift
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
  - SiriusMac/Authentication/AuthenticationPresentationModel.swift
  - SiriusMac/Authentication/AuthenticationView.swift
  - SiriusMac/Authentication/ClosedAuthenticationOracle.swift
  - SiriusMac/Authentication/RestorableAuthenticationCredentialSource.swift
  - SiriusMac/Authentication/WebAuthenticationBridge.swift
  - SiriusMac/Authentication/WebCredentialSelectionPolicy.swift
  - SiriusMac/Catalog/ListeningPresentationModel.swift
  - SiriusMac/Catalog/ListeningView.swift
  - SiriusMac/Listening/PlaybackCoordinator.swift
  - SiriusMac/Metadata/MetadataPresentationModel.swift
  - SiriusMacTests/AuthenticationPresentationModelTests.swift
  - SiriusMacTests/ListeningCompositionTests.swift
  - SiriusMacTests/MetadataPresentationTests.swift
  - SiriusMacTests/PlaybackInstallationOrderTests.swift
  - SiriusMacTests/SelectedAuthenticationCompositionTests.swift
  - SiriusMacTests/WebAuthenticationBridgeTests.swift
  - script/build_and_run.sh
  - script/lib/resolve_process_binary.sh
  - script/lib/single_instance_launcher.sh
  - script/test_offline_auth_matrix.sh
  - script/tests/OfflineAuthenticationMatrixTests.swift
  - script/tests/build_and_run_tests.sh
findings:
  critical: 2
  warning: 1
  info: 0
  total: 3
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-08-20T21:36:07Z
**Depth:** standard
**Files Reviewed:** 35
**Status:** issues_found

## Summary

The Phase 02 source set contains two release-blocking lifecycle defects: a failed or build-only invocation can remove another launcher's lock, and recovery can restart audio after the user deliberately paused it. A catalog race can also retain and later surface a prior session's lineup after an account switch.

## Critical Issues

### CR-01: Cleanup removes a lock owned by another launcher

**File:** `/Users/gabe/sirius-mac/script/build_and_run.sh:30-35,42-46,144-151`

**Issue:** The EXIT trap always calls `rmdir "$LAUNCH_LOCK_PATH"`, even when this invocation never acquired the lock. A second `run` invocation that fails `mkdir` at line 43 removes the first invocation's lock while that first build/launch is still in progress. `--build-only` also installs the same trap without acquiring a lock, so it can remove a concurrent launch's lock. A third invocation can then enter the launch path concurrently, defeating the single-instance protection and allowing the duplicate SiriusMac processes this phase is meant to prevent.

**Fix:** Track lock ownership and release only a lock acquired by this process. Keep build-only outside the lock cleanup path.

```bash
LAUNCH_LOCK_HELD=0

cleanup_launcher() {
  cleanup_telemetry
  if (( LAUNCH_LOCK_HELD )); then
    rmdir "$LAUNCH_LOCK_PATH" 2>/dev/null || true
    LAUNCH_LOCK_HELD=0
  fi
}

acquire_launch_lock() {
  if mkdir "$LAUNCH_LOCK_PATH" 2>/dev/null; then
    LAUNCH_LOCK_HELD=1
    return 0
  fi
  report_process_stage lock-acquisition-failed
  return 1
}
```

Add a regression case that holds the first invocation's lock, runs a second failing invocation (and `--build-only`), and asserts the first lock directory still exists.

### CR-02: Reconnect and wake can autoplay a deliberately paused stream

**File:** `/Users/gabe/sirius-mac/SiriusMac/Listening/PlaybackCoordinator.swift:612-630,891-908`

**Issue:** `networkBecameUnavailable` sets `recoveryPendingAfterReconnect` whenever a channel remains selected, including while `state == .paused`. On reconnect, `networkBecameAvailable` re-resolves and plays that channel. Independently, `didWake` starts recovery for every selected channel even when no recovery was pending. Because pausing retains `selectedChannelID`, a paused stream restarts and begins audio after a network transition or Mac wake without a Resume command.

**Fix:** Track whether playback was active/recoverable before the interruption, and gate automatic recovery on that state instead of selection alone. Do not schedule recovery from `.paused`, `.idle`, or `.stopped`.

```swift
private var shouldResumeAfterInterruption = false

case .networkBecameUnavailable, .willSleep:
    shouldResumeAfterInterruption = isActivelyPlayingOrRecovering
    cancelRecovery()

case .networkBecameAvailable, .didWake:
    guard shouldResumeAfterInterruption else { return }
    shouldResumeAfterInterruption = false
    _ = beginRecoveryIfEligible(stallGrace: false)
```

Add deterministic tests that pause a confirmed item, then emit unavailable/available and will-sleep/did-wake signals; assert no additional resolver call, install, or play request occurs.

## Warnings

### WR-01: An old catalog refresh can become the new account's stale snapshot

**File:** `/Users/gabe/sirius-mac/Packages/SiriusXMClient/Sources/SiriusXMClient/Public/SiriusXMClient.swift:139-170`

**Issue:** `catalog()` captures `expectedGeneration` but never compares it after awaiting `catalogRefresher.refresh()`. If Account A's refresh remains in flight, the user signs out and signs in as Account B, and Account A's request then succeeds, the post-await entitlement check passes for Account B and line 158 stores Account A's snapshot as `lastValidCatalogSnapshot`. A later failed refresh can show that prior-account lineup through the stale branch at lines 163-171. This is a cross-session authorization/presentation race; the existing sign-out test does not cover re-authentication before the old request completes.

**Fix:** Reject the completion unless the catalog generation is still current, before writing either fresh or stale state.

```swift
let refreshed = await catalogRefresher.refresh()
guard catalogRefreshGeneration == expectedGeneration,
      await sessionCoordinator.entitlementAvailability == .entitled
else { return .failed(.cancelled) }
```

Add a test that blocks Account A's catalog transport, signs out, completes Account B authentication, then releases Account A's response and verifies no old snapshot is cached or surfaced.

---

_Reviewed: 2026-08-20T21:36:07Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
