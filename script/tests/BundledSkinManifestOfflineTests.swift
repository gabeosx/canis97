import Foundation

struct BundledSkinManifestOfflineTests {
    private static let completeKeys: Set<String> = [
        "schemaVersion", "identifier", "displayName", "playerBackground",
        "metadataPanel", "accent", "destructive", "foregroundScheme",
        "contentPadding", "sectionSpacing", "cornerRadius", "backgroundAsset",
        "metadataPanelAsset"
    ]

    static func run() throws {
        let paths = Array(CommandLine.arguments.dropFirst())
        try require(paths.count == 2, "exactly two bundled skin manifests are required")
        try require(
            Set(paths.map { URL(fileURLWithPath: $0).lastPathComponent }) == ["SignalGlow.json", "TapeDeck.json"],
            "the bundled set must be Signal Glow and Tape Deck"
        )

        let manifests = try paths.map { path in
            try validate(Data(contentsOf: URL(fileURLWithPath: path)))
        }
        try require(Set(manifests.map(\.identifier)).count == 2, "bundled identifiers must be distinct")
        try require(Set(manifests.map(\.displayName)).count == 2, "bundled display names must be distinct")

        let ordered = manifests.sorted {
            if $0.displayName != $1.displayName { return $0.displayName < $1.displayName }
            return $0.identifier < $1.identifier
        }
        try require(
            ordered.map(\.displayName) == ["Signal Glow", "Tape Deck"],
            "bundled ordering must be deterministic by display name then identifier"
        )

        var unknownKeyObject = try object(from: Data(contentsOf: URL(fileURLWithPath: paths[0])))
        unknownKeyObject["transportControlSize"] = 32
        let unknownKeyData = try JSONSerialization.data(withJSONObject: unknownKeyObject)
        do {
            _ = try validate(unknownKeyData)
            throw AuditFailure("an unknown manifest key was accepted")
        } catch let error as AuditFailure {
            try require(error.description == "manifest keys are not exact", "unknown key failed for the expected reason")
        }

        print("PASS: exactly two complete bundled manifests")
        print("PASS: schema, palette, and metric boundaries")
        print("PASS: distinct deterministic ordering inputs")
        print("PASS: unknown fields are rejected")
    }

    private static func validate(_ data: Data) throws -> AuditManifest {
        let dictionary = try object(from: data)
        try require(Set(dictionary.keys) == completeKeys, "manifest keys are not exact")
        let manifest = try JSONDecoder().decode(AuditManifest.self, from: data)
        try require(manifest.schemaVersion == 1, "schemaVersion must equal 1")
        try require(isIdentifier(manifest.identifier), "identifier is not stable ASCII")
        try require((1...64).contains(manifest.displayName.count), "displayName is outside its boundary")
        try require(
            [manifest.playerBackground, manifest.metadataPanel, manifest.accent, manifest.destructive]
                .allSatisfy(isSixDigitRGB),
            "palette values must be exact six-digit RGB"
        )
        try require(["light", "dark"].contains(manifest.foregroundScheme), "foregroundScheme is not closed")
        try require((12...20).contains(manifest.contentPadding), "contentPadding is outside its boundary")
        try require((4...12).contains(manifest.sectionSpacing), "sectionSpacing is outside its boundary")
        try require((0...12).contains(manifest.cornerRadius), "cornerRadius is outside its boundary")
        return manifest
    }

    private static func object(from data: Data) throws -> [String: Any] {
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuditFailure("manifest is not a JSON object")
        }
        return dictionary
    }

    private static func isIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.utf8.count <= 64,
              value.unicodeScalars.allSatisfy(\.isASCII),
              let first = value.first,
              first.isLetter || first.isNumber
        else { return false }
        return value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }
    }

    private static func isSixDigitRGB(_ value: String) -> Bool {
        value.count == 7 && value.first == "#" && value.dropFirst().allSatisfy(\.isHexDigit)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw AuditFailure(message) }
    }
}

private struct AuditManifest: Decodable {
    let schemaVersion: Int
    let identifier: String
    let displayName: String
    let playerBackground: String
    let metadataPanel: String
    let accent: String
    let destructive: String
    let foregroundScheme: String
    let contentPadding: Int
    let sectionSpacing: Int
    let cornerRadius: Int
    let backgroundAsset: String?
    let metadataPanelAsset: String?
}

private struct AuditFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

try BundledSkinManifestOfflineTests.run()
