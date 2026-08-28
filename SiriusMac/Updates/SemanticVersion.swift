import Foundation

struct StableSemanticVersion: Comparable, CustomStringConvertible, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let versionText = trimmed.first == "v" ? String(trimmed.dropFirst()) : trimmed
        let components = versionText.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 else { return nil }

        let parsed = components.compactMap(Self.parseCanonicalComponent)
        guard parsed.count == 3 else { return nil }
        major = parsed[0]
        minor = parsed[1]
        patch = parsed[2]
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    private static func parseCanonicalComponent(_ component: Substring) -> Int? {
        guard !component.isEmpty,
              component.allSatisfy({ $0.isASCII && $0.isNumber }),
              component.count == 1 || component.first != "0"
        else { return nil }
        return Int(component)
    }
}

struct GitHubRepository: Equatable, Sendable {
    let owner: String
    let name: String

    init?(_ rawValue: String) {
        let components = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2,
              components.allSatisfy(Self.isValidPathComponent)
        else { return nil }
        owner = String(components[0])
        name = String(components[1])
    }

    var value: String { "\(owner)/\(name)" }

    var latestReleaseAPIURL: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(name)/releases/latest")!
    }

    private static func isValidPathComponent(_ component: Substring) -> Bool {
        !component.isEmpty
            && component != "."
            && component != ".."
            && component.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || "._-".contains(character))
        }
    }
}
