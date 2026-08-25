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

struct ValidatedSkinAppearance: Identifiable, Equatable, Sendable {
    let reference: SkinSelectionReference
    let displayName: String
    let style: CompactSkinStyle
    let cornerRadius: CGFloat
    let backgroundAssetURL: URL?
    let metadataPanelAssetURL: URL?

    var id: SkinSelectionReference { reference }

    static let native = Self(
        reference: .native,
        displayName: "Native",
        style: .fallback,
        cornerRadius: 4,
        backgroundAssetURL: nil,
        metadataPanelAssetURL: nil
    )
}

enum SkinManifestValidator {
    typealias AssetResolver = @Sendable (String) -> URL?

    private static let requiredKeys: Set<String> = [
        "schemaVersion", "identifier", "displayName", "playerBackground",
        "metadataPanel", "accent", "destructive", "foregroundScheme",
        "contentPadding", "sectionSpacing", "cornerRadius"
    ]
    private static let optionalKeys: Set<String> = ["backgroundAsset", "metadataPanelAsset"]

    static func validate(
        _ data: Data,
        classification: SkinClassification = .imported,
        assetResolver: AssetResolver = { _ in nil }
    ) throws -> ValidatedSkinAppearance {
        guard classification != .native else { return .native }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { throw SkinManifestValidationError.malformedDocument }

        let keys = Set(dictionary.keys)
        guard requiredKeys.isSubset(of: keys),
              keys.isSubset(of: requiredKeys.union(optionalKeys))
        else { throw SkinManifestValidationError.unknownOrMissingKeys }

        let decoder = JSONDecoder()
        guard let manifest = try? decoder.decode(SkinManifest.self, from: data) else {
            throw SkinManifestValidationError.malformedDocument
        }
        guard manifest.schemaVersion == 1 else {
            throw SkinManifestValidationError.unsupportedSchema
        }

        let trimmedName = manifest.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName == manifest.displayName,
              (1...64).contains(manifest.displayName.count)
        else { throw SkinManifestValidationError.invalidDisplayName }

        let colors = [manifest.playerBackground, manifest.metadataPanel, manifest.accent, manifest.destructive]
        guard colors.allSatisfy(isSixDigitRGB) else {
            throw SkinManifestValidationError.invalidColor
        }
        guard (12...20).contains(manifest.contentPadding),
              (4...12).contains(manifest.sectionSpacing),
              (0...12).contains(manifest.cornerRadius)
        else { throw SkinManifestValidationError.invalidMetric }

        let backgroundAssetURL = try resolve(manifest.backgroundAsset, using: assetResolver)
        let metadataPanelAssetURL = try resolve(manifest.metadataPanelAsset, using: assetResolver)
        let foregroundScheme: CompactPlayerForegroundColorScheme = switch manifest.foregroundScheme {
        case .light: .light
        case .dark: .dark
        }

        return ValidatedSkinAppearance(
            reference: SkinSelectionReference(identifier: manifest.identifier, classification: classification),
            displayName: manifest.displayName,
            style: CompactSkinStyle(
                contentSize: NativeCompactPlayerStyle.fallback.contentSize,
                dominantHex: manifest.playerBackground,
                secondaryHex: manifest.metadataPanel,
                accentHex: manifest.accent,
                destructiveHex: manifest.destructive,
                foregroundColorScheme: foregroundScheme,
                padding: CGFloat(manifest.contentPadding),
                sectionSpacing: CGFloat(manifest.sectionSpacing)
            ),
            cornerRadius: CGFloat(manifest.cornerRadius),
            backgroundAssetURL: backgroundAssetURL,
            metadataPanelAssetURL: metadataPanelAssetURL
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

    static let phaseOne: SkinAppearanceCatalog = {
        let signalGlow: ValidatedSkinAppearance?
        do {
            signalGlow = try SkinManifestValidator.validate(
                Data(signalGlowManifest.utf8),
                classification: .bundled
            )
        } catch {
            signalGlow = nil
        }
        return SkinAppearanceCatalog(appearances: signalGlow.map { [$0] } ?? [])
    }()

    private static let signalGlowManifest = #"""
    {
      "schemaVersion": 1,
      "identifier": "signal-glow",
      "displayName": "Signal Glow",
      "playerBackground": "#07130D",
      "metadataPanel": "#10291A",
      "accent": "#63FF9B",
      "destructive": "#FF5C70",
      "foregroundScheme": "dark",
      "contentPadding": 16,
      "sectionSpacing": 8,
      "cornerRadius": 8,
      "backgroundAsset": null,
      "metadataPanelAsset": null
    }
    """#
}

@MainActor
@Observable
final class SkinAppearanceController {
    let catalog: SkinAppearanceCatalog

    private(set) var selectedReference: SkinSelectionReference
    private(set) var selectedAppearance: ValidatedSkinAppearance
    private(set) var persistenceError: SkinSelectionStoreError?
    private let selectionStore: SkinSelectionStore?
    private var selectionGeneration = 0

    init(
        catalog: SkinAppearanceCatalog,
        initialReference: SkinSelectionReference = .native,
        selectionStore: SkinSelectionStore? = nil
    ) {
        self.catalog = catalog
        self.selectionStore = selectionStore
        let initialAppearance = catalog.resolve(initialReference) ?? SkinAppearanceCatalog.nativeAppearance
        selectedReference = initialAppearance.reference
        selectedAppearance = initialAppearance
    }

    var availableAppearances: [ValidatedSkinAppearance] { catalog.appearances }

    func select(_ reference: SkinSelectionReference) async {
        guard reference != selectedReference,
              let candidate = catalog.resolve(reference)
        else { return }

        selectionGeneration += 1
        let generation = selectionGeneration
        await Task.yield()
        guard generation == selectionGeneration, !Task.isCancelled else { return }

        if let selectionStore {
            do {
                _ = try await selectionStore.save(Self.persisted(reference))
            } catch let error as SkinSelectionStoreError {
                guard generation == selectionGeneration else { return }
                persistenceError = error
                return
            } catch {
                guard generation == selectionGeneration else { return }
                persistenceError = .writeFailed
                return
            }
        }
        guard generation == selectionGeneration else { return }
        persistenceError = nil
        selectedReference = reference
        selectedAppearance = candidate
    }

    func restoreNativeAppearance() async {
        guard selectedReference != .native else { return }
        selectionGeneration += 1
        selectedReference = .native
        selectedAppearance = SkinAppearanceCatalog.nativeAppearance
        persistenceError = nil
        guard let selectionStore else { return }
        do {
            _ = try await selectionStore.save(.native)
        } catch let error as SkinSelectionStoreError {
            persistenceError = error
        } catch {
            persistenceError = .writeFailed
        }
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
