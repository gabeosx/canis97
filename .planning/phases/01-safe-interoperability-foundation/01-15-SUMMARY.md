---
phase: 01-safe-interoperability-foundation
plan: "15"
subsystem: authentication
tags: [swift, webkit, cookies, session-retirement, fail-closed, appkit]
requires:
  - phase: 01-12
    provides: Main-actor WebKit credential bridge with shared extraction and cleanup predicate
provides:
  - Secure exact-domain AUTH_TOKEN selection shared by extraction and cleanup
  - Complete retirement of the bridge-owned nonpersistent WebKit website session
  - Stable native host replacement for a rotated WKWebView
affects: [authentication, session-security, sign-out, native-webview]
actuals:
  tokens: 4489
  tasks: 2
  commits: 4
tech-stack:
  added: []
  patterns:
    - Keep first-party token issuer authorization in one normalized exact-domain policy used by extraction, deletion, and rescan.
    - Delete and rescan named token evidence before bulk-retiring only the bridge-owned nonpersistent WebKit store.
    - Use a stable AppKit container to replace a rotated WebView without exposing browser data.
key-files:
  created: []
  modified:
    - SiriusMac/Authentication/FirstPartyTokenCookiePolicy.swift
    - SiriusMac/Authentication/WebAuthenticationBridge.swift
    - SiriusMac/Authentication/WebAuthenticationView.swift
    - SiriusMacTests/WebAuthenticationBridgeTests.swift
key-decisions:
  - "Only Secure, current, root-path AUTH_TOKEN cookies from normalized siriusxm.com or exact www.siriusxm.com are accepted."
  - "Cleanup reports success only when exact-token rescan is clean and bridge-owned nonpersistent session retirement succeeds."
  - "The WebKit session remover bulk-deletes its own store without enumerating, exporting, logging, or persisting unrelated website records."
patterns-established:
  - "Pair precise security evidence with an opaque full-session retirement result; never use unrelated browser records as observable test output."
requirements-completed: [AUTH-01, AUTH-02, AUTH-03, SECR-02, SECR-03, CLNT-04]
coverage:
  - id: D1
    description: Secure, exact apex/www token selection rejects insecure, expired, lookalike, unsupported-path, and unapproved-subdomain cookies in both bridge paths.
    requirement: AUTH-01
    verification:
      - kind: unit
        ref: SiriusMacTests/WebAuthenticationBridgeTests.swift#testMissingMultipleExpiredLookalikeAndUnsupportedCookiesFailClosed
        status: pass
      - kind: unit
        ref: SiriusMacTests/WebAuthenticationBridgeTests.swift#testUnapprovedSubdomainIsNeitherTransferredNorAnExactCleanupMatch
        status: pass
    human_judgment: false
  - id: D2
    description: Sign-out requires successful exact delete/rescan evidence and nonpersistent website-session retirement, while every partial failure remains explicit.
    requirement: AUTH-03
    verification:
      - kind: unit
        ref: SiriusMacTests/WebAuthenticationBridgeTests.swift#testSignOutRescansExactTokensThenRetiresTheOwnedWebsiteSession
        status: pass
      - kind: unit
        ref: SiriusMacTests/WebAuthenticationBridgeTests.swift#testSignOutReportsEveryPartialFailureButStillAttemptsWebsiteSessionRetirement
        status: pass
    human_judgment: false
  - id: D3
    description: A fresh nonpersistent configuration and WebView replace the retired browser child without exposing unrelated browser state.
    requirement: SECR-02
    verification:
      - kind: integration
        ref: SiriusMacTests/WebAuthenticationBridgeTests.swift#testStableWebViewHostReplacesTheRetiredChild
        status: pass
      - kind: automated_ui
        ref: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' test
        status: pass
    human_judgment: false
duration: 8 min
completed: 2026-08-18
status: complete
---

# Phase 01 Plan 15: WebKit Session Retirement Summary

**Secure exact issuer selection now gates volatile token use, while sign-out proves token removal and retires the complete bridge-owned nonpersistent WebKit session.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-08-18T17:47:00Z
- **Completed:** 2026-08-18T17:54:51Z
- **Tasks:** 2/2
- **Files modified:** 4

## Accomplishments

- Replaced suffix-based cookie acceptance with a Secure exact normalized allowlist for apex and `www` SiriusXM issuers.
- Preserved one predicate for credential selection, exact deletion candidates, and post-delete residue checks.
- Added bridge-owned nonpersistent website-session retirement, a new WebView/configuration generation, and native child replacement after cleanup.
- Proved delete/rescan/retirement ordering and all partial failure outcomes with synthetic-only browser residue tests.

## Task Commits

1. **Task 1: Restrict token selection and cleanup to Secure evidence-backed issuers**
   - `947f391` — RED exact-issuer cookie regressions
   - `c5d8e40` — Secure exact-domain policy implementation
2. **Task 2: Retire the complete nonpersistent website session after exact-token evidence**
   - `022932b` — RED session-retirement and host-replacement regressions
   - `57e69ec` — session rotation and stable AppKit host implementation

## Files Created/Modified

- `SiriusMac/Authentication/FirstPartyTokenCookiePolicy.swift` — applies Secure, current, root-path, exact normalized issuer checks.
- `SiriusMac/Authentication/WebAuthenticationBridge.swift` — aggregates deletion, exact rescan, opaque nonpersistent-store retirement, and fresh-session installation.
- `SiriusMac/Authentication/WebAuthenticationView.swift` — provides a stable AppKit container that replaces its one displayed WebView child.
- `SiriusMacTests/WebAuthenticationBridgeTests.swift` — covers issuer boundaries, cleanup evidence, retirement failure, generation, and host replacement.

## Verification

- Focused `WebAuthenticationBridgeTests` — passed (17 tests).
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' test` — passed (33 tests).
- `swift test` in `Packages/SiriusXMClient` — passed (29 tests, 6 suites).
- Static scan found no shared/persistent WebKit store, cookie export, JavaScript extraction, or suffix issuer acceptance.

## Decisions Made

- Restricted issuer evidence to the normalized apex cookie domain and exact `www` start host; unapproved SiriusXM subdomains remain unsupported until source-grounded evidence expands the allowlist.
- Kept bulk website-data removal opaque: production does not enumerate or return records, and tests observe only synthetic markers, counts, and booleans.
- Made cleanup success conjunctive: clean exact-token rescan and successful website-session retirement are both required.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected the synthetic insecure-cookie factory**
- **Found during:** Task 1
- **Issue:** Supplying `HTTPCookiePropertyKey.secure: "FALSE"` still constructed a secure cookie, so the insecure negative test did not exercise the intended condition.
- **Fix:** Omitted the Secure attribute entirely for synthetic insecure cookies.
- **Files modified:** `SiriusMacTests/WebAuthenticationBridgeTests.swift`
- **Verification:** Focused bridge suite passes with the insecure case rejected.
- **Committed in:** `c5d8e40` (part of Task 1 GREEN commit)

---

**Total deviations:** 1 auto-fixed (1 Rule 1 bug)
**Impact on plan:** The correction strengthened deterministic test fidelity without changing scope or production behavior.

## Issues Encountered

- The tracer gate briefly paused after its focused test passed; orchestration explicitly accepted that machine evidence and resumed the autonomous plan. No implementation work was skipped.

## Known Stubs

None.

## Next Phase Readiness

The WebKit authentication boundary now fails closed on issuer trust and cannot reuse a cleaned session. Later authentication work can rely on a fresh nonpersistent WebView after every successful cleanup.

## Self-Check: PASSED

- All four modified source and test files exist.
- RED commits `947f391`, `022932b` and GREEN commits `c5d8e40`, `57e69ec` exist in git history.
