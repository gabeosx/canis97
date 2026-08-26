import Foundation

struct BundledSkinManifestOfflineTests {
    private enum PaletteRole: CaseIterable {
        case canvas
        case metadata
        case accent
        case destructive
    }

    /// Mirrors the app-owned `CompactSkinSurface` vocabulary. This audit
    /// deliberately keeps the mapping fixed: manifests cannot add renderer
    /// surfaces or decide which role controls an existing surface.
    private enum SurfaceRole: CaseIterable {
        case canvas
        case metadata
        case status
        case transport
        case footer
        case interactiveAccent
        case criticalState
    }

    private static let completeKeys: Set<String> = [
        "schemaVersion", "identifier", "displayName", "playerBackground",
        "metadataPanel", "accent", "destructive", "foregroundScheme",
        "contentPadding", "sectionSpacing", "cornerRadius", "backgroundAsset",
        "metadataPanelAsset"
    ]
    private static let nativePalette: [PaletteRole: RGB] = [
        .canvas: .init(hex: "#111111"),
        .metadata: .init(hex: "#262626"),
        .accent: .init(hex: "#C6FF00"),
        .destructive: .init(hex: "#FF453A")
    ]
    private static let minimumCanvasDistance = 40.0
    private static let minimumMetadataDistance = 55.0

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
        try require(manifests.allSatisfy { $0.backgroundAsset == nil && $0.metadataPanelAsset == nil }, "bundled appearances must remain complete without decorations")

        let ordered = manifests.sorted {
            if $0.displayName != $1.displayName { return $0.displayName < $1.displayName }
            return $0.identifier < $1.identifier
        }
        try require(
            ordered.map(\.displayName) == ["Signal Glow", "Tape Deck"],
            "bundled ordering must be deterministic by display name then identifier"
        )
        try verifyExpectedPalettes(ordered)
        try verifyFullSurfaceRoleAccounting()
        try verifyMaterialSurfaceSeparation(ordered)

        var unknownKeyObject = try object(from: Data(contentsOf: URL(fileURLWithPath: paths[0])))
        for forbiddenKey in ["transportControlSize", "layout", "action", "accessibilityLabel", "remoteURL", "script"] {
            unknownKeyObject[forbiddenKey] = forbiddenKey == "transportControlSize" ? 32 : "forbidden"
            let unknownKeyData = try JSONSerialization.data(withJSONObject: unknownKeyObject)
            do {
                _ = try validate(unknownKeyData)
                throw AuditFailure("an unknown manifest key was accepted")
            } catch let error as AuditFailure {
                try require(error.description == "manifest keys are not exact", "unknown key failed for the expected reason")
            }
            unknownKeyObject.removeValue(forKey: forbiddenKey)
        }

        print("PASS: exactly two complete bundled manifests")
        print("PASS: schema, palette, and metric boundaries")
        print("PASS: complete fixed surface role accounting")
        print("PASS: canvas and metadata palettes are materially distinct")
        print("PASS: distinct deterministic ordering inputs")
        print("PASS: layout, behavior, and unknown fields are rejected")
    }

    private static func verifyExpectedPalettes(_ manifests: [AuditManifest]) throws {
        let byName = Dictionary(uniqueKeysWithValues: manifests.map { ($0.displayName, $0) })
        let signalGlow = try requiredManifest(named: "Signal Glow", in: byName)
        let tapeDeck = try requiredManifest(named: "Tape Deck", in: byName)
        try require(
            [signalGlow.playerBackground, signalGlow.metadataPanel, signalGlow.accent, signalGlow.destructive]
                == ["#063F2C", "#0B684B", "#62FFAB", "#FF5C75"],
            "Signal Glow must retain its complete green luminous palette"
        )
        try require(
            [tapeDeck.playerBackground, tapeDeck.metadataPanel, tapeDeck.accent, tapeDeck.destructive]
                == ["#4A2D18", "#74482B", "#FFC166", "#FF685B"],
            "Tape Deck must retain its complete warm analog palette"
        )
    }

    private static func verifyFullSurfaceRoleAccounting() throws {
        let paletteRolesBySurface: [SurfaceRole: Set<PaletteRole>] = [
            .canvas: [.canvas, .metadata, .accent],
            .metadata: [.metadata, .accent],
            .status: [.canvas, .accent],
            .transport: [.metadata, .accent],
            .footer: [.canvas, .metadata, .accent],
            .interactiveAccent: [.canvas, .accent],
            .criticalState: [.canvas, .destructive]
        ]
        try require(
            Set(paletteRolesBySurface.keys) == Set(SurfaceRole.allCases),
            "every fixed compact-player surface must have a treatment"
        )
        let consumed = paletteRolesBySurface.values.reduce(into: Set<PaletteRole>()) { $0.formUnion($1) }
        try require(consumed == Set(PaletteRole.allCases), "every mandatory palette role must feed a fixed surface")
    }

    private static func verifyMaterialSurfaceSeparation(_ manifests: [AuditManifest]) throws {
        let byName = Dictionary(uniqueKeysWithValues: manifests.map { ($0.displayName, $0) })
        let signalGlow = try requiredManifest(named: "Signal Glow", in: byName)
        let tapeDeck = try requiredManifest(named: "Tape Deck", in: byName)
        let signalCanvas = RGB(hex: signalGlow.playerBackground)
        let signalMetadata = RGB(hex: signalGlow.metadataPanel)
        let tapeCanvas = RGB(hex: tapeDeck.playerBackground)
        let tapeMetadata = RGB(hex: tapeDeck.metadataPanel)
        try requireSeparated(signalCanvas, nativePalette[.canvas]!, atLeast: minimumCanvasDistance, "Signal Glow canvas must be separated from Native")
        try requireSeparated(tapeCanvas, nativePalette[.canvas]!, atLeast: minimumCanvasDistance, "Tape Deck canvas must be separated from Native")
        try requireSeparated(signalCanvas, tapeCanvas, atLeast: minimumCanvasDistance, "bundled canvas colors must be separated from each other")
        try requireSeparated(signalMetadata, nativePalette[.metadata]!, atLeast: minimumMetadataDistance, "Signal Glow metadata must be separated from Native")
        try requireSeparated(tapeMetadata, nativePalette[.metadata]!, atLeast: minimumMetadataDistance, "Tape Deck metadata must be separated from Native")
        try requireSeparated(signalMetadata, tapeMetadata, atLeast: minimumMetadataDistance, "bundled metadata colors must be separated from each other")
    }

    private static func requiredManifest(named name: String, in manifests: [String: AuditManifest]) throws -> AuditManifest {
        guard let manifest = manifests[name] else { throw AuditFailure("missing \(name) manifest") }
        return manifest
    }

    private static func requireSeparated(_ first: RGB, _ second: RGB, atLeast threshold: Double, _ message: String) throws {
        try require(first.distance(to: second) >= threshold, message)
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

private struct RGB: Hashable {
    let red: Int
    let green: Int
    let blue: Int

    init(hex: String) {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        red = (value >> 16) & 0xFF
        green = (value >> 8) & 0xFF
        blue = value & 0xFF
    }

    func distance(to other: Self) -> Double {
        let redDistance = Double(red - other.red)
        let greenDistance = Double(green - other.green)
        let blueDistance = Double(blue - other.blue)
        return (redDistance * redDistance + greenDistance * greenDistance + blueDistance * blueDistance).squareRoot()
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
