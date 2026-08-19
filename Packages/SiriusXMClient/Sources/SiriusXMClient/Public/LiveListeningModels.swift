import AVFoundation
import Foundation

/// The only app-facing resolved-media seam. This SPI is deliberately unable
/// to expose a URL, header, key, resource value, encoder, or persistence API.
/// Creating an item is not evidence that AVFoundation can play it; Plan 02-05
/// owns that native verification.
@_spi(Playback)
public protocol SiriusXMAppleMediaHandoff: Sendable {
    /// Returns nil after the originating resolution generation is invalidated.
    /// The handoff deliberately exposes no resource, header, key, URL, encoder,
    /// or persistence capability to its Apple-platform consumer.
    @MainActor func makePlayerItem() -> AVPlayerItem?
}

/// Closed outcomes for an explicit current-session stream authorization.
/// The public result carries no provider resource, header, key, or response.
public enum LiveStreamResolutionFailure: Sendable, Equatable {
    case authenticationUnavailable
    case entitlementUnavailable
    case selectionUnavailable
    case tuneUnavailable
    case resourceUnavailable
    case malformedResource
    case protectedControl
    case networkUnavailable
    case unsupportedProtection
    case cancelled
    case superseded
}

/// Semantic availability for one explicit live-stream resolution attempt.
/// A successful resource remains usable only through the SPI media handoff.
public enum LiveStreamResolutionAvailability: Sendable, Equatable {
    @_spi(Playback) case available(any SiriusXMAppleMediaHandoff)
    case unavailable
    case failed(LiveStreamResolutionFailure)

    /// Equality deliberately compares only the closed semantic availability,
    /// never the opaque handoff or any material it encloses.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.available, .available), (.unavailable, .unavailable): true
        case let (.failed(left), .failed(right)): left == right
        default: false
        }
    }
}

/// A stable semantic identity for one selectable live channel.
///
/// The identity is deliberately opaque: it is not a provider request parameter,
/// resource location, or representation of an upstream entity.
public struct LiveChannelID: Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        precondition(!rawValue.isEmpty, "Live channel identities must be nonempty")
        self.rawValue = rawValue
    }

    public var description: String { "LiveChannelID(semantic)" }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue.unicodeScalars.elementsEqual(rhs.rawValue.unicodeScalars)
    }

    public func hash(into hasher: inout Hasher) {
        for scalar in rawValue.unicodeScalars {
            hasher.combine(scalar.value)
        }
    }
}

/// A closed entitlement classification used only while filtering catalog candidates.
public enum ChannelEntitlement: Sendable, Equatable {
    case entitledStandard
    case entitledAppOnly
    case notEntitled
    case unknown
}

/// A closed entity classification used only while filtering catalog candidates.
enum CatalogEntityKind: Sendable, Equatable {
    case channelLinear
    case xtra
    case replay
    case onDemand
    case nonlinear
    case unknown
}

/// An opaque, redacted marker that artwork exists for a channel.
///
/// It intentionally retains no URL, resource, token, or provider field. Artwork
/// loading and precedence remain a later presentation concern.
public struct ChannelArtworkReference: Sendable, Equatable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    let relativeReference: String?

    public init() { self.relativeReference = nil }

    init(relativeReference: String) { self.relativeReference = relativeReference }

    public var description: String { "ChannelArtworkReference(redacted)" }
    public var debugDescription: String { "ChannelArtworkReference(redacted)" }
}

/// Current listening context decoded from the fixed, selected-channel metadata
/// operation. Provider field names and transport details never leave this type.
public struct LiveProgramMetadata: Sendable, Equatable {
    public let title: String
    public let artist: String?
    public let artwork: ChannelArtworkReference?

    public init(title: String, artist: String? = nil, artwork: ChannelArtworkReference? = nil) {
        self.title = title
        self.artist = artist
        self.artwork = artwork
    }
}

public struct MetadataSnapshot: Sendable, Equatable {
    public let channelID: LiveChannelID
    public let program: LiveProgramMetadata?

    public init(channelID: LiveChannelID, program: LiveProgramMetadata?) {
        self.channelID = channelID
        self.program = program
    }
}

public enum MetadataFailure: Sendable, Equatable {
    case authenticationUnavailable
    case notEntitled
    case unsupportedResponse
    case superseded
}

public enum MetadataAvailability: Sendable, Equatable {
    case current(MetadataSnapshot)
    case unavailable
    case failed(MetadataFailure)
}

public enum ArtworkMediaType: Sendable, Equatable { case jpeg, png }

/// Bounded image bytes suitable for native rendering. It deliberately carries
/// neither a provider URL nor request/response metadata.
public struct ArtworkData: Sendable, Equatable {
    public let bytes: Data
    public let mediaType: ArtworkMediaType

    public init(bytes: Data, mediaType: ArtworkMediaType) {
        self.bytes = bytes
        self.mediaType = mediaType
    }
}

public enum ArtworkAvailability: Sendable, Equatable {
    case current(ArtworkData)
    case unavailable
}

public protocol LiveMetadataFetching: Sendable {
    func metadata(for channelID: LiveChannelID) async -> MetadataAvailability
    func artwork(for reference: ChannelArtworkReference) async -> ArtworkAvailability
}

/// Presentation-only channel data supplied by a strict compatibility adapter.
public struct LiveChannel: Sendable, Equatable, Hashable {
    public let id: LiveChannelID
    public let name: String?
    public let description: String?
    public let displayNumber: Int?
    public let category: String?
    public let artwork: ChannelArtworkReference?

    /// A presentation fallback for existing consumers. It never replaces `id`.
    public var title: String { name ?? id.rawValue }

    public init(
        id: LiveChannelID,
        name: String? = nil,
        description: String? = nil,
        displayNumber: Int? = nil,
        category: String? = nil,
        artwork: ChannelArtworkReference? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.displayNumber = displayNumber
        self.category = category
        self.artwork = artwork
    }

    public init(
        id: LiveChannelID,
        title: String,
        displayNumber: Int? = nil,
        category: String? = nil
    ) {
        self.init(id: id, name: title, displayNumber: displayNumber, category: category)
    }
}

/// The observed freshness of semantic catalog data, independent of authorization.
public enum CatalogFreshness: Sendable, Equatable {
    case fresh
    case stale
}

public typealias LiveCatalogFreshness = CatalogFreshness

/// Closed, non-provider-specific reasons a catalog refresh could not publish a fresh snapshot.
public enum CatalogFailure: Sendable, Equatable {
    case unavailable
    case authenticationUnavailable
    case notEntitled
    case collectionUnavailable
    case malformedCandidate
    case conflictingIdentity
    case unsupportedResponse
    case cancelled
}

/// A browsable catalog value that cannot authorize playback by itself.
public struct LiveCatalogSnapshot: Sendable, Equatable {
    public let channels: [LiveChannel]
    public let refreshedAt: Date
    public let freshness: CatalogFreshness

    public init(
        channels: [LiveChannel],
        refreshedAt: Date = .distantPast,
        freshness: CatalogFreshness
    ) {
        self.channels = channels
        self.refreshedAt = refreshedAt
        self.freshness = freshness
    }

    /// Catalog snapshots remain browse-only until an independent authorization step succeeds.
    public var allowsPlaybackAuthorization: Bool { false }
}

/// The public result of one explicit catalog refresh. A stale snapshot is browse-only.
public enum CatalogAvailability: Sendable, Equatable {
    case snapshot(LiveCatalogSnapshot)
    case stale(snapshot: LiveCatalogSnapshot, failure: CatalogFailure)
    case failed(CatalogFailure)
    case unavailable
}

/// Closed catalog presentation state before a live compatibility adapter exists.
public enum LiveCatalogPresentation: Sendable, Equatable {
    case unavailable
    case snapshot(LiveCatalogSnapshot)

    public var freshness: CatalogFreshness? {
        guard case let .snapshot(snapshot) = self else { return nil }
        return snapshot.freshness
    }
}

/// Confirmed playback state; none of these cases retains a resolved media resource.
public enum LivePlaybackState: Sendable, Equatable {
    case awaitingLiveContract
    case idle
    case playing(LiveChannelID?)
    case paused
    case stopped
    case unavailable(LiveListeningFailure)
}

/// Closed, provider-agnostic reasons that a listening action did not become active.
public enum LiveListeningFailure: Sendable, Equatable {
    case authorizationUnavailable
    case entitlementUnavailable
    case catalogUnavailable
    case selectionUnavailable
    case resolutionUnavailable
    case networkUnavailable
    case bufferingUnavailable
    case decoderUnavailable
    case protectedControl
    case cancelled
    case superseded
    case recoveryExhausted
    case unsupported
}

/// Compatibility spelling retained for earlier offline catalog tests.
enum LiveCatalogClassification: Sendable, Equatable {
    case standardLinear
    case appLinear
    case nonlinear
    case ambiguous
}

/// A semantic, non-wire candidate delivered only by the internal catalog adapter.
struct LiveCatalogCandidate: Sendable, Equatable {
    let identity: String
    let displayNumber: Double?
    let name: String?
    let description: String?
    let category: String?
    let artwork: ChannelArtworkReference?
    let entity: CatalogEntityKind
    let entitlement: ChannelEntitlement

    init(
        identity: String,
        displayNumber: Double?,
        name: String?,
        description: String?,
        category: String?,
        artwork: ChannelArtworkReference?,
        entity: CatalogEntityKind,
        entitlement: ChannelEntitlement
    ) {
        self.identity = identity
        self.displayNumber = displayNumber
        self.name = name
        self.description = description
        self.category = category
        self.artwork = artwork
        self.entity = entity
        self.entitlement = entitlement
    }

    init(
        id: LiveChannelID,
        title: String,
        displayNumber: Int?,
        category: String?,
        classification: LiveCatalogClassification
    ) {
        self.init(
            identity: id.rawValue,
            displayNumber: displayNumber.map(Double.init),
            name: title,
            description: nil,
            category: category,
            artwork: nil,
            entity: classification == .standardLinear || classification == .appLinear ? .channelLinear : .nonlinear,
            entitlement: classification == .standardLinear ? .entitledStandard : classification == .appLinear ? .entitledAppOnly : .notEntitled
        )
    }
}

/// Internal result keeps a failed refresh separate from a browsable cached snapshot.
struct LiveCatalogSnapshotResult: Sendable, Equatable {
    let snapshot: LiveCatalogSnapshot?
    let failure: CatalogFailure?
}

/// Converts semantic candidates into stable browse data without claiming current playback authority.
struct LiveCatalogAdapter: Sendable {
    static func snapshot(from candidates: [LiveCatalogCandidate]?) -> LiveCatalogSnapshotResult {
        guard let candidates else {
            return LiveCatalogSnapshotResult(snapshot: nil, failure: .collectionUnavailable)
        }

        var accepted: [String: LiveCatalogCandidate] = [:]
        for candidate in candidates {
            guard !candidate.identity.isEmpty, isKnown(candidate) else {
                return LiveCatalogSnapshotResult(snapshot: nil, failure: .malformedCandidate)
            }
            if let displayNumber = candidate.displayNumber,
               canonicalNumber(displayNumber) == nil {
                return LiveCatalogSnapshotResult(snapshot: nil, failure: .malformedCandidate)
            }

            guard candidate.entity == .channelLinear,
                  candidate.entitlement == .entitledStandard || candidate.entitlement == .entitledAppOnly
            else {
                continue
            }

            let key = opaqueIdentityKey(candidate.identity)
            if let existing = accepted[key], existing != candidate {
                return LiveCatalogSnapshotResult(snapshot: nil, failure: .conflictingIdentity)
            }
            accepted[key] = candidate
        }

        let channels = accepted.values
            .compactMap { candidate -> LiveChannel? in
                let number = candidate.displayNumber.flatMap(canonicalNumber)
                return LiveChannel(
                    id: LiveChannelID(candidate.identity),
                    name: candidate.name,
                    description: candidate.description,
                    displayNumber: number,
                    category: candidate.category,
                    artwork: candidate.artwork
                )
            }
            .sorted(by: isOrderedBefore)
        return LiveCatalogSnapshotResult(
            snapshot: LiveCatalogSnapshot(channels: channels, refreshedAt: Date(), freshness: .fresh),
            failure: nil
        )
    }

    static func withStaleSnapshot(
        _ snapshot: LiveCatalogSnapshot?,
        after failure: CatalogFailure
    ) -> LiveCatalogSnapshotResult {
        guard let snapshot else {
            return LiveCatalogSnapshotResult(snapshot: nil, failure: failure)
        }
        return LiveCatalogSnapshotResult(
            snapshot: LiveCatalogSnapshot(channels: snapshot.channels, refreshedAt: snapshot.refreshedAt, freshness: .stale),
            failure: failure
        )
    }

    func makeSnapshot(
        from candidates: [LiveCatalogCandidate],
        freshness: LiveCatalogFreshness
    ) -> LiveCatalogSnapshot {
        let result = Self.snapshot(from: candidates)
        return result.snapshot.map {
            LiveCatalogSnapshot(channels: $0.channels, refreshedAt: $0.refreshedAt, freshness: freshness)
        } ?? LiveCatalogSnapshot(channels: [], freshness: freshness)
    }

    func retainingForBrowsing(_ snapshot: LiveCatalogSnapshot) -> LiveCatalogSnapshot {
        LiveCatalogSnapshot(channels: snapshot.channels, freshness: .stale)
    }

    private static func canonicalNumber(_ number: Double) -> Int? {
        return Int(exactly: number)
    }

    private static func isKnown(_ candidate: LiveCatalogCandidate) -> Bool {
        candidate.entity != .unknown && candidate.entitlement != .unknown
    }

    private static func opaqueIdentityKey(_ identity: String) -> String {
        identity.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-")
    }

    private static func isOrderedBefore(_ lhs: LiveChannel, _ rhs: LiveChannel) -> Bool {
        let leftCategory = lhs.category ?? ""
        let rightCategory = rhs.category ?? ""
        if leftCategory != rightCategory { return leftCategory < rightCategory }

        let leftNumber = lhs.displayNumber ?? .max
        let rightNumber = rhs.displayNumber ?? .max
        if leftNumber != rightNumber { return leftNumber < rightNumber }
        if lhs.name != rhs.name { return (lhs.name ?? "") < (rhs.name ?? "") }
        return lhs.id.rawValue.utf8.lexicographicallyPrecedes(rhs.id.rawValue.utf8)
    }
}

enum LivePlaybackResolution: Sendable, Equatable {
    case ready
    case failed(LiveListeningFailure)
}

protocol LivePlaybackResolving: Sendable {
    func resolve(_ channelID: LiveChannelID) async -> LivePlaybackResolution
}

/// Internal current-session resolution seam. Implementations must perform only
/// the fixed contract and retain opaque resource material in memory.
protocol LiveStreamResolving: Sendable {
    func resolveLiveStream(for channelID: LiveChannelID) async -> LiveStreamResolutionAvailability
    func invalidate() async
}

struct UnavailableLiveStreamResolver: LiveStreamResolving {
    func resolveLiveStream(for _: LiveChannelID) async -> LiveStreamResolutionAvailability { .unavailable }
    func invalidate() async {}
}

/// The only fixed semantic steps allowed to materialize one live handoff.
/// Implementations are responsible for direct-host policy, strict transport
/// preflight, and opaque in-memory handling; this seam never receives or
/// returns URLs, headers, key material, bodies, or request builders.
protocol FixedLiveStreamOperating: Sendable {
    func authorizeTune(for channelID: LiveChannelID) async -> FixedLiveTuneAuthorization
    func resolveResource(in context: any FixedLiveOperationContext) async -> FixedLiveResourceResolution
    func authorizePlaybackKey(for context: any FixedLiveOperationContext) async -> LiveStreamResolutionFailure?
}

/// Opaque internal state for one authorized tune sequence. It intentionally
/// exposes no provider material, storage, encoding, or diagnostic capability.
protocol FixedLiveOperationContext: Sendable {}

enum FixedLiveTuneAuthorization: Sendable {
    case authorized(any FixedLiveOperationContext)
    case failed(LiveStreamResolutionFailure)
}

enum FixedLivePlaybackKeyRequirement: Sendable, Equatable {
    case required
    case notRequired
}

enum FixedLiveResourceResolution: Sendable {
    case resolved(any SiriusXMAppleMediaHandoff, keyRequirement: FixedLivePlaybackKeyRequirement)
    case failed(LiveStreamResolutionFailure)
}

/// Serializes the approved tune -> resource -> optional-key sequence. A newer
/// request or explicit invalidation makes all earlier resource handoffs
/// unusable before they can escape to a player.
actor FixedLiveStreamResolver: LiveStreamResolving {
    private let operations: any FixedLiveStreamOperating
    private var generation = 0
    private var activeHandoffs: [GenerationBoundAppleMediaHandoff] = []

    init(operations: any FixedLiveStreamOperating) {
        self.operations = operations
    }

    func resolveLiveStream(for channelID: LiveChannelID) async -> LiveStreamResolutionAvailability {
        let command = beginGeneration()
        guard !Task.isCancelled else { return .failed(.cancelled) }

        let context: any FixedLiveOperationContext
        switch await operations.authorizeTune(for: channelID) {
        case let .authorized(authorizedContext):
            context = authorizedContext
        case let .failed(failure):
            return terminal(failure, for: command)
        }
        guard isCurrent(command) else { return .failed(.superseded) }
        guard !Task.isCancelled else { return .failed(.cancelled) }

        let resource: (any SiriusXMAppleMediaHandoff, FixedLivePlaybackKeyRequirement)
        switch await operations.resolveResource(in: context) {
        case let .resolved(handoff, keyRequirement):
            resource = (handoff, keyRequirement)
        case let .failed(failure):
            return terminal(failure, for: command)
        }
        guard isCurrent(command) else { return .failed(.superseded) }
        guard !Task.isCancelled else { return .failed(.cancelled) }

        if resource.1 == .required {
            if let failure = await operations.authorizePlaybackKey(for: context) {
                return terminal(failure, for: command)
            }
            guard isCurrent(command) else { return .failed(.superseded) }
            guard !Task.isCancelled else { return .failed(.cancelled) }
        }

        let guarded = GenerationBoundAppleMediaHandoff(source: resource.0)
        activeHandoffs.append(guarded)
        guard isCurrent(command) else {
            guarded.invalidate()
            return .failed(.superseded)
        }
        return .available(guarded)
    }

    func invalidate() async {
        generation &+= 1
        invalidateActiveHandoffs()
    }

    private func beginGeneration() -> Int {
        generation &+= 1
        invalidateActiveHandoffs()
        return generation
    }

    private func isCurrent(_ command: Int) -> Bool { generation == command }

    private func terminal(_ failure: LiveStreamResolutionFailure, for command: Int) -> LiveStreamResolutionAvailability {
        guard isCurrent(command) else { return .failed(.superseded) }
        return .failed(failure)
    }

    private func invalidateActiveHandoffs() {
        activeHandoffs.forEach { $0.invalidate() }
        activeHandoffs.removeAll(keepingCapacity: true)
    }
}

/// A lock-protected validity bit is deliberately the only cross-actor state.
/// It contains no provider material and makes stale opaque handoffs fail closed.
private final class GenerationBoundAppleMediaHandoff: SiriusXMAppleMediaHandoff, @unchecked Sendable {
    private let source: any SiriusXMAppleMediaHandoff
    private let lock = NSLock()
    private var valid = true

    init(source: any SiriusXMAppleMediaHandoff) {
        self.source = source
    }

    func invalidate() {
        lock.lock()
        valid = false
        lock.unlock()
    }

    @MainActor func makePlayerItem() -> AVPlayerItem? {
        lock.lock()
        let isValid = valid
        lock.unlock()
        return isValid ? source.makePlayerItem() : nil
    }
}

enum LivePlaybackDriverResult: Sendable, Equatable {
    case confirmed(LivePlaybackState)
    case failed(LiveListeningFailure)
}

protocol LivePlaybackEventDriving: Sendable {
    func start(_ channelID: LiveChannelID) async -> LivePlaybackDriverResult
    func pause() async -> LivePlaybackDriverResult
    func resumeLiveEdge() async -> LivePlaybackDriverResult
    func stop() async -> LivePlaybackDriverResult
}

/// An offline state machine that coordinates semantic collaborator outcomes, not media resources.
actor LivePlaybackContractCoordinator {
    private let resolver: any LivePlaybackResolving
    private let player: any LivePlaybackEventDriving
    private let recoveryBudget: Int
    private var generation = 0

    private(set) var currentState: LivePlaybackState = .awaitingLiveContract
    private(set) var selectedChannelID: LiveChannelID?

    init(
        resolver: any LivePlaybackResolving,
        player: any LivePlaybackEventDriving,
        recoveryBudget: Int
    ) {
        self.resolver = resolver
        self.player = player
        self.recoveryBudget = max(0, recoveryBudget)
    }

    func tune(_ channelID: LiveChannelID) async -> LivePlaybackState {
        let command = beginCommand(selecting: channelID)
        guard !Task.isCancelled else { return publish(.cancelled, for: command) }

        switch await resolver.resolve(channelID) {
        case .ready:
            guard !Task.isCancelled else { return publish(.cancelled, for: command) }
            return publish(await player.start(channelID), for: command)
        case let .failed(failure):
            return publish(failure, for: command)
        }
    }

    func pause() async -> LivePlaybackState {
        let command = beginCommand()
        guard !Task.isCancelled else { return publish(.cancelled, for: command) }
        return publish(await player.pause(), for: command)
    }

    func resumeLiveEdge() async -> LivePlaybackState {
        let command = beginCommand()
        guard !Task.isCancelled else { return publish(.cancelled, for: command) }
        return publish(await player.resumeLiveEdge(), for: command)
    }

    func stop() async -> LivePlaybackState {
        let command = beginCommand()
        guard !Task.isCancelled else { return publish(.cancelled, for: command) }
        return publish(await player.stop(), for: command)
    }

    func recover() async -> LivePlaybackState {
        guard let channelID = selectedChannelID else {
            return unavailable(.selectionUnavailable)
        }

        let command = beginCommand()
        for _ in 0..<recoveryBudget {
            guard !Task.isCancelled else { return publish(.cancelled, for: command) }
            guard isCurrent(command) else { return currentState }

            switch await resolver.resolve(channelID) {
            case .ready:
                guard !Task.isCancelled else { return publish(.cancelled, for: command) }
                let outcome = await player.start(channelID)
                guard isCurrent(command) else { return currentState }
                switch outcome {
                case .confirmed:
                    return publish(outcome, for: command)
                case let .failed(failure) where isTerminalRecoveryFailure(failure):
                    return publish(failure, for: command)
                case .failed:
                    continue
                }
            case let .failed(failure) where isTerminalRecoveryFailure(failure):
                return publish(failure, for: command)
            case .failed:
                continue
            }
        }

        return publish(.recoveryExhausted, for: command)
    }

    private func beginCommand(selecting channelID: LiveChannelID? = nil) -> Int {
        generation += 1
        if let channelID { selectedChannelID = channelID }
        return generation
    }

    private func isCurrent(_ command: Int) -> Bool { generation == command }

    private func publish(_ outcome: LivePlaybackDriverResult, for command: Int) -> LivePlaybackState {
        switch outcome {
        case let .confirmed(state):
            return publish(state, for: command)
        case let .failed(failure):
            return publish(failure, for: command)
        }
    }

    private func publish(_ failure: LiveListeningFailure, for command: Int) -> LivePlaybackState {
        guard isCurrent(command) else { return currentState }
        return unavailable(failure)
    }

    private func publish(_ state: LivePlaybackState, for command: Int) -> LivePlaybackState {
        guard isCurrent(command) else { return currentState }
        currentState = state
        return state
    }

    private func unavailable(_ failure: LiveListeningFailure) -> LivePlaybackState {
        let state = LivePlaybackState.unavailable(failure)
        currentState = state
        return state
    }

    private func isTerminalRecoveryFailure(_ failure: LiveListeningFailure) -> Bool {
        switch failure {
        case .authorizationUnavailable, .entitlementUnavailable, .protectedControl, .cancelled, .superseded, .unsupported:
            true
        case .catalogUnavailable, .selectionUnavailable, .resolutionUnavailable, .networkUnavailable, .bufferingUnavailable, .decoderUnavailable, .recoveryExhausted:
            false
        }
    }
}

/// Text is deliberately semantic; it contains no provider response field names.
public enum LiveMetadataText: Sendable, Equatable {
    case current(String)
    case stale(String)
    case channelFallback(LiveChannelID)
    case unavailable
}

/// Artwork contains only bounded, validated image bytes suitable for native rendering.
/// It deliberately carries no source URL, request headers, or provider response data.
public enum LiveMetadataArtwork: Sendable, Equatable {
    case current(ArtworkData)
    case stale(ArtworkData)
    case unavailable
}

public struct LiveMetadataState: Sendable, Equatable {
    public let channelID: LiveChannelID
    public let text: LiveMetadataText
    public let artwork: LiveMetadataArtwork
    public let refreshedAt: Date?

    public init(channelID: LiveChannelID, text: LiveMetadataText, artwork: LiveMetadataArtwork, refreshedAt: Date?) {
        self.channelID = channelID
        self.text = text
        self.artwork = artwork
        self.refreshedAt = refreshedAt
    }
}

public enum LiveMetadataRefreshResult: Sendable, Equatable {
    case current(text: String?, artwork: ArtworkData?)
    case unavailable
}

public protocol LiveMetadataRefreshing: Sendable {
    func refresh(for channelID: LiveChannelID) async -> LiveMetadataRefreshResult
}

public protocol LiveMetadataClock: Sendable {
    func now() -> Date
}

public struct SystemLiveMetadataClock: LiveMetadataClock {
    public init() {}
    public func now() -> Date { Date() }
}

public struct UnavailableMetadataRefresher: LiveMetadataRefreshing {
    public init() {}
    public func refresh(for _: LiveChannelID) async -> LiveMetadataRefreshResult { .unavailable }
}

/// Refreshes metadata independently from playback and retains no audio-control collaborator.
public actor MetadataRefreshCoordinator {
    private let refresher: any LiveMetadataRefreshing
    private let clock: any LiveMetadataClock
    private var generation = 0

    public private(set) var currentState: LiveMetadataState

    public init(
        refresher: any LiveMetadataRefreshing = UnavailableMetadataRefresher(),
        clock: any LiveMetadataClock = SystemLiveMetadataClock()
    ) {
        self.refresher = refresher
        self.clock = clock
        let channelID = LiveChannelID("semantic-unselected-channel")
        self.currentState = Self.fallbackState(for: channelID)
    }

    @discardableResult
    public func select(_ channelID: LiveChannelID) -> LiveMetadataState {
        generation += 1
        currentState = Self.fallbackState(for: channelID)
        return currentState
    }

    @discardableResult
    public func refresh() async -> LiveMetadataState {
        let command = generation
        let channelID = currentState.channelID
        let result = await refresher.refresh(for: channelID)
        guard generation == command else { return currentState }

        switch result {
        case let .current(text, artwork):
            currentState = LiveMetadataState(
                channelID: channelID,
                text: text.map(LiveMetadataText.current) ?? .channelFallback(channelID),
                artwork: artwork.map(LiveMetadataArtwork.current) ?? .unavailable,
                refreshedAt: clock.now()
            )
        case .unavailable:
            currentState = Self.advanceUnavailableState(from: currentState)
        }
        return currentState
    }

    private static func fallbackState(for channelID: LiveChannelID) -> LiveMetadataState {
        LiveMetadataState(channelID: channelID, text: .channelFallback(channelID), artwork: .unavailable, refreshedAt: nil)
    }

    private static func advanceUnavailableState(from state: LiveMetadataState) -> LiveMetadataState {
        LiveMetadataState(
            channelID: state.channelID,
            text: staleOrUnavailable(state.text),
            artwork: staleOrUnavailable(state.artwork),
            refreshedAt: state.refreshedAt
        )
    }

    private static func staleOrUnavailable(_ text: LiveMetadataText) -> LiveMetadataText {
        switch text {
        case let .current(value): .stale(value)
        case .stale, .channelFallback, .unavailable: .unavailable
        }
    }

    private static func staleOrUnavailable(_ artwork: LiveMetadataArtwork) -> LiveMetadataArtwork {
        switch artwork {
        case let .current(value): .stale(value)
        case .stale, .unavailable: .unavailable
        }
    }
}
