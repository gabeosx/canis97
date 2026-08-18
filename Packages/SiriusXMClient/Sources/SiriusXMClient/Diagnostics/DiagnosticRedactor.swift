import Foundation

/// Structural fixture promotion failure with no raw input detail.
enum DiagnosticRedactionError: Error, Sendable, Equatable {
    case invalidJSON
    case sensitiveStructure
}

/// Validates synthetic fixtures before they can become test evidence.
enum DiagnosticRedactor {
    private static let sensitiveTerms: Set<String> = [
        "account", "authorization", "body", "cookie", "credential", "error", "header",
        "password", "request", "response", "session", "token", "url",
    ]

    static func promoteSyntheticFixture(_ data: Data) throws -> Data {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            throw DiagnosticRedactionError.invalidJSON
        }
        try validate(object)
        guard JSONSerialization.isValidJSONObject(object) else {
            throw DiagnosticRedactionError.invalidJSON
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func validate(_ value: Any) throws {
        switch value {
        case let dictionary as [String: Any]:
            for (key, nestedValue) in dictionary {
                guard !containsSensitiveTerm(key) else {
                    throw DiagnosticRedactionError.sensitiveStructure
                }
                try validate(nestedValue)
            }
        case let array as [Any]:
            for nestedValue in array {
                try validate(nestedValue)
            }
        case let string as String:
            guard !containsSensitiveTerm(string) else {
                throw DiagnosticRedactionError.sensitiveStructure
            }
        case is NSNumber, is NSNull:
            return
        default:
            throw DiagnosticRedactionError.invalidJSON
        }
    }

    private static func containsSensitiveTerm(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return sensitiveTerms.contains(where: { normalized.contains($0) })
    }
}
