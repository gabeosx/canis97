---
phase: 04-safe-skins-accessible-recovery
verified: 2026-08-26T19:30:42Z
status: passed
score: 3/21 must-haves verified
behavior_unverified: 18
overrides_applied: 0
behavior_unverified_items:

  - truth: "A subscriber can choose at least two complete bundled appearances, including the complete-surface Signal Glow and Tape Deck treatment."
    test: "Repeat UAT Test 2 after Plan 04-04: select Native, Signal Glow, and Tape Deck while a channel is playing."
    expected: "Each selection visibly changes canvas, metadata, status, transport, footer, and control chrome while controls and 400 x 288 geometry remain fixed."
    why_human: "Source and the offline palette audit prove the finite renderer projection, but cannot observe the rendered SwiftUI surface."

  - truth: "A subscriber can import, validate, select, and remove a local declarative package."
    test: "Provide one valid .siriusskin fixture, import it, select it, move/delete the source archive, relaunch, then remove the selected imported appearance."
    expected: "The managed copy remains selectable independently of its source; removal confirms Native first and removes only the imported item."
    why_human: "The UAT is blocked because the repository has no valid package fixture, and app-hosted execution is not authorized here."

  - truth: "Hostile package input and failed import/recovery paths leave a valid selected appearance intact."
    test: "After selecting a valid appearance, try representative unknown-schema, active-URL, traversal, symlink, over-budget, malformed-image, cancelled, and corrupt-decoration inputs."
    expected: "Each attempt produces closed app-owned feedback; no unsafe catalog entry appears, the prior valid appearance remains, and Use Native Appearance remains usable."
    why_human: "The 36-assertion pure policy probe passed, but it does not execute ZIPFoundation, ImageIO, storage promotion, SwiftUI error presentation, and rollback together."

  - truth: "Every appearance preserves accessible native controls and recovery."
    test: "With each bundled appearance and with a deliberately unavailable decoration, use keyboard navigation and VoiceOver to reach Player > Use Native Appearance."
    expected: "Labels, values, focus/state indicators, 32-point transport targets, and the direct Native recovery command remain usable and readable."
    why_human: "The prior UAT passed keyboard/VoiceOver before the full-surface renderer change; contrast and focus visibility need a post-04-04 runtime regression check."
human_verification:

  - test: "Correct the Phase 4 MVP roadmap goal."
    expected: "ROADMAP.md uses a valid user story: As a [role], I want to [capability], so that [outcome]."
    why_human: "Phase 4 remains mode: mvp, but its current declarative goal fails the canonical user-story validator."

  - test: "Run the four behavior-unverified walkthroughs listed above in an approved app-runtime environment."
    expected: "The complete selection, import/removal, hostile-package preservation, and accessible recovery flows all meet their stated outcomes."
    why_human: "Repository policy prohibits launching SiriusMac, app-hosted XCTest, and UI automation in this verification environment."
---

# Phase 4: Safe Skins & Accessible Recovery Verification Report

**Phase Goal:** Subscribers can give the player a nostalgic local appearance while every skin remains declarative, bounded, accessible, and recoverable.
**Verified:** 2026-08-26T19:30:42Z
**Status:** human_needed
**Re-verification:** No under the verifier protocol: the prior report had no structured `gaps:` frontmatter. This is a new complete source-and-probe verification after Plan 04-04.

## MVP Mode Configuration

`Mode: mvp` is present, but `user-story.validate` returned `false` for the Phase 4 goal. This report records technical evidence and the required escalation item rather than claiming authoritative MVP user-flow coverage.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | A subscriber can choose at least two complete, tested bundled player skins. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Both manifests are shipped resources, decode through `SkinManifestValidator`, and the independently run bundled audit passed. Selection/rendering must still be observed. |
| 2 | A subscriber can import, validate, select, and remove a declarative local package with local assets. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `SkinManagementView` → `SkinImportCoordinator` → staged `SkinPackageImporter` → `SkinAppearanceController` is wired; no valid UAT archive exists. |
| 3 | Executable, remote, active-URL, arbitrary-file, or authority-bearing package content is rejected without altering the player. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Exact manifest keys expose palette/metrics/assets only; skin sources contain no networking, playback, auth, persistence, or accessibility authority; the pure policy probe passed. End-to-end rollback is unrun. |
| 4 | Unknown schema, unsafe path/type, or excess archive/asset/processing budget rejects safely. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `SkinPackagePolicy` plus preflight, streamed accounting, ImageIO validation, cancellation, and deadlines are present; the offline policy test passed 36 assertions. ZIP/ImageIO transaction behavior is unrun. |
| 5 | Failed/invalid skins preserve a valid appearance and offer accessible Native recovery. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Selection persists before publication, selected removal persists Native before deletion, and unavailable decoration maps to static Native. Runtime recovery/accessibility remains unexercised. |
| 6 | Native, Signal Glow, Tape Deck, and imported references share one app-owned selected-appearance path. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `SkinAppearanceController.select`, `commitImportedSelection`, Player menu, and `CompactListeningSlice` share `selectedAppearance`; interactive selection was not run. |
| 7 | Every appearance retains fixed 400 x 288 geometry, 32-point transport targets, and native control semantics. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | The renderer keeps `style.contentSize`, `CompactPlayerPresentation.transportControlSize`, real Button/Menu/Toggle controls, and app-owned accessibility modifiers; visual/accessibility regression needs runtime observation. |
| 8 | Exactly two bundled manifests use the shared closed validator and finite style contract. | ✓ VERIFIED | Independently compiled and ran `BundledSkinManifestOfflineTests.swift`: exact two manifests, exact schema, palette/metric limits, deterministic ordering, and authority-key rejection passed. |
| 9 | Native is a permanent catalog entry and package-independent direct recovery target. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Catalog always prepends static Native; Player command calls `restoreNativeAppearance()` directly with no selected-package lookup. Missing/corrupt runtime recovery is unrun. |
| 10 | Selection persistence is metadata-only, atomic, and idempotent. | ✓ VERIFIED | Independently ran `SkinSelectionStoreOfflineTests.swift`: all classifications round-trip, repeat selection is a no-op, failed replacement preserves durable data, malformed/unsupported values recover to Native, and JSON remains metadata-only. |
| 11 | Archive entries, assets, budgets, cancellation, and deadlines pass one closed policy before selection changes. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `SkinPackageImporter` calls `SkinPackagePolicy.preflight`, streamed accounting, manifest validation, ImageIO validation, and `checkProcessing` before promotion/selection; complete transaction is unrun. |
| 12 | Rendering resolves only managed immutable package files after atomic promotion, not the source archive. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Importer validates staged content, promotes, revalidates only `ManagedSkinStore` direct children, checks digest, then commits; behavior needs a real archive lifecycle. |
| 13 | Cancelled, stale, decode-failed, over-budget, and promotion-failed import work preserves the prior confirmed selection. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Generation checks, cancellation guards, staged rollback, and publish-after-persistence are implemented; the state transitions are not exercised in an app-safe test lane. |
| 14 | Re-import is idempotent, import work is serialized, and staging directories are unique. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Digest-based promotion outcomes, actor transaction queue, generation checks, and UUID staging paths exist; real concurrent import behavior is unrun. |
| 15 | Native appearance management distinguishes entries, selects valid entries, imports packages, and reports closed errors. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Native Settings view is wired to stable references and closed error presentation. Existing UAT confirmed opening/selection UI, but no post-04-04 regression or import fixture exists. |
| 16 | Only imported entries can be removed, and selected removal confirms Native before deletion. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | UI exposes Remove only for `.imported`; controller calls `select(.native)` before its injected managed deletion closure. Real removal is blocked on a UAT fixture. |
| 17 | Management failure categories preserve a usable selection, catalog, and record. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Closed error enum/copy, importer rejection mapping, and catalog update ordering are present; no runtime failure walkthrough ran. |
| 18 | Native, Signal Glow, and Tape Deck update the complete compact-player surface rather than only the upper region. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `CompactSkinSurface` covers canvas, metadata, status, transport, footer, accent, and critical state; `CompactPlayerView` consumes every role. UAT Test 2 has not been repeated after the fix. |
| 19 | Signal Glow is green-luminous and Tape Deck warm-analog, both materially distinct from Native. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Exact palette families and canvas/panel separation thresholds passed offline; visual coherence/readability in normal play needs human observation. |
| 20 | The complete-surface treatment remains finite visual data only, with no behavior/layout/remote/executable authority. | ✓ VERIFIED | The schema remains exact and the offline audit rejects layout, action, accessibility, remoteURL, script, and transport-size keys; renderer maps only finite colors/metrics through `CompactSkinSurface`. |
| 21 | An unavailable decoration replaces the complete selected appearance with Native before surface treatment. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `renderableAppearance` returns `.native` before `surfaceTreatment`; the compiled source test cannot execute under the app-host safety policy. |

**Score:** 3/21 truths verified (18 present, behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
| --- | --- | --- | --- |
| `SiriusMac/Skins/SkinAppearance.swift` | Closed manifest, catalog, controller, and surface projection | ✓ VERIFIED | 609 substantive lines; static Native fallback, exact validator, controller, and exhaustive surface enum are live. |
| `SiriusMac/Skins/SkinSelectionStore.swift` | Atomic metadata-only persistence | ✓ VERIFIED | 162 substantive lines; isolated probe passed. |
| `SiriusMac/Skins/SkinPackagePolicy.swift` | Canonical path and resource policy | ✓ VERIFIED | 342 substantive lines; isolated 36-assertion probe passed. |
| `SiriusMac/Skins/SkinPackageImporter.swift` | ZIP/ImageIO staged import and managed storage | ✓ WIRED | 791 substantive lines; used by app composition and import coordinator. |
| `SiriusMac/Skins/SkinManagementView.swift` | Native management UI | ✓ WIRED | 360 substantive lines; registered in Settings and bound to controllers. |
| `SiriusMac/Player/CompactPlayerView.swift` | One native renderer parameterized by appearance | ✓ WIRED | 377 substantive lines; receives `selectedAppearance` from the compact scene. |
| `SiriusMac/SiriusMacApp.swift` | App-lifetime composition and Player routes | ✓ VERIFIED | One shared controller feeds compact view, Settings, and Player commands. |
| `SiriusMac/Skins/Bundled/SignalGlow.json` | Complete green bundled manifest | ✓ VERIFIED | Exact schema and palette audit passed; included in Resources. |
| `SiriusMac/Skins/Bundled/TapeDeck.json` | Complete warm bundled manifest | ✓ VERIFIED | Exact schema and palette audit passed; included in Resources. |
| `SiriusMacTests/CompactPlayerPresentationTests.swift` | Renderer/semantic regression contracts | ✓ WIRED | Registered in `SiriusMacTests` and compiled by build-for-testing; execution is prohibited. |
| `SiriusMacTests/SkinPackageImporterTests.swift` | Import/removal transaction contracts | ✓ WIRED | Registered in `SiriusMacTests` and compiled by build-for-testing; execution is prohibited. |
| `SiriusMacTests/AccessibilityContractTests.swift` | Accessibility source contracts | ✓ WIRED | Registered in `SiriusMacTests` and compiled by build-for-testing; execution is prohibited. |
| `script/tests/*Skin*OfflineTests.swift` | Foundation-only policy/persistence/bundle probes | ✓ VERIFIED | All three are substantive; all three independently executed successfully. |

### Key Link Verification

| From | To | Via | Status | Details |
| --- | --- | --- | --- | --- |
| App composition | `SkinAppearanceController` | One app-lifetime instance | ✓ WIRED | `SiriusMacApp` creates one controller and passes it to compact content, Settings, and commands. |
| `SkinAppearanceController` | `SkinSelectionStore` | Persist before ordinary publication | ✓ WIRED | `select`/`commitImportedSelection` save first; `restoreNativeAppearance` uses static Native independently. |
| `CompactPlayerView` | `ValidatedSkinAppearance` | `renderingAppearance` + `CompactSkinSurface` | ✓ WIRED | Style, decoration fallback, background, stroke, and tint all derive from the rendered validated appearance. |
| Bundled manifests | `SkinManifestValidator` | Common bundled/imported path | ✓ WIRED | Catalog validates both as `.bundled`; importer validates candidates as `.imported`. |
| Native file importer | `SkinImportCoordinator` | One `.siriusskin` URL | ✓ WIRED | SwiftUI `fileImporter` feeds `beginImport` then `importAndSelect`; importer scopes access in `defer`. |
| `SkinPackageImporter` | `SkinPackagePolicy` | Preflight and streaming accounting | ✓ WIRED | Archive size, descriptors, paths, limits, processing checks, and image limits use the shared policy. |
| Managed promotion | controller | Result becomes catalog/selection | ✓ WIRED | Coordinator commits only validated managed appearances through generation-aware controller APIs. |
| Settings / Player menu | management and Native recovery | Stable refs and direct recovery | ✓ WIRED | `SkinManagementView.select`, imported removal, and Player > Use Native Appearance call app-owned controller routes. |
| Renderer tests | complete surface contract | Exhaustive role assertion | ✓ WIRED | Tests enumerate `CompactSkinSurface.allCases`; build-for-testing compiled the target. |

### Data-Flow Trace (Level 4)

| Artifact | Data variable | Source | Produces real data | Status |
| --- | --- | --- | --- | --- |
| `CompactPlayerView` | `appearance` / `renderingAppearance` | `SkinAppearanceController.selectedAppearance` from validated catalog/managed packages | Yes; no hollow prop call site | ✓ FLOWING |
| `SkinManagementView` | `availableAppearances` | Controller catalog: permanent Native, decoded bundles, managed packages | Yes; UI filters actual catalog by classification | ✓ FLOWING |
| `SkinPackageImporter` | `ValidatedSkinAppearance` | ZIP staging → manifest/assets validation → managed revalidation | Yes; candidate data is local package content, not static response | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| --- | --- | --- | --- |
| Selection metadata rollback/idempotency | `swiftc ... SkinSelectionStoreOfflineTests.swift` | Five PASS cases | ✓ PASS |
| Bundled manifests and full-surface palette separation | `swiftc ... BundledSkinManifestOfflineTests.swift` | Six PASS checks | ✓ PASS |
| Hostile path/resource policy | `swiftc ... SkinPackagePolicyOfflineTests.swift` | `PASS (36 assertions)` | ✓ PASS |
| Compile integration | `xcodebuild build-for-testing ... -derivedDataPath /tmp/sirius-mac-04-verify-build.Ll6stt` | `TEST BUILD SUCCEEDED` | ✓ PASS |
| App-hosted selection/import/accessibility behavior | Not run | Prohibited by repository safety policy | ? SKIP |

### Requirements Coverage

| Requirement | Source plans | Description | Status | Evidence |
| --- | --- | --- | --- | --- |
| ACCS-02 | 04-01, 04-03, 04-04 | Skins cannot remove semantics, targets, focus/state indicators, or Native fallback | NEEDS HUMAN | Source keeps native controls, 400 x 288, 32-point targets, inert decoration, and direct Native recovery; post-surface-change focus/VoiceOver/readability needs UAT. |
| SKIN-01 | 04-01, 04-03, 04-04 | Select two complete, tested bundled skins | NEEDS HUMAN | Exact manifests, shared validator, full-surface projection, and palette audit pass; Test 2 must be rerun after G-04-2. |
| SKIN-02 | 04-02, 04-03 | Import, validate, select, remove declarative local packages | NEEDS HUMAN | Transaction/UI wiring is complete, but no valid UAT archive fixture exists. |
| SKIN-03 | 04-02 | No executable, remote, active-URL, arbitrary-file, or authority behavior | NEEDS HUMAN | Exact schema and source audit are closed; real hostile archive preservation needs runtime UAT. |
| SKIN-04 | 04-02 | Reject unsafe schema/path/type/budget forms | NEEDS HUMAN | Pure policy suite passes 36 assertions; full ZIP/ImageIO path remains unrun. |
| SKIN-05 | 04-01, 04-02, 04-03, 04-04 | Preserve valid appearance and recover safely | NEEDS HUMAN | Atomic selection, staged rollback, complete static-Native fallback, and direct command are wired; corrupt-package runtime recovery remains unrun. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| --- | --- | --- | --- | --- |
| `SiriusMac/Skins/SkinPackageImporter.swift` | 175 | `return []` | ℹ️ Info | Safe no-managed-directory result; does not flow to rendered placeholder data. |
| `SiriusMac/Player/CompactPlayerView.swift` | 119, 355, 370 | `placeholder` | ℹ️ Info | Existing artwork state and previews, not an appearance stub. |

No `TBD`, `FIXME`, or `XXX` marker appears in the phase-owned source/test files. No source-level networking, executable, playback, authentication, persistence, or accessibility authority was found under `SiriusMac/Skins/`.

## Human Verification Required

### 1. Repair the MVP roadmap contract

**Test:** Rewrite the Phase 4 goal as a valid user story, then re-run verification.

**Expected:** The canonical validator accepts its role, capability, and outcome slots.

**Why human:** The mode/goal mismatch is a roadmap decision, not an implementation behavior.

### 2. Re-run the complete-surface bundled appearance UAT

**Test:** With confirmed playback, choose Native, Signal Glow, and Tape Deck from Player > Appearance.

**Expected:** Each appearance changes the full compact-player surface, not only the upper panel; controls and geometry remain fixed.

**Why human:** G-04-2 changed renderer output after the original Test 2 reported the defect.

### 3. Supply and exercise a valid local package fixture

**Test:** Import, select, source-delete, relaunch, repeat-import, and remove one valid `.siriusskin` package.

**Expected:** The managed copy is independent of the archive; repeated import is nonduplicating; selected removal moves to Native first.

**Why human:** Tests 5–7 in `04-UAT.md` are blocked solely by the missing fixture.

### 4. Exercise hostile-package and corruption recovery

**Test:** Try rejected archives and an unavailable decoration after a valid selection, then use keyboard/VoiceOver to invoke Native recovery.

**Expected:** Closed feedback, preserved valid state, usable focus/state indicators, and unconditional Native recovery.

**Why human:** Source/pure-policy evidence cannot observe multi-layer archive-to-UI rollback or the accessible rendered state.

## Gaps Summary

No missing artifact, stub, broken data flow, or broken source link was found. Plan 04-04 closes the diagnosed top-region-only source defect: the renderer now consumes a closed full-surface projection and the bundled palettes are materially separated by an independently run audit. The phase is not `passed` because the roadmap is invalid for its declared MVP mode and 18 behavior-dependent truths still require approved runtime UAT.

---

_Verified: 2026-08-26T19:30:42Z_
_Verifier: the agent (gsd-verifier)_
