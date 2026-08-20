import AVFoundation
import Foundation
import ObjectiveC
import OSLog
import UniformTypeIdentifiers

/// A one-request redirect observer. It deliberately stores only a boolean,
/// never the redirect target or request, and cancels every redirect follow-up.
final class PerRequestRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var redirectObserved = false

    var didObserveRedirect: Bool {
        lock.withLock { redirectObserved }
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        lock.withLock { redirectObserved = true }
        completionHandler(nil)
    }
}
import ImageIO

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

    /// Decodes only the observed selected-channel lookaround shape. The first
    /// cut is the sole admitted current program; shows are intentionally not a
    /// replacement source.
    static func decodeMetadata(
        _ response: NativeTransportResponse,
        channelID: LiveChannelID
    ) -> MetadataAvailability {
        guard preflightFailure(for: response) == nil,
              let root = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              root["channels"] is [String: Any],
              root["delta"] is String,
              let channels = root["channels"] as? [String: Any],
              let channel = channels[channelID.rawValue] as? [String: Any],
              let cuts = channel["cuts"] as? [[String: Any]]
        else { return .failed(.unsupportedResponse) }
        guard let first = cuts.first else { return .unavailable }
        guard let title = first["name"] as? String, !title.isEmpty,
              let validFrom = first["validFrom"] as? String,
              ISO8601DateFormatter().date(from: validFrom) != nil
        else { return .failed(.unsupportedResponse) }
        let artist = first["artistName"] as? String
        let artwork = artworkReference(from: first["image"])
        return .current(MetadataSnapshot(channelID: channelID, program: LiveProgramMetadata(title: title, artist: artist, artwork: artwork)))
    }

    static func decodeArtwork(_ response: NativeTransportResponse) -> ArtworkAvailability {
        guard response.transportFailure == nil,
              response.redirectLocation == nil,
              (200 ... 299).contains(response.statusCode),
              response.body.count <= 5 * 1_024 * 1_024,
              let contentType = response.contentType?.lowercased(),
              let mediaType: ArtworkMediaType = contentType.hasPrefix("image/jpeg") ? .jpeg : contentType.hasPrefix("image/png") ? .png : nil,
              let source = CGImageSourceCreateWithData(response.body as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0, height.intValue > 0,
              width.intValue <= 4096, height.intValue <= 4096
        else { return .unavailable }
        return .current(ArtworkData(bytes: response.body, mediaType: mediaType))
    }

    private static func artworkReference(from value: Any?) -> ChannelArtworkReference? {
        guard let image = value as? [String: Any],
              let reference = image["url"] as? String,
              reference.hasPrefix("/"),
              !reference.contains(".."),
              URL(string: reference)?.scheme == nil,
              let width = image["width"] as? NSNumber,
              let height = image["height"] as? NSNumber,
              width.intValue > 0, height.intValue > 0,
              width.intValue <= 4096, height.intValue <= 4096,
              ["jpeg", "jpg", "png"].contains(reference.split(separator: ".").last?.lowercased())
        else { return nil }
        return ChannelArtworkReference(relativeReference: reference)
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

/// Internal transport seam for the one fixed catalog refresh. It accepts no
/// arbitrary host, path, query, request body, or caller-provided headers.
protocol FixedCatalogTransporting: Sendable {
    func catalog(using credential: AuthenticationCredential) async -> NativeTransportResponse
}

/// Concrete fixed catalog request. The test-only exactness predicate verifies
/// shape without retaining authorization material or a request object.
enum FixedCatalogRequestFactory {
    private static let scheme = "https"
    private static let path = "/browse/v1/pages/curated-grouping/403ab6a5-d3c9-4c2a-a722-a94a6a5fd056"

    static func makeRequest(using credential: AuthenticationCredential) -> URLRequest? {
        guard let url = URL(string: "\(scheme)://\(SiriusXMRequestContract.host)\(path)") else { return nil }
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

    static func isExact(credential: AuthenticationCredential) -> Bool {
        guard let request = makeRequest(using: credential) else { return false }
        return isExact(request)
    }

    private static func isExact(_ request: URLRequest) -> Bool {
        request.url?.scheme == scheme &&
            request.url?.host == SiriusXMRequestContract.host &&
            request.url?.path == path &&
            request.url?.query == nil &&
            request.url?.fragment == nil &&
            request.httpMethod == "GET" &&
            request.httpBody == nil &&
            request.value(forHTTPHeaderField: "Accept") == "application/json" &&
            request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true
    }
}

/// Ephemeral production transport for one fixed catalog request. Redirects
/// are cancelled and neither redirect targets nor transport errors escape.
final class FixedCatalogURLSessionTransport: FixedCatalogTransporting, @unchecked Sendable {
    private lazy var session = URLSession(configuration: Self.makeConfiguration())

    func catalog(using credential: AuthenticationCredential) async -> NativeTransportResponse {
        guard let request = FixedCatalogRequestFactory.makeRequest(using: credential) else {
            return Self.failedResponse
        }
        let redirectDelegate = PerRequestRedirectDelegate()
        do {
            let (body, response) = try await session.data(for: request, delegate: redirectDelegate)
            guard let response = response as? HTTPURLResponse else { return Self.failedResponse }
            return NativeTransportResponse(
                statusCode: response.statusCode,
                contentType: response.value(forHTTPHeaderField: "Content-Type"),
                body: body,
                redirectLocation: response.value(forHTTPHeaderField: "Location")
            )
        } catch {
            let redirected = redirectDelegate.didObserveRedirect
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

/// Decodes only the observed initial-page envelope. Pagination is deliberately
/// absent: one explicit refresh makes one fixed request and never invents a
/// query parameter or follow-up operation.
enum FixedCatalogResponseDecoder {
    private static let maximumBodyBytes = 1_048_576

    static func decode(_ response: NativeTransportResponse) -> LiveCatalogSnapshotResult {
        guard response.transportFailure == nil,
              response.redirectLocation == nil,
              (200 ... 299).contains(response.statusCode),
              response.body.count <= maximumBodyBytes,
              response.contentType?.lowercased().hasPrefix("application/json") == true,
              !containsProtectedControl(response.body),
              let root = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              let page = root["page"] as? [String: Any],
              let containers = page["containers"] as? [[String: Any]]
        else {
            return LiveCatalogSnapshotResult(snapshot: nil, failure: .unsupportedResponse)
        }

        var candidates: [LiveCatalogCandidate] = []
        for container in containers {
            guard let sets = container["sets"] as? [[String: Any]] else {
                return LiveCatalogSnapshotResult(snapshot: nil, failure: .collectionUnavailable)
            }
            for set in sets {
                guard let items = set["items"] as? [[String: Any]] else {
                    return LiveCatalogSnapshotResult(snapshot: nil, failure: .collectionUnavailable)
                }
                for item in items {
                    guard let candidate = candidate(from: item) else {
                        return LiveCatalogSnapshotResult(snapshot: nil, failure: .malformedCandidate)
                    }
                    candidates.append(candidate)
                }
            }
        }
        return LiveCatalogAdapter.snapshot(from: candidates)
    }

    private static func candidate(from item: [String: Any]) -> LiveCatalogCandidate? {
        guard let entity = item["entity"] as? [String: Any],
              let type = entity["type"] as? String,
              let identity = entity["id"] as? String,
              !identity.isEmpty
        else { return nil }

        if type == "channel-xtra" {
            return LiveCatalogCandidate(
                identity: identity, displayNumber: nil, name: nil, description: nil,
                category: nil, artwork: nil, entity: .xtra, entitlement: .notEntitled
            )
        }
        guard type == "channel-linear",
              let decorations = item["decorations"] as? [String: Any],
              let connectivity = decorations["connectivity"] as? String,
              let entitlement = entitlement(for: connectivity),
              decorations["contentTypeLabel"] as? String == "CHANNEL",
              let number = number(from: decorations["channelNumber"]),
              matchingPlayCapability(item["actions"], entityType: type, identity: identity)
        else { return nil }

        let texts = entity["texts"] as? [String: Any]
        let title = (texts?["title"] as? [String: Any])?["default"] as? String
        let description = (texts?["description"] as? [String: Any])?["default"] as? String
        return LiveCatalogCandidate(
            identity: identity,
            displayNumber: number,
            name: title,
            description: description,
            category: decorations["genre"] as? String,
            artwork: nil,
            entity: .channelLinear,
            entitlement: entitlement
        )
    }

    private static func entitlement(for connectivity: String) -> ChannelEntitlement? {
        switch connectivity {
        case "ip-and-sat": .entitledStandard
        case "ip": .entitledAppOnly
        default: nil
        }
    }

    private static func matchingPlayCapability(_ actions: Any?, entityType: String, identity: String) -> Bool {
        guard let actions = actions as? [String: Any],
              let play = actions["play"] as? [[String: Any]],
              !play.isEmpty
        else { return false }
        return play.contains { action in
            guard let entity = action["entity"] as? [String: Any] else { return false }
            return entity["type"] as? String == entityType && entity["id"] as? String == identity
        }
    }

    private static func number(from value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              Int(exactly: number.doubleValue) != nil
        else { return nil }
        return number.doubleValue
    }

    private static func containsProtectedControl(_ body: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return false }
        if object["bot"] as? Bool == true { return true }
        guard let challenge = object["challenge"] as? String else { return false }
        return ["captcha", "mfa", "control"].contains(challenge.lowercased())
    }
}

actor CurrentSessionCatalogRefresher: CatalogRefreshing {
    private let sessionCoordinator: SessionCoordinator
    private let transport: any FixedCatalogTransporting

    init(sessionCoordinator: SessionCoordinator, transport: any FixedCatalogTransporting) {
        self.sessionCoordinator = sessionCoordinator
        self.transport = transport
    }

    func refresh() async -> LiveCatalogSnapshotResult {
        switch await sessionCoordinator.withCurrentCatalogCredential({ [transport] credential in
            await transport.catalog(using: credential)
        }) {
        case let .completed(response):
            FixedCatalogResponseDecoder.decode(response)
        case .authenticationUnavailable:
            LiveCatalogSnapshotResult(snapshot: nil, failure: .authenticationUnavailable)
        case .notEntitled:
            LiveCatalogSnapshotResult(snapshot: nil, failure: .notEntitled)
        case .superseded:
            LiveCatalogSnapshotResult(snapshot: nil, failure: .cancelled)
        }
    }
}

/// Fixed metadata and artwork seam. It has no caller-provided host, query,
/// headers, or response exposure.
protocol FixedMetadataTransporting: Sendable {
    func lookaround(using credential: AuthenticationCredential) async -> NativeTransportResponse
    func artwork(for reference: ChannelArtworkReference) async -> NativeTransportResponse
}

final class FixedMetadataURLSessionTransport: FixedMetadataTransporting, @unchecked Sendable {
    private let clock = FixedLiveLogicalClock()
    private lazy var session = URLSession(configuration: Self.makeConfiguration())

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return configuration
    }

    func lookaround(using credential: AuthenticationCredential) async -> NativeTransportResponse {
        guard let url = URL(string: "https://lookaround-cache-prod.streaming.siriusxm.com/playbackservices/v1/live/lookAround?delta=") else { return Self.failed }
        guard let request = credential.withVolatileMaterial({ material -> URLRequest? in
            guard let authorization = String(data: material, encoding: .utf8), !authorization.isEmpty, !authorization.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
            request.setValue(clock.next(), forHTTPHeaderField: "x-sxm-clock")
            return request
        }) else { return Self.failed }
        return await send(request)
    }

    func artwork(for reference: ChannelArtworkReference) async -> NativeTransportResponse {
        guard let path = reference.relativeReference,
              path.hasPrefix("/"), !path.contains(".."), URL(string: path)?.scheme == nil,
              let url = URL(string: "https://imgsrv-sxm-prod-device.streaming.siriusxm.com\(path)")
        else { return Self.failed }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return await send(request)
    }

    private func send(_ request: URLRequest) async -> NativeTransportResponse {
        let redirectDelegate = PerRequestRedirectDelegate()
        do {
            let (body, response) = try await session.data(for: request, delegate: redirectDelegate)
            guard let response = response as? HTTPURLResponse else { return Self.failed }
            return NativeTransportResponse(statusCode: response.statusCode, contentType: response.value(forHTTPHeaderField: "Content-Type"), body: body, redirectLocation: response.value(forHTTPHeaderField: "Location"))
        } catch {
            let redirected = redirectDelegate.didObserveRedirect
            return NativeTransportResponse(statusCode: 0, contentType: nil, body: Data(), redirectLocation: redirected ? "blocked" : nil, transportFailure: redirected ? nil : SafeTransportFailure(error: error))
        }
    }

    private static let failed = NativeTransportResponse(statusCode: 0, contentType: nil, body: Data(), transportFailed: true)
}

actor CurrentSessionMetadataFetcher: LiveMetadataFetching {
    private let sessionCoordinator: SessionCoordinator
    private let transport: any FixedMetadataTransporting
    private var generation = 0

    init(sessionCoordinator: SessionCoordinator, transport: any FixedMetadataTransporting) {
        self.sessionCoordinator = sessionCoordinator
        self.transport = transport
    }

    func invalidate() async {
        generation &+= 1
    }

    func metadata(for channelID: LiveChannelID) async -> MetadataAvailability {
        generation &+= 1
        let expected = generation
        let authorization = await sessionCoordinator.withCurrentCatalogCredential({ [transport] credential in await transport.lookaround(using: credential) })
        guard generation == expected else { return .failed(.superseded) }
        switch authorization {
        case let .completed(response):
            return LiveListeningAdapter.decodeMetadata(response, channelID: channelID)
        case .authenticationUnavailable: return .failed(.authenticationUnavailable)
        case .notEntitled: return .failed(.notEntitled)
        case .superseded: return .failed(.superseded)
        }
    }

    func artwork(for reference: ChannelArtworkReference) async -> ArtworkAvailability {
        let expected = generation
        let response = await transport.artwork(for: reference)
        guard generation == expected else { return .unavailable }
        return LiveListeningAdapter.decodeArtwork(response)
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

/// Keeps every secret-adjacent tune result inside the one resolution that
/// admitted it. The marker protocol provides no way for any public consumer
/// to inspect or materialize its contents.
private final class CurrentSessionLiveOperationContext: FixedLiveOperationContext, @unchecked Sendable {
    let resource: FixedLiveResourceSelection
    let handoff: FixedLiveAppleMediaHandoff

    init(selection: FixedLiveResourceSelection) {
        resource = selection
        handoff = FixedLiveAppleMediaHandoff(url: selection.url, keyID: selection.keyID)
    }
}

/// Concrete production implementation of the narrow tune -> handoff -> key
/// sequence. It is actor-owned and has no credential or provider-material API.
actor CurrentSessionFixedLiveOperations: FixedLiveStreamOperating {
    private let sessionCoordinator: SessionCoordinator
    private let transport: any FixedLiveTransporting

    init(
        sessionCoordinator: SessionCoordinator,
        transport: any FixedLiveTransporting
    ) {
        self.sessionCoordinator = sessionCoordinator
        self.transport = transport
    }

    func authorizeTune(for channelID: LiveChannelID) async -> FixedLiveTuneAuthorization {
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
            return .authorized(CurrentSessionLiveOperationContext(selection: selection))
        }
    }

    func resolveResource(in context: any FixedLiveOperationContext) async -> FixedLiveResourceResolution {
        guard let context = context as? CurrentSessionLiveOperationContext,
              FixedLiveResponseDecoder.isCurrent(resource: context.resource, for: context.resource.channelID)
        else {
            return .failed(.resourceUnavailable)
        }
        return .resolved(context.handoff, keyRequirement: .required)
    }

    func authorizePlaybackKey(for context: any FixedLiveOperationContext) async -> LiveStreamResolutionFailure? {
        guard let context = context as? CurrentSessionLiveOperationContext else { return .resourceUnavailable }

        switch await sessionCoordinator.withCurrentEntitledCredential({ [transport] credential in
            await transport.playbackKey(for: context.resource.keyID, using: credential)
        }) {
        case let .failed(failure):
            return failure
        case let .completed(response):
            if let failure = FixedLiveResponseDecoder.failure(for: response, operation: .playbackKey) {
                return failure
            }
            guard let key = FixedLiveResponseDecoder.playbackKey(
                from: response.body,
                matching: context.resource.keyID
            ) else {
                return .unsupportedProtection
            }
            context.handoff.attachAuthorizedKey(key)
            return nil
        }
    }
}

/// A private handoff retaining approved material only until `AVPlayerItem`
/// construction. No ordinary API can inspect its URL or key material.
private final class FixedLiveAppleMediaHandoff: SiriusXMAppleMediaHandoff, @unchecked Sendable {
    private let url: URL
    private let keyID: FixedLivePlaybackKeyID
    private let lock = NSLock()
    private var authorizedKey: Data?
    nonisolated(unsafe) private static var loaderAssociationKey: UInt8 = 0

    init(url: URL, keyID: FixedLivePlaybackKeyID) {
        self.url = url
        self.keyID = keyID
    }

    func attachAuthorizedKey(_ key: Data) {
        lock.lock()
        authorizedKey = key
        lock.unlock()
    }

    @MainActor func makePlayerItem() -> AVPlayerItem? {
        lock.lock()
        let key = authorizedKey
        lock.unlock()
        guard let key else { return nil }

        let asset = AVURLAsset(url: url)
        let loader = FixedLivePlaybackKeyLoader(keyID: keyID, key: key)
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        let item = AVPlayerItem(asset: asset)
        objc_setAssociatedObject(
            item,
            &Self.loaderAssociationKey,
            loader,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return item
    }
}

private final class FixedLivePlaybackKeyLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.siriusmac.playback.key-loader")
    private let keyID: FixedLivePlaybackKeyID
    private let key: Data
    private let logger = Logger(subsystem: "com.siriusmac.client", category: "diagnostics")

    init(keyID: FixedLivePlaybackKeyID, key: Data) {
        self.keyID = keyID
        self.key = key
    }

    func resourceLoader(
        _: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let url = loadingRequest.request.url,
              url.path.hasPrefix("/playback/key/v1/"),
              url.lastPathComponent.removingPercentEncoding == keyID.value,
              let dataRequest = loadingRequest.dataRequest
        else { return false }

        if let information = loadingRequest.contentInformationRequest {
            information.contentType = UTType.data.identifier
            information.contentLength = Int64(key.count)
            information.isByteRangeAccessSupported = false
        }
        dataRequest.respond(with: key)
        loadingRequest.finishLoading()
        logger.info("SiriusXM client playback key loader handled")
        return true
    }
}

private enum FixedLiveOperation {
    case tune
    case playbackKey
}

private enum FixedLiveResponseDecoder {
    private static let maximumBodyBytes = 1_048_576
    private static let logger = Logger(subsystem: "com.siriusmac.client", category: "diagnostics")

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
        guard body.count <= maximumBodyBytes else {
            recordTuneShape("payload-too-large")
            return nil
        }
        guard let source = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            recordTuneShape("payload-not-object")
            return nil
        }
        guard source["id"] as? String == expectedChannelID.rawValue else {
            recordTuneShape(source["source"] is [String: Any] ? "legacy-source-envelope" : "identity-mismatch")
            return nil
        }
        guard source["type"] as? String == "channel-linear" else {
            recordTuneShape("type-mismatch")
            return nil
        }
        guard let streams = source["streams"] as? [[String: Any]], !streams.isEmpty else {
            recordTuneShape("streams-missing")
            return nil
        }

        var sawURLCollection = false
        var sawHTTPSCandidate = false
        var sawApprovedHost = false
        var sawSiriusXMSecondaryHost = false
        var sawAkamaiSecondaryHost = false
        var sawKeylessCandidate = false

        for stream in streams {
            guard let urls = stream["urls"] as? [[String: Any]] else { continue }
            sawURLCollection = true
            for candidate in urls {
                guard let value = candidate["url"] as? String,
                      let url = URL(string: value),
                      url.scheme?.lowercased() == "https",
                      url.port == nil,
                      url.user == nil,
                      url.password == nil,
                      !url.path.isEmpty
                else { continue }
                sawHTTPSCandidate = true
                switch mediaHostKind(url.host) {
                case .approved: sawApprovedHost = true
                case .siriusXMSecondary: sawSiriusXMSecondaryHost = true
                case .akamaiSecondary: sawAkamaiSecondaryHost = true
                case .unknown: break
                }
                guard let url = validMediaURL(value) else { continue }
                guard let keyID = candidate["encryptionKeyId"] as? String, !keyID.isEmpty else {
                    sawKeylessCandidate = true
                    continue
                }
                return FixedLiveResourceSelection(
                    channelID: expectedChannelID,
                    url: url,
                    keyID: FixedLivePlaybackKeyID(value: keyID)
                )
            }
        }
        let label: String
        if sawApprovedHost && sawKeylessCandidate {
            label = "approved-host-key-missing"
        } else if sawSiriusXMSecondaryHost {
            label = "siriusxm-secondary-host"
        } else if sawAkamaiSecondaryHost {
            label = "akamai-secondary-host"
        } else if sawHTTPSCandidate {
            label = "unknown-resource-host"
        } else if sawURLCollection {
            label = "resource-url-malformed"
        } else {
            label = "resource-urls-missing"
        }
        recordTuneShape(label)
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
        return Data(base64Encoded: value)
    }

    static func isCurrent(resource: FixedLiveResourceSelection, for channelID: LiveChannelID) -> Bool {
        resource.channelID == channelID && SiriusXMRequestContract.isOpaqueMediaDeliveryHost(resource.url.host)
    }

    private static func validMediaURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              SiriusXMRequestContract.isOpaqueMediaDeliveryHost(url.host),
              url.port == nil,
              url.user == nil,
              url.password == nil,
              !url.path.isEmpty
        else { return nil }
        return url
    }

    private enum MediaHostKind {
        case approved
        case siriusXMSecondary
        case akamaiSecondary
        case unknown
    }

    private static func mediaHostKind(_ host: String?) -> MediaHostKind {
        guard let host = host?.lowercased() else { return .unknown }
        if SiriusXMRequestContract.isOpaqueMediaDeliveryHost(host) { return .approved }
        if host.hasSuffix(".streaming.siriusxm.com") { return .siriusXMSecondary }
        if host.hasSuffix(".akamaized.net") { return .akamaiSecondary }
        return .unknown
    }

    private static func recordTuneShape(_ label: String) {
        logger.info("SiriusXM client tune shape \(label, privacy: .public)")
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
final class FixedLiveURLSessionTransport: FixedLiveTransporting, @unchecked Sendable {
    private lazy var session = URLSession(configuration: Self.makeConfiguration())

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
        let redirectDelegate = PerRequestRedirectDelegate()
        do {
            let (body, response) = try await session.data(for: request, delegate: redirectDelegate)
            guard let response = response as? HTTPURLResponse else { return Self.failedResponse }
            return NativeTransportResponse(
                statusCode: response.statusCode,
                contentType: response.value(forHTTPHeaderField: "Content-Type"),
                body: body,
                redirectLocation: response.value(forHTTPHeaderField: "Location")
            )
        } catch {
            let redirected = redirectDelegate.didObserveRedirect
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

enum FixedLiveRequestFactory {
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
            guard let body = try? JSONSerialization.data(withJSONObject: source) else { return nil }
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
