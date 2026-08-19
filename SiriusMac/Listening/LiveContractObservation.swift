/// The finite live-listening capabilities that the owner-visible checkpoint may classify.
enum LiveCapability: String, Sendable, Equatable, CaseIterable {
    case catalogRefresh = "catalog-refresh"
    case tuneAuthorization = "tune-authorization"
    case resourceResolution = "resource-resolution"
    case mediaKeyAuthorization = "media-key-authorization"
    case avFoundationCompatibility = "avfoundation-compatibility"
    case metadataText = "metadata-text"
    case artwork
    case streamRecovery = "stream-recovery"
}

/// Closed support dispositions that never carry provider or account details.
enum LiveSupportDisposition: String, Sendable, Equatable {
    case supported = "SUPPORTED"
    case notRequired = "NOT REQUIRED"
    case unsupported = "UNSUPPORTED"
}

/// The only purposes for request facts retained after the owner-visible checkpoint.
enum LiveOperationPurpose: String, Sendable, Equatable {
    case catalogObservation = "catalog-observation"
    case selectedTune = "selected-tune"
    case resourceHandoff = "resource-handoff"
    case mediaKeyAuthorization = "media-key-authorization"
    case metadataObservation = "metadata-observation"
    case artworkObservation = "artwork-observation"
    case sameChannelRecovery = "same-channel-recovery"
}

/// Fixed method facts that can be recorded without retaining request data.
enum LiveRequestMethod: String, Sendable, Equatable {
    case get = "GET"
}

/// An allow-listed host-policy label rather than a host name or destination.
enum LiveAuthorizedHostPolicy: String, Sendable, Equatable {
    case firstPartyAuthenticated = "first-party-authenticated"
}

/// Semantic request-template labels; no path values can enter the observation sink.
enum LivePathTemplate: String, Sendable, Equatable {
    case catalog
    case tune
    case resource
    case mediaKey
    case metadata
    case artwork
    case sameChannelRecovery = "same-channel-recovery"
}

/// A closed request-contract fact set that deliberately has no URL, headers, or body.
struct LiveRequestContract: Sendable, Equatable {
    let purpose: LiveOperationPurpose
    let method: LiveRequestMethod
    let authorizedHostPolicy: LiveAuthorizedHostPolicy
    let pathTemplate: LivePathTemplate
}

/// Invented semantic aliases that are sufficient to create later deterministic fixtures.
enum LiveSemanticAlias: String, Sendable, Equatable {
    case catalogEntity = "catalog-entity"
    case selectedChannel = "selected-channel"
    case authorizedResource = "authorized-resource"
    case requiredMediaKey = "required-media-key"
    case currentMetadata = "current-metadata"
    case artworkImage = "artwork-image"
}

enum LiveSemanticValueType: String, Sendable, Equatable {
    case object
    case string
    case boolean
}

enum LiveSemanticCardinality: String, Sendable, Equatable {
    case one
    case optionalOne = "optional-one"
    case many
}

/// A semantic field shape with no provider field name or observed value.
struct LiveSemanticShape: Sendable, Equatable {
    let alias: LiveSemanticAlias
    let valueType: LiveSemanticValueType
    let cardinality: LiveSemanticCardinality
}

/// Terminal protections and failure domains that must stop the bounded run.
enum LiveProtectionClass: String, Sendable, Equatable {
    case newLoginRequired = "new-login-required"
    case unknownHostOrRedirect = "unknown-host-or-redirect"
    case humanVerificationRequired = "human-verification-required"
    case forbidden
    case rateLimited = "rate-limited"
    case authorizationLost = "authorization-lost"
    case entitlementLost = "entitlement-lost"
    case malformedContract = "malformed-contract"
    case unknownContract = "unknown-contract"
    case drmOrAccessControlAmbiguous = "drm-or-access-control-ambiguous"
    case unsupportedMediaHandoff = "unsupported-media-handoff"
    case secretBearingEvidence = "secret-bearing-evidence"
}

/// Observable AVFoundation behavior classifications with no player, item, resource, or log.
enum LiveAVFoundationBehavior: String, Sendable, Equatable {
    case notObserved = "not-observed"
    case audibleAtLiveEdge = "audible-at-live-edge"
    case pauseSilences = "pause-silences"
    case resumeRejoinsLiveEdge = "resume-rejoins-live-edge"
    case stopClearsItem = "stop-clears-item"
    case unsupported = "unsupported"
}

/// The only durable-shaped value that can leave a bounded live observation.
struct LiveContractObservation: Sendable, Equatable {
    let capability: LiveCapability
    let disposition: LiveSupportDisposition
    let requestContract: LiveRequestContract?
    let semanticShapes: [LiveSemanticShape]
    let protection: LiveProtectionClass?
    let avFoundationBehavior: LiveAVFoundationBehavior
}

enum LiveContractObservationClosure: Sendable, Equatable {
    case cancelled
    case signedOut
    case terminalObservation
}

enum LiveContractObservationState: Sendable, Equatable {
    case idle
    case active
    case closed(LiveContractObservationClosure)
}

/// A main-actor, single-use sink that cannot accept raw traffic, secrets, locations, or errors.
@MainActor
final class LiveContractObservationSink {
    private(set) var observations: [LiveContractObservation] = []
    private(set) var state: LiveContractObservationState = .idle

    /// Starts the one owner-authorized run. A started or closed sink cannot be restarted.
    func begin() -> Bool {
        guard state == .idle else { return false }
        state = .active
        return true
    }

    /// Accepts only closed semantic values and closes immediately for terminal outcomes.
    func record(_ observation: LiveContractObservation) -> Bool {
        guard state == .active else { return false }
        observations.append(observation)

        if observation.disposition == .unsupported || observation.protection != nil {
            state = .closed(.terminalObservation)
        }

        return true
    }

    func cancel() {
        close(.cancelled)
    }

    func signOut() {
        close(.signedOut)
    }

    private func close(_ closure: LiveContractObservationClosure) {
        guard state == .active else { return }
        state = .closed(closure)
    }
}
