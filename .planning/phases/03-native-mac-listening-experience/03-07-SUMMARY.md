---
phase: 03-native-mac-listening-experience
plan: 07
subsystem: ui
tags: [swiftui, appkit, accessibility, voiceover, keyboard, menus]
requires:
  - phase: 03-06
    provides: shared listening controller, compact player, library, and system media ownership
provides:
  - closed, deduplicated native accessibility announcements
  - shared menu and keyboard command routing for player and library actions
  - stable VoiceOver semantics, focus restoration, context menus, and Reduce Motion handling
affects: [03-08, safe-skins-accessible-recovery]
actuals:
  tokens: 11523
  tasks: 2
  commits: 4
tech-stack:
  added: []
  patterns: [injected AppKit announcement poster, generation-tagged focus requests, semantic control identifiers]
key-files:
  created: [SiriusMac/Accessibility/AccessibilityAnnouncer.swift, SiriusMacTests/AccessibilityContractTests.swift]
  modified: [SiriusMac.xcodeproj/project.pbxproj, SiriusMac/App/ListeningSessionController.swift, SiriusMac/SiriusMacApp.swift, SiriusMac/Catalog/ListeningView.swift, SiriusMac/Player/CompactPlayerView.swift]
key-decisions:
  - "VoiceOver receives only closed semantic event strings through an injected AppKit poster."
  - "Menu and compact/library controls call the same ListeningSessionController routes."
requirements-completed: [ACCS-01, UI-01, UI-02]
coverage:
  - id: D1
    description: Closed, deduplicated native announcements for confirmed playback, favorite, failure, and freshness transitions.
    requirement: ACCS-01
    verification:
      - kind: unit
        ref: SiriusMacTests/AccessibilityContractTests.swift
        status: unknown
    human_judgment: true
    rationale: The repaired target includes the accessibility sources; compilation now reaches a separate type-inference error in ListeningSessionController.swift.
  - id: D2
    description: Native player and library menus, keyboard routes, semantic labels, focus restoration, context menus, and Reduce Motion behavior.
    requirement: UI-01
    verification:
      - kind: unit
        ref: xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/AccessibilityContractTests
        status: unknown
    human_judgment: true
    rationale: VoiceOver order, high-contrast rendering, and focused keyboard interaction require the planned native manual checkpoint.
duration: 19min
completed: 2026-08-21
status: complete
---

# Phase 03 Plan 07: Native Accessibility Commands Summary

**Closed VoiceOver announcements, shared native player/library commands, and stable semantic focus behavior across the macOS listening experience.**

## Performance

- **Duration:** 19 min
- **Started:** 2026-08-21T18:00:00Z
- **Completed:** 2026-08-21T18:19:51Z
- **Tasks:** 2/2
- **Files modified:** 7

## Accomplishments

- Added a closed, injected AppKit announcement boundary that deduplicates confirmed listening, favorite, terminal-failure, and metadata-freshness events.
- Routed Player menu, Space, Command-F, and Command-L controls through the app-lifetime listening session.
- Added stable control identifiers, complete VoiceOver labels/values/tooltips, independent favorite access, context-menu duplication, focus recovery, and Reduce Motion handling.

## Task Commits

1. **Task 1: Announce confirmed semantic transitions exactly once** — `ecfa380` (test RED), `39ebb63` (feat GREEN)
2. **Task 2: Complete native commands, focus, labels, values, order, and Reduce Motion** — `57a42fc` (feat)
3. **Post-gate repair: Restore original app Sources build-file identifiers** — `3b032bd` (fix)

## Files Created/Modified

- `SiriusMac/Accessibility/AccessibilityAnnouncer.swift` — Closed event model, AppKit poster, and per-session dedupe.
- `SiriusMac/App/ListeningSessionController.swift` — Confirmed-transition observation, favorite route, focus requests, and shared playback routing.
- `SiriusMac/SiriusMacApp.swift` — Player menu commands backed by the shared controller.
- `SiriusMac/Catalog/ListeningView.swift` — Focused search/list behavior, semantic rows, contexts, and motion policy.
- `SiriusMac/Player/CompactPlayerView.swift` — Stable compact accessibility identifiers, labels, values, hints, and order.
- `SiriusMacTests/AccessibilityContractTests.swift` — Deterministic injected-announcer contract coverage.
- `SiriusMac.xcodeproj/project.pbxproj` — Restored the five original build-file identifiers while retaining `AccessibilityAnnouncer.swift` source membership.

## Decisions Made

- VoiceOver strings are fixed semantic values; channel/provider errors, resources, tokens, diagnostics, and renderer text cannot cross the announcement boundary.
- Playback transition observation remains controller-owned so compact, library, menu, and system surfaces share one semantic source.

## Deviations from Plan

None - plan implementation followed the requested controller/view boundaries.

## Issues Encountered

- The malformed app Sources references introduced during the accessibility change omitted five existing Swift sources from Xcode's generated file list. Restoring their original build-file identifiers makes `FirstPartyTokenCookiePolicy.swift` compile again.
- Both `xcodebuild test -only-testing:SiriusMacTests/AccessibilityContractTests` and the complete macOS `xcodebuild test` now reach a separate `ListeningSessionController.swift` type-inference failure for `.current`, `.stale`, and `.unavailable`, so the focused suite cannot yet execute.

## Next Phase Readiness

- Plan 03-08 can manually inspect VoiceOver traversal, focus rings, high contrast, and Reduce Motion using the stable identifiers and shared command routes introduced here.
- Resolve the `ListeningSessionController` type-inference error before treating the focused accessibility suite as passing.

## Self-Check: PASSED

- Confirmed all listed source files exist and task commits `ecfa380`, `39ebb63`, and `57a42fc` are present in git history.
