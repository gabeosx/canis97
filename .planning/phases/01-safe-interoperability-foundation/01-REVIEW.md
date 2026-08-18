---
phase: 01-safe-interoperability-foundation
reviewed: 2026-08-18T13:47:40Z
depth: standard
files_reviewed: 31
files_reviewed_list:
  - .gitignore
  - Packages/SiriusXMClient/Package.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Diagnostics/DiagnosticRedactor.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Diagnostics/SafeDiagnosticEvent.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/AuthenticationFlowAdapter.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/SiriusXMRequestContract.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Public/AuthenticationModels.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Public/SiriusXMClient.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionState.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/EphemeralURLSessionTransport.swift
  - Packages/SiriusXMClient/Tests/FixtureTests/RedactionTests.swift
  - Packages/SiriusXMClient/Tests/PublicAPITests/PublicConsumerTests.swift
  - Packages/SiriusXMClient/Tests/SiriusXMClientTests/AuthenticationOutcomeTests.swift
  - Packages/SiriusXMClient/Tests/SiriusXMClientTests/EphemeralSessionTests.swift
  - Packages/SiriusXMClient/Tests/SiriusXMClientTests/SessionCoordinatorTests.swift
  - Packages/SiriusXMClient/Tests/SiriusXMClientTests/SignOutTests.swift
  - Packages/SiriusXMClient/Tests/SiriusXMClientTests/WebTokenAuthenticationTests.swift
  - SiriusMac.xcodeproj/project.pbxproj
  - SiriusMac/Authentication/AuthenticationPresentationModel.swift
  - SiriusMac/Authentication/AuthenticationView.swift
  - SiriusMac/Authentication/FirstPartyTokenCookiePolicy.swift
  - SiriusMac/Authentication/UnsupportedAuthenticationView.swift
  - SiriusMac/Authentication/WebAuthenticationBridge.swift
  - SiriusMac/Authentication/WebAuthenticationView.swift
  - SiriusMac/Security/KeychainCredentialStore.swift
  - SiriusMac/SiriusMacApp.swift
  - SiriusMacTests/AuthenticationPresentationModelTests.swift
  - SiriusMacTests/KeychainCredentialStoreTests.swift
  - SiriusMacTests/SelectedAuthenticationCompositionTests.swift
  - SiriusMacTests/WebAuthenticationBridgeTests.swift
findings:
  critical: 1
  warning: 1
  info: 0
  total: 2
status: issues_found
---

# Phase 1: Code Review Report

**Reviewed:** 2026-08-18T13:47:40Z
**Depth:** standard
**Files Reviewed:** 31
**Status:** issues_found

## Summary

The review covered the Phase 1 client, native WebView composition, local cleanup lifecycle, deterministic tests, and the consolidated Xcode test graph, with Plans 01-09 through 01-11 as context. The fresh-state cleanup and graph consolidation are structurally sound, but the bridge's new-attempt latch is not atomic across an asynchronous cookie read, so concurrent explicit selections can create multiple credential transfers in one attempt. The unsupported-result view also presents a Retry control that the presentation model rejects.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: Concurrent selections can transfer multiple credentials in one attempt

**File:** `/Users/gabe/sirius-mac/SiriusMac/Authentication/WebAuthenticationBridge.swift:84-117`

**Issue:** `useLoggedInSession()` checks `didTransferCredential` at line 84, then suspends at line 87 to obtain cookies. A second main-actor task can enter during that suspension, observe the same `false` latch, and progress to lines 115-117 as well. Both calls can invoke `credentialConsumer`, and the second handoff can overwrite the first before the client consumes it. This violates Plan 01-09's per-attempt single-consumption contract and can associate an authentication transaction with the wrong selected credential. The tests exercise only sequential calls, so they do not cover the flagged concurrent-selection assumption.

**Fix:** Introduce an explicit in-progress/consumed handoff state and reserve it before the first suspension. On non-transfer outcomes, reset only the in-progress reservation; retain the consumed state after a successful handoff. Add a controlled-suspension cookie-store test that starts two selections concurrently and proves exactly one consumer invocation.

```swift
private enum HandoffState { case available, selecting, consumed }
private var handoffState: HandoffState = .available

func useLoggedInSession() async -> Result {
    guard handoffState == .available else { return .alreadyConsumed }
    handoffState = .selecting
    defer {
        if handoffState == .selecting { handoffState = .available }
    }

    let cookies = await cookieStore.allCookies()
    // Validate exactly one cookie and its payload...
    handoffState = .consumed
    await credentialConsumer(credential)
    return .credentialTransferred
}
```

## Warnings

### WR-01: Unsupported screen offers a retry action that always does nothing

**File:** `/Users/gabe/sirius-mac/SiriusMac/Authentication/AuthenticationView.swift:25-31`

**Issue:** The unsupported-state branch renders `Retry Sign In`, but `AuthenticationPresentationModel.retry()` only accepts states in `isRetryableTerminalState`; `.unsupported` is explicitly excluded at `/Users/gabe/sirius-mac/SiriusMac/Authentication/AuthenticationPresentationModel.swift:81-95`. Pressing the visible control therefore returns `nil` and leaves the UI unchanged.

**Fix:** Either remove the retry button from the unsupported branch, which matches an intentionally terminal fail-closed result, or explicitly include `.unsupported` in the retryable states and add a test proving a new user-operated WebView attempt is started. Do not create an automatic retry path.

---

_Reviewed: 2026-08-18T13:47:40Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
