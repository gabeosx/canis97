import Foundation

protocol LiveNowFetching: Sendable {
    func liveNow(for channelIDs: [LiveChannelID]) async -> LiveNowAvailability
}

/// One explicit refresh, one fixed metadata request, no polling or retained body.
actor CurrentSessionMetadataFetcher: LiveMetadataFetching, LiveNowFetching {
    private let sessionCoordinator: SessionCoordinator
    private let transport: any FixedMetadataTransporting
    private let responseObservationClock: any MetadataResponseObservationClock
    private var generation = 0
    private var artworkGeneration = 0

    init(
        sessionCoordinator: SessionCoordinator,
        transport: any FixedMetadataTransporting,
        responseObservationClock: any MetadataResponseObservationClock = SystemMetadataResponseObservationClock()
    ) {
        self.sessionCoordinator = sessionCoordinator
        self.transport = transport
        self.responseObservationClock = responseObservationClock
    }

    func invalidate() async {
        generation &+= 1
        artworkGeneration &+= 1
    }

    func liveNow(for channelIDs: [LiveChannelID]) async -> LiveNowAvailability {
        await refresh(channelIDs: channelIDs).availability
    }

    func metadata(for channelID: LiveChannelID) async -> MetadataAvailability {
        await refresh(channelIDs: [channelID]).selectedChannel()
    }

    private func refresh(channelIDs: [LiveChannelID]) async -> DecodedLookaroundSnapshot {
        guard !Task.isCancelled else { return failed(.cancelled) }
        generation &+= 1
        let expected = generation
        let authorization = await sessionCoordinator.withCurrentCatalogCredential(
            { [transport, responseObservationClock] credential in
                let response = await transport.lookaround(using: credential)
                guard !Task.isCancelled else {
                    return DecodedLookaroundSnapshot(availability: .failed(.cancelled))
                }
                return LookaroundSnapshotDecoder.decode(
                    response, channelIDs: channelIDs,
                    observedAt: responseObservationClock.now()
                )
            },
            authorizationLoss: { result in
                switch result.availability {
                case .failed(.authenticationUnavailable): .unavailable
                case .failed(.notEntitled): .authenticatedButNotEntitled
                default: nil
                }
            }
        )
        guard !Task.isCancelled else { return failed(.cancelled) }
        guard generation == expected else { return failed(.superseded) }
        switch authorization {
        case let .completed(result): return result
        case .authenticationUnavailable: return failed(.authenticationUnavailable)
        case .notEntitled: return failed(.notEntitled)
        case .superseded: return failed(.superseded)
        }
    }

    func artwork(for reference: ChannelArtworkReference) async -> ArtworkAvailability {
        let expected = artworkGeneration
        let response = await transport.artwork(for: reference)
        CompatibilitySchemaDiagnostics.recordArtwork(response, origin: reference.fixedOrigin)
        guard !Task.isCancelled, artworkGeneration == expected else { return .unavailable }
        return LiveListeningAdapter.decodeArtwork(response)
    }

    private func failed(_ failure: LiveNowFailure) -> DecodedLookaroundSnapshot {
        DecodedLookaroundSnapshot(availability: .failed(failure))
    }
}
