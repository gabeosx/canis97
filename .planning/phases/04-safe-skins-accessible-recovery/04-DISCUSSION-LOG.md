# Phase 04: Safe Skins & Accessible Recovery - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in `04-CONTEXT.md` — this log preserves the analysis.

**Date:** 2026-08-24
**Phase:** 04-safe-skins-accessible-recovery
**Mode:** assumptions
**Areas analyzed:** Native Semantic and Accessibility Boundary, Package Transport and File Ownership, Closed Validation and Atomic Appearance Changes, Bundled Skins Selection and Built-In Recovery

## Assumptions Presented

### Native Semantic and Accessibility Boundary

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| A skin provides only bounded appearance data and noninteractive decoration behind fixed native controls; it cannot alter actions, VoiceOver content, focus order, announcements, or window policy. | Confident | `.planning/phases/03-native-mac-listening-experience/03-CONTEXT.md`; `SiriusMac/Player/CompactPlayerPresentation.swift`; `SiriusMac/Player/CompactPlayerView.swift`; `SiriusMac/Accessibility/AccessibilityAnnouncer.swift`; `SiriusMacTests/CompactPlayerPresentationTests.swift` |

### Package Transport and File Ownership

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Import a ZIP-based `.siriusskin` through ZIPFoundation into app-controlled storage; preflight and extract in two passes, then discard source access. | Likely after external research | `.planning/ROADMAP.md`; `.planning/phases/03-native-mac-listening-experience/03-CONTEXT.md`; `SiriusMac/Library/LibraryStore.swift`; ZIPFoundation 0.9.20 upstream documentation |

### Closed Validation and Atomic Appearance Changes

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Fully validate a strict versioned manifest and bounded assets before changing selection or persistence; hard resource limits are the safety boundary and failures preserve the prior appearance. | Confident | `.planning/ROADMAP.md`; `SiriusMac/Player/CompactPlayerPresentation.swift`; `SiriusMacTests/CompactPlayerPresentationTests.swift`; `SiriusMac/Library/LibraryStore.swift`; Apple Image I/O documentation |

### Bundled Skins, Selection, and Built-In Recovery

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Bundled and imported skins share one finite visual contract; the native fallback remains non-removable and reachable through a Player-menu recovery action; persistence stores selection metadata only. | Likely | `SiriusMac/Player/CompactPlayerView.swift`; `SiriusMac/Player/CompactPlayerPresentation.swift`; `SiriusMac/SiriusMacApp.swift`; `SiriusMac/Library/LibraryStore.swift`; `SiriusMac/Windows/CompactWindowController.swift` |

## Corrections Made

No corrections — all assumptions confirmed by the user.

## External Research

### Archive transport

- ZIPFoundation 0.9.20 exposes iterable entry metadata, chunked extraction, CRC verification, progress, and cooperative cancellation suitable for a guarded ZIP importer.
- ZIPFoundation does not enforce Sirius Mac's duplicate, collision, symlink, path, content, or resource policy; those remain app-owned.
- Apple Archive is a viable zero-dependency alternative only if the public package contract adopts Apple's `.aar` format. The ordinary ZIP creator experience and cheaper metadata preflight made ZIPFoundation the selected v1 transport.

### Resource limits

- Adopted initial policy limits: 16 MiB compressed, 64 MiB expanded, 128 entries, 8 MiB per file/image, 64 KiB manifest, 100:1 compression ratio, 4,096 pixels per dimension, 16 megapixels, four path components, 240 UTF-8 path bytes, and a 10-second monotonic cooperative deadline.
- Only single-frame PNG and JPEG assets are allowed, with Image I/O type detection required to agree with the extension.
- A wall-clock deadline cannot preempt arbitrary synchronous decoding; structural limits are the primary defense, with cooperative cancellation and deadline checks as responsiveness layers.

### Primary sources

- [ZIPFoundation 0.9.20 README](https://github.com/weichsel/ZIPFoundation/tree/0.9.20#readme)
- [ZIPFoundation entry metadata](https://github.com/weichsel/ZIPFoundation/blob/0.9.20/Sources/ZIPFoundation/Entry.swift)
- [ZIPFoundation extraction implementation](https://github.com/weichsel/ZIPFoundation/blob/0.9.20/Sources/ZIPFoundation/Archive%2BReading.swift)
- [Apple Archive streams](https://developer.apple.com/documentation/applearchive/archivestream)
- [Apple Image I/O `CGImageSource`](https://developer.apple.com/documentation/imageio/cgimagesource)
- [Swift task cancellation](https://developer.apple.com/documentation/swift/task/)

