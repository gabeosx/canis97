import AppKit
import Foundation
import SiriusXMClient
import SwiftUI

enum CompatibilityArea: String, CaseIterable, Codable, Equatable {
    case authentication
    case entitlement
    case catalog
    case stream
    case metadata
    case playback

    var title: String { rawValue.capitalized }
}

enum CompatibilityClassification: String, Codable, Equatable {
    case available
    case checking
    case degraded
    case unavailable
    case notChecked = "not_checked"

    var title: String {
        switch self {
        case .available: "Available"
        case .checking: "Checking"
        case .degraded: "Degraded"
        case .unavailable: "Unavailable"
        case .notChecked: "Not checked"
        }
    }

    var symbolName: String {
        switch self {
        case .available: "checkmark.circle.fill"
        case .checking: "clock.fill"
        case .degraded: "exclamationmark.triangle.fill"
        case .unavailable: "xmark.octagon.fill"
        case .notChecked: "minus.circle.fill"
        }
    }
}

struct CompatibilityFinding: Codable, Equatable, Identifiable {
    let area: CompatibilityArea
    let classification: CompatibilityClassification

    var id: CompatibilityArea { area }

    var explanation: String {
        switch (area, classification) {
        case (.authentication, .available): "The current sign-in is accepted."
        case (.authentication, .checking): "The current sign-in is being verified."
        case (.authentication, .unavailable): "The sign-in could not be used. Sign in again before checking later stages."
        case (.entitlement, .available): "The account is entitled to listening."
        case (.entitlement, .checking): "The subscription entitlement is being verified."
        case (.entitlement, .unavailable): "The account is not currently entitled to listening."
        case (.catalog, .available): "The channel catalog is available."
        case (.catalog, .checking): "The channel catalog is loading."
        case (.catalog, .degraded): "A saved catalog is available, but its latest refresh failed."
        case (.catalog, .unavailable): "The channel catalog could not be loaded."
        case (.stream, .available): "The current channel produced an authorized media handoff."
        case (.stream, .checking): "The current channel stream is being resolved."
        case (.stream, .unavailable): "The current channel could not produce an authorized media handoff."
        case (.metadata, .available): "Current program metadata is available."
        case (.metadata, .checking): "Current program metadata is loading."
        case (.metadata, .degraded): "The last program metadata is retained, but its refresh failed."
        case (.metadata, .unavailable): "Current program metadata is unavailable."
        case (.playback, .available): "Native playback is ready."
        case (.playback, .checking): "Native playback is starting."
        case (.playback, .unavailable): "Native playback could not continue."
        case (_, .notChecked): "This stage has not run in the current session."
        case (_, .degraded): "This stage is using retained information after a recoverable failure."
        case (_, .checking): "This stage is in progress."
        case (_, .available): "This stage is available."
        case (_, .unavailable): "This stage is unavailable."
        }
    }
}

struct SupportBundle: Codable, Equatable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let product: String
    let version: String
    let build: String
    let operatingSystem: String
    let architecture: String
    let compatibility: [CompatibilityFinding]
}

struct CompatibilitySnapshot: Equatable {
    let findings: [CompatibilityFinding]

    static func make(
        authentication: AuthenticationPresentationState,
        catalog: ListeningPresentationState,
        playback: LivePlaybackState,
        metadata: MetadataPresentationAvailability
    ) -> Self {
        let authenticationStatus: CompatibilityClassification
        let entitlementStatus: CompatibilityClassification

        switch authentication {
        case .entitled, .restoreCompleted:
            authenticationStatus = .available
            entitlementStatus = .available
        case .verifyingAuthentication:
            authenticationStatus = .checking
            entitlementStatus = .notChecked
        case .verifyingEntitlement:
            authenticationStatus = .available
            entitlementStatus = .checking
        case .authenticatedButNotEntitled, .entitlementAuthorizationRejected:
            authenticationStatus = .available
            entitlementStatus = .unavailable
        case .profileAuthorizationRejected, .credentialNotDurable, .rejected, .challengeRequired,
             .unsupported, .localCredentialInvalid, .localCredentialUnavailable,
             .webCredentialMalformed, .webCredentialAmbiguous, .webSessionResetFailed,
             .cleanupFailed:
            authenticationStatus = .unavailable
            entitlementStatus = .notChecked
        case .localCredentialMissing, .waitingForWebView, .webCredentialMissing, .signedOut,
             .finishingCleanup:
            authenticationStatus = .notChecked
            entitlementStatus = .notChecked
        }

        let catalogStatus: CompatibilityClassification = switch catalog {
        case .idle: .notChecked
        case .loading: .checking
        case .available, .empty: .available
        case .stale: .degraded
        case .failed: .unavailable
        }

        let streamStatus: CompatibilityClassification
        let playbackStatus: CompatibilityClassification
        switch playback {
        case .awaitingLiveContract:
            streamStatus = .checking
            playbackStatus = .notChecked
        case .playing, .paused:
            streamStatus = .available
            playbackStatus = .available
        case .idle, .stopped:
            streamStatus = .notChecked
            playbackStatus = .notChecked
        case let .unavailable(failure):
            switch failure {
            case .authorizationUnavailable, .entitlementUnavailable, .catalogUnavailable,
                 .selectionUnavailable, .resolutionUnavailable, .protectedControl, .unsupported:
                streamStatus = .unavailable
                playbackStatus = .notChecked
            case .networkUnavailable, .bufferingUnavailable, .decoderUnavailable, .recoveryExhausted:
                streamStatus = .available
                playbackStatus = .unavailable
            case .cancelled, .superseded:
                streamStatus = .notChecked
                playbackStatus = .notChecked
            }
        }

        let metadataStatus: CompatibilityClassification = switch metadata {
        case .loading: .checking
        case .current: .available
        case .failed: .degraded
        case .unavailable: .unavailable
        }

        return Self(findings: [
            .init(area: .authentication, classification: authenticationStatus),
            .init(area: .entitlement, classification: entitlementStatus),
            .init(area: .catalog, classification: catalogStatus),
            .init(area: .stream, classification: streamStatus),
            .init(area: .metadata, classification: metadataStatus),
            .init(area: .playback, classification: playbackStatus),
        ])
    }

    static let signedOut = make(
        authentication: .signedOut,
        catalog: .idle,
        playback: .idle,
        metadata: .unavailable
    )
}

enum SupportBundleFactory {
    static func make(snapshot: CompatibilitySnapshot, bundle: Bundle = .main) -> SupportBundle {
        SupportBundle(
            schemaVersion: SupportBundle.schemaVersion,
            product: ProductIdentity.displayName,
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Development",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: architecture,
            compatibility: snapshot.findings
        )
    }

    static func encoded(_ bundle: SupportBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(bundle)
    }

    private static var architecture: String {
#if arch(arm64)
        "arm64"
#elseif arch(x86_64)
        "x86_64"
#else
        "unknown"
#endif
    }
}

@MainActor
struct CompatibilitySupportView: View {
    let controller: ListeningSessionController?
    @State private var exportError: String?

    private var snapshot: CompatibilitySnapshot {
        guard let controller else { return .signedOut }
        return .make(
            authentication: controller.authenticationModel.state,
            catalog: controller.listeningModel.state,
            playback: controller.listeningModel.playbackState,
            metadata: controller.listeningModel.metadataPresentation.availability
        )
    }

    private var supportBundle: SupportBundle {
        SupportBundleFactory.make(snapshot: snapshot)
    }

    private var preview: String {
        guard let data = try? SupportBundleFactory.encoded(supportBundle) else { return "Unable to create preview." }
        return String(decoding: data, as: UTF8.self)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Compatibility & Support")
                    .font(.title2.bold())
                Text("These checks show where the current session stopped. No new SiriusXM requests are made here.")
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                ForEach(snapshot.findings) { finding in
                    GridRow {
                        Label(finding.area.title, systemImage: finding.classification.symbolName)
                            .frame(width: 150, alignment: .leading)
                        Text(finding.classification.title)
                            .fontWeight(.semibold)
                            .frame(width: 100, alignment: .leading)
                        Text(finding.explanation)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            GroupBox("Support bundle preview") {
                ScrollView {
                    Text(preview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 170)
            }

            HStack {
                Text("The export contains only the version fields and classifications shown above.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Export Support Bundle…", action: export)
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 610)
        .alert("Support Bundle Wasn’t Exported", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "Try another location.")
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.title = "Export Canis97 Support Bundle"
        panel.nameFieldStringValue = "Canis97-Support-Bundle.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try SupportBundleFactory.encoded(supportBundle).write(to: url, options: .atomic)
        } catch {
            exportError = "Canis97 could not write the reviewed bundle to that location."
        }
    }
}
