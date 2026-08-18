---
phase: 01-safe-interoperability-foundation
reviewed: 2026-08-18T12:03:40Z
depth: standard
files_reviewed: 35
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
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/DirectHostPolicy.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/EphemeralURLSessionTransport.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/SessionTransport.swift
  - Packages/SiriusXMClient/Tests/FixtureTests/RedactionTests.swift
  - Packages/SiriusXMClient/Tests/PublicAPITests/PublicConsumerTests.swift
  - Packages/SiriusXMClient/Tests/SiriusXMClientTests/AuthenticationOutcomeTests.swift
  - Packages/SiriusXMClient/Tests/SiriusXMClientTests/EphemeralSessionTests.swift
  - Packages/SiriusXMClient/Tests/SiriusXMClientTests/PlaceholderTests.swift
  - Packages/SiriusXMClient/Tests/SiriusXMClientTests/SessionCoordinatorTests.swift
  - Packages/SiriusXMClient/Tests/SiriusXMClientTests/SignOutTests.swift
  - Packages/SiriusXMClient/Tests/SiriusXMClientTests/WebTokenAuthenticationTests.swift
  - SiriusMac.xcodeproj/project.pbxproj
  - SiriusMac.xcodeproj/xcshareddata/xcschemes/SiriusMac.xcscheme
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
  critical: 2
  warning: 1
  info: 0
  total: 3
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-08-18T12:03:40Z
**Depth:** standard
**Files Reviewed:** 35
**Status:** issues_found

## Summary

The Phase 1 client and native app preserve several important fail-closed boundaries: the transport is ephemeral and host-constrained, response parsing is strict, and diagnostics avoid provider detail. However, the authentication composition has two lifecycle failures: a bridge cannot be reused after its first credential transfer, and a Keychain credential can become impossible to erase through the application after a restart. The focused macOS composition test target passed from a fresh derived-data directory during this review; its current build graph nevertheless contains duplicate, disconnected target records that should be consolidated.

## Critical Issues

### CR-01: Credential transfer is permanently consumed, so retry and re-login cannot work

**Classification:** BLOCKER

**File:** `SiriusMac/Authentication/WebAuthenticationBridge.swift:75`

**Issue:** `useLoggedInSession()` returns `.alreadyConsumed` forever after the first successful transfer because `didTransferCredential` is set at line 107 and is never reset. The UI intentionally exposes `Retry Sign In` after rejected, unsupported, cleanup-failed, and signed-out states (`AuthenticationView.swift:28,86`), but every subsequent attempt reaches the `.alreadyConsumed` branch, which the composed flow converts to `.unsupported`. A user who signs out or receives a terminal native-auth result therefore cannot sign in again without quitting and relaunching the app.

**Fix:** Establish an explicit new-login lifecycle that clears the transfer flag and any consumed handoff only when a new user-operated WebView sign-in begins (or replace the bridge/client pair for each new login). Keep duplicate consumption blocked during a single attempt, then add regression tests for terminal-result retry and sign-out followed by sign-in.

### CR-02: A persisted credential can be stranded after app restart

**Classification:** BLOCKER

**File:** `SiriusMac/Security/KeychainCredentialStore.swift:36`

**Issue:** A successful session persists a credential, but production code never reads `readStoredCredential()` (`KeychainCredentialStore.swift:46`) and the new app instance always composes its client with the empty WebView bridge as the sole credential source (`AuthenticationView.swift:9-14`). After restart, the presentation state is not entitled, so the only Sign Out control is absent (`AuthenticationView.swift:42-47`); even if the client sign-out API were called, `SessionCoordinator.signOut()` returns `.alreadySignedOut` before calling `erase()` when its fresh in-memory state is signed out (`SessionCoordinator.swift:141-144`). The saved credential can consequently remain in Keychain with no application path to reuse or remove it.

**Fix:** Choose one supported lifecycle and implement it end-to-end: either restore a valid Keychain credential through an app-owned `CredentialSource`, or do not persist it until restoration exists. In both cases, provide a user-reachable cleanup path that erases the Keychain item and WebView residue even when no in-memory session is active. Add an app-lifecycle test that signs in, creates a new composition, and verifies the credential is either restored or explicitly removed.

## Warnings

### WR-01: The Xcode project contains two disconnected SiriusMacTests target definitions

**Classification:** WARNING

**File:** `SiriusMac.xcodeproj/project.pbxproj:66-73`

**Issue:** The root project selects the `E1…` test target (line 72), while a second `A001…` target and a second PBXProject record describe the same test bundle but are not reachable from `rootObject` (lines 68 and 73). File references and source phases are duplicated for the same tests (lines 22-26 and 78-79). This leaves an inert build graph beside the active one, so a future edit can be made to the wrong target and silently have no effect on CI or local tests.

**Fix:** Retain one `SiriusMacTests` target, one source-build phase, and one file reference per test source; remove the unreachable PBXProject/target records and verify the shared scheme still targets the surviving test bundle.

---

_Reviewed: 2026-08-18T12:03:40Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
