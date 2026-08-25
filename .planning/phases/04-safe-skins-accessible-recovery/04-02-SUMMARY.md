---
phase: 04-safe-skins-accessible-recovery
plan: "02"
subsystem: security
tags: [swift, zipfoundation, imageio, skins, archive-safety, atomic-storage]

requires:
  - phase: 04-safe-skins-accessible-recovery
    provides: Closed appearance validator, catalog, metadata-only selection persistence, and Native recovery from Plan 04-01
provides:
  - Two-pass hostile-input-safe `.siriusskin` import into app-owned managed storage
  - Exact archive, canonical-path, byte, ratio, image, cancellation, and deadline policy
  - Serialized idempotent promotion with rollback backups and generation-guarded selection
affects: [04-safe-skins-accessible-recovery, skin-management, creator-packages, security-review, runtime-uat]

actuals:
  tokens: 24659
  tasks: 3
  commits: 6

tech-stack:
  added: [ZIPFoundation 0.9.20]
  patterns:
    - Pure Foundation-only hostile archive policy separated from ZIP and Image I/O effects
    - Validate in unique same-volume staging, atomically promote, revalidate managed bytes, then select
    - Actor-serialized import transactions with cancellation-safe waiting and selection generations

key-files:
  created:
    - SiriusMac/Skins/SkinPackagePolicy.swift
    - SiriusMac/Skins/SkinPackageImporter.swift
    - SiriusMacTests/SkinPackageImporterTests.swift
    - script/tests/SkinPackagePolicyOfflineTests.swift
  modified:
    - SiriusMac/Skins/SkinAppearance.swift
    - SiriusMac/SiriusMacApp.swift
    - SiriusMac.xcodeproj/project.pbxproj

key-decisions:
  - "Use ZIPFoundation only for bounded ZIP iteration and CRC-checked extraction; Sirius Mac owns every acceptance decision and semantic error."
  - "Keep an independent same-volume rollback copy until the replacement has been revalidated and its canonical digest confirmed."
  - "Insert a valid stale import into the catalog but require current request and main-actor authority generations before selection persistence or publication."
  - "Treat exact deadline equality as expired and every numeric limit as inclusive, using overflow-reporting integer arithmetic throughout."

patterns-established:
  - "Closed import transaction: preflight, fresh staging, streamed accounting, exact manifest/image validation, atomic promotion, managed revalidation, catalog, selection."
  - "Failure preservation: source scope closes in defer, unpromoted staging cleans in defer, failed replacement restores its backup, and selection publishes only after persistence."
  - "Idempotent managed content: identifier plus SHA-256 over canonical path/content avoids duplicate storage and equal-selection writes."

requirements-completed: [SKIN-02, SKIN-03, SKIN-04, SKIN-05]

coverage:
  - id: D1
    description: "One local `.siriusskin` follows the two-pass staged import path and can become a selected managed appearance."
    requirement: SKIN-02
    verification:
      - kind: integration
        ref: "xcodebuild build-for-testing with fresh unique DerivedData; app and tests not launched"
        status: pass
    human_judgment: true
    rationale: "The binding launch-safety policy defers native file-panel, real archive import, rendering, and selection runtime observation."
  - id: D2
    description: "Canonical paths, entry kinds, declared and streamed budgets, image dimensions, cancellation, and the exact deadline fail closed."
    requirement: SKIN-04
    verification:
      - kind: unit
        ref: "script/tests/SkinPackagePolicyOfflineTests.swift — 36 assertions"
        status: pass
      - kind: integration
        ref: "compiled SkinPackageImporterTests transport/image/rollback contracts"
        status: pass
    human_judgment: false
  - id: D3
    description: "Imported rendering resolves only validated app-owned managed package assets after source access has ended."
    requirement: SKIN-03
    verification:
      - kind: other
        ref: "targeted four-boundary source security review recorded below"
        status: pass
    human_judgment: true
    rationale: "Runtime asset rendering and attempted post-import source mutation were not observed under the launch restriction."
  - id: D4
    description: "Imports serialize; cancellation before the queue front creates no staging; equal content is idempotent; changed content retains rollback; stale generations cannot publish."
    requirement: SKIN-05
    verification:
      - kind: integration
        ref: "compiled SkinPackageImporterTests cancellation, rollback, unique staging, persistence-failure, and stale-generation contracts"
        status: pass
      - kind: integration
        ref: "xcodebuild build-for-testing with fresh unique DerivedData"
        status: pass
    human_judgment: true
    rationale: "Concurrency and injected app-host transaction tests were compiled but intentionally not executed; runtime forcing remains deferred."

duration: 44min
completed: 2026-08-25
status: complete
---

# Phase 04 Plan 02: Safe Local Skin Import Summary

**Hostile `.siriusskin` archives now cross a closed, resource-bounded two-pass pipeline into atomically managed app-owned appearances with rollback and selection-generation protection.**

## Performance

- **Duration:** 44 min
- **Started:** 2026-08-25T17:45:00-04:00
- **Completed:** 2026-08-25T18:29:08-04:00
- **Tasks:** 3
- **Files modified:** 8, including this summary

## Accomplishments

- Added a native Player > Appearance import flow for exactly one `.siriusskin`, with source security scope closed on every exit and semantic result copy that exposes no paths or archive content.
- Added exact preflight and streamed enforcement for entry kinds, canonical paths/collisions, archive and expansion budgets, compression ratios, manifest size/schema/references, PNG/JPEG frame/type/dimensions, cancellation, and the 10-second cooperative deadline.
- Added app-owned UUID staging, deterministic SHA-256 identity, equal-content idempotency, same-volume replacement with retained rollback source, managed-byte revalidation, serialized transactions, and generation-guarded selection.
- Added 36 runnable offline boundary assertions plus compiled app-layer contracts for managed roots, catalog replacement, persistence failure, cancellation-before-transport, unique staging, rollback, and stale selection authority.

## Task Commits

Each task was committed atomically; TDD tasks have separate RED and GREEN commits:

1. **Task 04-02-01: Import one valid local package into managed storage and select it** - `b788347`
2. **Task 04-02-02 RED: Define hostile package boundaries** - `1f3fd81`
3. **Task 04-02-02 GREEN: Enforce hostile package boundaries** - `799c994`
4. **Task 04-02-03 RED: Define atomic import transaction contracts** - `41da7ee`
5. **Task 04-02-03 GREEN: Serialize atomic skin imports** - `616ade4`

**Plan metadata:** committed with this summary.

## Files Created/Modified

- `SiriusMac/Skins/SkinPackagePolicy.swift` - Foundation-only limits, path canonicalization, preflight decisions, streamed counters, image math, and deadline/cancellation policy.
- `SiriusMac/Skins/SkinPackageImporter.swift` - ZIP transport, bounded envelope inspection, staged extraction, manifest/Image I/O validation, digesting, managed promotion/rollback, and serialized coordination.
- `SiriusMac/Skins/SkinAppearance.swift` - Imported catalog registration and main-actor request/authority generation checks around persistence and publication.
- `SiriusMac/SiriusMacApp.swift` - App-lifetime managed store/importer/coordinator and closed native import UI.
- `SiriusMacTests/SkinPackageImporterTests.swift` - Compiled transaction, cancellation, rollback, persistence, managed-root, and generation contracts.
- `script/tests/SkinPackagePolicyOfflineTests.swift` - Runnable 36-assertion boundary, precision, collision, overflow, byte-accounting, cancellation, and deadline matrix.
- `SiriusMac.xcodeproj/project.pbxproj` - Exact ZIPFoundation 0.9.20 app-only linkage and source/test membership.

## Decisions Made

- Archive metadata is rejected before extraction; only accepted regular files emit through CRC-checked ZIPFoundation chunk consumers into fresh contained destinations.
- A bounded central-directory envelope inspection detects encrypted records that ZIPFoundation 0.9.20 omits from its public entry sequence; ZIPFoundation remains the only ZIP decoder/extractor.
- Replacements keep an independent backup until the promoted package passes a second strict validation and canonical-content digest comparison. Any failure before commit restores the prior managed directory.
- Waiting transactions allocate no staging. A cancelled waiter is removed from the actor queue, and only a request that is still current reserves main-actor selection authority.
- Equal identifier/digest imports reuse the existing managed package. Equal selected references update the validated appearance value without a redundant persistence write.

## Private Helper Inventory

The plan-authorized private helpers added during execution are:

- `SkinExtractionBudget` for transaction-local actual emitted-byte accounting.
- `ZIPCentralDirectorySummary` and `ZIPCentralDirectoryInspector` for bounded EOCD/central-record encryption and count checks before ZIPFoundation iteration.
- `ManagedSkinStore.PromotionTransaction`, `restoreBackupIfPresent`, and direct-child checks for commit/rollback ownership.
- `SkinImportCoordinator.ImportOperation` plus its private continuation queue for deterministic transport substitution and cancellation-safe serialization.
- `SynchronousImportProbe` in the compiled test file for cancellation-before-transport verification.

## Flagged Assumption Results

- **A-04-07 — Passed by implementation/compile evidence:** equal identifier/digest removes staging and returns the existing managed URL; changed content uses replacement plus rollback. Runtime re-import observation is deferred.
- **A-04-08 — Passed by implementation/compile evidence:** the actor serializes transactions, UUID roots are distinct, cancelled waiters never call the import operation, and selection requires current generations. Runtime overlap forcing is deferred.
- **A-04-09 — Passed by source review:** the renderer receives only `ValidatedSkinAppearance` values whose optional assets resolve beneath an app-owned managed package; archive, staging, and source URLs never enter the renderer contract.
- **A-04-10 — Passed:** every maximum is inclusive; the exact 10,000,000,000-nanosecond deadline rejects because work must finish before it.
- **A-04-11 — Passed:** totals, ratios, pixels, and elapsed time use checked integer operations; zero-compressed nonempty entries and arithmetic overflow reject.
- **A-04-12 — Passed by source review:** counters, clocks, handles, digests, staging roots, and backups are transaction-local; the actor owns promotion/catalog ordering.

## Targeted Four-Boundary Security Review

1. **Local source archive -> ZIP transport/policy: PASS.** Source must be a lowercase `.siriusskin` regular non-symlink file within 16 MiB. The bounded central-directory check rejects encryption, split/ZIP64 envelopes, malformed counts, and trailing mismatch; the closed preflight rejects entry types, unsafe/colliding paths, declared sizes, ratios, and overflow before extraction. Source security scope is paired in `defer` on success, rejection, cancellation, and storage failure.
2. **Extracted candidate -> manifest/Image I/O validation: PASS.** Only accepted regular entries write through explicit file handles with CRC enabled and actual per-file/aggregate counters. Root `manifest.json` is exact-key decoded; every local canonical asset reference must exist beneath staging, every extracted non-manifest file must be referenced, and Image I/O must report one PNG/JPEG frame within checked dimensions/pixels.
3. **Staging -> managed package store: PASS.** Staging is a unique direct child on the managed volume and is removed on every unpromoted exit. Equal digest discards staging. Replacement first preserves the old package, uses `replaceItemAt`, revalidates the installed package and recomputes its digest, then deletes the backup only at commit; validation or commit failure rolls back.
4. **Managed package -> selected renderer: PASS.** The source scope has ended before coordinator selection. Catalog insertion accepts only imported `ValidatedSkinAppearance`; stale/cancelled generations may leave a valid managed entry available but cannot persist or publish it. Durable selection stores only identifier/classification metadata, while rendering sees no ZIP transport, manifest bytes, source URL, network, authentication, playback, scripting, or arbitrary-file collaborator.

Source scans additionally confirmed ZIPFoundation is imported only by `SkinPackageImporter.swift` and linked only to the app target; the policy, appearance controller, renderer, and persistence layer do not import it.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added bounded encrypted-entry visibility check**

- **Found during:** Task 04-02-02
- **Issue:** ZIPFoundation 0.9.20 does not expose its encryption flag and omits encrypted records from the public entry sequence, which could make a closed preflight miss them.
- **Fix:** Added a bounded EOCD/central-directory envelope inspector that rejects encryption and verifies the public-entry count before ZIPFoundation extraction.
- **Files modified:** `SiriusMac/Skins/SkinPackageImporter.swift`
- **Verification:** App/test compilation passed; source review confirmed ZIP mechanics remain with ZIPFoundation.
- **Committed in:** `799c994`

**2. [Rule 2 - Missing Critical] Retained an independent rollback source through managed revalidation**

- **Found during:** Task 04-02-03 security review
- **Issue:** Removing a replacement backup immediately after `replaceItemAt` could lose prior managed content if post-promotion revalidation failed.
- **Fix:** Copy the prior managed directory to a unique same-volume backup first, retain it through managed validation/digest confirmation, and restore it on every non-commit exit.
- **Files modified:** `SiriusMac/Skins/SkinPackageImporter.swift`
- **Verification:** Compiled rollback contract plus final build-for-testing passed; boundary source review traced prepare/commit/rollback exits.
- **Committed in:** `616ade4`

---

**Total deviations:** 2 auto-fixed missing-critical security issues.
**Impact on plan:** Both changes close required threat-model gaps without expanding product authority or modifying files outside the plan scope.

## Issues Encountered

- `build-for-testing` creates an untracked workspace `Package.resolved`; each generated copy was removed before staging because that path is outside this plan's ownership.
- The Task 04-02-03 RED build failed on the deliberately missing generation APIs. Two GREEN compile passes then exposed an inferred continuation type and async XCTest autoclosure usage; both were corrected before the passing final compile-only gate.
- Build-only output includes signed XCTest/UI-test runner assembly because the shared scheme contains those targets. No runner, test bundle, app host, UI automation, or application was executed.

## Verification

- Offline policy executable: **PASS**, 36 assertions from a fresh `mktemp` executable path.
- Task 04-02-01 `xcodebuild build-for-testing`: **PASS**, fresh unique DerivedData; no app/test launched.
- Task 04-02-02 `xcodebuild build-for-testing`: **PASS**, fresh unique DerivedData; no app/test launched.
- Task 04-02-03 final `xcodebuild build-for-testing`: **PASS**, `/tmp/sirius-mac-04-02-final.NYw1ke`; no app/test launched.
- Targeted four-boundary source security review: **PASS**.
- ZIPFoundation isolation and exact 0.9.20 app-only project linkage scan: **PASS**.
- `git diff --check`: **PASS**.

## Explicit Runtime UAT Deferrals

The launch-safety policy prohibited every runtime app/test lane. The following remain explicitly **NOT OBSERVED** and must be exercised only after a separately authorized safety review:

- Native `NSOpenPanel` filtering, success/failure alerts, and keyboard/VoiceOver behavior.
- End-to-end import and rendering of a real valid `.siriusskin` from a security-scoped location.
- Runtime hostile ZIP/Image I/O fixtures, active and waiting cancellation, two overlapping imports, equal/different-content re-import, and injected promotion/selection-persistence failures.
- Relaunch restoration of an imported managed appearance and visual rendering after source removal/mutation.
- App-hosted XCTest and all UI automation. No live SiriusXM, authentication, catalog, tune, playback, or telemetry operation was attempted.

## User Setup Required

None - no external service configuration is required.

## Next Phase Readiness

The managed import lifecycle is ready for subsequent imported-skin management/removal work. Runtime UAT remains intentionally deferred and is not evidence claimed by this plan.

## Self-Check: PASSED

- All seven declared implementation/test paths and this summary are present in the committed plan diff.
- Five atomic task commits plus this summary commit are present; hooks ran for every commit.
- `.planning/STATE.md` and `.planning/ROADMAP.md` are unchanged.
- No out-of-scope file remains modified or untracked.
- No prohibited test runner, app/test host, UI automation, application launch, build-and-run script, or live SiriusXM operation was used.

---
*Phase: 04-safe-skins-accessible-recovery*
*Completed: 2026-08-25*
