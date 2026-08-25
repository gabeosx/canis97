# Phase 04: Safe Skins & Accessible Recovery - Context

**Gathered:** 2026-08-24 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver safe visual personalization for the fixed compact player: at least two complete bundled skins, import and lifecycle management for validated local user-created packages, bounded declarative rendering, and a permanent accessible native recovery path.

This phase does not add executable skin behavior, remote content, classic Winamp compatibility, general-purpose layout scripting, skin-authoring tools, changes to playback or authentication behavior, compatibility support bundles, or public release infrastructure.

</domain>

<decisions>
## Implementation Decisions

### Native semantic and accessibility boundary

- **D-01:** A skin may provide only bounded appearance data and noninteractive decoration behind the fixed native compact-player controls. It cannot alter `CompactPlayerPresentation` semantics, the `CompactPlayerAction` set, VoiceOver labels or values, keyboard focus order, state announcements, Reduce Motion behavior, or compact-window policy.
- **D-02:** Native app-owned controls remain present, operable, and authoritative in every appearance. Skin content cannot remove controls, redefine actions, supply accessibility text, shrink usable hit targets, or replace readable app-owned focus and state indicators.
- **D-03:** Every skin renders within the existing fixed 400×288 compact-player content size. Skins may vary bounded visual tokens and decoration, but they do not resize the window or create an independent layout/runtime system.

### Package transport and file ownership

- **D-04:** The v1 user package is a ZIP-based `.siriusskin` archive. Use ZIPFoundation 0.9.20 through Swift Package Manager strictly as archive transport; Sirius Mac owns all schema, entry, path, resource, and content policy.
- **D-05:** Import is a two-pass transaction. First inspect every entry without extraction; then extract only accepted regular files into a fresh private temporary directory while measuring actual emitted bytes and observing cancellation/deadline checks.
- **D-06:** Reject encrypted archives, symlinks, absolute paths, traversal components, backslashes, NULs, duplicate canonical paths, case or Unicode collisions, file/directory prefix conflicts, unsupported entry types, and any reference that does not resolve beneath the candidate package root.
- **D-07:** After complete validation, atomically promote an app-owned copy into managed storage and discard access to the source archive. Rendering never depends on the original archive, a user-selected folder, a security-scoped bookmark, or files that can change after validation.

### Closed validation and atomic appearance changes

- **D-08:** Use a strict versioned JSON manifest with unknown-field rejection, closed semantic style roles, and local asset references only. Active URLs, remote references, executable content, arbitrary-file access, and fields that claim control over networking, playback, authentication, persistence, or accessibility are invalid.
- **D-09:** Adopt these initial centralized MVP limits: 16 MiB compressed package; 64 MiB total actual expanded regular-file bytes; 128 total entries; 8 MiB per regular file and encoded image; 64 KiB manifest; 100:1 declared per-file and aggregate compression ratio; 4,096 pixels per image dimension; 16,777,216 pixels per image; four path components; and 240 UTF-8 bytes per canonical path.
- **D-10:** Allow only single-frame PNG and JPEG image assets. The Image I/O detected type must agree with the extension; animated or multiframe images, GIF, TIFF, HEIF/HEIC, WebP, SVG, PDF, RAW, and extension-only type claims are rejected.
- **D-11:** Apply a 10-second monotonic cooperative processing deadline, but treat hard byte, count, path, and pixel limits as the security boundary. Check cancellation and the deadline between entries and streamed chunks; do not claim a timeout can preempt arbitrary synchronous image decoding.
- **D-12:** A candidate is fully validated before it can change selection or persistence. Invalid, cancelled, over-budget, failed-to-decode, or failed-to-promote candidates leave the previously selected valid appearance and its durable selection untouched.

### Bundled skins, selection, and recovery

- **D-13:** Ship at least two complete bundled skins and validate them against the same finite visual contract used by imported skins. Separate bundled and imported renderers are not allowed.
- **D-14:** Keep the current unskinned native appearance as a permanent, non-removable fallback that does not depend on any imported package. It remains available even when the persisted selected skin is missing, corrupt, unsupported, or fails to render.
- **D-15:** Provide a native Player-menu recovery action that restores the fallback without first loading or rendering the selected custom skin. Skin visuals cannot hide or disable this path.
- **D-16:** Persist only stable, non-secret selection metadata such as the selected skin identifier and classification. Package bytes and arbitrary manifest content do not enter SwiftData preference records.

### Agent's Discretion

- Exact manifest field names, schema version representation, semantic style-token names, and bounded decorative-slot vocabulary.
- Visual direction and names for the two bundled skins, provided both are complete and exercise the same contract as imported skins.
- Exact skin-management UI and removal confirmation copy, provided selection, removal, validation errors, and native recovery remain keyboard- and VoiceOver-usable.
- Internal importer/store type decomposition, temporary-directory naming, atomic promotion mechanism, and safe cleanup implementation.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Product and phase contracts

- `.planning/PROJECT.md` — native product intent, non-executable skin constraint, dependency strategy, and secret-handling rules.
- `.planning/REQUIREMENTS.md` — authoritative `ACCS-02` and `SKIN-01` through `SKIN-05` requirements.
- `.planning/ROADMAP.md` — Phase 04 goal, success criteria, Phase 03 dependency, and Phase 05 boundary.
- `.planning/phases/03-native-mac-listening-experience/03-CONTEXT.md` — locked semantic-slot, native-control, accessibility, fixed-window, and renderer-independence decisions inherited by Phase 04.
- `.planning/research/STACK.md` — current-macOS stack, strict Codable skin guidance, system image-decoding direction, and adopt-before-build dependency policy.

### Existing implementation contracts

- `SiriusMac/Player/CompactPlayerPresentation.swift` — renderer-independent semantic presentation, closed style roles, and native fallback style.
- `SiriusMac/Player/CompactPlayerView.swift` — fixed native controls, accessibility identifiers and labels, focus/state visuals, and current fallback renderer.
- `SiriusMac/Accessibility/AccessibilityAnnouncer.swift` — app-owned closed announcement vocabulary.
- `SiriusMac/Windows/CompactWindowController.swift` — fixed 400×288 compact-window size and lifecycle policy.
- `SiriusMac/Library/LibraryStore.swift` — app-owned non-secret persistence patterns and rollback-on-failed-mutation behavior.
- `SiriusMac/SiriusMacApp.swift` — application composition and native Player command-menu integration point.
- `SiriusMacTests/CompactPlayerPresentationTests.swift` — renderer/action separation and confirmed-content retention contracts.
- `SiriusMacTests/AccessibilityContractTests.swift` — existing keyboard, VoiceOver, focus, and semantic-control regression contract.

### External primary sources

- [ZIPFoundation 0.9.20 documentation](https://github.com/weichsel/ZIPFoundation/tree/0.9.20#readme) — archive iteration, extraction, progress, and cooperative cancellation behavior.
- [ZIPFoundation entry model](https://github.com/weichsel/ZIPFoundation/blob/0.9.20/Sources/ZIPFoundation/Entry.swift) — inspectable entry paths, types, and compressed/uncompressed size metadata.
- [Apple Image I/O `CGImageSource`](https://developer.apple.com/documentation/imageio/cgimagesource) — pre-decode image type, frame-count, and pixel-property inspection.
- [Swift task cancellation](https://developer.apple.com/documentation/swift/task/) — cooperative cancellation semantics that require structural budgets as the primary safety boundary.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `CompactPlayerPresentation` already separates semantic player state from renderer-owned appearance and exposes a closed `PlayerSemanticStyleRole` vocabulary.
- `CompactPlayerView` already supplies native app-owned controls and accessibility behavior while consuming semantic presentation data and a style value.
- `NativeCompactPlayerStyle` is the built-in recovery appearance and can anchor the permanent fallback identifier.
- `LibraryStore` already demonstrates narrow non-secret preference persistence and rollback when a durable mutation fails.
- The native Player command menu in `SiriusMacApp` provides a recovery route outside skinned compact-player visuals.

### Established Patterns

- Views consume closed semantic values rather than upstream, secret-adjacent, or behavior-bearing data.
- User-visible state changes only after the underlying operation is confirmed; failed operations preserve the last confirmed state.
- Accessibility semantics, menu commands, playback ownership, and window behavior remain app-owned and renderer-independent.
- SwiftUI owns product presentation; AppKit interop stays narrow and window-specific.

### Integration Points

- Extend the compact-player style seam with a bounded skin renderer without changing playback/session ownership or `CompactPlayerAction` routing.
- Add an app-owned skin importer, validator, managed package store, and selection model at the application layer.
- Connect stable selected-skin metadata to the existing non-secret preference store or a dedicated skin selection store without persisting package content in SwiftData.
- Add skin selection, import, removal, error presentation, and fallback recovery to native app/library or Settings surfaces and the Player command menu.

</code_context>

<specifics>
## Specific Ideas

- Preserve the compact, quirky, nostalgic spirit of Winamp without importing Winamp formats or executing a legacy skin runtime.
- Use `.siriusskin` as the recognizable user-facing package extension while retaining ordinary ZIP tooling for creators.
- Count actual streamed extraction output; declared ZIP sizes are early-rejection hints, not trusted resource measurements.
- Ship two tested bundled skins in addition to the permanent native fallback, so the fallback is a recovery guarantee rather than the minimum personalization offering.

</specifics>

<deferred>
## Deferred Ideas

- Skin-authoring tools, live skin editing, legacy Winamp skin import, animated skin formats, executable scripting, remote skin galleries, and remotely fetched assets remain outside the v1 Phase 04 boundary.
- A disposable helper or XPC process for hard decoder preemption is deferred unless testing establishes that structural budgets plus cooperative cancellation are insufficient.

</deferred>

---

*Phase: 04-safe-skins-accessible-recovery*
*Context gathered: 2026-08-24*
