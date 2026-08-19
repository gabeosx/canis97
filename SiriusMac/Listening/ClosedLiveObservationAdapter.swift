import Foundation
@_spi(AppIntegration) import SiriusXMClient

/// The only credential state the temporary catalog checkpoint can observe.
/// No error, material, cookie, or Keychain result leaves the app boundary.
enum ClosedCatalogCredentialAvailability: Sendable {
    case available(AuthenticationCredential)
    case missing
    case invalid
}

/// A deliberately bounded channel shape for owner selection during the checkpoint.
/// These values stay in memory and are validated before the UI receives them.
struct ClosedCatalogChannel: Sendable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let category: String?
    let isFavorite: Bool?
    let isAvailable: Bool?
}

/// Closed result vocabulary for the one catalog request.
enum ClosedCatalogResult: Sendable, Equatable {
    case channels([ClosedCatalogChannel])
    case terminal(LiveProtectionClass)
    /// This result may expose only a fixed, non-provider diagnostic atom. It
    /// never includes a response value, response key, header, URL, or count.
    case classifiedTerminal(LiveProtectionClass, ClosedCatalogFailure)
}

/// Fixed, privacy-safe reasons why an otherwise successful catalog response
/// could not become a selectable channel list. These classify parser state,
/// rather than preserving any provider response material.
enum ClosedCatalogFailure: String, Sendable, Equatable {
    case nonJSONContent = "catalog-non-json-content"
    case documentTooLarge = "catalog-document-too-large"
    case invalidJSON = "catalog-invalid-json"
    case unsupportedRoot = "catalog-unsupported-root"
    case noAdmissibleChannel = "catalog-no-admissible-channel"
    case noValidChannelIdentity = "catalog-no-valid-channel-identity"
}

/// The testable, private request seam. Implementations must return no URL,
/// header, error, redirect, or other raw transport material.
protocol ClosedCatalogRequestPerforming: Sendable {
    func send(_ request: URLRequest) async -> ClosedCatalogTransportResult
}

enum ClosedCatalogTransportResult: Sendable {
    case response(statusCode: Int, contentType: String?, body: Data)
    case redirect
    case transportFailure
}

/// Exact candidate request construction. No arbitrary host, path, method,
/// request body, query, or caller-provided header can enter this boundary.
enum ClosedCatalogRequestContract {
    private static let scheme = "https"
    private static let host = "browse-at-edge.siriusxm.com"
    private static let path = "/v2/all-channels"

    static func makeRequest(credential: AuthenticationCredential) -> URLRequest? {
        guard let url = URL(string: "\(scheme)://\(host)\(path)") else { return nil }
        return credential.withVolatileMaterial { material in
            guard let authorization = String(data: material, encoding: .utf8),
                  !authorization.isEmpty,
                  !authorization.contains(where: { $0.isWhitespace || $0.isNewline })
            else { return nil }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
            return isExact(request) ? request : nil
        }
    }

    static func isExact(_ request: URLRequest) -> Bool {
        request.url?.scheme == scheme &&
            request.url?.host == host &&
            request.url?.path == path &&
            request.url?.query == nil &&
            request.url?.fragment == nil &&
            request.httpMethod == "GET" &&
            request.httpBody == nil &&
            request.value(forHTTPHeaderField: "Accept") == "application/json" &&
            request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true
    }
}

/// Ephemeral direct transport that cancels every redirect and returns only the
/// status family, content type, and transient response bytes to the parser.
final class ClosedCatalogTransport: NSObject, ClosedCatalogRequestPerforming, @unchecked Sendable {
    enum RedirectDecision: Sendable, Equatable {
        case cancel
    }

    static let redirectDecision: RedirectDecision = .cancel

    private let redirectLock = NSLock()
    private var redirectWasObserved = false
    private lazy var session = URLSession(
        configuration: Self.makeConfiguration(),
        delegate: self,
        delegateQueue: nil
    )

    private static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        return configuration
    }

    func send(_ request: URLRequest) async -> ClosedCatalogTransportResult {
        guard ClosedCatalogRequestContract.isExact(request) else { return .transportFailure }
        setObservedRedirect(false)

        do {
            var responseData = Data()
            defer { responseData = Data() }
            let response: URLResponse
            (responseData, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { return .transportFailure }
            return .response(
                statusCode: response.statusCode,
                contentType: response.value(forHTTPHeaderField: "Content-Type"),
                body: responseData
            )
        } catch {
            return observedRedirect ? .redirect : .transportFailure
        }
    }
}

extension ClosedCatalogTransport: URLSessionTaskDelegate {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        setObservedRedirect(true)
        completionHandler(nil)
    }

    private var observedRedirect: Bool {
        redirectLock.lock()
        defer { redirectLock.unlock() }
        return redirectWasObserved
    }

    private func setObservedRedirect(_ value: Bool) {
        redirectLock.lock()
        redirectWasObserved = value
        redirectLock.unlock()
    }
}

/// Temporary checkpoint-only authority for the exact catalog candidate.
@MainActor
final class ClosedLiveObservationAdapter {
    enum StartResult: Equatable {
        case started
        case entitlementRequired
        case alreadyConsumed
    }

    private let sink: LiveContractObservationSink
    private let credentialLoader: @MainActor @Sendable () -> ClosedCatalogCredentialAvailability
    private let transport: any ClosedCatalogRequestPerforming

    init(
        sink: LiveContractObservationSink = LiveContractObservationSink(),
        credentialLoader: @escaping @MainActor @Sendable () -> ClosedCatalogCredentialAvailability = { .missing },
        transport: any ClosedCatalogRequestPerforming = ClosedCatalogTransport()
    ) {
        self.sink = sink
        self.credentialLoader = credentialLoader
        self.transport = transport
    }

    var observations: [LiveContractObservation] { sink.observations }
    var state: LiveContractObservationState { sink.state }

    func begin(entitlement: EntitlementAvailability) -> StartResult {
        guard entitlement == .entitled else { return .entitlementRequired }
        return sink.begin() ? .started : .alreadyConsumed
    }

    /// Executes exactly one allow-listed catalog GET after entitlement is already
    /// derived. Every outcome becomes a closed semantic result immediately.
    func runCatalog() async -> ClosedCatalogResult {
        guard state == .active else { return .terminal(.unknownContract) }

        let credential: AuthenticationCredential
        switch credentialLoader() {
        case let .available(value): credential = value
        case .missing, .invalid: return terminalCatalogResult(.authorizationLost)
        }

        guard let request = ClosedCatalogRequestContract.makeRequest(credential: credential) else {
            return terminalCatalogResult(.authorizationLost)
        }

        switch await transport.send(request) {
        case .redirect:
            return terminalCatalogResult(.unknownHostOrRedirect)
        case .transportFailure:
            return terminalCatalogResult(.unknownContract)
        case let .response(statusCode, contentType, body):
            guard (200 ... 299).contains(statusCode) else {
                return terminalCatalogResult(protection(for: statusCode))
            }
            guard isJSON(contentType) else {
                return terminalCatalogResult(.malformedContract, failure: .nonJSONContent)
            }

            var responseBody = body
            defer { responseBody = Data() }
            switch ClosedCatalogParser.parse(responseBody) {
            case let .channels(channels):
                _ = sink.record(
                    LiveContractObservation(
                        capability: .catalogRefresh,
                        disposition: .supported,
                        requestContract: LiveRequestContract(
                            purpose: .catalogObservation,
                            method: .get,
                            authorizedHostPolicy: .firstPartyAuthenticated,
                            pathTemplate: .catalog
                        ),
                        semanticShapes: [
                            LiveSemanticShape(alias: .catalogEntity, valueType: .object, cardinality: .many),
                            LiveSemanticShape(alias: .selectedChannel, valueType: .string, cardinality: .one),
                        ],
                        protection: nil,
                        avFoundationBehavior: .notObserved
                    )
                )
                return .channels(channels)
            case let .failure(failure):
                return terminalCatalogResult(.malformedContract, failure: failure)
            }
        }
    }

    private func terminalCatalogResult(
        _ protection: LiveProtectionClass,
        failure: ClosedCatalogFailure? = nil
    ) -> ClosedCatalogResult {
        _ = sink.record(
            LiveContractObservation(
                capability: .catalogRefresh,
                disposition: .unsupported,
                requestContract: nil,
                semanticShapes: [],
                protection: protection,
                avFoundationBehavior: .notObserved
            )
        )
        if let failure {
            return .classifiedTerminal(protection, failure)
        }
        return .terminal(protection)
    }

    private func protection(for statusCode: Int) -> LiveProtectionClass {
        switch statusCode {
        case 401: .authorizationLost
        case 403: .forbidden
        case 429: .rateLimited
        case 300 ... 399: .unknownHostOrRedirect
        case 400 ... 499: .humanVerificationRequired
        default: .unknownContract
        }
    }

    private func isJSON(_ contentType: String?) -> Bool {
        contentType?.lowercased().split(separator: ";", maxSplits: 1).first == "application/json"
    }
}

private enum ClosedCatalogParser {
    enum Result {
        case channels([ClosedCatalogChannel])
        case failure(ClosedCatalogFailure)
    }

    /// The current first-party player consumes a complete page graph rather than
    /// a flat lineup. Keep the transient decode bounded, but leave enough room
    /// for its container, set, item, image, and decoration metadata.
    private static let maximumDocumentBytes = 8 * 1_024 * 1_024

    static func parse(_ body: Data) -> Result {
        guard body.count <= maximumDocumentBytes else {
            return .failure(.documentTooLarge)
        }
        guard let root = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]) else {
            return .failure(.invalidJSON)
        }
        guard root is [String: Any] || root is [Any] else {
            return .failure(.unsupportedRoot)
        }

        let candidates = entities(in: root)
        guard !candidates.isEmpty else {
            return .failure(.noAdmissibleChannel)
        }
        let channels = candidates.compactMap(channel(from:))
        return channels.isEmpty ? .failure(.noValidChannelIdentity) : .channels(channels)
    }

    /// The one response establishes the provider's JSON nesting, but it is never
    /// retained. Traverse only bounded JSON containers to find explicitly linear
    /// entities; all emitted fields still pass the fixed semantic validators.
    private static func entities(in root: Any) -> [[String: Any]] {
        var results: [[String: Any]] = []

        func visit(_ value: Any, depth: Int) {
            guard depth <= 12, results.count < 2_000 else { return }
            if let entity = value as? [String: Any] {
                if entity["type"] as? String == "channel-linear" {
                    results.append(entity)
                }
                for child in entity.values {
                    visit(child, depth: depth + 1)
                }
            } else if let values = value as? [Any] {
                for child in values {
                    visit(child, depth: depth + 1)
                }
            }
        }

        visit(root, depth: 0)
        return results
    }

    private static func channel(from entity: [String: Any]) -> ClosedCatalogChannel? {
        guard entity["type"] as? String == "channel-linear",
              let id = safeIdentifier(entity["id"] as? String)
        else { return nil }

        return ClosedCatalogChannel(
            id: id,
            displayName: safeText(entity["name"] as? String) ?? title(in: entity) ?? id,
            category: safeText(entity["category"] as? String),
            isFavorite: entity["isFavorite"] as? Bool,
            isAvailable: entity["isAvailable"] as? Bool
        )
    }

    /// The current first-party browse renderer reads a channel's title from
    /// `item.entity.texts.title.default`; preserve only its bounded display
    /// string after the surrounding page graph has been discarded.
    private static func title(in entity: [String: Any]) -> String? {
        guard let texts = entity["texts"] as? [String: Any],
              let title = texts["title"] as? [String: Any]
        else { return nil }
        return safeText(title["default"] as? String)
    }

    private static func safeIdentifier(_ value: String?) -> String? {
        guard let value,
              (1 ... 96).contains(value.utf8.count),
              value.unicodeScalars.allSatisfy({ scalar in
                  scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "._-".unicodeScalars.contains(scalar))
              })
        else { return nil }
        return value
    }

    private static func safeText(_ value: String?) -> String? {
        guard let value,
              (1 ... 128).contains(value.utf8.count),
              value.unicodeScalars.allSatisfy({ scalar in
                  scalar.isASCII && scalar.value >= 0x20 && scalar.value <= 0x7E
              })
        else { return nil }
        return value
    }
}
