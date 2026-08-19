import SwiftUI
import SiriusXMClient

struct AuthenticationView: View {
    @State private var model: AuthenticationPresentationModel
    @State private var bridge: WebAuthenticationBridge
    @State private var closedLiveObservation: ClosedLiveObservationAdapter
    @State private var closedTuneObservation: ClosedTuneObservationAdapter
    @State private var catalogResult: ClosedCatalogResult?
    @State private var isCatalogObservationRunning = false
    @State private var tuneResult: ClosedTuneResult?
    @State private var isTuneObservationRunning = false

    init() {
        let composition = AuthenticationComposition()
        _bridge = State(initialValue: composition.bridge)
        _model = State(initialValue: AuthenticationPresentationModel(
            flow: composition.flow
        ))
        _closedLiveObservation = State(initialValue: ClosedLiveObservationAdapter(
            credentialLoader: {
                switch composition.keychain.loadStoredCredentialForAuthentication() {
                case let .credential(credential):
                    .available(credential)
                case .missing:
                    .missing
                case .invalidErased, .cleanupFailed, .unavailable:
                    .invalid
                }
            }
        ))
        _closedTuneObservation = State(initialValue: ClosedTuneObservationAdapter(
            credentialLoader: {
                switch composition.keychain.loadStoredCredentialForAuthentication() {
                case let .credential(credential):
                    .available(credential)
                case .missing:
                    .missing
                case .invalidErased, .cleanupFailed, .unavailable:
                    .invalid
                }
            }
        ))
    }

    var body: some View {
        let copy = model.presentation(for: model.state)

        SwiftUI.Group {
            if case .unsupported = model.state {
                VStack(alignment: .leading, spacing: 16) {
                    UnsupportedAuthenticationView(copy: copy)
                    HStack {
                        Button("Retry Sign In") { _ = model.retry() }
                        clearLocalSessionButton
                    }
                }
                .frame(maxWidth: 520, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Label(copy.title, systemImage: copy.iconName)
                        .font(.title2)
                        .accessibilityAddTraits(.isHeader)

                    Text(copy.message)
                        .foregroundStyle(.secondary)

                    if isVerifying {
                        ProgressView()
                            .accessibilityLabel("Authentication in progress")
                    } else if copy.isReady {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Authentication is complete", systemImage: "checkmark.circle")
                                .foregroundStyle(.green)
                            Button("Run one authorized catalog check") {
                                let result = closedLiveObservation.begin(entitlement: .entitled)
                                if result == .started {
                                    isCatalogObservationRunning = true
                                    Task { @MainActor in
                                        catalogResult = await closedLiveObservation.runCatalog()
                                        isCatalogObservationRunning = false
                                    }
                                }
                            }
                            .disabled(isCatalogObservationRunning || closedLiveObservation.state != .idle)
                            .accessibilityHint("Makes only the approved catalog request and stops on any protected or unknown response.")
                            catalogCheckpointResult
                            Button("Run selected SiriusXM Hits 1 tune check") {
                                let result = closedTuneObservation.begin(entitlement: .entitled)
                                if result == .started {
                                    isTuneObservationRunning = true
                                    Task { @MainActor in
                                        tuneResult = await closedTuneObservation.runTune()
                                        isTuneObservationRunning = false
                                    }
                                }
                            }
                            .disabled(isTuneObservationRunning || closedTuneObservation.state != .idle)
                            .accessibilityHint("Makes only the approved selected-channel tune request and never requests a returned media resource.")
                            tuneCheckpointResult
                            Button("Sign Out") { _ = model.signOut() }
                        }
                    } else {
                        if model.state == .waitingForWebView {
                            WebViewAuthenticationContainer(bridge: bridge)
                        }
                        authenticationActions
                    }
                }
                .frame(
                    maxWidth: AuthenticationLayout.maximumContentWidth,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .disabled(model.isAttemptInFlight)
        .padding(AuthenticationLayout.contentPadding)
        .task { @MainActor in
            let attempt = model.restoreStoredCredentialOnLaunch()
            await attempt?.value
        }
    }

    private var isVerifying: Bool {
        switch model.state {
        case .verifyingAuthentication, .verifyingEntitlement:
            true
        default:
            false
        }
    }

    @ViewBuilder
    private var catalogCheckpointResult: some View {
        if isCatalogObservationRunning {
            ProgressView("Checking approved catalog route")
                .accessibilityLabel("Checking approved catalog route")
        } else if let catalogResult {
            switch catalogResult {
            case let .channels(channels):
                VStack(alignment: .leading, spacing: 4) {
                    Text("Catalog check completed. Choose one listed channel to continue.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(channels.prefix(5)) { channel in
                        Text(channelSelectionLabel(for: channel))
                            .font(.caption)
                            .accessibilityLabel(channelSelectionLabel(for: channel))
                    }
                }
            case let .terminal(protection):
                Text("Catalog check stopped safely: \(protection.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Catalog check stopped safely: \(protection.rawValue)")
            case let .classifiedTerminal(protection, failure):
                Text("Catalog check stopped safely: \(failure.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Catalog check stopped safely: \(protection.rawValue), \(failure.rawValue)")
            }
        }
    }

    private func channelSelectionLabel(for channel: ClosedCatalogChannel) -> String {
        if let category = channel.category {
            "\(channel.displayName) (\(channel.id)) — \(category)"
        } else {
            "\(channel.displayName) (\(channel.id))"
        }
    }

    @ViewBuilder
    private var tuneCheckpointResult: some View {
        if isTuneObservationRunning {
            ProgressView("Checking selected channel tune route")
                .accessibilityLabel("Checking selected channel tune route")
        } else if let tuneResult {
            switch tuneResult {
            case .resourceAllowlistDecisionRequired:
                Text("Tune check completed. A returned media resource requires a separate fixed allowlist decision.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Tune check requires a separate media resource allowlist decision")
            case let .terminal(protection):
                Text("Tune check stopped safely: \(protection.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Tune check stopped safely: \(protection.rawValue)")
            case let .classifiedTerminal(protection, failure):
                Text("Tune check stopped safely: \(failure.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Tune check stopped safely: \(protection.rawValue), \(failure.rawValue)")
            case .cancelled:
                Text("Tune check cancelled safely.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .alreadyConsumed:
                Text("Tune check was already consumed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var authenticationActions: some View {
        switch model.state {
        case .waitingForWebView:
            HStack {
                Button("Use This Window’s Session") {
                    _ = model.useLoggedInSession()
                }
                clearLocalSessionButton
            }
        case .authenticatedButNotEntitled,
             .rejected,
             .challengeRequired,
             .cleanupFailed:
            HStack {
                Button("Retry Sign In") { _ = model.retry() }
                clearLocalSessionButton
            }
        case .signedOut:
            HStack {
                Button("Sign In") { _ = model.signIn() }
                clearLocalSessionButton
            }
        case .verifyingAuthentication,
             .verifyingEntitlement,
             .entitled,
             .unsupported:
            EmptyView()
        }
    }

    private var clearLocalSessionButton: some View {
        Button("Clear Local Session") { _ = model.clearLocalSession() }
    }
}

/// Keeps production composition to one Keychain adapter, one WebView bridge, and
/// one combined credential source. Tests can recreate the same graph with fakes.
@MainActor
struct AuthenticationComposition {
    let bridge: WebAuthenticationBridge
    let keychain: KeychainCredentialStore
    let credentialSource: RestorableAuthenticationCredentialSource
    let flow: ComposedAuthenticationPresentationFlow

    init() {
        self.init(bridge: WebAuthenticationBridge(), keychain: KeychainCredentialStore())
    }

    init(
        bridge: WebAuthenticationBridge,
        keychain: KeychainCredentialStore,
        client: (any ClientAuthenticationFlow)? = nil
    ) {
        let credentialSource = RestorableAuthenticationCredentialSource(
            keychain: keychain,
            webViewSource: bridge
        )
        let composedClient = client ?? SiriusXMClient(
            credentialSource: credentialSource,
            credentialStore: keychain,
            residueCleaner: bridge
        )

        self.bridge = bridge
        self.keychain = keychain
        self.credentialSource = credentialSource
        flow = ComposedAuthenticationPresentationFlow(
            bridge: bridge,
            client: composedClient,
            credentialSource: credentialSource
        )
    }
}

/// The fixed native location where Plan 01-06 attaches the nonpersistent WebKit bridge.
private struct WebViewAuthenticationContainer: View {
    let bridge: WebAuthenticationBridge

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Native sign-in")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            WebAuthenticationView(bridge: bridge)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(.rect(cornerRadius: AuthenticationLayout.webViewCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: AuthenticationLayout.webViewCornerRadius)
                        .strokeBorder(.secondary.opacity(0.2), lineWidth: 1)
                }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: AuthenticationLayout.minimumWebViewHeight,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .layoutPriority(1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Native SiriusXM sign-in area")
    }
}

private enum AuthenticationLayout {
    static let contentPadding: CGFloat = 24
    static let maximumContentWidth: CGFloat = 1_200
    static let minimumWebViewHeight: CGFloat = 420
    static let webViewCornerRadius: CGFloat = 8
}
