import Foundation
import Testing
@testable import SiriusXMClient

@Suite("Provider-neutral live catalog contracts")
struct LiveCatalogAdapterTests {

    @Test("supported live operations remain fixed, first-party, and non-generic")
    func supportedOperationsStayFixed() {
        let operations = SiriusXMRequestContract.liveListeningOperations

        #expect(operations.map(\.operationID) == [
            "catalog",
            "tune",
            "playback-key",
            "live-update",
            "channel-peek",
            "stream-enforcement",
        ])
        #expect(operations.map(\.method) == ["GET", "POST", "GET", "POST", "GET", "GET"])
        #expect(operations.map(\.pathTemplate) == [
            "/browse/v1/pages/curated-grouping/403ab6a5-d3c9-4c2a-a722-a94a6a5fd056",
            "/playback/play/v1/tuneSource",
            "/playback/key/v1/{keyId}",
            "/playback/play/v1/liveUpdate",
            "/channel-guide/v1/channel/{channelId}/peek",
            "/playback/stream-enforcement/v1/status",
        ])
        #expect(operations.allSatisfy { $0.host == "api.edge-gateway.siriusxm.com" })
        #expect(SiriusXMRequestContract.opaqueMediaDeliveryHost == "live-akc-prod-device.streaming.siriusxm.com")
        #expect(!SiriusXMRequestContract.all.contains { $0.operationID == "media-resource" })
    }

    @Test("playback-key decoding accepts only the recorded opaque two-string shape after preflight")
    func playbackKeyDecoderFailsClosed() {
        let accepted = NativeTransportResponse(
            statusCode: 200,
            contentType: "application/json",
            body: Data(#"{"keyId":"fixture-key-id","key":"fixture-key-material"}"#.utf8)
        )
        let malformed = NativeTransportResponse(
            statusCode: 200,
            contentType: "application/json",
            body: Data(#"{"keyId":"fixture-key-id","unexpected":"fixture-value"}"#.utf8)
        )
        let control = NativeTransportResponse(
            statusCode: 403,
            contentType: "application/json",
            body: Data(#"{"fixture_marker":"blocked"}"#.utf8)
        )

        #expect(LiveListeningAdapter.inspectPlaybackKey(accepted) == .accepted)
        #expect(LiveListeningAdapter.inspectPlaybackKey(malformed) == .unsupported(.playbackKeyUnexpectedShape))
        #expect(LiveListeningAdapter.inspectPlaybackKey(control) == .unsupported(.rejected))
    }

    @Test("tune semantics include only the recorded non-secret values and clock shape")
    func tuneBodyContractStaysBounded() {
        #expect(SiriusXMRequestContract.tune.bodyContract.fixedSemantics == [
            "type": .string("channel-linear"),
            "hlsVersion": .string("V3"),
            "manifestVariant": .string("WEB"),
            "mtcVersion": .string("V2"),
            "trackResumeSupported": .boolean(false),
            "x-sxm-clock": .epochCounter,
        ])
        #expect(SiriusXMRequestContract.liveUpdate.bodyContract.fixedSemantics == [
            "channelId": .opaqueValue,
            "startTimestamp": .opaqueValue,
            "endTimestamp": .opaqueValue,
        ])
    }

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
