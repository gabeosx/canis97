---
phase: 03-native-mac-listening-experience
plan: 09
subsystem: native macOS UAT regression closure
tags: [macos, appkit, swiftui, xcuitest, accessibility, window-management]
requires:
  - phase: 03-08
    provides: Approved Phase 03 native acceptance baseline
provides:
  - Credential-free DEBUG-only launched-app UI validation with production composition disabled before session construction
  - Exact 400 x 288 compact content geometry with safe-origin-only restoration
  - Immediate native library selection and exactly-once double-click/Return activation
affects: [phase-04-safe-skins-accessible-recovery, phase-verification, release-readiness]
actuals:
  tasks: 3
  commits: 8
tech-stack:
  added: []
  patterns:
    - Dedicated serialized UI-validation scheme isolated from the normal app-unit scheme
    - Harness-only AppKit accessibility marker for measuring the true window content region
    - Native List owns selection while one table-level AppKit double action owns activation
key-files:
  created:
    - SiriusMac/Testing/UITestHarness.swift
    - SiriusMac/Windows/NativeListDoubleActionBridge.swift
    - SiriusMacUITests/SiriusMacUITests.swift
    - SiriusMac.xcodeproj/xcshareddata/xcschemes/SiriusMacUIValidation.xcscheme
    - .planning/phases/03-native-mac-listening-experience/03-09-SUMMARY.md
  modified:
    - SiriusMac/SiriusMacApp.swift
    - SiriusMac/Windows/CompactWindowController.swift
    - SiriusMac/Catalog/ListeningView.swift
    - SiriusMacTests/AuthenticationPresentationModelTests.swift
    - SiriusMacTests/ListeningSessionControllerTests.swift
    - SiriusMac.xcodeproj/xcshareddata/xcschemes/SiriusMac.xcscheme
key-decisions:
  - "The UI-test flag is DEBUG-only, selected before production session composition, and fails closed in non-Debug builds."
  - "Compact restoration may restore a valid origin but always reapplies the fixed 400 x 288 content size."
  - "SwiftUI List remains the sole selection owner; AppKit target-action handles double-click without delaying single-click selection."
requirements-completed: [MAC-01, UI-01, UI-02, UI-03, ACCS-01]
gaps-closed: [G-03-7, G-03-17]
duration: multi-session implementation and isolated verification
completed: 2026-08-24
status: complete
---

# Phase 03 Plan 09: Native UAT Regression Closure Summary

**The compact player now keeps an exact native content size, library selection responds immediately, and an offline launched-app harness locks both behaviors down without subscriber state or provider access.**

## Accomplishments

- Added a deterministic DEBUG-only harness that composes the real compact player and native library from fixed synthetic channels and an in-memory local store before any production session, Keychain, WebKit, network, stream, or media collaborator can be created.
- Hardened launch safety with exact executable/PID checks, deterministic teardown, a dedicated serialized `SiriusMacUIValidation` scheme, and UI-test exclusion from the normal shared scheme.
- Changed compact restoration to retain only a safe saved origin and always enforce a 400 x 288 content rect.
- Removed the competing row-level double-click gesture; native List selection is immediate, while a narrow AppKit double-action bridge dispatches explicit activation exactly once.

## Verification

- Focused AppKit and launch-guard lane — 9 tests passed, zero failures.
- Fresh `xcodebuild build-for-testing` for `SiriusMacUIValidation` — passed.
- Offline launched-app harness smoke test — passed; compact and library windows appeared and exact-process teardown completed.
- Compact geometry XCUITest — passed; the harness-only AppKit marker measured a 400 x 288 content region aligned to the fixed-width window with only bounded native titlebar height.
- Native selection XCUITest — passed; two single clicks moved real native selection and left tune count at zero.
- Activation XCUITest — passed; double-click and Return each produced exactly one tune with the correct visible origin order.
- Human UAT — passed for both absence of authentication-sized compact border and immediate single-click/double-click/Return interaction behavior.
- Every post-run audit found no SiriusMac, UI runner, `xcodebuild`, or `xctest` process; `loginwindow` and `WindowServer` PIDs remained unchanged.

## Task Commits

1. **Credential-free launched-app harness** — `9ef746c`, `0d0f7b8`
2. **Exact compact content geometry** — `bb44328`, `c29c80c`
3. **Immediate selection and explicit activation** — `5df1ec6`, `670f8e5`
4. **Launch-safety closure** — `742cf78`, `389789e`

**Plan metadata:** committed separately with this summary, state, and roadmap transition.

## Deviations and Issues

- XCTest intermittently timed out while enabling automation mode before the app launched. Each occurrence stopped the sequence, left no residual process, and required explicit owner continuation; later serialized runs passed.
- SwiftUI exposed the root compact accessibility group using the 400 x 320 outer-window bounds. A harness-only AppKit content-region marker was added so launched verification measures the required 400 x 288 content view without changing production accessibility semantics.

## User Setup Required

None. The UI-validation harness is DEBUG-only and uses no external service or subscriber configuration.

## Next Phase Readiness

Phase 03 is complete. Phase 04 can build declarative skins on the fixed compact geometry and must preserve the closed native selection, activation, accessibility, focus, and recovery semantics.

## Self-Check: PASSED

- Confirmed all four serialized launched-app UI tests and both human UAT checks passed.
- Confirmed the offline UAT process is closed and `.gsd/` remains untouched.
- Confirmed implementation commits `9ef746c`, `0d0f7b8`, `bb44328`, `c29c80c`, `5df1ec6`, `670f8e5`, `742cf78`, and `389789e` exist in Git history.

---
*Phase: 03-native-mac-listening-experience*
*Completed: 2026-08-24*
