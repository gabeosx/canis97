import Foundation
import SiriusXMClient

/// Confirms whether playback may be attempted for the currently selected channel.
protocol LivePlaybackAuthorizing: Sendable {
    func authorizePlayback(for channelID: LiveChannelID) async -> LivePlaybackAuthorization
}

enum LivePlaybackAuthorization: Sendable, Equatable {
    case authorized
    case unavailable
}

/// A reversible app seam for a future supported player implementation.
protocol LivePlaybackDriving: Sendable {
    func tune(_ channelID: LiveChannelID) async -> LivePlaybackDriverResult
    func pause() async -> LivePlaybackDriverResult
    func resumeLiveEdge() async -> LivePlaybackDriverResult
    func stop() async -> LivePlaybackDriverResult
}

enum LivePlaybackDriverResult: Sendable, Equatable {
    case confirmed(LivePlaybackState)
    case failed(LiveListeningFailure)
}

/// The single app-owned future-player seam. It has no provider or media implementation.
@MainActor
final class PlaybackCoordinator {
    private let authorization: any LivePlaybackAuthorizing
    private let driver: any LivePlaybackDriving
    private var generation = 0

    private(set) var state: LivePlaybackState
    private(set) var selectedChannelID: LiveChannelID?

    init(
        authorization: any LivePlaybackAuthorizing = UnavailablePlaybackAuthorization(),
        driver: any LivePlaybackDriving = UnavailablePlaybackDriver()
    ) {
        self.authorization = authorization
        self.driver = driver
        state = .awaitingLiveContract
        selectedChannelID = nil
    }

    func tune(_ channelID: LiveChannelID) async {
        let currentGeneration = startCommand()
        selectedChannelID = channelID
        guard await authorization.authorizePlayback(for: channelID) == .authorized else {
            publish(.unavailable(.authorizationUnavailable), for: currentGeneration)
            return
        }
        publish(await driver.tune(channelID), for: currentGeneration)
    }

    func pause() async {
        let currentGeneration = startCommand()
        publish(await driver.pause(), for: currentGeneration)
    }

    func resumeLiveEdge() async {
        let currentGeneration = startCommand()
        publish(await driver.resumeLiveEdge(), for: currentGeneration)
    }

    func stop() async {
        let currentGeneration = startCommand()
        let result = await driver.stop()
        guard generation == currentGeneration else { return }
        if case .confirmed(.stopped) = result {
            selectedChannelID = nil
        }
        publish(result, for: currentGeneration)
    }

    private func startCommand() -> Int {
        generation += 1
        return generation
    }

    private func publish(_ result: LivePlaybackDriverResult, for currentGeneration: Int) {
        guard generation == currentGeneration else { return }
        switch result {
        case let .confirmed(confirmedState):
            state = confirmedState
        case let .failed(failure):
            state = .unavailable(failure)
        }
    }

    private func publish(_ state: LivePlaybackState, for currentGeneration: Int) {
        guard generation == currentGeneration else { return }
        self.state = state
    }
}

private struct UnavailablePlaybackAuthorization: LivePlaybackAuthorizing {
    func authorizePlayback(for _: LiveChannelID) async -> LivePlaybackAuthorization {
        .unavailable
    }
}

private struct UnavailablePlaybackDriver: LivePlaybackDriving {
    func tune(_: LiveChannelID) async -> LivePlaybackDriverResult { .failed(.resolutionUnavailable) }
    func pause() async -> LivePlaybackDriverResult { .failed(.unsupported) }
    func resumeLiveEdge() async -> LivePlaybackDriverResult { .failed(.unsupported) }
    func stop() async -> LivePlaybackDriverResult { .confirmed(.stopped) }
}
