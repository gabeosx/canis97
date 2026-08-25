---
phase: 04-safe-skins-accessible-recovery
plan: "03"
subsystem: ui
tags: [swiftui, skins, accessibility, managed-storage, recovery]

requires:
  - phase: 04-safe-skins-accessible-recovery
    provides: Validated appearance catalog, bundled skins, metadata-only persistence, and safe managed package import from Plans 04-01 and 04-02
provides:
  - Native Settings appearance management for Native, bundled, and imported entries
  - Managed-only imported removal with durable Native confirmation for selected packages
  - Always-enabled package-independent Player-menu Native recovery
  - Static Native rendering fallback for decoration decode loss with closed app-owned status
affects: [skin-management, compact-player, accessibility, runtime-uat]

actuals:
  tasks: 3
  commits: 8

tech-stack:
  added: []
  patterns:
    - App-lifetime appearance/import controllers shared by Settings and compact rendering
    - Persist Native before deleting selected imported content; reconcile catalog only after deletion
    - Resolve the complete appearance to static Native when any inert decoration becomes unusable

key-files:
  created:
    - SiriusMac/Skins/SkinManagementView.swift
  modified:
    - SiriusMac/Skins/SkinAppearance.swift
    - SiriusMac/Skins/SkinPackageImporter.swift
    - SiriusMac/Player/CompactPlayerView.swift
    - SiriusMac/SiriusMacApp.swift
    - SiriusMac.xcodeproj/project.pbxproj
    - SiriusMacTests/SkinPackageImporterTests.swift
    - SiriusMacTests/CompactPlayerPresentationTests.swift
    - SiriusMacTests/AccessibilityContractTests.swift

key-decisions:
  - "Expose appearance management through the native Settings scene and a Player-menu SettingsLink while keeping rows limited to stable semantic references and closed actions."
  - "Serialize removal with import work, use the ordinary persisted selection path before selected-package deletion, and treat an already-absent imported package as successful reconciliation."
  - "Keep Use Native Appearance top-level, always enabled, and directly bound to restoreNativeAppearance() with no selected-package lookup."
  - "Decode decorations during validation and re-check renderability at display time; one failed decoration replaces the full style with static Native and never changes controls or announcements."

patterns-established:
  - "Permanent classes: Native and bundled rows never receive a removal action; every storage/controller removal entry point independently requires an imported reference."
  - "Closed recovery: persistence failure blocks deletion, deletion failure retains the catalog entry with Native active, and render failure uses bounded app-owned status."
  - "Semantic isolation: custom appearance data supplies only bounded colors, spacing, radius, foreground scheme, and inert hidden decoration behind one native control tree."

requirements-completed: [ACCS-02, SKIN-01, SKIN-02, SKIN-05]

coverage:
  - id: D1
    description: "One native management surface lists and selects Native, bundled, and imported appearances and presents closed import outcomes."
    requirement: SKIN-02
    verification:
      - kind: integration
        ref: "xcodebuild build-for-testing with fresh unique DerivedData; app and tests not launched"
        status: pass
      - kind: other
        ref: "source audit of Settings/Player routing and stable SkinSelectionReference row authority"
        status: pass
    human_judgment: true
    rationale: "Real file-panel import, keyboard navigation, focus behavior, and visual management state remain A-04-13 runtime UAT."
  - id: D2
    description: "Imported removal preserves a valid confirmed selection and cannot remove Native or bundled appearances."
    requirement: SKIN-05
    verification:
      - kind: integration
        ref: "compiled selected/nonselected, persistence-failure, deletion-failure, idempotence, permanence, and concurrent-selection contracts"
        status: pass
      - kind: other
        ref: "source audit of imported guards, direct-child managed deletion, persistence-before-delete ordering, and catalog reconciliation"
        status: pass
    human_judgment: true
    rationale: "The app-hosted contracts were compiled but intentionally not executed; real selected and nonselected removal remains deferred."
  - id: D3
    description: "Native recovery is package-independent and decoration failure cannot alter compact-player semantics, geometry, hit regions, or announcements."
    requirement: ACCS-02
    verification:
      - kind: integration
        ref: "compiled cross-class, render-failure, direct-command, management-focus, and announcement-boundary source contracts"
        status: pass
      - kind: other
        ref: "source audit confirmed direct enabled Native command, one control tree, 400 x 288 frame, 32-point transport regions, and inert accessibility-hidden decoration"
        status: pass
    human_judgment: true
    rationale: "Keyboard, VoiceOver, focus visuals, Reduce Motion, and recovery observation remain the explicitly unverified A-04-13 walkthrough."
  - id: D4
    description: "Both bundled manifests remain exact, complete, deterministic inputs to the same finite appearance contract."
    requirement: SKIN-01
    verification:
      - kind: unit
        ref: "BundledSkinManifestOfflineTests.swift"
        status: pass
    human_judgment: false

duration: 26min
completed: 2026-08-25
status: complete
---

# Phase 04 Plan 03: Accessible Skin Management and Native Recovery Summary

**Sirius Mac now provides one native appearance-management surface, safe managed-package removal, and an unconditional static-Native recovery path without giving custom appearance data control over player semantics or accessibility.**

## Performance

- **Duration:** 26 min
- **Started:** 2026-08-25T18:32:00-04:00
- **Completed:** 2026-08-25T18:58:01-04:00
- **Tasks:** 3
- **Files modified:** 10, including this summary

## Accomplishments

- Added a native Settings appearance manager, Player > Manage Appearances route, classification/selection state, single-package import progress/cancellation, and closed actionable errors including a distinct reachable unsupported-schema result.
- Added imported-only managed removal with confirmation, persistence-before-delete for selected content, deletion-failure catalog retention, absent-package idempotence, Native/bundled permanence, focus restoration, and import/removal serialization.
- Kept Player > Use Native Appearance enabled and bound directly to the static Native controller path without consulting selected custom content.
- Added full Image I/O decode validation plus display-time renderability fallback to the static Native value and bounded app-owned recovery status.
- Extended compiled contracts for removal ordering/concurrency, stable semantic authority, cross-class fixed controls/geometry, inert decoration, direct recovery, management focus/error boundaries, and announcement isolation.

## Task Commits

Each task was committed atomically; TDD tasks have separate RED and GREEN commits:

1. **Task 04-03-01: Add native appearance management** - `ef67642`
2. **Task 04-03-02 RED: Define imported removal contract** - `52dee0d`
3. **Task 04-03-02 GREEN: Remove imported skins safely** - `a2cde9a`
4. **Task 04-03-03 RED: Define Native recovery invariants** - `b3727a6`
5. **Task 04-03-03 GREEN: Lock Native appearance recovery** - `5822359`
6. **Task 04-03-02 follow-up: Cover concurrent selection/removal** - `bb7063d`
7. **Source-audit fix: Preserve unsupported skin-version errors** - `6219373`

**Plan metadata:** committed with this summary.

## Files Created/Modified

- `SiriusMac/Skins/SkinManagementView.swift` - Native Settings list, selection/import/removal controls, progress, confirmation, focus restoration, and closed status/error copy.
- `SiriusMac/Skins/SkinAppearance.swift` - Imported catalog removal, generation-checked lifecycle coordination, hardened static Native restore, and renderability fallback.
- `SiriusMac/Skins/SkinPackageImporter.swift` - Exact managed-package removal, import/removal actor serialization, distinct schema compatibility failure, and full image decode validation.
- `SiriusMac/Player/CompactPlayerView.swift` - One invariant native control tree with complete Native fallback, inert decoration, and closed recovery status.
- `SiriusMac/SiriusMacApp.swift` - Shared app-lifetime removal seam, Settings scene, management route, direct Native command, and render-failure recovery callback.
- `SiriusMac.xcodeproj/project.pbxproj` - Management-view app target membership.
- `SiriusMacTests/SkinPackageImporterTests.swift` - Compiled removal ordering, failure, idempotence, permanence, and concurrency contracts.
- `SiriusMacTests/CompactPlayerPresentationTests.swift` - Compiled render fallback, cross-class semantic/geometry, management-authority, and direct-command source contracts.
- `SiriusMacTests/AccessibilityContractTests.swift` - Compiled focus, native-control, inert-decoration, closed-copy, and announcement-boundary contracts.

## Decisions Made

- The management view receives only `SkinAppearanceController` and `SkinImportCoordinator`; rows receive bounded display text, classification, stable reference, selected state, and app-owned closures.
- Removal derives the canonical package directory only from a validated imported identifier beneath the managed Packages root. It never retains or deletes the original archive URL.
- Selected removal uses ordinary `select(.native)` persistence before the deletion closure. If persistence fails, the imported selection and package remain; if deletion fails afterward, Native remains active and the catalog entry remains retryable.
- `restoreNativeAppearance()` publishes `SkinAppearanceCatalog.nativeAppearance` before persistence and works even when Native is already selected. The Player command has no selected-package lookup or disabled modifier.
- Appearance validation now constructs the single Image I/O frame, while the renderer re-checks requested assets. Any unavailable decoration replaces the entire appearance with the static Native value and records app-owned status outside `AccessibilityAnnouncementEvent`.

## Private Helper Inventory

The plan-authorized helpers added during execution are:

- `SkinRemovalConfirmation`, `isBusy`, and `removalAction(for:)` in `SkinManagementView` for bounded confirmation state and imported-only actions.
- `SkinAppearanceCatalog.removingImported(_:)`, `removeImportedPackage`, `removalsInProgress`, and `removalError` for lifecycle reconciliation and generation exclusion.
- `ManagedSkinStore.removeManagedPackage` injection for deterministic deletion failures; its existing direct-child check remains the ownership boundary.
- `SkinPackageCompatibilityFailure` for the closed unsupported-schema category across importer and UI without exposing validator text.
- `ValidatedSkinAppearance.renderableAppearance(_:)`, `CompactPlayerView.renderingAppearance`, `needsNativeAppearanceRecovery`, `showsNativeAppearanceRecoveryStatus`, and `onAppearanceRecovery` for complete static-Native display recovery.
- `RemovalEventProbe` and `RemovalPersistenceGate` in compiled tests for ordering, failure, idempotence, and concurrent selection/removal contracts.
- Test-only `repositorySource(_:)` helpers for bounded source invariants without launching an app or test host.

## Source Coverage Audit

- **PASS:** Every Multi-Source Coverage Audit row is `COVERED`; the absent `RESEARCH.md` row is explicitly `EXCLUDED` because locked context supplies the contracts.
- **PASS:** D-01 through D-16 each appear in an owning task action; no decision citation is orphaned.
- **PASS:** `Use Native Appearance` directly calls `restoreNativeAppearance()`, has no selected-package resolution, and has no disabled modifier.
- **PASS:** `CompactPlayerView` has no classification-based control branch, keeps the fixed 400 x 288 style size and 32-point transport regions, and marks every decoration as non-hit-testable and accessibility-hidden.
- **PASS:** `SkinManagementView` contains no listening-session, accessibility-announcer, window-policy, manifest, `NSAlert`, or `NSOpenPanel` authority.
- **PASS:** Appearance management and recovery do not call or extend `AccessibilityAnnouncementEvent`; copy is finite and app-owned.
- **PASS:** Removal requires imported classification at UI/controller/store boundaries, derives an exact direct child of Packages, rejects symlinks/non-directories, confirms Native before selected deletion, and removes the catalog value only after storage success.
- **PASS:** The committed implementation diff contains only the nine plan-owned source/test/project paths plus this summary. `.planning/STATE.md`, `.planning/ROADMAP.md`, `.planning/config.json`, and `.planning/PROJECT.md` are unchanged.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Preserved the distinct unsupported-schema presentation**

- **Found during:** Final source audit
- **Issue:** The management UI defined closed unsupported-version copy, but the importer collapsed `SkinManifestValidationError.unsupportedSchema` into generic invalid-manifest rejection, leaving that copy unreachable.
- **Fix:** Added `SkinPackageCompatibilityFailure.unsupportedSchema` and mapped only that validator result to the existing closed UI case.
- **Files modified:** `SiriusMac/Skins/SkinPackageImporter.swift`, `SiriusMac/Skins/SkinManagementView.swift`, `SiriusMacTests/CompactPlayerPresentationTests.swift`
- **Verification:** Fresh final `xcodebuild build-for-testing` passed; source contract confirms the distinct boundary.
- **Committed in:** `6219373`

**2. [Rule 2 - Missing Critical] Added a deterministic concurrent selection/removal contract**

- **Found during:** Task 04-03-03 source review
- **Issue:** Ordering/failure cases were covered, but the plan's explicit newer-selection-versus-removal generation case was not yet represented by an injected compile contract.
- **Fix:** Added a bounded persistence gate proving a newer bundled selection invalidates selected removal before deletion begins and retains the imported catalog entry.
- **Files modified:** `SiriusMacTests/SkinPackageImporterTests.swift`
- **Verification:** Fresh compile-only `build-for-testing` passed.
- **Committed in:** `bb7063d`

---

**Total deviations:** 2 auto-fixed issues (one reachable-error bug, one missing concurrency contract).
**Impact on plan:** Both changes close declared contracts within owned files; no new product authority, persistence format, or runtime operation was introduced.

## Issues Encountered

- Task 04-03-02 RED failed on the deliberately absent removal APIs; its first GREEN compile exposed a SwiftUI type-checker diagnostic and async XCTest autoclosures, both corrected before the passing task compile.
- Task 04-03-03 RED failed on the deliberately absent renderability API and passed after the Native fallback implementation.
- `build-for-testing` generated an untracked `SiriusMac.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`; the exact generated workspace directory was moved to a temporary holding directory before summary staging because it was absent initially and outside plan ownership.
- Build-only output retained pre-existing warnings in `AccessibilityAnnouncer.swift`, `WebAuthenticationBridgeTests.swift`, signed XCTest framework copying, and App Intents metadata extraction. No new compile error or plan-owned warning blocked validation.
- `CODE_SIGNING_ALLOWED=NO` was used for compile-only verification instead of the plan's ad-hoc signing flags; this avoided signing state while preserving the authorized `build-for-testing` boundary.

## Verification

- Selection persistence offline executable: **PASS** — all classifications round-trip, same-selection no-op, failed replacement preservation, malformed/unsupported Native recovery, and metadata-only JSON.
- Bundled manifest offline executable: **PASS** — exactly two complete manifests, bounded schema/palette/metrics, deterministic ordering, and unknown-field rejection.
- Package policy offline executable: **PASS** — 36 assertions.
- Final `xcodebuild build-for-testing`: **PASS**, `/tmp/sirius-mac-04-03-final2.Gq20JV`; app and test bundles compiled only and were not launched.
- Multi-source and D-01 through D-16 source audit: **PASS**.
- Owned-scope diff and `git diff --check`: **PASS**.

## Explicit A-04-13 Runtime UAT Deferrals

A-04-13 remains explicitly **UNVERIFIED**. The launch-safety policy prohibited all runtime app/test lanes, so this plan did not claim or observe:

- Keyboard traversal, default/cancel actions, focus restoration, visible focus indicators, or native menu/Settings behavior.
- VoiceOver labels, values, order, live-region behavior, or announcement timing across management and compact-player states.
- Visual equivalence and readability for Native, Signal Glow, Tape Deck, a real imported appearance, long metadata, missing artwork, selected state, failure state, and Reduce Motion.
- Runtime missing/corrupt/unsupported/decode-failed/render-failed selected-package recovery or persistence behavior.
- Real `.siriusskin` file-panel import, selection, cancellation, selected/nonselected removal, repeated removal, deletion failure, or source archive removal/mutation.
- App-hosted XCTest, UI automation, the SiriusMac app/test host, or any live SiriusXM authentication, catalog, tune, playback, metadata, telemetry, or compatibility check.

These checks require a separately authorized safety review and safe execution environment.

## User Setup Required

None - no external service configuration is required.

## Next Phase Readiness

Phase 04's compile/offline implementation is complete and its source audit passes. Phase/release acceptance still requires the separately authorized A-04-13 keyboard, VoiceOver, visual, recovery, and real import/removal UAT; no runtime evidence is claimed here.

## Self-Check: PASSED

- All nine declared implementation/test/project paths and this summary are present in the committed plan diff.
- Seven atomic implementation/test/fix commits plus this summary commit are present; commit hooks ran for every commit.
- `.planning/STATE.md` and `.planning/ROADMAP.md` are unchanged.
- No out-of-scope file remains modified or untracked.
- No prohibited test runner, app/test host, UI automation, application launch, build-and-run script, or live SiriusXM operation was used.

---
*Phase: 04-safe-skins-accessible-recovery*
*Completed: 2026-08-25*
