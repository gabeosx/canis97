import Foundation

/// Compatibility spelling retained for the walking skeleton's presentation model.
public typealias AuthenticationAvailability = AuthenticationOutcome

/// A semantic client for the supported SiriusXM subscriber experience.
public actor SiriusXMClient {
    private let sessionCoordinator: SessionCoordinator?
    private let retainedSessionDiagnostics: OSLogSessionDiagnostics?
    private let catalogRefresher: any CatalogRefreshing
    private let liveStreamResolver: any LiveStreamResolving
    private let metadataFetcher: any LiveMetadataFetching
    private var liveNowCoordinator: LiveNowRefreshCoordinator?
    private var lastValidCatalogSnapshot: LiveCatalogSnapshot?
    private var catalogRefreshGeneration = 0
    private var liveResolutionGeneration = 0
    private var metadataGeneration = 0
    private var metadataLifecycleTransitions = 0
    private var batchMetadataDemandGeneration = 0

    public init() {
        self.sessionCoordinator = nil
        self.retainedSessionDiagnostics = nil
        self.catalogRefresher = UnavailableCatalogRefresher()
        self.liveStreamResolver = UnavailableLiveStreamResolver()
        self.metadataFetcher = UnavailableMetadataFetcher()
    }

    init(metadataFetcher: any LiveMetadataFetching) {
        self.sessionCoordinator = nil
        self.retainedSessionDiagnostics = nil
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
        metadataFetcher: (any LiveMetadataFetching)? = nil,
        retainedSessionDiagnostics: OSLogSessionDiagnostics? = nil
    ) {
        self.sessionCoordinator = sessionCoordinator
        self.retainedSessionDiagnostics = retainedSessionDiagnostics
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
        residueCleaner: any AuthenticationResidueCleaner,
        credentialRefresher: (any CredentialRefresher)? = nil
    ) {
        let diagnostics = OSLogSessionDiagnostics()
        let verifier = NativeRequestVerifier(transport: EphemeralURLSessionTransport())
        let coordinator = SessionCoordinator(
            credentialSource: credentialSource,
            authenticationVerifier: verifier,
            entitlementVerifier: verifier,
            credentialStore: credentialStore,
            credentialRefresher: credentialRefresher ?? PassThroughPublicCredentialRefresher(),
            residueCleaner: residueCleaner,
            clock: SystemSessionClock(),
            diagnostics: diagnostics
        )
        sessionCoordinator = coordinator
        retainedSessionDiagnostics = diagnostics
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
        metadataLifecycleTransitions += 1
        defer { metadataLifecycleTransitions -= 1 }
        metadataGeneration &+= 1
        catalogRefreshGeneration &+= 1
        lastValidCatalogSnapshot = nil
        await liveNowCoordinator?.invalidate(before: metadataGeneration)
        await metadataFetcher.invalidate()
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

    /// Returns only the latest closed native-authentication classification.
    /// Provider material and transport error text are discarded before this point.
    public func latestAuthenticationDiagnostic() async -> AuthenticationDiagnosticOutcome? {
        await retainedSessionDiagnostics?.latestAuthenticationOutcome()
    }

#if DEBUG
    /// Runs one owner-initiated renewal transaction through the production
    /// session actor and credential store. The operation never retries.
    public func qualifyCurrentCredentialRenewal() async -> AuthenticationRenewalQualificationOutcome {
        guard let sessionCoordinator else { return .sessionUnavailable }
        return await sessionCoordinator.qualifyCurrentCredentialRenewal()
    }
#endif

    /// Reports the entitlement derived from the most recent native transaction.
    public func entitlement() async -> EntitlementAvailability {
        guard let sessionCoordinator else {
            return .unavailable
        }
        return await sessionCoordinator.entitlementAvailability
    }

    /// Ends the empty in-memory session without scheduling retry work.
    public func signOut() async -> SignOutOutcome {
        metadataLifecycleTransitions += 1
        defer { metadataLifecycleTransitions -= 1 }
        metadataGeneration &+= 1
        lastValidCatalogSnapshot = nil
        catalogRefreshGeneration &+= 1
        liveResolutionGeneration &+= 1
        await liveNowCoordinator?.invalidate(before: metadataGeneration)
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
        metadataGeneration &+= 1
        let expectedGeneration = catalogRefreshGeneration
        await liveNowCoordinator?.invalidate(before: metadataGeneration)
        guard let sessionCoordinator else {
            return .failed(.authenticationUnavailable)
        }
        guard await sessionCoordinator.entitlementAvailability == .entitled,
              catalogRefreshGeneration == expectedGeneration
        else {
            return .failed(.notEntitled)
        }

        let refreshed = await catalogRefresher.refresh()

        // An intervening sign-out, reauthentication, or entitlement loss makes
        // the attempted refresh non-authoritative, even if it returned a
        // semantic snapshot. Never cache a prior session's catalog.
        guard await sessionCoordinator.entitlementAvailability == .entitled,
              catalogRefreshGeneration == expectedGeneration
        else {
            return .failed(.cancelled)
        }

        if let snapshot = refreshed.snapshot, refreshed.failure == nil {
            metadataGeneration &+= 1
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
        guard metadataLifecycleTransitions == 0 else { return .failed(.superseded) }
        metadataGeneration &+= 1
        let expected = metadataGeneration
        let expectedBatchDemand = batchMetadataDemandGeneration
        await liveNowCoordinator?.invalidate(before: metadataGeneration)
        guard metadataGeneration == expected, metadataLifecycleTransitions == 0,
              batchMetadataDemandGeneration == expectedBatchDemand else { return .failed(.superseded) }
        let result = await metadataFetcher.metadata(for: channelID)
        guard metadataGeneration == expected, batchMetadataDemandGeneration == expectedBatchDemand else { return .failed(.superseded) }
        return result
    }

    /// Retrieves a full replacement of metadata for ordered entitled catalog IDs
    /// through one fixed request. Missing channels are explicitly unavailable.
    /// The observation time is local receipt time, not provider time. This
    /// operation never authorizes playback and never schedules a polling loop.
    /// Concurrent demand covered by the active batch shares its one response.
    /// A new selection outside that coverage, catalog refresh, reauthentication,
    /// or sign-out supersedes outstanding work. Cancelling one consumer preserves
    /// other consumers; the last cancellation retires the shared request.
    /// Private protocol changes fail closed.
    public func liveNow(for channelIDs: [LiveChannelID]) async -> LiveNowAvailability {
        guard !Task.isCancelled else { return .failed(.cancelled) }
        guard metadataLifecycleTransitions == 0 else { return .failed(.superseded) }
        batchMetadataDemandGeneration &+= 1
        let expected = metadataGeneration
        guard let fetcher = metadataFetcher as? any LiveNowFetching else {
            return .failed(.authenticationUnavailable)
        }
        if liveNowCoordinator == nil {
            liveNowCoordinator = LiveNowRefreshCoordinator(fetcher: fetcher)
        }
        guard let liveNowCoordinator else { return .failed(.authenticationUnavailable) }
        let result = await liveNowCoordinator.refresh(for: channelIDs, context: expected)
        guard !Task.isCancelled else { return .failed(.cancelled) }
        guard metadataGeneration == expected else { return .failed(.superseded) }
        return result
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

private struct PassThroughPublicCredentialRefresher: CredentialRefresher {
    func refreshedCredential(ifNeeded credential: AuthenticationCredential) async -> AuthenticationCredential? {
        credential
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
