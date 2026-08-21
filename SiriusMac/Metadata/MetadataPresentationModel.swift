import Foundation
import Observation
import SiriusXMClient

protocol MetadataFlow: AnyObject, Sendable {
    func metadata(for channelID: LiveChannelID) async -> MetadataAvailability
    func artwork(for reference: ChannelArtworkReference) async -> ArtworkAvailability
}

extension SiriusXMClient: MetadataFlow {}

struct MetadataRefreshPolicy: Sendable, Equatable {
    let pollInterval: TimeInterval
    let staleAfter: TimeInterval
    let unavailableAfter: TimeInterval
    static let `default` = Self(pollInterval: 30, staleAfter: 90, unavailableAfter: 300)
}

protocol MetadataClock: Sendable {
    func now() -> Date
}

struct SystemMetadataClock: MetadataClock {
    func now() -> Date { Date() }
}

protocol MetadataSleeping: Sendable {
    func sleep(for duration: TimeInterval) async throws
}

/// Closed, provider-neutral evidence for the metadata fallback. This lets
/// presentation and diagnostics distinguish an unavailable upstream result
/// from an app wiring failure without retaining response details.
enum MetadataPresentationAvailability: Equatable {
    case loading
    case current
    case unavailable
    case failed
}

/// The bounded semantic subset that can be safely represented outside Sirius
/// Mac's views. It excludes renderer state, request details, and stream data.
struct NowPlayingSemanticMetadata: Equatable {
    let programTitle: String?
    let programArtist: String?
    let currentProgram: String?
    let artwork: ArtworkData?
}

struct SystemMetadataSleeper: MetadataSleeping {
    func sleep(for duration: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(duration))
    }
}

/// Presentation-owned metadata lifecycle. It deliberately has no playback collaborator.
@MainActor
@Observable
final class MetadataPresentationModel {
    private let flow: any MetadataFlow
    private let policy: MetadataRefreshPolicy
    private let clock: any MetadataClock
    private let sleeper: any MetadataSleeping
    private var metadataTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var generation = 0
    private(set) var state: LiveMetadataState
    private(set) var availability: MetadataPresentationAvailability = .unavailable
    private(set) var programTitle: String?
    private(set) var programArtist: String?

    var nowPlayingSemanticMetadata: NowPlayingSemanticMetadata {
        let currentProgram: String? = switch state.text {
        case let .current(value), let .stale(value): value
        case .channelFallback, .unavailable: nil
        }
        let artwork: ArtworkData? = switch state.artwork {
        case let .current(value), let .stale(value): value
        case .unavailable: nil
        }
        return NowPlayingSemanticMetadata(
            programTitle: programTitle,
            programArtist: programArtist,
            currentProgram: currentProgram,
            artwork: artwork
        )
    }

    init(
        flow: any MetadataFlow = UnavailableMetadataFlow(),
        policy: MetadataRefreshPolicy = .default,
        clock: any MetadataClock = SystemMetadataClock(),
        sleeper: any MetadataSleeping = SystemMetadataSleeper()
    ) {
        self.flow = flow
        self.policy = policy
        self.clock = clock
        self.sleeper = sleeper
        let channelID = LiveChannelID("semantic-unselected-channel")
        state = LiveMetadataState(channelID: channelID, text: .channelFallback(channelID), artwork: .unavailable, refreshedAt: nil)
    }

    func select(_ channelID: LiveChannelID) {
        generation &+= 1
        metadataTask?.cancel()
        artworkTask?.cancel()
        pollTask?.cancel()
        expiryTask?.cancel()
        state = LiveMetadataState(channelID: channelID, text: .channelFallback(channelID), artwork: .unavailable, refreshedAt: nil)
        availability = .loading
        programTitle = nil
        programArtist = nil
        let expected = generation
        metadataTask = Task { [weak self] in await self?.refresh(channelID: channelID, generation: expected) }
        pollTask = Task { [weak self] in await self?.poll(channelID: channelID, generation: expected) }
    }

    func clear() {
        generation &+= 1
        metadataTask?.cancel()
        artworkTask?.cancel()
        pollTask?.cancel()
        expiryTask?.cancel()
        metadataTask = nil
        artworkTask = nil
        pollTask = nil
        expiryTask = nil
        let channelID = LiveChannelID("semantic-unselected-channel")
        state = LiveMetadataState(channelID: channelID, text: .channelFallback(channelID), artwork: .unavailable, refreshedAt: nil)
        availability = .unavailable
        programTitle = nil
        programArtist = nil
    }

    private func poll(channelID: LiveChannelID, generation expected: Int) async {
        while !Task.isCancelled, generation == expected {
            do {
                try await sleeper.sleep(for: policy.pollInterval)
            } catch {
                return
            }
            guard !Task.isCancelled, generation == expected else { return }
            await refresh(channelID: channelID, generation: expected)
        }
    }

    private func refresh(channelID: LiveChannelID, generation expected: Int) async {
        let result = await flow.metadata(for: channelID)
        guard !Task.isCancelled, generation == expected else { return }
        switch result {
        case let .current(snapshot):
            let program = snapshot.program
            let text = presentationText(for: program, channelID: channelID)
            let refreshedAt = clock.now()
            programTitle = program?.title.nonEmptyTrimmed
            programArtist = program?.artist?.nonEmptyTrimmed
            availability = programTitle == nil ? .unavailable : .current
            state = LiveMetadataState(channelID: channelID, text: text, artwork: .unavailable, refreshedAt: refreshedAt)
            if let reference = program?.artwork {
                startArtworkFetch(for: reference, channelID: channelID, generation: expected, refreshedAt: refreshedAt)
            }
            scheduleExpiry(channelID: channelID, generation: expected, refreshedAt: refreshedAt)
        case .unavailable:
            markRetainedMetadataStale()
            availability = .unavailable
            programTitle = nil
            programArtist = nil
        case .failed:
            markRetainedMetadataStale()
            availability = .failed
            programTitle = nil
            programArtist = nil
        }
    }

    /// A failed refresh does not invalidate the last confirmed semantic value,
    /// but it must never continue to present it as freshly current. Its
    /// original expiry task remains responsible for the eventual fallback.
    private func markRetainedMetadataStale() {
        artworkTask?.cancel()
        state = LiveMetadataState(
            channelID: state.channelID,
            text: stale(state.text),
            artwork: stale(state.artwork),
            refreshedAt: state.refreshedAt
        )
    }

    private func stale(_ text: LiveMetadataText) -> LiveMetadataText { if case let .current(value) = text { return .stale(value) }; return text }
    private func stale(_ artwork: LiveMetadataArtwork) -> LiveMetadataArtwork { if case let .current(value) = artwork { return .stale(value) }; return artwork }

    private func presentationText(for program: LiveProgramMetadata?, channelID: LiveChannelID) -> LiveMetadataText {
        guard let program, !program.title.isEmpty else { return .channelFallback(channelID) }
        if let artist = program.artist, !artist.isEmpty {
            return .current("\(artist) — \(program.title)")
        }
        return .current(program.title)
    }

    private func startArtworkFetch(
        for reference: ChannelArtworkReference,
        channelID: LiveChannelID,
        generation expected: Int,
        refreshedAt: Date
    ) {
        artworkTask?.cancel()
        let flow = flow
        artworkTask = Task { [weak self] in
            let result = await flow.artwork(for: reference)
            guard let self, !Task.isCancelled, self.generation == expected, self.state.channelID == channelID, self.state.refreshedAt == refreshedAt else { return }
            guard case let .current(artwork) = result else { return }
            let age = self.clock.now().timeIntervalSince(refreshedAt)
            guard age < self.policy.unavailableAfter else { return }
            self.state = LiveMetadataState(
                channelID: channelID,
                text: self.state.text,
                artwork: age >= self.policy.staleAfter ? .stale(artwork) : .current(artwork),
                refreshedAt: refreshedAt
            )
        }
    }

    private func scheduleExpiry(channelID: LiveChannelID, generation expected: Int, refreshedAt: Date) {
        expiryTask?.cancel()
        expiryTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sleeper.sleep(for: self.policy.staleAfter)
            } catch {
                return
            }
            guard !Task.isCancelled, self.generation == expected, self.state.channelID == channelID, self.state.refreshedAt == refreshedAt else { return }
            self.state = LiveMetadataState(
                channelID: channelID,
                text: self.stale(self.state.text),
                artwork: self.stale(self.state.artwork),
                refreshedAt: refreshedAt
            )

            do {
                try await self.sleeper.sleep(for: self.policy.unavailableAfter - self.policy.staleAfter)
            } catch {
                return
            }
            guard !Task.isCancelled, self.generation == expected, self.state.channelID == channelID, self.state.refreshedAt == refreshedAt else { return }
            self.state = LiveMetadataState(
                channelID: channelID,
                text: .channelFallback(channelID),
                artwork: .unavailable,
                refreshedAt: nil
            )
            self.availability = .unavailable
            self.programTitle = nil
            self.programArtist = nil
        }
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private final class UnavailableMetadataFlow: MetadataFlow, @unchecked Sendable {
    func metadata(for _: LiveChannelID) async -> MetadataAvailability { .unavailable }
    func artwork(for _: ChannelArtworkReference) async -> ArtworkAvailability { .unavailable }
}
