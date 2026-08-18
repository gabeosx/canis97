import OSLog

/// Closed operation labels that may be emitted by the client diagnostic sink.
enum SafeDiagnosticOperation: String, Sendable, Equatable {
    case nativeAuthentication = "native-authentication"
    case entitlement
    case sessionCleanup = "session-cleanup"
}

/// Closed outcome labels that contain no provider, account, request, or error detail.
enum SafeDiagnosticOutcome: String, Sendable, Equatable {
    case completed
    case rejected
    case challengeRequired = "challenge-required"
    case unsupported
    case cancelled
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
