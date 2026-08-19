import SiriusXMClient

/// Temporary checkpoint-only authority for live-content observation.
///
/// It deliberately receives only the already-derived entitlement state, never
/// a credential or browser/session object. Until a fixed content contract has
/// been independently authorized, the adapter closes the single run before it
/// can construct or send a content request.
@MainActor
final class ClosedLiveObservationAdapter {
    enum StartResult: Equatable {
        case started
        case entitlementRequired
        case alreadyConsumed
    }

    private let sink: LiveContractObservationSink

    init(sink: LiveContractObservationSink = LiveContractObservationSink()) {
        self.sink = sink
    }

    var observations: [LiveContractObservation] { sink.observations }
    var state: LiveContractObservationState { sink.state }

    /// Begins one checkpoint only after the native client has already derived
    /// entitlement from its opaque restored credential.
    func begin(entitlement: EntitlementAvailability) -> StartResult {
        guard entitlement == .entitled else { return .entitlementRequired }
        return sink.begin() ? .started : .alreadyConsumed
    }

    /// Fails closed before a catalog request whenever no exact provider
    /// method/host/path contract is available. This prevents endpoint probing,
    /// redirects, retries, and any accidental content request.
    func refuseUnknownCatalogContract() {
        _ = sink.record(
            LiveContractObservation(
                capability: .catalogRefresh,
                disposition: .unsupported,
                requestContract: nil,
                semanticShapes: [],
                protection: .unknownContract,
                avFoundationBehavior: .notObserved
            )
        )
    }
}
