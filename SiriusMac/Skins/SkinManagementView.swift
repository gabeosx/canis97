import SwiftUI
import UniformTypeIdentifiers

enum SkinManagementErrorPresentation: String, Identifiable, Equatable {
    case invalidPackage
    case unsupportedSchema
    case unsafeContent
    case overBudget
    case cancelled
    case storageFailure
    case selectionFailure
    case removalFailure
    case nativeRecoveryFailure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .invalidPackage: "Appearance Not Imported"
        case .unsupportedSchema: "Appearance Version Not Supported"
        case .unsafeContent: "Unsafe Appearance Package"
        case .overBudget: "Appearance Package Too Large"
        case .cancelled: "Import Cancelled"
        case .storageFailure: "Appearance Couldn’t Be Saved"
        case .selectionFailure: "Appearance Saved, Not Selected"
        case .removalFailure: "Appearance Couldn’t Be Removed"
        case .nativeRecoveryFailure: "Native Appearance Not Confirmed"
        }
    }

    var detail: String {
        switch self {
        case .invalidPackage:
            "Choose a valid .siriusskin package and try again. Your current appearance was not changed."
        case .unsupportedSchema:
            "This package uses an appearance version Sirius Mac doesn’t support. Your current appearance was not changed."
        case .unsafeContent:
            "This package contains content that safe appearances don’t allow. Your current appearance was not changed."
        case .overBudget:
            "This package exceeds the safe appearance limits. Choose a smaller package and try again."
        case .cancelled:
            "The import stopped before making any appearance change."
        case .storageFailure:
            "Sirius Mac couldn’t save this appearance. Your current appearance was not changed. Try again."
        case .selectionFailure:
            "The validated appearance was saved, but your previous appearance remains selected. Select it again when ready."
        case .removalFailure:
            "Sirius Mac couldn’t remove the saved appearance. Native remains active if recovery already completed. Try again."
        case .nativeRecoveryFailure:
            "Sirius Mac couldn’t durably select Native, so the imported appearance was not removed. Try again."
        }
    }

    static func importFailure(_ rejection: SkinPackageRejection) -> Self {
        switch rejection {
        case .cancelled:
            .cancelled
        case .storageFailed:
            .storageFailure
        case .archiveTooLarge, .tooManyEntries, .fileTooLarge, .packageTooLarge,
             .manifestTooLarge, .compressionRatioExceeded, .invalidImageDimensions,
             .deadlineExceeded, .arithmeticOverflow:
            .overBudget
        case .invalidPath, .duplicatePath, .pathCollision, .pathPrefixConflict,
             .encryptedEntry, .symbolicLink, .unsupportedEntry, .unexpectedFile,
             .unsupportedImageType, .invalidImageFrameCount:
            .unsafeContent
        case .sourceUnavailable, .manifestMissing, .extractionFailed, .invalidManifest,
             .invalidAssetReference:
            .invalidPackage
        }
    }
}

struct SkinManagementView: View {
    let appearanceController: SkinAppearanceController
    let skinImportCoordinator: SkinImportCoordinator

    @State private var presentsImporter = false
    @State private var importTask: Task<Void, Never>?
    @State private var removalTask: Task<Void, Never>?
    @State private var removalConfirmation: SkinRemovalConfirmation?
    @State private var statusMessage: String?
    @State private var errorPresentation: SkinManagementErrorPresentation?
    @FocusState private var focusedReference: SkinSelectionReference?

    private var isImporting: Bool { importTask != nil }
    private var isBusy: Bool { importTask != nil || removalTask != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Appearances")
                    .font(.title2.weight(.semibold))
                Text("Choose a built-in look or import a safe local appearance package.")
                    .foregroundStyle(.secondary)
            }

            List {
                appearanceSection("Native", appearances: appearances(classifiedAs: .native))
                appearanceSection("Bundled", appearances: appearances(classifiedAs: .bundled))
                appearanceSection("Imported", appearances: appearances(classifiedAs: .imported))
            }
            .accessibilityIdentifier("appearance.management.list")

            if let statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(statusMessage)
            }

            HStack(spacing: 8) {
                Button("Import Appearance…") {
                    statusMessage = nil
                    errorPresentation = nil
                    presentsImporter = true
                }
                .disabled(isBusy)
                .frame(minHeight: 32)
                .accessibilityIdentifier("appearance.management.import")
                .accessibilityHint("Choose one local .siriusskin package")

                if isImporting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Importing appearance")
                    Button("Cancel Import") {
                        importTask?.cancel()
                    }
                    .frame(minHeight: 32)
                    .accessibilityIdentifier("appearance.management.cancel-import")
                }
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 460)
        .fileImporter(
            isPresented: $presentsImporter,
            allowedContentTypes: [UTType(importedAs: "com.siriusmac.skin-package", conformingTo: .zip)],
            allowsMultipleSelection: false,
            onCompletion: handleImportSelection
        )
        .alert(item: $errorPresentation) { presentation in
            Alert(
                title: Text(presentation.title),
                message: Text(presentation.detail),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog(
            "Remove Appearance?",
            isPresented: Binding(
                get: { removalConfirmation != nil },
                set: { if !$0 { removalConfirmation = nil } }
            ),
            titleVisibility: .visible,
            presenting: removalConfirmation
        ) { confirmation in
            Button("Remove \(confirmation.displayName)", role: .destructive) {
                beginRemoval(confirmation)
            }
            Button("Cancel", role: .cancel) {}
        } message: { confirmation in
            Text("Remove \(confirmation.displayName) from this Mac? Native and bundled appearances cannot be removed.")
        }
        .onDisappear {
            importTask?.cancel()
            removalTask?.cancel()
        }
    }

    @ViewBuilder
    private func appearanceSection(
        _ title: String,
        appearances: [ValidatedSkinAppearance]
    ) -> some View {
        Section(title) {
            if appearances.isEmpty {
                Text("No \(title.lowercased()) appearances")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appearances) { appearance in
                    SkinManagementRow(
                        reference: appearance.reference,
                        displayName: appearance.displayName,
                        classification: appearance.reference.classification,
                        isSelected: appearance.reference == appearanceController.selectedReference,
                        onSelect: {
                            select(appearance.reference)
                        },
                        onRemove: removalAction(for: appearance)
                    )
                    .focused($focusedReference, equals: appearance.reference)
                }
            }
        }
    }

    private func appearances(classifiedAs classification: SkinClassification) -> [ValidatedSkinAppearance] {
        appearanceController.availableAppearances.filter {
            $0.reference.classification == classification
        }
    }

    private func select(_ reference: SkinSelectionReference) {
        statusMessage = nil
        errorPresentation = nil
        Task { @MainActor in
            guard await appearanceController.select(reference) else {
                errorPresentation = .selectionFailure
                focusedReference = reference
                return
            }
            statusMessage = "Appearance selected."
            focusedReference = reference
        }
    }

    private func handleImportSelection(_ result: Result<[URL], any Error>) {
        switch result {
        case let .success(urls):
            guard let sourceURL = urls.first else {
                errorPresentation = .invalidPackage
                return
            }
            beginImport(sourceURL)
        case .failure:
            errorPresentation = .cancelled
        }
    }

    private func beginImport(_ sourceURL: URL) {
        guard !isBusy else { return }
        statusMessage = nil
        errorPresentation = nil
        importTask = Task { @MainActor in
            defer { importTask = nil }
            do {
                let result = try await skinImportCoordinator.importAndSelect(sourceURL)
                if result.selected {
                    statusMessage = result.storageOutcome == .unchanged
                        ? "Appearance already saved and selected."
                        : "Appearance imported and selected."
                    focusedReference = result.appearance.reference
                } else {
                    errorPresentation = .selectionFailure
                }
            } catch let rejection as SkinPackageRejection {
                errorPresentation = .importFailure(rejection)
            } catch SkinPackageCompatibilityFailure.unsupportedSchema {
                errorPresentation = .unsupportedSchema
            } catch is CancellationError {
                errorPresentation = .cancelled
            } catch {
                errorPresentation = .invalidPackage
            }
        }
    }

    private func requestRemoval(_ appearance: ValidatedSkinAppearance) {
        guard appearance.reference.classification == .imported, !isBusy else { return }
        statusMessage = nil
        errorPresentation = nil
        removalConfirmation = SkinRemovalConfirmation(
            reference: appearance.reference,
            displayName: appearance.displayName
        )
    }

    private func removalAction(
        for appearance: ValidatedSkinAppearance
    ) -> (@MainActor () -> Void)? {
        guard appearance.reference.classification == .imported else { return nil }
        return { requestRemoval(appearance) }
    }

    private func beginRemoval(_ confirmation: SkinRemovalConfirmation) {
        guard !isBusy else { return }
        statusMessage = nil
        errorPresentation = nil
        removalTask = Task { @MainActor in
            defer { removalTask = nil }
            do {
                let removed = try await skinImportCoordinator.removeImportedSkin(confirmation.reference)
                guard removed else {
                    errorPresentation = appearanceController.removalError == .storageFailed
                        ? .removalFailure
                        : .nativeRecoveryFailure
                    focusedReference = appearanceController.selectedReference
                    return
                }
                statusMessage = "Appearance removed."
                focusedReference = appearanceController.selectedReference
            } catch let rejection as SkinPackageRejection where rejection == .cancelled {
                errorPresentation = .cancelled
            } catch {
                errorPresentation = .removalFailure
            }
        }
    }
}

private struct SkinRemovalConfirmation: Identifiable {
    let reference: SkinSelectionReference
    let displayName: String

    var id: SkinSelectionReference { reference }
}

struct SkinManagementRow: View {
    let reference: SkinSelectionReference
    let displayName: String
    let classification: SkinClassification
    let isSelected: Bool
    let onSelect: @MainActor () -> Void
    let onRemove: (@MainActor () -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body.weight(.medium))
                Text(classificationLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Label("Selected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
            Button(isSelected ? "Selected" : "Select", action: onSelect)
                .disabled(isSelected)
                .frame(minWidth: 80, minHeight: 32)
                .accessibilityLabel("Select \(displayName)")
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityIdentifier("appearance.management.select.\(reference.identifier.rawValue)")
            if let onRemove {
                Button("Remove", role: .destructive, action: onRemove)
                    .frame(minHeight: 32)
                    .accessibilityLabel("Remove \(displayName)")
                    .accessibilityHint("Asks for confirmation before removing this imported appearance")
                    .accessibilityIdentifier("appearance.management.remove.\(reference.identifier.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(displayName), \(classificationLabel)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var classificationLabel: String {
        switch classification {
        case .native: "Native"
        case .bundled: "Bundled"
        case .imported: "Imported"
        }
    }
}
