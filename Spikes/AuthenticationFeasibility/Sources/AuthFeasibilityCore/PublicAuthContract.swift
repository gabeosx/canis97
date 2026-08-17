import Foundation

public enum ContractFactState: String, CaseIterable, Sendable {
    case established
    case open
    case unsafe
}

public enum EvidenceProvenance: String, CaseIterable, Sendable {
    case publicFirstParty = "public-first-party"
    case sanitizedPreliminary = "sanitized-preliminary"
    case empiricallyObserved = "empirically-observed"
    case open
}

public struct ContractFact: Equatable, Sendable {
    public let state: ContractFactState
    public let provenance: EvidenceProvenance

    public init(_ state: ContractFactState, provenance: EvidenceProvenance) {
        self.state = state
        self.provenance = provenance
    }

    public static let publicFirstParty = ContractFact(.established, provenance: .publicFirstParty)
    public static let sanitizedPreliminary = ContractFact(.established, provenance: .sanitizedPreliminary)
    public static let empiricallyObserved = ContractFact(.established, provenance: .empiricallyObserved)
    public static let open = ContractFact(.open, provenance: .open)
    public static let unsafe = ContractFact(.unsafe, provenance: .open)
}

public struct BrowserExperimentEvidence: Equatable, Sendable {
    public var entryURL: String
    public var entrySurface: ContractFact
    public var ordinaryNavigation: ContractFact
    public var appBoundReturn: ContractFact
    public var semanticTransitions: ContractFact
    public var stopBounds: ContractFact
    public var authenticationExpectation: ContractFact
    public var entitlementExpectation: ContractFact
    public var renewalExpectation: ContractFact
    public var tuneKeyExpectation: ContractFact
    public var signOutExpectation: ContractFact
    public var thirdPartyCallbackDocumentation: ContractFact

    public init(
        entryURL: String,
        entrySurface: ContractFact,
        ordinaryNavigation: ContractFact,
        appBoundReturn: ContractFact,
        semanticTransitions: ContractFact,
        stopBounds: ContractFact,
        authenticationExpectation: ContractFact,
        entitlementExpectation: ContractFact,
        renewalExpectation: ContractFact,
        tuneKeyExpectation: ContractFact,
        signOutExpectation: ContractFact,
        thirdPartyCallbackDocumentation: ContractFact
    ) {
        self.entryURL = entryURL
        self.entrySurface = entrySurface
        self.ordinaryNavigation = ordinaryNavigation
        self.appBoundReturn = appBoundReturn
        self.semanticTransitions = semanticTransitions
        self.stopBounds = stopBounds
        self.authenticationExpectation = authenticationExpectation
        self.entitlementExpectation = entitlementExpectation
        self.renewalExpectation = renewalExpectation
        self.tuneKeyExpectation = tuneKeyExpectation
        self.signOutExpectation = signOutExpectation
        self.thirdPartyCallbackDocumentation = thirdPartyCallbackDocumentation
    }

    public static func ready() -> BrowserExperimentEvidence {
        BrowserExperimentEvidence(
            entryURL: "https://www.siriusxm.com/",
            entrySurface: .publicFirstParty,
            ordinaryNavigation: .publicFirstParty,
            appBoundReturn: .sanitizedPreliminary,
            semanticTransitions: .sanitizedPreliminary,
            stopBounds: .sanitizedPreliminary,
            authenticationExpectation: .sanitizedPreliminary,
            entitlementExpectation: .sanitizedPreliminary,
            renewalExpectation: .sanitizedPreliminary,
            tuneKeyExpectation: .sanitizedPreliminary,
            signOutExpectation: .sanitizedPreliminary,
            thirdPartyCallbackDocumentation: .open
        )
    }

    public func validate() throws {
        guard AuthExperimentContract.isPublicFirstPartyEntryURL(entryURL),
              Self.isPublicFact(entrySurface),
              Self.isPublicFact(ordinaryNavigation),
              Self.isClosedExpectation(appBoundReturn),
              Self.isClosedExpectation(semanticTransitions),
              Self.isClosedExpectation(stopBounds),
              Self.isClosedExpectation(authenticationExpectation),
              Self.isClosedExpectation(entitlementExpectation),
              Self.isClosedExpectation(renewalExpectation),
              Self.isClosedExpectation(tuneKeyExpectation),
              Self.isClosedExpectation(signOutExpectation),
              Self.isDocumentationFact(thirdPartyCallbackDocumentation) else {
            throw ContractError.invalidArtifact
        }
    }

    public var hasAllSafeConstructionBounds: Bool {
        let required = [
            entrySurface, ordinaryNavigation, appBoundReturn, semanticTransitions, stopBounds,
            authenticationExpectation, entitlementExpectation, renewalExpectation,
            tuneKeyExpectation, signOutExpectation,
        ]
        return required.allSatisfy { $0.state == .established }
    }

    private static func isPublicFact(_ fact: ContractFact) -> Bool {
        fact.state == .established && fact.provenance == .publicFirstParty
    }

    private static func isClosedExpectation(_ fact: ContractFact) -> Bool {
        switch fact.state {
        case .established:
            return fact.provenance == .sanitizedPreliminary || fact.provenance == .empiricallyObserved
        case .open:
            return fact.provenance == .open
        case .unsafe:
            return false
        }
    }

    private static func isDocumentationFact(_ fact: ContractFact) -> Bool {
        switch fact.state {
        case .open:
            return fact.provenance == .open
        case .established:
            return fact.provenance == .publicFirstParty
        case .unsafe:
            return false
        }
    }
}

public struct NativePurposeContractEvidence: Equatable, Sendable {
    public var clientIdentity: ContractFact
    public var authentication: ContractFact
    public var result: ContractFact
    public var entitlement: ContractFact
    public var renewal: ContractFact
    public var tuneKeyAuthorization: ContractFact
    public var signOut: ContractFact

    public init(
        clientIdentity: ContractFact,
        authentication: ContractFact,
        result: ContractFact,
        entitlement: ContractFact,
        renewal: ContractFact,
        tuneKeyAuthorization: ContractFact,
        signOut: ContractFact
    ) {
        self.clientIdentity = clientIdentity
        self.authentication = authentication
        self.result = result
        self.entitlement = entitlement
        self.renewal = renewal
        self.tuneKeyAuthorization = tuneKeyAuthorization
        self.signOut = signOut
    }

    public static func qualified() -> NativePurposeContractEvidence {
        NativePurposeContractEvidence(
            clientIdentity: .sanitizedPreliminary,
            authentication: .sanitizedPreliminary,
            result: .sanitizedPreliminary,
            entitlement: .sanitizedPreliminary,
            renewal: .sanitizedPreliminary,
            tuneKeyAuthorization: .sanitizedPreliminary,
            signOut: .sanitizedPreliminary
        )
    }

    public func validate() throws {
        let facts = [clientIdentity, authentication, result, entitlement, renewal, tuneKeyAuthorization, signOut]
        guard facts.allSatisfy({ fact in
            fact.state == .established && (fact.provenance == .sanitizedPreliminary || fact.provenance == .empiricallyObserved)
        }) else {
            throw ContractError.invalidArtifact
        }
    }
}

public struct AuthExperimentContract: Equatable, Sendable {
    public let reviewRevision: String
    public var browser: BrowserExperimentEvidence
    public var native: NativePurposeContractEvidence

    public init(reviewRevision: String, browser: BrowserExperimentEvidence, native: NativePurposeContractEvidence) {
        self.reviewRevision = reviewRevision
        self.browser = browser
        self.native = native
    }

    public static func readyForBrowserExperiment() -> AuthExperimentContract {
        AuthExperimentContract(
            reviewRevision: "empirical-proof-v2",
            browser: .ready(),
            native: .qualified()
        )
    }

    public var digest: String {
        Self.digest(for: canonicalTextWithoutDigest)
    }

    public var canonicalText: String {
        canonicalTextWithoutDigest + "Digest: \(digest)\n"
    }

    public func validate() throws {
        guard ArtifactFields.isRevisionTwo(reviewRevision) else { throw ContractError.invalidArtifact }
        try browser.validate()
        try native.validate()
    }

    public static func parse(_ text: String) throws -> AuthExperimentContract {
        let fields = try ArtifactFields.parse(text, ordered: canonicalKeys)
        guard fields["Schema"] == "auth-experiment-v1",
              let revision = fields["Review revision"],
              let entryURL = fields["Browser entry URL"],
              let expectedDigest = fields["Digest"], ArtifactFields.isLowerHex(expectedDigest, count: 16) else {
            throw ContractError.invalidArtifact
        }

        let browser = BrowserExperimentEvidence(
            entryURL: entryURL,
            entrySurface: try fact(fields, stateKey: "Browser entry state", provenanceKey: "Browser entry provenance"),
            ordinaryNavigation: try fact(fields, stateKey: "Navigation state", provenanceKey: "Navigation provenance"),
            appBoundReturn: try fact(fields, stateKey: "Return shape state", provenanceKey: "Return shape provenance"),
            semanticTransitions: try fact(fields, stateKey: "Transition state", provenanceKey: "Transition provenance"),
            stopBounds: try fact(fields, stateKey: "Stop bounds state", provenanceKey: "Stop bounds provenance"),
            authenticationExpectation: try fact(fields, stateKey: "Authentication expectation state", provenanceKey: "Authentication expectation provenance"),
            entitlementExpectation: try fact(fields, stateKey: "Entitlement expectation state", provenanceKey: "Entitlement expectation provenance"),
            renewalExpectation: try fact(fields, stateKey: "Renewal expectation state", provenanceKey: "Renewal expectation provenance"),
            tuneKeyExpectation: try fact(fields, stateKey: "Tune/key expectation state", provenanceKey: "Tune/key expectation provenance"),
            signOutExpectation: try fact(fields, stateKey: "Sign-out expectation state", provenanceKey: "Sign-out expectation provenance"),
            thirdPartyCallbackDocumentation: try fact(fields, stateKey: "Third-party callback documentation state", provenanceKey: "Third-party callback documentation provenance")
        )
        let native = NativePurposeContractEvidence(
            clientIdentity: try fact(fields, stateKey: "Native purpose identity state", provenanceKey: "Native purpose identity provenance"),
            authentication: try fact(fields, stateKey: "Native authentication state", provenanceKey: "Native authentication provenance"),
            result: try fact(fields, stateKey: "Native result state", provenanceKey: "Native result provenance"),
            entitlement: try fact(fields, stateKey: "Native entitlement state", provenanceKey: "Native entitlement provenance"),
            renewal: try fact(fields, stateKey: "Native renewal state", provenanceKey: "Native renewal provenance"),
            tuneKeyAuthorization: try fact(fields, stateKey: "Native tune/key state", provenanceKey: "Native tune/key provenance"),
            signOut: try fact(fields, stateKey: "Native sign-out state", provenanceKey: "Native sign-out provenance")
        )
        let contract = AuthExperimentContract(reviewRevision: revision, browser: browser, native: native)
        try contract.validate()
        guard contract.digest == expectedDigest, contract.canonicalText == text else { throw ContractError.invalidArtifact }
        return contract
    }

    static func isPublicFirstPartyEntryURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              components.scheme == "https",
              let host = components.host?.lowercased(), host == "www.siriusxm.com" || host == "siriusxm.com",
              components.port == nil, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path == "/" else {
            return false
        }
        return true
    }

    private var canonicalTextWithoutDigest: String {
        [
            "Schema: auth-experiment-v1",
            "Review revision: \(reviewRevision)",
            "Browser entry URL: \(browser.entryURL)",
            Self.line("Browser entry", browser.entrySurface),
            Self.line("Navigation", browser.ordinaryNavigation),
            Self.line("Return shape", browser.appBoundReturn),
            Self.line("Transition", browser.semanticTransitions),
            Self.line("Stop bounds", browser.stopBounds),
            Self.line("Authentication expectation", browser.authenticationExpectation),
            Self.line("Entitlement expectation", browser.entitlementExpectation),
            Self.line("Renewal expectation", browser.renewalExpectation),
            Self.line("Tune/key expectation", browser.tuneKeyExpectation),
            Self.line("Sign-out expectation", browser.signOutExpectation),
            Self.line("Third-party callback documentation", browser.thirdPartyCallbackDocumentation),
            Self.line("Native purpose identity", native.clientIdentity),
            Self.line("Native authentication", native.authentication),
            Self.line("Native result", native.result),
            Self.line("Native entitlement", native.entitlement),
            Self.line("Native renewal", native.renewal),
            Self.line("Native tune/key", native.tuneKeyAuthorization),
            Self.line("Native sign-out", native.signOut),
        ].flatMap { $0.split(separator: "\n", omittingEmptySubsequences: false) }
            .map(String.init)
            .joined(separator: "\n") + "\n"
    }

    private static func line(_ name: String, _ fact: ContractFact) -> String {
        "\(name) state: \(fact.state.rawValue)\n\(name) provenance: \(fact.provenance.rawValue)"
    }

    private static let canonicalKeys = [
        "Schema", "Review revision", "Browser entry URL",
        "Browser entry state", "Browser entry provenance", "Navigation state", "Navigation provenance",
        "Return shape state", "Return shape provenance", "Transition state", "Transition provenance",
        "Stop bounds state", "Stop bounds provenance", "Authentication expectation state", "Authentication expectation provenance",
        "Entitlement expectation state", "Entitlement expectation provenance", "Renewal expectation state", "Renewal expectation provenance",
        "Tune/key expectation state", "Tune/key expectation provenance", "Sign-out expectation state", "Sign-out expectation provenance",
        "Third-party callback documentation state", "Third-party callback documentation provenance",
        "Native purpose identity state", "Native purpose identity provenance", "Native authentication state", "Native authentication provenance",
        "Native result state", "Native result provenance", "Native entitlement state", "Native entitlement provenance",
        "Native renewal state", "Native renewal provenance", "Native tune/key state", "Native tune/key provenance",
        "Native sign-out state", "Native sign-out provenance", "Digest",
    ]

    private static func fact(_ fields: [String: String], stateKey: String, provenanceKey: String) throws -> ContractFact {
        guard let stateValue = fields[stateKey], let state = ContractFactState(rawValue: stateValue),
              let provenanceValue = fields[provenanceKey], let provenance = EvidenceProvenance(rawValue: provenanceValue) else {
            throw ContractError.invalidArtifact
        }
        return ContractFact(state, provenance: provenance)
    }

    private static func digest(for text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

public enum ExperimentReadiness: String, Equatable, Sendable {
    case browserExperimentReady = "browser-experiment-ready"
    case browserExperimentIncomplete = "browser-experiment-incomplete"

    public func canonicalText(contractDigest: String) -> String {
        [
            "Schema: experiment-readiness-v1",
            "Contract digest: \(contractDigest)",
            "Readiness: \(rawValue)",
            "",
        ].joined(separator: "\n")
    }
}

public struct ExperimentApproval: Equatable, Sendable {
    public let contractDigest: String

    public init(contract: AuthExperimentContract) {
        self.contractDigest = contract.digest
    }

    public static func record(for contract: AuthExperimentContract) throws -> ExperimentApproval {
        guard try CandidateSelection.experimentReadiness(for: contract) == .browserExperimentReady else {
            throw ContractError.invalidArtifact
        }
        return ExperimentApproval(contract: contract)
    }

    public var canonicalText: String {
        [
            "Schema: experiment-approval-v1",
            "Contract digest: \(contractDigest)",
            "Owner approval: confirmed",
            "",
        ].joined(separator: "\n")
    }

    public static func parse(_ text: String) throws -> ExperimentApproval {
        let fields = try ArtifactFields.parse(text, ordered: ["Schema", "Contract digest", "Owner approval"])
        guard fields["Schema"] == "experiment-approval-v1",
              let digest = fields["Contract digest"], ArtifactFields.isLowerHex(digest, count: 16),
              fields["Owner approval"] == "confirmed" else {
            throw ContractError.invalidArtifact
        }
        let approval = ExperimentApproval(contractDigest: digest)
        guard approval.canonicalText == text else { throw ContractError.invalidArtifact }
        return approval
    }

    private init(contractDigest: String) {
        self.contractDigest = contractDigest
    }

    public func validate(against contract: AuthExperimentContract) throws {
        try contract.validate()
        guard contractDigest == contract.digest else { throw ContractError.invalidArtifact }
    }
}

private extension ArtifactFields {
    static func isLowerHex(_ value: String, count: Int) -> Bool {
        value.count == count && value.allSatisfy { $0.isNumber || ("a"..."f").contains(String($0)) }
    }
}
