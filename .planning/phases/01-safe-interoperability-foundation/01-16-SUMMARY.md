---
phase: 01-safe-interoperability-foundation
plan: "16"
subsystem: authentication
tags: [swift, keychain, webkit, native-authentication, entitlement, fail-closed, xctest]
requires:
  - phase: 01-13
    provides: Versioned fail-closed native profile and subscription transaction semantics
  - phase: 01-15
    provides: Secure exact-token cleanup and nonpersistent WebKit session retirement
provides:
  - Bounded, semantic Keychain loading for one explicit app-owned sign-in attempt
  - A single opaque restore-or-WebView credential source using the unchanged native transaction
  - Deterministic restore, revocation, retry, composition, and sign-out cleanup regressions
affects: [authentication, keychain-security, session-lifecycle, phase-2]
actuals:
  tokens: 9465
  tasks: 2
  commits: 4
tech-stack:
  added: []
  patterns:
    - Keep persisted credential bytes inside the Keychain adapter and emit only opaque credentials or semantic outcomes.
    - Stage restored material once after an explicit action, then revoke it before any non-entitled terminal presentation.
    - Compose the Keychain adapter, WebView bridge, combined source, and client as one app-owned graph.
key-files:
  created:
    - SiriusMac/Authentication/RestorableAuthenticationCredentialSource.swift
  modified:
    - SiriusMac.xcodeproj/project.pbxproj
    - SiriusMac/Security/KeychainCredentialStore.swift
    - SiriusMac/Authentication/AuthenticationPresentationModel.swift
    - SiriusMac/Authentication/AuthenticationView.swift
    - SiriusMacTests/KeychainCredentialStoreTests.swift
    - SiriusMacTests/SelectedAuthenticationCompositionTests.swift
key-decisions:
  - "A Keychain restore is a one-shot opaque CredentialSource input, never a second sign-in method or authorization claim."
  - "Only missing stored material reaches the existing user-operated WebView branch; unavailable, malformed, and erase-failed material remains terminal."
  - "All restored non-entitled outcomes erase the stored item before presentation; an erase failure is surfaced as an explicit cleanup failure."
patterns-established:
  - "Use an app-internal semantic loader rather than widening CredentialStore with a public secret read API."
  - "Keep restored and WebView credentials on one runtime-owned authentication then entitlement path."
requirements-completed: [AUTH-01, AUTH-02, AUTH-03, SECR-01, SECR-02, SECR-03, CLNT-04]
coverage:
  - id: D1
    description: Explicit bounded Keychain restore stages one opaque credential and reaches entitlement only through ordered native authentication and entitlement.
    requirement: AUTH-01
    verification:
      - kind: integration
        ref: SiriusMacTests/SelectedAuthenticationCompositionTests.swift#testFreshRestoreConsumesOneStoredCredentialBeforeOrderedNativeTransaction
        status: pass
    human_judgment: false
  - id: D2
    description: Missing, unavailable, malformed, and rejected stored material fails closed, is erased where possible, and never falls through in the same attempt.
    requirement: AUTH-02
    verification:
      - kind: unit
        ref: SiriusMacTests/KeychainCredentialStoreTests.swift#testAuthenticationLoaderErasesEmptyOversizedAndNonUTF8Material
        status: pass
      - kind: integration
        ref: SiriusMacTests/SelectedAuthenticationCompositionTests.swift#testRejectedRestoreErasesBeforeTerminalStateThenLaterExplicitRetryUsesWebView
        status: pass
    human_judgment: false
  - id: D3
    description: Explicit sign-out after restored success clears Keychain material and exact WebView residue through the existing client cleanup pipeline.
    requirement: AUTH-03
    verification:
      - kind: integration
        ref: SiriusMacTests/SelectedAuthenticationCompositionTests.swift#testRestoredSuccessSignOutClearsKeychainAndBridgeResidueThroughClientPipeline
        status: pass
    human_judgment: false
duration: 10 min
completed: 2026-08-18
status: complete
---

# Phase 01 Plan 16: Keychain Restore and Native Revalidation Summary

**An explicit Sign In now stages one bounded Keychain credential or the existing WebView handoff, and every credential is revalidated through the same native authentication-and-entitlement transaction.**

## Performance

- **Duration:** 10 min
- **Started:** 2026-08-18T18:00:15Z
- **Completed:** 2026-08-18T18:10:34Z
- **Tasks:** 2/2
- **Files modified:** 7

## Accomplishments

- Added a semantic Keychain loader that accepts only non-empty, whitespace-free UTF-8 material up to 8192 bytes and never exposes raw bytes through an app or package API.
- Added a single app-owned restore/WebView `CredentialSource`; restore uses the unchanged client-owned native authentication, entitlement, active-session, and post-entitlement-save sequence.
- Made malformed and non-entitled restored material erase before terminal presentation, with no automatic retry or same-attempt WebView fallback.
- Centralized production composition and covered fresh restore, missing fallback, invalid data, rejection, later explicit WebView retry, and restored-session sign-out cleanup.

## Task Commits

1. **Task 1: Restore one bounded credential through the same native transaction**
   - `b27e34c` — RED restore and erasure regressions
   - `7d76915` — bounded loader, combined source, native transaction mapping, and source membership
2. **Task 2: Compose the single source in the app and lock restart/sign-out acceptance**
   - `f36b2d5` — RED lifecycle, composition, malformed-data, and cleanup regressions
   - `c6b80e2` — production composition and corrected project group membership

## Files Created/Modified

- `SiriusMac/Security/KeychainCredentialStore.swift` — semantic bounded loader and fail-closed invalid-data deletion.
- `SiriusMac/Authentication/RestorableAuthenticationCredentialSource.swift` — explicit one-attempt restore-or-WebView credential source.
- `SiriusMac/Authentication/AuthenticationPresentationModel.swift` — shared native transaction presentation mapping with restored-result revocation.
- `SiriusMac/Authentication/AuthenticationView.swift` — one production Keychain/bridge/source/client composition graph.
- `SiriusMac.xcodeproj/project.pbxproj` — sole app-target membership for the combined source, with signing settings unchanged.
- `SiriusMacTests/KeychainCredentialStoreTests.swift` and `SiriusMacTests/SelectedAuthenticationCompositionTests.swift` — deterministic restore, fallback, erase, retry, and cleanup coverage.

## Verification

- Focused `KeychainCredentialStoreTests` and `SelectedAuthenticationCompositionTests` — passed.
- `plutil -lint SiriusMac.xcodeproj/project.pbxproj` — passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' test` — passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SiriusXMClient` — passed (29 tests, 6 suites).
- Static checks confirmed one source membership, no signing-setting changes, no background authentication work, and no production use of the raw Keychain test helper.

## Decisions Made

- Restored data carries no authority: it is supplied once through the same opaque `CredentialSource` boundary that already drives the native verification transaction.
- A failed restore never silently changes methods. Only a later explicit retry may observe a missing Keychain item and begin the established WebView path.
- Source construction moved into a small app-owned composition type so the live graph and deterministic test graph stay aligned.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected the new Xcode group reference to the source file identity.**
- **Found during:** Task 2
- **Issue:** The initial source membership compiled, but the Authentication group pointed at a mismatched file-reference identifier.
- **Fix:** Repointed the group child to the registered source file reference; build membership and all signing settings stayed unchanged.
- **Files modified:** `SiriusMac.xcodeproj/project.pbxproj`
- **Verification:** `plutil -lint`, focused XCTest, full app suite, and static one-membership scan passed.
- **Committed in:** `c6b80e2`

---

**Total deviations:** 1 auto-fixed (1 Rule 1 bug)
**Impact on plan:** The correction restored valid project navigation/membership without changing application behavior or release configuration.

## Issues Encountered

None.

## Known Stubs

None.

## Next Phase Readiness

Phase 1 now restores only previously approved Keychain material through fresh native revalidation, while preserving strict one-method and complete local cleanup behavior. The authorization foundation is ready for Phase 2's entitled catalog and playback work.

## Self-Check: PASSED

- All seven planned production and test artifacts exist.
- RED commits `b27e34c`, `f36b2d5` and GREEN commits `7d76915`, `c6b80e2` exist in git history.
- Focused, full app, full package, project-lint, and static boundary checks pass.
