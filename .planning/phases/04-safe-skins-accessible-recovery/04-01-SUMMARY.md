---
phase: 04-safe-skins-accessible-recovery
plan: "01"
subsystem: ui
tags: [swiftui, appkit, skins, accessibility, persistence, json]

requires:
  - phase: 03-native-mac-listening-experience
    provides: Native compact presentation, app-owned controls, and fixed compact-window policy
provides:
  - Closed declarative appearance contract shared by native, bundled, and imported classifications
  - Metadata-only selected-appearance persistence with atomic replacement and Native recovery
  - Signal Glow and Tape Deck bundled manifests validated through the shared import-ready path
affects: [04-safe-skins-accessible-recovery, skin-import, skin-management, accessibility-uat]

actuals:
  tokens: 16925
  tasks: 3
  commits: 6

tech-stack:
  added: []
  patterns:
    - App-owned native controls rendered over bounded declarative appearance data
    - Persist-before-publish selection with generation ordering and direct Native recovery
    - Exact-key versioned JSON validation shared by bundled and imported appearances

key-files:
  created:
    - SiriusMac/Skins/SkinAppearance.swift
    - SiriusMac/Skins/SkinSelectionStore.swift
    - SiriusMac/Skins/Bundled/SignalGlow.json
    - SiriusMac/Skins/Bundled/TapeDeck.json
    - script/tests/SkinSelectionStoreOfflineTests.swift
    - script/tests/BundledSkinManifestOfflineTests.swift
  modified:
    - SiriusMac/Player/CompactPlayerView.swift
    - SiriusMac/SiriusMacApp.swift
    - SiriusMacTests/CompactPlayerPresentationTests.swift
    - SiriusMac.xcodeproj/project.pbxproj

key-decisions:
  - "Treat selected appearance as the primary path across native, bundled, and imported classifications."
  - "Persist only schema version, stable identifier, and classification; ordinary selections publish only after a durable write."
  - "Make Native recovery independent of custom resolution and publish it even when its persistence attempt fails."
  - "Load bundled resources through the same exact-key validator and validated appearance type reserved for imports."

patterns-established:
  - "Closed appearance vocabulary: skins can provide bounded palette, spacing, radius, and inert decorative assets, but never behavior or control geometry."
  - "Recovery anchor: the static Native appearance is always available without loading a custom manifest or managed file."
  - "Selection durability: equal references are no-ops, failed writes preserve the last confirmed appearance, and stale generations cannot publish."

requirements-completed: [ACCS-02, SKIN-01, SKIN-05]

coverage:
  - id: D1
    description: "Native, Signal Glow, and Tape Deck share one selected-appearance path and the production compact renderer."
    requirement: ACCS-02
    verification:
      - kind: integration
        ref: "xcodebuild build-for-testing with fresh DerivedData; no tests or app launched"
        status: pass
    human_judgment: true
    rationale: "Visual quality and assistive-technology behavior require authorized runtime UAT; this plan intentionally claims compile and contract evidence only."
  - id: D2
    description: "Selected appearance persists as atomic metadata-only state with idempotency, rollback, and Native fallback."
    requirement: SKIN-05
    verification:
      - kind: unit
        ref: "script/tests/SkinSelectionStoreOfflineTests.swift"
        status: pass
    human_judgment: false
  - id: D3
    description: "Exactly two complete bundled skin manifests pass the shared strict manifest contract and ship in app resources."
    requirement: SKIN-01
    verification:
      - kind: unit
        ref: "script/tests/BundledSkinManifestOfflineTests.swift"
        status: pass
      - kind: integration
        ref: "fresh build-for-testing app-bundle resource existence check"
        status: pass
    human_judgment: false
  - id: D4
    description: "Appearance data cannot replace native actions, accessibility semantics, 32-point transport regions, or 400 x 288 window geometry."
    requirement: ACCS-02
    verification:
      - kind: integration
        ref: "compiled CompactPlayerPresentationTests contract plus fixed-geometry source checks"
        status: pass
    human_judgment: true
    rationale: "The native accessibility tree, focus traversal, and Reduce Motion behavior were not exercised at runtime under the project's launch restrictions."

duration: 20min
completed: 2026-08-25
status: complete
---

# Phase 04 Plan 01: Safe Appearance Foundation Summary

**A closed, persistent appearance pipeline now serves Native and two bundled skins while keeping compact-player behavior, accessibility semantics, and geometry app-owned.**

## Performance

- **Duration:** 20 min
- **Started:** 2026-08-25T21:39:23Z
- **Completed:** 2026-08-25T21:59:09Z
- **Tasks:** 3
- **Files modified:** 10

## Accomplishments

- Added one strict versioned appearance vocabulary and a shared production selection-to-render path for native, bundled, and future imported appearances.
- Added atomic metadata-only persistence, same-selection idempotency, rollback on write failure, startup fallback, and a direct Native recovery action.
- Shipped Signal Glow and Tape Deck as complete JSON resources validated through the import-ready validator, with offline exact-count and schema audits.
- Preserved the existing native action and accessibility modifiers, 32-point transport regions, and fixed 400 x 288 compact content contract.

## Task Commits

Each task was committed atomically; TDD tasks have separate RED and GREEN commits:

1. **Task 04-01-01: Select one bundled appearance through the production native renderer** - `a0a4892`
2. **Task 04-01-02 RED: Define selected appearance persistence contract** - `cbed3dc`
3. **Task 04-01-02 GREEN: Persist selected appearance metadata safely** - `5710580`
4. **Task 04-01-03 RED: Define bundled skin manifest contract** - `918bba0`
5. **Task 04-01-03 GREEN: Ship two validated bundled appearances** - `0fc6e1e`

**Plan metadata:** committed with this summary.

## Files Created/Modified

- `SiriusMac/Skins/SkinAppearance.swift` - Closed manifest, validator, classifications, catalog, controller, and bundle loading.
- `SiriusMac/Skins/SkinSelectionStore.swift` - Versioned atomic metadata persistence and fail-closed restoration.
- `SiriusMac/Skins/Bundled/SignalGlow.json` - Complete Signal Glow bundled manifest.
- `SiriusMac/Skins/Bundled/TapeDeck.json` - Complete Tape Deck bundled manifest.
- `SiriusMac/Player/CompactPlayerView.swift` - Applies validated visual tokens and inert decoration behind native controls.
- `SiriusMac/SiriusMacApp.swift` - Shares one app-lifetime appearance controller with compact content and Player commands.
- `SiriusMacTests/CompactPlayerPresentationTests.swift` - Compiled classification, selection-path, Native-presence, and geometry-rejection contracts.
- `script/tests/SkinSelectionStoreOfflineTests.swift` - Offline persistence, idempotency, rollback, malformed-record, and metadata-only checks.
- `script/tests/BundledSkinManifestOfflineTests.swift` - Offline exact-count, completeness, ordering, boundary, and unknown-key audit.
- `SiriusMac.xcodeproj/project.pbxproj` - Registers new sources and bundled JSON resources.

## Decisions Made

- Selected appearance is the app's primary noun; Native is both a normal selection and the permanent recovery anchor.
- Ordinary selection resolves first, persists second, and publishes last. Direct Native recovery publishes immediately and reports persistence failure separately.
- The durable record deliberately excludes manifest bytes, style tokens, paths, provider data, and subscriber state.
- Bundled skins are data resources rather than Swift special cases, so later imported skins exercise the same validator and renderer boundary.

## Flagged Assumption Results

- **A-04-01:** Passed by exact unknown-key rejection for attempted control/window geometry and unchanged 32-point/400 x 288 source contracts.
- **A-04-02:** Passed by integer-only bounded metric validation; accessibility and control geometry are absent from the manifest vocabulary.
- **A-04-03:** Passed by the offline same-reference no-write check and controller no-op guard.
- **A-04-04:** Implemented and compiled: main-actor isolation plus generation checks prevent stale publication. No runtime concurrency forcing was performed.
- **A-04-05:** Passed: the bundled audit succeeds with exactly two resources and fails closed with one.
- **A-04-06:** Passed by complete required-key validation and deterministic display-name/identifier ordering checks.

Runtime visual appearance, VoiceOver traversal, focus behavior, and Reduce Motion behavior remain **NOT OBSERVED** under the binding launch/test restrictions.

## Deviations from Plan

None - the plan was executed within its declared files and behavior.

## Issues Encountered

- The standalone Swift resource audit required a top-level entry point instead of `@main`; corrected before the RED contract commit.
- Swift needed an explicit `compactMap` element type for bundled resource loading; added before the GREEN implementation commit.
- The final build-only run emitted existing warnings in files outside this plan and signed-XCTest copy diagnostics, but completed with exit status 0. No out-of-scope files were changed.

## Verification

- `SkinSelectionStoreOfflineTests`: all classifications round-trip, equal selection is a no-op, failed replacement preserves durable state, malformed/unsupported data recovers to Native, and JSON remains metadata-only.
- `BundledSkinManifestOfflineTests`: exactly two complete manifests, valid schema/palette/metrics, distinct deterministic ordering, unknown-key rejection; the same audit fails with one resource.
- `xcodebuild build-for-testing`: passed against a fresh unique DerivedData path; all configured targets compiled and both JSON files were found in the built app resources. No tests or application were launched.
- `git diff --check`: passed.

## User Setup Required

None - no external service configuration is required.

## Next Phase Readiness

The closed validator, classification, catalog, persistence, and renderer boundaries are ready for managed local skin import and management work. Visual and assistive-technology runtime UAT remains deferred to the authorized phase-level verification lane.

## Self-Check: PASSED

- All ten plan-owned implementation/test/resource paths exist in the committed diff.
- Five task commits are present and independently scoped.
- `.planning/STATE.md` and `.planning/ROADMAP.md` are unchanged.
- No prohibited test runner, app launch, live SiriusXM operation, or shared checkout path was used.

---
*Phase: 04-safe-skins-accessible-recovery*
*Completed: 2026-08-25*
