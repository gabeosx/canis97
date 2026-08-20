# Phase 03: Native Mac Listening Experience - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-20
**Phase:** 03-native-mac-listening-experience
**Areas discussed:** Window roles and lifecycle, Library navigation and tuning, Favorites/recents/previous-next, Mac controls and accessibility

---

## Window roles and lifecycle

### Authenticated launch

| Option | Description | Selected |
|--------|-------------|----------|
| Compact player only | Launch into the smallest listening surface. | |
| Compact player and library | Open both native listening surfaces. | ✓ |
| Library only | Make browsing the initial focus. | |
| Restore previous windows | Restore only the windows open in the prior session. | |

**User's choice:** Open both the compact player and library after authenticated launch.
**Notes:** Both windows must share the same composed session and player.

### Window closing

| Option | Description | Selected |
|--------|-------------|----------|
| Close only that window | Keep the app and audio alive after either window closes. | |
| Compact player close stops audio | Treat compact-player closing as app termination while library closing remains local. | ✓ |
| Keep compact player open while playing | Prevent its close while playback is active. | |
| Freeform behavior | Supply another lifecycle model. | |

**User's choice:** Closing the compact player quits the app. Closing the library closes only that window.
**Notes:** Library closing must not interrupt audio. Compact-player closing is normal application termination, not a request to leave a hidden player process running.

### Compact-player size

| Option | Description | Selected |
|--------|-------------|----------|
| Fixed compact size | Use one non-resizable player canvas. | ✓ |
| Limited resizing | Permit resizing within a narrow range. | |
| Fully resizable | Let the player freely adapt to arbitrary window sizes. | |

**User's choice:** Fixed, non-resizable compact player.
**Notes:** This also creates a stable base canvas for future bounded skin geometry.

### Window level

| Option | Description | Selected |
|--------|-------------|----------|
| User-controlled Always on Top | Remember a user toggle, initially disabled. | ✓ |
| Always on top | Keep the player permanently above normal windows. | |
| Normal window level | Never elevate it. | |

**User's choice:** Remembered Always on Top toggle, off by default.
**Notes:** None.

---

## Library navigation and tuning

### Library organization

| Option | Description | Selected |
|--------|-------------|----------|
| Toolbar tabs | Channels, Categories, Favorites, and Recents in a themeable tab strip. | ✓ |
| Native sidebar | Use the standard macOS split-view sidebar. | |
| Single scrolling library | Put all library sections into one scrolling surface. | |

**User's choice:** Skin-themeable toolbar tabs.
**Notes:** The user prioritized maximum visual customizability for future Winamp-style skins. Native navigation semantics remain stable even when visuals change.

### Selection and tuning

| Option | Description | Selected |
|--------|-------------|----------|
| Select, then activate | Single-click selects; double-click or Return tunes. | ✓ |
| Immediate tuning | Single-click tunes a row immediately. | |
| Explicit Tune button | Single-click selects and a separate button tunes. | |

**User's choice:** Single-click selects; double-click or Return tunes.
**Notes:** Existing `ListeningPresentationModel` already separates selection from its tune command.

### Phase 03 skin-system boundary

| Option | Description | Selected |
|--------|-------------|----------|
| Semantic slot/style seam only | Make the UI skin-ready but add no external skin dependency in this phase. | ✓ |
| Seam plus ZIPFoundation | Also add an archive dependency before skin packages are designed. | |
| Defer all architecture | Wait until Phase 04 to separate rendering and semantics. | |

**User's choice:** Establish a skin-ready semantic slot and style seam with no external dependency yet.
**Notes:** The user explicitly requested open-source Mac-player research to avoid future rework. NullPlayer was the closest native Swift precedent: app-owned Codable configuration, a closed semantic element catalog, fixed base geometry, separate rendering, state-specific assets, and a native fallback. IINA reinforced core/window separation. Ampintosh showed the coupling risk of theme-heavy application views. qtWasabi showed the runtime and safety cost of full legacy Winamp/Maki compatibility. NullPlayer is GPL-3.0 and is precedent only; its source must not be copied. Rive and Lottie were rejected as the skin contract, and ZIPFoundation was deferred for Phase 04 archive-transport evaluation.

### Browse selection versus playback

| Option | Description | Selected |
|--------|-------------|----------|
| Independent selection | Preserve browse selection and separately mark the active Now Playing channel. | ✓ |
| Selection follows playback | Automatically select the tuned channel. | |
| Playback highlight only | Clear browse selection after tuning. | |

**User's choice:** Independent browse selection plus a persistent Now Playing indicator.
**Notes:** None.

---

## Favorites, recents, and previous/next

### Favorite controls

| Option | Description | Selected |
|--------|-------------|----------|
| Player and library rows | Toggle favorite state from either surface with immediate synchronization. | ✓ |
| Compact player only | Centralize favorite changes in the player. | |
| Library rows only | Keep favorite editing in the library. | |

**User's choice:** Favorite controls in both compact player and library rows.
**Notes:** Every surface must use the same state keyed by stable channel identity.

### Recents insertion

| Option | Description | Selected |
|--------|-------------|----------|
| Confirmed and deduplicated | Add only after confirmed playback and move repeat listens to the top. | ✓ |
| On tune request | Add before playback success is known. | |
| Confirmed event history | Add after success but keep duplicate listen entries. | |

**User's choice:** Confirmed playback with deduplicated move-to-top behavior.
**Notes:** Failed or superseded tune attempts do not create history.

### Recents retention

| Option | Description | Selected |
|--------|-------------|----------|
| 50 unique channels | Keep the latest 50 and provide Clear Recents. | ✓ |
| All unique channels | Retain indefinitely and provide a clear action. | |
| 10 unique channels | Keep a very short list without manual clearing. | |

**User's choice:** Keep 50 unique channels and provide Clear Recents.
**Notes:** Persistence must comply with `LIBR-03` and contain no secret or stream material.

### Previous/Next sequence

| Option | Description | Selected |
|--------|-------------|----------|
| Captured source queue | Traverse the ordered collection used to start playback, with a full-lineup fallback. | ✓ |
| Full lineup only | Always traverse channel-number order. | |
| History then lineup | Previous uses listen history while Next uses channel order. | |

**User's choice:** Capture a stable queue from the tuning source; later tab changes do not mutate it; fall back to the full lineup.
**Notes:** The playing result remains revealable in the library. Planning determines bounded behavior when the source collection later changes.

---

## Mac controls and accessibility

### System playback commands

| Option | Description | Selected |
|--------|-------------|----------|
| Play/Pause and Previous/Next | Support live-appropriate commands and omit seeking. | ✓ |
| Play/Pause only | Expose only the basic toggle. | |
| Include Stop | Add a separate Stop system command too. | |

**User's choice:** Play/Pause and Previous/Next, without seek or scrub controls.
**Notes:** The app may retain its own Stop control; it is not part of the chosen system surface.

### Now Playing metadata

| Option | Description | Selected |
|--------|-------------|----------|
| Track-first with channel fallback | Show track/artist, channel context, and artwork; fall back to channel metadata. | ✓ |
| Channel only | Publish only station identity and artwork. | |
| Mirror the skin | Publish whatever text the active skin renders. | |

**User's choice:** Track and artist first, with channel context, artwork, and a clean channel fallback.
**Notes:** System metadata follows confirmed semantic state, never arbitrary skin text.

### Keyboard control

| Option | Description | Selected |
|--------|-------------|----------|
| Comprehensive in-app commands | Support focused controls and standard app menu shortcuts, without global hotkeys. | ✓ |
| System-wide shortcuts | Add configurable commands active from other applications. | |
| Minimal navigation | Limit support to standard Tab and Return behavior. | |

**User's choice:** Comprehensive in-app keyboard control with no system-wide hotkeys in Phase 03.
**Notes:** Explicit examples are arrows for navigation, Return to tune, Space for Play/Pause, Command-F for search, and Command-L to show the library.

### Accessibility ownership under skins

| Option | Description | Selected |
|--------|-------------|----------|
| App-owned semantics | Permit visual and bounded-layout changes while the app retains accessibility semantics and fallbacks. | ✓ |
| Free skin layout with labels | Let skins rearrange controls freely if they supply labels. | |
| Separate accessibility mode | Use an independent unskinned mode when accessibility is needed. | |

**User's choice:** App-owned native semantics beneath every skin.
**Notes:** VoiceOver labels and values, focus order, state announcements, contrast fallbacks, and Reduce Motion behavior cannot be removed or redefined by skins.

---

## the agent's Discretion

- Exact fixed compact-player dimensions, initial placement, and library reopen/focus behavior.
- Internal decomposition and names for the semantic presentation, slot, style, and native-fallback boundaries.
- Local persistence types and implementation, subject to the explicit non-secret data constraint.
- Deterministic handling of mutations to a captured queue.
- Exact reveal animation, focus restoration, VoiceOver copy, Now Playing field mapping, and system integration wiring.

## Deferred Ideas

None. Skin package importing, validation, selection, archive handling, and failure recovery remain in the already-defined Phase 04 scope.
