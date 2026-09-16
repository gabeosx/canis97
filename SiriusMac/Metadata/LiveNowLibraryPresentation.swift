import Foundation
import SiriusXMClient

protocol LiveNowFlow: AnyObject, Sendable {
    func liveNow(for channelIDs: [LiveChannelID]) async -> LiveNowAvailability
}
extension SiriusXMClient: LiveNowFlow {}

/// A local projection used by every channel collection. It preserves each
/// collection's order and never grants tuning or playback authority.
@MainActor
struct LiveNowLibraryProjection {
    private let states: [LiveChannelID: LiveNowChannelState]
    let freshness: LiveNowFreshness

    init(monitor: LiveNowMonitor?, at date: Date = Date()) {
        freshness = monitor?.freshness(at: date) ?? .unavailable
        guard freshness != .unavailable, let snapshot = monitor?.snapshot else {
            states = [:]
            return
        }
        states = Dictionary(snapshot.channels.map { ($0.channelID, $0.state) }, uniquingKeysWith: { first, _ in first })
    }

    func state(for channelID: LiveChannelID) -> LiveNowChannelState? {
        states[channelID]
    }

    func program(for channelID: LiveChannelID) -> LiveNowProgram? {
        guard case let .current(program) = states[channelID] else { return nil }
        return program
    }

    func matches(_ item: LibraryChannelItem, query: String) -> Bool {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return true }
        let program = program(for: item.id)
        return [
            item.channel.name,
            item.channel.category,
            item.channel.displayNumber.map(String.init),
            program?.title,
            program?.artist,
        ]
        .compactMap { $0 }
        .contains { $0.localizedStandardContains(search) }
    }
}
