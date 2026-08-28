import Foundation

enum ExpressiveSkinPhaseContract {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(description: message) }
    }

    static func source(at root: URL, _ relativePath: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    static func run(arguments: [String]) throws {
        try require(arguments.count == 3, "expected SiriusMac, SiriusMacTests, and project paths")
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let player = try source(at: root, "SiriusMac/Player/CompactPlayerView.swift")
        let presentation = try source(at: root, "SiriusMac/Player/CompactPlayerPresentation.swift")
        let management = try source(at: root, "SiriusMac/Skins/SkinManagementView.swift")
        let appearance = try source(at: root, "SiriusMac/Skins/SkinAppearance.swift")
        let importer = try source(at: root, "SiriusMac/Skins/SkinPackageImporter.swift")
        let app = try source(at: root, "SiriusMac/SiriusMacApp.swift")
        let harness = try source(at: root, "SiriusMac/Testing/UITestHarness.swift")

        for resource in ["SignalGlow", "TapeDeck", "PixelDesk", "PocketDisc", "AquaVista"] {
            try require(FileManager.default.fileExists(atPath: root.appendingPathComponent("SiriusMac/Skins/Bundled/\(resource).json").path), "missing bundled appearance: \(resource)")
        }
        for asset in ["PocketDiscFaceplate@2x.png", "AquaVistaFaceplate@2x.png"] {
            try require(FileManager.default.fileExists(atPath: root.appendingPathComponent("SiriusMac/Skins/Bundled/Assets/\(asset)").path), "missing bundled faceplate: \(asset)")
            try require(player.contains(asset) == false, "faceplate identity must stay declarative in its manifest: \(asset)")
        }
        for marker in ["case 1:", "case 2:", "case 3:", "CompactSkinSemanticSlot", "transportControlSize", "focusClearance"] {
            try require(appearance.contains(marker) || presentation.contains(marker), "missing compatibility or interaction marker: \(marker)")
        }
        for slot in ["artwork", "channelIdentity", "metadata", "favorite", "status", "transport", "library", "overflowMenu"] {
            try require(player.contains("expressiveSlot(.\(slot))"), "missing semantic slot: \(slot)")
        }
        for identifier in ["compact.favorite", "compact.status", "previous", "play-pause", "next", "compact.show-library", "compact.always-on-top", "compact.sign-out"] {
            try require(player.contains(identifier), "missing control identifier: \(identifier)")
        }
        for copy in [
            "Nothing Playing",
            "Choose a channel in the Library to start listening.",
            "Loading playback",
            "Playback couldn’t start.",
            "This appearance is unavailable. Native appearance has been restored.",
            "No imported appearances yet.",
            "Import a local .siriusskin package to add one.",
            "This appearance couldn’t be used. Choose another package or select Native.",
        ] {
            try require(player.contains(copy) || presentation.contains(copy) || management.contains(copy), "missing app-owned copy: \(copy)")
        }
        try require(player.contains("duration: 0.15") && player.contains("reduceMotion ? nil"), "motion policy must remain a 150ms optional app-owned treatment")
        try require(player.contains("expressiveFaceplateLayer") && player.contains("hasExpressiveFaceplate"), "validated faceplates must render behind semantic slots")
        try require(player.contains("expressiveSlotAlignment") && player.contains("minimumScaleFactor(0.72)") && player.contains("minimumScaleFactor(0.78)"), "expressive slot content must remain inset, aligned, and bounded")
        try require(player.contains("compact.overflow.use-native-appearance"), "compact Native recovery route is missing")
        try require(app.contains("Button(\"Use Native Appearance\")") && app.contains("restoreNativeAppearance()"), "Player-menu Native recovery route is missing")
        try require(importer.contains("SkinManifestValidator.referencedAssetPaths"), "importer must use the closed asset accessor")
        try require(!management.contains("NSOpenPanel") && !management.contains("NSAlert"), "management must use native SwiftUI presentation")
        try require(harness.contains("OfflineReviewAppearanceFixture") && harness.contains("compactAppearanceFailure"), "offline review matrix is incomplete")

        let enumerator = FileManager.default.enumerator(at: root.appendingPathComponent("SiriusMac/Skins"), includingPropertiesForKeys: nil)
        while let fileURL = enumerator?.nextObject() as? URL {
            try require(!["ttf", "otf", "woff", "woff2"].contains(fileURL.pathExtension.lowercased()), "appearance resources may not contain font binaries: \(fileURL.lastPathComponent)")
        }
    }
}

do {
    try ExpressiveSkinPhaseContract.run(arguments: Array(CommandLine.arguments.dropFirst()))
    print("Expressive skin phase contract: PASS")
} catch {
    FileHandle.standardError.write(Data("Expressive skin phase contract: FAIL — \(error)\\n".utf8))
    exit(1)
}
