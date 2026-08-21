# Phase 3: Native Mac Listening Experience - Research

**Researched:** 2026-08-21
**Domain:** Native macOS SwiftUI/AppKit listening shell, local library state, MediaPlayer controls, and accessibility
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** After an authenticated launch, open both the compact player and the library window.
- **D-02:** The compact player is the application's primary lifetime window: closing it quits Sirius Mac and ends playback through normal application shutdown. Closing the library closes only that window; the app and healthy audio continue. Library reopening must reconnect to the existing state rather than compose another player.
- **D-03:** Use one fixed, non-resizable compact-player size. The exact dimensions are left to planning and UI design.
- **D-04:** Provide a remembered user-controlled **Always on Top** setting for the compact player. It is off by default.
- **D-05:** Organize the library with skin-themeable toolbar tabs for Channels, Categories, Favorites, and Recents. Navigation semantics remain app-owned even when their visuals are themed.
- **D-06:** A single click changes browse selection without tuning. A double-click or Return tunes the selected channel.
- **D-07:** Establish a skin-ready semantic-slot and style seam during Phase 03, but add no external skin dependency. The compact player must not embed playback behavior in a particular renderer or hard-code future skin behavior into one monolithic view. — **Reversibility:** costly — deferring this boundary until after the player, library, system controls, and accessibility tree are coupled would require coordinated changes across those presentation surfaces before Phase 04 skins could safely replace their visuals.
- **D-08:** Keep browse selection independent from active playback. Every library collection displays a persistent Now Playing indicator on the active channel without forcing browse selection to follow it.
- **D-09:** Allow favorite and unfavorite actions from both the compact player and every applicable library channel row. All surfaces update immediately from the same local favorite state keyed by stable channel identity.
- **D-10:** Add a channel to Recents only after playback is confirmed. Replaying a channel moves its existing entry to the top rather than creating a duplicate.
- **D-11:** Retain the 50 most recently played unique channels and provide a **Clear Recents** action. Persist only non-secret identity and presentation snapshots as constrained by `LIBR-03`.
- **D-12:** Previous and Next traverse a stable ordered queue captured from the collection where playback began, such as a category or Favorites. Later library-tab changes do not silently mutate that queue. If there is no usable captured collection, fall back to the full entitled channel lineup. Previous/Next results must be revealable in the library as required by `UI-04`.
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

### Deferred Ideas (OUT OF SCOPE)

None — skin package importing, validation, bundled/user skin selection, and recovery were kept within their already-defined Phase 04 boundary rather than added to Phase 03.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| LIBR-01 | Local favorites keyed by stable channel identity | One app-owned observable library store, SwiftData persistence, and every surface bound to that store. |
| LIBR-02 | Ordered successful-listen recents | Record only the `.playing` confirmation; deduplicate/move-to-front and cap at 50. |
| LIBR-03 | Persist no credentials, session material, or stream URLs | Persist an allow-listed channel snapshot only; never copy client/session/metadata artwork transport values. |
| MAC-01 | Healthy audio survives backgrounding/library closure | Retain the single coordinator at app composition, never in a scene or view. |
| MAC-02 | Media keys and system Now Playing controls | A single `MPRemoteCommandCenter` integration registers Play/Pause, Previous, and Next only. |
| MAC-03 | System state is confirmed, not optimistic | Observe coordinator and active metadata state; update Now Playing only on their confirmed transitions. |
| MAC-04 | Normal system audio routing | Keep AVFoundation as the one existing playback runtime; add no routing/output layer. |
| UI-01 | Single compact player | Singleton SwiftUI `Window`, fixed content size, narrow AppKit adapter for level/frame/close behavior. |
| UI-02 | Separate library with browse/categories/local collections | Singleton library `Window`, four app-owned tabs, dynamic category grouping, and search. |
| UI-03 | Both windows share state and never construct another player | One app-level session composition is injected into both scene roots. |
| UI-04 | Deterministic previous/next and library reveal | Capture a stable queue at tune intent, validate it against current entitlement, and route reveal through library state. |
| ACCS-01 | Keyboard and VoiceOver access | Native controls/commands, focused values, explicit state labels, announcements, and Reduce Motion handling. |
</phase_requirements>

## Project Constraints (from AGENTS.md)

- Target current macOS APIs without legacy fallbacks; remain a real native SwiftUI/AppKit application, not a web wrapper. [VERIFIED: AGENTS.md:15-16]
- Keep volatile SiriusXM behavior behind repairable client adapters and compatibility tests; views and playback must not construct upstream requests. [VERIFIED: AGENTS.md:17; AGENTS.md:90]
- Keep credentials/session tokens local and Keychain-backed; do not persist or log secret-adjacent data. Fail closed for unknown authentication/control behavior. [VERIFIED: AGENTS.md:18-19; AGENTS.md:91-93]
- Preserve the declarative, non-executable skin boundary and prefer platform/system solutions before a new dependency. [VERIFIED: AGENTS.md:20; AGENTS.md:23; AGENTS.md:94-95]
- Use the established Xcode/Swift toolchain and strict concurrency; the project configures `MACOSX_DEPLOYMENT_TARGET = 26.0` and `SWIFT_STRICT_CONCURRENCY = complete`. [VERIFIED: AGENTS.md:39-46; SiriusMac.xcodeproj/project.pbxproj:100-101]
- Phase work must stay in the GSD workflow; this research output is the authorized planning artifact. [VERIFIED: AGENTS.md:151-157]

## Summary

Phase 3 should promote the current authentication-local composition into an application-owned listening composition, then inject its one `PlaybackCoordinator`, one listening model, one local library store, and one system-media integration into two singleton SwiftUI `Window` scenes. The present composition already creates a concrete coordinator with system network/power observers; creating that composition inside each scene would violate the one-player requirement. [VERIFIED: SiriusMac/Authentication/AuthenticationView.swift:129-184]

The primary correctness boundary is confirmed playback. The coordinator already publishes semantic state only after AVFoundation observation, while the current metadata model follows browse selection. Split those responsibilities: browse selection remains local to the library; active-channel metadata, recents, compact-player content, and system Now Playing derive from confirmed playback. [VERIFIED: SiriusMac/Listening/PlaybackCoordinator.swift:476-516; SiriusMac/Catalog/ListeningPresentationModel.swift:87-110; SiriusMac/Catalog/ListeningPresentationModel.swift:165-179]

**Primary recommendation:** Build a single app-owned `ListeningSessionController` and make windows, commands, persistence, media controls, and presentation renderers thin consumers of its semantic state. [VERIFIED: 03-CONTEXT.md; SiriusMac/Authentication/AuthenticationView.swift:129-184]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Compact and library windows | Frontend Server (SwiftUI app scenes) | Browser / Client (AppKit window bridge) | SwiftUI owns views/scenes; only native window-level/frame/close hooks require AppKit. [CITED: https://developer.apple.com/documentation/swiftui/window/init(_:id:content:)] |
| One playback lifetime | API / Backend (app-owned coordinator) | Frontend Server | It serializes commands and owns the already-existing AVPlayer; neither view may own it. [VERIFIED: SiriusMac/Listening/PlaybackCoordinator.swift:476-555] |
| Favorites, recents, tab/top-most preference | Database / Storage | API / Backend | Local SwiftData holds non-secret records; observable store applies local business rules. [CITED: https://developer.apple.com/documentation/swiftdata/modelcontext] |
| Previous/next queue and reveal | API / Backend | Frontend Server | Deterministic queue selection and entitlement validation are app state; the library only renders/reveals. [VERIFIED: 03-CONTEXT.md; Packages/SiriusXMClient/Sources/SiriusXMClient/Public/LiveListeningModels.swift:232-250]
| System Now Playing/media keys | API / Backend | OS service | One integration maps confirmed app state to MediaPlayer and routes accepted commands back into the command router. [CITED: https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter] |
| Keyboard, menus, VoiceOver semantics | Frontend Server | Browser / Client | SwiftUI commands/native controls own semantic focus; narrow AppKit provides announcements when needed. [CITED: https://developer.apple.com/documentation/swiftui/commandmenu] |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | Xcode 26.6 / macOS 26.5 SDK | Singleton app scenes, views, commands, focus | Existing app UI and Apple-supported `Window`/`openWindow` APIs suit the two-window model. [CITED: https://developer.apple.com/documentation/swiftui/window/init(_:id:content:)] |
| AppKit | macOS 26.5 SDK | Compact close policy, frame autosave, always-on-top window level, announcements | Apple provides `NSWindow.level`, frame autosave, `NSWindowDelegate`, and accessibility notifications. [CITED: https://developer.apple.com/documentation/appkit/nswindow] |
| SwiftData | macOS 26.5 SDK | Local favorites and recents | `ModelContainer`/`ModelContext` are the native persistence lifecycle for small app-local models. [CITED: https://developer.apple.com/documentation/swiftdata/modelcontainer] |
| MediaPlayer | macOS 26.5 SDK | Now Playing and media-key/Control Center commands | The system shared command center and Now Playing info center provide the required integration. [CITED: https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter] |
| AVFoundation | macOS 26.5 SDK | Existing live-audio playback | Retain the established `AVPlayer` runtime; it is already the sole playback runtime. [VERIFIED: SiriusMac/Listening/PlaybackCoordinator.swift:266-319] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Observation | OS-bundled | Shared semantic-state updates | Retain the current `@Observable` main-actor model pattern for composition, store, queue, and system-media publisher. [VERIFIED: SiriusMac/Catalog/ListeningPresentationModel.swift:37-55] |
| XCTest | Xcode 26.6 | Offline unit/integration coverage | Use for store, queue, coordinator-observation, media-command mapping, and AppKit adapter seams; add UI tests only if target/config support is introduced. [VERIFIED: SiriusMac.xcodeproj/xcshareddata/xcschemes/SiriusMac.xcscheme:13-17] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Singleton SwiftUI `Window` scenes | `WindowGroup` | `WindowGroup` can create multiple independently stateful windows; Apple documents that targeted `Window` scenes are brought forward, matching the no-duplicate library requirement. [CITED: https://developer.apple.com/documentation/swiftui/openwindow] |
| SwiftData local store | A custom JSON/UserDefaults persistence layer | A custom store adds ordering, migration, atomicity, and data-validation work while SwiftData already coordinates model persistence; never use it for secrets. [CITED: https://developer.apple.com/documentation/swiftdata/modelcontext] |
| MediaPlayer integration | Custom global media-key monitor | The system command center is the supported control surface and supports disabling unsupported commands. [CITED: https://developer.apple.com/documentation/mediaplayer/mpremotecommand] |

**Installation:** No external package installation is required. All recommended frameworks ship with the installed Xcode/macOS SDK. [VERIFIED: xcodebuild -version; xcrun --sdk macosx --show-sdk-version]

## Architecture Patterns

### System Architecture Diagram

```text
Authenticated app launch
        |
        v
Application-owned ListeningSessionController
  | owns one PlaybackCoordinator + one ListeningPresentationModel
  | owns one LibraryStore + QueueController + SystemMediaController
  | observes confirmed playback + active-channel metadata
  |
  +--> Compact Window -----> semantic compact renderer -----> native controls/menu
  |          |                         |                            |
  |          |                         +--> AppKit Window adapter    |
  |          |                              (frame/level/close)      |
  |          +--------------------------------------------------------+
  |
  +--> Library Window -----> Channels/Categories/Favorites/Recents --+--> command router
  |          |                       |                                |
  |          +--> selection/search/reveal only      tune/pause/next/previous
  |
  +--> SwiftData LibraryStore (allow-listed local snapshots only)
  |
  +--> MediaPlayer: confirmed state -> Now Playing; remote commands -> command router
                                      (no seek, scrub, or Stop)
```

### Recommended Project Structure

```text
SiriusMac/
├── App/                 # App-owned session composition and commands
├── Listening/            # Existing coordinator plus queue/system-media integration
├── Library/              # SwiftData models, local store, collections, library view
├── Player/               # Semantic presentation model, slots, compact renderer
├── Windows/              # Focused NSWindow adapter and scene lifecycle bridges
└── Accessibility/        # Announcements and focus helpers owned by native UI
```

### Pattern 1: App-owned composition, scene-injected references

**What:** Construct the coordinator once at the `App` boundary; scene roots receive references but never construct services. Existing code already centralizes the concrete client/coordinator and passes the coordinator into `ListeningPresentationModel`. [VERIFIED: SiriusMac/Authentication/AuthenticationView.swift:129-184]

**Use:** Replace the current single `WindowGroup`/`AuthenticationView` container with two `Window` scenes backed by the same controller. Use a unique scene id and `openWindow(id:)` to bring the library forward. Apple documents that `Window` is a title-plus-unique-id scene and `openWindow` brings an existing `Window` to the front. [CITED: https://developer.apple.com/documentation/swiftui/window/init(_:id:content:); https://developer.apple.com/documentation/swiftui/openwindow]

### Pattern 2: Confirmed-state fan-out

**What:** A single observer derives active channel, system playback state, recents, compact content, and announcements from `PlaybackCoordinator.state`, not button intent. [VERIFIED: 03-CONTEXT.md; SiriusMac/Listening/PlaybackCoordinator.swift:476-516]

**Use:** Move metadata activation away from `ListeningPresentationModel.select(_:)`; that method currently calls `metadataPresentation.select(channelID)` even though it must remain browse-only. [VERIFIED: SiriusMac/Catalog/ListeningPresentationModel.swift:87-95]

### Pattern 3: Captured queue with runtime eligibility filtering

**What:** Capture ordered stable IDs from the collection at a user tune. Preserve that array across tab/search/favorite changes; on Previous/Next, walk it deterministically, accepting only ids still present in the current entitled lineup. Fall back to the current full lineup if no captured candidate remains. [VERIFIED: 03-CONTEXT.md; Packages/SiriusXMClient/Sources/SiriusXMClient/Public/LiveListeningModels.swift:232-250]

**Use:** Do not persist the queue. It is live app state that must be checked against the current catalog before tuning because catalog snapshots cannot authorize playback.

<!-- DATA_Q4N8V2KZ_START -->
`public var allowsPlaybackAuthorization: Bool { false }`
<!-- DATA_Q4N8V2KZ_END -->
[VERIFIED: Packages/SiriusXMClient/Sources/SiriusXMClient/Public/LiveListeningModels.swift:232-250]

### Pattern 4: Local allow-list persistence

**What:** Keep `LibraryStore` as the only persistence facade. It stores a favorite by stable identity and a recent record with stable identity plus allow-listed presentation fields: name, display number, category, and successful-listen timestamp. Do not persist artwork reference/data, metadata text, playback state, queue, credentials, session values, client values, or media resources. [VERIFIED: AGENTS.md:18; AGENTS.md:91; Packages/SiriusXMClient/Sources/SiriusXMClient/Public/LiveListeningModels.swift:174-200]

<!-- DATA_B7T1L5RX_START -->
`public let id: LiveChannelID`
`public let name: String?`
`public let description: String?`
`public let displayNumber: Int?`
`public let category: String?`
`public let artwork: ChannelArtworkReference?`
<!-- DATA_B7T1L5RX_END -->
[VERIFIED: Packages/SiriusXMClient/Sources/SiriusXMClient/Public/LiveListeningModels.swift:174-200]

Use a single `ModelContainer` injected into both scenes and make the store expose observable projections; Apple documents that a model container coordinates persistent storage and a context performs fetch/insert/delete/save. [CITED: https://developer.apple.com/documentation/swiftdata/modelcontainer; https://developer.apple.com/documentation/swiftdata/modelcontext]

### Pattern 5: Narrow system bridges

**What:** Keep AppKit and MediaPlayer access in focused adapters owned by the controller, with closures/protocols for deterministic tests. [VERIFIED: AGENTS.md:41-46; SiriusMac/Listening/PlaybackCoordinator.swift:249-319]

**Use:** The compact-window adapter may set normal/floating `NSWindow.Level`, a unique frame-autosave name, and close-to-terminate behavior. The system-media adapter registers handlers once, retains/removes their opaque targets, updates `MPNowPlayingInfoCenter.default().nowPlayingInfo`, and sets macOS `playbackState` on every confirmed start/halt. [CITED: https://developer.apple.com/documentation/appkit/nswindow; https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter/playbackstate]

### Anti-Patterns to Avoid

- **Scene-local `@State` composition:** each `WindowGroup` instance owns independent state, which can create an extra coordinator/player. [CITED: https://developer.apple.com/documentation/swiftui/windowgroup]
- **Selection-driven Now Playing:** a browse click must not change compact/system metadata or playback. [VERIFIED: SiriusMac/Catalog/ListeningPresentationModel.swift:87-110]
- **Recent on tune intent:** add/update only when the coordinator confirms `.playing`, never while resolution is pending or fails. [VERIFIED: Packages/SiriusXMClient/Sources/SiriusXMClient/Public/LiveListeningModels.swift:271-295]
- **Unbounded/automatic system commands:** disable seek, skip interval, playback-position, and Stop commands instead of supplying handlers. [CITED: https://developer.apple.com/documentation/mediaplayer/mpremotecommand]
- **Skin-owned semantics:** renderer slots may affect presentation only; actions, keyboard commands, accessibility labels, and system metadata stay native/app-owned. [VERIFIED: AGENTS.md:20; AGENTS.md:94]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Media key / Control Center delivery | Global keyboard hooks or a media-key listener | `MPRemoteCommandCenter.shared()` | System delivers supported remote events and can hide disabled commands. [CITED: https://developer.apple.com/documentation/mediaplayer/mpremotecommand] |
| Now Playing surface | A custom status/menu replacement | `MPNowPlayingInfoCenter.default()` | System owns presentation, accessory support, and Control Center layout. [CITED: https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter] |
| Local record store | Custom serialized state file | SwiftData `ModelContainer`/`ModelContext` | Platform persistence coordinates model fetches, mutations, and saves. [CITED: https://developer.apple.com/documentation/swiftdata/modelcontext] |
| Window frame persistence | Custom screen-coordinate archival | `NSWindow` frame autosave | AppKit stores/restores named frames and supports non-resizable restoration. [CITED: https://developer.apple.com/documentation/appkit/nswindow] |
| Accessibility announcements | Ad hoc speech or an unlabelled toast | Native SwiftUI accessibility plus `NSAccessibility.post` | The system delivers an announcement to assistive apps only when appropriate. [CITED: https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/notification/announcementrequested] |

**Key insight:** The phase’s custom work is product semantics (stable queue, non-secret local model, presentation slots), not a replacement for macOS persistence, windowing, media controls, audio routing, or accessibility services. [VERIFIED: 03-CONTEXT.md; AGENTS.md:23; AGENTS.md:95]

## Common Pitfalls

### Pitfall 1: A second player is accidentally composed

**What goes wrong:** Reopening the library or entering each window scene creates another `AuthenticationComposition` and `PlaybackCoordinator`. **Avoid:** own composition at `App` scope and use singleton `Window` scenes. **Warning sign:** a regression test observes more than one runtime/player or a library reopen interrupts audio. [VERIFIED: SiriusMac/Authentication/AuthenticationView.swift:9-16; SiriusMacTests/ListeningCompositionTests.swift:176-199]

### Pitfall 2: Metadata changes when browsing

**What goes wrong:** Current selection calls metadata selection, which violates independent browse/playback and can publish incorrect system content. **Avoid:** make active playback the metadata source; leave browse selection in library state. **Warning sign:** one click changes Now Playing without a confirmed tune. [VERIFIED: SiriusMac/Catalog/ListeningPresentationModel.swift:87-95]

### Pitfall 3: Remote command handlers outlive or multiply with windows

**What goes wrong:** Each view installation adds a target, producing duplicate previous/next/toggle commands. **Avoid:** one retained system-media controller at composition scope; remove its target tokens on app shutdown. **Warning sign:** one media key produces two coordinator commands. [CITED: https://developer.apple.com/documentation/mediaplayer/mpremotecommand]

### Pitfall 4: System UI shows optimistic/unsupported controls

**What goes wrong:** App publishes a playing state before AVFoundation confirms it, or exposes seek/Stop for live radio. **Avoid:** observe the current semantic state and set unsupported `MPRemoteCommand.isEnabled = false`. **Warning sign:** Control Center says Playing while coordinator is idle/unavailable. [VERIFIED: SiriusMac/Listening/PlaybackCoordinator.swift:476-516; CITED: https://developer.apple.com/documentation/mediaplayer/mpremotecommand/isenabled]

### Pitfall 5: Persisted local data becomes a secret side channel

**What goes wrong:** A record stores an artwork URL, raw metadata response, session-linked value, stream value, or diagnostic object. **Avoid:** one explicitly allow-listed snapshot mapping and source scan tests. **Warning sign:** a persistence model imports client/session/transport types. [VERIFIED: AGENTS.md:18; AGENTS.md:91-92]

### Pitfall 6: Accessibility is deferred to the skin

**What goes wrong:** Canvas/bitmap decoration becomes the interactive or semantic control surface. **Avoid:** native controls remain accessible and semantic slots decorate around them; use `AccessibilityFocusState`, app menus, native labels/values, and native announcements. **Warning sign:** the same action cannot be reached by keyboard and VoiceOver without the selected visual renderer. [CITED: https://developer.apple.com/documentation/swiftui/accessibilityfocusstate; https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/notification/announcementrequested]

## Code Examples

Verified patterns from official sources:

### Singleton library scene activation

Use a `Window` scene with a unique identifier and call `openWindow(id:)` from the compact-player/library command surface. Apple documents that a targeted `Window` is ordered front rather than recreated; this is the required reopen behavior. [CITED: https://developer.apple.com/documentation/swiftui/window/init(_:id:content:); https://developer.apple.com/documentation/swiftui/openwindow]

### Confirmed system-media publishing

The system-media adapter maps only observed semantic playback transitions to `MPNowPlayingInfoCenter` and updates `playbackState` every time playback begins or halts on macOS. It enables only Play/Pause, Previous, and Next and returns a failed command status when queue validation cannot accept a command. [CITED: https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter/playbackstate; https://developer.apple.com/documentation/mediaplayer/mpremotecommand]

### Accessible state change

Keep a focused native element for the library/compact surface and post one native announcement after confirmed tune/play/pause/favorite/failure transitions. Apple documents `NSAccessibility.post(element:notification:userInfo:)` with announcement and priority user-info keys. [CITED: https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/notification/announcementrequested]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| A single `WindowGroup` contains authentication and the listening browser | Two singleton `Window` scenes consume one app composition | Phase 3 | Separates compact/libraries without multiplying playback state. [VERIFIED: SiriusMac/SiriusMacApp.swift:4-19; 03-CONTEXT.md] |
| Browse selection starts metadata | Confirmed active playback starts metadata/system publishing | Phase 3 | Prevents a browse click from changing audible/system identity. [VERIFIED: SiriusMac/Catalog/ListeningPresentationModel.swift:87-95; 03-CONTEXT.md] |
| Generic listening controls include Tune/Pause/Resume/Stop | Live-specific primary controls are Previous/Play-Pause/Next; system Stop/seek are disabled | Phase 3 | Matches the locked live-radio system surface. [VERIFIED: SiriusMac/Catalog/ListeningView.swift:82-101; 03-CONTEXT.md] |

**Deprecated/outdated:** `ListeningView` is a semantic baseline, not the Phase 3 final window structure; split it rather than carrying its single-window controls and selection-coupled metadata forward. [VERIFIED: SiriusMac/Catalog/ListeningView.swift:5-43; SiriusMac/Catalog/ListeningPresentationModel.swift:87-95]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | A no-wrap policy is the correct deterministic behavior at either end of a captured queue. | Architecture Patterns | User decision specifies deterministic traversal but does not explicitly choose wrap behavior; planner should preserve the approved UI contract’s no-wrap instruction or seek confirmation before changing it. |

## Open Questions (RESOLVED)

1. **RESOLVED — Compact close uses a narrow exact-window AppKit lifecycle adapter.**
   - The isolated `CompactWindowController` bridge attaches to the compact `NSWindow` and observes that exact window's `willCloseNotification`; it requests `NSApplication.terminate(nil)` through an injected terminator. The library role never requests termination. [CITED: https://developer.apple.com/documentation/appkit/nswindow]
   - SwiftUI retains scene and internal window-delegate ownership: the adapter does not replace the application delegate or `NSWindowDelegate`, and it owns no playback/session state. Normal `NSApplication.willTerminateNotification` handling invokes the app-owned session controller's idempotent shutdown so compact close follows the ordinary application-termination path.

2. **RESOLVED — Initial library opening uses singleton scene activation from app-owned session readiness.**
   - The app-owned `ListeningSessionController`/authentication composition exposes the entitled transition; the compact/authenticated scene observes its first successful transition and calls `openWindow(id:)` once for the uniquely identified library `Window`. [CITED: https://developer.apple.com/documentation/swiftui/openwindow]
   - Every later Show Library, Command-L, reopen, or reauthentication activation targets that same scene id and existing library scene/state. Scene activation never constructs another `AuthenticationComposition`, `ListeningSessionController`, `PlaybackCoordinator`, or AVFoundation runtime.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Xcode / `xcodebuild` | Build and app tests | ✓ | Xcode 26.6 (17F113) | — |
| Swift | App and package compilation | ✓ | Swift 6.3.3 | — |
| macOS SDK | SwiftUI/AppKit/MediaPlayer/SwiftData | ✓ | 26.5 | — |
| External package manager/service | Phase 3 implementation | Not required | — | System frameworks only |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** None.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest via Xcode 26.6 |
| Config file | `SiriusMac.xcodeproj/xcshareddata/xcschemes/SiriusMac.xcscheme` |
| Quick run command | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` |
| Full suite command | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` |

Baseline: the full command passed **113 tests** on 2026-08-21. [VERIFIED: local xcodebuild execution]

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| LIBR-01 | Favorite changes are shared immediately and key by stable ID | unit | full Xcode test command | ❌ Wave 0 |
| LIBR-02 | Confirmed playback inserts/deduplicates/caps recents | unit | full Xcode test command | ❌ Wave 0 |
| LIBR-03 | Persistence allow-list excludes all secret-adjacent values | unit/source scan | full Xcode test command | ❌ Wave 0 |
| MAC-01 | Closing library/backgrounding retains exactly one healthy player | integration/manual | full Xcode test command + manual app run | ❌ Wave 0 |
| MAC-02 | Remote command router supports only chosen commands | unit/integration | full Xcode test command | ❌ Wave 0 |
| MAC-03 | System-media publisher uses confirmed coordinator/metadata states | unit | full Xcode test command | ❌ Wave 0 |
| MAC-04 | Existing AVFoundation runtime remains sole audio output path | source scan/manual | full Xcode test command + audio-device check | ✅ partial (`ListeningCompositionTests`) |
| UI-01 | One fixed compact window has semantic slots and primary controls | UI state/source scan/manual | full Xcode test command + manual app run | ❌ Wave 0 |
| UI-02 | Library tab/filter/select/tune interaction works | unit/UI state/manual | full Xcode test command + manual app run | ❌ Wave 0 |
| UI-03 | Scene reopen/close does not compose a second coordinator | integration/manual | full Xcode test command + manual app run | ❌ Wave 0 |
| UI-04 | Captured queue is deterministic and reveal preserves selection | unit | full Xcode test command | ❌ Wave 0 |
| ACCS-01 | Commands, labels/values, focus and announcements are native/correct | source scan/UI state/manual VoiceOver | full Xcode test command + manual VoiceOver run | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'`
- **Per wave merge:** same full suite
- **Phase gate:** full suite green plus manual checks for window lifecycle, Control Center/media keys, audio routing, and VoiceOver.

### Wave 0 Gaps

- [ ] `SiriusMacTests/LibraryStoreTests.swift` — favorites, deduped successful recents, 50-entry cap, clear, and secret allow-list.
- [ ] `SiriusMacTests/PlaybackQueueTests.swift` — captured ordering, bounds, catalog filtering, fallback, and reveal payload.
- [ ] `SiriusMacTests/SystemMediaControllerTests.swift` — confirmed publishing and remote command enablement/one-registration behavior.
- [ ] `SiriusMacTests/ListeningSessionControllerTests.swift` — one composition fan-out and selection-vs-active-metadata separation.
- [ ] `SiriusMacTests/AccessibilityContractTests.swift` — keyboard/menu/identifier/label/value and native-semantic source contracts.
- [ ] Manual acceptance checklist — compact close quits, library close preserves audio, reopen reuses state, media keys/Control Center, normal output routing, VoiceOver, Reduce Motion.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Preserve Phase 1/2 authenticated composition; phase UI does not create alternate sign-in/session paths. [VERIFIED: SiriusMac/Authentication/AuthenticationView.swift:129-184] |
| V3 Session Management | yes | Reuse existing coordinator/session teardown and do not persist session material in library records. [VERIFIED: SiriusMac/Listening/PlaybackCoordinator.swift:599-607; AGENTS.md:18] |
| V4 Access Control | yes | Queue/catalog is browse-only; every tune remains delegated to client/coordinator authorization. [VERIFIED: Packages/SiriusXMClient/Sources/SiriusXMClient/Public/LiveListeningModels.swift:232-250; SiriusMac/Listening/PlaybackCoordinator.swift:552-555] |
| V5 Input Validation | yes | Allow-list bounded local snapshot fields and reject/ignore absent or malformed persisted records; no raw provider objects. [VERIFIED: AGENTS.md:17-18; Packages/SiriusXMClient/Sources/SiriusXMClient/Public/LiveListeningModels.swift:174-200] |
| V6 Cryptography | no new cryptography | Reuse Keychain-only credential storage; no secrets enter SwiftData/UserDefaults. [VERIFIED: AGENTS.md:18; AGENTS.md:91] |

### Known Threat Patterns for native macOS listening

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Secret-adjacent data written to library storage/logs | Information Disclosure | Explicit snapshot mapper, type-boundary tests, and no client/session/transport fields in persistence. [VERIFIED: AGENTS.md:18; AGENTS.md:91-92] |
| A stale/removed channel is tuned by previous/next | Elevation of Privilege | Filter captured IDs against the current entitled lineup, then let existing client authorization decide every tune. [VERIFIED: Packages/SiriusXMClient/Sources/SiriusXMClient/Public/LiveListeningModels.swift:232-250] |
| Duplicate remote handler or window creates repeated commands/player | Denial of Service | Composition-owned singleton controller; register handlers once and remove them on shutdown. [CITED: https://developer.apple.com/documentation/mediaplayer/mpremotecommand] |
| Skin data controls semantic actions or accessibility | Tampering | Keep renderer data declarative; native action and accessibility tree are app-owned. [VERIFIED: AGENTS.md:20; AGENTS.md:94] |

## Sources

### Primary (HIGH confidence)

- [SiriusMac playback coordinator](SiriusMac/Listening/PlaybackCoordinator.swift) — ownership, confirmed state, command/teardown behavior.
- [SiriusMac listening model](SiriusMac/Catalog/ListeningPresentationModel.swift) — selection/metadata coupling and coordinator observation.
- [SiriusMac composition](SiriusMac/Authentication/AuthenticationView.swift) — current one-client/one-coordinator integration boundary.
- [SiriusXM public listening models](Packages/SiriusXMClient/Sources/SiriusXMClient/Public/LiveListeningModels.swift) — stable identity, browse-only catalog, semantic playback/metadata boundaries.
- Local `xcodebuild test` run — 113/113 passing baseline.

### Secondary (MEDIUM confidence)

- [SwiftUI Window](https://developer.apple.com/documentation/swiftui/window/init(_:id:content:)) and [openWindow](https://developer.apple.com/documentation/swiftui/openwindow) — singleton scene id and reopen behavior.
- [SwiftUI WindowGroup](https://developer.apple.com/documentation/swiftui/windowgroup) and [WindowResizability](https://developer.apple.com/documentation/swiftui/windowresizability) — independent group state and fixed content-size behavior.
- [NSWindow](https://developer.apple.com/documentation/appkit/nswindow) and [NSWindowDelegate close hook](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowshouldclose(_:)) — frame, level, and close behavior.
- [MPRemoteCommandCenter](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter), [MPRemoteCommand](https://developer.apple.com/documentation/mediaplayer/mpremotecommand), and [MPNowPlayingInfoCenter](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter) — system media ownership.
- [SwiftData ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer) and [ModelContext](https://developer.apple.com/documentation/swiftdata/modelcontext) — app-local persistence.
- [AccessibilityFocusState](https://developer.apple.com/documentation/swiftui/accessibilityfocusstate), [announcementRequested](https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/notification/announcementrequested), and [accessibilityReduceMotion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion) — native accessibility/focus/motion APIs.

### Tertiary (LOW confidence)

- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — system frameworks are locked in project stack and present in the installed macOS 26.5 SDK.
- Architecture: HIGH — direct inspection found the existing single-coordinator composition and the selection/metadata hazard.
- Pitfalls: HIGH — derived from direct existing behavior plus Apple scene/media documentation.

**Research date:** 2026-08-21
**Valid until:** 2026-09-20 (stable system-framework and codebase planning guidance)
