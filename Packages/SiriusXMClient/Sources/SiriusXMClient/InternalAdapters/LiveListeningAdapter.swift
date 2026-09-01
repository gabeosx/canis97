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
        CompatibilitySchemaDiagnostics.recordLookaround(
            body: response.body,
            selectedChannelID: channelID
        )
        guard preflightFailure(for: response) == nil,
              let root = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              root["channels"] is [String: Any],
              root["delta"] is String,
              let channels = root["channels"] as? [String: Any],
              let channel = channels[channelID.rawValue] as? [String: Any],
              let cuts = channel["cuts"] as? [[String: Any]]
        else { return .failed(.unsupportedResponse) }
        guard let first = cuts.first else { return .unavailable }
        guard let title = nonEmptyString(first["name"]),
              let artist = nonEmptyString(first["artistName"]),
              parseObservedLookaroundTimestamp(first["validFrom"]) != nil
        else { return .failed(.unsupportedResponse) }
        let artwork = currentProgramArtworkReference(from: first)
        return .current(MetadataSnapshot(channelID: channelID, program: LiveProgramMetadata(title: title, artist: artist, artwork: artwork)))
    }

    /// The observed lookaround contract requires a displayable name and artist.
    /// Whitespace-only values are not semantic metadata and must fail closed.
    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The provider's observed timestamp contract is ISO-8601 with either the
    /// default internet-date-time form or its fractional-seconds variant. No
    /// other date representation is admitted at this compatibility boundary.
    private static func parseObservedLookaroundTimestamp(_ value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        if let parsed = ISO8601DateFormatter().date(from: value) {
            return parsed
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions.insert(.withFractionalSeconds)
        return fractionalFormatter.date(from: value)
    }

    static func decodeArtwork(_ response: NativeTransportResponse) -> ArtworkAvailability {
        guard response.transportFailure == nil,
              response.redirectLocation == nil,
              (200 ... 299).contains(response.statusCode),
              response.body.count <= 5 * 1_024 * 1_024,
              let contentType = response.contentType?.lowercased()
        else { return .unavailable }

        if contentType.hasPrefix("image/svg+xml") {
            guard BoundedSVGArtworkValidator.isSafe(response.body) else { return .unavailable }
            return .current(ArtworkData(bytes: response.body, mediaType: .svg))
        }

        guard let mediaType: ArtworkMediaType = contentType.hasPrefix("image/jpeg") ? .jpeg : contentType.hasPrefix("image/png") ? .png : nil,
              let source = CGImageSourceCreateWithData(response.body as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0, height.intValue > 0,
              width.intValue <= 4096, height.intValue <= 4096
        else { return .unavailable }
        return .current(ArtworkData(bytes: response.body, mediaType: mediaType))
    }

    /// The observed current-song image URL is an opaque image-service key, not
    /// a fetchable URL. SiriusXM's current player Base64-encodes that key and a
    /// bounded resize edit into the fixed image-service path.
    private static func currentProgramArtworkReference(from cut: [String: Any]) -> ChannelArtworkReference? {
        guard let image = cut["image"] as? [String: Any],
              let key = image["url"] as? String,
              imageServiceKeyIsSafe(key),
              let resize = imageServiceResize(for: image),
              let payload = try? JSONSerialization.data(
                  withJSONObject: [
                      "key": key,
                      "edits": [["resize": ["width": resize.width, "height": resize.height]]],
                  ],
                  options: [.sortedKeys]
              )
        else { return nil }

        return ChannelArtworkReference(
            relativeReference: "/\(payload.base64EncodedString())",
            fixedOrigin: .mediaImage
        )
    }

    private static func imageServiceKeyIsSafe(_ key: String) -> Bool {
        guard !key.isEmpty,
              key.utf8.count <= 4_096,
              !key.hasPrefix("/"),
              !key.contains(".."),
              !key.contains("\\"),
              key.unicodeScalars.allSatisfy({ 0x21 ... 0x7E ~= $0.value }),
              let components = URLComponents(string: key),
              components.scheme == nil,
              components.host == nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              !components.percentEncodedPath.isEmpty
        else { return false }
        return true
    }

    private static func imageServiceResize(for image: [String: Any]) -> (width: Int, height: Int)? {
        let width = image["width"] as? NSNumber
        let height = image["height"] as? NSNumber
        guard width != nil || height != nil else { return (1_080, 1_080) }
        guard let width, let height,
              width.intValue > 0, height.intValue > 0,
              width.intValue <= 4_096, height.intValue <= 4_096
        else { return nil }

        let maximum = 1_920.0
        let scale = min(1, maximum / Double(width.intValue), maximum / Double(height.intValue))
        return (
            max(1, Int((Double(width.intValue) * scale).rounded())),
            max(1, Int((Double(height.intValue) * scale).rounded()))
        )
    }

    static func publicChannelArtworkReference(from value: Any?) -> ChannelArtworkReference? {
        guard let reference = value as? String else { return nil }
        return fixedArtworkReference(
            reference,
            origin: .publicWebsite,
            allowedExtensions: ["jpeg", "jpg", "png", "svg"]
        )
    }

    static func mediaImageArtworkReference(from value: Any?) -> ChannelArtworkReference? {
        guard let reference = value as? String else { return nil }
        return fixedArtworkReference(
            reference,
            origin: .mediaImage,
            allowedExtensions: nil
        )
    }

    private static func fixedArtworkReference(
        _ value: String,
        origin: ChannelArtworkReference.FixedOrigin,
        allowedExtensions: Set<String>?
    ) -> ChannelArtworkReference? {
        let relativeValue: String
        if value.hasPrefix("/") {
            relativeValue = value
        } else if value.hasPrefix("\(fixedHost(for: origin))/") {
            relativeValue = String(value.dropFirst(fixedHost(for: origin).count))
        } else if let components = URLComponents(string: value),
                  components.scheme == "https",
                  components.user == nil,
                  components.password == nil,
                  components.port == nil,
                  components.fragment == nil,
                  components.host == fixedHost(for: origin) {
            var relative = components.percentEncodedPath
            if let query = components.percentEncodedQuery, !query.isEmpty {
                relative += "?\(query)"
            }
            relativeValue = relative
        } else {
            return nil
        }

        guard relativeValue.hasPrefix("/"),
              !relativeValue.hasPrefix("//"),
              !relativeValue.contains(".."),
              let components = URLComponents(string: relativeValue),
              components.scheme == nil,
              components.host == nil,
              components.user == nil,
              components.password == nil,
              components.fragment == nil
        else { return nil }

        if let allowedExtensions,
           !allowedExtensions.contains((components.path as NSString).pathExtension.lowercased()) {
            return nil
        }

        return ChannelArtworkReference(relativeReference: relativeValue, fixedOrigin: origin)
    }

    private static func fixedHost(for origin: ChannelArtworkReference.FixedOrigin) -> String {
        switch origin {
        case .mediaImage: "imgsrv-sxm-prod-device.streaming.siriusxm.com"
        case .publicWebsite: SiriusXMRequestContract.publicChannelGuideHost
        }
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

/// Admits only bounded, inert SVG artwork from the fixed SiriusXM website.
/// AppKit performs final native decoding, but active content and external
/// references are rejected before bytes cross the client boundary.
private final class BoundedSVGArtworkValidator: NSObject, XMLParserDelegate {
    private static let maximumElements = 20_000
    private static let maximumDepth = 128
    private static let forbiddenElements: Set<String> = [
        "audio", "embed", "foreignobject", "iframe", "image", "object", "script", "video",
    ]

    private var elementCount = 0
    private var depth = 0
    private var styleDepth = 0
    private var styleText = ""
    private var rootDimensionsAreValid = false
    private var rejected = false

    static func isSafe(_ data: Data) -> Bool {
        guard let source = String(data: data, encoding: .utf8) else { return false }
        let normalizedSource = source.lowercased()
        guard !normalizedSource.contains("<!doctype"),
              !normalizedSource.contains("<!entity")
        else { return false }

        let validator = BoundedSVGArtworkValidator()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = validator
        return parser.parse() && validator.rootDimensionsAreValid && !validator.rejected
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        depth += 1
        elementCount += 1
        let normalizedElement = elementName.lowercased()
        guard depth <= Self.maximumDepth,
              elementCount <= Self.maximumElements,
              !Self.forbiddenElements.contains(normalizedElement)
        else {
            rejected = true
            parser.abortParsing()
            return
        }

        if elementCount == 1 {
            guard normalizedElement == "svg", Self.validDimensions(attributeDict) else {
                rejected = true
                parser.abortParsing()
                return
            }
            rootDimensionsAreValid = true
        }
        if normalizedElement == "style" {
            if styleDepth == 0 { styleText = "" }
            styleDepth += 1
        }

        for (name, value) in attributeDict {
            let normalizedName = name.lowercased()
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedName.hasPrefix("on") || normalizedValue.contains("javascript:") || normalizedValue.contains("data:") {
                rejected = true
                parser.abortParsing()
                return
            }
            if !normalizedName.hasPrefix("xmlns"),
               normalizedValue.contains("http:") || normalizedValue.contains("https:") || normalizedValue.hasPrefix("//") {
                rejected = true
                parser.abortParsing()
                return
            }
            if normalizedName == "href" || normalizedName == "xlink:href" {
                guard normalizedValue.hasPrefix("#") else {
                    rejected = true
                    parser.abortParsing()
                    return
                }
            }
            if normalizedName == "style",
               normalizedValue.contains("url("),
               !normalizedValue.contains("url(#") {
                rejected = true
                parser.abortParsing()
                return
            }
        }
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        if elementName.lowercased() == "style" {
            styleDepth -= 1
            if styleDepth == 0, Self.containsExternalStyleReference(styleText) {
                rejected = true
            }
        }
        depth -= 1
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard styleDepth > 0 else { return }
        styleText += string
        if styleText.utf8.count > 1_048_576 {
            rejected = true
            parser.abortParsing()
        }
    }

    func parser(
        _ parser: XMLParser,
        foundExternalEntityDeclarationWithName _: String,
        publicID _: String?,
        systemID _: String?
    ) {
        rejected = true
        parser.abortParsing()
    }

    private static func validDimensions(_ attributes: [String: String]) -> Bool {
        if let width = boundedDimension(attributes["width"]),
           let height = boundedDimension(attributes["height"]) {
            return width > 0 && height > 0
        }

        guard let viewBox = attributes.first(where: { $0.key.lowercased() == "viewbox" })?.value else {
            return false
        }
        let values = viewBox
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .compactMap { Double($0) }
        guard values.count == 4 else { return false }
        return values[2].isFinite && values[3].isFinite &&
            values[2] > 0 && values[3] > 0 &&
            values[2] <= 4096 && values[3] <= 4096
    }

    private static func boundedDimension(_ value: String?) -> Double? {
        guard let value else { return nil }
        let numeric = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "px", with: "", options: [.caseInsensitive, .anchored], range: nil)
        guard let dimension = Double(numeric), dimension.isFinite, dimension <= 4096 else { return nil }
        return dimension
    }

    private static func containsExternalStyleReference(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.contains("@import") || normalized.contains("javascript:") ||
            normalized.contains("data:") || normalized.contains("http:") || normalized.contains("https:")
    }
}

/// Emits a deliberately closed, value-free shape summary for the three
/// authorized content boundaries. These summaries exist to repair volatile
/// provider adapters without retaining a response, an identity, or any
/// protected transport material. Every rendered token is an allow-listed path,
/// scalar/container kind, or bounded cardinality.
enum CompatibilitySchemaDiagnostics {
    private static let logger = Logger(subsystem: "com.siriusmac.client", category: "diagnostics")

    static func recordCatalog(body: Data) {
        record(catalogEvidence(body: body))
    }

    static func recordLookaround(body: Data, selectedChannelID: LiveChannelID) {
        record(lookaroundEvidence(body: body, selectedChannelID: selectedChannelID))
    }

    static func recordTune(body: Data) {
        record(tuneEvidence(body: body))
    }

    static func recordArtwork(
        _ response: NativeTransportResponse,
        origin: ChannelArtworkReference.FixedOrigin?
    ) {
        record(artworkEvidence(response, origin: origin))
    }

    static func catalogEvidence(body: Data) -> String {
        CatalogSchemaEvidence(body: body).rendered
    }

    static func lookaroundEvidence(body: Data, selectedChannelID: LiveChannelID) -> String {
        LookaroundSchemaEvidence(body: body, selectedChannelID: selectedChannelID).rendered
    }

    static func tuneEvidence(body: Data) -> String {
        TuneSchemaEvidence(body: body).rendered
    }

    static func artworkEvidence(
        _ response: NativeTransportResponse,
        origin: ChannelArtworkReference.FixedOrigin?
    ) -> String {
        let originClass = switch origin {
        case .mediaImage: "media-image"
        case .publicWebsite: "public-website"
        case nil: "absent"
        }
        let statusClass = switch response.statusCode {
        case 200 ... 299: "success"
        case 400 ... 499: "client-error"
        case 500 ... 599: "server-error"
        default: "other"
        }
        let normalizedContentType = response.contentType?.lowercased()
        let contentTypeClass: String
        if normalizedContentType?.hasPrefix("image/jpeg") == true {
            contentTypeClass = "jpeg"
        } else if normalizedContentType?.hasPrefix("image/png") == true {
            contentTypeClass = "png"
        } else if normalizedContentType?.hasPrefix("image/svg+xml") == true {
            contentTypeClass = "svg"
        } else if normalizedContentType?.hasPrefix("application/json") == true {
            contentTypeClass = "json"
        } else if normalizedContentType?.hasPrefix("text/html") == true {
            contentTypeClass = "html"
        } else {
            contentTypeClass = normalizedContentType == nil ? "absent" : "other"
        }
        let sizeClass = switch response.body.count {
        case 0: "empty"
        case 1 ... 65_536: "small"
        case 65_537 ... 1_048_576: "medium"
        case 1_048_577 ... 5_242_880: "large"
        default: "over-limit"
        }
        return "stage=artwork origin=\(originClass) transport=\(response.transportFailure == nil ? "ok" : "failed") redirect=\(response.redirectLocation == nil ? "none" : "blocked") status=\(statusClass) content-type=\(contentTypeClass) bytes=\(sizeClass)"
    }

    private static func record(_ evidence: String) {
        logger.info("SiriusXM compatibility schema \(evidence, privacy: .public)")
    }
}

private enum CompatibilitySchemaValueKind: String {
    case absent
    case null
    case emptyString = "string-empty"
    case string = "string-nonempty"
    case object
    case emptyArray = "array-empty"
    case array = "array-nonempty"
    case other

    init(_ value: Any?) {
        switch value {
        case nil:
            self = .absent
        case is NSNull:
            self = .null
        case let value as String:
            self = value.isEmpty ? .emptyString : .string
        case is [String: Any]:
            self = .object
        case let value as [Any]:
            self = value.isEmpty ? .emptyArray : .array
        default:
            self = .other
        }
    }
}

/// A closed classification of the only ISO-8601 variants relevant to the
/// observed lookaround boundary. This intentionally records parser behavior,
/// never a provider timestamp.
private enum LookaroundTimestampParseClass: String {
    case defaultISO8601 = "default-ISO8601"
    case fractionalSecondsISO8601 = "fractional-seconds-ISO8601"
    case both
    case unparseable

    init(_ value: Any?) {
        guard let value = value as? String else {
            self = .unparseable
            return
        }

        let defaultParses = ISO8601DateFormatter().date(from: value) != nil
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions.insert(.withFractionalSeconds)
        let fractionalParses = fractionalFormatter.date(from: value) != nil

        switch (defaultParses, fractionalParses) {
        case (true, false): self = .defaultISO8601
        case (false, true): self = .fractionalSecondsISO8601
        case (true, true): self = .both
        case (false, false): self = .unparseable
        }
    }
}

/// Value-free classification for artwork references at the compatibility
/// boundary. It is detailed enough to repair a fixed allow-list without ever
/// logging the provider path, query, host, or user/session material.
private enum ArtworkReferenceShape: String {
    case absent
    case relative
    case rootlessPath = "rootless-path"
    case fixedMediaSchemelessAbsolute = "fixed-media-schemeless-absolute"
    case publicWebsiteSchemelessAbsolute = "public-website-schemeless-absolute"
    case fixedMediaAbsolute = "fixed-media-absolute"
    case publicWebsiteAbsolute = "public-website-absolute"
    case fixedMediaProtocolRelative = "fixed-media-protocol-relative"
    case publicWebsiteProtocolRelative = "public-website-protocol-relative"
    case otherProtocolRelative = "other-protocol-relative"
    case insecureAbsolute = "insecure-absolute"
    case otherAbsolute = "other-absolute"
    case invalid

    init(_ value: Any?) {
        guard let value = value as? String, !value.isEmpty else {
            self = value == nil ? .absent : .invalid
            return
        }
        if value.hasPrefix("//") {
            guard let components = URLComponents(string: "https:\(value)"),
                  let host = components.host
            else {
                self = .invalid
                return
            }
            switch host {
            case "imgsrv-sxm-prod-device.streaming.siriusxm.com":
                self = .fixedMediaProtocolRelative
            case SiriusXMRequestContract.publicChannelGuideHost:
                self = .publicWebsiteProtocolRelative
            default:
                self = .otherProtocolRelative
            }
            return
        }
        if value.hasPrefix("/") {
            self = .relative
            return
        }
        if value.hasPrefix("imgsrv-sxm-prod-device.streaming.siriusxm.com/") {
            self = .fixedMediaSchemelessAbsolute
            return
        }
        if value.hasPrefix("\(SiriusXMRequestContract.publicChannelGuideHost)/") {
            self = .publicWebsiteSchemelessAbsolute
            return
        }
        guard let components = URLComponents(string: value) else {
            self = .invalid
            return
        }
        if components.scheme == nil, components.host == nil,
           !components.percentEncodedPath.isEmpty {
            self = .rootlessPath
            return
        }
        guard let host = components.host else {
            self = .invalid
            return
        }
        guard components.scheme == "https" else {
            self = components.scheme == "http" ? .insecureAbsolute : .invalid
            return
        }
        switch host {
        case "imgsrv-sxm-prod-device.streaming.siriusxm.com":
            self = .fixedMediaAbsolute
        case SiriusXMRequestContract.publicChannelGuideHost:
            self = .publicWebsiteAbsolute
        default:
            self = .otherAbsolute
        }
    }
}

private enum CompatibilitySchemaCardinality: String {
    case absent
    case empty
    case one
    case twoOrMore = "two-or-more"
    case other

    init(_ value: Any?) {
        guard let value else {
            self = .absent
            return
        }
        guard let values = value as? [Any] else {
            self = .other
            return
        }
        switch values.count {
        case 0: self = .empty
        case 1: self = .one
        default: self = .twoOrMore
        }
    }
}

private struct CatalogSchemaEvidence {
    let rendered: String

    init(body: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            rendered = "stage=catalog root=non-catalog-object"
            return
        }

        if let channels = root["channels"] as? [[String: Any]] {
            rendered = [
                "stage=catalog",
                "root=object",
                "channels=\(CompatibilitySchemaCardinality(channels).rawValue)",
                "item-count=\(boundedCount(channels.count))",
                "channel_type=\(aggregateKind(channels.map { $0["channel_type"] }))",
                "uuid=\(aggregateKind(channels.map { $0["uuid"] }))",
                "streamingChannelNumber=\(aggregateKind(channels.map { $0["streamingChannelNumber"] }))",
                "deliveryTypes=\(aggregateKind(channels.map { $0["deliveryTypes"] }))"
            ].joined(separator: " ")
            return
        }

        if let container = root["container"] as? [String: Any],
           let sets = container["sets"] as? [[String: Any]] {
            let items = sets.flatMap { $0["items"] as? [[String: Any]] ?? [] }
            let paginationClasses = sets.map { set -> String in
                guard let pagination = set["pagination"] as? [String: Any],
                      let offset = pagination["offset"] as? [String: Any],
                      let size = offset["size"] as? NSNumber,
                      let start = offset["offset"] as? NSNumber,
                      let pageItems = set["items"] as? [Any]
                else { return "invalid" }
                return start.intValue + pageItems.count < size.intValue ? "partial" : "complete"
            }
            let paginationClass = Set(paginationClasses).count == 1 ? paginationClasses.first ?? "absent" : "mixed"
            rendered = [
                "stage=catalog",
                "root=object",
                "container=object",
                "container.sets=\(CompatibilitySchemaCardinality(sets).rawValue)",
                "item-count=\(boundedCount(items.count))",
                "pagination=\(paginationClass)"
            ].joined(separator: " ")
            return
        }

        guard let page = root["page"] as? [String: Any],
              let containers = page["containers"] as? [[String: Any]]
        else {
            rendered = "stage=catalog root=non-catalog-object"
            return
        }

        let items = containers.flatMap { container in
            (container["sets"] as? [[String: Any]] ?? []).flatMap { $0["items"] as? [[String: Any]] ?? [] }
        }
        let metadataValues = items.map { $0["metadata"] }
        let liveValues = metadataValues.map { ($0 as? [String: Any])?["live"] }
        let currentItems = liveValues.compactMap { ($0 as? [String: Any])?["items"] as? [Any] }
        let cuts = items.map { $0["cuts"] }
        let titleValues = items.map { item -> Any? in
            let entity = item["entity"] as? [String: Any]
            let texts = entity?["texts"] as? [String: Any]
            let title = texts?["title"] as? [String: Any]
            return title?["default"]
        }

        rendered = [
            "stage=catalog",
            "root=object",
            "page=object",
            "page.containers=\(CompatibilitySchemaCardinality(containers).rawValue)",
            "item-count=\(boundedCount(items.count))",
            "entity.texts.title.default=\(aggregateKind(titleValues))",
            "metadata=\(aggregateKind(metadataValues))",
            "metadata.live=\(aggregateKind(liveValues))",
            "metadata.live.items=\(aggregateCardinality(currentItems))",
            "cuts=\(aggregateKind(cuts))"
        ].joined(separator: " ")
    }
}

private struct LookaroundSchemaEvidence {
    let rendered: String

    init(body: Data, selectedChannelID: LiveChannelID) {
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let channels = root["channels"] as? [String: Any]
        else {
            rendered = "stage=lookaround root=non-lookaround-object"
            return
        }

        let selected = channels[selectedChannelID.rawValue] as? [String: Any]
        let cuts = selected?["cuts"]
        let firstCut = (cuts as? [[String: Any]])?.first
        let selectedChannel = selected == nil ? "absent" : "object"
        let name = CompatibilitySchemaValueKind(firstCut?["name"]).rawValue
        let title = CompatibilitySchemaValueKind(firstCut?["title"]).rawValue
        let artistName = CompatibilitySchemaValueKind(firstCut?["artistName"]).rawValue
        let artist = CompatibilitySchemaValueKind(firstCut?["artist"]).rawValue
        let validFrom = CompatibilitySchemaValueKind(firstCut?["validFrom"]).rawValue
        let timestampParse = LookaroundTimestampParseClass(firstCut?["validFrom"]).rawValue
        let image = firstCut?["image"] as? [String: Any]
        let imageKind = CompatibilitySchemaValueKind(firstCut?["image"]).rawValue
        let imageURL = CompatibilitySchemaValueKind(image?["url"]).rawValue
        let imageURLShape = ArtworkReferenceShape(image?["url"]).rawValue
        let imageWidth = CompatibilitySchemaValueKind(image?["width"]).rawValue
        let imageHeight = CompatibilitySchemaValueKind(image?["height"]).rawValue
        let album = firstCut?["album"] as? [String: Any]
        let creativeArts = album?["creativeArts"]
        let firstCreativeArt = (creativeArts as? [[String: Any]])?.first
        let topLevelCreativeArts = firstCut?["creativeArts"]
        let delta = CompatibilitySchemaValueKind(root["delta"]).rawValue
        let shows = CompatibilitySchemaCardinality(selected?["shows"]).rawValue
        rendered = [
            "stage=lookaround",
            "root=object",
            "channels=object",
            "selected-channel=\(selectedChannel)",
            "selected.cuts=\(CompatibilitySchemaCardinality(cuts).rawValue)",
            "selected.cuts[0].name=\(name)",
            "selected.cuts[0].title=\(title)",
            "selected.cuts[0].artistName=\(artistName)",
            "selected.cuts[0].artist=\(artist)",
            "selected.cuts[0].validFrom=\(validFrom)",
            "selected.cuts[0].validFrom.parse=\(timestampParse)",
            "selected.cuts[0].image=\(imageKind)",
            "selected.cuts[0].image.url=\(imageURL)",
            "selected.cuts[0].image.url.shape=\(imageURLShape)",
            "selected.cuts[0].image.width=\(imageWidth)",
            "selected.cuts[0].image.height=\(imageHeight)",
            "selected.cuts[0].album=\(CompatibilitySchemaValueKind(firstCut?["album"]).rawValue)",
            "selected.cuts[0].album.creativeArts=\(CompatibilitySchemaCardinality(creativeArts).rawValue)",
            "selected.cuts[0].album.creativeArts[0].type=\(CompatibilitySchemaValueKind(firstCreativeArt?["type"]).rawValue)",
            "selected.cuts[0].album.creativeArts[0].url=\(CompatibilitySchemaValueKind(firstCreativeArt?["url"]).rawValue)",
            "selected.cuts[0].album.creativeArts[0].url.shape=\(ArtworkReferenceShape(firstCreativeArt?["url"]).rawValue)",
            "selected.cuts[0].creativeArts=\(CompatibilitySchemaCardinality(topLevelCreativeArts).rawValue)",
            "delta=\(delta)",
            "selected.shows=\(shows)"
        ].joined(separator: " ")
    }
}

private struct TuneSchemaEvidence {
    let rendered: String

    init(body: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            rendered = "stage=tune root=non-object"
            return
        }
        let metadata = root["metadata"] as? [String: Any]
        let live = metadata?["live"] as? [String: Any]
        let items = live?["items"]
        let firstItem = (items as? [[String: Any]])?.first
        let streams = CompatibilitySchemaCardinality(root["streams"]).rawValue
        let metadataKind = CompatibilitySchemaValueKind(root["metadata"]).rawValue
        let liveKind = CompatibilitySchemaValueKind(metadata?["live"]).rawValue
        let name = CompatibilitySchemaValueKind(firstItem?["name"]).rawValue
        let title = CompatibilitySchemaValueKind(firstItem?["title"]).rawValue
        let artistName = CompatibilitySchemaValueKind(firstItem?["artistName"]).rawValue
        let artist = CompatibilitySchemaValueKind(firstItem?["artist"]).rawValue
        let episodes = CompatibilitySchemaCardinality(live?["episodes"]).rawValue
        rendered = [
            "stage=tune",
            "root=object",
            "streams=\(streams)",
            "metadata=\(metadataKind)",
            "metadata.live=\(liveKind)",
            "metadata.live.items=\(CompatibilitySchemaCardinality(items).rawValue)",
            "metadata.live.items[0].name=\(name)",
            "metadata.live.items[0].title=\(title)",
            "metadata.live.items[0].artistName=\(artistName)",
            "metadata.live.items[0].artist=\(artist)",
            "metadata.live.episodes=\(episodes)"
        ].joined(separator: " ")
    }
}

private func aggregateKind(_ values: [Any?]) -> String {
    guard !values.isEmpty else { return "no-items" }
    let kinds = Set(values.map { CompatibilitySchemaValueKind($0).rawValue })
    return kinds.count == 1 ? kinds.first ?? "other" : "mixed"
}

private func aggregateCardinality(_ values: [[Any]]) -> String {
    guard !values.isEmpty else { return "absent" }
    return boundedCount(values.reduce(0) { $0 + $1.count })
}

private func boundedCount(_ count: Int) -> String {
    switch count {
    case 0: "zero"
    case 1: "one"
    default: "two-or-more"
    }
}

/// The continuation state admitted from SiriusXM's fixed Channels page. IDs are
/// provider-issued opaque path segments and are validated before reuse.
struct FixedCatalogPageCursor: Sendable, Equatable {
    let containerID: String
    let setID: String
    let nextOffset: Int
    let totalCount: Int
}

/// Internal transport seam for the fixed Channels page and its bounded
/// continuation pages. It accepts no caller-provided host, headers, or body.
protocol FixedCatalogTransporting: Sendable {
    func initialCatalog(using credential: AuthenticationCredential) async -> NativeTransportResponse
    func catalogPage(
        using credential: AuthenticationCredential,
        cursor: FixedCatalogPageCursor
    ) async -> NativeTransportResponse
}

/// Exact authenticated Browse requests observed from SiriusXM Web 7.131.0.
/// The initial page supplies 30 channels and an opaque container/set cursor;
/// continuation requests retrieve the remaining lineup in batches of 50.
enum FixedCatalogRequestFactory {
    static let pageID = "403ab6a5-d3c9-4c2a-a722-a94a6a5fd056"
    static let initialItemLimit = 30
    static let continuationItemLimit = 50

    private static let scheme = "https"
    private static let host = SiriusXMRequestContract.host
    private static let pagePath = "/browse/v1/pages/curated-grouping/\(pageID)"
    private static let maximumOffset = 2_000
    private static let supportedEntityTypes = [
        "artist-station", "brand", "channel-linear", "channel-xtra", "container",
        "curated-grouping", "episode-audio", "episode-linear", "episode-podcast",
        "episode-video", "event", "experience", "genre", "league", "show",
        "show-podcast", "tag-topic", "talent", "team", "user-signal",
    ]

    static func makeInitialRequest(
        using credential: AuthenticationCredential,
        clock: String
    ) -> URLRequest? {
        let object: [String: Any] = [
            "pagination": ["offset": [
                "containerLimit": 5,
                "containerOffset": 0,
                "setItemsLimit": initialItemLimit,
            ]],
            "deviceCapabilities": ["supportsDownloads": false],
            "containerConfiguration": [:],
            "constraints": ["supportedEntityTypes": supportedEntityTypes],
            "locale": "en-US",
        ]
        guard let query = encodedQuery(object) else { return nil }
        return makeRequest(path: pagePath, query: query, credential: credential, clock: clock)
    }

    static func makePageRequest(
        using credential: AuthenticationCredential,
        cursor: FixedCatalogPageCursor,
        clock: String
    ) -> URLRequest? {
        guard isSafeOpaqueID(cursor.containerID),
              isSafeOpaqueID(cursor.setID),
              (0 ... maximumOffset).contains(cursor.nextOffset),
              cursor.nextOffset < cursor.totalCount,
              cursor.totalCount <= maximumOffset
        else { return nil }

        let object: [String: Any] = [
            "pagination": ["offset": ["setItemsLimit": continuationItemLimit]],
            "deviceCapabilities": ["supportsDownloads": false],
            "sets": [cursor.setID: [
                "sort": ["sortId": "CHANNEL_NUMBER_ASC"],
                "pagination": ["offset": [
                    "setItemsLimit": continuationItemLimit,
                    "setItemsOffset": cursor.nextOffset,
                ]],
            ]],
            "constraints": ["supportedEntityTypes": supportedEntityTypes],
            "locale": "en-US",
            "filter": ["one": ["filterId": "all"]],
        ]
        guard let query = encodedQuery(object) else { return nil }
        return makeRequest(
            path: "\(pagePath)/containers/\(cursor.containerID)",
            query: query,
            credential: credential,
            clock: clock
        )
    }

    private static func makeRequest(
        path: String,
        query: String,
        credential: AuthenticationCredential,
        clock: String
    ) -> URLRequest? {
        guard !clock.isEmpty,
              let authorization = credential.accessToken()
        else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        components.percentEncodedQuery = "q=\(query)"
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
        request.setValue(clock, forHTTPHeaderField: "x-sxm-clock")
        return request
    }

    private static func encodedQuery(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else { return nil }
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "1.\(encoded)"
    }

    static func isSafeOpaqueID(_ value: String) -> Bool {
        (1 ... 64).contains(value.utf8.count) && value.unicodeScalars.allSatisfy {
            (0x30 ... 0x39).contains($0.value) ||
                (0x41 ... 0x5A).contains($0.value) ||
                (0x61 ... 0x7A).contains($0.value)
        }
    }
}

/// Ephemeral production transport for the fixed catalog sequence. Redirects
/// are cancelled and neither redirect targets nor transport errors escape.
final class FixedCatalogURLSessionTransport: FixedCatalogTransporting, @unchecked Sendable {
    private let clock = FixedLiveLogicalClock()
    private lazy var session = URLSession(configuration: Self.makeConfiguration())

    func initialCatalog(using credential: AuthenticationCredential) async -> NativeTransportResponse {
        guard let request = FixedCatalogRequestFactory.makeInitialRequest(
            using: credential,
            clock: clock.next()
        ) else { return Self.failedResponse }
        return await send(request)
    }

    func catalogPage(
        using credential: AuthenticationCredential,
        cursor: FixedCatalogPageCursor
    ) async -> NativeTransportResponse {
        guard let request = FixedCatalogRequestFactory.makePageRequest(
            using: credential,
            cursor: cursor,
            clock: clock.next()
        ) else { return Self.failedResponse }
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
        configuration.timeoutIntervalForResource = 30
        return configuration
    }
}

struct FixedCatalogDecodedSegment: Sendable {
    let candidates: [LiveCatalogCandidate]
    let cursor: FixedCatalogPageCursor?
}

struct FixedCatalogSegmentResult: Sendable {
    let segment: FixedCatalogDecodedSegment?
    let failure: CatalogFailure?
}

/// Strictly decodes the observed Channels page and container continuation
/// envelopes. Partial pages never publish as a complete lineup.
enum FixedCatalogResponseDecoder {
    private static let maximumBodyBytes = 8 * 1_024 * 1_024
    private static let maximumCandidateItems = 2_000

    static func decode(_ response: NativeTransportResponse) -> LiveCatalogSnapshotResult {
        let result = decodeInitial(response)
        guard let segment = result.segment else {
            return LiveCatalogSnapshotResult(snapshot: nil, failure: result.failure)
        }
        guard segment.cursor == nil else {
            return LiveCatalogSnapshotResult(snapshot: nil, failure: .partialLineup)
        }
        return LiveCatalogAdapter.snapshot(from: segment.candidates)
    }

    static func decodeInitial(_ response: NativeTransportResponse) -> FixedCatalogSegmentResult {
        guard let root = rootObject(response),
              let page = root["page"] as? [String: Any],
              page["id"] as? String == FixedCatalogRequestFactory.pageID,
              let containers = page["containers"] as? [[String: Any]],
              containers.count == 1,
              let container = containers.first,
              let containerID = container["id"] as? String,
              FixedCatalogRequestFactory.isSafeOpaqueID(containerID),
              let sets = container["sets"] as? [[String: Any]],
              sets.count == 1,
              let set = sets.first,
              let setID = set["id"] as? String,
              FixedCatalogRequestFactory.isSafeOpaqueID(setID)
        else { return failed(.collectionUnavailable) }
        return decodeSet(
            set,
            containerID: containerID,
            setID: setID,
            expectedOffset: 0,
            expectedTotal: nil,
            expectedLimit: FixedCatalogRequestFactory.initialItemLimit
        )
    }

    static func decodeContinuation(
        _ response: NativeTransportResponse,
        expected cursor: FixedCatalogPageCursor
    ) -> FixedCatalogSegmentResult {
        guard let root = rootObject(response),
              let container = root["container"] as? [String: Any],
              container["id"] as? String == cursor.containerID,
              let sets = container["sets"] as? [[String: Any]],
              sets.count == 1,
              let set = sets.first,
              set["id"] as? String == cursor.setID
        else { return failed(.paginationUnavailable) }
        return decodeSet(
            set,
            containerID: cursor.containerID,
            setID: cursor.setID,
            expectedOffset: cursor.nextOffset,
            expectedTotal: cursor.totalCount,
            expectedLimit: FixedCatalogRequestFactory.continuationItemLimit
        )
    }

    private static func decodeSet(
        _ set: [String: Any],
        containerID: String,
        setID: String,
        expectedOffset: Int,
        expectedTotal: Int?,
        expectedLimit: Int
    ) -> FixedCatalogSegmentResult {
        guard let items = set["items"] as? [[String: Any]],
              let pagination = set["pagination"] as? [String: Any],
              let offset = pagination["offset"] as? [String: Any],
              let totalCount = integer(offset["size"]),
              let limit = integer(offset["limit"]),
              let actualOffset = integer(offset["offset"]),
              totalCount > 0,
              totalCount <= maximumCandidateItems,
              expectedTotal.map({ $0 == totalCount }) ?? true,
              actualOffset == expectedOffset,
              limit == expectedLimit,
              !items.isEmpty,
              items.count <= limit,
              actualOffset + items.count <= totalCount,
              items.count == min(limit, totalCount - actualOffset)
        else { return failed(expectedTotal == nil ? .collectionUnavailable : .paginationUnavailable) }

        var candidates: [LiveCatalogCandidate] = []
        candidates.reserveCapacity(items.count)
        for item in items {
            guard let candidate = candidate(from: item) else {
                return failed(.malformedCandidate)
            }
            candidates.append(candidate)
        }

        let nextOffset = actualOffset + items.count
        let cursor = nextOffset < totalCount ? FixedCatalogPageCursor(
            containerID: containerID,
            setID: setID,
            nextOffset: nextOffset,
            totalCount: totalCount
        ) : nil
        return FixedCatalogSegmentResult(
            segment: FixedCatalogDecodedSegment(candidates: candidates, cursor: cursor),
            failure: nil
        )
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
              UUID(uuidString: identity) != nil,
              let decorations = item["decorations"] as? [String: Any],
              decorations["contentTypeLabel"] as? String == "CHANNEL",
              let connectivity = decorations["connectivity"] as? String,
              let isUnentitled = decorations["unentitled"] as? Bool,
              let number = number(from: decorations["channelNumber"]),
              matchingPlayCapability(item["actions"], entityType: type, identity: identity),
              let texts = entity["texts"] as? [String: Any],
              let title = texts["title"] as? [String: Any],
              let name = title["default"] as? String,
              !name.isEmpty
        else { return nil }

        let entitlement: ChannelEntitlement
        if isUnentitled {
            entitlement = .notEntitled
        } else {
            switch connectivity {
            case "ip-and-sat": entitlement = .entitledStandard
            case "ip": entitlement = .entitledAppOnly
            default: return nil
            }
        }
        let description = (texts["description"] as? [String: Any])?["default"] as? String
        return LiveCatalogCandidate(
            identity: identity,
            displayNumber: number,
            name: name,
            description: description,
            category: decorations["genre"] as? String,
            artwork: artwork(from: entity),
            entity: .channelLinear,
            entitlement: entitlement
        )
    }

    private static func artwork(from entity: [String: Any]) -> ChannelArtworkReference? {
        let images = entity["images"] as? [String: Any]
        let tile = images?["tile"] as? [String: Any]
        let aspect = tile?["aspect_1x1"] as? [String: Any]
        let preferred = aspect?["preferred"] as? [String: Any]
        let fallback = aspect?["default"] as? [String: Any]
        return LiveListeningAdapter.mediaImageArtworkReference(
            from: preferred?["url"] ?? fallback?["url"]
        )
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

    private static func rootObject(_ response: NativeTransportResponse) -> [String: Any]? {
        guard response.transportFailure == nil,
              response.redirectLocation == nil,
              (200 ... 299).contains(response.statusCode),
              response.body.count <= maximumBodyBytes,
              response.contentType?.lowercased().hasPrefix("application/json") == true,
              !containsProtectedControl(response.body)
        else { return nil }
        CompatibilitySchemaDiagnostics.recordCatalog(body: response.body)
        return try? JSONSerialization.jsonObject(with: response.body) as? [String: Any]
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              let integer = Int(exactly: number.doubleValue)
        else { return nil }
        return integer
    }

    private static func number(from value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              Int(exactly: number.doubleValue) != nil
        else { return nil }
        return number.doubleValue
    }

    private static func failed(_ failure: CatalogFailure) -> FixedCatalogSegmentResult {
        FixedCatalogSegmentResult(segment: nil, failure: failure)
    }

    private static func containsProtectedControl(_ body: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return false }
        if object["bot"] as? Bool == true { return true }
        guard let challenge = object["challenge"] as? String else { return false }
        return ["captcha", "mfa", "control"].contains(challenge.lowercased())
    }
}

actor CurrentSessionCatalogRefresher: CatalogRefreshing {
    private static let maximumRequests = 24
    private let sessionCoordinator: SessionCoordinator
    private let transport: any FixedCatalogTransporting

    init(sessionCoordinator: SessionCoordinator, transport: any FixedCatalogTransporting) {
        self.sessionCoordinator = sessionCoordinator
        self.transport = transport
    }

    func refresh() async -> LiveCatalogSnapshotResult {
        switch await sessionCoordinator.withCurrentCatalogCredential({ [transport] credential in
            let initial = FixedCatalogResponseDecoder.decodeInitial(
                await transport.initialCatalog(using: credential)
            )
            guard let firstSegment = initial.segment else {
                return LiveCatalogSnapshotResult(snapshot: nil, failure: initial.failure)
            }

            var candidates = firstSegment.candidates
            var cursor = firstSegment.cursor
            var requestCount = 1
            while let current = cursor {
                guard requestCount < Self.maximumRequests else {
                    return LiveCatalogSnapshotResult(snapshot: nil, failure: .paginationUnavailable)
                }
                let page = FixedCatalogResponseDecoder.decodeContinuation(
                    await transport.catalogPage(using: credential, cursor: current),
                    expected: current
                )
                guard let segment = page.segment else {
                    return LiveCatalogSnapshotResult(snapshot: nil, failure: page.failure ?? .paginationUnavailable)
                }
                candidates.append(contentsOf: segment.candidates)
                cursor = segment.cursor
                requestCount += 1
            }
            return LiveCatalogAdapter.snapshot(from: candidates)
        }) {
        case let .completed(result):
            result
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
        guard let authorization = credential.accessToken() else { return Self.failed }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
        request.setValue(clock.next(), forHTTPHeaderField: "x-sxm-clock")
        return await send(request)
    }

    func artwork(for reference: ChannelArtworkReference) async -> NativeTransportResponse {
        guard let request = Self.artworkRequest(for: reference) else { return Self.failed }
        return await send(request)
    }

    static func artworkRequest(for reference: ChannelArtworkReference) -> URLRequest? {
        guard let path = reference.relativeReference,
              path.hasPrefix("/"),
              !path.hasPrefix("//"),
              !path.contains(".."),
              URLComponents(string: path)?.scheme == nil,
              let origin = reference.fixedOrigin
        else { return nil }

        let host = switch origin {
        case .mediaImage: "imgsrv-sxm-prod-device.streaming.siriusxm.com"
        case .publicWebsite: SiriusXMRequestContract.publicChannelGuideHost
        }
        guard let url = URL(string: "https://\(host)\(path)"),
              url.scheme == "https",
              url.host == host,
              url.user == nil,
              url.password == nil,
              url.port == nil,
              url.fragment == nil
        else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("image/svg+xml,image/png,image/jpeg", forHTTPHeaderField: "Accept")
        return request
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
        CompatibilitySchemaDiagnostics.recordArtwork(response, origin: reference.fixedOrigin)
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
        CompatibilitySchemaDiagnostics.recordTune(body: body)
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
        guard let authorization = credential.accessToken() else { return nil }
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

    static func playbackKey(for keyID: FixedLivePlaybackKeyID, using credential: AuthenticationCredential) -> URLRequest? {
        let allowedPathCharacters = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        guard let encodedKeyID = keyID.value.addingPercentEncoding(withAllowedCharacters: allowedPathCharacters),
              let url = URL(string: "\(scheme)://\(host)/playback/key/v1/\(encodedKeyID)")
        else { return nil }
        guard let authorization = credential.accessToken() else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
        return request
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
