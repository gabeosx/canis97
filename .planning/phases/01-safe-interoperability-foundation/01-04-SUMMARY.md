---
phase: 01-safe-interoperability-foundation
plan: "04"
subsystem: credential-persistence-and-sign-out
tags: [swift, security-framework, keychain, actor-isolation, sign-out, cleanup]
requires:
  - phase: 01-01
    provides: Opaque credential handoff and app-bound credential-store seam.
  - phase: 01-02
    provides: Entitlement-gated actor-owned session lifecycle.
  - phase: 01-03
    provides: Redacted diagnostics and native transport safety boundaries.
provides:
  - App-owned Keychain credential CRUD using direct Security.framework APIs
  - SPI-only app integration bridge for approved volatile material
  - Memory-first sign-out with honest aggregate Keychain and browser cleanup results
affects: [01-06, 01-07, phase-2]
tech-stack:
  added: []
  patterns: [direct SecItem lifecycle, SPI-scoped secret handoff, memory-first cleanup, aggregate cleanup outcomes]
key-files:
  created:
    - SiriusMac/Security/KeychainCredentialStore.swift
    - SiriusMacTests/KeychainCredentialStoreTests.swift
    - Packages/SiriusXMClient/Tests/SiriusXMClientTests/SignOutTests.swift
  modified:
    - SiriusMac.xcodeproj/project.pbxproj
    - Packages/SiriusXMClient/Sources/SiriusXMClient/Public/AuthenticationModels.swift
    - Packages/SiriusXMClient/Sources/SiriusXMClient/Public/SiriusXMClient.swift
    - Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift
key-decisions:
  - "Keep app Keychain access behind one generic-password identity and safe classifications with no OSStatus or secret detail."
  - "Expose material to the app-owned Keychain adapter only through an SPI-scoped closure, never through the ordinary public client API."
  - "Retire actor state before starting both local cleaners and report their aggregate outcome without retrying cleanup."
actuals:
  tokens: 8765
  tasks: 2
  commits: 4
duration: 10min
completed: 2026-08-18
status: complete
---

# Phase 01 Plan 04: Keychain Persistence and Memory-First Sign-Out Summary

**The app now stores approved reusable material solely in Keychain and ends sessions by retiring memory before independently attempting each local cleanup.**

## Performance

- **Duration:** 10 min
- **Started:** 2026-08-18T03:54:00Z
- **Completed:** 2026-08-18T04:04:01Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- Added an app-owned `KeychainCredentialStore` using `SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate`, and `SecItemDelete` for one app-scoped generic-password identity.
- Added randomized integration coverage for add, read, update-on-duplicate, delete, missing-item, and safe failure classification behavior.
- Added an SPI-scoped closure that gives only the app integration adapter ephemeral access to approved material while keeping ordinary client consumers unable to retrieve it.
- Added sign-out state revocation that invalidates in-flight session work, clears actor-held material before cleanup, and runs Keychain and browser-residue cleaners once.
- Added semantic aggregate outcomes for partial cleanup failure, so signed-out memory is never restored and incomplete local cleanup is visible.

## Task Commits

1. **Task 1: Implement isolated app-owned Keychain CRUD** - `77fd418` (RED), `50b123a` (GREEN)
2. **Task 2: Enforce memory-first aggregate sign-out cleanup** - `aeb63b9` (RED), `939d488` (GREEN)

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/KeychainCredentialStoreTests test` — passed (3 tests).
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SiriusXMClient --filter SignOutTests` — passed (4 tests).
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SiriusXMClient` — passed (23 tests).

## Decisions Made

- Treat a missing Keychain item as a successful idempotent deletion but classify any other Security failure without exposing an OS status, item identity, or secret.
- Keep the Keychain implementation app-owned; the package provides only the narrow credential-store and browser-residue cleanup contracts.
- Allow stale in-flight verification to finish internally, but revoke its lease immediately so it cannot publish or restore a session after sign-out.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added an SPI-only Keychain handoff for opaque credentials.**
- **Found during:** Task 1
- **Issue:** The app's required `CredentialStore` conformer had no safe way to persist opaque material; the existing package helper was inaccessible across the app boundary.
- **Fix:** Added the `AppIntegration` SPI closure used only by `KeychainCredentialStore`, retaining no ordinary public material accessor.
- **Files modified:** `Packages/SiriusXMClient/Sources/SiriusXMClient/Public/AuthenticationModels.swift`, `SiriusMac/Security/KeychainCredentialStore.swift`
- **Commit:** `50b123a`

**2. [Rule 1 - Bug] Corrected initial project membership and Swift control-flow issues.**
- **Found during:** Tasks 1 and 2
- **Issue:** Initial Xcode group references resolved the new source at the project root, and a stale-attempt defer path plus a test helper return did not compile.
- **Fix:** Corrected the project file references and made stale lease cleanup conditional without returning from `defer`; returned the cleaner test outcome explicitly.
- **Files modified:** `SiriusMac.xcodeproj/project.pbxproj`, `Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift`, `Packages/SiriusXMClient/Tests/SiriusXMClientTests/SignOutTests.swift`
- **Commit:** `77fd418`, `939d488`

**Total deviations:** 2 auto-fixed (1 Rule 2 critical integration fix, 1 Rule 1 bug fix).

## Known Stubs

None.

## Next Phase Readiness

- Plan 01-06 can implement `AuthenticationResidueCleaner` with the shared exact WebView cookie policy.
- Plan 01-07 can compose the app Keychain adapter and browser cleaner with the settled runtime transaction.

## Self-Check: PASSED

- All seven production, project, and test files exist.
- All four RED/GREEN task commits are present in git history.
- Focused Xcode and SwiftPM tests pass, and the complete package suite remains green.
