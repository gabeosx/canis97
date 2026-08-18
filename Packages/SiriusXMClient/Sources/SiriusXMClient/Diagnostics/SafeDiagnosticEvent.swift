import OSLog

/// Closed operation labels that may be emitted by the client diagnostic sink.
enum SafeDiagnosticOperation: String, Sendable, Equatable {
    case nativeAuthentication = "native-authentication"
    case entitlement
    case sessionCleanup = "session-cleanup"
}

/// Closed outcome labels that contain no provider, account, request, or error detail.
enum SafeDiagnosticOutcome: String, Sendable, Equatable, CaseIterable {
    case completed
    case rejected
    case challengeRequired = "challenge-required"
    case rateLimited = "rate-limited"
    case redirectDrift = "redirect-drift"
    case botControlDetected = "bot-control-detected"
    case transportFailure = "transport-failure"
    case unsupportedContentType = "unsupported-content-type"
    case unsupportedHTTPStatus = "unsupported-http-status"
    case unsupportedPayload = "unsupported-payload"
    case unsupported
    case cancelled
    case credentialUnavailable = "credential-unavailable"
    case credentialPersistenceFailed = "credential-persistence-failed"
    case notEntitled = "not-entitled"
    case cleanupIncomplete = "cleanup-incomplete"
}

/// A locally generated correlation handle with no renderable or exportable representation.
struct SafeDiagnosticHandle: Sendable, Equatable {
    init() {}
}

/// A diagnostic value whose initializer has no sink for transport or secret-bearing material.
struct SafeDiagnosticEvent: Sendable, Equatable {
    let operation: SafeDiagnosticOperation
    let outcome: SafeDiagnosticOutcome

    init(operation: SafeDiagnosticOperation, outcome: SafeDiagnosticOutcome, handle _: SafeDiagnosticHandle) {
        self.operation = operation
        self.outcome = outcome
    }

    var rendered: String {
        "\(operation.rawValue):\(outcome.rawValue)"
    }
}

/// The only production sink for closed semantic diagnostic events.
struct OSLogDiagnosticSink: Sendable {
    private let logger = Logger(subsystem: "com.siriusmac.client", category: "diagnostics")

    func record(_ event: SafeDiagnosticEvent) {
        logger.info("SiriusXM client event \(event.rendered, privacy: .public)")
    }
}

/// Bridges actor-owned session diagnostics to the closed production OSLog sink.
struct OSLogSessionDiagnostics: SessionDiagnostics {
    private let sink = OSLogDiagnosticSink()

    func record(_ event: SessionDiagnosticEvent) async {
        let safeEvent: SafeDiagnosticEvent
        switch event {
        case let .authentication(outcome):
            safeEvent = SafeDiagnosticEvent(
                operation: .nativeAuthentication,
                outcome: outcome,
                handle: SafeDiagnosticHandle()
            )
        case let .entitlement(outcome):
            safeEvent = SafeDiagnosticEvent(
                operation: .entitlement,
                outcome: outcome,
                handle: SafeDiagnosticHandle()
            )
        case .credentialPersistenceFailed:
            safeEvent = SafeDiagnosticEvent(
                operation: .nativeAuthentication,
                outcome: .credentialPersistenceFailed,
                handle: SafeDiagnosticHandle()
            )
        }
        sink.record(safeEvent)
    }
}
