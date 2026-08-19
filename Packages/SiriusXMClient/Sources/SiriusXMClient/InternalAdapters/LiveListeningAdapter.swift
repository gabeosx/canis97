import Foundation

/// Strict, non-retaining compatibility classifiers for the Phase 02 contract.
/// It intentionally exposes only a closed inspection result: opaque response
/// values never cross this adapter boundary.
enum LiveListeningAdapter {
    enum PlaybackKeyInspection: Sendable, Equatable {
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
