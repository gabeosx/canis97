import Testing
@testable import SiriusXMClient

@Suite("Provider-neutral live catalog contracts")
struct LiveCatalogAdapterTests {
    @Test("only explicitly linear classifications enter a stable ordered catalog")
    func filtersAndOrdersSemanticCandidates() {
        let adapter = LiveCatalogAdapter()
        let catalog = adapter.makeSnapshot(
            from: [
                LiveCatalogCandidate(id: LiveChannelID("fixture-echo"), title: "Echo", displayNumber: 15, category: "Music", classification: .appLinear),
                LiveCatalogCandidate(id: LiveChannelID("fixture-bravo"), title: "Bravo", displayNumber: 2, category: "News", classification: .standardLinear),
                LiveCatalogCandidate(id: LiveChannelID("fixture-charlie"), title: "Charlie", displayNumber: 9, category: "Music", classification: .nonlinear),
                LiveCatalogCandidate(id: LiveChannelID("fixture-alpha"), title: "Alpha", displayNumber: 3, category: "News", classification: .ambiguous),
            ],
            freshness: .fresh
        )

        #expect(catalog.channels.map(\.id) == [LiveChannelID("fixture-echo"), LiveChannelID("fixture-bravo")])
        #expect(catalog.channels.map(\.category) == ["Music", "News"])
    }

    @Test("a retained catalog becomes stale browsing data and never authorizes playback")
    func cachedCatalogHasNoPlaybackAuthority() {
        let adapter = LiveCatalogAdapter()
        let fresh = adapter.makeSnapshot(
            from: [
                LiveCatalogCandidate(id: LiveChannelID("fixture-cached"), title: "Cached", displayNumber: 1, category: "Talk", classification: .standardLinear),
            ],
            freshness: .fresh
        )

        let stale = adapter.retainingForBrowsing(fresh)

        #expect(stale.freshness == .stale)
        #expect(stale.channels == fresh.channels)
        #expect(stale.allowsPlaybackAuthorization == false)
    }
}
