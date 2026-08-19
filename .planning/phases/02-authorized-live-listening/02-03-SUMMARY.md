---
phase: 02-authorized-live-listening
plan: "03"
subsystem: siriusxm-client-live-compatibility
tags: [swift, swiftpm, avfoundation, compatibility-contract, offline-tests]
requires:
  - "02-02 supported live-contract gate"
provides:
  - "Exact non-sensitive Phase 02 operation mappings"
  - "Fail-closed playback-key preflight and opaque Apple media handoff SPI"
  - "Deterministic offline live-contract regression coverage"
affects:
  - "02-04 catalog implementation"
  - "02-05 AVFoundation validation"
  - "02-07 metadata presentation"
tech-stack:
  added: [AVFoundation SPI handoff]
  patterns: [fixed internal request contracts, non-materializable live scaffolding, strict preflight, invented fixtures]
key-files:
  created:
    - Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift
  modified:
    - .planning/phases/02-authorized-live-listening/02-LIVE-CONTRACT.md
    - Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/SiriusXMRequestContract.swift
    - Packages/SiriusXMClient/Sources/SiriusXMClient/Public/LiveListeningModels.swift
    - Packages/SiriusXMClient/Tests/SiriusXMClientTests/LiveCatalogAdapterTests.swift
decisions:
  - "Phase 02 supports only fixed semantic mappings; no live operation is materializable until a later capability plan supplies validated opaque inputs."
  - "Use an SPI-scoped AVPlayerItem factory handoff without exposing resource, key, header, or URL material; AVFoundation behavior remains unobserved until 02-05."
metrics:
  duration: "6 min"
  completed: "2026-08-19"
status: complete
actuals:
  tokens: 7154
  tasks: 2
  commits: 4
---

# Phase 02 Plan 03: Fixed Live Compatibility Contracts Summary

Approved first-party operation mappings, an opaque Apple media handoff SPI, and offline contract tests now contain Phase 02 provider volatility without making provider traffic or claiming AVFoundation playback.

## Tasks Completed

1. **Resolve the three research questions and encode only supported fixed contracts**
   - Recorded the approved method, host, and path/template mapping in the canonical contract and coverage matrix.
   - Added individually named internal operation cases and a strict playback-key classifier that preflights transport, redirects, status, content type, and protected controls.
   - Selected `SiriusXMAppleMediaHandoff` as an SPI-only `AVPlayerItem` seam while documenting that native playback remains unobserved until Plan 02-05.
   - Commits: `ae91b0a` (RED), `8471876` (GREEN).

2. **Lock the supported contracts with invented deterministic fixtures**
   - Added synthetic fixed-semantics, preflight, offline-scaffolding, and independent-metadata coverage across all three Wave 0 live suites.
   - Verified unsupported Phase 02 mappings cannot make a transport request and that no resource, key, or live-provider fixture is retained.
   - Commits: `8ad379e` (RED), `a0ab3d7` (GREEN).

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SiriusXMClient` — passed (51 tests).
- Static contract scan confirms the `SUPPORTED` gate, all approved fixed mappings, the SPI handoff, and explicit `AVFoundation: NOT OBSERVED` status.
- Changed fixture suites contain no URL, credential, session, resource, or provider-response material; all values are fixed synthetic labels or documented semantic constants.
- No live provider request, browser/DOM operation, credential/session read, response capture, or playback attempt was made.

## Decisions Made

- Keep all Phase 02 live operations as fixed, non-materializable compatibility scaffolding until later capability plans possess validated opaque inputs; this prevents accidental provider traffic from the contract layer.
- Keep the media delivery host as an opaque handoff fact only. The ordinary public API cannot return, encode, persist, render, or log resource, header, or key material.
- Keep AVFoundation outcome claims deferred to Plan 02-05.

## Deviations from Plan

### Auto-fixed Issues

1. **[Rule 3 - Blocking compatibility guard] Preserved the Phase 01 transport allowlist after introducing non-materializable Phase 02 cases**
   - **Found during:** Task 1 verification
   - **Issue:** `DirectHostPolicy` still expected every request-contract case to be a concrete, body-free transport request.
   - **Fix:** Restricted the existing transport policy and its test to the settled materializable Phase 01 operations; Phase 02 mappings now fail closed before request construction.
   - **Files modified:** `DirectHostPolicy.swift`, `EphemeralSessionTests.swift`
   - **Verification:** Full Swift package suite passed.
   - **Commit:** `8471876`

**Total deviations:** 1 auto-fixed (Rule 3).

## TDD Gate Compliance

- RED: `ae91b0a`, `8ad379e`
- GREEN: `8471876`, `a0ab3d7`

## Issues Encountered

- The sandbox could not run SwiftPM's manifest compiler because its nested sandbox/cache setup is unavailable. The same local, offline package test passed when run with the required execution permission; no source workaround or network access was used.

## Self-Check: PASSED

- Required artifacts exist on disk.
- All four TDD task commits exist in git history.
