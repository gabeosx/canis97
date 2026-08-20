import Foundation

/// Compatibility spelling retained for the walking skeleton's presentation model.
public typealias AuthenticationAvailability = AuthenticationOutcome

/// A semantic client for the supported SiriusXM subscriber experience.
public actor SiriusXMClient {
    private let sessionCoordinator: SessionCoordinator?
    private let catalogRefresher: any CatalogRefreshing
    private let liveStreamResolver: any LiveStreamResolving
    private let metadataFetcher: any LiveMetadataFetching
    private var lastValidCatalogSnapshot: LiveCatalogSnapshot?
    private var catalogRefreshGeneration = 0
    private var liveResolutionGeneration = 0

    public init() {
        self.sessionCoordinator = nil
        self.catalogRefresher = UnavailableCatalogRefresher()
        self.liveStreamResolver = UnavailableLiveStreamResolver()
        self.metadataFetcher = UnavailableMetadataFetcher()
    }

    init(metadataFetcher: any LiveMetadataFetching) {
        self.sessionCoordinator = nil
        self.catalogRefresher = UnavailableCatalogRefresher()
        self.liveStreamResolver = UnavailableLiveStreamResolver()
        self.metadataFetcher = metadataFetcher
    }

    init(
        sessionCoordinator: SessionCoordinator,
        catalogRefresher: (any CatalogRefreshing)? = nil,
        catalogTransport: (any FixedCatalogTransporting)? = nil,
        liveStreamResolver: (any LiveStreamResolving)? = nil,
        fixedLiveTransport: (any FixedLiveTransporting)? = nil,
        metadataFetcher: (any LiveMetadataFetching)? = nil
    ) {
        self.sessionCoordinator = sessionCoordinator
        self.catalogRefresher = catalogRefresher ?? CurrentSessionCatalogRefresher(
            sessionCoordinator: sessionCoordinator,
            transport: catalogTransport ?? FixedCatalogURLSessionTransport()
        )
        self.liveStreamResolver = liveStreamResolver ?? FixedLiveStreamResolver(
            operations: CurrentSessionFixedLiveOperations(
                sessionCoordinator: sessionCoordinator,
                transport: fixedLiveTransport ?? FixedLiveURLSessionTransport()
            )
        )
        self.metadataFetcher = metadataFetcher ?? CurrentSessionMetadataFetcher(sessionCoordinator: sessionCoordinator, transport: FixedMetadataURLSessionTransport())
    }

    /// Composes the sole supported WebView-token/native-request authentication path.
    ///
    /// The app owns the credential source, persistence adapter, and browser-residue
    /// cleanup. The client owns the ephemeral native requests and derives every
    /// authentication and entitlement result from their responses.
    public init(
        credentialSource: any CredentialSource,
        credentialStore: any CredentialStore,
        residueCleaner: any AuthenticationResidueCleaner
    ) {
        let diagnostics = OSLogSessionDiagnostics()
        let verifier = NativeRequestVerifier(transport: EphemeralURLSessionTransport())
        let coordinator = SessionCoordinator(
            credentialSource: credentialSource,
            authenticationVerifier: verifier,
            entitlementVerifier: verifier,
            credentialStore: credentialStore,
            residueCleaner: residueCleaner,
            clock: SystemSessionClock(),
            diagnostics: diagnostics
        )
        sessionCoordinator = coordinator
        catalogRefresher = CurrentSessionCatalogRefresher(
            sessionCoordinator: coordinator,
            transport: FixedCatalogURLSessionTransport()
        )
        liveStreamResolver = FixedLiveStreamResolver(
            operations: CurrentSessionFixedLiveOperations(
                sessionCoordinator: coordinator,
                transport: FixedLiveURLSessionTransport()
            )
        )
        metadataFetcher = CurrentSessionMetadataFetcher(sessionCoordinator: coordinator, transport: FixedMetadataURLSessionTransport())
    }

    /// Returns the fail-closed Phase 1 state without contacting a provider.
    public func authenticationAvailability() -> AuthenticationAvailability {
        .waitingForAuthenticationComposition
    }

    /// Consumes one opaque WebView credential and completes native authentication
    /// followed by native entitlement verification.
    public func authenticate() async -> AuthenticationOutcome {
        guard let sessionCoordinator else {
            return .waitingForAuthenticationComposition
        }

        switch await sessionCoordinator.attemptSession() {
        case .active, .entitlement:
            // Entitlement remains separately observable through `entitlement()`.
            return .authenticatedPendingEntitlement
        case .credentialPersistenceFailed:
            return .credentialPersistenceFailed
        case let .authentication(outcome):
            return outcome
        case .attemptInProgress:
            return .waitingForAuthenticationComposition
        }
    }

    /// Reports the entitlement derived from the most recent native transaction.
    public func entitlement() async -> EntitlementAvailability {
        guard let sessionCoordinator else {
            return .unavailable
        }
        return await sessionCoordinator.entitlementAvailability
    }

    /// Ends the empty in-memory session without scheduling retry work.
    public func signOut() async -> SignOutOutcome {
        lastValidCatalogSnapshot = nil
        catalogRefreshGeneration &+= 1
        liveResolutionGeneration &+= 1
        await liveStreamResolver.invalidate()
        await metadataFetcher.invalidate()
        guard let sessionCoordinator else {
            return .alreadySignedOut
        }
        return await sessionCoordinator.signOut()
    }

    /// Refreshes the catalog through the current authorized client transaction.
    ///
    /// The default refresher deliberately fails closed until a later capability
    /// plan can supply validated opaque inputs. It does not make a provider
    /// request, expose a request materialization API, or infer a wire schema.
    public func catalog() async -> CatalogAvailability {
        let expectedGeneration = catalogRefreshGeneration
        guard let sessionCoordinator else {
            return .failed(.authenticationUnavailable)
        }
        guard catalogRefreshGeneration == expectedGeneration,
              await sessionCoordinator.entitlementAvailability == .entitled
        else {
            return .failed(.notEntitled)
        }

        let refreshed = await catalogRefresher.refresh()

        // An intervening sign-out or entitlement loss makes the attempted
        // refresh non-authoritative, even if it returned a semantic snapshot.
        guard await sessionCoordinator.entitlementAvailability == .entitled else {
            return .failed(.notEntitled)
        }

        if let snapshot = refreshed.snapshot, refreshed.failure == nil {
            lastValidCatalogSnapshot = snapshot
            return .snapshot(snapshot)
        }

        let failure = refreshed.failure ?? .unavailable
        if let lastValidCatalogSnapshot {
            return .stale(
                snapshot: LiveCatalogSnapshot(
                    channels: lastValidCatalogSnapshot.channels,
                    refreshedAt: lastValidCatalogSnapshot.refreshedAt,
                    freshness: .stale
                ),
                failure: failure
            )
        }
        return .failed(failure)
    }

    /// Retrieves one selected-channel snapshot through the fixed lookaround
    /// operation. It has no playback authority or retry loop.
    public func metadata(for channelID: LiveChannelID) async -> MetadataAvailability {
        await metadataFetcher.metadata(for: channelID)
    }

    /// Compatibility spelling without a selected identity. It cannot issue a
    /// metadata request.
    public func metadata() -> MetadataAvailability {
        .unavailable
    }

    /// Fetches only an opaque, adapter-issued artwork reference.
    public func artwork(for reference: ChannelArtworkReference) async -> ArtworkAvailability {
        await metadataFetcher.artwork(for: reference)
    }

    /// Resolves only an explicitly selected live identity after the current
    /// session still reports entitlement. Catalog presence never authorizes it.
    public func resolveLiveStream(for channelID: LiveChannelID) async -> LiveStreamResolutionAvailability {
        let expectedGeneration = liveResolutionGeneration
        guard let sessionCoordinator else {
            return .failed(.authenticationUnavailable)
        }
        guard await sessionCoordinator.entitlementAvailability == .entitled else {
            return .failed(.entitlementUnavailable)
        }

        let result = await liveStreamResolver.resolveLiveStream(for: channelID)
        guard liveResolutionGeneration == expectedGeneration,
              await sessionCoordinator.entitlementAvailability == .entitled
        else {
            return .failed(.superseded)
        }
        return result
    }

    /// Compatibility spelling retained for callers that have not supplied a
    /// semantic selection; it cannot authorize a request.
    public func resolveLiveStream() -> LiveStreamResolutionAvailability {
        .failed(.selectionUnavailable)
    }
}

/// An internal semantic seam. Its implementations must not expose catalog bodies,
/// URLs, headers, credentials, or a generic provider request surface.
protocol CatalogRefreshing: Sendable {
    func refresh() async -> LiveCatalogSnapshotResult
}

private struct UnavailableCatalogRefresher: CatalogRefreshing {
    func refresh() async -> LiveCatalogSnapshotResult {
        LiveCatalogSnapshotResult(snapshot: nil, failure: .unavailable)
    }
}

private struct UnavailableMetadataFetcher: LiveMetadataFetching {
    func metadata(for _: LiveChannelID) async -> MetadataAvailability { .unavailable }
    func artwork(for _: ChannelArtworkReference) async -> ArtworkAvailability { .unavailable }
}

private final class NativeRequestVerifier: NativeAuthenticationVerifying, NativeEntitlementVerifying, @unchecked Sendable {
    private let transport: any SessionTransport

    init(transport: any SessionTransport) {
        self.transport = transport
    }

    func verifyAuthentication(using credential: AuthenticationCredential) async -> NativeTransportResponse {
        await response(for: .authentication, using: credential)
    }

    func verifyEntitlement(using credential: AuthenticationCredential) async -> NativeTransportResponse {
        await response(for: .entitlement, using: credential)
    }

    private func response(
        for operation: SiriusXMRequestContract,
        using credential: AuthenticationCredential
    ) async -> NativeTransportResponse {
        do {
            return try await transport.send(operation, using: credential)
        } catch {
            // Preserve only a closed error class. Error text and failing URLs
            // must never cross into session diagnostics.
            return NativeTransportResponse(
                statusCode: 0,
                contentType: nil,
                body: Data(),
                transportFailure: SafeTransportFailure(error: error)
            )
        }
    }
}

private struct SystemSessionClock: SessionClock {
    func now() -> Date { Date() }
}
