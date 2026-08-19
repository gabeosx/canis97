import AVFoundation
import Foundation

/// Strict, non-retaining compatibility classifiers for the Phase 02 contract.
/// It intentionally exposes only a closed inspection result: opaque response
/// values never cross this adapter boundary.
enum LiveListeningAdapter {
    enum PlaybackKeyInspection: Sendable, Equatable {
        case accepted
        case unsupported(SafeDiagnosticOutcome)
    }

    enum CatalogPreflightInspection: Sendable, Equatable {
        case accepted
        case unsupported(SafeDiagnosticOutcome)
    }

    static func inspectPlaybackKey(_ response: NativeTransportResponse) -> PlaybackKeyInspection {
        if let failure = preflightFailure(for: response) {
            return .unsupported(failure)
        }

        guard let root = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              Set(root.keys) == ["keyId", "key"],
              root["keyId"] is String,
              root["key"] is String
        else {
            return .unsupported(.playbackKeyUnexpectedShape)
        }
        return .accepted
    }

    static func inspectCatalogPreflight(_ response: NativeTransportResponse) -> CatalogPreflightInspection {
        if let failure = preflightFailure(for: response) {
            return .unsupported(failure)
        }
        return .accepted
    }

    private static func preflightFailure(for response: NativeTransportResponse) -> SafeDiagnosticOutcome? {
        if let transportFailure = response.transportFailure {
            return transportFailure.diagnosticOutcome
        }
        guard response.redirectLocation == nil else { return .redirectDrift }

        switch response.statusCode {
        case 401, 403: return .rejected
        case 429: return .rateLimited
        case 404: return .httpNotFound
        case 400 ... 499: return .httpClientError
        case 500 ... 599: return .httpServerError
        case 200 ... 299: break
        default: return .unsupportedHTTPStatus
        }

        guard let contentType = response.contentType else { return .contentTypeMissing }
        let normalizedContentType = contentType.lowercased()
        guard normalizedContentType.hasPrefix("application/json") else {
            return normalizedContentType.hasPrefix("text/html") ? .contentTypeHTML : .unsupportedContentType
        }

        guard !containsProtectedControl(response.body) else { return .challengeRequired }
        return nil
    }

    private static func containsProtectedControl(_ body: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return false
        }
        if object["bot"] as? Bool == true { return true }
        guard let challenge = object["challenge"] as? String else { return false }
        return ["captcha", "mfa", "control"].contains(challenge.lowercased())
    }
}

/// Internal transport seam for the only supported production live sequence.
/// It has no arbitrary request, resource, header, or URL entry point.
protocol FixedLiveTransporting: Sendable {
    func tune(
        for channelID: LiveChannelID,
        using credential: AuthenticationCredential
    ) async -> NativeTransportResponse
    func playbackKey(
        for keyID: FixedLivePlaybackKeyID,
        using credential: AuthenticationCredential
    ) async -> NativeTransportResponse
}

/// Opaque key identifier admitted only by the strict tune decoder.
struct FixedLivePlaybackKeyID: Sendable, Equatable {
    fileprivate let value: String
}

private struct FixedLiveResourceSelection: Sendable {
    let channelID: LiveChannelID
    let url: URL
    let keyID: FixedLivePlaybackKeyID
}

/// Concrete production implementation of the narrow tune -> handoff -> key
/// sequence. It is actor-owned and has no credential or provider-material API.
actor CurrentSessionFixedLiveOperations: FixedLiveStreamOperating {
    private let sessionCoordinator: SessionCoordinator
    private let transport: any FixedLiveTransporting
    private var resource: FixedLiveResourceSelection?
    private var handoff: FixedLiveAppleMediaHandoff?

    init(
        sessionCoordinator: SessionCoordinator,
        transport: any FixedLiveTransporting
    ) {
        self.sessionCoordinator = sessionCoordinator
        self.transport = transport
    }

    func authorizeTune(for channelID: LiveChannelID) async -> FixedLiveTuneAuthorization {
        resource = nil
        handoff = nil

        switch await sessionCoordinator.withCurrentEntitledCredential({ [transport] credential in
            await transport.tune(for: channelID, using: credential)
        }) {
        case let .failed(failure):
            return .failed(failure)
        case let .completed(response):
            if let failure = FixedLiveResponseDecoder.failure(for: response, operation: .tune) {
                return .failed(failure)
            }
            guard let selection = FixedLiveResponseDecoder.tuneSelection(
                from: response.body,
                expectedChannelID: channelID
            ) else {
                return .failed(.malformedResource)
            }
            resource = selection
            handoff = FixedLiveAppleMediaHandoff(url: selection.url)
            return .authorized
        }
    }

    func resolveResource(for channelID: LiveChannelID) async -> FixedLiveResourceResolution {
        guard let resource,
              let handoff,
              FixedLiveResponseDecoder.isCurrent(resource: resource, for: channelID)
        else {
            return .failed(.resourceUnavailable)
        }
        return .resolved(handoff, keyRequirement: .required)
    }

    func authorizePlaybackKey() async -> LiveStreamResolutionFailure? {
        guard let resource, let handoff else { return .resourceUnavailable }

        switch await sessionCoordinator.withCurrentEntitledCredential({ [transport] credential in
            await transport.playbackKey(for: resource.keyID, using: credential)
        }) {
        case let .failed(failure):
            return failure
        case let .completed(response):
            if let failure = FixedLiveResponseDecoder.failure(for: response, operation: .playbackKey) {
                return failure
            }
            guard let key = FixedLiveResponseDecoder.playbackKey(
                from: response.body,
                matching: resource.keyID
            ) else {
                return .unsupportedProtection
            }
            handoff.attachAuthorizedKey(key)
            return nil
        }
    }
}

/// A private handoff retaining approved material only until `AVPlayerItem`
/// construction. No ordinary API can inspect its URL or key material.
private final class FixedLiveAppleMediaHandoff: SiriusXMAppleMediaHandoff, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var authorizedKey: Data?

    init(url: URL) {
        self.url = url
    }

    func attachAuthorizedKey(_ key: Data) {
        lock.lock()
        authorizedKey = key
        lock.unlock()
    }

    @MainActor func makePlayerItem() -> AVPlayerItem? {
        lock.lock()
        let canCreateItem = authorizedKey != nil
        lock.unlock()
        guard canCreateItem else { return nil }

        // The contract does not authorize synthesizing resource-loader headers
        // or a DRM/key mapping. AVFoundation receives only the fixed signed URL.
        return AVPlayerItem(asset: AVURLAsset(url: url))
    }
}

private enum FixedLiveOperation {
    case tune
    case playbackKey
}

private enum FixedLiveResponseDecoder {
    private static let maximumBodyBytes = 1_048_576

    static func failure(
        for response: NativeTransportResponse,
        operation: FixedLiveOperation
    ) -> LiveStreamResolutionFailure? {
        if let transportFailure = response.transportFailure {
            return transportFailure == .cancelled ? .cancelled : .networkUnavailable
        }
        guard response.redirectLocation == nil else { return .protectedControl }

        switch response.statusCode {
        case 401, 403: return .authenticationUnavailable
        case 429: return .protectedControl
        case 200 ... 299: break
        case 400 ... 499: return operation == .tune ? .tuneUnavailable : .unsupportedProtection
        case 500 ... 599: return .networkUnavailable
        default: return .resourceUnavailable
        }

        guard response.body.count <= maximumBodyBytes,
              let contentType = response.contentType?.lowercased(),
              contentType.hasPrefix("application/json")
        else { return operation == .tune ? .malformedResource : .unsupportedProtection }
        guard !containsProtectedControl(response.body) else { return .protectedControl }
        return nil
    }

    static func tuneSelection(
        from body: Data,
        expectedChannelID: LiveChannelID
    ) -> FixedLiveResourceSelection? {
        guard body.count <= maximumBodyBytes,
              let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let source = root["source"] as? [String: Any],
              source["id"] as? String == expectedChannelID.rawValue,
              source["type"] as? String == "channel-linear",
              let streams = source["streams"] as? [[String: Any]]
        else { return nil }

        for stream in streams {
            guard let urls = stream["urls"] as? [[String: Any]] else { continue }
            for candidate in urls {
                guard let value = candidate["url"] as? String,
                      let url = validMediaURL(value),
                      let keyID = candidate["encryptionKeyId"] as? String,
                      !keyID.isEmpty
                else { continue }
                return FixedLiveResourceSelection(
                    channelID: expectedChannelID,
                    url: url,
                    keyID: FixedLivePlaybackKeyID(value: keyID)
                )
            }
        }
        return nil
    }

    static func playbackKey(from body: Data, matching keyID: FixedLivePlaybackKeyID) -> Data? {
        guard body.count <= maximumBodyBytes,
              let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              Set(root.keys) == ["keyId", "key"],
              root["keyId"] as? String == keyID.value,
              let value = root["key"] as? String,
              !value.isEmpty
        else { return nil }
        return Data(value.utf8)
    }

    static func isCurrent(resource: FixedLiveResourceSelection, for channelID: LiveChannelID) -> Bool {
        resource.channelID == channelID && resource.url.host == SiriusXMRequestContract.opaqueMediaDeliveryHost
    }

    private static func validMediaURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == SiriusXMRequestContract.opaqueMediaDeliveryHost,
              url.port == nil,
              url.user == nil,
              url.password == nil,
              !url.path.isEmpty
        else { return nil }
        return url
    }

    private static func containsProtectedControl(_ body: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return false
        }
        if object["bot"] as? Bool == true { return true }
        guard let challenge = object["challenge"] as? String else { return false }
        return ["captcha", "mfa", "control"].contains(challenge.lowercased())
    }
}

/// Direct, ephemeral transport for the two fixed provider operations. Each
/// request is individually constructed and every redirect is cancelled.
final class FixedLiveURLSessionTransport: NSObject, FixedLiveTransporting, @unchecked Sendable {
    private let redirectLock = NSLock()
    private var redirectObserved = false
    private lazy var session = URLSession(
        configuration: Self.makeConfiguration(),
        delegate: self,
        delegateQueue: nil
    )

    func tune(for channelID: LiveChannelID, using credential: AuthenticationCredential) async -> NativeTransportResponse {
        guard let request = FixedLiveRequestFactory.tune(for: channelID, using: credential) else {
            return Self.failedResponse
        }
        return await send(request)
    }

    func playbackKey(for keyID: FixedLivePlaybackKeyID, using credential: AuthenticationCredential) async -> NativeTransportResponse {
        guard let request = FixedLiveRequestFactory.playbackKey(for: keyID, using: credential) else {
            return Self.failedResponse
        }
        return await send(request)
    }

    private func send(_ request: URLRequest) async -> NativeTransportResponse {
        redirectLock.withLock { redirectObserved = false }
        do {
            let (body, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { return Self.failedResponse }
            return NativeTransportResponse(
                statusCode: response.statusCode,
                contentType: response.value(forHTTPHeaderField: "Content-Type"),
                body: body,
                redirectLocation: response.value(forHTTPHeaderField: "Location")
            )
        } catch {
            let redirected = redirectLock.withLock { redirectObserved }
            return NativeTransportResponse(
                statusCode: 0,
                contentType: nil,
                body: Data(),
                redirectLocation: redirected ? "blocked" : nil,
                transportFailure: redirected ? nil : SafeTransportFailure(error: error)
            )
        }
    }

    private static var failedResponse: NativeTransportResponse {
        NativeTransportResponse(statusCode: 0, contentType: nil, body: Data(), transportFailed: true)
    }

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
}

extension FixedLiveURLSessionTransport: URLSessionTaskDelegate {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        redirectLock.withLock { redirectObserved = true }
        completionHandler(nil)
    }
}

private enum FixedLiveRequestFactory {
    private static let host = SiriusXMRequestContract.host
    private static let scheme = "https"
    private static let logicalClock = FixedLiveLogicalClock()

    static func tune(for channelID: LiveChannelID, using credential: AuthenticationCredential) -> URLRequest? {
        guard let url = URL(string: "\(scheme)://\(host)/playback/play/v1/tuneSource") else { return nil }
        return credential.withVolatileMaterial { material in
            guard let authorization = validAuthorization(material) else { return nil }
            let source: [String: Any] = [
                "id": channelID.rawValue,
                "type": "channel-linear",
                "hlsVersion": "V3",
                "manifestVariant": "WEB",
                "mtcVersion": "V2",
                "trackResumeSupported": false,
            ]
            guard let body = try? JSONSerialization.data(withJSONObject: ["sources": [source]]) else { return nil }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = body
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
            request.setValue(logicalClock.next(), forHTTPHeaderField: "x-sxm-clock")
            return request
        }
    }

    static func playbackKey(for keyID: FixedLivePlaybackKeyID, using credential: AuthenticationCredential) -> URLRequest? {
        let allowedPathCharacters = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        guard let encodedKeyID = keyID.value.addingPercentEncoding(withAllowedCharacters: allowedPathCharacters),
              let url = URL(string: "\(scheme)://\(host)/playback/key/v1/\(encodedKeyID)")
        else { return nil }
        return credential.withVolatileMaterial { material in
            guard let authorization = validAuthorization(material) else { return nil }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
            return request
        }
    }

    private static func validAuthorization(_ material: Data) -> String? {
        guard let authorization = String(data: material, encoding: .utf8),
              !authorization.isEmpty,
              !authorization.contains(where: { $0.isWhitespace || $0.isNewline })
        else { return nil }
        return authorization
    }
}

private final class FixedLiveLogicalClock: @unchecked Sendable {
    private let lock = NSLock()
    private var counter = 0

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        let value = counter
        counter &+= 1
        return "[0,\(value)]"
    }
}
