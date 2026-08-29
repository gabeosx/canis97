---
status: resolved
trigger: "Gap G-04-2: selecting Signal Glow, Tape Deck, and Native changes only the color behind the top part of the compact player instead of the complete appearance."
created: 2026-08-26T14:04:51Z
updated: 2026-08-28T00:37:00Z
goal: find_root_cause_only
---

## Current Focus

bug_class: bohrbug
hypothesis: Confirmed — the appearance pipeline selects the correct bundle, but a renderer-scope and bundled-data AND-gate reduces each bundle to a subtle color change instead of a whole-player visual appearance.
test: Differential static trace from the selected appearance through the compact renderer, then compare each bundle's permitted data with the user-visible Phase 4 intent and test coverage.
expecting: Confirmed: only the root/background, upper metadata panel, and favorited star consume appearance values; both bundles omit all decorative assets; no test asserts full-surface rendering.
next_action: Return the root-cause-only diagnosis to the Phase 4 verifier. No source or test changes are authorized in this session.

root_cause_branches:
  - category: code
    candidate: The compact renderer applies `dominantHex` only as a near-black canvas background, `secondaryHex` only to the metadata/artwork panel, `accentHex` only to a favorited star, and never consumes `destructiveHex`; transport/footer surfaces retain system styling.
    result: confirmed
  - category: data
    candidate: Signal Glow and Tape Deck provide no background or metadata decoration because both asset slots are null, and their dominant colors have luminance 0.005 and 0.010 versus Native's 0.006.
    result: confirmed
  - category: config
    candidate: A stale selection/reference is preventing the chosen bundle from reaching the compact player.
    result: eliminated
    evidence: `SiriusMacApp` passes `appearanceController.selectedAppearance` directly to `CompactPlayerView`, and the user observes the immediate upper-panel change when switching choices.
and_gate: yes — either a full-surface renderer or materially complete bundle decorations would make the user-visible result more comprehensive; the reported near-monochrome outcome requires both the narrow renderer consumption and decoration-free/dark bundled inputs.

## Symptoms

expected: Selecting Signal Glow, Tape Deck, and Native updates the complete compact-player appearance; each is readable and visually distinct while layout and controls remain fixed.
actual: "it changes the color behind the top part of the player"
errors: none reported
reproduction: Phase 04 UAT Test 2; select Signal Glow, Tape Deck, and Native.
started: discovered during Phase 04 UAT on 2026-08-26.

## Eliminated

<!-- APPEND only - prevents re-investigating -->

- hypothesis: The selected appearance is not propagated to the live compact-player view.
  evidence: `SiriusMacApp.swift` passes `appearanceController.selectedAppearance` directly to `CompactPlayerView`, and the UAT reporter observes immediate appearance-dependent color changes.
  timestamp: 2026-08-26T14:12:48Z
- hypothesis: A failed decoration is forcing Native recovery.
  evidence: Both bundled manifests declare no decoration URLs, so `renderableAppearance` has no asset to reject and preserves the selected validated appearance.
  timestamp: 2026-08-26T14:12:48Z

## Evidence

- timestamp: 2026-08-26T14:04:51Z
  checked: UAT report supplied by the Phase 4 verifier
  found: The behavior is repeatable while switching bundled appearances and has no error output.
  implication: Treat as a deterministic visual-scope defect (Bohrbug); no live playback or UI automation is needed for source-level diagnosis.
- timestamp: 2026-08-26T14:05:20Z
  checked: .planning/debug/knowledge-base.md and project skill directories
  found: No debug knowledge base or project-defined skill files are present.
  implication: No prior-resolution candidate applies; proceed with direct source inspection under the repository safety policy.
- timestamp: 2026-08-26T14:09:33Z
  checked: CompactPlayerView, SkinAppearance, SiriusMacApp selection composition, bundled manifests, and focused compact-player tests
  found: The selected appearance is passed directly from `SkinAppearanceController.selectedAppearance` to `CompactPlayerView`; `dominantHex` is its sole whole-canvas color, `secondaryHex` decorates the upper metadata panel and artwork, and `accentHex` is used only for a favorited star. The renderer has no use of `destructiveHex`. Both bundled manifests set `backgroundAsset` and `metadataPanelAsset` to null.
  implication: Selection propagation or a stale appearance reference cannot explain the reported behavior. The visual scope is inherently limited by the present renderer/data combination, and the top panel is the most visibly themed surface.
- timestamp: 2026-08-26T14:09:33Z
  checked: SiriusMacTests/CompactPlayerPresentationTests.swift and script/tests/BundledSkinManifestOfflineTests.swift
  found: Tests assert manifest completeness, selection routing, fixed geometry, accessibility containment, and only that `style.dominantHex` is passed to a background modifier. No test renders or asserts per-appearance coverage of the compact-player surface.
  implication: Existing validation can pass while users see a near-monochrome compact player with only the upper panel visibly changing.
- timestamp: 2026-08-26T14:12:48Z
  checked: Phase 4 context/plan, current manifests, and renderer value-to-surface mapping
  found: The Phase 4 intent is safe visual personalization and a bounded skin renderer, but the chosen contract permits null decoration assets and has no user-visible full-surface appearance criterion. The plan's automated acceptance checks therefore validate a complete schema rather than a complete visual treatment.
  implication: The gap is a product-rendering completeness defect, not a selection, persistence, accessibility, or recovery failure.
- timestamp: 2026-08-26T14:12:48Z
  checked: relative luminance of the selected bundle palettes versus Native
  found: Signal Glow dominant 0.005 / panel 0.018; Tape Deck dominant 0.010 / panel 0.027; Native dominant 0.006 / panel 0.019. The more conspicuous non-black palette is attached to the upper panel, while the full-canvas colors remain near-black.
  implication: The user's description is predicted by the current data/renderer composition.

## Resolution

root_cause: "Two contributing causes: (1) `CompactPlayerView` does not render a whole-player visual treatment from the complete bounded style vocabulary; it applies the strongly visible secondary color only to the upper metadata/artwork region, leaves transport/footer system-styled, and does not consume `destructiveHex`. (2) Signal Glow and Tape Deck contain null decoration slots and near-black full-canvas colors, so their only conspicuous difference is the upper panel. The Phase 4 contract/tests define completeness as schema completeness, not full-surface visual distinction."
fix: "Not applied (root-cause-only task). Define a bounded full-player surface model that preserves all app-owned controls/accessibility, then supply and validate visually complete bundled skins (safe local decorations and/or explicit palette roles for each existing surface). Add a renderer-level visual contract so a bundle cannot pass merely by supplying unused tokens or null decorations."
verification: "Static source/data differential: selected appearance propagation is direct; manifests contain no assets; renderer consumption is limited to root background, upper panel/artwork, and favorite star; focused tests do not cover full-surface appearance. No app, app-hosted test, UI test, or live operation was run."
files_changed: []
