import Foundation

enum BundledThemeManifestOfflineTests {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private static let manifestKeys: Set<String> = [
        "schemaVersion", "identifier", "displayName", "playerBackground", "metadataPanel", "accent", "destructive", "foregroundScheme",
        "layoutVariant", "silhouette", "size", "typography", "slots", "dragRegions", "decorations"
    ]
    private static let themeKeys: Set<String> = [
        "identifier", "displayName", "source", "rendererLayers", "fontTokens", "fontFiles", "externalAssetURLs"
    ]
    private static let expected: [(name: String, identifier: String, layout: String, silhouette: String, size: String, palette: [String], fonts: [String], layers: [String])] = [
        ("Pixel Desk", "pixel-desk", "desktopUtility", "pixelNotched", "desktop432x304", ["#C8C2AF", "#8A8E83", "#304D92", "#A63A32"], ["systemMonospaced", "systemDefault"], ["pixel-bevel-frame", "pixel-dither-cells", "pixel-display-plate"]),
        ("Pocket Disc", "pocket-disc", "discConsole", "discPod", "console384x320", ["#3E4641", "#202825", "#A6E15A", "#D85A48"], ["systemMonospaced", "systemDefault"], ["disc-molded-plane", "disc-screw-set", "disc-segment-bars"]),
        ("Aqua Vista", "aqua-vista", "aquaPod", "bubbleCapsule", "capsule448x304", ["#C9EFF8", "#78C4E3", "#198D74", "#C74654"], ["systemRounded", "systemDefault"], ["aqua-color-planes", "aqua-bubble-set", "aqua-glass-highlights"])
    ]
    private static let prohibitedAttributions = ["apple", "finder", "platinum", "sony", "minidisc", "walkman", "atrac", "microsoft", "windows", "winamp"]

    static func run(arguments: [String]) throws {
        guard arguments.count == 4 else { throw Failure(description: "expected three manifests and provenance") }
        let manifestTexts = try arguments.prefix(3).map { try String(contentsOfFile: $0, encoding: .utf8) }
        let manifests = try manifestTexts.map(dictionary)
        let provenance = try dictionary(String(contentsOfFile: arguments[3], encoding: .utf8))
        try audit(manifests: manifests, provenance: provenance, manifestTexts: manifestTexts)
        try runNegativeFixtures(manifests: manifests, provenance: provenance, manifestTexts: manifestTexts)
    }

    private static func audit(manifests: [[String: Any]], provenance: [String: Any], manifestTexts: [String]) throws {
        try require(manifests.count == expected.count, "exactly three expressive manifests are required")
        try require(Set(provenance.keys) == ["version", "themes"], "provenance keys must remain closed")
        try require(provenance["version"] as? Int == 1, "provenance version must be one")
        guard let provenanceThemes = provenance["themes"] as? [[String: Any]] else { throw Failure(description: "provenance themes must be records") }
        try require(provenanceThemes.count == expected.count, "provenance must contain every theme")

        var tuples = Set<String>()
        var palettes = Set<String>()
        var frameArrangements = Set<String>()
        for index in expected.indices {
            let item = expected[index]
            let manifest = manifests[index]
            try require(Set(manifest.keys) == manifestKeys, "\(item.name) manifest keys must remain closed")
            try require(manifest["schemaVersion"] as? Int == 3, "\(item.name) must use schema v3")
            try require(manifest["identifier"] as? String == item.identifier, "\(item.name) identifier changed")
            try require(manifest["displayName"] as? String == item.name, "\(item.name) public name changed")
            try require(manifest["layoutVariant"] as? String == item.layout, "\(item.name) layout changed")
            try require(manifest["silhouette"] as? String == item.silhouette, "\(item.name) silhouette changed")
            try require(manifest["size"] as? String == item.size, "\(item.name) size changed")
            let palette = ["playerBackground", "metadataPanel", "accent", "destructive"].compactMap { manifest[$0] as? String }
            try require(palette == item.palette, "\(item.name) palette changed")
            guard let typography = manifest["typography"] as? [String: String] else { throw Failure(description: "\(item.name) typography must be closed") }
            try require(Set(typography.keys) == ["display", "body", "label"], "\(item.name) typography keys changed")
            try require(Set(typography.values).isSubset(of: ["systemDefault", "systemRounded", "systemMonospaced"]), "\(item.name) uses an unsupported font token")
            try require(Set(item.fonts).isSubset(of: Set(typography.values)), "\(item.name) typography lost its approved treatment")
            let slots = try validateSlots(manifest, item.name)
            try validateDragRegions(manifest, slots: slots, name: item.name)
            try validateDecorations(manifest, name: item.name)
            for attribution in prohibitedAttributions {
                try require(!manifestTexts[index].lowercased().contains(attribution), "\(item.name) contains barred attribution \(attribution)")
            }
            try require(tuples.insert("\(item.layout)|\(item.silhouette)|\(item.size)").inserted, "layout tuple repeats")
            try require(palettes.insert(palette.joined(separator: "|")).inserted, "palette-only theme duplication")
            let frameArrangement = slots.map { frame in
                [frame["x", default: 0], frame["y", default: 0], frame["width", default: 0], frame["height", default: 0]]
                    .map(String.init)
                    .joined(separator: ",")
            }.joined(separator: "|")
            try require(frameArrangements.insert(frameArrangement).inserted, "semantic frame arrangement repeats")
            try validateProvenance(provenanceThemes[index], expected: item)
        }
    }

    private static func validateSlots(_ manifest: [String: Any], _ name: String) throws -> [[String: Int]] {
        guard let slots = manifest["slots"] as? [[String: Any]] else { throw Failure(description: "\(name) slots must be records") }
        let semanticNames: Set<String> = ["artwork", "channelIdentity", "metadata", "favorite", "status", "transport", "library", "overflowMenu"]
        try require(slots.count == semanticNames.count, "\(name) must provide all semantic slots")
        try require(Set(slots.compactMap { $0["semantic"] as? String }) == semanticNames, "\(name) semantic slots changed")
        let frames = try slots.map { slot -> [String: Int] in
            guard let frame = slot["frame"] as? [String: Int], Set(slot.keys) == ["semantic", "frame"], Set(frame.keys) == ["x", "y", "width", "height"] else { throw Failure(description: "\(name) slot is malformed") }
            try require(frame.values.allSatisfy { $0 >= 0 && $0 % 4 == 0 }, "\(name) frames must use the four-point grid")
            try require(frame["width", default: 0] > 0 && frame["height", default: 0] > 0, "\(name) frames must be nonempty")
            return frame
        }
        for index in frames.indices {
            for otherIndex in frames.indices.dropFirst(index + 1) {
                try require(!intersects(frames[index], frames[otherIndex]), "\(name) semantic frames overlap")
            }
        }
        let bySemantic = Dictionary(uniqueKeysWithValues: zip(slots.compactMap { $0["semantic"] as? String }, frames))
        for semantic in ["favorite", "transport", "library", "overflowMenu"] {
            guard let frame = bySemantic[semantic] else { throw Failure(description: "\(name) missing interactive frame") }
            try require(frame["width", default: 0] >= 32 && frame["height", default: 0] >= 32, "\(name) interactive target is undersized")
        }
        try require(bySemantic["channelIdentity", default: [:]]["width", default: 0] >= 96, "\(name) channel capacity is insufficient")
        try require(bySemantic["metadata", default: [:]]["width", default: 0] >= 128 && bySemantic["metadata", default: [:]]["height", default: 0] >= 40, "\(name) metadata capacity is insufficient")
        try require(bySemantic["status", default: [:]]["width", default: 0] >= 80, "\(name) status capacity is insufficient")
        return frames
    }

    private static func validateDragRegions(_ manifest: [String: Any], slots: [[String: Int]], name: String) throws {
        guard let regions = manifest["dragRegions"] as? [[String: Int]], !regions.isEmpty else { throw Failure(description: "\(name) needs a drag region") }
        for region in regions {
            try require(Set(region.keys) == ["x", "y", "width", "height"], "\(name) drag region keys changed")
            try require(region.values.allSatisfy { $0 >= 0 && $0 % 4 == 0 }, "\(name) drag region must use the four-point grid")
            try require(region["width", default: 0] >= 80 && region["height", default: 0] >= 20, "\(name) drag region is too small")
            try require(!slots.contains { intersects(region, $0) }, "\(name) drag region overlaps semantic content")
        }
    }

    private static func validateDecorations(_ manifest: [String: Any], name: String) throws {
        guard let decorations = manifest["decorations"] as? [String: Any] else { throw Failure(description: "\(name) decorations are malformed") }
        try require(Set(decorations.keys) == ["backdrop", "chromeFrame", "displayPlate", "ornaments"], "\(name) decoration keys changed")
        try require(decorations["backdrop"] is NSNull && decorations["chromeFrame"] is NSNull && decorations["displayPlate"] is NSNull && (decorations["ornaments"] as? [Any])?.isEmpty == true, "\(name) declares unsupported decoration assets")
    }

    private static func validateProvenance(_ record: [String: Any], expected item: (name: String, identifier: String, layout: String, silhouette: String, size: String, palette: [String], fonts: [String], layers: [String])) throws {
        try require(Set(record.keys) == themeKeys, "\(item.name) provenance keys changed")
        try require(record["identifier"] as? String == item.identifier && record["displayName"] as? String == item.name, "\(item.name) provenance identity changed")
        try require(record["source"] as? String == "original-app-drawn", "\(item.name) provenance must be original app drawing")
        try require(record["rendererLayers"] as? [String] == item.layers, "\(item.name) layer provenance changed")
        try require(record["fontTokens"] as? [String] == item.fonts, "\(item.name) font provenance changed")
        try require((record["fontFiles"] as? [Any])?.isEmpty == true, "\(item.name) must not carry font binaries")
        try require((record["externalAssetURLs"] as? [Any])?.isEmpty == true, "\(item.name) must not depend on external assets")
    }

    private static func runNegativeFixtures(manifests: [[String: Any]], provenance: [String: Any], manifestTexts: [String]) throws {
        func fails(_ name: String, manifests candidate: [[String: Any]], provenance candidateProvenance: [String: Any] = provenance) throws {
            do {
                try audit(manifests: candidate, provenance: candidateProvenance, manifestTexts: manifestTexts)
                throw Failure(description: "negative fixture passed: \(name)")
            } catch let failure as Failure where failure.description == "negative fixture passed: \(name)" {
                throw failure
            } catch { }
        }
        var clone = manifests; clone[2] = clone[1]; try fails("exact clone", manifests: clone)
        var paletteClone = manifests; paletteClone[2]["playerBackground"] = manifests[1]["playerBackground"]; paletteClone[2]["metadataPanel"] = manifests[1]["metadataPanel"]; paletteClone[2]["accent"] = manifests[1]["accent"]; paletteClone[2]["destructive"] = manifests[1]["destructive"]; try fails("palette clone", manifests: paletteClone)
        var missingSlot = manifests; var slots = missingSlot[0]["slots"] as! [[String: Any]]; slots.removeLast(); missingSlot[0]["slots"] = slots; try fails("missing semantic slot", manifests: missingSlot)
        var missingDrag = manifests; missingDrag[0]["dragRegions"] = []; try fails("missing drag region", manifests: missingDrag)
        var offGrid = manifests; var offGridSlots = offGrid[0]["slots"] as! [[String: Any]]; var frame = offGridSlots[0]["frame"] as! [String: Int]; frame["x"] = 18; offGridSlots[0]["frame"] = frame; offGrid[0]["slots"] = offGridSlots; try fails("off-grid frame", manifests: offGrid)
        var repeatedTuple = manifests; repeatedTuple[2]["layoutVariant"] = manifests[1]["layoutVariant"]; repeatedTuple[2]["silhouette"] = manifests[1]["silhouette"]; repeatedTuple[2]["size"] = manifests[1]["size"]; try fails("repeated variant tuple", manifests: repeatedTuple)
        var decoration = manifests; var decorations = decoration[0]["decorations"] as! [String: Any]; decorations["ornaments"] = ["ornament.png"]; decoration[0]["decorations"] = decorations; try fails("undeclared decoration", manifests: decoration)
        var extraManifestKey = manifests; extraManifestKey[0]["authority"] = "forbidden"; try fails("extra manifest key", manifests: extraManifestKey)
        var extraProvenanceKey = provenance; extraProvenanceKey["authority"] = "forbidden"; try fails("extra provenance key", manifests: manifests, provenance: extraProvenanceKey)
        var absentProvenance = provenance; var themes = absentProvenance["themes"] as! [[String: Any]]; themes.removeLast(); absentProvenance["themes"] = themes; try fails("absent provenance", manifests: manifests, provenance: absentProvenance)
        var fontProvenance = provenance; var fontThemes = fontProvenance["themes"] as! [[String: Any]]; fontThemes[0]["fontFiles"] = ["unreviewed.ttf"]; fontProvenance["themes"] = fontThemes; try fails("font file", manifests: manifests, provenance: fontProvenance)
    }

    private static func intersects(_ lhs: [String: Int], _ rhs: [String: Int]) -> Bool {
        lhs["x", default: 0] < rhs["x", default: 0] + rhs["width", default: 0] && rhs["x", default: 0] < lhs["x", default: 0] + lhs["width", default: 0] && lhs["y", default: 0] < rhs["y", default: 0] + rhs["height", default: 0] && rhs["y", default: 0] < lhs["y", default: 0] + lhs["height", default: 0]
    }

    private static func dictionary(_ text: String) throws -> [String: Any] {
        guard let result = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { throw Failure(description: "JSON document is not an object") }
        return result
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(description: message) }
    }
}

do {
    try BundledThemeManifestOfflineTests.run(arguments: Array(CommandLine.arguments.dropFirst()))
    print("Bundled theme manifest audit: PASS")
} catch {
    FileHandle.standardError.write(Data("Bundled theme manifest audit: FAIL — \(error)\n".utf8))
    exit(1)
}
