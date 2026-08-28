import Foundation

enum ExpressiveSkinContractOfflineTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(message) }
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    static func run(arguments: [String]) throws {
        guard arguments.count == 3 else { throw Failure("expected Pixel Desk, Signal Glow, and Tape Deck manifests") }
        let manifests = try arguments.map { path -> [String: Any] in
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw Failure("manifest is not an object: \(path)")
            }
            return object
        }
        try require(manifests[0]["schemaVersion"] as? Int == 3, "Pixel Desk must be schema v3")
        try require(manifests[0]["size"] as? String == "desktop432x304", "Pixel Desk size must stay closed")
        try require(manifests[1]["schemaVersion"] as? Int == 2 && manifests[2]["schemaVersion"] as? Int == 2, "legacy bundled manifests must remain v2")

        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let importer = try String(contentsOf: root.appendingPathComponent("SiriusMac/Skins/SkinPackageImporter.swift"), encoding: .utf8)
        try require(importer.contains("SkinManifestValidator.referencedAssetPaths"), "importer must use the compiler-owned asset accessor")
        try require(!importer.contains("JSONDecoder().decode(SkinManifest.self"), "importer must not decode schema-v1 assets directly")
        let window = try String(contentsOf: root.appendingPathComponent("SiriusMac/Windows/CompactWindowController.swift"), encoding: .utf8)
        try require(window.contains("struct CompactWindowPositionRecord"), "window restoration must use a versioned record")
        try require(window.contains("enum CompactWindowGeometry"), "window transitions must use pure finite geometry")
        try require(window.contains("restoreNativeAppearance"), "invalid restoration must route to Native recovery")
    }
}

do {
    try ExpressiveSkinContractOfflineTests.run(arguments: Array(CommandLine.arguments.dropFirst()))
    print("Expressive skin offline contract: PASS")
} catch {
    FileHandle.standardError.write(Data("Expressive skin offline contract: FAIL — \(error)\n".utf8))
    exit(1)
}
