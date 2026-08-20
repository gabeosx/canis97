# Phase 03: Native Mac Listening Experience - Context

**Gathered:** 2026-08-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver the finished native macOS listening shell around the authorized live-listening core from Phase 02: a fixed-size compact player and a separate library window that share one session and one playback coordinator; local favorites and successful-listen recents; deterministic previous/next behavior; and macOS media controls, Now Playing, keyboard, and VoiceOver integration.

This phase also establishes the semantic presentation and styling seam that Phase 04 skins will consume. It does not add a skin package format, archive importer, third-party skin runtime, bundled skin selection, or hostile-package validation; those remain in Phase 04.

</domain>

<decisions>
## Implementation Decisions

### Window roles and lifecycle

- **D-01:** After an authenticated launch, open both the compact player and the library window.
- **D-02:** The compact player is the application's primary lifetime window: closing it quits Sirius Mac and ends playback through normal application shutdown. Closing the library closes only that window; the app and healthy audio continue. Library reopening must reconnect to the existing state rather than compose another player.
- **D-03:** Use one fixed, non-resizable compact-player size. The exact dimensions are left to planning and UI design.
- **D-04:** Provide a remembered user-controlled **Always on Top** setting for the compact player. It is off by default.

### Library navigation and tuning

- **D-05:** Organize the library with skin-themeable toolbar tabs for Channels, Categories, Favorites, and Recents. Navigation semantics remain app-owned even when their visuals are themed.
- **D-06:** A single click changes browse selection without tuning. A double-click or Return tunes the selected channel.
- **D-07:** Establish a skin-ready semantic-slot and style seam during Phase 03, but add no external skin dependency. The compact player must not embed playback behavior in a particular renderer or hard-code future skin behavior into one monolithic view. — **Reversibility:** costly — deferring this boundary until after the player, library, system controls, and accessibility tree are coupled would require coordinated changes across those presentation surfaces before Phase 04 skins could safely replace their visuals.
- **D-08:** Keep browse selection independent from active playback. Every library collection displays a persistent Now Playing indicator on the active channel without forcing browse selection to follow it.

### Favorites, recents, and previous/next

- **D-09:** Allow favorite and unfavorite actions from both the compact player and every applicable library channel row. All surfaces update immediately from the same local favorite state keyed by stable channel identity.
- **D-10:** Add a channel to Recents only after playback is confirmed. Replaying a channel moves its existing entry to the top rather than creating a duplicate.
- **D-11:** Retain the 50 most recently played unique channels and provide a **Clear Recents** action. Persist only non-secret identity and presentation snapshots as constrained by `LIBR-03`.
- **D-12:** Previous and Next traverse a stable ordered queue captured from the collection where playback began, such as a category or Favorites. Later library-tab changes do not silently mutate that queue. If there is no usable captured collection, fall back to the full entitled channel lineup. Previous/Next results must be revealable in the library as required by `UI-04`.

### Mac controls and accessibility

- **D-13:** Expose Play/Pause and Previous/Next through Mac media keys and Control Center. Do not expose seek or scrub controls because this is live radio. A separate system Stop command is not part of the chosen v1 surface.
- **D-14:** Now Playing prioritizes current track title and artist, with channel name and artwork as context. When track details are absent, fall back cleanly to channel metadata; never mirror arbitrary text chosen by a skin.
- **D-15:** Make every essential action operable while Sirius Mac is active through focused controls and application menu commands. Include arrow-key library navigation, Return to tune, Space for Play/Pause, Command-F for search, and Command-L to show or focus the library. Configurable system-wide hotkeys are out of scope for this phase.
- **D-16:** Skins may change visuals and bounded layout but cannot remove or redefine native control semantics. VoiceOver labels and values, keyboard focus, contrast fallbacks, state announcements, and Reduce Motion behavior remain app-owned. The accessible experience is the normal product, not a separate unskinned accessibility mode.

### the agent's Discretion

- Choose the exact fixed compact-player dimensions, initial placement, and library reopen/focus behavior while preserving the two distinct window roles and remembered Always on Top setting.
- Choose internal type names and decomposition for semantic player slots, presentation data, style tokens, native fallback rendering, and window composition. The seam must remain declarative and renderer-independent; it does not need to freeze Phase 04's final public manifest schema.
- Choose local persistence details for favorites, recents, the Always on Top preference, and selected tab while retaining no credentials, session material, resolved stream URLs, or other secret-adjacent state.
- Define bounded behavior when a captured queue changes after tuning, such as a favorite being removed or a catalog refresh removing a channel. Preserve deterministic ordering, entitlement checks, and the full-lineup fallback.
- Choose the exact library reveal animation, focus movement, empty-state copy, keyboard focus restoration, VoiceOver announcements, and Now Playing field mapping from the confirmed semantic states already provided by Phase 02.
- Use normal macOS audio routing. Do not add a custom audio-output stack.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Product and phase contract

- `.planning/PROJECT.md` — native-product boundary, compact nostalgic player intent, one reusable client, secret-handling rules, skin safety, and dependency strategy.
- `.planning/REQUIREMENTS.md` — authoritative `LIBR-01`–`LIBR-03`, `MAC-01`–`MAC-04`, `UI-01`–`UI-04`, and `ACCS-01` requirements; also defines the Phase 04 skin boundary.
- `.planning/ROADMAP.md` — Phase 03 goal, success criteria, Phase 02 dependency, and handoff to Phase 04 Safe Skins & Accessible Recovery.

### Carried-forward playback and platform decisions

- `.planning/phases/02-authorized-live-listening/02-CONTEXT.md` — one playback coordinator, confirmed-state rendering, live-radio pause/resume semantics, deterministic channel identity, metadata fallback, and secret-safe state boundaries.
- `.planning/research/STACK.md` — SwiftUI with narrow AppKit interop, AVFoundation and MediaPlayer integration, SwiftData guidance, current-macOS window APIs, and the declarative non-executable skin strategy.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `SiriusMac/Listening/PlaybackCoordinator.swift`: the `@MainActor`, observable coordinator already owns exactly one `AVPlayer`, serializes live commands, reports confirmed playback states, and contains recovery/lifecycle observation. Every new window and system command must reuse this instance.
- `SiriusMac/Catalog/ListeningPresentationModel.swift`: browse selection is already distinct from `tuneSelectedChannel()`, and the model observes the shared coordinator after commands return. This directly supports single-click selection, explicit tune activation, and independent Now Playing state.
- `SiriusMac/Catalog/ListeningView.swift`: the current native list, channel rows, metadata rendering, playback controls, and accessibility identifiers provide a working semantic baseline to refactor into the dedicated library and compact-player surfaces.
- `SiriusMac/Authentication/AuthenticationView.swift`: authenticated app composition already creates and retains the playback coordinator and listening model. Phase 03 should lift or reshape this composition without allowing either window to construct its own coordinator.

### Established Patterns

- Views consume semantic channel, playback, and metadata state rather than upstream responses, stream URLs, or AVFoundation objects.
- User-facing playback state follows coordinator confirmation rather than optimistic button state.
- Stable `LiveChannelID` values anchor selection and tuning; favorites, recents, queue entries, and library reveal should use the same identity.
- SwiftUI owns product UI while AppKit interop remains narrow and window-specific.

### Integration Points

- Replace the single authentication `WindowGroup` in `SiriusMac/SiriusMacApp.swift` with explicit compact-player and library scenes while preserving the inert unit-test-host launch path.
- Split the current `ListeningView` responsibilities into shared semantic presentation plus distinct compact-player and library views; do not duplicate playback ownership.
- Feed confirmed `PlaybackCoordinator` and metadata presentation state into `MPRemoteCommandCenter` and `MPNowPlayingInfoCenter` through one app-owned integration layer.
- Connect favorites, recents, and captured queue state at the application layer so compact player, library, menus, and system controls observe the same source of truth.

</code_context>

<specifics>
## Specific Ideas

- The target feel is a genuinely native Mac application with the compact, quirky, nostalgic spirit of Winamp, not a website-shaped player.
- Open-source precedent research identified [NullPlayer](https://github.com/ad-repo/nullplayer) as the closest native Swift example. Its app-owned declarative configuration, closed semantic [element catalog](https://github.com/ad-repo/nullplayer/blob/main/Sources/NullPlayer/ModernSkin/ModernSkinElements.swift), fixed base canvas, state-specific assets, and separate [renderer](https://github.com/ad-repo/nullplayer/blob/main/Sources/NullPlayer/ModernSkin/ModernSkinRenderer.swift) validate the chosen semantic-slot seam. NullPlayer is GPL-3.0 precedent only; do not copy its implementation.
- [IINA](https://github.com/iina/iina) reinforces separation between playback core and window presentation. [Ampintosh](https://github.com/KiwiSingh/Ampintosh) illustrates the rework risk of concentrating theme behavior in application views. [qtWasabi](https://github.com/qtWasabi/qtWasabi) illustrates why full legacy Winamp compatibility and a Maki bytecode runtime conflict with the native, declarative, non-executable skin boundary.
- Do not add Rive, Lottie, ZIPFoundation, a Maki interpreter, or another skin runtime in Phase 03. Phase 04 may evaluate ZIPFoundation strictly as archive transport after defining independent path, symlink, size, dimension, schema, and processing-budget validation.
- Rendered bitmap or Canvas decoration may eventually sit behind controls, but actual interactive controls and their accessibility tree remain native and app-owned.
- The compact player's close behavior intentionally means application termination, whereas closing the library is a non-destructive window operation. Window closing must never create or silently replace playback state; normal app termination owns shutdown.

</specifics>

<deferred>
## Deferred Ideas

None — skin package importing, validation, bundled/user skin selection, and recovery were kept within their already-defined Phase 04 boundary rather than added to Phase 03.

</deferred>

---

*Phase: 03-native-mac-listening-experience*
*Context gathered: 2026-08-20*
