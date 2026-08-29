# Phase 03 — UI Review

**Audited:** 2026-08-26
**Baseline:** Approved `03-UI-SPEC.md` design contract
**Screenshots:** Not captured — Sirius Mac is a native macOS app and no supported local web dev server was present on ports 3000, 5173, or 8080. This is a code-and-contract audit; existing Phase 03 offline UI-harness evidence was considered but not re-run.

---

## Pillar Scores

| Pillar | Score | Key Finding |
|--------|-------|-------------|
| 1. Copywriting | 2/4 | Catalog errors always offer `Try Again`, including sign-in and entitlement failures that require a different recovery action. |
| 2. Visuals | 2/4 | Categories becomes an unexplained split-pane browser and the four navigation tabs/search are placed in content rather than the promised toolbar. |
| 3. Color | 2/4 | The compact fallback owns the specified palette, but the library uses system/default tint and has no declared dominant/secondary surface treatment. |
| 4. Typography | 3/4 | The compact player mostly uses the four approved sizes, but library typography is implicit and has off-contract legacy surface styles. |
| 5. Spacing | 2/4 | Multiple un-tokenized 2/5/6/10/20 pt values and an additional persistent banner weaken the documented 4 pt scale and fixed compact rhythm. |
| 6. Experience Design | 2/4 | Favorites can render empty merely because the current catalog does not contain saved IDs; category, error, and fallback states do not consistently preserve user intent. |

**Overall: 13/24**

---

## Top 3 Priority Fixes

1. **Make Favorites a durable saved collection, not a filter of the current catalog** — a user who favorited channels can be shown `No Favorites Yet` when the catalog has not loaded, is incomplete, or omits an old ID — render stored snapshots first, label entries unavailable when entitlement is unknown, and reserve the empty state for genuinely zero saved favorites.
2. **Replace the Categories split pane with a clear browsing model and put navigation where the contract promises it** — the current unexplained left category list plus right channel list is why the tab feels purposeless; use a toolbar tab/search surface and grouped category sections (or clearly label the left pane `Browse by Category`) while retaining an obvious all-channel path.
3. **Map recovery UI to the actual failure and unify library visual tokens** — authentication/entitlement errors must expose `Sign In Again`, catalog errors `Refresh Library`, and retryable errors `Try Again`; give the library the same documented semantic palette/focus treatment as compact rather than mixing default system tint, orange warning treatment, and skin-only colors.

---

## Detailed Findings

### Pillar 1: Copywriting (2/4)

- **WARNING — failure recovery is inaccurate.** `LibraryView` always renders a `Try Again` button for `.failed`, even though `failureCopy` can say to sign in again or reports missing entitlement. This breaks the approved failure-specific recovery contract and can lead to repeated ineffective refreshes. See [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:496) and [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:823).
- **WARNING — canonical empty-state copy is expanded with an unsupported account assertion.** The Favorites body adds “aren’t imported from your SiriusXM account,” which is neither in the contract nor needed to tell the user how to recover. It makes the most sensitive local-state screen less direct. See [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:765).
- **WARNING — category navigation does not communicate its purpose.** The visible `Categories` label does not say that a second selection is required before results change; the fallback “Choose a Category” arrives only after entering the tab. See [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:524) and [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:542).
- **PASSING EVIDENCE.** Compact idle, loading, and confirmed states now use truthful language: `Nothing Playing`, `Loading playback`, and `Playing`; the prior idle spinner problem is resolved. See [CompactPlayerView.swift](/Users/gabe/sirius-mac/SiriusMac/Player/CompactPlayerView.swift:158) and [CompactPlayerPresentation.swift](/Users/gabe/sirius-mac/SiriusMac/Player/CompactPlayerPresentation.swift:110).

### Pillar 2: Visuals (2/4)

- **WARNING — library navigation diverges from the toolbar contract.** The contract requires four semantic tabs and search in the top toolbar. They are rendered as a segmented picker and a text field inside the document body, while the actual toolbar contains only Refresh and conditional Clear Recents. This creates a second navigation band and makes empty collection content compete with navigation rather than sit beneath it. See [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:384), [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:439), and [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:481).
- **WARNING — Categories has a weak focal hierarchy.** An `HSplitView` gives raw category names/counts a full sidebar but provides no explanatory header, active scope label, or category artwork. The user must infer why this tab exists and why the current result list changes. See [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:524).
- **WARNING — the persistence warning can become a third permanent chrome band.** It appears beneath the collection and uses an orange surface independently of the normal error/empty region, leaving the user with tabs, search, collection, and warning chrome in a 540 pt-tall minimum window. See [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:467).
- **PASSING EVIDENCE.** Compact preserves the required visual anchor: channel identity and a 72 pt artwork well are first, before status, transport, and footer. Icon-only controls have labels and help. See [CompactPlayerView.swift](/Users/gabe/sirius-mac/SiriusMac/Player/CompactPlayerView.swift:77), [CompactPlayerView.swift](/Users/gabe/sirius-mac/SiriusMac/Player/CompactPlayerView.swift:115), and [CompactPlayerView.swift](/Users/gabe/sirius-mac/SiriusMac/Player/CompactPlayerView.swift:218).

### Pillar 3: Color (2/4)

- **WARNING — visual system is inconsistent across the two primary windows.** The compact style declares the approved `#111111`, `#262626`, `#C6FF00`, and `#FF453A` fallback palette, but the library has no corresponding dominant/secondary surface roles and instead uses default list/window materials. This does not meet the specified shared native fallback palette or the intended 60/30/10 distribution. See [CompactPlayerPresentation.swift](/Users/gabe/sirius-mac/SiriusMac/Player/CompactPlayerPresentation.swift:254) and [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:565).
- **WARNING — accent is not deterministic in the library.** Now Playing uses `.tint` and the favorite glyph uses `Color.accentColor`; neither is pinned to the contract’s accent role or checked against the compact appearance. A changed system accent can make active and favorite states visually unrelated to the compact player. See [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:644) and [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:659).
- **WARNING — orange is used as a generic persistence warning color, outside the declared semantic palette.** The contract reserves destructive red and does not define orange warning chrome; it needs a tested semantic warning treatment with adequate contrast, not an ad hoc opacity surface. See [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:469).
- **Audit evidence.** No Tailwind-style primary tokens exist (expected for SwiftUI); the only hard-coded colors are the compact fallback token values. No third-party registry applies: `components.json` is absent and the UI-SPEC declares no third-party blocks.

### Pillar 4: Typography (3/4)

- **WARNING — compact meets the declared scale, but the library does not deliberately express it.** Compact uses only 12, 14, 18, and 24 pt with semibold for hierarchy. Library rows instead depend largely on implicit defaults plus `.caption` and `.medium`, which leaves heading/body/label relationships ungoverned. See [CompactPlayerView.swift](/Users/gabe/sirius-mac/SiriusMac/Player/CompactPlayerView.swift:84), [CompactPlayerView.swift](/Users/gabe/sirius-mac/SiriusMac/Player/CompactPlayerView.swift:285), and [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:629).
- **WARNING — the file still contains an older `ListeningView` with `.title2` and a different browser/control hierarchy.** Although the app root uses `LibraryView`, retaining a competing presentation surface makes future regressions likely and creates inconsistent preview/test reference material. See [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:7) and [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:41).
- **PASSING EVIDENCE.** Compact truncates metadata, exposes full values via tooltip/accessibility, and uses the intended semantic hierarchy. See [CompactPlayerView.swift](/Users/gabe/sirius-mac/SiriusMac/Player/CompactPlayerView.swift:135).

### Pillar 5: Spacing (2/4)

- **WARNING — the declared 4 pt scale is not consistently followed.** Compact uses 6 pt horizontal padding and a 20 pt artwork-placeholder inset; library uses 2, 5, and 10 pt row spacing/insets. These values are not listed exceptions, so the system cannot produce predictable rhythm. See [CompactPlayerView.swift](/Users/gabe/sirius-mac/SiriusMac/Player/CompactPlayerView.swift:124), [CompactPlayerView.swift](/Users/gabe/sirius-mac/SiriusMac/Player/CompactPlayerView.swift:180), [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:629), and [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:844).
- **WARNING — the compact content budget is fragile.** The 288 pt fixed canvas hosts a 72 pt top panel, separate status/recovery area, transport, footer, and potentially an appearance-recovery banner. Long metadata plus the extra banner can force density rather than the intended 32 pt section separation. See [CompactPlayerView.swift](/Users/gabe/sirius-mac/SiriusMac/Player/CompactPlayerView.swift:37), [CompactPlayerView.swift](/Users/gabe/sirius-mac/SiriusMac/Player/CompactPlayerView.swift:158), and [CompactPlayerView.swift](/Users/gabe/sirius-mac/SiriusMac/Player/CompactPlayerView.swift:189).
- **WARNING — `ContentUnavailableView` can vertically center the empty state while navigation remains a separate body band.** This is the likely structural source of the reported navigation/empty-state “middle of the screen” feeling. The content uses maximum height under custom body controls rather than a native toolbar/content hierarchy. See [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:439) and [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:509).

### Pillar 6: Experience Design (2/4)

- **BLOCKER — saved Favorites can disappear from the user’s only favorites surface.** The Favorites tab is calculated solely as `currentChannels.filter { isFavorite }`. If the current snapshot is unavailable, incomplete, or a prior stable ID no longer appears in it, a user with durable saved records sees the false `No Favorites Yet` empty state. This directly matches the reported trust failure. Retain/display stored `LibraryChannelSnapshot`s, then decorate them with current availability instead of conflating absent catalog data with absent favorite data. See [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:603) and [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:747).
- **WARNING — Categories provides browsing mechanics but not a user goal.** It is a raw grouping projection with no purpose statement, no cross-category overview, and an extra selection step. It should become a direct grouped library list or be renamed and introduced as an explicit browsing mode. See [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:293) and [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:524).
- **WARNING — failure state loses the valid recovery route.** As in Pillar 1, the error action is generic despite a typed error model. The compact player handles specific recovery actions correctly, so the two windows can disagree about what the user should do. Compare [CompactPlayerPresentation.swift](/Users/gabe/sirius-mac/SiriusMac/Player/CompactPlayerPresentation.swift:183) with [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:496).
- **WARNING — artwork has a resilient placeholder but no observable loading/error state.** `ArtworkStore` treats an unavailable reference as terminal until a catalog refresh and `ChannelArtworkImage` keeps the same photo placeholder for no reference, in-flight request, byte failure, and unsupported image decode. The layout remains stable, but the user cannot distinguish ordinary delayed art from a failed fetch. See [ArtworkStore.swift](/Users/gabe/sirius-mac/SiriusMac/Metadata/ArtworkStore.swift:37) and [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:251).
- **PASSING EVIDENCE.** Compact state is now truthful: idle/stopped does not spin, while a genuine pending tune exposes progress. Library row activation remains separate from selection, and favorite controls are independently focusable. See [CompactPlayerPresentation.swift](/Users/gabe/sirius-mac/SiriusMac/Player/CompactPlayerPresentation.swift:110), [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:565), and [ListeningView.swift](/Users/gabe/sirius-mac/SiriusMac/Catalog/ListeningView.swift:650).

---

## Files Audited

- `03-01-SUMMARY.md` through `03-09-SUMMARY.md`, `03-01-PLAN.md` through `03-09-PLAN.md`, `03-UI-SPEC.md`, and `03-CONTEXT.md`
- `SiriusMac/Catalog/ListeningView.swift`
- `SiriusMac/Library/LibraryStore.swift` and `SiriusMac/Library/PlaybackQueue.swift`
- `SiriusMac/Metadata/ArtworkStore.swift`
- `SiriusMac/Player/CompactPlayerPresentation.swift` and `SiriusMac/Player/CompactPlayerView.swift`
- `SiriusMac/SiriusMacApp.swift`
- Focused compact, library, queue, and persistence tests
