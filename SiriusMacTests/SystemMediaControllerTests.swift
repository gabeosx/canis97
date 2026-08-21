import XCTest
@_spi(Playback) import SiriusXMClient
@testable import SiriusMac

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
}

@MainActor
private final class FakeRemoteCommandCenter: RemoteCommandCenterControlling {
    private final class Token: RemoteCommandTarget {
        var isRemoved = false
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
    func publish(_ info: SystemNowPlayingInfo?) {}
}
