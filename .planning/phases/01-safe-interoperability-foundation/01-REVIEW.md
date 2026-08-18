---
phase: 01-safe-interoperability-foundation
reviewed: 2026-08-18T14:57:49Z
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
  critical: 2
  warning: 3
  info: 1
  total: 6
status: issues_found
---

# Phase 1: Code Review Report

**Reviewed:** 2026-08-18T14:57:49Z
**Depth:** standard
**Files Reviewed:** 31
**Status:** issues_found

## Summary

The review covered the client transaction, raw-response classification, WebKit-to-native token handoff, session cleanup, Keychain persistence, release configuration, and their tests. Existing tests pass (`swift test --package-path Packages/SiriusXMClient` and the Xcode `SiriusMac` test scheme), but they use synthetic success payloads and do not exercise the production release or restore paths. The submitted code cannot produce a signed release and is wired to reject ordinary multi-field profile/entitlement responses before a session can become active.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: Release builds are explicitly prevented from being signed

**File:** `/Users/gabe/sirius-mac/SiriusMac.xcodeproj/project.pbxproj:76-79`

**Issue:** Both project-level Debug and Release configurations set `CODE_SIGNING_ALLOWED = NO`; the app target does not override it. Confirmed with `xcodebuild -configuration Release -showBuildSettings`, which reports `CODE_SIGNING_ALLOWED = NO` and `CODE_SIGN_IDENTITY = -`. A Release archive produced from this project therefore cannot satisfy the project's mandatory signed/notarized binary requirement and will be rejected by Gatekeeper distribution workflows.

**Fix:** Remove the project-wide `CODE_SIGNING_ALLOWED = NO` setting (or restrict it to an explicitly test-only local configuration), set the app target's Developer ID signing identity/team for Release archives, and add a release CI check that verifies the archive is signed before notarization.

```xcconfig
// SiriusMac Release.xcconfig
CODE_SIGNING_ALLOWED = YES
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = Developer ID Application
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

### CR-02: Raw provider responses are only accepted when they contain exactly one synthetic key

**File:** `/Users/gabe/sirius-mac/Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/AuthenticationFlowAdapter.swift:87-104,115-142`

**Issue:** The production transport forwards raw bodies directly to this adapter, but `exactJSONObject` rejects every object whose `dictionary.count` is not exactly one. Success is then recognized only for the test-shaped bodies `{"authenticated": true}` and `{"entitled": true}`. A normal profile or subscription response necessarily contains additional fields/envelopes, so it is classified as `.unsupported` even when the relevant success indicator is present. The only successful fixtures in the tests deliberately contain one field (for example `AuthenticationOutcomeTests.swift:9` and `:16`), masking the production failure. The client therefore cannot establish a session against a schema that adds even one benign field.

**Fix:** Define a versioned, recorded-and-redacted response adapter for each endpoint. Decode the documented/observed envelope, validate the required success evidence and prohibited control signals, and tolerate unrelated fields rather than using object cardinality as an authenticity check. Add fixtures with representative multi-field success responses and unknown extra fields.

```swift
private static func authenticatedProfile(from data: Data) -> Bool? {
    guard let profile = try? JSONDecoder().decode(ProfileResponse.self, from: data) else {
        return nil
    }
    return profile.profileID == nil ? false : true
}
// Keep challenge/redirect/status preflight checks; make the endpoint schema explicit.
```

## Warnings

### WR-01: Saved credentials are write-only and cannot restore a session after relaunch

**File:** `/Users/gabe/sirius-mac/SiriusMac/Authentication/AuthenticationView.swift:9-14`

**Issue:** The sole production `CredentialSource` is `WebAuthenticationBridge`, whose `credential()` only consumes the in-memory `VolatileWebCredentialHandoff` (`WebAuthenticationBridge.swift:146-150,193-203`). `KeychainCredentialStore.readStoredCredential()` is never called outside tests, while `SessionCoordinator` saves the credential after success (`SessionCoordinator.swift:133-138`). Consequently, a token saved to Keychain is never available to a newly created app/client after relaunch; the user must repeat WebView authentication despite the persisted credential store.

**Fix:** Supply a single app-owned credential source that first performs an explicit, authorized Keychain restore (and validates it through the same native auth/entitlement transaction), then falls back to the one-time WebView handoff. Erase the item on terminal invalid/unsupported results and add a launch/recreation test proving that a saved credential is consumed once and verified natively.

### WR-02: Sign-out leaves the rest of the authenticated WebKit session intact

**File:** `/Users/gabe/sirius-mac/SiriusMac/Authentication/WebAuthenticationBridge.swift:153-176`

**Issue:** The residue cleaner deletes only cookies named `AUTH_TOKEN` with path `/`. The same nonpersistent `WKWebsiteDataStore` remains alive for the bridge/web view and retains every other SiriusXM/identity-provider session cookie and website-data record. After a reported `.signedOut`, a new user-operated sign-in can therefore load an already-authenticated provider session, which is surprising on a shared Mac and contradicts the cleaner's stated browser-residue responsibility. The tests only populate `AUTH_TOKEN`, so they cannot detect retained session state.

**Fix:** On sign-out, remove all authentication-related records from this bridge's nonpersistent website data store (or create a fresh configuration/WebView), then rescan the token-cookie store before reporting success. Keep the predicate-based token deletion as a defense-in-depth check and add a test with a second first-party session cookie/data record.

### WR-03: Cookie selection accepts insecure tokens from any SiriusXM subdomain

**File:** `/Users/gabe/sirius-mac/SiriusMac/Authentication/FirstPartyTokenCookiePolicy.swift:23-35`

**Issue:** The extraction predicate checks name, path, expiry, and a broad `*.siriusxm.com` suffix, but does not require `cookie.isSecure` and accepts tokens set by any current or future subdomain. A non-secure cookie, or one placed by an unrelated/misconfigured subdomain, can be selected and forwarded as a bearer value to `api.edge-gateway.siriusxm.com`. This broadens the token-injection/session-fixation surface unnecessarily; the tests mark their cookies secure but never assert that insecure cookies are rejected.

**Fix:** Require `cookie.isSecure`, and replace the suffix match with a narrowly reviewed allowlist of the exact authentication hosts that are expected to issue `AUTH_TOKEN`. Add negative cases for a non-secure token and an unapproved `*.siriusxm.com` host.

```swift
guard cookie.isSecure,
      ["siriusxm.com", "player.siriusxm.com"].contains(normalizedDomain)
else { return false }
```

## Info

### IN-01: Redirect test counter is permanently zero and provides no redirect-behavior evidence

**File:** `/Users/gabe/sirius-mac/Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/EphemeralURLSessionTransport.swift:54-60,77-96`

**Issue:** `RequestState.redirects` is never incremented. `followUpRequestCount` consequently always returns zero, so `EphemeralSessionTests.swift:37-44` passes whether the redirect delegate is reached, ignored, or repeatedly invoked. The production delegate does cancel redirects, but this test-only observable cannot verify that fact.

**Fix:** Replace the counter with an observable redirect-delegate invocation count that increments under the same lock before `completionHandler(nil)`, and test both invocation and the nil follow-up decision using a controllable URL protocol or delegate seam.

---

_Reviewed: 2026-08-18T14:57:49Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
