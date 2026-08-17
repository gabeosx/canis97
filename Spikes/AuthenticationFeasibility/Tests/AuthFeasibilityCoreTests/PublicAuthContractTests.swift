import Testing
@testable import AuthFeasibilityCore

@Test("a complete browser construction stays ready when callback documentation is open")
func readyConstructionWithOpenDocumentation() throws {
    let contract = AuthExperimentContract.readyForBrowserExperiment()

    try contract.validate()
    #expect(try CandidateSelection.experimentReadiness(for: contract) == .browserExperimentReady)
    #expect(contract.browser.thirdPartyCallbackDocumentation.state == .open)
    #expect(contract.browser.thirdPartyCallbackDocumentation.provenance == .open)
}

@Test("missing construction facts are incomplete while unsafe facts fail closed")
func incompleteAndUnsafeConstructionAreDistinct() throws {
    var incomplete = AuthExperimentContract.readyForBrowserExperiment()
    incomplete.browser.appBoundReturn = .open
    #expect(try CandidateSelection.experimentReadiness(for: incomplete) == .browserExperimentIncomplete)

    var unsafe = AuthExperimentContract.readyForBrowserExperiment()
    unsafe.browser.stopBounds = .unsafe
    #expect(isPublicContractInvalid { try unsafe.validate() })
}

@Test("canonical contracts reject duplicate, conflicting, non-first-party, and unrecognized input")
func contractParsingFailsClosed() throws {
    let canonical = AuthExperimentContract.readyForBrowserExperiment().canonicalText
    #expect(try AuthExperimentContract.parse(canonical).canonicalText == canonical)

    let duplicate = canonical.replacingOccurrences(
        of: "Browser entry provenance: public-first-party\n",
        with: "Browser entry provenance: public-first-party\nBrowser entry provenance: public-first-party\n"
    )
    #expect(isPublicContractInvalid { try AuthExperimentContract.parse(duplicate) })

    let conflicting = canonical.replacingOccurrences(
        of: "Browser entry provenance: public-first-party",
        with: "Browser entry provenance: sanitized-preliminary"
    )
    #expect(isPublicContractInvalid { try AuthExperimentContract.parse(conflicting) })

    let nonFirstParty = canonical.replacingOccurrences(
        of: "Browser entry URL: https://www.siriusxm.com/",
        with: "Browser entry URL: https://example.invalid/"
    )
    #expect(isPublicContractInvalid { try AuthExperimentContract.parse(nonFirstParty) })

    let unrecognized = String(canonical.dropLast()) + "Unknown: field\n"
    #expect(isPublicContractInvalid { try AuthExperimentContract.parse(unrecognized) })
}

@Test("sanitized preliminary facts are allowed but noncanonical bytes and raw fields are not")
func contractAcceptsSanitizedPreliminaryOnlyInClosedFields() {
    let contract = AuthExperimentContract.readyForBrowserExperiment()
    #expect(contract.browser.appBoundReturn.provenance == .sanitizedPreliminary)
    #expect(contract.native.authentication.provenance == .sanitizedPreliminary)

    let noncanonical = contract.canonicalText.replacingOccurrences(
        of: "Schema: auth-experiment-v1\n",
        with: "Schema: auth-experiment-v1\n\n"
    )
    #expect(isPublicContractInvalid { try AuthExperimentContract.parse(noncanonical) })

    let rawField = String(contract.canonicalText.dropLast()) + "Raw capture: forbidden\n"
    #expect(isPublicContractInvalid { try AuthExperimentContract.parse(rawField) })
}

@Test("native qualification remains a purpose contract and cannot select a runtime")
func nativePurposeContractDoesNotSelectRuntime() throws {
    let contract = AuthExperimentContract.readyForBrowserExperiment()
    try contract.native.validate()
    #expect(try CandidateSelection.experimentReadiness(for: contract) == .browserExperimentReady)
    #expect(CandidateSelection.nativeRuntimeSelection(for: contract) == .notEligible)
}

@Test("approval is issued only for ready bounds and is bound to exact canonical bytes")
func approvalRequiresReadyConstructionAndExactDigest() throws {
    let contract = AuthExperimentContract.readyForBrowserExperiment()
    let approval = try ExperimentApproval.record(for: contract)
    try approval.validate(against: contract)

    var changedContract = contract
    changedContract.browser.thirdPartyCallbackDocumentation = .publicFirstParty
    #expect(isPublicContractInvalid { try approval.validate(against: changedContract) })

    var incompleteContract = contract
    incompleteContract.browser.renewalExpectation = .open
    #expect(isPublicContractInvalid { try ExperimentApproval.record(for: incompleteContract) })
}

private func isPublicContractInvalid<T>(_ operation: () throws -> T) -> Bool {
    do {
        _ = try operation()
        return false
    } catch {
        return true
    }
}
