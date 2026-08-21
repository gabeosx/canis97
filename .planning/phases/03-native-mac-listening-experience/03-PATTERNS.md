# Phase 3: Native Mac Listening Experience - Pattern Map

**Mapped:** 2026-08-21  
**Files analyzed:** 18 planned new/modified files  
**Analogs found:** 13 / 18

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `SiriusMac/SiriusMacApp.swift` | app/scene config | event-driven | `SiriusMac/SiriusMacApp.swift` | exact (modify) |
| `SiriusMac/App/ListeningSessionController.swift` | controller | event-driven | `Authentication/AuthenticationView.swift` | role-match |
| `SiriusMac/Authentication/AuthenticationView.swift` | component | request-response | same file | exact (reshape) |
| `SiriusMac/Catalog/ListeningPresentationModel.swift` | model | request-response | same file | exact (modify) |
| `SiriusMac/Library/LibraryStore.swift` | store/model | CRUD | `Security/KeychainCredentialStore.swift` | partial (safe facade/error boundary) |
| `SiriusMac/Library/PlaybackQueue.swift` | utility/model | transform | `Catalog/ListeningPresentationModel.swift` | partial (stable-ID selection) |
| `SiriusMac/Library/LibraryView.swift` | component | request-response | `Catalog/ListeningView.swift` | role-match |
| `SiriusMac/Player/CompactPlayerPresentation.swift` | model | transform | `Metadata/MetadataPresentationModel.swift` | role-match |
| `SiriusMac/Player/CompactPlayerView.swift` | component | request-response | `Catalog/ListeningView.swift` | role-match |
| `SiriusMac/Listening/SystemMediaController.swift` | service/adapter | event-driven | `Listening/PlaybackCoordinator.swift` | partial |
| `SiriusMac/Windows/CompactWindowController.swift` | controller/adapter | event-driven | none | none |
| `SiriusMac/Accessibility/AccessibilityAnnouncer.swift` | utility/adapter | event-driven | `Catalog/ListeningView.swift` | partial (native semantic controls) |
| `SiriusMac/Metadata/MetadataPresentationModel.swift` | model | streaming | same file | exact (retarget active channel) |
| `SiriusMac/Catalog/ListeningView.swift` | component | request-response | same file | exact (split/deprecate) |
| `SiriusMacTests/LibraryStoreTests.swift` | test | CRUD | `KeychainCredentialStoreTests.swift` | role-match |
| `SiriusMacTests/PlaybackQueueTests.swift` | test | transform | `ListeningCompositionTests.swift` | role-match |
| `SiriusMacTests/SystemMediaControllerTests.swift` | test | event-driven | `ListeningCompositionTests.swift` | role-match |
| `SiriusMacTests/ListeningSessionControllerTests.swift`, `AccessibilityContractTests.swift` | test | event-driven/request-response | `ListeningCompositionTests.swift`, `MetadataPresentationTests.swift` | role-match |

## Pattern Assignments

### `SiriusMac/SiriusMacApp.swift` (app/scene config, event-driven)

**Analog:** `SiriusMac/SiriusMacApp.swift:4-19`.

```swift
@main
struct SiriusMacApp: App {
    var body: some Scene {
        WindowGroup("Sirius Mac") {
            if SiriusMacLaunchMode.isUnitTestHost() { Color.clear ... }
            else { AuthenticationView() ... }
        }
    }
}
```

Keep the unit-test-host branch (`:8-15`) inert. Replace only the production `WindowGroup` composition with two uniquely identified singleton `Window` scenes and inject one app-owned session controller; do not create `@State` controller/coordinator per scene.

### `SiriusMac/App/ListeningSessionController.swift` and `AuthenticationView.swift` (controller/component, event-driven)

**Analog:** `SiriusMac/Authentication/AuthenticationView.swift:4-17, 129-184`.

```swift
@State private var listeningModel: ListeningPresentationModel

init() {
    let composition = AuthenticationComposition()
    _listeningModel = State(initialValue: ListeningPresentationModel(
        flow: composition.listeningFlow,
        playbackCoordinator: composition.playbackCoordinator
    ))
}

@MainActor
struct AuthenticationComposition {
    let listeningFlow: any ListeningFlow
    let playbackCoordinator: PlaybackCoordinator
}
```

Lift this construction from a view into one `@MainActor @Observable` application-owned controller. The controller retains exactly one `AuthenticationComposition`, coordinator, catalog/listening state, metadata model, library store, queue, and system-media adapter. Windows consume references. Preserve sign-out ordering: `listeningModel.reset()` before `model.signOut()` (`:23-28`) and `clearLocalSession()` (`:121-125`).

### `SiriusMac/Catalog/ListeningPresentationModel.swift` and `Metadata/MetadataPresentationModel.swift` (models, request-response/streaming)

**Analogs:** `ListeningPresentationModel.swift:37-56, 87-110, 165-179`; `MetadataPresentationModel.swift:37-90, 104-119`.

```swift
@MainActor
@Observable
final class ListeningPresentationModel { ... }

func select(_ channelID: LiveChannelID) {
    selectedChannelID = channelID
    metadataPresentation.select(channelID)
}

withObservationTracking { _ = playbackCoordinator.state } onChange: { ... }
```

Keep the main-actor observable, injected-flow, task-generation pattern. Change browse selection to update only `selectedChannelID`; confirmation observation must select/clear metadata from the coordinator's confirmed active channel. `MetadataPresentationModel` already cancels stale work and guards every async result by generation (`:66-76`, `:104-119`); retain this pattern. No view may invoke provider flows, metadata flows, or AVFoundation directly.

### `SiriusMac/Library/LibraryStore.swift` (store, CRUD)

**Analog:** `SiriusMac/Security/KeychainCredentialStore.swift:5-10, 65-109, 117-146`.

```swift
/// ... deliberately exposes only safe error classifications.
final class KeychainCredentialStore: CredentialStore, @unchecked Sendable {
    func erase() async throws { try removeStoredCredential() }
    static func classify(status: OSStatus) -> StatusClassification { ... }
}
```

There is no SwiftData precedent. Copy the narrow facade and closed outcome/error style, not Keychain APIs or `@unchecked Sendable`. Make this the only local-persistence facade and persist an explicit allow-list: stable ID, name, display number, category, favorite flag/recent timestamp, selected tab, compact frame, and Always-on-Top preference. Exclude artwork/reference/data, metadata, playback state, queue, credentials, tokens, stream URLs, raw client data, and diagnostics. Use one injected `ModelContainer` for both scenes.

### `SiriusMac/Library/PlaybackQueue.swift` (utility/model, transform)

**Analog:** `SiriusMac/Catalog/ListeningPresentationModel.swift:87-110` and `SiriusMac/Listening/PlaybackCoordinator.swift:552-556`.

```swift
func select(_ channelID: LiveChannelID) { selectedChannelID = channelID }

func tune(_ channelID: LiveChannelID) async {
    let commandGeneration = supersedeActiveWork(clearItem: true)
    selectedChannelID = channelID
    await resolveAndInstall(channelID, commandGeneration: commandGeneration)
}
```

Capture `[LiveChannelID]` when an explicit tune begins. Keep queue navigation pure/deterministic: filter candidates through the current entitled catalog, do not wrap, disable an unavailable end, and return a revealable ID. Never persist the captured queue; send the selected candidate to the existing coordinator so authorization remains there.

### `SiriusMac/Library/LibraryView.swift` and `Player/CompactPlayerView.swift` (components, request-response)

**Analog:** `SiriusMac/Catalog/ListeningView.swift:7-63, 82-112, 188-218`.

```swift
struct ListeningView: View {
    @Bindable var model: ListeningPresentationModel
    var channelSelection: Binding<LiveChannelID?> { ... }
    List(snapshot.channels, id: \.id, selection: channelSelection) { channel in
        ChannelRow(channel: channel).tag(channel.id)
    }
}
```

Split the baseline instead of duplicating it. Bind library click/arrow navigation to browse selection only; double-click/Return calls the controller tune action. Preserve stable identifiers, `.tag(channel.id)`, fixed row semantics, and native `List`/toolbar/search. Compact player consumes a renderer-independent semantic presentation value and sends controller actions only; it does not own coordinator, metadata, queue, persistence, media integration, or accessibility policy. Replace generic Tune/Pause/Resume/Stop controls (`:82-101`) with Previous, confirmed Play/Pause, Next; do not add seek or Stop.

### `SiriusMac/Player/CompactPlayerPresentation.swift` (model, transform)

**Analog:** `SiriusMac/Metadata/MetadataPresentationModel.swift:125-131` and `ListeningView.swift:104-155`.

```swift
private func presentationText(for program: LiveProgramMetadata?, channelID: LiveChannelID) -> LiveMetadataText {
    guard let program, !program.title.isEmpty else { return .channelFallback(channelID) }
    if let artist = program.artist, !artist.isEmpty { return .current("\(artist) — \(program.title)") }
    return .current(program.title)
}
```

Use a closed, declarative semantic model: background, channel identity, artwork, primary/secondary metadata, confirmed status, favorite state, transport availability, and error/recovery action. Preserve confirmed metadata fallbacks; skin renderers may decorate slots but cannot supply metadata/system text or actions.

### `SiriusMac/Listening/SystemMediaController.swift` (service/adapter, event-driven)

**Analog:** `SiriusMac/Listening/PlaybackCoordinator.swift:479-516, 820-889`.

```swift
@MainActor
@Observable
final class PlaybackCoordinator {
    private(set) var state: LivePlaybackState = .idle
    private(set) var selectedChannelID: LiveChannelID?
}

private func publishPlaying(...) { ... state = .playing(channelID) }
private func publishObservedFailure(_ failure: LiveListeningFailure) {
    state = .unavailable(failure)
}
```

No MediaPlayer analog exists. Mirror the coordinator's one-owner, main-actor, confirmed-state discipline: register retained remote-command targets once in the session controller; route only play/pause/previous/next through controller closures; remove targets at shutdown. Publish `MPNowPlayingInfoCenter` only from observed confirmed playback plus active metadata. Disable seek, skip interval, change-position, and Stop rather than handling them. Clear system playing state on terminal failure/no active channel.

### `SiriusMac/Windows/CompactWindowController.swift` and `Accessibility/AccessibilityAnnouncer.swift` (adapters, event-driven)

**Analog:** `SiriusMac/Catalog/ListeningView.swift:82-101, 210-217`.

```swift
Button("Pause") { _ = model.pausePlayback() }
    .accessibilityIdentifier("listening.pause")
    .accessibilityLabel("Pause playback")
...
.accessibilityLabel(accessibilityName)
```

No AppKit window or announcement adapter currently exists. Keep both narrow, injectable, and controller-owned: window bridge alone handles fixed size, frame autosave/onscreen validation, normal/floating level, and compact-close-to-terminate; accessibility bridge alone posts once per confirmed semantic transition. Native buttons/menu commands keep explicit identifiers, labels, values, tooltips, keyboard shortcuts, focus, and reduced-motion behavior regardless of renderer.

## Test Patterns

### `LibraryStoreTests.swift`, `PlaybackQueueTests.swift`, `SystemMediaControllerTests.swift`, `ListeningSessionControllerTests.swift`

**Analog:** `SiriusMacTests/ListeningCompositionTests.swift:6-103, 105-115`.

```swift
@MainActor
final class SemanticListeningPresentationTests: XCTestCase {
    func testRefreshIsSingleFlightAndPublishesTheSemanticSnapshot() async throws {
        let flow = ControlledCatalogFlow()
        let model = ListeningPresentationModel(flow: flow)
        ...
        XCTAssertEqual(model.state.snapshot?.channels.map(\.id), [LiveChannelID("fixture-current")])
    }
}
```

Use `XCTest`, `@MainActor` UI/controller tests, deterministic fakes/actors, and semantic fixture IDs. Test observed confirmation rather than command intent; queue bounds/filter/fallback; one-session fan-out; store dedupe/cap/clear and allow-list; remote command registration and enablement.

### `AccessibilityContractTests.swift`

**Analog:** `SiriusMacTests/MetadataPresentationTests.swift:7-40`.

```swift
let source = try String(contentsOf: root.appending(path: "SiriusMac/Catalog/ListeningView.swift"), encoding: .utf8)
XCTAssertTrue(buttonDefinition.contains(".accessibilityIdentifier(\"\\(control.identifier)\")"))
XCTAssertTrue(buttonDefinition.contains(".accessibilityLabel(\"\\(control.label)\")"))
```

Follow the existing source-contract tests for stable identifiers/labels, supplemented by behavior tests for confirmed announcements and keyboard command routing. Do not test AppKit/MediaPlayer globals directly without an injected wrapper.

## Shared Patterns

### Single playback ownership and confirmed fan-out

**Sources:** `AuthenticationView.swift:129-184`; `PlaybackCoordinator.swift:479-556, 820-876`.

The app-level session is the only owner of `PlaybackCoordinator`; views/scenes only receive it. Derive active metadata, recents, semantic player content, accessibility announcements, and Now Playing after coordinator state transitions—especially `.playing(channelID)`—not browse selection or button tapping.

### Main-actor observable state with cancellable async work

**Sources:** `ListeningPresentationModel.swift:37-55, 67-84, 165-179`; `MetadataPresentationModel.swift:37-76, 104-119`.

Use `@MainActor @Observable`, injected protocols, `Task` references, generation checks, cancellation, and `withObservationTracking`. This prevents stale catalog/metadata/playback callbacks from replacing current semantic state.

### Secret-safe storage boundary

**Source:** `KeychainCredentialStore.swift:5-10, 112-146`.

Keep secret material contained in Keychain. Library persistence has an explicit non-secret projection only; fail closed/return classifications rather than transporting provider/session objects into UI or persistence.

### Native semantic accessibility

**Sources:** `ListeningView.swift:82-101, 210-217`; `MetadataPresentationTests.swift:7-40`.

Every essential visible action gets a native control/menu path plus stable accessibility label/value/identifier. Skin-ready presentation is decoration around this semantic layer, never a replacement.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `SiriusMac/Windows/CompactWindowController.swift` | AppKit adapter | event-driven | No current `NSWindow` bridge/frame/level/close-policy code. |
| `SiriusMac/Listening/SystemMediaController.swift` | MediaPlayer adapter | event-driven | No current remote-command or Now Playing integration. |
| `SiriusMac/Library/LibraryStore.swift` | SwiftData store | CRUD | No existing SwiftData model/container/store; use the narrow storage-facade pattern above. |
| `SiriusMac/Accessibility/AccessibilityAnnouncer.swift` | AppKit adapter | event-driven | No current native announcement helper. |
| `SiriusMac/Player/CompactPlayerPresentation.swift` | presentation model | transform | Current view has semantic rendering only; no renderer-independent slots yet. |

## Metadata

**Analog search scope:** `SiriusMac/{Authentication,Catalog,Listening,Metadata,Security}`, `SiriusMacTests`  
**Files scanned:** 9 primary implementation/test analogs  
**Pattern extraction date:** 2026-08-21
