import Foundation
import Observation
import SiriusXMClient

enum ChannelArtworkLoadState: Equatable {
    case noReference
    case idle
    case loading
    case available
    case unavailable
}

/// Shared, memory-only artwork loading for library rows and channel fallbacks.
/// References remain opaque and the client retains sole authority over fixed
/// hosts, response validation, and byte bounds.
@MainActor
@Observable
final class ArtworkStore {
    @ObservationIgnored private let flow: any MetadataFlow
    @ObservationIgnored private let maximumEntryCount: Int
    @ObservationIgnored private let maximumCacheBytes: Int
    @ObservationIgnored private var tasks: [ChannelArtworkReference: Task<ArtworkAvailability, Never>] = [:]
    @ObservationIgnored private var insertionOrder: [ChannelArtworkReference] = []
    @ObservationIgnored private var cachedByteCount = 0
    @ObservationIgnored private var generation = 0

    private var cached: [ChannelArtworkReference: ArtworkData] = [:]
    private var loading: Set<ChannelArtworkReference> = []
    private var unavailable: Set<ChannelArtworkReference> = []

    init(
        flow: any MetadataFlow = UnavailableArtworkFlow(),
        maximumEntryCount: Int = 128,
        maximumCacheBytes: Int = 32 * 1_024 * 1_024
    ) {
        self.flow = flow
        self.maximumEntryCount = maximumEntryCount
        self.maximumCacheBytes = maximumCacheBytes
    }

    func artwork(for reference: ChannelArtworkReference?) -> ArtworkData? {
        guard let reference else { return nil }
        return cached[reference]
    }

    func loadState(for reference: ChannelArtworkReference?) -> ChannelArtworkLoadState {
        guard let reference else { return .noReference }
        if cached[reference] != nil { return .available }
        if loading.contains(reference) { return .loading }
        if unavailable.contains(reference) { return .unavailable }
        return .idle
    }

    func load(_ reference: ChannelArtworkReference?) async {
        guard let reference,
              cached[reference] == nil,
              !unavailable.contains(reference)
        else { return }

        if let task = tasks[reference] {
            _ = await task.value
            return
        }

        let expectedGeneration = generation
        let flow = flow
        let task = Task { await flow.artwork(for: reference) }
        tasks[reference] = task
        loading.insert(reference)
        let result = await task.value

        guard generation == expectedGeneration else { return }
        tasks[reference] = nil
        loading.remove(reference)
        switch result {
        case let .current(artwork):
            insert(artwork, for: reference)
        case .unavailable:
            unavailable.insert(reference)
        }
    }

    /// A catalog refresh is an explicit retry boundary for transient image
    /// failures without discarding already validated bytes.
    func retryUnavailable() {
        unavailable.removeAll(keepingCapacity: true)
    }

    func clear() {
        generation &+= 1
        for task in tasks.values { task.cancel() }
        tasks.removeAll(keepingCapacity: false)
        cached.removeAll(keepingCapacity: false)
        loading.removeAll(keepingCapacity: false)
        unavailable.removeAll(keepingCapacity: false)
        insertionOrder.removeAll(keepingCapacity: false)
        cachedByteCount = 0
    }

    private func insert(_ artwork: ArtworkData, for reference: ChannelArtworkReference) {
        guard artwork.bytes.count <= maximumCacheBytes else {
            unavailable.insert(reference)
            return
        }

        cached[reference] = artwork
        cachedByteCount += artwork.bytes.count
        insertionOrder.append(reference)

        while cached.count > maximumEntryCount || cachedByteCount > maximumCacheBytes {
            guard let oldest = insertionOrder.first else { break }
            insertionOrder.removeFirst()
            if let removed = cached.removeValue(forKey: oldest) {
                cachedByteCount -= removed.bytes.count
            }
        }
    }
}

private final class UnavailableArtworkFlow: MetadataFlow, @unchecked Sendable {
    func metadata(for _: LiveChannelID) async -> MetadataAvailability { .unavailable }
    func artwork(for _: ChannelArtworkReference) async -> ArtworkAvailability { .unavailable }
}
