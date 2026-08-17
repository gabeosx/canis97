import AVFoundation

/// Closed prerequisites for creating any volatile playback work.
public enum BrowserProofEligibility: Equatable, Sendable {
    case environmentPending
    case constructionIncomplete
    case ownerRejected
    case qualified

    var permitsVolatileWork: Bool { self == .qualified }
}

/// The only authorization classification accepted by the bounded proof.
public enum ExpectedAuthorization: Equatable, Sendable {
    case expected
    case unsupported
}

/// Confirmation remains with the account owner and carries no media data.
public enum OwnerAudibleConfirmation: Equatable, Sendable {
    case audible
    case notConfirmed
}

public enum PlaybackReadiness: Equatable, Sendable {
    case ready
    case failed(SafeTerminalReason)
}

/// A closed outcome that contains no URL, content key, asset, or player state.
public enum PlaybackProof: Equatable, Sendable {
    case notApplicable
    case incomplete
    case authorizedAndAudible
    case terminal(SafeTerminalReason)
}

/// The narrow volatile bridge used by the proof coordinator. Implementations must
/// attach an asset to the content-key session before creating the player item and
/// must clear all state when asked.
@MainActor
public protocol AuthorizedPlaybackRuntime: AnyObject {
    func prepareExpectedAuthorization() -> PlaybackReadiness
    func clearVolatileState()
}

/// Current-SDK AVFoundation bridge. The caller supplies an in-memory asset only at
/// the live boundary; no asset URL or key material reaches the proof record.
@MainActor
public final class AVContentKeyPlaybackRuntime: AuthorizedPlaybackRuntime {
    private let asset: AVURLAsset
    private var contentKeySession: AVContentKeySession?
    private var player: AVPlayer?

    public init(asset: AVURLAsset) {
        self.asset = asset
    }

    public func prepareExpectedAuthorization() -> PlaybackReadiness {
        clearVolatileState()

        let keySession = AVContentKeySession(keySystem: .fairPlayStreaming)
        keySession.addContentKeyRecipient(asset)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)

        contentKeySession = keySession
        self.player = player
        return player.currentItem == nil ? .failed(.unknown) : .ready
    }

    public func clearVolatileState() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        contentKeySession?.removeContentKeyRecipient(asset)
        contentKeySession = nil
    }
}

/// Coordinates exactly one bounded proof. It deliberately has no retry, timer,
/// recording, persistence, download, cache, or provider operation API.
@MainActor
public final class AuthorizedPlaybackProbe {
    private let eligibility: BrowserProofEligibility
    private let runtime: any AuthorizedPlaybackRuntime
    private var terminalProof: PlaybackProof?

    public init(eligibility: BrowserProofEligibility, runtime: any AuthorizedPlaybackRuntime) {
        self.eligibility = eligibility
        self.runtime = runtime
    }

    public func prove(
        expectedAuthorization: ExpectedAuthorization,
        ownerConfirmation: OwnerAudibleConfirmation
    ) -> PlaybackProof {
        guard eligibility.permitsVolatileWork else { return .notApplicable }
        if let terminalProof { return terminalProof }
        guard expectedAuthorization == .expected else {
            return closeTerminal(.protectedControl)
        }

        let readiness = runtime.prepareExpectedAuthorization()
        switch readiness {
        case .ready:
            runtime.clearVolatileState()
            return ownerConfirmation == .audible ? .authorizedAndAudible : .incomplete
        case let .failed(reason):
            runtime.clearVolatileState()
            return closeTerminal(reason)
        }
    }

    private func closeTerminal(_ reason: SafeTerminalReason) -> PlaybackProof {
        let proof = PlaybackProof.terminal(reason)
        terminalProof = proof
        return proof
    }
}
