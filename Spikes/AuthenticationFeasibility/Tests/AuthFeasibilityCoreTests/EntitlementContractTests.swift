import AuthFeasibilityCore
import Testing

@Test("canonical unsupported entitlement closure validates without a provider destination")
func unsupportedEntitlementContractIsCanonicalAndDestinationFree() throws {
    let text = EntitlementContract.unsupportedCanonicalText
    let contract = try EntitlementContract.parse(text)

    #expect(contract.status == .unsupported)
    #expect(contract.canonicalText == text)
    #expect(!text.contains("Host:"))
    #expect(!text.contains("Path:"))
}

@Test("supported entitlement contract requires exact public evidence and predicates")
func supportedEntitlementContractRequiresAllBoundedFields() throws {
    let text = supportedContractText()
    let contract = try EntitlementContract.parse(text)

    #expect(contract.status == .supported)
    #expect(contract.request?.method == "GET")
    #expect(contract.request?.host == "api.edge-gateway.siriusxm.com")
    #expect(contract.successPredicate?.field == "subscription.status")
    #expect(contract.successPredicate?.value == "active")
}

@Test("unsupported or unsafe entitlement evidence fails closed")
func entitlementContractRejectsAmbiguousOrSensitiveEvidence() {
    #expect(throws: ContractError.self) {
        try EntitlementContract.parse(supportedContractText(replacing: "Public provenance URL: https://www.siriusxm.com/player", with: "Public provenance URL: https://example.invalid/player"))
    }
    #expect(throws: ContractError.self) {
        try EntitlementContract.parse(supportedContractText(replacing: "Path: /subscription/v1/status", with: "Path: /profile/v4/profiles/me"))
    }
    #expect(throws: ContractError.self) {
        try EntitlementContract.parse(supportedContractText(replacing: "Method: GET", with: "Method: GET\nRedirects: allowed"))
    }
    #expect(throws: ContractError.self) {
        try EntitlementContract.parse(supportedContractText(replacing: "Success field: subscription.status", with: "Success field: subscription.status\nAuthorization: sensitive-canary"))
    }
}

@Test("entitlement parser rejects missing provenance, unknown fields, and noncanonical text")
func entitlementContractRejectsMalformedText() {
    #expect(throws: ContractError.self) {
        try EntitlementContract.parse(supportedContractText(replacing: "Retrieved on: 2026-08-17\n", with: ""))
    }
    #expect(throws: ContractError.self) {
        try EntitlementContract.parse(supportedContractText(replacing: "Denial value: inactive", with: "Denial value: inactive\nUnknown: no"))
    }
    #expect(throws: ContractError.self) {
        try EntitlementContract.parse(supportedContractText() + "\n")
    }
}

private func supportedContractText(replacing old: String? = nil, with new: String = "") -> String {
    let text = [
        "Schema: entitlement-contract-v1",
        "Status: supported",
        "Method: GET",
        "Host: api.edge-gateway.siriusxm.com",
        "Path: /subscription/v1/status",
        "Public provenance URL: https://www.siriusxm.com/player",
        "Retrieved on: 2026-08-17",
        "Success field: subscription.status",
        "Success value: active",
        "Denial field: subscription.status",
        "Denial value: inactive",
        "Malformed rule: missing-or-non-string-field",
        "",
    ].joined(separator: "\n")
    guard let old else { return text }
    return text.replacingOccurrences(of: old, with: new)
}
