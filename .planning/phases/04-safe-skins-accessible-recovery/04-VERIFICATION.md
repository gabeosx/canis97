---
phase: 04-safe-skins-accessible-recovery
verified: 2026-08-25T23:07:18Z
status: human_needed
score: 0/5 must-haves verified
behavior_unverified: 5
overrides_applied: 0
behavior_unverified_items:
  - truth: "A subscriber can choose between at least two complete, tested bundled player skins."
    test: "Launch the app, use Player > Appearance to choose Signal Glow and Tape Deck, then return to Native."
    expected: "Each selection changes only the compact-player visual treatment; all controls remain usable and Native is restored."
    why_human: "The static bundle, catalog, menu wiring, and manifest tests are present, but the app-host safety policy forbids exercising the rendered selection flow."
  - truth: "A subscriber can import, validate, select, and remove a local user-created declarative package with local assets."
    test: "In Manage Appearances, import a valid local .siriusskin with one local image, select it, then remove it."
    expected: "The imported entry is shown and selected, then removal returns to Native and removes only the managed package."
    why_human: "The importer/UI transaction is wired in source, but importing a real archive through the app is a runtime state transition that is not permitted in this verification environment."
  - truth: "Executable, remote, active-URL, arbitrary-file, or authority-bearing package content is rejected without altering the player."
    test: "Attempt representative rejected packages containing an unknown manifest capability key, an active URL, traversal path, and an unreferenced file."
    expected: "Each attempt shows a closed error, leaves the existing selected appearance intact, and creates no selectable imported entry."
    why_human: "The pure policy boundary ran successfully, but full ZIP/ImageIO/importer-to-UI rollback behavior is not exercised without the prohibited app/test host."
  - truth: "Unsafe schema, paths, entry types, file types, or resource budgets reject safely."
    test: "Attempt packages just over each documented boundary, plus encrypted/symlink/traversal and invalid-image fixtures."
    expected: "Each package is rejected through a closed message; existing appearance, catalog, and selection remain unchanged."
    why_human: "The 36-assertion policy suite proves the pure limits, but the end-to-end archive and rendering path is runtime-only here."
  - truth: "Failed or invalid skins preserve a valid appearance and built-in recovery never loses semantics, target size, focus/state indicators, or the Native fallback."
    test: "Select a package whose decoration is subsequently missing or corrupt, then invoke Player > Use Native Appearance with the package unavailable."
    expected: "The compact player falls back to Native, exposes the recovery state, and the Player-menu Native command remains available and restores Native."
    why_human: "A-04-13 deliberately defers keyboard, VoiceOver, visual, and recovery walkthroughs until an approved app-runtime safety environment exists."
human_verification:
  - test: "Correct the Phase 4 MVP goal format."
    expected: "ROADMAP.md uses a valid user story: 'As a [role], I want to [capability], so that [outcome].'"
    why_human: "Phase 4 is marked `Mode: mvp`, but its present goal fails the canonical user-story validator, so MVP user-flow verification cannot be authoritative."
  - test: "Run the bundled appearance selection and recovery walkthrough."
    expected: "Signal Glow, Tape Deck, and Native render through the Player menu without changing semantic controls or geometry."
    why_human: "The repository policy prohibits launching the app, UI tests, and app-hosted XCTest until a separate safety review authorizes an environment."
  - test: "Run a valid-package import/select/remove and rejected-package preservation walkthrough."
    expected: "Valid local packages are managed atomically; invalid/hostile packages leave the current appearance intact and show only closed messages."
    why_human: "Full archive/import UI state and rollback cannot be exercised by the allowed offline checks."
  - test: "Check accessibility and recovery with keyboard navigation, VoiceOver, and a missing/corrupt decorative asset."
    expected: "Native semantic controls, focus/state indicators, 32-point targets, and the direct Native recovery path remain usable."
    why_human: "Visual, VoiceOver, and runtime focus behavior require a manually approved app-runtime UAT (A-04-13)."
---

# Phase 4: Safe Skins & Accessible Recovery Verification Report

**Phase Goal:** Subscribers can give the player a nostalgic local appearance while every skin remains declarative, bounded, accessible, and recoverable.
**Verified:** 2026-08-25T23:07:18Z
**Status:** human_needed
**Re-verification:** No — initial verification

## MVP Mode Configuration

Phase 4 declares `Mode: mvp`, but its goal is not a valid user story. The canonical validator returned `valid: false`, with all three required slots absent: `As a [role]`, `I want to [capability]`, and `so that [outcome].` Per MVP verification policy, an authoritative MVP user-flow verdict is withheld until the roadmap goal is corrected. The source audit below is supporting technical evidence, not a substitute for the required user-flow verification.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | A subscriber can choose between at least two complete, tested bundled player skins. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `SignalGlow.json` and `TapeDeck.json` are complete resources in the app target; `SkinAppearanceCatalog.bundledCatalog` validates both; `CompactPlayerView` receives the selected appearance; the isolated bundled-manifest check passed. The rendered menu flow was not run. |
| 2 | A subscriber can import, validate, select, and remove a local user-created declarative package with local assets. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `SkinManagementView` calls `SkinImportCoordinator.importAndSelect` and `removeImportedSkin`; the coordinator serializes transactions and `ManagedSkinStore` owns app-support package paths. Real archive/UI execution was not run. |
| 3 | Executable, remote, active-URL, arbitrary-file, or authority-bearing package content is rejected without altering the player. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | The closed `SkinManifest` permits palette/metrics plus two local asset names only; skin files contain no network, playback, auth, persistence, or accessibility authority. `SkinPackagePolicyOfflineTests` passed 36 boundary assertions. Full importer rollback was not run. |
| 4 | Unknown schema, unsafe path/type, or excess archive/asset/processing budget rejects safely. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `SkinPackagePolicy` rejects unknown paths/types and enforces exact limits; `SkinPackageImporter` preflights ZIP entries, streams accounting, verifies ImageIO type/frame/dimensions, and stages before promotion. The pure policy suite passed; a real ZIP/ImageIO transaction was not exercised. |
| 5 | Failed/invalid skins preserve a prior valid appearance and provide accessible Native recovery. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Ordinary selection persists before publication; selected removal persists Native before deletion; unavailable decoration resolves to static Native; Player > Use Native Appearance calls `restoreNativeAppearance()` directly without package lookup. Keyboard/VoiceOver/visual recovery UAT remains intentionally deferred by A-04-13. |

**Score:** 0/5 truths verified (5 present, behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
| --- | --- | --- | --- |
| `SiriusMac/Skins/SkinAppearance.swift` | Closed manifest, catalog, selection, recovery contract | ✓ VERIFIED | 523 substantive lines; exact-key/schema/metric validation; catalog has permanent Native; controller owns selection generation and recovery. |
| `SiriusMac/Skins/SkinSelectionStore.swift` | Atomic metadata-only selection persistence | ✓ VERIFIED | 162 substantive lines; only schema/version, identifier, and classification persist; temporary replace/move preserves prior record on failure. Isolated rollback/idempotency check passed. |
| `SiriusMac/Skins/Bundled/SignalGlow.json` and `TapeDeck.json` | Two complete bundled manifests | ✓ VERIFIED | Both are resources in `project.pbxproj`; the isolated contract check passed exactly-two, schema/metric, ordering, and unknown-field assertions. |
| `SiriusMac/Skins/SkinPackagePolicy.swift` | Hostile archive/path/budget boundary | ✓ VERIFIED | 342 substantive lines; canonical path, collision, ratio, overflow, streamed-byte, image, and deadline checks. 36-assertion offline suite passed. |
| `SiriusMac/Skins/SkinPackageImporter.swift` | Validated atomic import and managed removal | ✓ VERIFIED | 791 substantive lines; two-pass ZIP preflight/extraction, ImageIO validation, staging/promotion/rollback, exact managed-root removal, and serialized coordinator. |
| `SiriusMac/Skins/SkinManagementView.swift` | Native management, selection/import/removal/error UI | ✓ VERIFIED | 360 substantive lines; native `fileImporter`, focused rows, import cancellation, imported-only destructive removal, and closed user-facing errors. |
| `SiriusMac/Player/CompactPlayerView.swift` | One native-control renderer parameterized by validated appearance data | ✓ VERIFIED | Decorative assets are behind native controls with `allowsHitTesting(false)` and `accessibilityHidden(true)`; dimensions and transport controls remain app-owned. |
| `SiriusMac/SiriusMacApp.swift` | App-lifetime controller, Settings/menu routes, direct recovery | ✓ VERIFIED | One `SkinAppearanceController` is passed to compact content, settings, and Player commands; recovery action is direct and has no disabled state. |

### Key Link Verification

| From | To | Via | Status | Details |
| --- | --- | --- | --- | --- |
| App composition | `SkinAppearanceController` | Shared app-lifetime instance | ✓ WIRED | Constructed once in `SiriusMacApp.init`, passed to `CompactListeningSlice`, `ListeningCommands`, and `SkinManagementView`. |
| `SkinAppearanceController` | `SkinSelectionStore` | Persist-before-publish normal selection; direct Native recovery | ✓ WIRED | `select` saves before setting selected fields; `restoreNativeAppearance` publishes static Native without resolving custom content. |
| `CompactPlayerView` | `ValidatedSkinAppearance` | Validated style/inert decoration only | ✓ WIRED | `renderingAppearance` drives bounded style and decorative URLs; action closure and accessibility modifiers remain on native view code. |
| Bundled/imported manifests | `SkinManifestValidator` | Same strict manifest contract | ✓ WIRED | Bundled catalog and importer both call `SkinManifestValidator.validate`; imported assets also pass canonical and ImageIO checks. |
| Management surface | selection/import/removal controllers | Stable reference only | ✓ WIRED | Rows pass `SkinSelectionReference`; selection, import, and removal call their app-owned controllers, never raw manifest dictionaries. |
| Selected imported removal | `ManagedSkinStore` | Persist Native then delete | ✓ WIRED | `SkinAppearanceController.removeImportedSkin` calls `select(.native)` before the injected managed removal closure. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| --- | --- | --- | --- | --- |
| `CompactPlayerView` | `appearance` / `renderingAppearance` | App-lifetime `SkinAppearanceController.selectedAppearance`, populated from validated bundled resources or managed local package | Yes; no static empty prop call site | ✓ FLOWING |
| `SkinManagementView` | `availableAppearances` | Controller catalog: permanent Native + decoded bundled values + managed validated packages | Yes; UI filters the catalog by classification | ✓ FLOWING |
| `SkinPackageImporter` | `ValidatedSkinAppearance` | Staged ZIP entries → manifest validation → managed revalidation after promotion | Yes; candidate values come from real local package data, not a mock/static return | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| --- | --- | --- | --- |
| Metadata-only persistence, rollback, idempotency | `swiftc SkinSelectionStore.swift … && selection-tests` | Five PASS cases | ✓ PASS |
| Two bundled manifest contract | `swift BundledSkinManifestOfflineTests.swift SignalGlow.json TapeDeck.json` | Four PASS checks | ✓ PASS |
| Hostile path/budget policy | `swiftc SkinPackagePolicy.swift … && policy-tests` | `PASS (36 assertions)` | ✓ PASS |
| App-hosted importer/UI/accessibility behavior | Not run | Repository safety policy prohibits app/test host and UI automation pending separate approval | ? SKIP |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| --- | --- | --- | --- | --- |
| ACCS-02 | 04-01, 04-03 | Skins cannot remove semantics, targets, focus/state, or Native fallback | NEEDS HUMAN | Code keeps controls/accessibility app-owned, fixes 400×288 and 32-point transport region, and provides direct recovery; VoiceOver/keyboard/visual runtime proof is deferred. |
| SKIN-01 | 04-01, 04-03 | Select at least two bundled complete tested skins | NEEDS HUMAN | Two validated resources, catalog, menu, and offline manifest check exist; user-visible selection has not run. |
| SKIN-02 | 04-02, 04-03 | Import, validate, select, and remove local declarative packages | NEEDS HUMAN | Import coordinator, managed store, settings UI, and removal ordering are wired; a real package workflow has not run. |
| SKIN-03 | 04-02 | No executable/remote/authority-bearing package behavior | NEEDS HUMAN | Closed manifest and source audit show no prohibited authority surface; pure boundary suite passed, while real hostile archive handling awaits UAT. |
| SKIN-04 | 04-02 | Reject schemas, unsafe paths/types, and all documented budgets | NEEDS HUMAN | Source includes exact structural/budget guards and policy suite passes; full ZIP/ImageIO transaction awaits UAT. |
| SKIN-05 | 04-01, 04-03 | Preserve valid appearance and recover safely | NEEDS HUMAN | Persist-before-publish selection, staged rollback, static Native fallback, and direct menu recovery are wired; runtime recovery walk-through is A-04-13. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| --- | --- | --- | --- | --- |
| `SiriusMac/Skins/SkinPackageImporter.swift` | 175 | `return []` | ℹ️ Info | Safe no-managed-directory result, not rendered placeholder data. |
| `SiriusMac/Player/CompactPlayerView.swift` | 117, 310, 325 | `placeholder` | ℹ️ Info | Existing artwork state / SwiftUI previews, not a phase stub. |

No `TBD`, `FIXME`, or `XXX` debt marker was found in the Phase 4 change set. No blocking code or wiring gap was observed in the static audit.

## Human Verification Required

### 1. Repair the MVP roadmap contract

**Test:** Rewrite Phase 4’s goal as a valid user story and rerun verification.

**Expected:** The canonical validator accepts all role, capability, and outcome slots, enabling a real MVP user-flow coverage table.

**Why human:** The current `Mode: mvp` / non-user-story goal mismatch is a roadmap decision, not a code behavior that source inspection can resolve.

### 2. Appearance lifecycle

**Test:** Use the Player menu and Manage Appearances to select each bundled skin, import/select/remove a valid package, then select Native.

**Expected:** The compact player changes appearance only; the imported item is managed locally and removal leaves Native selected.

**Why human:** The app, UI tests, and app-hosted XCTest are explicitly prohibited until a separate safety review approves the runtime environment.

### 3. Hostile package preservation

**Test:** Try invalid schema, traversal/symlink, remote/authority-style, over-budget, and malformed-image packages after selecting a valid appearance.

**Expected:** Each error is closed and actionable; the confirmed appearance, catalog, and selection remain intact.

**Why human:** Pure policy checks ran, but complete ZIP/ImageIO/storage/UI rollback requires app-runtime exercise.

### 4. Accessible recovery (A-04-13)

**Test:** With a missing or corrupt selected decoration, use keyboard navigation and VoiceOver to reach Player > Use Native Appearance.

**Expected:** Native controls, labels, values, focus/state indicators, and hit regions remain usable; the direct Native command works even without custom package content.

**Why human:** Visual, keyboard, VoiceOver, and final recovery behavior cannot be proven from source or isolated offline tests.

## Gaps Summary

No observable implementation absence, stub, or broken source link was found. The phase cannot pass yet because (1) its MVP designation has no valid user-story goal, and (2) all subscriber-facing lifecycle and accessibility outcomes require the deliberately deferred, separately authorized runtime UAT.

---

_Verified: 2026-08-25T23:07:18Z_
_Verifier: the agent (gsd-verifier)_
