import MediaPlayer
import XCTest
@_spi(Playback) import SiriusXMClient
@testable import Canis97

@MainActor
final class SystemMediaControllerTests: XCTestCase {
    func testRepeatedStartInstallsOneTargetForEachSupportedCommandAndShutdownRemovesThemOnce() {
        let commandCenter = FakeRemoteCommandCenter()
        let controller = SystemMediaController(
            commandCenter: commandCenter,
            nowPlayingPublisher: FakeNowPlayingPublisher(),
            actions: .init(playPause: { .success }, previous: { .success }, next: { .success })
        )

        controller.start()
        controller.start()

        XCTAssertEqual(commandCenter.targetCount(for: .playPause), 1)
        XCTAssertEqual(commandCenter.targetCount(for: .previous), 1)
        XCTAssertEqual(commandCenter.targetCount(for: .next), 1)

        controller.shutdown()
        controller.shutdown()

        XCTAssertEqual(commandCenter.removalCount, 3)
        XCTAssertTrue(commandCenter.allTargetsRemoved)
    }

    func testLiveInappropriateCommandsAreDisabledAndHandlerFree() {
        let commandCenter = FakeRemoteCommandCenter()
        let controller = SystemMediaController(
            commandCenter: commandCenter,
            nowPlayingPublisher: FakeNowPlayingPublisher(),
            actions: .init(playPause: { .success }, previous: { .success }, next: { .success })
        )

        controller.start()

        for command in SystemRemoteCommand.liveInappropriateCommands {
            XCTAssertFalse(commandCenter.isEnabled(command))
            XCTAssertEqual(commandCenter.targetCount(for: command), 0)
        }
    }

    func testRemoteEventsRouteOnceAndUnavailableActionsFailWithoutMutation() {
        let commandCenter = FakeRemoteCommandCenter()
        var playPauseCount = 0
        var nextCount = 0
        let controller = SystemMediaController(
            commandCenter: commandCenter,
            nowPlayingPublisher: FakeNowPlayingPublisher(),
            actions: .init(
                playPause: { playPauseCount += 1; return .success },
                previous: { .commandFailed },
                next: { nextCount += 1; return .success }
            )
        )

        controller.start()

        XCTAssertEqual(commandCenter.send(.playPause), .success)
        XCTAssertEqual(commandCenter.send(.next), .success)
        XCTAssertEqual(commandCenter.send(.previous), .commandFailed)
        XCTAssertEqual(playPauseCount, 1)
        XCTAssertEqual(nextCount, 1)
    }

    func testNowPlayingSemanticMetadataPrefersCurrentTitleAndArtistWithChannelArtworkContext() {
        let artwork = ArtworkData(bytes: Data([0x89, 0x50, 0x4E, 0x47]), mediaType: .png)
        let metadata = NowPlayingSemanticMetadata(
            programTitle: "Été électronique",
            programArtist: "Björk",
            currentProgram: "Fallback program",
            artwork: artwork
        )

        let info = metadata.systemNowPlayingInfo(
            channelName: "80s on 8",
            playbackState: .playing
        )

        XCTAssertEqual(info.title, "Été électronique")
        XCTAssertEqual(info.artist, "Björk")
        XCTAssertEqual(info.channelName, "80s on 8")
        XCTAssertEqual(info.artwork, artwork)
        XCTAssertTrue(info.isLive)
        XCTAssertEqual(info.playbackRate, 1)
    }

    func testNowPlayingRetainsLastConfirmedInfoUntilTerminalStateClearsIt() {
        let commandCenter = FakeRemoteCommandCenter()
        let publisher = FakeNowPlayingPublisher()
        let controller = SystemMediaController(
            commandCenter: commandCenter,
            nowPlayingPublisher: publisher,
            actions: .init(playPause: { .success }, previous: { .success }, next: { .success })
        )
        let confirmed = NowPlayingSemanticMetadata(
            programTitle: nil,
            programArtist: nil,
            currentProgram: "Current program",
            artwork: nil
        ).systemNowPlayingInfo(channelName: "Channel 42", playbackState: .paused)

        controller.start()
        controller.publish(confirmed)

        // A pending tune has no confirmed presentation to publish, so it keeps
        // the previous system representation rather than leaking a browse choice.
        XCTAssertEqual(publisher.lastPublished, confirmed)

        controller.publish(nil)
        XCTAssertNil(publisher.lastPublished)
    }

    func testNowPlayingArtworkRequestIsSafeOnMediaPlayersBackgroundQueue() async throws {
        let png = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        let artwork = try XCTUnwrap(SystemNowPlayingArtworkFactory.make(
            from: ArtworkData(bytes: png, mediaType: .png)
        ))
        let sendableArtwork = UncheckedSendableArtwork(artwork)

        let rendered = await withCheckedContinuation { continuation in
            DispatchQueue(label: "fixture.media-player.accessQueue").async {
                continuation.resume(returning: sendableArtwork.value.image(at: CGSize(width: 64, height: 64)) != nil)
            }
        }

        XCTAssertTrue(rendered)
    }
}

private final class UncheckedSendableArtwork: @unchecked Sendable {
    let value: MPMediaItemArtwork
    init(_ value: MPMediaItemArtwork) { self.value = value }
}

@MainActor
private final class FakeRemoteCommandCenter: RemoteCommandCenterControlling {
    private final class Token: RemoteCommandTarget, Hashable {
        var isRemoved = false

        nonisolated static func == (lhs: Token, rhs: Token) -> Bool { lhs === rhs }
        nonisolated func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
    }

    private var handlers: [SystemRemoteCommand: [Token: () -> SystemRemoteCommandStatus]] = [:]
    private var enabled: [SystemRemoteCommand: Bool] = [:]
    private(set) var removalCount = 0

    func setEnabled(_ isEnabled: Bool, for command: SystemRemoteCommand) {
        enabled[command] = isEnabled
    }

    func addTarget(
        for command: SystemRemoteCommand,
        handler: @escaping () -> SystemRemoteCommandStatus
    ) -> any RemoteCommandTarget {
        let token = Token()
        handlers[command, default: [:]][token] = handler
        return token
    }

    func removeTarget(_ target: any RemoteCommandTarget, for command: SystemRemoteCommand) {
        guard let token = target as? Token, !token.isRemoved else { return }
        token.isRemoved = true
        handlers[command]?[token] = nil
        removalCount += 1
    }

    func targetCount(for command: SystemRemoteCommand) -> Int { handlers[command]?.count ?? 0 }
    func isEnabled(_ command: SystemRemoteCommand) -> Bool { enabled[command] ?? true }
    var allTargetsRemoved: Bool { handlers.values.allSatisfy(\.isEmpty) }

    func send(_ command: SystemRemoteCommand) -> SystemRemoteCommandStatus {
        guard isEnabled(command), let handler = handlers[command]?.values.first else { return .commandFailed }
        return handler()
    }
}

@MainActor
private final class FakeNowPlayingPublisher: NowPlayingInfoPublishing {
    private(set) var lastPublished: SystemNowPlayingInfo?

    func publish(_ info: SystemNowPlayingInfo?) {
        lastPublished = info
    }
}
