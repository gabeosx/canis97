import Foundation

/// The two admissible outcomes for public entitlement evidence. A public source
/// may either establish a bounded predicate or close it as unsupported; it never
/// grants entitlement by itself.
public enum EntitlementContractStatus: String, Equatable, Sendable {
    case supported
    case unsupported
}

public struct EntitlementRequest: Equatable, Sendable {
    public let method: String
    public let host: String
    public let path: String
}

public struct EntitlementPredicate: Equatable, Sendable {
    public let field: String
    public let value: String
}

/// Byte-canonical, public-only evidence required before the native harness may
/// make an entitlement request. It deliberately has no representation for
/// account data, browser state, raw responses, or credential material.
public struct EntitlementContract: Equatable, Sendable {
    public static let unsupportedCanonicalText = [
        "Schema: entitlement-contract-v1",
        "Status: unsupported",
        "Reason: no-public-bounded-entitlement-predicate",
        "",
    ].joined(separator: "\n")

    public let status: EntitlementContractStatus
    public let request: EntitlementRequest?
    public let provenanceURL: URL?
    public let retrievedOn: String?
    public let successPredicate: EntitlementPredicate?
    public let denialPredicate: EntitlementPredicate?
    public let malformedRule: String?

    private init(
        status: EntitlementContractStatus,
        request: EntitlementRequest? = nil,
        provenanceURL: URL? = nil,
        retrievedOn: String? = nil,
        successPredicate: EntitlementPredicate? = nil,
        denialPredicate: EntitlementPredicate? = nil,
        malformedRule: String? = nil
    ) {
        self.status = status
        self.request = request
        self.provenanceURL = provenanceURL
        self.retrievedOn = retrievedOn
        self.successPredicate = successPredicate
        self.denialPredicate = denialPredicate
        self.malformedRule = malformedRule
    }

    public var canonicalText: String {
        switch status {
        case .unsupported:
            return Self.unsupportedCanonicalText
        case .supported:
            guard let request, let provenanceURL, let retrievedOn,
                  let successPredicate, let denialPredicate, let malformedRule else {
                return ""
            }
            return [
                "Schema: entitlement-contract-v1",
                "Status: supported",
                "Method: \(request.method)",
                "Host: \(request.host)",
                "Path: \(request.path)",
                "Public provenance URL: \(provenanceURL.absoluteString)",
                "Retrieved on: \(retrievedOn)",
                "Success field: \(successPredicate.field)",
                "Success value: \(successPredicate.value)",
                "Denial field: \(denialPredicate.field)",
                "Denial value: \(denialPredicate.value)",
                "Malformed rule: \(malformedRule)",
                "",
            ].joined(separator: "\n")
        }
    }

    public static func parse(_ text: String) throws -> EntitlementContract {
        guard text.utf8.last == 10, !text.hasSuffix("\n\n") else { throw ContractError.invalidArtifact }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.last == "", lines.dropLast().allSatisfy({ !$0.isEmpty }) else { throw ContractError.invalidArtifact }

        var fields: [String: String] = [:]
        for line in lines.dropLast() {
            guard let separator = line.firstIndex(of: ":") else { throw ContractError.invalidArtifact }
            let key = String(line[..<separator])
            let valueStart = line.index(after: separator)
            guard line.indices.contains(valueStart), line[valueStart] == " " else { throw ContractError.invalidArtifact }
            let value = String(line[line.index(after: valueStart)...])
            guard !key.isEmpty, !value.isEmpty, fields[key] == nil else { throw ContractError.invalidArtifact }
            fields[key] = value
        }

        guard fields["Schema"] == "entitlement-contract-v1",
              let statusText = fields["Status"], let status = EntitlementContractStatus(rawValue: statusText) else {
            throw ContractError.invalidArtifact
        }

        switch status {
        case .unsupported:
            let expected = ["Schema", "Status", "Reason"]
            guard Set(fields.keys) == Set(expected),
                  fields["Reason"] == "no-public-bounded-entitlement-predicate",
                  text == unsupportedCanonicalText else {
                throw ContractError.invalidArtifact
            }
            return EntitlementContract(status: .unsupported)

        case .supported:
            let expected = [
                "Schema", "Status", "Method", "Host", "Path", "Public provenance URL", "Retrieved on",
                "Success field", "Success value", "Denial field", "Denial value", "Malformed rule",
            ]
            guard Set(fields.keys) == Set(expected),
                  let method = fields["Method"], ["GET", "POST"].contains(method),
                  let host = fields["Host"], host == "api.edge-gateway.siriusxm.com",
                  let path = fields["Path"], isSafePath(path),
                  path != "/profile/v4/profiles/me",
                  let provenanceText = fields["Public provenance URL"], let provenanceURL = URL(string: provenanceText),
                  isPublicFirstPartyProvenance(provenanceURL),
                  let retrievedOn = fields["Retrieved on"], isDate(retrievedOn),
                  let successField = fields["Success field"], isSafeField(successField),
                  let successValue = fields["Success value"], isSafeValue(successValue),
                  let denialField = fields["Denial field"], denialField == successField,
                  let denialValue = fields["Denial value"], isSafeValue(denialValue), denialValue != successValue,
                  let malformedRule = fields["Malformed rule"], malformedRule == "missing-or-non-string-field" else {
                throw ContractError.invalidArtifact
            }
            let contract = EntitlementContract(
                status: .supported,
                request: EntitlementRequest(method: method, host: host, path: path),
                provenanceURL: provenanceURL,
                retrievedOn: retrievedOn,
                successPredicate: EntitlementPredicate(field: successField, value: successValue),
                denialPredicate: EntitlementPredicate(field: denialField, value: denialValue),
                malformedRule: malformedRule
            )
            guard contract.canonicalText == text else { throw ContractError.invalidArtifact }
            return contract
        }
    }

    private static func isSafePath(_ value: String) -> Bool {
        value.hasPrefix("/") && !value.contains("?") && !value.contains("#") &&
            !value.contains("//") && !value.contains("..") && !value.contains("%") && value.count <= 160
    }

    private static func isPublicFirstPartyProvenance(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              let host = components.host?.lowercased(), ["www.siriusxm.com", "siriusxm.com"].contains(host),
              components.port == nil, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path == "/player" else {
            return false
        }
        return true
    }

    private static func isDate(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value).map { formatter.string(from: $0) == value } ?? false
    }

    private static func isSafeField(_ value: String) -> Bool {
        value.range(of: #"^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$"#, options: .regularExpression) != nil
    }

    private static func isSafeValue(_ value: String) -> Bool {
        value.range(of: #"^[a-z][a-z0-9-]{0,63}$"#, options: .regularExpression) != nil
    }
}
