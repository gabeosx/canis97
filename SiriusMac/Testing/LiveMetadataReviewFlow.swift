#if DEBUG || CANIS97_ANIMATION_ACCEPTANCE
import Foundation
import SiriusXMClient

/// Synthetic channel and live metadata used only by the credential-free review composition.
actor LiveMetadataReviewFlow: ListeningFlow, LiveNowFlow {
    private var scenario: String
    init(scenario: String = "current") { self.scenario = scenario }

    func setScenario(_ value: String) { scenario = value }

    static let channels: [LiveChannel] = [
        LiveChannel(id: LiveChannelID("live-review-1"), name: "Orbit", displayNumber: 8, category: "Pop"),
        LiveChannel(id: LiveChannelID("live-review-2"), name: "Night Drive", displayNumber: 21, category: "Electronic"),
        LiveChannel(id: LiveChannelID("live-review-3"), name: "The Listening Room", displayNumber: 34, category: "Indie"),
        LiveChannel(id: LiveChannelID("live-review-4"), name: "Blue Hour", displayNumber: 67, category: "Jazz"),
        LiveChannel(id: LiveChannelID("live-review-5"), name: "The Conversation", displayNumber: 102, category: "Talk"),
        LiveChannel(id: LiveChannelID("live-review-6"), name: "Game Day", displayNumber: 204, category: "Sports"),
        LiveChannel(id: LiveChannelID("live-review-7"), name: "Open Road", displayNumber: 311, category: "Country"),
        LiveChannel(id: LiveChannelID("live-review-8"), name: "Studio Sessions", displayNumber: 412, category: "Live music"),
    ]

    func catalog() async -> CatalogAvailability {
        .snapshot(LiveCatalogSnapshot(channels: Self.channels, freshness: .fresh))
    }

    func liveNow(for channelIDs: [LiveChannelID]) async -> LiveNowAvailability {
        if scenario == "failure" { return .failed(.networkUnavailable) }
        let observedAt = Date().addingTimeInterval(scenario == "stale" ? -120 : 0)
        let programs: [LiveNowChannelState] = [
            .current(LiveNowProgram(title: "A Little More Light", artist: "The Satellites", kind: .item, startedAt: observedAt.addingTimeInterval(-94))),
            .current(LiveNowProgram(title: "City After Midnight", artist: "Neon Avenue", kind: .item, startedAt: observedAt.addingTimeInterval(-183))),
            .current(LiveNowProgram(title: "Everything in Its Own Time", artist: "Juniper & the Coast", kind: .item, startedAt: observedAt.addingTimeInterval(-41))),
            .current(LiveNowProgram(title: "Sunday in September", artist: "The Ellis Quartet", kind: .item, startedAt: observedAt.addingTimeInterval(-280))),
            .current(LiveNowProgram(title: "The Weekend Conversation", kind: .show, startedAt: observedAt.addingTimeInterval(-1140))),
            .current(LiveNowProgram(title: "Around the League", kind: .item, startedAt: observedAt.addingTimeInterval(-650))),
            .unavailable,
            .unsupported,
        ]
        let states = Dictionary(uniqueKeysWithValues: zip(Self.channels.map(\.id), programs))
        return .current(LiveNowSnapshot(observedAt: observedAt, channels: channelIDs.map {
            LiveNowChannel(channelID: $0, state: scenario == "empty" ? .unavailable : states[$0] ?? .unavailable)
        }))
    }
}
#endif
