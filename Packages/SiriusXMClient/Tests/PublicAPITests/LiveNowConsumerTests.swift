import Foundation
import SiriusXMClient
import Testing

@Test func independentConsumerUsesBulkMetadataWithoutPlaybackAuthority() async {
    let ids = [LiveChannelID("second"), LiveChannelID("first")]
    let observedAt = Date(timeIntervalSince1970: 100)
    let program = LiveNowProgram(title: "Synthetic Show", kind: .show, startedAt: observedAt)
    let snapshot = LiveNowSnapshot(observedAt: observedAt, channels: [
        LiveNowChannel(channelID: ids[0], state: .current(program)),
        LiveNowChannel(channelID: ids[1], state: .unavailable),
    ])
    let availability = LiveNowAvailability.current(snapshot)
    #expect(snapshot.channels.map(\.channelID) == ids)
    #expect(program.artist == nil)
    #expect(availability == .current(snapshot))
    #expect(await SiriusXMClient().liveNow(for: ids) == .failed(.authenticationUnavailable))
}

@Test func bulkMetadataModelsContainOnlyDeclaredSemanticFields() throws {
    let program = LiveNowProgram(title: "Synthetic", artist: "Host", kind: .item, startedAt: .distantPast)
    let channel = LiveNowChannel(channelID: LiveChannelID("fixture"), state: .current(program))
    let snapshot = LiveNowSnapshot(observedAt: .distantPast, channels: [channel])
    #expect(Mirror(reflecting: program).children.compactMap(\.label) == ["title", "artist", "kind", "startedAt"])
    #expect(Mirror(reflecting: channel).children.compactMap(\.label) == ["channelID", "state"])
    #expect(Mirror(reflecting: snapshot).children.compactMap(\.label) == ["observedAt", "channels"])

    // The API's implementation is checked alongside an independent import:
    // no resource/access type, provider marker, or materialization member can
    // silently be added to this metadata-only value surface.
    let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: package.appendingPathComponent("Sources/SiriusXMClient/Public/LiveNowSnapshot.swift"), encoding: .utf8)
    let declarations = source.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }.joined(separator: "\n")
    for forbidden in ["URL", "Data", "ChannelArtworkReference", "AuthenticationCredential", "AVPlayer", "Handoff", "delta", "validFrom", "artistName", "headers", "token", "cookie", "encode", "Codable"] {
        #expect(!declarations.contains(forbidden))
    }
}
