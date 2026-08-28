import Foundation
import Observation

struct SkinIdentifier: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init?(rawValue: String) {
        guard Self.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let identifier = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Skin identifiers must be stable ASCII values of at most 64 bytes."
            )
        }
        self = identifier
    }

    private static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.utf8.count <= 64,
              value.unicodeScalars.allSatisfy(\.isASCII),
              let first = value.first,
              first.isLetter || first.isNumber
        else { return false }
        return value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }
    }
}

enum SkinClassification: String, Codable, CaseIterable, Hashable, Sendable {
    case native
    case bundled
    case imported
}

struct SkinSelectionReference: Codable, Hashable, Sendable {
    let identifier: SkinIdentifier
    let classification: SkinClassification

    static let native = Self(
        identifier: SkinIdentifier(rawValue: "native")!,
        classification: .native
    )
}

struct SkinManifest: Codable, Equatable, Sendable {
    enum ForegroundScheme: String, Codable, Sendable {
        case light
        case dark
    }

    let schemaVersion: Int
    let identifier: SkinIdentifier
    let displayName: String
    let playerBackground: String
    let metadataPanel: String
    let accent: String
    let destructive: String
    let foregroundScheme: ForegroundScheme
    let contentPadding: Int
    let sectionSpacing: Int
    let cornerRadius: Int
    let backgroundAsset: String?
    let metadataPanelAsset: String?
}

/// Schema version 2 keeps the version 1 document intact while adding only two
/// finite, noninteractive decorative colors. It deliberately does not inherit
/// a permissive decoder or an open-ended style dictionary.
private struct SkinManifestVersion2: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let identifier: SkinIdentifier
    let displayName: String
    let playerBackground: String
    let metadataPanel: String
    let accent: String
    let destructive: String
    let chromeHighlight: String
    let displayGlow: String
    let foregroundScheme: SkinManifest.ForegroundScheme
    let contentPadding: Int
    let sectionSpacing: Int
    let cornerRadius: Int
    let backgroundAsset: String?
    let metadataPanelAsset: String?
}

enum SkinManifestValidationError: Error, Equatable {
    case malformedDocument
    case unknownOrMissingKeys
    case unsupportedSchema
    case invalidDisplayName
    case invalidColor
    case invalidMetric
    case unresolvedAsset
}

typealias CompactSkinStyle = NativeCompactPlayerStyle

/// A closed, app-owned vocabulary for the compact player's visual regions.
/// Appearances can choose finite color tokens, but cannot add surfaces or
/// influence control, layout, accessibility, or playback behavior.
enum CompactSkinSurface: String, CaseIterable, Sendable {
    case canvas
    case chromeHighlight
    case displayGlow
    case metadata
    case status
    case transport
    case footer
    case interactiveAccent
    case criticalState
}

/// Fixed renderer chrome derived from a validated finite appearance.
struct CompactSkinSurfaceTreatment: Equatable, Sendable {
    let fillHex: String
    let strokeHex: String
    let tintHex: String
    let fillOpacity: Double
    let strokeOpacity: Double
}

struct ValidatedSkinAppearance: Identifiable, Equatable, Sendable {
    let reference: SkinSelectionReference
    let displayName: String
    let style: CompactSkinStyle
    let cornerRadius: CGFloat
    let backgroundAssetURL: URL?
    let metadataPanelAssetURL: URL?
    let chromeHighlightHex: String
    let displayGlowHex: String

    init(
        reference: SkinSelectionReference,
        displayName: String,
        style: CompactSkinStyle,
        cornerRadius: CGFloat,
        backgroundAssetURL: URL?,
        metadataPanelAssetURL: URL?,
        chromeHighlightHex: String? = nil,
        displayGlowHex: String? = nil
    ) {
        self.reference = reference
        self.displayName = displayName
        self.style = style
        self.cornerRadius = cornerRadius
        self.backgroundAssetURL = backgroundAssetURL
        self.metadataPanelAssetURL = metadataPanelAssetURL
        self.chromeHighlightHex = chromeHighlightHex ?? style.accentHex
        self.displayGlowHex = displayGlowHex ?? style.secondaryHex
    }

    var id: SkinSelectionReference { reference }

    /// Appearance assets are decoration only. If any requested decoration is
    /// unavailable at render time, the complete static Native value wins.
    func renderableAppearance(
        _ assetIsUsable: (URL) -> Bool
    ) -> ValidatedSkinAppearance {
        let decorationURLs = [backgroundAssetURL, metadataPanelAssetURL].compactMap { $0 }
        guard decorationURLs.allSatisfy(assetIsUsable) else { return .native }
        return self
    }

    /// Projects the already-renderable appearance into fixed renderer chrome.
    /// All opacity and stroke choices are application constants, rather than
    /// part of the skin manifest's authority.
    func surfaceTreatment(for surface: CompactSkinSurface) -> CompactSkinSurfaceTreatment {
        switch surface {
        case .canvas:
            .init(
                fillHex: style.dominantHex,
                strokeHex: style.secondaryHex,
                tintHex: style.accentHex,
                fillOpacity: 1,
                strokeOpacity: 0.5
            )
        case .chromeHighlight:
            .init(
                fillHex: style.dominantHex,
                strokeHex: chromeHighlightHex,
                tintHex: chromeHighlightHex,
                fillOpacity: 0,
                strokeOpacity: 0.72
            )
        case .displayGlow:
            .init(
                fillHex: displayGlowHex,
                strokeHex: displayGlowHex,
                tintHex: displayGlowHex,
                fillOpacity: 0.24,
                strokeOpacity: 0
            )
        case .metadata:
            .init(
                fillHex: style.secondaryHex,
                strokeHex: style.accentHex,
                tintHex: style.accentHex,
                fillOpacity: 0.96,
                strokeOpacity: 0.52
            )
        case .status:
            .init(
                fillHex: style.dominantHex,
                strokeHex: style.accentHex,
                tintHex: style.accentHex,
                fillOpacity: 0.9,
                strokeOpacity: 0.42
            )
        case .transport:
            .init(
                fillHex: style.secondaryHex,
                strokeHex: style.accentHex,
                tintHex: style.accentHex,
                fillOpacity: 0.9,
                strokeOpacity: 0.58
            )
        case .footer:
            .init(
                fillHex: style.dominantHex,
                strokeHex: style.secondaryHex,
                tintHex: style.accentHex,
                fillOpacity: 0.9,
                strokeOpacity: 0.7
            )
        case .interactiveAccent:
            .init(
                fillHex: style.dominantHex,
                strokeHex: style.accentHex,
                tintHex: style.accentHex,
                fillOpacity: 0.82,
                strokeOpacity: 0.82
            )
        case .criticalState:
            .init(
                fillHex: style.dominantHex,
                strokeHex: style.destructiveHex,
                tintHex: style.destructiveHex,
                fillOpacity: 0.9,
                strokeOpacity: 0.9
            )
        }
    }

    static let native = Self(
        reference: .native,
        displayName: "Native",
        style: .fallback,
        cornerRadius: 4,
        backgroundAssetURL: nil,
        metadataPanelAssetURL: nil,
        chromeHighlightHex: "#D6FF60",
        displayGlowHex: "#173A46"
    )
}

enum SkinManifestValidator {
    typealias AssetResolver = @Sendable (String) -> URL?

    private static let version1RequiredKeys: Set<String> = [
        "schemaVersion", "identifier", "displayName", "playerBackground",
        "metadataPanel", "accent", "destructive", "foregroundScheme",
        "contentPadding", "sectionSpacing", "cornerRadius"
    ]
    private static let version1OptionalKeys: Set<String> = ["backgroundAsset", "metadataPanelAsset"]
    private static let version2RequiredKeys = version1RequiredKeys.union(["chromeHighlight", "displayGlow"])

    static func validate(
        _ data: Data,
        classification: SkinClassification = .imported,
        assetResolver: AssetResolver = { _ in nil }
    ) throws -> ValidatedSkinAppearance {
        guard classification != .native else { return .native }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { throw SkinManifestValidationError.malformedDocument }

        guard let schemaVersion = dictionary["schemaVersion"] as? Int else {
            throw SkinManifestValidationError.malformedDocument
        }

        switch schemaVersion {
        case 1:
            return try validateVersion1(data, dictionary: dictionary, classification: classification, assetResolver: assetResolver)
        case 2:
            return try validateVersion2(data, classification: classification, assetResolver: assetResolver)
        default:
            throw SkinManifestValidationError.unsupportedSchema
        }
    }

    /// Validates schema version 2 as a separate, exact contract so version 1
    /// retains its original key set and behavior byte-for-byte.
    static func validateVersion2(
        _ data: Data,
        classification: SkinClassification = .imported,
        assetResolver: AssetResolver = { _ in nil }
    ) throws -> ValidatedSkinAppearance {
        guard classification != .native else { return .native }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { throw SkinManifestValidationError.malformedDocument }

        let keys = Set(dictionary.keys)
        guard dictionary["schemaVersion"] as? Int == 2,
              version2RequiredKeys.isSubset(of: keys),
              keys.isSubset(of: version2RequiredKeys.union(version1OptionalKeys))
        else { throw SkinManifestValidationError.unknownOrMissingKeys }

        let decoder = JSONDecoder()
        guard let manifest = try? decoder.decode(SkinManifestVersion2.self, from: data) else {
            throw SkinManifestValidationError.malformedDocument
        }
        return try validatedAppearance(
            identifier: manifest.identifier,
            displayName: manifest.displayName,
            playerBackground: manifest.playerBackground,
            metadataPanel: manifest.metadataPanel,
            accent: manifest.accent,
            destructive: manifest.destructive,
            chromeHighlight: manifest.chromeHighlight,
            displayGlow: manifest.displayGlow,
            foregroundScheme: manifest.foregroundScheme,
            contentPadding: manifest.contentPadding,
            sectionSpacing: manifest.sectionSpacing,
            cornerRadius: manifest.cornerRadius,
            backgroundAsset: manifest.backgroundAsset,
            metadataPanelAsset: manifest.metadataPanelAsset,
            classification: classification,
            assetResolver: assetResolver
        )
    }

    private static func validateVersion1(
        _ data: Data,
        dictionary: [String: Any],
        classification: SkinClassification,
        assetResolver: AssetResolver
    ) throws -> ValidatedSkinAppearance {
        let keys = Set(dictionary.keys)
        guard version1RequiredKeys.isSubset(of: keys),
              keys.isSubset(of: version1RequiredKeys.union(version1OptionalKeys))
        else { throw SkinManifestValidationError.unknownOrMissingKeys }

        let decoder = JSONDecoder()
        guard let manifest = try? decoder.decode(SkinManifest.self, from: data) else {
            throw SkinManifestValidationError.malformedDocument
        }
        guard manifest.schemaVersion == 1 else {
            throw SkinManifestValidationError.unsupportedSchema
        }

        return try validatedAppearance(
            identifier: manifest.identifier,
            displayName: manifest.displayName,
            playerBackground: manifest.playerBackground,
            metadataPanel: manifest.metadataPanel,
            accent: manifest.accent,
            destructive: manifest.destructive,
            chromeHighlight: manifest.accent,
            displayGlow: manifest.metadataPanel,
            foregroundScheme: manifest.foregroundScheme,
            contentPadding: manifest.contentPadding,
            sectionSpacing: manifest.sectionSpacing,
            cornerRadius: manifest.cornerRadius,
            backgroundAsset: manifest.backgroundAsset,
            metadataPanelAsset: manifest.metadataPanelAsset,
            classification: classification,
            assetResolver: assetResolver
        )
    }

    private static func validatedAppearance(
        identifier: SkinIdentifier,
        displayName: String,
        playerBackground: String,
        metadataPanel: String,
        accent: String,
        destructive: String,
        chromeHighlight: String,
        displayGlow: String,
        foregroundScheme: SkinManifest.ForegroundScheme,
        contentPadding: Int,
        sectionSpacing: Int,
        cornerRadius: Int,
        backgroundAsset: String?,
        metadataPanelAsset: String?,
        classification: SkinClassification,
        assetResolver: AssetResolver
    ) throws -> ValidatedSkinAppearance {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName == displayName,
              (1...64).contains(displayName.count)
        else { throw SkinManifestValidationError.invalidDisplayName }

        let colors = [playerBackground, metadataPanel, accent, destructive, chromeHighlight, displayGlow]
        guard colors.allSatisfy(isSixDigitRGB) else {
            throw SkinManifestValidationError.invalidColor
        }
        guard (12...20).contains(contentPadding),
              (4...12).contains(sectionSpacing),
              (0...12).contains(cornerRadius)
        else { throw SkinManifestValidationError.invalidMetric }

        let backgroundAssetURL = try resolve(backgroundAsset, using: assetResolver)
        let metadataPanelAssetURL = try resolve(metadataPanelAsset, using: assetResolver)
        let playerForegroundScheme: CompactPlayerForegroundColorScheme = switch foregroundScheme {
        case .light: .light
        case .dark: .dark
        }

        return ValidatedSkinAppearance(
            reference: SkinSelectionReference(identifier: identifier, classification: classification),
            displayName: displayName,
            style: CompactSkinStyle(
                contentSize: NativeCompactPlayerStyle.fallback.contentSize,
                dominantHex: playerBackground,
                secondaryHex: metadataPanel,
                accentHex: accent,
                destructiveHex: destructive,
                foregroundColorScheme: playerForegroundScheme,
                padding: CGFloat(contentPadding),
                sectionSpacing: CGFloat(sectionSpacing)
            ),
            cornerRadius: CGFloat(cornerRadius),
            backgroundAssetURL: backgroundAssetURL,
            metadataPanelAssetURL: metadataPanelAssetURL,
            chromeHighlightHex: chromeHighlight,
            displayGlowHex: displayGlow
        )
    }

    private static func isSixDigitRGB(_ value: String) -> Bool {
        guard value.count == 7, value.first == "#" else { return false }
        return value.dropFirst().allSatisfy { $0.isHexDigit }
    }

    private static func resolve(_ path: String?, using resolver: AssetResolver) throws -> URL? {
        guard let path else { return nil }
        guard !path.isEmpty, let url = resolver(path) else {
            throw SkinManifestValidationError.unresolvedAsset
        }
        return url
    }
}

struct SkinAppearanceCatalog: Sendable {
    static let nativeAppearance = ValidatedSkinAppearance.native

    let appearances: [ValidatedSkinAppearance]
    private let appearancesByReference: [SkinSelectionReference: ValidatedSkinAppearance]

    init(appearances: [ValidatedSkinAppearance]) {
        let customAppearances = appearances
            .filter { $0.reference.classification != .native }
            .sorted {
                let nameOrder = $0.displayName.localizedStandardCompare($1.displayName)
                if nameOrder == .orderedSame {
                    return $0.reference.identifier.rawValue < $1.reference.identifier.rawValue
                }
                return nameOrder == .orderedAscending
            }
        self.appearances = [Self.nativeAppearance] + customAppearances
        appearancesByReference = Dictionary(
            customAppearances.map { ($0.reference, $0) },
            uniquingKeysWith: { first, _ in first }
        ).merging([.native: Self.nativeAppearance], uniquingKeysWith: { first, _ in first })
    }

    func resolve(_ reference: SkinSelectionReference) -> ValidatedSkinAppearance? {
        appearancesByReference[reference]
    }

    func inserting(_ appearance: ValidatedSkinAppearance) -> SkinAppearanceCatalog {
        inserting(contentsOf: [appearance])
    }

    func inserting(contentsOf additions: [ValidatedSkinAppearance]) -> SkinAppearanceCatalog {
        let replacementReferences = Set(additions.map(\.reference))
        let retained = appearances.filter {
            $0.reference != .native && !replacementReferences.contains($0.reference)
        }
        return SkinAppearanceCatalog(appearances: retained + additions)
    }

    func removingImported(_ reference: SkinSelectionReference) -> SkinAppearanceCatalog {
        guard reference.classification == .imported else { return self }
        return SkinAppearanceCatalog(
            appearances: appearances.filter { $0.reference != reference }
        )
    }

    static let phaseOne = bundledCatalog()

    static func bundledCatalog(in bundle: Bundle = .main) -> SkinAppearanceCatalog {
        let bundledAppearances: [ValidatedSkinAppearance] = ["SignalGlow", "TapeDeck"].compactMap { resourceName -> ValidatedSkinAppearance? in
            guard let manifestURL = bundle.url(forResource: resourceName, withExtension: "json"),
                  let data = try? Data(contentsOf: manifestURL)
            else { return nil }
            let resourceDirectory = manifestURL.deletingLastPathComponent()
            return try? SkinManifestValidator.validate(
                data,
                classification: .bundled,
                assetResolver: { path in
                    let candidate = resourceDirectory.appendingPathComponent(path, isDirectory: false)
                    return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
                }
            )
        }
        return SkinAppearanceCatalog(appearances: bundledAppearances)
    }
}

@MainActor
@Observable
final class SkinAppearanceController {
    private(set) var catalog: SkinAppearanceCatalog

    private(set) var selectedReference: SkinSelectionReference
    private(set) var selectedAppearance: ValidatedSkinAppearance
    private(set) var persistenceError: SkinSelectionStoreError?
    private(set) var removalError: SkinPackageRejection?
    private let selectionStore: SkinSelectionStore?
    private let removeImportedPackage: ((SkinSelectionReference) throws -> Bool)?
    private var selectionGeneration = 0
    private var latestImportedGeneration = 0
    private var removalsInProgress: Set<SkinSelectionReference> = []

    init(
        catalog: SkinAppearanceCatalog,
        initialReference: SkinSelectionReference = .native,
        selectionStore: SkinSelectionStore? = nil,
        removeImportedPackage: ((SkinSelectionReference) throws -> Bool)? = nil
    ) {
        self.catalog = catalog
        self.selectionStore = selectionStore
        self.removeImportedPackage = removeImportedPackage
        let initialAppearance = catalog.resolve(initialReference) ?? SkinAppearanceCatalog.nativeAppearance
        selectedReference = initialAppearance.reference
        selectedAppearance = initialAppearance
    }

    var availableAppearances: [ValidatedSkinAppearance] { catalog.appearances }

    @discardableResult
    func select(_ reference: SkinSelectionReference) async -> Bool {
        guard !removalsInProgress.contains(reference),
              reference != selectedReference,
              let candidate = catalog.resolve(reference)
        else { return reference == selectedReference }

        selectionGeneration += 1
        let generation = selectionGeneration
        await Task.yield()
        guard generation == selectionGeneration, !Task.isCancelled else { return false }

        if let selectionStore {
            do {
                _ = try await selectionStore.save(Self.persisted(reference))
            } catch let error as SkinSelectionStoreError {
                guard generation == selectionGeneration else { return false }
                persistenceError = error
                return false
            } catch {
                guard generation == selectionGeneration else { return false }
                persistenceError = .writeFailed
                return false
            }
        }
        guard generation == selectionGeneration else { return false }
        persistenceError = nil
        selectedReference = reference
        selectedAppearance = candidate
        return true
    }

    @discardableResult
    func registerImportedAndSelect(_ appearance: ValidatedSkinAppearance) async -> Bool {
        let generation = latestImportedGeneration + 1
        let authority = beginImportedSelection(generation: generation)
        return await commitImportedSelection(
            appearance,
            generation: generation,
            authority: authority
        )
    }

    func registerImported(_ appearance: ValidatedSkinAppearance) {
        guard appearance.reference.classification == .imported,
              !removalsInProgress.contains(appearance.reference)
        else { return }
        catalog = catalog.inserting(appearance)
    }

    /// Reserves selection authority before an import waits for the serialized
    /// transaction queue. A newer import or any ordinary selection invalidates
    /// the returned token before durable or in-memory publication.
    func beginImportedSelection(generation: Int) -> Int {
        latestImportedGeneration = max(latestImportedGeneration, generation)
        selectionGeneration += 1
        return selectionGeneration
    }

    @discardableResult
    func commitImportedSelection(
        _ appearance: ValidatedSkinAppearance,
        generation: Int,
        authority: Int
    ) async -> Bool {
        guard appearance.reference.classification == .imported,
              !removalsInProgress.contains(appearance.reference)
        else { return false }
        catalog = catalog.inserting(appearance)
        guard generation == latestImportedGeneration,
              authority == selectionGeneration,
              !Task.isCancelled
        else { return false }

        await Task.yield()
        guard generation == latestImportedGeneration,
              authority == selectionGeneration,
              !Task.isCancelled
        else { return false }
        if selectedReference == appearance.reference {
            selectedAppearance = appearance
            persistenceError = nil
            return true
        }
        if let selectionStore {
            do {
                _ = try await selectionStore.save(Self.persisted(appearance.reference))
            } catch let error as SkinSelectionStoreError {
                guard generation == latestImportedGeneration,
                      authority == selectionGeneration
                else { return false }
                persistenceError = error
                return false
            } catch {
                guard generation == latestImportedGeneration,
                      authority == selectionGeneration
                else { return false }
                persistenceError = .writeFailed
                return false
            }
        }
        guard generation == latestImportedGeneration,
              authority == selectionGeneration,
              !Task.isCancelled
        else { return false }
        persistenceError = nil
        selectedReference = appearance.reference
        selectedAppearance = appearance
        return true
    }

    /// Selected imported content must not be deleted until Native is durably
    /// confirmed through the ordinary selection path.
    @discardableResult
    func removeImportedSkin(_ reference: SkinSelectionReference) async -> Bool {
        guard reference.classification == .imported,
              removalsInProgress.insert(reference).inserted
        else { return false }
        defer { removalsInProgress.remove(reference) }
        removalError = nil

        if selectedReference == reference {
            guard await select(.native) else { return false }
        } else {
            selectionGeneration += 1
        }

        guard let removeImportedPackage else {
            removalError = .storageFailed
            return false
        }
        do {
            _ = try removeImportedPackage(reference)
            catalog = catalog.removingImported(reference)
            return true
        } catch {
            removalError = .storageFailed
            return false
        }
    }

    @discardableResult
    func restoreNativeAppearance() async -> Bool {
        selectionGeneration += 1
        let generation = selectionGeneration
        publishNative()
        persistenceError = nil
        guard let selectionStore else { return true }
        do {
            _ = try await selectionStore.save(.native)
        } catch let error as SkinSelectionStoreError {
            guard generation == selectionGeneration else { return false }
            persistenceError = error
            return false
        } catch {
            guard generation == selectionGeneration else { return false }
            persistenceError = .writeFailed
            return false
        }
        guard generation == selectionGeneration else { return false }
        return true
    }

    func restorePersistedSelection() async {
        guard let selectionStore else { return }
        selectionGeneration += 1
        let generation = selectionGeneration

        let persisted: PersistedSkinSelection?
        do {
            persisted = try await selectionStore.load()
        } catch let error as SkinSelectionStoreError {
            guard generation == selectionGeneration else { return }
            persistenceError = error
            publishNative()
            return
        } catch {
            guard generation == selectionGeneration else { return }
            persistenceError = .readFailed
            publishNative()
            return
        }

        guard generation == selectionGeneration else { return }
        guard let persisted,
              let reference = Self.reference(persisted),
              let appearance = catalog.resolve(reference)
        else {
            publishNative()
            return
        }
        persistenceError = nil
        selectedReference = reference
        selectedAppearance = appearance
    }

    private func publishNative() {
        selectedReference = .native
        selectedAppearance = SkinAppearanceCatalog.nativeAppearance
    }

    private static func persisted(_ reference: SkinSelectionReference) -> PersistedSkinSelection {
        let classification: PersistedSkinClassification = switch reference.classification {
        case .native: .native
        case .bundled: .bundled
        case .imported: .imported
        }
        return PersistedSkinSelection(
            identifier: reference.identifier.rawValue,
            classification: classification
        )
    }

    private static func reference(_ persisted: PersistedSkinSelection) -> SkinSelectionReference? {
        guard let identifier = SkinIdentifier(rawValue: persisted.identifier) else { return nil }
        let classification: SkinClassification = switch persisted.classification {
        case .native: .native
        case .bundled: .bundled
        case .imported: .imported
        }
        let reference = SkinSelectionReference(identifier: identifier, classification: classification)
        guard reference.classification != .native || reference == .native else { return nil }
        return reference
    }
}
