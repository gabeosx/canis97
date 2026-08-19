# Phase 02: Authorized Live Listening - Pattern Map

**Mapped:** 2026-08-19  
**Files analyzed:** 14 planned new/modified files  
**Analogs found:** 14 / 14

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `Packages/SiriusXMClient/Sources/SiriusXMClient/Public/LiveListeningModels.swift` | model | transform | `Public/AuthenticationModels.swift` | role-match |
| `Packages/SiriusXMClient/Sources/SiriusXMClient/Public/SiriusXMClient.swift` | service | request-response | `Public/SiriusXMClient.swift` | exact |
| `Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift` | service | request-response | `InternalAdapters/AuthenticationFlowAdapter.swift` | role-match |
| `Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/SiriusXMRequestContract.swift` | config | request-response | `InternalAdapters/SiriusXMRequestContract.swift` | exact |
| `Packages/SiriusXMClient/Sources/SiriusXMClient/Diagnostics/SafeDiagnosticEvent.swift` | utility | transform | `Diagnostics/SafeDiagnosticEvent.swift` | exact |
| `Packages/SiriusXMClient/Tests/SiriusXMClientTests/LiveCatalogAdapterTests.swift` | test | transform | `SiriusXMClientTests/AuthenticationOutcomeTests.swift` | role-match |
| `Packages/SiriusXMClient/Tests/SiriusXMClientTests/LivePlaybackCoordinatorTests.swift` | test | event-driven | `SiriusXMClientTests/SessionCoordinatorTests.swift` | partial |
| `Packages/SiriusXMClient/Tests/SiriusXMClientTests/MetadataRefreshCoordinatorTests.swift` | test | event-driven | `SiriusXMClientTests/SessionCoordinatorTests.swift` | partial |
| `Packages/SiriusXMClient/Tests/SiriusXMClientTests/SanitizedNativeResponseFixtures.swift` | test | transform | `SiriusXMClientTests/SanitizedNativeResponseFixtures.swift` | exact |
| `SiriusMac/Listening/PlaybackCoordinator.swift` | service | event-driven | `Authentication/AuthenticationPresentationModel.swift` | partial |
| `SiriusMac/Catalog/ListeningPresentationModel.swift` | model | request-response | `Authentication/AuthenticationPresentationModel.swift` | role-match |
| `SiriusMac/Catalog/ListeningView.swift` | component | request-response | `Authentication/AuthenticationView.swift` | role-match |
| `SiriusMac/SiriusMacApp.swift` | config | request-response | `SiriusMac/SiriusMacApp.swift` | exact |
| `SiriusMacTests/ListeningCompositionTests.swift` | test | event-driven | `SiriusMacTests/AuthenticationPresentationModelTests.swift` | role-match |

## Pattern Assignments

### `Packages/SiriusXMClient/Sources/SiriusXMClient/Public/LiveListeningModels.swift` (model, transform)

**Analog:** `Packages/SiriusXMClient/Sources/SiriusXMClient/Public/AuthenticationModels.swift`

**Semantic, secret-safe public types** (lines 3-24, 49-96):

```swift
public struct AuthenticationCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    private let material: Data
    public init(volatileMaterial: Data) { self.material = volatileMaterial }
    public var description: String { "AuthenticationCredential(redacted)" }
    public var debugDescription: String { "AuthenticationCredential(redacted)" }
}

public enum EntitlementAvailability: Sendable, Equatable {
    case unavailable, entitled, authenticatedButNotEntitled
    case rejected, challengeRequired, unsupported, cancelled
}
```

Create immutable `Sendable`/`Equatable` semantic channel, catalog freshness, metadata freshness, and closed listening-failure/result types. Keep all provider fields optional where presentation is not guaranteed. A resolved resource must be opaque/redacted, non-`Codable`, in-memory-only, and made available only through a narrow app-integration seam after the checkpoint establishes a safe mechanism.

### `Packages/SiriusXMClient/Sources/SiriusXMClient/Public/SiriusXMClient.swift` (service, request-response)

**Analog:** same file (lines 7-39, 64-93, 96-127).

```swift
public actor SiriusXMClient {
    private let sessionCoordinator: SessionCoordinator?

    public func entitlement() async -> EntitlementAvailability {
        guard let sessionCoordinator else { return .unavailable }
        return await sessionCoordinator.entitlementAvailability
    }

    public func catalog() -> CatalogAvailability { .unavailable }
    public func metadata() -> MetadataAvailability { .unavailable }
    public func resolveLiveStream() -> LiveStreamResolutionAvailability { .unavailable }
}
```

Replace only the Phase-01 placeholders with typed `async` semantic APIs that consult the active session at operation time. Preserve the actor boundary and do not expose provider URLs, request builders, raw bodies, headers, or unredacted `Error` values. Follow the private verifier’s closed conversion on transport errors (lines 111-125).

### `Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift` (service, request-response)

**Analog:** `Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/AuthenticationFlowAdapter.swift`, exercised by `Tests/SiriusXMClientTests/AuthenticationOutcomeTests.swift:5-154`.

**Fixed-contract classification test style** (lines 23-45, 48-56):

```swift
for response in controlResponses {
    #expect(AuthenticationFlowAdapter.classifyAuthentication(response).isTerminal)
    #expect(AuthenticationFlowAdapter.classifyAuthentication(response) != .authenticatedPendingEntitlement)
}

#expect(AuthenticationFlowAdapter.classifyEntitlement(missing) == .unsupported)
```

Build a small strict decoder/classifier per discovered operation: validate status/content type/control indications first, then decode an allow-listed response shape, filter exactly entitled standard/app-only `channel-linear` values, and map unknown fields/shapes to a closed unsupported failure. Use invented/sanitized fixture markers only; no captures, URLs, token material, or raw response logging.

### `Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/SiriusXMRequestContract.swift` (config, request-response)

**Analog:** same file (lines 3-59).

```swift
enum SiriusXMRequestContract: CaseIterable, Sendable {
    case authentication
    case entitlement

    static func makeRequest(for operation: Self, authorization: String) throws -> URLRequest {
        guard !authorization.isEmpty,
              !authorization.contains(where: { $0.isWhitespace || $0.isNewline })
        else { throw SiriusXMRequestContractError.invalidAuthorizationMaterial }
        var request = URLRequest(url: operation.url)
        request.httpMethod = operation.method
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(operation.accept, forHTTPHeaderField: "Accept")
        request.setValue("Bearer \\(authorization)", forHTTPHeaderField: "Authorization")
        return request
    }
}
```

Add individually named catalog/tune/metadata operations only after the owner-visible compatibility checkpoint. Do not turn this enum into a generic URL/header builder. Preserve fixed host policy, nonempty credential validation, and cache bypass.

### `Packages/SiriusXMClient/Sources/SiriusXMClient/Diagnostics/SafeDiagnosticEvent.swift` (utility, transform)

**Analog:** same file (lines 3-75).

```swift
enum SafeDiagnosticOperation: String, Sendable, Equatable {
    case nativeAuthentication = "native-authentication"
    case entitlement
}

struct SafeDiagnosticEvent: Sendable, Equatable {
    let operation: SafeDiagnosticOperation
    let outcome: SafeDiagnosticOutcome
    init(operation: SafeDiagnosticOperation, outcome: SafeDiagnosticOutcome, handle _: SafeDiagnosticHandle) {
        self.operation = operation
        self.outcome = outcome
    }
}
```

Extend closed operation/outcome cases for catalog, stream resolution, playback/recovery, and metadata only as safe semantic labels. Preserve the constructor shape with no material/error/URL sink. Do not log AVFoundation errors, stream resources, or provider payloads.

### Package live-listening tests (test, transform/event-driven)

**Files:** `LiveCatalogAdapterTests.swift`, `LivePlaybackCoordinatorTests.swift`, `MetadataRefreshCoordinatorTests.swift`, and updates to `SanitizedNativeResponseFixtures.swift`.

**Analogs:** `AuthenticationOutcomeTests.swift:5-154`, `SessionCoordinatorTests.swift:5-126`, `SanitizedNativeResponseFixtures.swift:3-45`.

```swift
@Suite("Session coordinator")
struct SessionCoordinatorTests {
    @Test("parallel attempts are rejected before collaborator work")
    func rejectsParallelAttemptsAndClearsCancelledTransientState() async {
        let first = Task { await coordinator.attemptSession() }
        await authentication.waitUntilStarted()
        #expect(await coordinator.attemptSession() == .attemptInProgress)
        first.cancel()
    }
}

enum SanitizedNativeResponseFixtures {
    static let subscriptionV1Active = Data(""" ... """.utf8)
}
```

Use Swift Testing, `@testable import SiriusXMClient`, async actor spies/blockers, and deterministic synthetic/sanitized fixture bytes. Assert cancellation/supersession, terminal fail-closed control mapping, filtering, freshness transitions, and recovery budgets without a live session.

### `SiriusMac/Listening/PlaybackCoordinator.swift` (service, event-driven)

**Analog:** `SiriusMac/Authentication/AuthenticationPresentationModel.swift` (lines 5-18, 20-35, 110-123).

```swift
@MainActor
@Observable
final class AuthenticationPresentationModel {
    private let flow: any AuthenticationPresentationFlow
    private var attemptID: UUID?
    private(set) var state: AuthenticationPresentationState = .waitingForWebView

    private func startAttempt(at state: AuthenticationPresentationState) -> UUID {
        let identifier = UUID()
        attemptID = identifier
        isAttemptInFlight = true
        self.state = state
        return identifier
    }
}
```

Use the same `@MainActor`, injected protocol, task, and monotonically unique generation pattern, but make it the sole owner of one `AVPlayer`, its current item/observers, resolution task, recovery task, metadata task coordination hooks, and confirmed playback state. Increment/cancel generation before every tune/stop/sign-out/sleep-wake replacement and check it after each `await`; map AVFoundation observations immediately to closed listening states.

### `SiriusMac/Catalog/ListeningPresentationModel.swift` (model, request-response)

**Analog:** `SiriusMac/Authentication/AuthenticationPresentationModel.swift` (lines 20-80, 125-207, 245-275).

```swift
@discardableResult
func retry() -> Task<Void, Never>? {
    guard isRetryableTerminalState else { return nil }
    state = .waitingForWebView
    return signIn()
}

protocol ClientAuthenticationFlow: Sendable {
    func authenticate() async -> AuthenticationOutcome
    func entitlementAvailability() async -> EntitlementAvailability
}
```

Model catalog load/refresh, selected stable channel identity, catalog freshness, and metadata presentation as explicit state. Depend on a small `Sendable` listening-flow protocol so tests can block and supersede operations. Do not let cached catalog state authorize tuning; only the coordinator/client’s current resolution result may enter active playback state.

### `SiriusMac/Catalog/ListeningView.swift` (component, request-response)

**Analog:** `SiriusMac/Authentication/AuthenticationView.swift` (lines 4-62, 73-105).

```swift
struct AuthenticationView: View {
    @State private var model: AuthenticationPresentationModel

    var body: some View {
        let copy = model.presentation(for: model.state)
        VStack(alignment: .leading, spacing: 16) {
            Label(copy.title, systemImage: copy.iconName)
            Text(copy.message).foregroundStyle(.secondary)
        }
        .disabled(model.isAttemptInFlight)
    }
}
```

Use the smallest native SwiftUI surface: ordered/category channel rows, explicit fresh/stale catalog indicator, selected-channel identity, confirmed loading/buffering/playing/paused/stopped/failure copy, and independent metadata fresh/stale/unavailable display. Actions call the presentation model only—not transport/client adapters directly.

### `SiriusMac/SiriusMacApp.swift` (config, request-response)

**Analog:** same file (lines 3-12).

```swift
@main
struct SiriusMacApp: App {
    var body: some Scene {
        WindowGroup("Sirius Mac") {
            AuthenticationView()
                .frame(minWidth: 760, minHeight: 620)
        }
        .defaultSize(width: 1_160, height: 820)
        .windowResizability(.contentMinSize)
    }
}
```

Replace the authentication-only root with a composition that retains existing authentication until entitlement is confirmed and then injects exactly one listening/coordinator composition. Preserve the one main window and defer compact/multi-window polish to Phase 3.

### `SiriusMacTests/ListeningCompositionTests.swift` (test, event-driven)

**Analog:** `SiriusMacTests/AuthenticationPresentationModelTests.swift` (lines 5-29, 60-103, 126-179).

```swift
@MainActor
final class AuthenticationPresentationModelTests: XCTestCase {
    func testSignInStartsOnlyOneBridgeActionWhileInFlight() async {
        let firstAttempt = model.signIn()
        let secondAttempt = model.signIn()
        XCTAssertNil(secondAttempt)
    }
}

private actor AuthenticationFlowSpy: AuthenticationPresentationFlow {
    private(set) var beginCallCount = 0
}
```

Use XCTest for app composition. Create `@MainActor` tests plus actor fakes that prove exactly one coordinator/player graph, confirmed rather than optimistic state, stale catalog never tunes, and superseded or terminal work cannot update the active presentation.

## Shared Patterns

### Actor-owned authorization and cancellation

**Source:** `Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift:59-138`

```swift
guard attemptLease == nil else { return .attemptInProgress }
let lease = AttemptLease()
attemptLease = lease
defer { if isCurrent(lease) { attemptLease = nil; transientCredential = nil } }

guard isCurrent(lease), !Task.isCancelled else {
    await diagnostics.record(.authentication(.cancelled))
    return .authentication(.cancelled)
}
```

Apply to client operations and app coordinator generations: serialize authority, cancel/ignore superseded work, and publish only current results.

### Fixed ephemeral transport and host policy

**Source:** `Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/EphemeralURLSessionTransport.swift:31-37, 40-73, 85-96`

```swift
let configuration = URLSessionConfiguration.ephemeral
configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
configuration.httpCookieStorage = nil
configuration.httpShouldSetCookies = false
configuration.urlCredentialStorage = nil

guard DirectHostPolicy.isAuthorizedRequest(request) else { throw URLError(.badURL) }
completionHandler(nil)
```

Apply to every new provider request. No shared cookie state, redirects, dynamic hosts, or permissive request construction.

### Closed diagnostics and error mapping

**Source:** `Packages/SiriusXMClient/Sources/SiriusXMClient/Diagnostics/SafeDiagnosticEvent.swift:10-75`

```swift
enum SafeDiagnosticOutcome: String, Sendable, Equatable, CaseIterable {
    case rateLimited = "rate-limited"
    case botControlDetected = "bot-control-detected"
    case transportFailure = "transport-failure"
    case unsupported
    case cancelled
}
```

Apply at every adapter/player error boundary. Record only a closed operation/outcome pair; raw error descriptions, request URLs, response bytes, headers, stream URLs, and token/key material must not escape.

### Test collaborators and synthetic fixtures

**Sources:** `SessionCoordinatorTests.swift:128-241`; `SanitizedNativeResponseFixtures.swift:3-45`

Use actor spies/blockers for concurrent sequencing and cancellation. Fixture payloads may identify only artificial `fixture_marker` data—not copied provider response material.

## No Analog Found

| File / responsibility | Role | Data Flow | Reason |
|---|---|---|---|
| AVFoundation item observation and stream-resource handoff within `PlaybackCoordinator.swift` | service | event-driven | No existing AVFoundation playback implementation exists; follow the research’s current-API design and keep it behind the coordinator. |
| `NWPathMonitor` and `NSWorkspace` recovery signals in `PlaybackCoordinator.swift` | service | event-driven | No existing network-path/sleep-wake observer exists; inject/classify signals and do not attach direct retry behavior. |

## Metadata

**Analog search scope:** `Packages/SiriusXMClient/Sources`, `Packages/SiriusXMClient/Tests`, `SiriusMac`, and `SiriusMacTests`  
**Files scanned:** 30  
**Pattern extraction date:** 2026-08-19
