---
phase: 01-safe-interoperability-foundation
plan: "06"
subsystem: native-web-authentication-bridge
tags: [swift, webkit, wkwebview, cookie-policy, authentication, security, xctest]
requires:
  - phase: 01-04
    provides: AuthenticationResidueCleaner seam and memory-first sign-out semantics.
  - phase: 01-05
    provides: Native authentication surface and semantic presentation states.
provides:
  - Nonpersistent, user-operated WKWebView authentication bridge
  - Exact shared first-party AUTH_TOKEN extraction and cleanup policy
  - Deterministic extraction, cleanup, and unconditional-build regressions
affects: [01-07, phase-2]
actuals:
  tokens: 8455
  tasks: 2
  commits: 4
tech-stack:
  added: []
  patterns: [nonpersistent WebKit data store, exact cookie predicate, opaque volatile credential handoff, post-delete residue rescan]
key-files:
  created:
    - SiriusMac/Authentication/FirstPartyTokenCookiePolicy.swift
    - SiriusMac/Authentication/WebAuthenticationBridge.swift
    - SiriusMac/Authentication/WebAuthenticationView.swift
    - SiriusMacTests/WebAuthenticationBridgeTests.swift
  modified:
    - SiriusMac/Authentication/AuthenticationView.swift
    - SiriusMac.xcodeproj/project.pbxproj
key-decisions:
  - "Use WKWebsiteDataStore.nonPersistent() and a WebView-owned WKHTTPCookieStore; no Safari or shared-cookie state is consulted."
  - "Use one root-path, expiry-aware, boundary-correct SiriusXM cookie predicate for extraction and residue cleanup."
  - "Decode only session.accessToken into an opaque AuthenticationCredential and make the handoff single-consumption."
patterns-established:
  - "WebKit behavior is tested through an injected cookie-store seam, while the live adapter remains restricted to the app-owned nonpersistent store."
  - "Browser cleanup is successful only after deleting every policy match and observing zero matches in a post-delete rescan."
requirements-completed: [AUTH-01, AUTH-02, AUTH-03, SECR-02, SECR-03, CLNT-04]
coverage:
  - id: D1
    description: Explicit native WebView consent selects only one current first-party token and emits one opaque volatile credential.
    requirement: AUTH-01
    verification:
      - kind: unit
        ref: "SiriusMacTests/WebAuthenticationBridgeTests.swift#testExplicitConsentAcceptsOneCurrentApexOrBoundaryCorrectSubdomainToken"
        status: pass
    human_judgment: false
  - id: D2
    description: Sign-out deletes matching apex and subdomain tokens with a post-delete rescan, and bridge tests remain unconditionally compiled.
    requirement: AUTH-03
    verification:
      - kind: unit
        ref: "SiriusMacTests/WebAuthenticationBridgeTests.swift#testSignOutDeletesEveryExactApexAndSubdomainMatchThenRescans"
        status: pass
      - kind: unit
        ref: "SiriusMacTests/WebAuthenticationBridgeTests.swift#testBridgeAndTestsAreUnconditionallyIncludedWithoutPlanningArtifactChecks"
        status: pass
    human_judgment: false
duration: 15min
completed: 2026-08-18
status: complete
---

# Phase 01 Plan 06: Nonpersistent WebView Token Bridge Summary

**A user-operated, nonpersistent WKWebView now transfers exactly one validated first-party token as an opaque volatile credential and removes the same token set on sign-out.**

## Performance

- **Duration:** 15 min
- **Started:** 2026-08-18T04:20:00Z
- **Completed:** 2026-08-18T04:35:54Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Added one strict `FirstPartyTokenCookiePolicy` for current root-path `AUTH_TOKEN` cookies on `siriusxm.com` and real subdomains, rejecting expired, lookalike, and unsupported-path candidates.
- Added the app-owned `WebAuthenticationBridge`, built on `WKWebsiteDataStore.nonPersistent()`, with explicit-consent-only cookie access, bounded minimal payload decoding, and a single opaque handoff.
- Replaced the placeholder browser container with a native `NSViewRepresentable` host and added deterministic cookie-store tests for extraction, ambiguity, malformed data, cleanup parity, delete errors, and build membership.
- Implemented `AuthenticationResidueCleaner` with exact-match deletion and a mandatory post-delete rescan.

## Task Commits

1. **Task 1: Extract exactly one current first-party token after explicit consent** - `d82ae7e` (RED), `4cb78c9` (GREEN)
2. **Task 2: Apply the same token predicate to sign-out and keep tests unconditional** - `cea4a4b` (RED), `8ba3aa6` (GREEN)

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/WebAuthenticationBridgeTests test` — passed (7 tests).
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' test` — passed (7 tests).
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SiriusXMClient` — passed (23 tests).
- `! rg -n '\\.planning|canImport\\(AuthFeasibilityHarness\\)' SiriusMac.xcodeproj Packages/SiriusXMClient/Package.swift SiriusMacTests/WebAuthenticationBridgeTests.swift` — passed.

## Decisions Made

- The WebView owns a fresh in-memory website data store; the bridge never creates or accesses Safari, shared cookie, JavaScript, or developer-tool paths.
- Only the exact policy may select or remove cookies, so a remaining accepted subdomain token can never be mistaken for successful cleanup.
- The bridge exposes only an opaque `CredentialSource` seam to the forthcoming client composition; raw cookie and decoded payload material stay internal and transient.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected Xcode source file references to their actual repository paths.**
- **Found during:** Task 1
- **Issue:** The existing project references resolved grouped app and test Swift files from the repository root, preventing a clean WebView bridge build.
- **Fix:** Registered all app/test source references against `SOURCE_ROOT` and added the planned bridge files to the correct target build phases.
- **Files modified:** `SiriusMac.xcodeproj/project.pbxproj`
- **Verification:** Focused and full Xcode test targets compile and pass.
- **Committed in:** `4cb78c9`

**2. [Rule 2 - Missing Critical] Exposed the bridge's handoff solely as an opaque CredentialSource seam.**
- **Found during:** Task 2
- **Issue:** The default bridge handoff needed an app-facing client seam without exposing raw token material.
- **Fix:** Retained the single-consumption handoff internally and exposed only an optional `CredentialSource` protocol view for Plan 01-07 composition.
- **Files modified:** `SiriusMac/Authentication/WebAuthenticationBridge.swift`
- **Verification:** Focused bridge tests pass and no raw credential accessor exists.
- **Committed in:** `8ba3aa6`

**Total deviations:** 2 auto-fixed (1 Rule 1 build defect, 1 Rule 2 security integration fix).

## Known Stubs

None.

## Next Phase Readiness

- Plan 01-07 can compose the opaque bridge credential source with the client-owned native authentication and entitlement transaction.
- The bridge already conforms to the existing residue-cleaner seam for memory-first sign-out composition.

## Self-Check: PASSED

- All four bridge/policy/view/test artifacts exist in their Xcode targets.
- All four RED/GREEN task commits exist in git history.
- Focused bridge tests, the full app test target, and the complete client package suite pass.
