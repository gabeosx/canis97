import SwiftUI
import SiriusXMClient

struct AuthenticationView: View {
    @State private var model: AuthenticationPresentationModel
    @State private var bridge: WebAuthenticationBridge
    @State private var closedLiveObservation = ClosedLiveObservationAdapter()

    init() {
        let composition = AuthenticationComposition()
        _bridge = State(initialValue: composition.bridge)
        _model = State(initialValue: AuthenticationPresentationModel(
            flow: composition.flow
        ))
    }

    var body: some View {
        let copy = model.presentation(for: model.state)

        Group {
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
                            Button("Run closed live compatibility preflight") {
                                let result = closedLiveObservation.begin(entitlement: .entitled)
                                if result == .started {
                                    closedLiveObservation.refuseUnknownCatalogContract()
                                }
                            }
                            .disabled(closedLiveObservation.state != .idle)
                            .accessibilityHint("Stops safely before any live-content request without an exact approved contract.")
                            if closedLiveObservation.state != .idle {
                                Text("Live compatibility preflight stopped safely before any content request.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Live compatibility preflight stopped safely")
                            }
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
