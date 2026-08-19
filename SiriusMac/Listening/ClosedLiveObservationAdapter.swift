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
    case nestingLimit = "catalog-nesting-limit"
    case candidateBeyondNestingLimit = "catalog-channel-beyond-nesting-limit"
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
    /// The current public player navigates its Channels entry through this
    /// fixed browse-page route. Keep the published page identity private to
    /// this allowlist rather than accepting caller-provided catalog targets.
    private static let host = "api.edge-gateway.siriusxm.com"
    private static let path = "/browse/v1/pages/curated-grouping/403ab6a5-d3c9-4c2a-a722-a94a6a5fd056"

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

/// The one catalog-admitted channel the owner selected for the temporary tune
/// checkpoint. It is a fixed safe display identity, not a caller-supplied tune
/// target or a reusable production selection API.
enum ClosedTuneSelection {
    static let approved = ClosedCatalogChannel(
        id: "194adbca-34d6-cb94-b153-3488ee563308",
        displayName: "SiriusXM Hits 1",
        category: nil,
        isFavorite: nil,
        isAvailable: nil
    )
    static let sourceType = "channel-linear"
}

enum ClosedTuneResult: Sendable, Equatable {
    case resourceAllowlistDecisionRequired
    case terminal(LiveProtectionClass)
    /// This result carries only one fixed diagnostic atom. It never preserves
    /// a response body, status value, header, URL, or provider error text.
    case classifiedTerminal(LiveProtectionClass, ClosedTuneFailure)
    case cancelled
    case alreadyConsumed
}

/// Fixed, privacy-safe diagnostic atoms for exact client-status outcomes. A
/// status alone cannot establish whether the provider rejected a request shape
/// or required an unavailable account-side control, so it is never promoted
/// beyond the closed unknown-contract failure domain.
enum ClosedTuneFailure: String, Sendable, Equatable {
    case http400 = "tune-http-400"
    case http404 = "tune-http-404"
    case http409 = "tune-http-409"
    case http422 = "tune-http-422"
}

protocol ClosedTuneRequestPerforming: Sendable {
    func send(_ request: URLRequest) async -> ClosedTuneTransportResult
}

enum ClosedTuneTransportResult: Sendable {
    case response(statusCode: Int, contentType: String?, body: Data)
    case redirect
    case transportFailure
}

/// Exact construction for the one current first-party tune operation. The
/// selected identity and every JSON field are fixed in this checkpoint-only
/// type; no caller can select a host, header, path, or request shape.
enum ClosedTuneRequestContract {
    private static let scheme = "https"
    private static let host = "api.edge-gateway.siriusxm.com"
    private static let path = "/playback/play/v1/tuneSource"
    private static let clockHeader = "x-sxm-clock"

    static func makeRequest(credential: AuthenticationCredential) -> URLRequest? {
        guard let url = URL(string: "\(scheme)://\(host)\(path)") else { return nil }
        return credential.withVolatileMaterial { material in
            guard let authorization = String(data: material, encoding: .utf8),
                  !authorization.isEmpty,
                  !authorization.contains(where: { $0.isWhitespace || $0.isNewline })
            else { return nil }

            let source: [String: Any] = [
                "id": ClosedTuneSelection.approved.id,
                "type": ClosedTuneSelection.sourceType,
                "hlsVersion": "V3",
                "manifestVariant": "WEB",
                "mtcVersion": "V2",
                "trackResumeSupported": false,
            ]
            guard let body = try? JSONSerialization.data(withJSONObject: ["sources": [source]]) else {
                return nil
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = body
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
            request.setValue(
                ClosedTuneLogicalClock.shared.nextHeaderValue(),
                forHTTPHeaderField: clockHeader
            )
            return isExact(request) ? request : nil
        }
    }

    static func isExact(_ request: URLRequest) -> Bool {
        request.url?.scheme == scheme &&
            request.url?.host == host &&
            request.url?.path == path &&
            request.url?.query == nil &&
            request.url?.fragment == nil &&
            request.httpMethod == "POST" &&
            request.value(forHTTPHeaderField: "Accept") == "application/json" &&
            request.value(forHTTPHeaderField: "Content-Type") == "application/json" &&
            request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true &&
            isLogicalClockHeader(request.value(forHTTPHeaderField: clockHeader)) &&
            hasExactBody(request.httpBody)
    }

    private static func hasExactBody(_ body: Data?) -> Bool {
        guard let body,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              Set(object.keys) == Set(["sources"]),
              let sources = object["sources"] as? [[String: Any]],
              sources.count == 1,
              let source = sources.first
        else { return false }

        return Set(source.keys) == Set([
            "id",
            "type",
            "hlsVersion",
            "manifestVariant",
            "mtcVersion",
            "trackResumeSupported",
        ]) &&
            source["id"] as? String == ClosedTuneSelection.approved.id &&
            source["type"] as? String == ClosedTuneSelection.sourceType &&
            source["hlsVersion"] as? String == "V3" &&
            source["manifestVariant"] as? String == "WEB" &&
            source["mtcVersion"] as? String == "V2" &&
            source["trackResumeSupported"] as? Bool == false
    }

    private static func isLogicalClockHeader(_ value: String?) -> Bool {
        guard let value,
              value.first == "[",
              value.last == "]"
        else { return false }

        let parts = value.dropFirst().dropLast().split(separator: ",", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy(isUnsignedDecimal)
    }

    private static func isUnsignedDecimal(_ value: Substring) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48 ... 57).contains($0) }
    }
}

/// The public web client emits `x-sxm-clock` as a logical `[epoch,counter]`
/// pair. This closed, one-request checkpoint keeps only the non-secret counter
/// in process memory; it neither reads nor writes cookies, Keychain items, or
/// persistent account state.
private final class ClosedTuneLogicalClock: @unchecked Sendable {
    static let shared = ClosedTuneLogicalClock()

    private static let maximumValue = 9_007_199_254_740_991
    private let lock = NSLock()
    private var epoch = 0
    private var counter = -1

    func nextHeaderValue() -> String {
        lock.lock()
        defer { lock.unlock() }

        if counter >= Self.maximumValue {
            counter = 0
            epoch = epoch >= Self.maximumValue ? 0 : epoch + 1
        } else {
            counter += 1
        }
        return "[\(epoch),\(counter)]"
    }
}

/// The tune transport is separate from catalog transport so a request cannot
/// cross the two exact contract predicates. It cancels every redirect before a
/// location can become a result or a follow-up request.
final class ClosedTuneTransport: NSObject, ClosedTuneRequestPerforming, @unchecked Sendable {
    enum RedirectDecision: Sendable, Equatable { case cancel }

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

    func send(_ request: URLRequest) async -> ClosedTuneTransportResult {
        guard ClosedTuneRequestContract.isExact(request) else { return .transportFailure }
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

extension ClosedTuneTransport: URLSessionTaskDelegate {
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

/// Single-use owner-selected tune checkpoint. A matching source and a single
/// HTTPS resource candidate may become only a resource-policy decision; this
/// type never requests that resource or an associated media key.
@MainActor
final class ClosedTuneObservationAdapter {
    enum StartResult: Equatable {
        case started
        case entitlementRequired
        case alreadyConsumed
    }

    private let sink: LiveContractObservationSink
    private let credentialLoader: @MainActor @Sendable () -> ClosedCatalogCredentialAvailability
    private let transport: any ClosedTuneRequestPerforming
    private var hasRun = false

    init(
        sink: LiveContractObservationSink = LiveContractObservationSink(),
        credentialLoader: @escaping @MainActor @Sendable () -> ClosedCatalogCredentialAvailability = { .missing },
        transport: any ClosedTuneRequestPerforming = ClosedTuneTransport()
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

    func cancel() {
        sink.cancel()
    }

    func runTune() async -> ClosedTuneResult {
        guard state != .closed(.cancelled) else { return .cancelled }
        guard state == .active, !hasRun else { return .alreadyConsumed }
        hasRun = true

        let credential: AuthenticationCredential
        switch credentialLoader() {
        case let .available(value): credential = value
        case .missing, .invalid: return terminalTuneResult(.authorizationLost)
        }
        guard let request = ClosedTuneRequestContract.makeRequest(credential: credential) else {
            return terminalTuneResult(.authorizationLost)
        }

        switch await transport.send(request) {
        case .redirect:
            return terminalTuneResult(.unknownHostOrRedirect)
        case .transportFailure:
            return terminalTuneResult(.unknownContract)
        case let .response(statusCode, contentType, body):
            var responseBody = body
            defer { responseBody = Data() }

            if let protection = terminalProtection(for: statusCode) {
                return terminalTuneResult(protection)
            }
            if let failure = requestContractFailure(for: statusCode) {
                return terminalTuneResult(.unknownContract, failure: failure)
            }
            guard (200 ... 299).contains(statusCode) else {
                return terminalTuneResult(.unknownContract)
            }
            guard isJSON(contentType) else { return terminalTuneResult(.malformedContract) }
            guard ClosedTuneParser.hasMatchingHTTPSResource(responseBody) else {
                return terminalTuneResult(.malformedContract)
            }

            _ = sink.record(
                LiveContractObservation(
                    capability: .tuneAuthorization,
                    disposition: .supported,
                    requestContract: LiveRequestContract(
                        purpose: .selectedTune,
                        method: .post,
                        authorizedHostPolicy: .firstPartyAuthenticated,
                        pathTemplate: .tune
                    ),
                    semanticShapes: [
                        LiveSemanticShape(alias: .selectedChannel, valueType: .string, cardinality: .one),
                        LiveSemanticShape(alias: .authorizedResource, valueType: .string, cardinality: .one),
                    ],
                    protection: nil,
                    avFoundationBehavior: .notObserved
                )
            )
            return .resourceAllowlistDecisionRequired
        }
    }

    private func terminalTuneResult(
        _ protection: LiveProtectionClass,
        failure: ClosedTuneFailure? = nil
    ) -> ClosedTuneResult {
        _ = sink.record(
            LiveContractObservation(
                capability: .tuneAuthorization,
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

    /// The current public playback bundle documents a separate enforcement
    /// operation, but no tune-failure body schema that can truthfully identify
    /// CAPTCHA, MFA, or another user-mediated control. Do not inspect opaque
    /// provider text or upgrade an arbitrary 4xx into that classification.
    /// Future support may add an exact, source-derived structural control
    /// predicate here; until then every unrecognized response stops closed.
    private func terminalProtection(for statusCode: Int) -> LiveProtectionClass? {
        switch statusCode {
        case 401: .authorizationLost
        case 403: .forbidden
        case 429: .rateLimited
        case 300 ... 399: .unknownHostOrRedirect
        default: nil
        }
    }

    private func requestContractFailure(for statusCode: Int) -> ClosedTuneFailure? {
        switch statusCode {
        case 400: .http400
        case 404: .http404
        case 409: .http409
        case 422: .http422
        default: nil
        }
    }

    private func isJSON(_ contentType: String?) -> Bool {
        contentType?.lowercased().split(separator: ";", maxSplits: 1).first == "application/json"
    }
}

private enum ClosedTuneParser {
    static func hasMatchingHTTPSResource(_ body: Data) -> Bool {
        guard body.count <= 1_048_576,
              let root = try? JSONSerialization.jsonObject(with: body),
              root is [String: Any] || root is [Any]
        else { return false }

        var matched = false
        func visit(_ value: Any, depth: Int) {
            guard !matched, depth <= 12 else { return }
            if let source = value as? [String: Any] {
                if source["id"] as? String == ClosedTuneSelection.approved.id,
                   source["type"] as? String == ClosedTuneSelection.sourceType,
                   let streams = source["streams"] as? [[String: Any]],
                   streams.contains(where: hasHTTPSResourceURL)
                {
                    matched = true
                    return
                }
                for child in source.values { visit(child, depth: depth + 1) }
            } else if let values = value as? [Any] {
                for child in values { visit(child, depth: depth + 1) }
            }
        }
        visit(root, depth: 0)
        return matched
    }

    private static func hasHTTPSResourceURL(_ stream: [String: Any]) -> Bool {
        guard let urls = stream["urls"] as? [[String: Any]] else { return false }
        return urls.contains(where: isHTTPSResource)
    }

    private static func isHTTPSResource(_ candidate: [String: Any]) -> Bool {
        guard let value = candidate["url"] as? String,
              let url = URL(string: value),
              url.scheme == "https",
              url.host != nil
        else { return false }
        return true
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

        let search = entities(in: root)
        guard !search.entities.isEmpty else {
            if search.foundCandidateBeyondNestingLimit {
                return .failure(.candidateBeyondNestingLimit)
            }
            if search.reachedNestingLimit {
                return .failure(.nestingLimit)
            }
            return .failure(.noAdmissibleChannel)
        }
        let channels = search.entities.compactMap(channel(from:))
        return channels.isEmpty ? .failure(.noValidChannelIdentity) : .channels(channels)
    }

    /// The one response establishes the provider's JSON nesting, but it is never
    /// retained. Traverse only bounded JSON containers to find explicitly linear
    /// entities; all emitted fields still pass the fixed semantic validators.
    private struct EntitySearch {
        var entities: [[String: Any]]
        var reachedNestingLimit: Bool
        var foundCandidateBeyondNestingLimit: Bool
    }

    private static func entities(in root: Any) -> EntitySearch {
        var results: [[String: Any]] = []
        var reachedNestingLimit = false
        var foundCandidateBeyondNestingLimit = false

        func visit(_ value: Any, depth: Int) {
            guard results.count < 2_000 else { return }
            guard depth <= 32 else { return }
            if depth > 12 {
                reachedNestingLimit = true
            }
            if let entity = value as? [String: Any] {
                if entity["type"] as? String == "channel-linear" {
                    if depth <= 12 {
                        results.append(entity)
                    } else {
                        foundCandidateBeyondNestingLimit = true
                    }
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
        return EntitySearch(
            entities: results,
            reachedNestingLimit: reachedNestingLimit,
            foundCandidateBeyondNestingLimit: foundCandidateBeyondNestingLimit
        )
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
