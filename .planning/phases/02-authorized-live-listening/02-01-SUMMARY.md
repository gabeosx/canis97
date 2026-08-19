---
phase: 02-authorized-live-listening
plan: "01"
subsystem: authorized-live-listening
tags: [swift, swift-testing, xctest, state-machines, offline-contracts]
status: complete
dependency_graph:
  requires: [phase-01-authentication-and-entitlement]
  provides: [wave-0-listening-contracts, provider-neutral-listening-shell]
  affects: [02-02-live-provider-checkpoint, 02-03-media-handoff, 02-04-catalog]
tech_stack:
  added: [Swift Testing, XCTest, Swift actors, Observation]
  patterns: [semantic-only collaborators, generation-based stale completion rejection, bounded recovery]
key_files:
  created:
    - Packages/SiriusXMClient/Tests/SiriusXMClientTests/LiveCatalogAdapterTests.swift
    - Packages/SiriusXMClient/Tests/SiriusXMClientTests/LivePlaybackCoordinatorTests.swift
    - Packages/SiriusXMClient/Tests/SiriusXMClientTests/MetadataRefreshCoordinatorTests.swift
    - SiriusMac/Metadata/MetadataPresentationModel.swift
  modified:
    - Packages/SiriusXMClient/Sources/SiriusXMClient/Public/LiveListeningModels.swift
    - SiriusMac/Catalog/ListeningPresentationModel.swift
    - SiriusMac/Listening/PlaybackCoordinator.swift
    - SiriusMacTests/ListeningCompositionTests.swift
    - SiriusMac.xcodeproj/project.pbxproj
decisions:
  - "Keep Wave 0 semantic and provider-neutral: invented catalog candidates and collaborator outcomes never represent provider wire data."
  - "Treat catalog snapshots as browse-only; current authorization remains a separate collaborator confirmation."
  - "Use generation checks and finite retry budgets so superseded or cancelled work cannot publish stale playback or metadata state."
metrics:
  duration: 23m
  completed_date: 2026-08-18
actuals:
  tokens: 13070
  tasks: 2
  commits: 4
---

# Phase 02 Plan 01: Deterministic Wave 0 Summary

Provider-neutral catalog, playback, and metadata state machines with deterministic offline contract suites and no live content capability.

## Accomplishments

- Added the four required Wave 0 suites covering CAT-01 through CAT-03, PLAY-01 through PLAY-04, and META-01 through META-02 using invented values and fake collaborators only.
- Kept stale catalog snapshots browsable but explicitly unable to authorize playback; confirmed collaborator outcomes are the only state-publication path.
- Added a bounded, cancellation-aware recovery state machine that retains the selected identity and ignores superseded completions.
- Added metadata text/artwork lifecycle state that falls back to channel identity, transitions current → stale → unavailable, and has no audio-control collaborator.
- Registered the metadata presentation shell in the existing Xcode target without changing build or signing settings.

## Verification

- `swift test --package-path Packages/SiriusXMClient` — 45 tests passed.
- `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` — 51 tests passed.
- `plutil -lint SiriusMac.xcodeproj/project.pbxproj` — passed.
- Static provider-neutrality scan passed; the settled request enum still has exactly two cases.

## Commits

- `1d06ddb` — `test(02-01): add listening composition contracts`
- `053dfdc` — `feat(02-01): add provider-neutral listening shell`
- `1daf93d` — `test(02-01): add Wave 0 listening contracts`
- `9a4789f` — `feat(02-01): implement offline listening state contracts`

## Decisions Made

- Keep pre-checkpoint listening seams semantic and reversible, with no provider request, schema, host, or media-detail representation.
- Make presentational cache data non-authoritative for tune attempts.
- Isolate metadata refresh ownership from playback ownership before a supported live contract exists.

## Deviations from Plan

None — plan executed as written.

## Known Stubs

None. The default composition deliberately reports unavailable or awaiting-contract state; it does not prevent this plan’s stated goal because live-provider activity is expressly deferred to Plan 02-02.

## Self-Check: PASSED

- All four required Wave 0 test files and the metadata presentation shell exist.
- All four task commits are present in the repository history.
