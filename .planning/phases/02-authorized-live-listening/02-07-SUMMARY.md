---
phase: 02
plan: "07"
subsystem: metadata
tags: [metadata, artwork, freshness, safety]
status: complete
requires: [02-06]
provides: [fixed-lookaround-metadata, bounded-artwork, independent-presentation]
affects: [listening-ui]
actuals:
  tasks: 2
  commits: 2
---

# Phase 02 Plan 07: Metadata Presentation Summary

Implemented fixed, semantic current-program metadata and bounded artwork handling that remains independent of playback authority.

## Completed

1. Added the approved lookaround metadata operation and strict first-cut decoder, opaque artwork references, fixed artwork host, JPEG/PNG admission, redirect denial, 5 MiB and 4096-pixel product bounds.
2. Added a metadata-only selected-channel presentation model with generation cancellation, 30-second polling policy, 90-second stale ceiling, five-minute unavailable ceiling, channel fallback, and native accessibility copy.

## Verification

- `swift test --package-path Packages/SiriusXMClient --filter MetadataRefreshCoordinatorTests`: passed, 7 tests.
- `plutil -lint SiriusMac.xcodeproj/project.pbxproj`: passed.
- Focused `xcodebuild ... -only-testing:SiriusMacTests/MetadataPresentationTests`: exited 0 with 2 tests passing. It unexpectedly launched a DerivedData SiriusMac test host, which was left untouched under the no-termination constraint; no more app tests were run.

## Decisions

- Admit only `cuts[0]` for text/artwork; optional shows never replace it.
- Treat `delta` and `validFrom` as non-scheduling values; use the fixed product cadence/ceilings.
- Metadata and artwork failures degrade presentation only and expose no playback mutation path.

## Deviations from Plan

### Auto-fixed Issues

1. [Rule 1 - Test compilation] Stored an actor result before passing it to XCTest's synchronous assertion autoclosure.

### Verification deviation

The focused app-test host remained running after the successful command. It was not terminated because the owner prohibited app termination. No live provider, Keychain, browser, or AVFoundation validation occurred.

## Self-Check: PASSED

- Commits `dd7c7d8` and `9e80060` exist.
- Metadata source, focused tests, and sanitized contract evidence exist.
